import std/[ os, sets, strformat, strutils, tables, strscans, times, algorithm]
import std/[ json, jsonutils, streams ]
import std/[ osproc ]
import std/[ monotimes ]
import std/[ cmdline, parseopt ]
import utils/[filehashutils, fileutils]

import plugin/pgmain


const pilRootPath = currentSourcePath.parentDir().parentDir()
const PPACKAGE_INFO_FILE = "ppackage.json"
const PTOOL_LIST_FILE = "ptools.json"


type 
  ToolKind = enum
    Nims
    Nim
    Executable

  ToolEntry = object
    kind:ToolKind
    name:string
    path:string
    package:string
    global:bool #no package namespace

var tools:seq[ToolEntry]

proc cmdName(entry:ToolEntry):string =
  let package = entry.package
  let name = entry.name
  if package == "" or package == "pil":
    name
  else:
    package & "." & name
#----------------------------------------------------------------
proc scanTools() =
  proc scanOnePackage( path:string ) =
    let infoPath = path / PPACKAGE_INFO_FILE
    if fileExists(infoPath):
      let info = parseFile(infoPath)
      let packageName = info["package"].getStr( "nil" )

      for nims in walkFiles(path/"*/ptool_*.nims"):
        let (dir,name,ext) = splitFile(nims)
        var toolname:string
        discard name.scanf("ptool_$w+", toolname)
        if toolname.startswith("g_"):
          toolname = toolname.substr(2)
          tools.add ToolEntry(kind:Nims, path:nims, name:toolname, package:"")
        else:
          tools.add ToolEntry(kind:Nims, path:nims, name:toolname, package:packageName)

      for nimfile in walkFiles(path/"*/ptool_*.nim"):
        let (dir,name,ext) = splitFile(nimfile)
        var toolname:string
        discard name.scanf("ptool_$w+", toolname)
        discard name.scanf("ptool_$w+", toolname)
        if toolname.startswith("g_"):
          toolname = toolname.substr(2)
          tools.add ToolEntry(kind:Nim, path:nimfile, name:toolname, package:"")
        else:
          tools.add ToolEntry(kind:Nim, path:nimfile, name:toolname, package:packageName)

  proc scanPackages( path:string ) =
    for kind, p in walkDir( path ):
      if kind in { pcLinkToDir, pcDir }:
        scanOnePackage(p)

  scanPackages( pilRootPath/"packages")
  tools.add ToolEntry(kind:Nim, path:pilRootPath/"lib"/"phasher.nim", name:"hasher", package:"")
  tools.add ToolEntry(kind:Nim, path:pilRootPath/"lib"/"pstub.nim",   name:"stub",   package:"")
  tools.add ToolEntry(kind:Nim, path:pilRootPath/"lib"/"pbuild.nim",  name:"build",  package:"")
  tools.add ToolEntry(kind:Nim, path:pilRootPath/"lib"/"pload.nim",  name:"load",  package:"")
  # writeFile pilRootPath/"bin"/PTOOL_LIST_FILE, pretty(tools.toJson)

#----------------------------------------------------------------
proc affirmTools() =
  let infoPath = pilRootPath/"bin"/PTOOL_LIST_FILE
  if fileExists( infoPath ):
    let infoJson = parseJson(readFile(infoPath))
    tools.fromJson(infoJson)

proc sortTool(a, b:ToolEntry): int=
  result = cmp(a.package, b.package)
  if result == 0:
    result = cmp(a.name, b.name)

proc listTools() =
  echo "PIL command line tool"
  echo ""
  echo "  available tools:"
  echo ""
  let sortedTools = tools.sorted(sortTool)
  for entry in sortedTools:
    echo "   - ", entry.cmdName
  echo ""


#----------------------------------------------------------------
proc isNewer(fileA, fileB:string):bool =
  if fileExists(fileA) and fileExists(fileB):
    let timeA = getLastModificationTime(fileA)
    let timeB = getLastModificationTime(fileB)
    timeA > timeB
  else:
    false


proc getParams():string =
  var first:bool = true
  for p in commandLineParams()[ 1 .. ^1]:
    if p == "--rebuildTool": continue
    if not first:
      result.add " "
    first = false
    result.add p

#----------------------------------------------------------------
proc exec(tool:ToolEntry, rebuilding:bool) =
  # echo "rebuilding:", rebuilding
  let paramStr = getParams()
  case tool.kind
  of Nim:
    let toolBinPath = pilRootPath/"bin"/"tools"
    let toolBin = toolBinPath/tool.name
    let toolSrc = tool.path
    let toolCfg = toolSrc & ".cfg"
    let needCompile = 
      if rebuilding:
        true
      else:
        if fileExists(toolBin):
          # isNewer(toolSrc, toolBin) or isNewer(toolCfg, toolBin)
          isNewer(toolSrc, toolBin)
        else:
          true

    if needCompile:
      createDir(toolBinPath)
      # echo "recompling tool.."
      let cmd = &"nim cpp -d:PIL_TOOL --out:{toolBin} -d:release --debuginfo --debugger:native --stackTrace:on --lineTrace:on {toolSrc}"
      let (output, exitCode) = execCmdEx( cmd )
      if exitCode != 0: 
        echo output
        quit(exitCode)
      # echo "done"

    if fileExists(toolBin):
      let cmd = &"{toolBin} {paramStr}"
      let exitCode = execCmd( cmd )
      quit(exitCode)

  of Nims:
    let cmd = &"nim e {tool.path} {paramStr}"
    let (output, exitCode) = execCmdEx( cmd )
    echo output
    quit(exitCode)

  of Executable:
    discard

#----------------------------------------------------------------
proc runTool(cmd:string, rebuilding:bool) =
  var tool:ToolEntry
  for entry in tools:
    if entry.cmdName == cmd:
      entry.exec(rebuilding)
      return
  echo "tool not found: ", cmd
  return


#----------------------------------------------------------------
proc entry() =
  #ENTRY
  var cmdName:string
  var rebuilding = false

  for kind, key, val in getOpt(commandLineParams()):
    case kind
    of cmdArgument:
      if cmdName == "":
        cmdName = key

    of cmdLongOption, cmdShortOption:
      case key
      of "rebuildTool":
        rebuilding = true
    
    of cmdEnd:
      assert(false)

  #redirect to sub_tool
  # if cmdName == "update":
  #   scanTools()
    # return
  # affirmTools()
  scanTools()
  if cmdName == "":
    listTools()
  else:
    runTool(cmdName, rebuilding)
  

when isMainModule:
  entry()