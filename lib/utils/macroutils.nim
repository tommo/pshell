import macros

macro instantiationFilePath*():string =
  let pos = instantiationInfo( 0, true )
  newLit( pos.filename )

template notNil*( a:untyped ):bool = 
  a != nil

template isNil*( a:untyped ):bool = 
  a == nil

proc isGlobalNode*( a:NimNode ):bool =
  a.owner().symKind == nskModule

proc stripPragma*(node: NimNode): NimNode =
  if node.kind == nnkPragmaExpr:
    return node[0]
  else:
    return node
    
proc stripPublic*(node: NimNode): NimNode =
  if node.kind == nnkPostfix:
    return node[1]
  else:
    return node

proc publicIdent*(node: string, public = true): NimNode =
  if public:
    nnkPostfix.newTree( ident "*", ident(node) )
  else:
    ident( node )

proc publicIdent*(node: NimNode, public = true): NimNode =
  if public:
    nnkPostfix.newTree( ident "*", stripPublic(node))
  else:
    stripPublic( node )

proc getArgIds*( procDef:NimNode ):seq[ NimNode ] =
  var params:NimNode

  case procDef.kind
  of nnkProcDef:
    params = procDef[ 3 ]
  of nnkProcTy:
    params = procDef[ 0 ]
  else:
    error( "expecting procDef/procTy", procDef )

  for n in params:
    if n.kind == nnkIdentDefs:
      for i in 0 .. n.len() - 3:
        let id = n[ i ]
        if id.kind == nnkIdent:
          result.add( id )

proc newTypeInstance*(typ: NimNode, args: seq[NimNode]): NimNode =
  # returns typ[args]
  if args.len == 0:
    return typ
  result = newNimNode(nnkBracketExpr).add(typ)
  for arg in args:
    result.add(arg)

proc flattenNode*(v: NimNode, kind: NimNodeKind): seq[NimNode] {.compiletime.} =
  if v.kind == kind:
    var ret: seq[NimNode] = @[]
    for child in v:
      for node in flattenNode(child, kind):
        ret.add node
    return ret
  else:
    return @[v]

proc identToString*(node: NimNode): string =
  if node.kind == nnkIdent:
    return $node
  elif node.kind == nnkAccQuoted:
    return $node[0]
  else:
    error("expected identifier, found " & $node.kind)

proc symToExpr*(val: NimNode, depth=false): NimNode =
  if val.kind == nnkSym:
    if depth:
      return newIdentNode($val)
    else:
      return val
  elif val.kind in {nnkIntLit}:
    return val
  elif val.kind == nnkBracketExpr: # hacky
    result = newNimNode(nnkBracketExpr)
    for item in val:
      result.add symToExpr(item, true)
  else:
    return nil

proc `[]`*(node: NimNode, s: Slice): seq[NimNode] =
  result = @[]
  for i in s:
    result.add(node[i])

#

proc getFieldNames*(t: NimNode): seq[string] =
  var res = t.getType

  if res.kind == nnkBracketExpr and $res[0] == "typeDesc":
    res = res[1]

  if res.kind == nnkBracketExpr and $res[0] == "ref":
    res = res[1].getType

  if res.kind == nnkSym:
    for item in res.getImpl[2][2]:
      result.add $(stripPublic(item[0]))
  else:
    assert res.kind == nnkObjectTy
    for item in res[2]:
      result.add $item


# proc print*(things: varargs[string, `$`]) =
#   var first:bool = true
#   for t in things:
#     if first:
#       first = false
#     else:
#       stdout.write( "\t" )
#     stdout.write( t )

#   stdout.writeLine( "" )
#   stdout.flushFile()


proc insertTypeFieldImpl*( a:var NimNode; fname:NimNode, ftype:NimNode, pos = -1 ) =
  a.expectKind( nnkTypeDef )
  # let tname = a[0][0]
  if not ( a[2].kind in {nnkObjectTy, nnkRefTy, nnkPtrTy} ):
    error( "Node must be object or ref or ptr type" )

  let objTy = if a[2].kind in {nnkRefTy, nnkPtrTy}:
      a[2][0]
    else:
      a[2]

  var fnameNode = fname
  # fnameNode = nnkPostfix.newTree( ident "*", fname )
  #insert nodeId entry
  var recList = objTy[2]
  if recList.kind == nnkEmpty:
    recList = nnkRecList.newTree(
        nnkIdentDefs.newTree(
        fnameNode,
        ftype,
        newEmptyNode()
      )
    )
    objTy[2] = recList
  else:
    var defs = nnkIdentDefs.newTree(
      fnameNode,
      ftype,
      newEmptyNode()
    )
    if pos >= 0:
      recList.insert( pos, defs )
    else:
      recList.add( defs )
    # recList.insert( 0, defs )

proc insertPublicTypeFieldImpl*( a:var NimNode; fname:string, ftype:NimNode, pos = -1 ) =
  insertTypeFieldImpl( a, nnkPostfix.newTree( ident "*", ident( fname ) ), ftype, pos )

proc insertTypeFieldImpl*( a:var NimNode; fname:string, ftype:NimNode, pos = -1 ) =
  insertTypeFieldImpl( a, ident( fname ), ftype, pos )

macro insertPublicTypeField*( a:var NimNode, fname:string, ftype:typedesc ) =
  let ftypeStr = $ftype
  result = quote do:
    insertPublicTypeFieldImpl( `a`, `fname`, ident `ftypeStr` )
    
macro insertTypeField*( a:var NimNode, fname:string, ftype:typedesc ) =
  let ftypeStr = $ftype
  result = quote do:
    insertTypeFieldImpl( `a`, `fname`, ident `ftypeStr` )


proc getBaseType*( t:NimNode ):NimNode =
  if t.kind != nnkSym:
    return nil
  let impl = t.getImpl()
  let inheritNode = impl[2][1]
  if inheritNode.kind == nnkOfInherit:
    return inheritNode[0]
  else:
    return nil

iterator baseTypes*( t:NimNode ):NimNode =
  var b = t
  while true:
    b = getBaseType(b)
    if b == nil:
      break
    else:
      yield b

#================================================================
when isMainModule:
  discard