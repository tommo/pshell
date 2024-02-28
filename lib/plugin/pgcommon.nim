import ../pdef

import std/compilesettings
import std/staticos

import std/[os, json, macros, tables, sets, times]
import utils/simpletasks

template trycall*( body:untyped ):untyped =
  body
  # try:
  #   body
  #   discard #FIXME:need add this to "CLOSE" body

  # except CatchableError:
  #   echo getCurrentExceptionMsg()
  #   echo "[PMODULE:]stack traceback:"
  #   echo getCurrentException().getStackTrace()
  #   when not defined(release):
  #     raise getCurrentException()

#----------------------------------------------------------------
const combinePModules* {.booldefine.} = false
const forcePModulesPlugins* {.booldefine.} = false
const testExtPModule* {.booldefine.} = false

const combinePModulesReal* = combinePModules and not forcePModulesPlugins

const isPModuleTest*{.booldefine.} = false
const isPModule*{.booldefine.} = false
const isPHost* = not isPModule

var depPModules*{.compiletime.}:OrderedSet[string]

#----------------------------------------------------------------
const PMODULE_CURRENT*  {.strdefine.} = "core@pil"

var pathToModule{.compiletime.}:Table[ string, string ]
var pimportLevel{.compiletime.}:int 

macro pimportLevelInc*()=
  pimportLevel.inc

macro pimportLevelDec*()=
  pimportLevel.dec

proc pimportLevelLit*():NimNode =
  newLit( pimportLevel )

type
  TargetModInfo = object
    name:string
    subname:string
    package:string
    packageRoot:string
    moduleRoot:string

  TargetPackageInfo = object
    name:string
    root:string

var registeredPackages{.compiletime.}:Table[string, TargetPackageInfo]
var foundPModules*{.compiletime.}:Table[string, TargetModInfo]
var packageScanned{.compiletime.}:bool

proc fullname( info:TargetModInfo ):string = info.subname & "@" & info.package

proc findParentPackageStatic( filePath:string ):string {.compiletime.} =
  var path = filePath
  var ppath = filePath.parentDir()
  while not path.isRootDir:
    let infoPath = ppath/PPACKAGE_INFO_FILE
    if staticFileExists( infoPath ):
      let s = staticRead( infoPath )
      let info = parseJson( s )
      let packageName = info["package"].getStr( "" )
      return packageName
    path = ppath
    ppath = path.parentDir
  return ""

proc findParentPModule*( fromPath:string ):string =
  var path = fromPath
  assert not path.isRootDir
  var ppath = path.parentDir
  while not path.isRootDir:
    let infoPath = ppath / PPACKAGE_INFO_FILE
    if fileExists( infoPath ):
      let info = parseFile( infoPath )
      let packageName = info["package"].getStr( "nil" )
      let ( _, tail ) = splitPath( path )
      return tail & "@" & packageName
    path = ppath
    ppath = path.parentDir
  return "unknown"

proc findParentPModuleStatic*( fromPath:string ):string {.compiletime.} =
  # echo "checking from:", fromPath
  assert not fromPath.isRootDir
  # var allowParentLevel = 8
  if fromPath in pathToModule:
    return pathToModule[fromPath]
  var path = fromPath
  let fromParent = path.parentDir
  if fromParent in pathToModule:
    let res = pathToModule[fromParent]
    pathToModule[fromPath] = res
    return res

  var ppath = fromParent
  while not path.isRootDir:
    let infoPath = ppath/PPACKAGE_INFO_FILE
    if fileExists( infoPath ):
      let s = staticRead( infoPath )
      let info = parseJson( s )
      let packageName = info["package"].getStr( "nil" )
      let ( _, tail ) = splitPath( path )
      
      let modname = tail & "@" & packageName
      if modname != PMODULE_CURRENT:
        depPModules.incl( modname )
      pathToModule[ fromParent ] = modname
      pathToModule[ fromPath ] = modname
      return modname
    # allowParentLevel.dec
    # if allowParentLevel == 0: break
    path = ppath
    ppath = path.parentDir
  pathToModule[ fromParent ] = "unknown"
  pathToModule[ fromPath ] = "unknown"
  return "unknown"

proc findParentPackageStatic*( fromNode:NimNode ):string {.compiletime.} =
  findParentPackageStatic( lineInfoObj( fromNode ).filename )

proc findParentPModuleStatic*( fromNode:NimNode ):string {.compiletime.} =
  findParentPModuleStatic( lineInfoObj( fromNode ).filename )

proc checkCurrentPModule*( fromNode:NimNode ):bool {.compiletime.} =
  when combinePModulesReal:
    true
  else:
    findParentPModuleStatic( fromNode ) == PMODULE_CURRENT

macro checkPModule*() =
  when false:
    let lvl = newLit(pimportLevel)
    result = quote do:
      const mname = findParentPModuleStatic( instantiationInfo(`lvl`, true).filename )
  else:
    discard
    
macro isModuleScope*():bool =
  when combinePModulesReal:
    newLit(true)
  elif testExtPModule:
    newLit(false)
  else:
    let lvl = newLit(pimportLevel)
    result = quote do:
      when isMainModule:
        true
      else:
        const mname = findParentPModuleStatic( instantiationInfo(`lvl`, true).filename )
        mname  == PMODULE_CURRENT

#----------------------------------------------------------------
proc getPackages():Table[string, TargetPackageInfo] {.compiletime.}=
  if not packageScanned:
    packageScanned = true
    for path in querySettingSeq(searchPaths):
      let infoPath = path / PPACKAGE_INFO_FILE
      if fileExists( infoPath ):
        let info = parseJson( staticRead(infoPath) )
        let packageName = info["package"].getStr( "nil" )
        registeredPackages[packageName] = TargetPackageInfo(
            name:packageName,
            root:path
          )

  result = registeredPackages

proc findModule( packname:string, subname:string ):TargetModInfo {.compiletime.}=
  let fullname = subname & "@" & packname
  if foundPModules.contains( fullname ):
    result = foundPModules[fullname]
  else:
    let packages = getPackages()
    if packname in packages:
      let pinfo = packages[packname]
      if dirExists(pinfo.root / subname):
        result.name = subname
        result.subname = subname
        result.package = pinfo.name
        result.packageRoot = pinfo.root
        result.moduleRoot = pinfo.root / subname
        foundPModules[fullname] = result

proc findModule( modname:NimNode ):TargetModInfo =
  #TODO: search for module
  case modname.kind
  of nnkIdent: #same package
    error("full pmodule name expected", modname)
    # let thisPackage = findParentPackageStatic( modname )
    # if thisPackage == "":
    #   error( "not in a ppackage", modname )

    # result = findModule( thisPackage, modname.strVal)
    # if result.name == "":
    #   error( "invalid package", modname )

  of nnkDotExpr: #full package
    result = findModule( modname[0].strVal, modname[^1].strVal )
    if result.name == "":
      error( "package not found: " & modname.repr, modname )
  else:
    error("invalid pmodule path", modname)

macro prequire*( modname:untyped ) =
  let info = findModule( modname )
  let mfullname = info.fullname
  if mfullname != PMODULE_CURRENT:
    depPModules.incl( mfullname )

macro markUsed*( modnode:typed ) {.used.}=
  discard

macro markImportsUsed*() {.used.}=
  {. warning[UnusedImport]:off .}

# macro generateDepImplImports*():untyped =
#   when combinePModules and not defined(nimdoc):
#     result = newStmtList()
#     result.add quote do:
#       {. warning[UnusedImport]:off .}
#     for _, info in foundPModules:
#       let m_impl_path = newLit( info.moduleRoot / "impl" )
#       result.add quote do:
#         from `m_impl_path` import nil

var depPModulesRT*:OrderedSet[string]
proc requirePModuleImpl( mname:static string ) =
  depPModulesRT.incl mname

macro pimportFile*( modname:untyped, filename:untyped ) =
  let info = findModule( modname )
  let targetPath = newLit( info.moduleRoot / filename.strVal )
  result = quote do:
    pimportLevelInc()
    import `targetPath`
    pimportLevelDec()

macro pimport*( arg:untyped ) =
  var modname:NimNode
  var aliasIdent:NimNode

  case arg.kind
  of nnkIdent:
      modname = arg
  of nnkDotExpr:
      modname = arg
  of nnkInfix:
    if arg[0].strVal == "as" and arg[2].kind == nnkIdent:
      modname = arg[1]
      aliasIdent = arg[2]
    else:
      error("invalid pimport syntax", arg)
  else:
    error("invalid pimport syntax", arg)
  let info = findModule( modname )
  let mfullname = info.fullname
  if mfullname != PMODULE_CURRENT:
    depPModules.incl( mfullname )

  #----------------------------
  let mnameStr = newLit info.name
  let requirePModule = bindSym "requirePModuleImpl" 
  let m_api_path = newLit( info.moduleRoot / "api" )
  let m_impl_path = newLit( info.moduleRoot / "impl" )
  if aliasIdent == nil:
    aliasIdent = ident( info.subname )

  result = quote do:
    pimportLevelInc()
    import `m_api_path` as `aliasIdent`
    export `aliasIdent`
    when combinePModules and not defined(nimdoc):
      from `m_impl_path` import nil
      markUsed(impl)
    `requirePModule`(`mnameStr`)
    pimportLevelDec()


macro pimportApi*( arg:untyped ) =
  var modname:NimNode
  var aliasIdent:NimNode

  case arg.kind
  of nnkIdent:
      modname = arg
  of nnkDotExpr:
      modname = arg
  of nnkInfix:
    if arg[0].strVal == "as" and arg[2].kind == nnkIdent:
      modname = arg[1]
      aliasIdent = arg[2]
    else:
      error("invalid pimport syntax", arg)
  else:
    error("invalid pimport syntax", arg)
  let info = findModule( modname )
  let mfullname = info.fullname
  if mfullname != PMODULE_CURRENT:
    depPModules.incl( mfullname )

  #----------------------------
  let mname = ident info.name
  let m_api_path = newLit( info.moduleRoot / "api" )
  if aliasIdent == nil:
    aliasIdent = ident( info.subname )

  result = quote do:
    pimportLevelInc()
    import `m_api_path` as `aliasIdent`
    export `aliasIdent`
    pimportLevelDec()

#----------------------------------------------------------------
type
  PModuleAPITable* = ref object
    apiSlots:array[ 4096, pointer ]
    apiIndex:Table[ string, int ]
    apiCount:int

  PModuleEvent* = enum
    modulePreStart,
    moduleStart,
    modulePostStart,
    modulePreUpdate,
    moduleUpdate,
    modulePostUpdate,
    moduleRefresh,
    moduleStop,
    moduleUnloadOther

  PModuleMgrState* = enum
    stateRunning,
    statePaused,
    stateStopping,
    stateStopped,

  PModuleMgrFlagBit* {.pure, size:sizeof( uint32 ).} = enum
    mmfNeedUpdate,
    mmfNeedExit,
    mmfHasError,

  PModuleMgrFlags* = set[ PModuleMgrFlagBit ]

  PModuleInfo* = object
    name*:string
    revision*:int
    desc*:string
    deps*:seq[string]

  PModuleObject* = object
    main*:bool
    name*:string
    path*:string
    revision*:int
    targetRevision*:int
    lib*:pointer #LibHandle
    loadingLib*:pointer #LibHandle
    revPath*:string
    dllPath*:string
    tasks*:SimpleTaskQueue
    apiTable*:PModuleAPITable
    eventHandler*:proc(mgr:PModuleMgr, m:PModule, event:PModuleEvent ){.cdecl.}

  PModule* = ptr PModuleObject

  PModuleMgrObject* = object #global
    basePath*:string
    modules*:Table[ string, PModuleObject ]
    moduleStack*:OrderedSet[string]
    state*:PModuleMgrState
    flags*:PModuleMgrFlags
    apiTable*:PModuleAPITable
    userObjects*:Table[ string, pointer ]

  PModuleMgr* = ptr PModuleMgrObject


proc setUniqueUserObject*( mgr:PModuleMgr, name:string, data:pointer ) =
  assert not ( name in mgr.userObjects )
  mgr.userObjects[name] = data

proc setUserObject*( mgr:PModuleMgr, name:string, data:pointer ) =
  mgr.userObjects[name] = data

proc getUserObject*( mgr:PModuleMgr, name:string ):pointer =
  mgr.userObjects[name]

proc getUserObject*[T]( mgr:PModuleMgr, name:string, _:typedesc[T] ):ptr T =
  cast[ ptr T ](mgr.userObjects[name])

proc getApiSlotImpl( t:PModuleAPITable, name:string, affirm:bool ):ptr pointer =
  var idx:int
  if t.apiIndex.hasKey( name ):
    idx = t.apiIndex[ name ]
    result = addr( t.apiSlots[ idx ] )
  else:
    if affirm:
      idx = t.apiCount
      t.apiCount.inc
      t.apiIndex[ name ] = idx
      result = addr( t.apiSlots[ idx ] )
    else:
      result = nil

proc getApiSlot*( m:PModule, name:cstring ):ptr pointer =
  result = getApiSlotImpl( m.apiTable, $name, true )
  assert result != nil
  # echo "getting api:", name, "=", cast[int]( result )

proc setApiSlot*( m:PModule, name:cstring, impl:pointer ) =
  let slot = getApiSlotImpl( m.apiTable, $name, false )
  if slot == nil:
    raiseAssert( "API not defined:" & $name )
  else:
    # echo "setting api:", name, "@", cast[int](impl) , "=>", cast[int]( slot )
    slot[] = impl

proc newTask*( m:PModule ):ptr SimpleTask =
  m.tasks.newTask()

proc updateModuleTasks*( m:PModule ) =
  # trycall:
  m.tasks.update()

proc stopModuleTasks*( m:PModule ) =
  m.tasks.stopAll()

proc hasTask*( m:PModule|PModuleObject ):bool =
  not m.tasks.isEmpty()

proc getApiSlot*( mgr:PModuleMgr, name:cstring ):ptr pointer =
  result = getApiSlotImpl( mgr.apiTable, $name, true )
  assert result != nil
  # echo "getting api:", name, "=", cast[int]( result )

proc setApiSlot*( mgr:PModuleMgr, name:cstring, impl:pointer ) =
  let slot = getApiSlotImpl( mgr.apiTable, $name, false )
  # echo "setting api:", name, "@", cast[int](impl) , "=>", cast[int]( slot )
  if slot == nil:
    raiseAssert( "API not defined:" & $name )
  else:
    slot[] = impl

var currentPModule:PModule
proc getCurrentPModule*():PModule =
  currentPModule

proc getCurrentPModuleRev*():int =
  currentPModule.revision

proc setCurrentPModule*( m:PModule ) =
  currentPModule = m

proc getPModule*( mgr:PModuleMgr, name:string ):PModule =
  mgr.modules[ name ].addr

proc tryStop*( mgr:PModuleMgr ) =
  if mgr.state notin { stateStopped, stateStopping }:
    mgr.state = stateStopping

proc stopping*( mgr:PModuleMgr ):bool = 
  mgr.state == stateStopping

proc running*( mgr:PModuleMgr ):bool = 
  mgr.state == stateRunning

proc paused*( mgr:PModuleMgr ):bool = 
  mgr.state == statePaused

proc stopped*( mgr:PModuleMgr ):bool = 
  mgr.state == stateStopped

proc reload*( mgr:PModuleMgr ) =
  mgr.flags.incl mmfNeedUpdate

template timeIt*( body:untyped ):untyped =
  let t0 = epochTime()
  echo "timing: >>", (t0*1000).int, " @ ", instantiationInfo(-1, true)
  body
  echo "Timed:",((epochTime() - t0)*1000).int, " @ ", instantiationInfo(-1, true)
