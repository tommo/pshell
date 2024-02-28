import plugin/pgapiImpl
import std/[macros]

export pgapiImpl

#----------------------------------------------------------------
template testAsMainModule*( body:untyped ) =
  {.error:"obseleted".}
  # when isMainModule:
  #   import plugin/pgmain
  #   import plua
  #   import unittest
  #   import std/os
  #   echo "start at:", getCurrentDir()
  #   onModuleStart:
  #     let vm = affirmDefaultLuaVM()
  #     vm.addPath(getCurrentDir()/"testdata/?.lua")
  #     body
  #   testMainModule()

when defined(combinePModules):
  template testPModule*(body:untyped) =
    when isMainModule:
      import plugin/pgmain
      import utils/extern/unittest2
      import std/os
      echo "start at:", getCurrentDir()
      onModuleStart:
        body
      testMainModule()
else:
  template testPModule*(body:untyped) =
    #TODO: dangerous
    import plugin/pgmain
    # import utils/extern/unittest2
    import std/os
    echo "start at:", getCurrentDir()
    onModuleTestStart:
      body

template importSub*( modname:untyped ) =
  import modname
  export modname


macro defineOpaqueConverter*( ptype:typedesc, vtype:typedesc ) =
  #TODO: typechecking
  let ptypeInner = getTypeImpl(getTypeImpl(ptype)[1])
  if not ( ptypeInner.kind == nnkDistinctTy ):
    error("first argument is not a distinct type", ptype )
  let nameIn = ident "fromOpaque_" & ptype.strVal
  let nameOut = ident "toOpaque_" & ptype.strVal
  let nameAt = ident "@"
  let nameDot = ident "."
  let nameDotEq = ident ".="
  result = quote do:
    converter `nameIn`*( p:`ptype` ):`vtype`  =
      cast[`vtype`](p)
    
    template `nameAt`*( p:`ptype` ):`vtype`  =
      cast[`vtype`](p)

    template `nameDot`*( p:`ptype`, k:untyped ):untyped =
      cast[`vtype`](p).k

    template `nameDotEq`*( p:`ptype`, k, v:untyped ):untyped =
      cast[`vtype`](p).k = v

    converter `nameOut`*( p:`vtype` ):`ptype`  =
      `ptype`(p)

  when isMainModule:
    echo result.repr

#----------------------------------------------------------------
when isMainModule:
  type opaque = distinct pointer
  defineOpaqueConverter opaque, ptr int


{.used.}