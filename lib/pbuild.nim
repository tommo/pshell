import std/[ os, strutils, strformat, strscans, streams, hashes ]
import std/[ osproc ]
import utils/cliutils

import penv
import pmodenv
import phasher
import plogging

type
  BuildParams = object
    outputRoot:string
    outputPath:string
    outputName:string
    cachePath:string
    buildType:string
    entryFile:string
    args:seq[string]

proc default(v:string, default:string):string =
  if v == "": 
    default
  else:
    v

proc exec(params:BuildParams):bool =
  var cmd = "nim"
  cmd.add " cpp"
  cmd.add " --app:" & default(params.buildType, "console")
  cmd.add " --nimcache:" & default(params.cachePath, ".nimcache")
  if params.outputPath != "":
    cmd.add " -o:" & params.outputPath
  else:
    var outputPath:string
    if params.outputName != "":
      outputPath = params.outputRoot / params.outputName
      cmd.add " -o:" & outputPath
    elif params.outputRoot != "":
      outputPath = params.outputRoot
      cmd.add " -o:" & outputPath

  for arg in params.args:
    cmd.add " "
    cmd.add arg

  cmd.add " "
  cmd.add params.entryFile
  echo "cmdline:", cmd
  let (output, exitCode) = execCmdEx( cmd )
  if exitCode != 0:
    stderr.writeLine output
    false
  else:
    stdout.writeLine output
    true

#----------------------------------------------------------------
proc buildTest(source_dir:string, rebuild:bool, release:bool) = 
  let fromPath = if source_dir == "" or source_dir == "nil":
      getCurrentDir()
    else:
      source_dir

  debugLog ">> building test from: ", fromPath
  let (moduleName, moduleSrcPath) = findPModule( fromPath )
  if moduleName == "" or moduleSrcPath == "":
    errorLog "no pmodule found"
    quit(1)
  
  let testSrcFile = moduleSrcPath/"test.nim"
  if not testSrcFile.fileExists:
    errorLog "test.nim not found"
    quit(1)

  let packagePath = moduleSrcPath.parentDir()
  let binRoot = moduleSrcPath / "bin"
  let testFile = binRoot / "test_entry.nim"
  createDir(binRoot)
  if not dirExists(binRoot):
    errorLog "failed to create output dir"
    quit(1)

  var entryChanged = false
  block:
    proc addLine(s:var string, l:string) =
      s.add l
      s.add "\n"
    var entryCode:string
    entryCode.addLine "import os"
    entryCode.addLine "template currentSourceDir():string = instantiationInfo(-1, true).filename.parentDir()"
    entryCode.addLine "const moduleDir = currentSourceDir.parentDir() "
    entryCode.addLine "import pmodules"
    entryCode.addLine "include ../test"
    entryCode.addLine "const PMODULE_REVISION {.intdefine.} = 0"
    entryCode.addLine "genPModuleInfoProc(PMODULE_REVISION)"
    var code0:string
    if fileExists(testFile):
      code0 = readFile(testFile)
    if code0.hash != entryCode.hash: #nochange
      writeFile(testFile, entryCode)
      entryChanged = true

  var params:BuildParams
  params.entryFile = testFile
  let moduleTestName = moduleName & ".test"
  var m1 = moduleTestName
  let dllName = m1.libName
  params.outputName = dllName
  params.buildType = "lib"
  # params.buildType = "console"
  if release:
    params.outputRoot = binRoot / "test_release"
    params.cachePath = moduleSrcPath / ".nimcache/test_release"
    params.args.add "-d:release"
    params.args.add "--opt:size"
    params.args.add "--debuginfo"
    params.args.add "--debugger:native"
  else:
    params.outputRoot = binRoot / "test_debug"
    params.cachePath = moduleSrcPath / ".nimcache/test_debug"
    params.args.add "--debuginfo"
    params.args.add "--debugger:native"

  params.args.add &"-p:\"{packagePath}\""
  params.args.add &"-d:PMODULE_CURRENT=\"{moduleTestName}\""
  params.args.add "--exceptions:cpp"
  # params.args.add "-d:useMalloc"
  params.args.add "-u:useMalloc"
  params.args.add "-d:isPHost"
  params.args.add "-d:isPModuleTest"

  if params.exec():
    echo "OK"
    quit(0)
  else:
    echo "Failed"
    quit(1)

#----------------------------------------------------------------
proc buildLib(source_dir:string, rebuild:bool, release:bool) = 
  let fromPath = if source_dir == "" or source_dir == "nil":
      getCurrentDir()
    else:
      source_dir

  debugLog ">> building library from: ", fromPath
  let (moduleName, moduleSrcPath) = findPModule( fromPath )
  if moduleName == "" or moduleSrcPath == "":
    errorLog "no pmodule found"
    quit(1)

  
  let packagePath = moduleSrcPath.parentDir()
  let binRoot = moduleSrcPath / "bin"
  let entryFile = binRoot / "lib_entry.nim"
  createDir(binRoot)
  if not dirExists(binRoot):
    errorLog "failed to create output dir"
    quit(1)

  var needBuild = false
  block:
    proc addLine(s:var string, l:string) =
      s.add l
      s.add "\n"
    var entryCode:string
    entryCode.addLine "import os"
    entryCode.addLine "template currentSourceDir():string = instantiationInfo(-1, true).filename.parentDir()"
    entryCode.addLine "const moduleDir = currentSourceDir.parentDir() "
    entryCode.addLine "when fileExists(moduleDir/\"api.nim\"):"
    entryCode.addLine "  import ../api"
    entryCode.addLine "when fileExists(moduleDir/\"impl.nim\"):"
    entryCode.addLine "  import ../impl"
    entryCode.addLine "import pmodules"
    entryCode.addLine "const PMODULE_REVISION {.intdefine.} = 0"
    entryCode.addLine "genPModuleInfoProc(PMODULE_REVISION)"
    var code0:string
    if fileExists(entryFile):
      code0 = readFile(entryFile)
    if code0.hash != entryCode.hash: #nochange
      writeFile(entryFile, entryCode)
      needBuild = true

  #hash modulefile
  let mhash = hashPModule(moduleSrcPath).hashstr

  var params:BuildParams
  params.entryFile = entryFile
  var m1 = moduleName #nim BUG
  let dllName = m1.libName
  params.outputName = dllName
  params.buildType = "lib"
  if release:
    params.outputRoot = binRoot / "lib_release"
    params.cachePath = moduleSrcPath / ".nimcache/lib_release"
    params.args.add "-d:release"
    params.args.add "--opt:speed"
    # params.args.add "--debuginfo"
    # params.args.add "--debugger:native"
  else:
    params.outputRoot = binRoot / "lib_debug"
    params.cachePath = moduleSrcPath / ".nimcache/lib_debug"
    # params.args.add "--opt:size"
    params.args.add "--debuginfo"
    params.args.add "--debugger:native"

  params.args.add &"-p:\"{packagePath}\""
  params.args.add &"-d:PMODULE_CURRENT=\"{moduleName}\""
  params.args.add "--exceptions:cpp"
  params.args.add "-u:useMalloc"
  params.args.add "-d:useNimRtl"
  params.args.add "-d:isPModule"

  let libHashFile = params.outputRoot / (dllName & ".hash")
  let dllFile = params.outputRoot / dllName
  var hash0:string
  if dllFile.fileExists() and libHashFile.fileExists():
    hash0 = readFile(libHashFile)
  if hash0 != mhash or rebuild: #need build
    noticeLog &"building: {moduleName}"
    if params.exec():
      writeFile(libHashFile, mhash)
      echo "OK"
      quit(0)
    else:
      echo "Failed"
      quit(1)
  else:
    echo "No change"
    quit(0)

#----------------------------------------------------------------
proc buildApp() =
  echo ">> building application"


#================================================================
let doc = """
Pil build tool.

  Usage:
    pbuild lib [--release] [--rebuild] [<source_dir>]
    pbuild test [--run] [--release] [--rebuild] [<source_dir>]
    pbuild (-h | --help)

  Options:
    -h --help     Show this screen.
"""
when isMainModule:
  prepareModuleEnv()
  let args = docopt(doc)
  if args.dispatchProc(buildLib, "lib"): discard
  elif args.dispatchProc(buildTest, "test"): discard
  else:
    echo doc