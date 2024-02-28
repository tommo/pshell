import std/[macros, tables]
import hashutils

type StrId* = distinct int

proc `==`*( a, b:StrId ):bool {.borrow.}
proc `$`*( a:StrId ):string {.borrow.}
func hash*( v:StrId ):Hash = hash( v.int )

var usedIDs{.compiletime.}:Table[StrId, string]

proc getStaticStrID( id:static string ):StrId {.compiletime.} =
  result = hashFNV1a( id ).StrId
  let prev = usedIDs.mgetOrPut( result, id )
  if prev != id:
    let errmsg = "string hash collision: " & id & " -> " & prev
    warning( errmsg )

proc strId*( id:static[string]|string ):StrId =
  when id is static[string]:
    result = static:
      getStaticStrID( id )
  else:
    hashFNV1a( id ).StrId

converter toStrId*( id:static[string]|string ):StrId =
  strId( id )


#----------------------------------------------------------------
when isMainModule:
  proc useId( n:StrId ) =
    echo "hello!", $n

  const nice = "nice"
  let good = "good"
  echo strId(nice)
  assert strId( good ) == strId( "good" )

  useId( "good" )
  echo strId( "good" )