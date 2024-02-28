type
  Stack*[T] = seq[T]

proc push*[T]( s:var Stack[T], v:T ) {.inline.} =
  s.add( v )

func topOrDefault*[T]( s:Stack[T], default:T ):T =
  if s.len > 0:
    s[ s.len - 1 ]
  else:
    default

func top*[T]( s:Stack[T] ):T {.inline.} =
  assert s.len > 0
  s[ s.len - 1 ]

func isEmpty*[T]( s:Stack[T] ):bool =
  s.len == 0

proc pop*[T]( s:var Stack[T] ):T {.inline.}=
  assert s.len > 0
  let l = s.len
  result = s[ l-1 ]
  s.del( l-1 )

proc popOrDefault*[T]( s:var Stack[T], default:T ):T =
  if s.len > 0:
    s.pop()
  else:
    default  

when isMainModule:
  var s:Stack[int]

  for i in 0..<10:
    s.push i

  while not s.isEmpty:
    echo s.pop

  echo s.popOrDefault( 133 )
  