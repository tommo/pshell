import sets
import macros, strutils

#----------------------------------------------------------------
#extra set helper
template containsAndExcl*[T]( a:set[T], v:T ):bool =
  if a.contains( v ):
    a.excl( v )
    true
  else:
    false

template missingAndIncl*[T]( a:set[T], v:T ):bool =
  if not a.contains( v ):
    a.incl( v )
    true
  else:
    false

#----------------------------------------------------------------
type SomeSet* = concept x, T
  x.incl( T )
  x.excl( T )

template setIncl*( a:SomeSet, flag:untyped, b = true ):untyped =
  if b:
    a.incl( flag )
  else:
    a.excl( flag )

#----------------------------------------------------------------
template addReadonlyFlagProperty( selfType, flagsId, flag, keyId:untyped ):untyped {.dirty.}=
  proc keyId*( self:selfType ):bool=
    self.flagsId.contains( flag )

  macro `keyId=`*( self:var selfType, value:bool ):untyped=
    error( "readonly property", self )

#----------------------------------------------------------------
template addFlagProperty( selfType, flagsId, flag, keyId:untyped ):untyped {.dirty.}=
  proc keyId*( self:selfType ):bool=
    self.flagsId.contains( flag )

  proc `keyId=`*( self:var selfType, value:bool )=
    if value:
      self.flagsId.incl( flag )
    else:
      self.flagsId.excl( flag )


#----------------------------------------------------------------
template addReadonlyValueProperty( selfType, fieldId, fieldType, keyId:untyped ):untyped {.dirty.}=
  proc keyId*( self:selfType ):fieldType =
    self.fieldId

  macro `keyId=`*( self:var selfType, value:fieldType ):untyped=
    error( "readonly propery", self )

#----------------------------------------------------------------
template addValueProperty( selfType, fieldId, fieldType, keyId:untyped ):untyped {.dirty.}=
  proc keyId*( self:selfType ):fieldType =
    self.fieldId

  proc `keyId=`*( self:var selfType, value:fieldType )=
    self.fieldId = value

#----------------------------------------------------------------
template addFnProperty( selfType, fieldType, keyId, getterStmt, setterStmt:untyped ):untyped {.dirty.}=
  proc keyId*( self{.inject.}:selfType ):fieldType {.inline.}  =
    getterStmt

  proc `keyId=`*( self{.inject.}:var selfType, value{.inject.}:fieldType ) {.inline.} =
    setterStmt

#----------------------------------------------------------------
template addReadonlyFnProperty( selfType, fieldType, keyId, getterStmt, setterStmt:untyped ):untyped {.dirty.}=
  proc keyId*( self{.inject.}:selfType ):fieldType {.inline.}  =
    getterStmt

  macro `keyId=`*( self{.inject.}:var selfType, value{.inject.}:fieldType ) {.inline.} =
    error( "readonly propery", self )


#----------------------------------------------------------------
macro property*( t:typedesc, body:untyped ):untyped =
  result = newStmtList()
  expectKind body, nnkStmtList
  for entry in body:
    expectKind entry, nnkAsgn
    let pname = entry[0]
    let pbody = entry[1]
    expectKind pbody, nnkCommand
    let pmode = pbody[0]
    let pvalue = pbody[1]

    case pmode.strVal
    of "flag":
      expectKind pvalue, nnkDotExpr
      let flagField = pvalue[0]
      let flagValue = pvalue[1]
      result.add getAst( addFlagProperty( t, flagField, flagValue, pname ) )

    of "flag_readonly":
      expectKind pvalue, nnkDotExpr
      let flagField = pvalue[0]
      let flagValue = pvalue[1]
      result.add getAst( addReadonlyFlagProperty( t, flagField, flagValue, pname ) )

    of "value":
      expectKind pvalue, nnkIdent
      # let ptype = getType( )
      let tDesc = getType(getType(t)[1])
      let fieldStr = $pvalue
      for field in tDesc[2].children:
        if $field == fieldStr:
          result.add getAst( addValueProperty( t, pvalue, getType( field ), pname ) )
          break

    of "value_readonly":
      expectKind pvalue, nnkIdent
      let tDesc = getType(getType(t)[1])
      let fieldStr = $pvalue
      for field in tDesc[2].children:
        if $field == fieldStr:
          result.add getAst( addReadonlyValueProperty( t, pvalue, getType( field ), pname ) )
          break
    
    of "expr": #expr type expr
      let vtype = pbody[1][0]
      let exprBody = pbody[1][1]
      var getterStmt, setterStmt:NimNode
      getterStmt = nnkStmtList.newTree( exprBody )
      setterStmt = nnkStmtList.newTree( nnkAsgn.newTree( exprBody, ident "value" ) )
      result.add getAst( addFnProperty( t, vtype, pname, getterStmt, setterStmt ) )

    of "expr_readonly": #expr type expr
      let vtype = pbody[1][0]
      let exprBody = pbody[1][1]
      var getterStmt, setterStmt:NimNode
      getterStmt = nnkStmtList.newTree( exprBody )
      setterStmt = nnkStmtList.newTree( nnkAsgn.newTree( exprBody, ident "value" ) )
      result.add getAst( addReadonlyFnProperty( t, vtype, pname, getterStmt, setterStmt ) )

    else:
      error( "invalid property definition", entry )
  echo result.repr

template tryCompiles*( body:untyped ):untyped =
  when compiles( body ):
    body
    
template assertCompiles*( msg:string, body:untyped ):untyped =
  when compiles( body ):
    body
  else:
    {.fatal: msg.}

#----------------------------------------------------------------
macro toArray*( stmtlist:untyped ):untyped =
    result = nnkBracket.newNimNode()
    for n in stmtlist:
        case n.kind
        of nnkCommand:
            var call = nnkCall.newNimNode()
            n.copyChildrenTo( call )
            result.add call
        else:
            result.add n


macro toSeq*( stmtlist:untyped ):untyped =
    var bracket = nnkBracket.newNimNode()
    result = nnkPrefix.newTree( ident "@", bracket )
    for n in stmtlist:
        case n.kind
        of nnkCommand:
            var call = nnkCall.newNimNode()
            n.copyChildrenTo( call )
            bracket.add call
        else:
            bracket.add n
#================================================================
when isMainModule:
  type TMyStruct = object
    foo: int32
    bar: int16

  macro sumSizes(t: typedesc): untyped =
    result = nil
    let tDesc = getType(getType(t)[1])
    let foo = ident( "foo" )
    for field in tDesc[2].children:
      if field == foo:
        echo "YES"
      echo getType(field)
      let sizeOfThis = newCall("sizeof", getType(field))
      if isNil(result):
        result = sizeOfThis
      else:
        result = infix(result, "+", sizeOfThis)

  echo sumSizes(TMyStruct)

  type
    FooFlag{.size:sizeof(uint8).} = enum
      flagVisible,
      flagLocked
    FooFlags = set[ FooFlag ]

    Bar = object
      x,y:int

    Test = object
      flags:FooFlags
      internalSize:int
      bar:Bar

  property Test:
    visible = flag flags.flagVisible
    locked  = flag flags.flagLocked
    size    = value internalSize
    sizeRead = value_readonly internalSize
    bx       = expr int self.bar.x

  #----------------------------------------------------------------
  # addFlagProperty Test, flags, flagVisible, visible
  var t = Test()
  t.internalSize = 100
  echo t.visible
  t.visible = true
  echo t.visible
  echo t.size
  # t.sizeRead = 10

  #----------------------------------------------------------------
  type DirtyFlag {.size:sizeof(uint8).} = enum
    dirtyFBO
    dirtyVBO
    dirtyShader
  type DirtyFlags = set[ DirtyFlag ]

  type Foo = object
    dirtyFlags:DirtyFlags

  var o = Foo()
  o.dirtyFlags.incl( dirtyFBO )
  if o.dirtyFlags.containsAndExcl( dirtyFBO ):
    echo( "update" )
