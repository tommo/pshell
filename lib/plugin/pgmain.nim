import std/[ dynlib, tables, strformat, sets, algorithm ]
import 
  pgcommon, pgapiImpl

export pgcommon

import plogging

var moduleMgrObject:PModuleMgrObject
var moduleMgr* = moduleMgrObject.addr
var moduleReady:bool

type
  PluginLoadResultKind*{.pure.}= enum
    resultCheckDep,
    resultLoaded,
    resultNoDependency,
    resultNoFile,
    resultNoProc

  PluginLoadResult* = object
    case kind*:PluginLoadResultKind
    of resultNoDependency, resultCheckDep:
      deps*:seq[string]
    else:
      nil

#----------------------------------------------------------------
proc registerModule( info:PModuleInfo ):PModule =
  let name = info.name
  if moduleMgr.modules.hasKey( name ): #reload
    debugLog "reloading module:", name
    #TODO:reload
    result = moduleMgr.modules[ name ].addr
    result.name = name
    result.revision = info.revision
    result.targetRevision = info.revision

  else:
    debugLog "register module:", name
    moduleMgr.modules[ name ] = PModuleObject()
    result = moduleMgr.modules[ name ].addr
    result.name = name
    result.targetRevision = -1
    result.revision = info.revision
    result.apiTable = new( PModuleAPITable )

#----------------------------------------------------------------
proc findModule( modName:string ):PModule =
  if moduleMgr.modules.contains( modName ):
    moduleMgr.modules[modName].addr
  else:
    nil

proc checkModuleReady( modName:string ):bool =
  let m = findModule( modName )
  if m == nil: 
    debugLog "module not found:", modName
    return false
  if m.revision >= m.targetRevision:
    return true
  else:
    debugLog "module not ready:", modName, "@", $m.revision, " < ", $m.targetRevision
    return false

proc findModuleByLib( libPath:string ):PModule =
  for name, m in moduleMgr.modules.mpairs:
    if m.path == libPath:
      return m.addr
  return nil

#----------------------------------------------------------------
const mainName = "main"
proc loadMainModule() =
  noticeLog "----------------------------------------------------------------"
  noticeLog "> loading main module"
  var info:PModuleInfo
  info.name = "main"
  let targetModule = registerModule(info)
  # targetModule.eventHandler = pmoduleEventHandler
  targetModule.lib = nil
  targetModule.path = ""
  targetModule.main = true
  discard pmoduleLoader( moduleMgr, targetModule, false )
  moduleMgr.moduleStack.incl("main")

proc setModuleTargetRevision*( formalDllPath:string, revision:int ) =
  var module:PModule = findModuleByLib( formalDllPath )
  if module != nil:
    module.targetRevision = revision
    
#----------------------------------------------------------------
var pendingDlls:Table[string, LibHandle]

proc loadModule*( formalDllPath:string, dllPath:string, checkDep:bool, noreload:bool = true ):PluginLoadResult =
  var lib:LibHandle = pendingDlls.getOrDefault( dllPath, nil )
  if lib.isNil:
    if not checkDep:
      debugLog "> loading module:", dllPath , " as ", formalDllPath
    lib = loadLib( dllPath )
    pendingDlls[dllPath] = lib
  else:
    if not checkDep:
      debugLog "> retrying module:", dllPath

  if lib.isNil:
    errorLog "> invalid module:", dllPath
    
  else:
    let infoProc         = cast[proc(info:var PModuleInfo) {.cdecl.}](lib.symAddr("pmoduleGetModuleInfo"))
    let loaderProc       = cast[proc(mgr:PModuleMgr, m:PModule, reloading:bool) {.cdecl.}](lib.symAddr("pmoduleLoader"))
    let eventHandlerProc = cast[proc(mgr:PModuleMgr, m:PModule, event:PModuleEvent ) {.cdecl.}](lib.symAddr("pmoduleEventHandler"))
    
    var module:PModule = findModuleByLib( formalDllPath )
        
    if infoProc.isNil or loaderProc.isNil:
      warnLog "no module proc found"
      unloadLib lib
      return PluginLoadResult( kind:resultNoProc )

    else:
      var info:PModuleInfo
      infoProc( info )
      var reloading:bool
      var targetModule:PModule
      var oldLib:LibHandle

      #check deps
      if checkDep:
        return PluginLoadResult( kind:resultCheckDep, deps:info.deps )

      var lackingDeps:seq[string]
      for dep in info.deps:
        if not checkModuleReady( dep ):
          lackingDeps.add( dep )

      if lackingDeps.len > 0:
        return PluginLoadResult( kind:resultNoDependency, deps:lackingDeps )

      if module.isNil:
        reloading = false
        targetModule = registerModule( info )

      else:
        if noreload:
          return PluginLoadResult( kind:resultLoaded )
        reloading = true
        targetModule = module
        module.revision = info.revision
        oldLib = module.lib
        
      targetModule.eventHandler = eventHandlerProc
      targetModule.lib = lib
      targetModule.path = formalDllPath
      targetModule.main = false

      pendingDlls.del( dllPath )
      loaderProc( moduleMgr, targetModule, reloading )
    
      if oldLib != nil:
        debugLog "unload old lib:", info.name
        let unloaderProc = cast[proc(mgr:PModuleMgr, m:PModule, reloading:bool) {.cdecl.}](oldLib.symAddr("pmoduleUnloader"))
        if not unloaderProc.isNil:
          unloaderProc( moduleMgr, targetModule, reloading )
        unloadLib( oldLib )
        # debugLog "unloaded!"
      discard moduleMgr.moduleStack.missingOrExcl( targetModule.name )
      moduleMgr.moduleStack.incl( targetModule.name )

      debugLog &"module loaded: {info.name} @ {$info.revision}"
      return PluginLoadResult( kind:resultLoaded )


#----------------------------------------------------------------
proc unloadAllModules*() =
  var libHandles:seq[ LibHandle ]
  var list:seq[string]

  for mname in moduleMgr.moduleStack:
    list.add( mname )
    
  for mname in reversed(list):
    var m = addr moduleMgr.modules[mname]
    if not m.main:
      for v1 in moduleMgr.modules.mvalues:
        let m1 = v1.addr
        if m == m1: continue
        if m1.main: continue
        if m1.eventHandler != nil:
          m1.eventHandler( moduleMgr, m1, moduleUnloadOther )

      let unloaderProc = cast[proc(mgr:PModuleMgr, m:PModule, reloading:bool) {.cdecl.}](m.lib.symAddr("pmoduleUnloader"))
      if not unloaderProc.isNil:
        unloaderProc( moduleMgr, m, false )
      libHandles.add( m.lib )
    else:
      pmoduleUnloader( moduleMgr, m, false )

  moduleMgr.modules.clear()

  for handle in libHandles:
    unloadLib( handle )


# # #----------------------------------------------------------------
# proc tryReloadModules() =
#   let dllPath = gMonToMain.recv()
#   let ext = dllPath.splitFile().ext
#   let replacing = ext.startsWith( ".rev" )
#   let formalDllPath = if replacing:
#       dllPath[0 .. ^( ext.len + 1 )]
#     else:
#       dllPath

#   discard loadModule( dllPath, formalDllPath )

#   if replacing:
#     let pboName = dllPath & ".dSYM"
#     let formalPboName = formalDllPath & ".dSYM"
#     if fileExists( formalDllPath ):
#       discard tryRemoveFile( formalDllPath )
#     # if fileExists( formalPboName ):
#     #   discard tryRemoveFile( formalPboName )
#     # moveFile( dllPath, formalDllPath )
#     copyFile( dllPath, formalDllPath )
#     # if fileExists( pboName ):
#     #   moveFile( pboName, formalPboName )


#----------------------------------------------------------------
proc initModuleMgr*() =
  once:
    #clean revisions
    moduleMgr.apiTable = new(PModuleAPITable)
    moduleMgr.state = stateRunning
    moduleReady = false
    loadMainModule()
    debugLog "init module manager"

#----------------------------------------------------------------
proc initModules*( dllDir:string, paths: seq[string] ) =
  initModuleMgr()

#----------------------------------------------------------------
proc broadcastModuleEvent*( ev:PModuleEvent ) =
  for m in moduleMgr.modules.mvalues:
    let p = m.addr
    if m.main:
      discard pmoduleEventHandler( moduleMgr, p, ev )
    else:
      # if ev == moduleStop:
      #   for m1 in moduleMgr.modules.mvalues:
      #     let p1 = m1.addr
      #     if p == p1: continue
      #     p1.eventHandler( moduleMgr, p1, moduleStopOther )
      p.eventHandler( moduleMgr, p, ev )


#----------------------------------------------------------------
proc startModules*() =
  debugLog "pre start modules:"
  broadcastModuleEvent( modulePreStart )
  debugLog "start modules:"
  broadcastModuleEvent( moduleStart )
  debugLog "post start modules:"
  broadcastModuleEvent( modulePostStart )

#----------------------------------------------------------------
proc pollModules*() =
  # tryReloadModules()
  if moduleMgr.state notin { stateStopped, stateStopping }:
    broadcastModuleEvent( modulePreUpdate )

  var stopping = false
  if moduleMgr.state notin { stateStopped, stateStopping }:
    var hasTasks = false  
    broadcastModuleEvent( moduleUpdate )
    for m in moduleMgr.modules.values:
      if m.hasTask():
        hasTasks = true

    if not hasTasks:
      stopping = true

  if moduleMgr.state notin { stateStopped, stateStopping }:
    broadcastModuleEvent( modulePostUpdate )

  if stopping:
    broadcastModuleEvent( moduleStop )
    moduleMgr.tryStop()

      
#----------------------------------------------------------------
proc defaultMainLoop( iteration:int ):bool {.nimcall.} =
  if not moduleMgr.running: return false
  pollModules()
  cpuRelax()
  return true

proc prepareMainLoop() =
  moduleMgr.apiTable = new(PModuleAPITable)
  moduleMgr.state = stateRunning
  moduleReady = false
  loadMainModule()
  startModules()

when defined(emscripten):
  import pgwasm
  export pgwasm
  
  proc testMainModule*() =  
    prepareMainLoop()
    startWasmMainLoop( defaultMainLoop )
    #how to unload resources?

else:
  #----------------------------------------------------------------
  proc testMainModule*() =  
    prepareMainLoop()
    var iteration:int = 0
    while true:
      if not defaultMainLoop(iteration): break
      iteration.inc
    noticeLog "> unloading modules:"
    unloadAllModules()
    noticeLog "> bye!"

