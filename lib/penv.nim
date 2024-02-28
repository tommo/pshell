import plugin/pgapiImpl
import std/[tables]
import std/[os, json]

import pdef
export pdef

var env:Table[string, string]

proc getPEnv*(k:string, default:string=""):string {.hostapi.} =
  env.getOrDefault(k, default)

proc setPEnv*(k:string, value:string) {.hostapi.} =
  env[k] = value

proc hasPEnv*(k:string):bool {.hostapi.} =
  env.contains(k)

#----------------------------------------------------------------
var packagePaths:seq[string]
var projectRoot:string

proc findPProject*( fromPath:string ):string {.hostapi.} =
  var path = fromPath
  assert not path.isRootDir
  while not path.isRootDir:
    let infoPath = path / PPROJECT_INFO_FILE
    if fileExists( infoPath ):
      let info = parseFile( infoPath )
      let projName = info["project"].getStr( "nil" )
      return path #TODO
    path = path.parentDir
  return ""


proc findPModule*( fromPath:string ):tuple[name:string, path:string] {.hostapi.} =
  assert not fromPath.isRootDir
  var path = fromPath
  var ppath = path.parentDir
  while not path.isRootDir:
    let infoPath = ppath / PPACKAGE_INFO_FILE
    if fileExists( infoPath ):
      let info = parseFile( infoPath )
      let packageName = info["package"].getStr( "nil" )
      let ( _, tail ) = splitPath( path )
      let mname = tail & "@" & packageName
      return (mname, path)
    path = ppath
    ppath = path.parentDir
  return ("", "")

proc findPPackage*( fromPath:string ):string {.hostapi.} =
  var path = fromPath
  assert not path.isRootDir
  var ppath = path
  while not path.isRootDir:
    let infoPath = ppath / PPACKAGE_INFO_FILE
    if fileExists( infoPath ):
      let info = parseFile( infoPath )
      let packageName = info["package"].getStr( "nil" )
      return ppath
    path = ppath
    ppath = path.parentDir
  return ""
