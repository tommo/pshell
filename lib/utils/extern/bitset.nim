#[
MIT License

Copyright (c) 2020 Jory Schossau

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]#


import strutils
# import unicode
# export strutils

{.checks: off, optimization: speed.}
when not declared(BitsetBitCountTable):
  const BitsetBitCountTable = [0,1,1,2,1,2,2,3,1,2,2,3,2,3,3,4,1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,4,5,5,6,5,6,6,7,5,6,6,7,6,7,7,8]

type Bitset*[S:static int] = object
  bytes*:array[(S shr 3) + int((S and 0b111) != 0), uint8]

# define all function signatures to use AnyBitset,
# thereby allowing both stack and pointer bitsets
type AnyBitset[S:static int] = (Bitset[S]|ptr Bitset[S])

func len*[S:static int](bs:AnyBitset[S]):int = S

func `[]`*[S:static int](bs:AnyBitset[S], i:int):int {.inline.}=
  when not defined(release):
    if i < 0 or i >= S:
      raise newException(IndexDefect,"Error: index $1 not in Bitset of size $2" % [$i, $S])
  (bs.bytes[i shr 3].int and (1 shl (0b111 and i))) shr (0b111 and i)

proc `[]=`*[S:static int](bs:var AnyBitset[S], i:int, value:bool|int) {.inline.} =
  when not defined(release):
    if i < 0 or i >= S:
      raise newException(IndexDefect,"Error: index $1 not in Bitset of size $2" % [$i, $S])
  if value.bool:
    bs.bytes[i shr 3] = bs.bytes[i shr 3] or uint8(1 shl (0b111 and i))
  else:
    bs.bytes[i shr 3] = bs.bytes[i shr 3] and not uint8(1 shl (0b111 and i))

func `==`*[S:static int](x,y:AnyBitset[S]):bool {.inline.} = x.bytes == y.bytes
func `!=`*[S:static int](x,y:AnyBitset[S]):bool {.inline.} = x.bytes != y.bytes

func `$$`*[S:static int] (bs:AnyBitset[S]):string =
  for i in countDown(bs.bytes.len-1,0):
    result.add int(bs.bytes[i]).toBin(8) & ' '
  result.delete(result.len-1, result.len-1)
  result = '[' & result & ']'

func `$`*[S:static int] (bs:AnyBitset[S]):string =
  for i in countDown(bs.bytes.len-1,0):
    result.add int(bs.bytes[i]).toBin(8)

func count*[S:static int] (bs:AnyBitset[S]):int =
  for i in countDown(bs.bytes.len-1,0):
    result += BitsetBitCountTable[bs.bytes[i]]

func any*[S:static int] (bs:AnyBitset[S]):bool =
  for i in countDown(bs.bytes.len-1,0):
    if bs.bytes[i] > 0: return true
  return false

func none*[S:static int] (bs:AnyBitset[S]):bool =
  for i in countDown(bs.bytes.len-1,0):
    if bs.bytes[i] != 0: return false
  return true

template test*[S:static int] (bs:AnyBitset[S], i:int):bool = bs[i] == 1

func all*[S:static int] (bs:AnyBitset[S]):bool =
  for i in countDown(bs.bytes.len-1,0):
    if bs.bytes[i] != 255: return false
  return true

# in nim we usually use `len`, but this is here for a more faithful port
template size*[S:static int] (bs:AnyBitset[S]):int = S

proc set*[S:static int] (bs:var AnyBitset[S]) =
  for i in countDown(bs.bytes.len-1,0):
    bs.bytes[i] = 255

template set*[S:static int] (bs:var AnyBitset[S], pos:int, value:bool|int) =
  `[]=`(bs, pos, value.bool)

proc reset*[S:static int] (bs:var AnyBitset[S]) =
  zeroMem bs.bytes[0].addr, bs.bytes.len
  # for i in countDown(bs.bytes.len-1,0):
  #   bs.bytes[i] = 0

template reset*[S:static int] (bs:var AnyBitset[S], pos:Natural) =
  `[]=`(bs, pos, 0)

proc flip*[S:static int] (bs:var AnyBitset[S]) =
  for i in countDown(bs.bytes.len-1,0):
    bs.bytes[i] = not bs.bytes[i]

template flip*[S:static int] (bs:var AnyBitset[S], pos:Natural) =
  bs[pos] = bs[pos] xor 1

template bitset_boolop (op:untyped) =
  proc `op`*[S:static int] (a,b: AnyBitset[S]): Bitset[S]{.inject.} =
    for i in countDown(a.bytes.len-1,0):
      result.bytes[i] = `op`(a.bytes[i],b.bytes[i])
bitset_boolop(`and`)
bitset_boolop(`or`)
bitset_boolop(`xor`)

func `not`*[S:static int] (bs: AnyBitset[S]): Bitset[S]=
  for i in countDown(bs.bytes.len-1,0):
    result.bytes[i] = not bs.bytes[i]
