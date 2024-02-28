import std/[ os, sets, strformat, strutils, tables, times, algorithm, sequtils, strscans ]
import std/[ json, streams, monotimes ]
import utils/[strutils2]
import plugin/pgapiImpl

import penv
import plogging

proc timeInSeconds:float64 = getMonoTime().ticks.float64 * ( 1e-9 )

proc libName*(moduleName:string):string = 
  DynlibFormat % moduleName
  # &"lib{moduleName}.dylib"

proc normalizeModuleName*(s:string):string =
  let stripped = s.strip()
  block:
    let parts = stripped.split(".")
    if parts.len == 2:
      return parts[1] & "@" & parts[0]
  block:
    let parts = stripped.split("@")
    if parts.len == 2:
      return parts[0] & "@" & parts[1]
  return ""

#----------------------------------------------------------------
type
  DefaultPModuleSettings* = object
    autoload*:bool
    priority*:int

  PPackageConfig* = ref object
    name*:string
    path*:string
    modes*:seq[string]
    accepted*:bool
    moduleSettings*:DefaultPModuleSettings

  PModuleIndex* = object
    preloadModules*:OrderedSet[ string ]
    moduleQueue*:seq[PModuleConfig]
    moduleConfigs*:OrderedTable[ string, PModuleConfig ]
    packageConfigs*:OrderedTable[ string, PPackageConfig ]
    appMode*:string
    projectRoot*:string

  PModuleConfig* = ref object
    name*:string
    path*:string
    subname*:string
    impname*:string
    package*:PPackageConfig
    friends*:seq[ string ]

    srcfiles*:seq[ string ]
    deps*:OrderedTable[ string, int ]
    depModules*:OrderedSet[string]
    
    autoload*:bool = false
    depended*:bool = false
    modified*:bool = false
    compiled*:bool = false

    priority*:int
    depOrder*:int
    srchash*:uint32
    revision*:int = -1
    timestamp*:int64
    loadedRevision*:int = -1
    loadedDllHash*:uint32
    dllPath*:string
    statChanged*:bool

#----------------------------------------------------------------
var pmoduleIndex* = PModuleIndex()

#----------------------------------------------------------------
proc tryRegisterPackage( path:string ) {.hostapi.} =
  #TODO:user package mark
  let configPath = path / PPACKAGE_INFO_FILE
  if fileExists( configPath ):
    let config = parseFile( configPath )
    var pkg:PPackageConfig = nil
    
    if config{ "package" } != nil:
      let pname = config["package"].to(string)
      pkg = PPackageConfig(
        name: pname,
        path: path,
      )
    else:
      warnLog "invalid ppackage.json(?), lacking package name."

    if pkg == nil: return
    let pkg0 = pmoduleIndex.packageConfigs.getOrDefault(pkg.name, nil)
    if pkg0 != nil:
      if pkg0.path != path:
        errorLog("package name conflicted:" & pkg.name)
        quit(1)

    pmoduleIndex.packageConfigs[pkg.name] = pkg

    pkg.accepted = true
    pkg.moduleSettings.autoload = config{"autoload"}.getBool(false)
    pkg.moduleSettings.priority = config{"priority"}.getInt(0)
    
    debugLog "add ppackage:", pkg.name, "  ->", pkg.path
    if pkg.moduleSettings.autoload:
      debugLog " >autoload"

    if config{ "mode" } != nil:
      let modes = to( config{ "mode" }, seq[string] )
      pkg.modes = modes
      if (modes.len > 0) and (pmoduleIndex.appMode notin modes):
        pkg.accepted = false

proc preloadModule*( path:string ) {.hostapi.} =
  pmoduleIndex.preloadModules.incl( path )

proc scanPackages*( path:string )  {.hostapi.} =
  if dirExists(path):
    tryRegisterPackage( path )
    for kind, p in walkDir( path ):
      if kind in { pcLinkToDir, pcDir }:
        tryRegisterPackage( p )

proc scanPilPackages*()  {.hostapi.} =
  scanPackages( pilRootPath / "packages" )

proc scanProject*(projectRoot:string) {.hostapi.} =
  scanPilPackages()
  scanPackages( projectRoot / "packages" )
  scanPackages( projectRoot )
  
  #load project config
  let infoPath = projectRoot / PPROJECT_INFO_FILE
  let info = parseFile( infoPath )
  
  if info.contains("preload"):
    for n in info["preload"]:
      let val = n.getStr()
      let fullname = normalizeModuleName(val)
      if fullname != "":
        preloadModule(fullname)
  
  if info.contains("packages"):
    for n in info["packages"]:
      if dirExists(n.getStr()):
        scanPackages(n.getStr())

proc scanModuleNimFiles( path:string ):seq[string] =
  for nimfile in walkFiles( path / "*.nim" ):
    let relative = relativePath( nimfile, path )
    # echo relative
    result.add( nimfile )

proc affirmModuleConfig( pkg:PPackageConfig, moduleSrcPath:string ) =
  let moduleFullName = findParentPModule( moduleSrcPath )
  var config = pmoduleIndex.moduleConfigs.getOrDefault( moduleFullName, nil )
  if config == nil:
    let parts = moduleFullName.split("@")
    config = PModuleConfig(
      package: pkg, 
      name: moduleFullName, 
      subname: parts[0], 
      impname: parts[1] & "." & parts[0],
      path:moduleSrcPath,
      depOrder: -1
    )
    pmoduleIndex.moduleConfigs[ moduleFullName ] = config
    pmoduleIndex.moduleQueue.add config
    # noticeLog "add pmodule:   ", moduleFullName, "    autoload: ", config.autoload

  if fileExists( moduleSrcPath / PMODULE_INFO_FILE ):
    let j = parseFile( moduleSrcPath / PMODULE_INFO_FILE )
    config.autoload = j{"autoload"}.getBool(pkg.moduleSettings.autoload)
    config.priority = j{"priority"}.getInt(pkg.moduleSettings.priority)
    # try:
    #   config.friends = j["friends"].to( seq[string] )
    # except CatchableError:
    #   config.friends.setLen(0)
  else:
    config.autoload = pkg.moduleSettings.autoload
    config.priority = pkg.moduleSettings.priority

  #preload ?
  for m in pmoduleIndex.preloadModules:
    if matchAsterisk(m, moduleFullName):
      config.autoload = true
      noticeLog "AUTOLOAD: ", moduleFullName
      break

proc updateModuleList*() {.hostapi.} =
  for pname, pkg in pmoduleIndex.packageConfigs:
    for kind, p in walkDir( pkg.path ):
      let filename = p.splitFile().name
      if filename.startswith("."): continue
      if filename.startswith("_"): continue
      if kind in { pcLinkToDir, pcDir }:
        affirmModuleConfig( pkg, p )

proc findModuleConfig*(name:string):PModuleConfig {.hostapi.} =
  let normalized = normalizeModuleName(name)
  pmoduleIndex.moduleConfigs.getOrDefault( normalized, nil )

proc affirmTestModuleConfig*(name:string):PModuleConfig {.hostapi.} =
  let normalized = normalizeModuleName(name)
  let srcModule = pmoduleIndex.moduleConfigs.getOrDefault( normalized, nil )
  if srcModule != nil:
    let testName = normalized & ".test"
    var config = PModuleConfig(
      package: srcModule.package, 
      name: testName, 
      # subname: parts[0], 
      # impname: parts[1] & "." & parts[0],
      path: srcModule.path,
      autoload: false,
      depOrder: -1
    )
    pmoduleIndex.moduleConfigs[ testName ] = config
    pmoduleIndex.moduleQueue.add config
    return config

proc prepareModuleEnv*() {.hostapi.} =
  scanPilPackages()
  #TODO: load project env
  let projectRoot = findPProject( getCurrentDir() )
  if projectRoot != "":
    noticeLog "current project:", projectRoot
    pmoduleIndex.projectRoot = projectRoot
    scanProject( projectRoot )

proc getProjectRoot*():string {.hostapi.} =
  pmoduleIndex.projectRoot

proc getAutoloadModules*():seq[PModuleConfig] {.hostapi.} =
  for mconf in pmoduleIndex.moduleConfigs.values:
    if mconf.autoload:
      result.add mconf
# proc updateModuleQueue*() {.hostapi.} =
#   type
#     MNode = ref object
#       m:PModuleConfig
#       deps:seq[MNode]
#       depChecked:bool
#       visitSeq:int
#       root:bool

#   var map:Table[string, MNode]
#   var rootMNode = MNode( root:true)

#   for m in pmoduleIndex.moduleQueue:
#     if not (m.depended or m.autoload): continue
#     let n = MNode(m:m)
#     map[m.name] = n
#     rootMNode.deps.add n
#     rootMNode.deps.sort  do (a,b:MNode) -> int:
#         cmp(a.m.priority, b.m.priority)

#   while true:
#     var hasNew = false
#     let batch = map.values.toseq()
#     for mnode in batch:
#       if mnode.depChecked: continue
#       # echo ">>>> check:  ", mnode.m.name
#       mnode.depChecked = true
#       hasNew = true
#       let res = loadModule( mnode.m.formalDllPath, mnode.m.revDllPath, true )
#       case res.kind
#       of resultCheckDep:
#         for name in res.deps:
#           if name notin map:
#             if not pmoduleIndex.moduleConfigs.contains(name):
#               doAssert false #TODO
#             map[name] = MNode(m:pmoduleIndex.moduleConfigs[name])
#           let depMNode = map[name]
#           mnode.deps.add depMNode
#         mnode.deps.sort  do (a,b:MNode) -> int:
#           cmp(a.m.priority, b.m.priority)
          
#       else:
#         doAssert false
#     if not hasNew: break

#   var visitSeq = 0
#   proc topoSort(head:MNode):seq[MNode] =
#     visitSeq.inc
#     var loopcount = 0
#     proc visit(n:MNode, history:var seq[MNode]) =
#       loopcount.inc
#       if loopcount > 100: return
#       for n in n.deps:
#         if n.visitSeq != visitSeq: 
#           n.visitSeq = visitSeq
#           visit(n, history)
#         else:
#           if n notin history:
#             echo "cycle loop found:", n.m.name
#             assert false
#       if not n.root: history.add(n)
#     visit(head, result)
#   var order = 0
#   for subNode in rootMNode.deps:
#     for n in topoSort(subNode):
#       order.inc
#       # echo n.m.name, "->", order
#       if n.m.depOrder < 0:
#         n.m.depOrder = order
#       else:
#         n.m.depOrder = min(n.m.depOrder, order)
#   pmoduleIndex.moduleQueue.sort do (a,b:PModuleConfig) -> int:
#     cmp(a.depOrder, b.depOrder)
