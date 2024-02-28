import hashes
export hashes

{.checks: off, optimization: speed.}
proc hashFNV1a*(x: string): Hash {.inline.} =
  # FNV-1a 64
  var h = 0x100000001b3'u64
  for c in x:
    h = h xor c.uint64
    h *= 0xcbf29ce484222325'u64
  return cast[Hash](h)

#----------------------------------------------------------------
type
  HashBox* [T]= object
    objHash:int
    obj:T

proc hash*[T]( box:HashBox[T] ):int =
  box.objHash

proc updateHash[T]( box:var HashBox[T] ) =
  box.objHash = hash( box.obj )

proc set*[T]( box:var HashBox[T], obj:T ) =
  box.obj = obj
  box.objHash = hash( box.obj )

proc hashBox*[T]( obj:T ):HashBox[T] =
  result.set( obj )

proc `==`*[T]( a,b:HashBox[T] ):bool =
  a.objHash == b.objHash

proc obj*[T]( b:HashBox[T]):T =
  b.obj

# converter toHashBox*[T]( b:T ):HashBox[T] =
#   result.set( b )

converter fromHashBox*[T]( b:HashBox[T] ):T =
  b.obj

template modify*[T]( b:var HashBox[T], body:untyped ):untyped =
  bind updateHash
  block:
    let obj{.inject.} = addr b.obj
    body
    updateHash( b )


#----------------------------------------------------------------
when isMainModule:
  var a = hashBox( "hello" )
  var b = hashBox( "hello" )
  assert( a == b )

  type Desc = object
    name:string
    x,y:int

  type DescHolder = object
    d1:HashBox[Desc]
    d2:HashBox[Desc]

  var h = DescHolder()
  h.d1 = Desc()
  h.d2 = Desc()
  modify h.d1:
    obj.name = "name"
  modify h.d2:
    obj.name = "name"

  assert h.d1.hash == h.d2.hash
  
  modify h.d2:
    obj.name = "NAME"  

  assert h.d1.hash != h.d2.hash
