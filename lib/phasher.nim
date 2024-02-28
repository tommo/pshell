import penv
import std/[ os, strutils, strformat, strscans ]
import std/[ times ]
import std/[ cmdline, parseopt ]
import utils/[filehashutils, fileutils, strutils2]


proc hashPModule*( rootPath:string ):tuple[hashstr:string, msg:string] =
  let (moduleName, m1) = findPModule(
    if rootPath == "":
      getCurrentDir()
    else:
      rootPath
  )
  let moduleSrcPath = m1
  if moduleSrcPath != "":
    let binPath = moduleSrcPath / "bin"
    proc isFile(name, patt:string):bool = name.endsWith(patt)
    proc inDir(name, patt:string):bool = name.startsWith(patt)
    
    let filterAbs = proc( name:string ):bool = 
      if name.inDir(moduleSrcPath / "_build"): return false
      if name.inDir(moduleSrcPath / "test"): return false
      if name.inDir(moduleSrcPath / "bin"): return false
      if name.inDir(moduleSrcPath / ".nimcache"): return false
      if name.inDir(moduleSrcPath / ".testdata"): return false
      if name.endsWith( ".nim" ):
        if name.startsWith("test"):
          return false
      elif name.endsWith( ".json" ):
        return true
      return true
    
    let filterRel = proc( name:string ):bool = 
      filterAbs(moduleSrcPath/name)

    discard existsOrCreateDir(binPath)

    let timestampFile = binPath / ".timestamp"
    
    var timestamp0:int64
    var hash0:uint32

    if fileExists(timestampFile):
      var t1, h1:int
      if scanf(readFile(timestampFile), "$i,$i", t1, h1):
        timestamp0 = t1.int64
        hash0 = h1.uint32
    let timestamp = getLastContentModificationTime( moduleSrcPath, filterAbs ).toUnix()
    if timestamp > timestamp0:
      #check file hash
      let srcHash = calcDirHashMT( moduleSrcPath, filterRel )
      let output = $timestamp & "," & $srcHash
      writeFile(timestampFile, output)
      if srcHash != hash0:
        return (srcHash.toHex, "changed")
      else:
        return (srcHash.toHex, "no_change")
    else:
      return (hash0.toHex, "no_change")
  else:
    return ("0", "no_module")

when isMainModule:
  var pwd:string
  for kind, key, val in getOpt(commandLineParams()):
    case kind
    of cmdArgument:
      pwd = key
    else:
      discard
  let output = hashPModule( pwd )
  echo output.hashstr, ":", output.msg

