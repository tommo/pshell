when not defined(nimscript):
  {.error:"nimscript module".}

import os
import strutils
import strformat
import strscans
import json

import ../pdef

putEnv("FROM_PIL_NIMSCRIPT", "1")

#----------------------------------------------------------------
const pilRoot = getEnv "PIL_ROOT"

# #----------------------------------------------------------------
# const PPACKAGE_INFO_FILE = "ppackage.json"
# const PMODULE_INFO_FILE  = "pmodule.json"
# const PROJECT_INFO_FILE  = "pproject.json"

type
  ModInfo = ref object
    root:string
    name:string
    packageName:string
    fullname:string

  ProjInfo = ref object
    root:string
    name:string

proc findProject( fromPath:string ):ProjInfo =
  var path = fromPath
  assert not path.isRootDir
  while not path.isRootDir:
    let infoPath = path / PPROJECT_INFO_FILE
    if fileExists( infoPath ):
      let s = staticRead( infoPath )
      let info = parseJson( s )
      let projName = info["project"].getStr( "nil" )
      return ProjInfo(
        name:projName,
        root:path
      )
    path = path.parentDir
  return nil

proc findParentPModule( fromPath:string ):ModInfo =
  var path = fromPath
  assert not path.isRootDir
  var ppath = path.parentDir
  while not path.isRootDir:
    let infoPath = ppath / PPACKAGE_INFO_FILE
    if fileExists( infoPath ):
      let s = staticRead( infoPath )
      let info = parseJson( s )
      let packageName = info["package"].getStr( "nil" )
      let ( _, tail ) = splitPath( path )
      return ModInfo(
        fullname: tail & "@" & packageName,
        name: tail,
        packageName: packageName,
        root:path
      )
    path = ppath
    ppath = path.parentDir
  return nil

proc taskBuildLib() =
  let m = findParentPModule( getCurrentDir() )
  if m == nil:
    echo "no module found at:", getCurrentDir()
    quit(-1)
  let r = staticExec("pil hasher " & m.root)
  var moduleHash:string
  var k:string
  discard scanf(r, "$*:$w", moduleHash, k)
  if k == "":
    echo "failed to get module hash:", getCurrentDir()
    quit(-1)
  echo r
  const libRoot = "bin"
  when defined(release):
    const binPath = libRoot / "lib_release"
    const argBuildType = "-d:release --debuginfo --debugger:native"
    const cachePath = ".nimcache/release_lib"
  else:
    const binPath = libRoot / "lib_debug"
    const argBuildType = "--debuginfo --debugger:native"
    const cachePath = ".nimcache/debug_lib"

  var needBuild = false
  if k == "changed":
    echo "build"
    needBuild = true
    let entrySrc = m.root / "impl.nim"
    let outputFileName = DynlibFormat % (m.name & "_" & moduleHash)
    let outputPath = m.root / binPath / outputFileName
    exec  &"nim cpp --app:lib {argBuildType} --nimcache:{cachePath} -o:{outputPath} -d:isPModule {entrySrc}"

# #----------------------------------------------------------------
# task build_lib, "build libraries for current pmodule":
#   hint("QuitCalled", false)
#   taskBuildLib()

# #----------------------------------------------------------------
# proc buildApp( rel:static bool, run:static bool ) =
#   hint("QuitCalled", false)
#   let p = findProject( getCurrentDir() )
#   if p == nil:
#     echo "no module found at:", getCurrentDir()
#     quit(-1)

#   switch "path", p.root / "packages" / "game"

#   when rel:
#     const binPath = "bin" / "release"
#     when defined(danger):
#       const argBuildType = "-d:danger" #& " -d:tracyEnabled=1"
#     else:
#       const argBuildType = "-d:release"
#     const cachePath = ".nimcache/release"
#   else:
#     const binPath = "bin" / "debug"
#     const argBuildType = "--debuginfo --debugger:native"
#     const cachePath = ".nimcache/debug"

#   when run:
#     const  argRun = "-r"
#   else:
#     const  argRun = ""

#   let entrySrc = p.root / "bin" / "entry.nim"
#   let outputPath = p.root / binPath / "app"
#   if fileExists(entrySrc):
#     withDir p.root:
#       exec  &"nim cpp --nimcache:{cachePath} {argBuildType} {argRun} -o:{outputPath} -d:combinePModules --d:papp_root:{p.root} {entrySrc}"
#   else:
#     echo "no entry.nim found in", p.root / "bin"

# task build_app, "build app for current pproject":
#   buildApp( defined(release), false )

# task run_app, "build and app for current pproject":
#   buildApp( defined(release), true )
  
# #----------------------------------------------------------------
# task start_test, "test current pmodule":
#   hint("QuitCalled", false)
#   let m = findParentPModule( getCurrentDir() )
#   if m == nil:
#     echo "no module found at:", getCurrentDir()
#     quit(-1)

#   var extra = ""
#   when defined(release):
#     const binPath      = "bin" / "test_release"
#     when defined(danger):
#       const argBuildType = "-d:danger -d:pmoduleTest=1" # --passC:-flto --passL:-flto" #& " -d:tracyEnabled=1"
#     else:
#       const argBuildType = "-d:release -d:pmoduleTest=1" #& -d:tracyEnabled=1"
#     let cachePath    = m.root / ".nimcache" / "release"
#     extra &= " --warning:UnusedImport:off"
#     extra &= " --warning:Effect:off"
#     extra &= " --warning:CastSizes:off"
#   else:
#     const binPath      = "bin" / "test_debug"
#     const argBuildType = "--debuginfo --debugger:native"
#     let cachePath    = m.root / ".nimcache" / "debug"
#     extra &= " --warning:UnusedImport:off"
#     extra &= " --warning:Effect:off"

#   let entrySrc = m.root / "test.nim"
#   # let outputFileName = DynlibFormat % m.name
#   let outputPath = m.root / binPath / "test_" & m.fullname
#   var
#     testname = ""
#   if fileExists( m.root/".workspace" ):
#     let s = staticRead( m.root/".workspace" )
#     let info = parseJson( s )
#     testname = info{"default_test"}.getStr("")
#   var arguments:string = &"\"{testname}\""
#   echo "test argument:", arguments

#   if fileExists(entrySrc):
#     cd m.root
#     echo ">> run test for ", m.fullname
#     exec  &"nim cpp -r {argBuildType} -d:combinePModules --nimcache:{cachePath} {extra} -o:{outputPath} {entrySrc} {arguments}"
#   else:
#     echo "no test.nim found in ", m.fullname
#     quit(-1)



# #----------------------------------------------------------------
# task build_test_web, "test current pmodule":
#   hint("QuitCalled", false)
#   let m = findParentPModule( getCurrentDir() )
#   if m == nil:
#     echo "no module found at:", getCurrentDir()
#     quit(-1)

#   var extra = ""
#   var wasmDefines = ""
#   when defined(release):
#     const binPath      = "bin" / "test_release"
#     const argBuildType = "-d:release" #& " -d:tracyEnabled=1"
#     let cachePath    = m.root / ".nimcache" / "release"
#     extra.add " --warning:UnusedImport:off"
#     extra.add " --warning:Effect:off"
#     extra.add " --warning:CastSizes:off"
#   else:
#     const binPath      = "bin" / "test_debug"
#     const argBuildType = ""
#     # const argBuildType = "--debuginfo --debugger:native"
#     let cachePath    = m.root / ".nimcache" / "debug"


#   let entrySrc = m.root / "test.nim"
#   # let outputFileName = DynlibFormat % m.name
#   let outputPath = m.root / binPath / "test_" & m.fullname
#   let assetPath = m.root / "assets"
#   if dirExists( assetPath ):
#     wasmDefines.add &" -d:wasmAssets=\"{assetPath}\""
#   if fileExists(entrySrc):
#     cd m.root
#     echo ">> run test for ", m.fullname
#     exec  &"nim cpp {argBuildType} -d:PIL_WASM -d:combinePModules {wasmDefines} --nimcache:{cachePath} {extra} {entrySrc}"
#   else:
#     echo "no test.nim found in ", m.fullname
#     quit(-1)

# #----------------------------------------------------------------
# task start_test_lldb, "test current pmodule":
#   hint("QuitCalled", false)
#   let m = findParentPModule( getCurrentDir() )
#   if m == nil:
#     echo "no module found at:", getCurrentDir()
#     quit(-1)

#   when defined(release):
#     const binPath      = "bin" / "test_release"
#     const argBuildType = "-d:release"
#     let cachePath    = m.root / ".nimcache" / "release"
#   else:
#     const binPath      = "bin" / "test_debug"
#     const argBuildType = "--debuginfo --debugger:native"
#     let cachePath    = m.root / ".nimcache" / "debug"

#   let entrySrc = m.root / "test.nim"
#   # let outputFileName = DynlibFormat % m.name
#   let outputPath = m.root / binPath / "test"

#   if fileExists(entrySrc):
#     cd m.root
#     echo ">> run test for ", m.fullname
#     exec  &"nim cpp {argBuildType} -d:combinePModules --nimcache:{cachePath} -o:{outputPath} {entrySrc}"
#     exec &"lldb -o 'run' {outputPath}"
#   else:
#     echo "no test.nim found in ", m.fullname
#     quit(-1)
  
# #----------------------------------------------------------------
# task pstub, "start current project with debugger attached":
#   when defined(release):
#     const binPath = pilRoot / "bin" / "release"
#     const cachePath = pilRoot / ".nimcache"/"release"
#     const argBuildType = "-d:release"
#   else:
#     const binPath = pilRoot / "bin" / "debug"
#     const cachePath = pilRoot / ".nimcache"/"debug"
#     const argBuildType = "--debuginfo --debugger:native"
  
#   # const binFilePath = binPath / "pstub"
#   # when defined(pstub_nobuild):
#   #   if fileExists( binFilePath ):
#   #     exec &"{binFilePath}"
#   #     return
#   const stubBin = binPath / "pstub"
#   let stubSrc = pilRoot/"lib"/"pstub.nim"
#   let workingDir = getCurrentDir()

#   var params:seq[string]
#   var recording = false

#   withDir pilRoot:
#     # if not fileExists(stubBin):
#     exec &"nim cpp {argBuildType} --nimcache:{cachePath} -o:{stubBin} {stubSrc}"
#     let paramStr = params.join(" ")
#     exec &"{stubBin} --working-dir:{workingDir} {paramStr}"
#   # exec &"lldb -o 'run' {stubBin}"

# #----------------------------------------------------------------
# task ptool, "launch tool provided by packages":
#   discard

# task pload_dbg, "launch tool with lldb":
#   const toolPath = pilRoot / "bin" / "tools"
#   const loadBin = toolPath / "load"
#   exec &"lldb -o 'run' {loadBin}"


# task build_cli, "build pil cli":
#   const cachePath = pilRoot / ".nimcache"/"release"
#   const argBuildType = "-d:release"
#   const binPath = pilRoot / "bin"
#   const pilBin = binPath / "pil"
#   let pilSrc = pilRoot/"lib"/"pcli.nim"
#   withDir pilRoot:
#     exec &"nim cpp {argBuildType} --nimcache:{cachePath} -o:{pilBin} {pilSrc}"

# # #================================================================
# # task start_lldb, "start current project with debugger attached":
# #   let cliSrc = root/"tools"/"cli"/"cli.nim"
# #   let cliBin = root/"bin"/"cli"
# #   exec &"nim cpp --debuginfo --debugger:native {cliSrc}"
# #   exec &"lldb -o 'run' {cliBin}"