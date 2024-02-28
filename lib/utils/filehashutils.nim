import skyhash/xxhash
import std/[algorithm, os, threadpool, hashes]

{.push checks: off, optimization: speed.}

proc calcFileHash*( paths:openarray[string], seed:uint32=0 ):uint32 {.gcsafe.}=
  const blockSize = 1024 * 64
  var bytesRead: int = 0
  var buffer: array[blockSize, byte]
  let p = buffer[0].addr

  var hs: XXH32_state
  discard hs.init( seed )
  for path in paths:
    var f: File = open( path, fmRead )
    while true:
      bytesRead = f.readBuffer( p, blockSize )
      if likely( bytesRead > 0 ):
        hs.update( p, bytesRead )
      else:
        break
    f.close()
    
  result = hs.final()

proc calcFileHash*( path:string, seed:uint32=0 ):uint32 {.gcsafe.}=
  calcFileHash([path], seed)


proc calcDirHashMT*( path:string, filter:proc( name:string ):bool {.gcsafe.} = nil, seed:uint32=0 ):uint32 {.gcsafe.} =
  var files:seq[string]
  if filter == nil:
    for f in walkDirRec( path, relative = true ):
      files.add( f )
  else:
    for f in walkDirRec( path, relative = true ):
      if filter( f ):
        files.add( f )

  sort( files, system.cmp )

  var finalHash: Hash = 0
  #Workaround for orc/threadpool bug
  proc calcFileHashWrapper( path:string, output:ptr uint32, seed:uint32 ) =
    output[]= calcFileHash( path, seed )

  # var res = newSeq[tuple[ name:string, fv:FlowVar[uint32]]]( files.len )
  var fHashes = newSeq[uint32]( files.len )
  for i, f in files:
    spawn calcFileHashWrapper( path / f, fHashes[i].addr, seed )

  for i, f in files:
    finalHash = finalHash !& hash(f)

  sync()

  for h in fHashes:
    finalHash = finalHash !& h.int

  result = ( !$finalHash ).uint32


proc calcDirHash*( path:string, filter:proc( name:string ):bool = nil, seed:uint32=0 ):uint32 =
  var files:seq[string]
  if filter == nil:
    for f in walkDirRec( path, relative = true ):
      files.add( f )
  else:
    for f in walkDirRec( path, relative = true ):
      if filter( f ):
        files.add( f )
  sort( files, system.cmp )
  var finalHash: Hash = 0

  for i, f in files:
    finalHash = finalHash !& hash(f)

  for i, f in files:
    let path = path / f
    let h = calcFileHash( path )
    finalHash = finalHash !& h.int

  result = ( !$finalHash ).uint32

#================================================================
when isMainModule:
  const mthread{.booldefine.} = true
  let path = "/Volumes/prj/moai/eastward/deploy/_build/osx"
  when mthread:
    echo calcDirHashMT( path )
  else:
    echo calcDirHash( path )
