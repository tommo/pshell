when not defined(emscripten):
  {.error:"html5 target only".}

{.emit:"""
#include <emscripten.h>
""".}

type em_callback_func* = proc() {.cdecl.}

proc emscripten_set_main_loop*(f: em_callback_func, fps, simulate_infinite_loop: cint) {.importc.}
proc emscripten_cancel_main_loop*() {.importc.}

template mainLoop*(statement, actions: untyped): untyped =
  proc emscLoop {.cdecl.} =
    if not statement:
      emscripten_cancel_main_loop()
    else:
      actions

  emscripten_set_main_loop(emscLoop, 0 ,1)

var configInitialised = false
proc initConfigDone*() {.exportc, cdecl, used.} =
  configInitialised = true
  debugEcho "initConfigDone"

proc initConfig() =
  debugEcho "initConfig"
  configInitialised = false
  {.emit:"""
  EM_ASM(
     //create your directory where we keep our persistent data
     FS.mkdir('/IDBFS'); 

     //mount persistent directory as IDBFS
     FS.mount(IDBFS,{},'/IDBFS');

     Module.print("start file sync..");
     //flag to check when data are synchronized
     Module.syncdone = 0;

     //populate persistent_data directory with existing persistent source data 
    //stored with Indexed Db
    //first parameter = "true" mean synchronize from Indexed Db to 
    //Emscripten file system,
    // "false" mean synchronize from Emscripten file system to Indexed Db
    //second parameter = function called when data are synchronized
    FS.syncfs(true, function(err) {
                     Module.print("syncfs done");
                     Module.print(err);
                     assert(!err);
                     ccall("initConfigDone", "v");
                     Module.print("end file sync..");
                     Module.syncdone = 1;
    });
  );
  """.}

proc syncIDBFS() =
  {.emit:"""
  EM_ASM(
    Module.syncdone = 0;
    FS.syncfs(false, function(err) {
                     assert(!err);
                     Module.print("end file sync..");
                     Module.syncdone = 1;
    });
  );
  """.}


#----------------------------------------------------------------
type WasmMainLoop* = proc( iteration:int ):bool {.nimcall.}

var
  mainLoopBody:WasmMainLoop = nil
  iteration = 0.int
  running = false

proc mainLoopEntry() {.cdecl.} =
  if running:
    if mainLoopBody != nil:
      if not mainLoopBody( iteration ):
        #TODO:halt message?
        echo "main loop stopped!"
        running = false
        discard
    iteration.inc

#----------------------------------------------------------------
const
  simulateInfiniteLoop = 1
  fps = 0

proc startWasmMainLoop*( loopBody:WasmMainLoop) =
  echo "start main loop"
  assert loopBody != nil
  mainLoopBody = loopBody
  running = true
  emscripten_set_main_loop(mainLoopEntry, fps, simulateInfiniteLoop)
