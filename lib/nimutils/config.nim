when not defined(nimscript):
  {.error:"nimscript module".}

import os
import parseini
import strformat

const pilRoot = currentSourcePath.parentDir.parentDir.parentDir

putEnv "PIL_ROOT", pilRoot

const PPACKAGE_INFO_FILE = "ppackage.json"
const PIL_CFG_FILE = "pil.cfg"

#----------------------------------------------------------------
proc scanSinglePackage( path:string ) =
  if fileExists( path / PPACKAGE_INFO_FILE ):
      # echo "search path:", path
      switch "path", path

proc scanPackages( path:string ) =
  for packPath in listDirs( path ):
    scanSinglePackage( packPath)

proc readCfg() =
  let path = getHomeDir() / PIL_CFG_FILE
  if fileExists( path ):
    let data = parseIni(staticRead(path))
    for k, v in data.getSection("packages"):
      scanSinglePackage(v)
  
proc setupPackagePath*() =
  scanPackages pilRoot/"packages" 
  if not defined(PIL_NO_EXPERIMENT):
    scanPackages pilRoot/"experiments"
  readCfg()

proc setupAppPackage*( proot:string ) =
  let p = proot / "packages" 
  echo p
  scanPackages p

#----------------------------------------------------------------
proc setupDepPath*() =
  switch "path", pilRoot/ "deps/taskpools"
  switch "path", pilRoot/ "deps/vmath/src"
  switch "path", pilRoot/ "deps/pixie/src"
  switch "path", pilRoot/ "deps/chroma/src"
  switch "path", pilRoot/ "deps/skyhash"
  switch "path", pilRoot/ "deps/jsony/src"
  switch "path", pilRoot/ "deps/flatty/src"
  switch "path", pilRoot/ "deps/msgpack4nim"
  switch "path", pilRoot / "thirdparty"
  switch "path", pilRoot / "lib"


#MODULE SEARCH PATH
setupPackagePath()
setupDepPath()

const papp_root{.strdefine.} = ""
when defined(papp_root):
  setupAppPackage(papp_root)

when not existsEnv("FROM_PIL_NIMSCRIPT"):
  import modutils
  import testutils

#================================================================
when defined(release):
  --outdir:"_build/release"
  --nimcache:"_build/release/.nimcache"
else:
  --outdir:"_build/debug"
  --nimcache:"_build/debug/.nimcache"

hint "XDeclaredButNotUsed", false
hint "CC", false
hint "Link", false
hint "Conf", false
hint "Exec", false

#COMMON FLAGS
--styleChecks:off

--mm:arc
# --mm:atomicArc
# --d:useNimRtl
--threads:on
--cc:clang
--experimental:notnil
# --opt:size

when defined(PIL_WASM):
  --cc:clang
  # put "clang.exe", "emcc"
  # put "clang++.exe", "emcc"
  switch "clang.exe", "emcc"
  switch "clang.cpp.exe", "emcc"
  switch "clang.linkerexe", "emcc"
  switch "clang.cpp.linkerexe", "emcc"
  switch "clang.options.linker", ""
  switch "cpu","wasm32"
  switch "os","linux"
  # out = "public/index.html"
  # 
  # --d:useRealtimeGC
  --exceptions:cpp
  # --exceptions:goto
  --d:noSignalHandler # Emscripten doesn't support signal handlers.
  --d:emscripten
  --d:nimStdSetjmp
  --listCmd
  --dynlibOverride:SDL2
  # switch "passL", "-s ALLOW_MEMORY_GROWTH=1 -O3 -s WASM=1 -Lemscripten -s USE_SDL=2"
  #-o {outFile}
  const
    wasmEntry{.strdefine.}      = "index.html"
    wasmShellFile{.strdefine.}  = "minimal.html"
    wasmOutput{.strdefine.}     = "output"
    wasmAssets{.strdefine.}     = ""

  var extraFlags = ""
  extraFlags.add " -s ASSERTIONS=1" 
  extraFlags.add " -s FORCE_FILESYSTEM=1"
  
  extraFlags.add " -s USE_SDL=2"
  extraFlags.add " -s OFFSCREENCANVAS_SUPPORT=1" 
  extraFlags.add " -sFULL_ES2=1" 
  extraFlags.add " -sFULL_ES3=1" 
  
  extraFlags.add " -s USE_PTHREADS=1"
  extraFlags.add " -s PTHREAD_POOL_SIZE=8"
  extraFlags.add " -s PTHREAD_POOL_SIZE_STRICT=2"
  extraFlags.add " -s MIN_WEBGL_VERSION=2"

  # extraFlags.add " -s PROXY_TO_PTHREAD=1"

  extraFlags.add " -s INITIAL_MEMORY=200MB"
  extraFlags.add " -s ALLOW_MEMORY_GROWTH"

  var shellArgs = " --shell-file " & wasmShellFile
  var preloadArgs:string
  if wasmAssets == "":
    preloadArgs = ""
  else:
    preloadArgs= &" --preload-file {wasmAssets}@/"

  mkDir wasmOutput
  switch "passC", "-s WASM=1 -Iemscripten -s USE_SDL=2 -O2 -g1"
  switch "passL", &"-o {wasmOutput}/{wasmEntry}  -lidbfs.js {extraFlags} -s EXPORTED_FUNCTIONS=[\"_main\",\"_initConfigDone\"] -s EXPORTED_RUNTIME_METHODS=[\"ccall\",\"cwrap\"] -g1 -O2 {preloadArgs}"

else:
  when defined(macosx):
    --d:SDL_VIDEO_DRIVER_COCOA
  --passL:"-L/Volumes/prj/dev/shared"
  # --exceptions:quirky
  # --exceptions:cpp
  --debugger:native
  --stackTrace
  --lineTrace
  --d:useMalloc 
  # --d:useNimRtl
  # --d:nimAllocPagesViaMalloc


