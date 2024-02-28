import std/[ os, sets, strformat, strutils, tables, times, algorithm, sequtils, strscans ]
import std/[ json, streams ]
import std/[ osproc ]
import std/[ monotimes ]

import plugin/pgmain
import plogging
import penv
import phasher
import pmodenv

import utils/[cliutils, pathutils]

const PilPath = currentSourceDir/".."/"bin"/"pil"

type 
  RunSettings = object
    root:string
    release:bool
    nobuild:bool
    rebuild:bool
    test:bool

var moduleQueue:seq[PModuleConfig]
var sortedQueue:seq[PModuleConfig]
var visited:HashSet[string]
#----------------------------------------------------------------
proc libName*(moduleName:string):string = 
  #TODO:crash in rtl Mode
  # DynlibFormat % moduleName
  DynlibFormat % [moduleName]
  # &"lib{moduleName}.dylib"

proc testLibRoot(root:string, release = false):string =
  if release:
    root/"bin"/"test_release"
  else:
    root/"bin"/"test_debug"

proc libRoot(root:string, release = false):string =
  if release:
    root/"bin"/"lib_release"
  else:
    root/"bin"/"lib_debug"


#----------------------------------------------------------------
proc sortModuleQueue() = 
  var visited:HashSet[string]
  proc visit(m:PModuleConfig) =
    if not visited.contains(m.name):
      visited.incl m.name
      var deps:seq[PModuleConfig]
      for depName in m.depModules:
        let dep = findModuleConfig(depName)
        deps.add dep 
      #sort and visit
      deps.sort do (a,b:PModuleConfig) -> int:
        cmp(a.priority, b.priority)
      for dep in deps:
        assert dep != nil
        visit(dep)
      sortedQueue.add m

  moduleQueue.sort do (a,b:PModuleConfig) -> int:
    cmp(a.priority, b.priority)
  for m in moduleQueue:
    visit(m)

#----------------------------------------------------------------
proc preloadDeps(entryModule:PModuleConfig, depPath:string, settings:RunSettings)

proc preloadPModule(rootPath:string, settings:RunSettings) =
  let m = findPModule( rootPath )
  let moduleName = m.name
  let entryModule = findModuleConfig(m.name)
  moduleQueue.insert(entryModule, 0)

  if visited.contains(rootPath):
    return
  visited.incl rootPath

  if not settings.nobuild:
    var buildCmd = PilPath & " build lib"
    if settings.release:
      buildCmd.add " --release"
    if settings.rebuild:
      buildCmd.add " --rebuild"
    buildCmd.add " "
    buildCmd.add rootPath
    infoLog buildCmd
    let (output, code) = execCmdEx( buildCmd )
    if code != 0:
      echo &"Failed to build module: {moduleName}"
      echo output
      quit(-1)

  if entryModule == nil:
    echo "TODO: non registered module: ", m.name, "  @ ", rootPath
    quit(-1)

  let dllPath = m.path.libRoot(settings.release) / m.name.libName
  let depPath = m.path/"bin"/"lib_deps"
  entryModule.dllPath = dllPath

  if depPath.fileExists():
    entryModule.preloadDeps(depPath, settings)
    
proc preloadPModuleTest(rootPath:string, settings:RunSettings) =
  let m = findPModule( rootPath )
  let moduleName = m.name
  let testName = moduleName & ".test"

  let entryModule = affirmTestModuleConfig(m.name)
  moduleQueue.insert(entryModule, 0)
  
  # let srcModule = findModuleConfig(m.name)
  # moduleQueue.insert(srcModule, 0)

  if not settings.nobuild:
    var buildCmd = PilPath & " build test"
    if settings.release:
      buildCmd.add " --release"
    if settings.rebuild:
      buildCmd.add " --rebuild"
    buildCmd.add " "
    buildCmd.add rootPath
    infoLog buildCmd
    let (output, code) = execCmdEx( buildCmd )
    if code != 0:
      echo &"Failed to build test: {moduleName}"
      echo "cmd: ", buildCmd
      echo output
      quit(-1)
  
  let dllPath = m.path.testLibRoot(settings.release) / testName.libName
  let depPath = m.path/"bin"/"test_deps"
  entryModule.dllPath = dllPath

  if depPath.fileExists():
    entryModule.preloadDeps(depPath, settings)

proc preloadDeps(entryModule:PModuleConfig, depPath:string, settings:RunSettings) =
  let deps = readFile(depPath).split("\n")
  for depName in deps:
    if depName == "": continue
    let mconf = findModuleConfig(depName)
    entryModule.depModules.incl depName
    if mconf == nil:
      echo "DEP not found:", depName
      quit(-1)
    else:
      preloadPModule(mconf.path, settings)

proc mainloop(settings:RunSettings) =
  debugLog "PLoad main loop:"
  startModules()
  while moduleMgr.running:
    # if moduleMgr.flags.contains( mmfNeedUpdate ):
    #   moduleMgr.flags.excl mmfNeedUpdate
    #   discard updateModules( true )
    pollModules()
    cpuRelax()
    # sleep(1)
  unloadAllModules()


#----------------------------------------------------------------
proc loadPModuleTest(settings:RunSettings) =
  let m = findPModule( settings.root )
  preloadPModuleTest(settings.root, settings)
  #start loading
  setCurrentDir(m.path)
  initModuleMgr()
  sortModuleQueue()
  for m in sortedQueue:
    var dllPath = m.dllPath
    let lres = loadModule( dllPath, dllPath, false, noreload = true )
    if lres.kind != resultLoaded:
      echo "error loading module: ", m.name
      echo "errorcode: ", lres.kind
      if lres.kind == resultNoDependency:
        echo lres.deps
      quit(1)
  mainloop(settings)

#----------------------------------------------------------------
proc loadPModule(settings:RunSettings) =
  if settings.test:
    preloadPModuleTest(settings.root, settings)
  else:
    preloadPModule(settings.root, settings)
  
  #start loading
  setCurrentDir(settings.root)
  initModuleMgr()
  sortModuleQueue()
  for m in sortedQueue:
    let lres = loadModule( m.dllPath, m.dllPath, false, noreload = true )
    if lres.kind != resultLoaded:
      echo "failed to load module: ", m.name
      echo "errorcode: ", lres.kind
      if lres.kind == resultNoDependency:
        echo lres.deps
      quit(1)
  mainloop(settings)

#----------------------------------------------------------------
proc loadPProject(settings:RunSettings) =
  for m in getAutoloadModules():
    preloadPModule(m.path, settings)
    
  setCurrentDir(settings.root)
  initModuleMgr()
  sortModuleQueue()

  for m in sortedQueue:
    let lres = loadModule( m.dllPath, m.dllPath, false, noreload = true )
  mainloop(settings)

#----------------------------------------------------------------
proc loadEntry(settings:RunSettings) =  
  prepareModuleEnv()

  let projectRoot = getProjectRoot()

  if projectRoot == "":
    let localPackage = findPPackage(settings.root)
    if localPackage != "":
      scanPackages(localPackage)
    updateModuleList()
    loadPModuleTest(settings)

  else:
    updateModuleList()
    loadPProject(settings)


#================================================================
let doc = """
Pil loader.

  Description:
    load PIL module/project in specified directory

  Usage:
    pload [--test] [--release] [--rebuild] [--nobuild] [<root_path>]
    pload (-h | --help)

  Options:
    -h --help     Show this screen.
"""

proc toStr(v:Value, def = ""):string =
  if v.kind == vkNone:
    def
  else:
    $v

when isMainModule:
  let args = docopt(doc)

  var settings = RunSettings(
    root:     args["<root_path>"].toStr(getCurrentDir()),
    release:  args["--release"].toBool,
    rebuild:  args["--rebuild"].toBool,
    nobuild:  args["--nobuild"].toBool,
    test:     args["--test"].toBool,
  )

  loadEntry(settings)
