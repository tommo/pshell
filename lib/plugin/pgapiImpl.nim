import pgcommon

import std/[tables, macros, strutils, hashes, sets, times]
import utils/macroutils

export pgcommon

var currentModuleLoadProcs:seq[proc( mgr:PModuleMgr, module:PModule, reloading:bool ) {.nimcall.}]
var currentModuleEventProcs:seq[proc( mgr:PModuleMgr, module:PModule, ev:PModuleEvent ) {.nimcall.}]
var currentModuleUnloadProcs:seq[proc( mgr:PModuleMgr, module:PModule, reloading:bool ) {.nimcall.}]
var depModuleLoadProcs:seq[proc( mgr:PModuleMgr, module:PModule ) {.nimcall.}]

var pmoduleApiEntries:Table[ string, ptr pointer ]
var pmoduleImplEntries:Table[ string, pointer ]
var pmoduleHostImplEntries:Table[ string, pointer ]

type ModuleApiItem = object
  name     :string
  protoName:string

var ctApiEntries{.compiletime.}:Table[ string, ModuleApiItem]
var ctImplEntries{.compiletime.}:Table[ string, ModuleApiItem]

proc checkApiValid( p:pointer, name:static string ) =
  if p == nil:
    raiseAssert "current module not initialized. " & name
  if cast[ptr pointer](p)[] == nil:
    raiseAssert "API proc not loaded: " & name
  # discard

#----------------------------------------------------------------
macro onDepModuleLoad*( body:untyped ):untyped =
  result = quote do:
    block:
      proc callback( mgr{.inject.}:PModuleMgr, module{.inject.}:PModule ) {.nimcall.} =
        # let t0 = epochTime()
        # echo "onModuleLoad at:", instantiationInfo(-1, true), " @ ",epochTime()
        trycall:
          `body`
        # echo "onDepLoad done",instantiationInfo(-1, true), " @ ", ((epochTime() - t0)*1000).int

      depModuleLoadProcs.add( callback )

macro onExternModuleLoad*( body:untyped ):untyped =
  result = quote do:
    when not isModuleScope:
      block:
        proc callback( mgr{.inject.}:PModuleMgr, module{.inject.}:PModule ) {.nimcall.} =
          trycall:
            `body`
        depModuleLoadProcs.add( callback )

template onModuleLoad*( body:untyped ):untyped =
  when isModuleScope:
    proc callback( mgr{.inject.}:PModuleMgr, module{.inject.}:PModule, reloading{.inject.}:bool ) {.nimcall, gensym.} =
      checkPModule()
      # let t0 = epochTime()
      # echo "onModuleLoad at:", instantiationInfo(-1, true), " @ ",epochTime()
      trycall:
        body
      # echo "onModuleLoad done",instantiationInfo(-1, true), " @ ", ((epochTime() - t0)*1000).int
    currentModuleLoadProcs.add( callback )

template onModuleFirstLoad*( body:untyped ):untyped =
  onModuleLoad:
    if not reloading:
      body

template onModuleFinalUnload*( body:untyped ):untyped =
  onModuleUnload:
    if not reloading:
      body

template onModuleUnload*( body:untyped ):untyped =
  block:
    when isModuleScope:
      proc callback( mgr{.inject.}:PModuleMgr, module{.inject.}:PModule, reloading{.inject.}:bool ) {.nimcall.} =
        # debugEcho "onModuleUnload at:", instantiationInfo(-1, true)
        trycall:
          body
        # debugEcho "onModuleUnload done"
      currentModuleUnloadProcs.insert( callback, 0 )

template onDepModuleUnload*( body:untyped ):untyped =
  block:
    proc callback( mgr{.inject.}:PModuleMgr, module{.inject.}:PModule, reloading{.inject.}:bool ) {.nimcall.} =
      # debugEcho "onModuleUnload at:", instantiationInfo(-1, true)
      trycall:
        body
      # debugEcho "onModuleUnload done"
    currentModuleUnloadProcs.insert( callback, 0 )

template onModuleUnloadLate*( body:untyped ):untyped =
  block:
    when isModuleScope:
      proc callback( mgr{.inject.}:PModuleMgr, module{.inject.}:PModule, reloading{.inject.}:bool ) {.nimcall.} =
        # debugEcho "onModuleUnload at:", instantiationInfo(-1, true)
        trycall:
          body
        # debugEcho "onModuleUnload done"
      currentModuleUnloadProcs.add( callback )

template onDepModuleUnloadLate*( body:untyped ):untyped =
  block:
    proc callback( mgr{.inject.}:PModuleMgr, module{.inject.}:PModule, reloading{.inject.}:bool ) {.nimcall.} =
      # debugEcho "onModuleUnload at:", instantiationInfo(-1, true)
      trycall:
        body
      # debugEcho "onModuleUnload done"
    currentModuleUnloadProcs.add( callback )


template onModuleTestStart*( body:untyped ):untyped =
  block:
    proc callback( mgr{.inject.}:PModuleMgr, module{.inject.}:PModule, event{.inject.}:PModuleEvent ) {.nimcall.} =
      if event == moduleStart:
        trycall:
          body
    currentModuleEventProcs.add( callback )

template onModuleEvent*( body:untyped ):untyped =
  block:
    when isModuleScope:
      proc callback( mgr{.inject.}:PModuleMgr, module{.inject.}:PModule, event{.inject.}:PModuleEvent ) {.nimcall.} =
        trycall:
          body
      currentModuleEventProcs.add( callback )

template onModuleRefresh*( body:untyped ):untyped =
  onModuleEvent:
    if event == moduleRefresh:
      body

template preModuleStart*( body:untyped ):untyped =
  onModuleEvent:
    if event == modulePreStart:
      body

template postModuleStart*( body:untyped ):untyped =
  onModuleEvent:
    if event == modulePostStart:
      body

template onModuleStart*( body:untyped ):untyped =
  onModuleEvent:
    if event == moduleStart:
      body

template preModuleUpdate*( body:untyped ):untyped =
  onModuleEvent:
    if event == modulePreUpdate:
      body

template postModuleUpdate*( body:untyped ):untyped =
  onModuleEvent:
    if event == modulePostUpdate:
      body

template onModuleUpdate*( body:untyped ):untyped =
  onModuleEvent:
    if event == moduleUpdate:
      body

proc genProcProtoName( procDef:NimNode ):string =
  let fname = stripPublic( procDef[0] )
  # echo procDef[3].repr
  # genSym( nskProc, $fname )
  $fname & "_" & toHex( hash( procDef[3].repr ))

proc defineAPIEntry( fname:string; p:ptr pointer ) =
  # echo "<---", fname, ",", cast[int]( p )
  pmoduleApiEntries[ fname ] = p

proc defineImplEntry( fname:string; f:pointer ) =
  # echo "<---", fname, ",", cast[int]( p )
  pmoduleImplEntries[ fname ] = f

proc defineHostImplEntry( fname:string; f:pointer ) =
  # echo "<---", fname, ",", cast[int]( p )
  pmoduleHostImplEntries[ fname ] = f


#[
  mgr.setApiEntry( mhandle, "xxxx", cast[pointer](xxx_pointer) )
]#
template tplSetApiEntry( fname, impl:untyped ) =
  setAPIEntry( currentPModule, fname, cast[pointer]( impl ))

#[
  xxx_pointer = cast[proctype](mgr.getApiAddr( mhandle, "xxxx" ))
]#
template tplGetApiEntry( fname, impl:untyped ) =
  impl = getAPIAddr( currentPModule, fname )

proc checkApiAst( item:NimNode, hostApi = false ) =
  var msg:string = ""
  # let ptype = item[3]
  block checking:
    if not hostApi:
      if item[^1].kind != nnkEmpty:
        msg = "no proc implementation allowed"
        break checking
    if item.kind notin {nnkProcDef, nnkFuncDef}:
      msg = "expecting proc/func"
      break checking
    if item[2].kind != nnkEmpty:
      msg = "no generic allowed"
      break checking
    # if item[0].kind != nnkPostfix:
    #   msg = "API must be public symbol"
    #   break checking
  if msg != "":
    error( msg, item )

proc addApiItem*( mname:string, f0:NimNode, hostApi = false ):NimNode =
  f0.expectKind nnkProcDef
  checkApiAst( f0, hostApi )  
  let f = f0.copyNimTree()
  let fname = stripPublic( f[0] )
  let fnameProtoStr = genProcProtoName( f )
  let fnameProto = ident( fnameProtoStr )
  
  ctApiEntries[ fnameProtoStr ] = ModuleApiItem(
    name:fname.strVal,
    protoName:fnameProtoStr
  )
  var copiedTy = copyNimTree( f[3] )
  var procTy = nnkProcTy.newTree(
    copiedTy, nnkPragma.newTree( ident "nimcall" )
  )
  var castBody = nnkCast.newTree( nnkPtrTy.newTree( procTy ), fnameProto )
  var callBody = nnkCall.newTree( nnkBracketExpr.newTree( castBody ) )
  # var debugBody = nnkCall.newTree( ident "echo", nnkCast.newTree(  ident "int",  fnameProto ) )
  when defined(release):
    var assertBody = newEmptyNode()
  else:
    var assertBody = newCall( bindSym "checkApiValid", fnameProto, newLit fname.repr )

  for arg in getArgIds( f ):
    callBody.add( arg )
  f[6] = newStmtList(
      assertBody,
      callBody
    )

  var pragDef = f[ 4 ]
  if pragDef.kind == nnkEmpty:
    pragDef = nnkPragma.newTree()
    f[ 4 ] = pragDef
  pragDef.insert( 0, ident "inline" )
  pragDef.insert( 0, ident "nimcall" )

  var loadAPI = nnkCall.newTree( 
    bindSym "defineAPIEntry",
    newLit( mname & "." & $fnameProto ),
    nnkAddr.newTree(
      fnameProto
    )
  )

  result = nnkStmtList.newTree(
    nnkVarSection.newTree( 
      nnkIdentDefs.newTree( fnameProto, ident "pointer", newEmptyNode())
    ),
    f,
    loadAPI
  )
  echo result.repr
  

proc addImplItem*( mname:string, f:NimNode, hostApi = false ):NimNode =
  f.expectKind nnkProcDef
  let fname = stripPublic( f[0] )
  let fnameProtoStr = genProcProtoName(f)

  if not ctApiEntries.hasKey( fnameProtoStr ):
    error( "API or API overload is not defined", f )

  if ctImplEntries.hasKey( fnameProtoStr ):
    error( "duplicated Impl", f )

  ctImplEntries[ fnameProtoStr ] = ModuleApiItem(
    name:fname.strVal,
    protoName:fnameProtoStr
  )

  let fnameProto = ident( fnameProtoStr )
  let fnameImplProto = ident( fnameProtoStr & "_impl" )
  f[0] = fnameImplProto
  if f[4].kind == nnkEmpty:
    f[4] = nnkPragma.newTree( 
      ident("nimcall")
    )
  else:
    f[4].add ident("nimcall")

  var loadAPI = nnkCall.newTree( 
    bindSym "defineImplEntry",
    newLit( mname & "." & $fnameProto ),
    fnameImplProto
  )

  result = newStmtList(
    f,
    loadAPI
  )
  echo result.repr

proc addHostApiItem*( mname:string, f:NimNode ):NimNode =
  f.expectKind nnkProcDef
  let fname = stripPublic( f[0] )
  let fnameProtoStr = genProcProtoName(f)
  let fnameProto = ident( fnameProtoStr )
  f[0] = fnameProto

  var falias = nnkProcDef.newTree()
  falias.add( publicIdent fname )
  for i in 1..5:
    falias.add( f[i].copyNimTree )
  var pragDef = f[ 4 ]
  if pragDef.kind == nnkEmpty:
    pragDef = nnkPragma.newTree()
    f[ 4 ] = pragDef
  pragDef.insert( 0, ident "inline" )
  pragDef.insert( 0, ident "nimcall" )
  var call = nnkCall.newTree( fnameProto )
  for arg in getArgIds( f ):
    call.add( arg )

  var forwardDecl = falias.copyNimTree()
  forwardDecl.add( newEmptyNode() )
  falias.add( nnkStmtList.newTree(
      call #arglist
    ) )

  var loadAPI = nnkCall.newTree( 
    bindSym "defineHostImplEntry",
    newLit( mname & "." & $fnameProto ),
    fnameProto
  )

  result = newStmtList()
  result.add( forwardDecl )
  result.add( f )
  result.add( falias )
  result.add( loadAPI )

  # echo result.repr

proc pmodulePreloader*( mgr{.inject.}:PModuleMgr, module:PModule, reloading:bool ):PModule {.exportc, dynlib.} =
  for mname in depPModulesRT: 
    echo mname

proc pmoduleLoader*( mgr{.inject.}:PModuleMgr, module:PModule, reloading:bool ):PModule {.exportc, dynlib.} =  
  setCurrentPModule( module )
  #flush api
  for fname, p in pmoduleHostImplEntries:
    discard mgr.getApiSlot( fname.cstring ) #affirm slot
    mgr.setApiSlot( fname.cstring, p )

  for fname, p in pmoduleApiEntries:
    p[] = mgr.getApiSlot( fname.cstring )

  for fname, p in pmoduleImplEntries:
    mgr.setApiSlot( fname.cstring, p )


  for cb in depModuleLoadProcs:
    cb( mgr, module )

  for cb in currentModuleLoadProcs:
    cb( mgr, module, reloading )

proc pmoduleEventHandler*( mgr{.inject.}:PModuleMgr, module:PModule, ev:PModuleEvent ):PModule {.cdecl, exportc, dynlib.} =
  for cb in currentModuleEventProcs:
    cb( mgr, module, ev )
  if ev == moduleUpdate:
    module.updateModuleTasks()

proc pmoduleUnloader*( mgr{.inject.}:PModuleMgr, module:PModule, reloading:bool ) {.cdecl, exportc, dynlib.} =
  module.stopModuleTasks()
  for cb in currentModuleUnloadProcs:
    cb( mgr, module, reloading )

macro genPModuleInfoProc*(revision:int):untyped =
  var nnn = nnkBracket.newNimNode()
  for dm in depPModules: 
    if dm != PMODULE_CURRENT:
      nnn.add( newLit(dm) )

  let depsRepr = nnkPrefix.newTree(
      ident "@",
      nnn
    )

  result = quote do:
    proc pmoduleGetModuleInfo*( info:var PModuleInfo ) {.cdecl, exportc, dynlib.} =
      static: 
        const depsStatic:seq[string] = `depsRepr`
        when isPModuleTest:
          writeFile( getProjectPath() & "/test_deps", join( depsStatic, "\n" ) )
        else:
          writeFile( getProjectPath() & "/lib_deps", join( depsStatic, "\n" ) )
      info.deps = `depsRepr`
      info.name = PMODULE_CURRENT
      info.revision = `revision`
  # echo result.repr

#----------------------------------------------------------------
when defined(nimsuggest) or defined(nimdoc):
  macro papi*( a:untyped ):untyped {.used.}=
    a[^1] = quote do:
      discard
    result = a

  macro pimpl*( a:untyped ):untyped {.used.}=
    discard

  macro hostapi*( a:untyped ):untyped {.used.}=
    result = a

else:
  macro papi*( a:untyped ):untyped {.used.}=
    let mname = findParentPModuleStatic( a )
    addApiItem( mname, a, false )

  macro pimpl*( a:untyped ):untyped {.used.}=
    let mname = findParentPModuleStatic( a )
    addImplItem( mname, a, false )

  macro hostapi*( a:untyped ):untyped {.used.}=
    when combinePModulesReal:
      result = a
    else:
      when isPHost:
        result = addHostApiItem( "_host", a )
      else:
        result = addApiItem( "_host", a, true )
