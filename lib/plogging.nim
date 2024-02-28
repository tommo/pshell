import plugin/pgapiImpl

type
  LogLevel* {.size:sizeof(uint8).} = enum
    levelDebug  = "DEBUG"
    levelInfo   = "INFO",
    levelNotice = "NOTICE",
    levelWarn   = "WARN",
    levelError  = "ERROR",
    levelFatal  = "FATAL"
    levelAlways = "LOG  "

  LogHandlerProc* = proc( lv:LogLevel, msg:varargs[string] )

  LogHandler* = object
    handleProc*:LogHandlerProc
    level*:LogLevel

  LogMgr* = object
    handlers*:seq[LogHandler]
    level*:LogLevel

#----------------------------------------------------------------
const defaultPilLogLevel = 
  when defined(pmoduleTest):
    "DEBUG"
  else:
    when defined(release):
      "NOTICE"
    else:
      "DEBUG"

const pilLogLevel{.strdefine.} = defaultPilLogLevel

const
  pilLogLevelValue = case pilLogLevel
    of "DEBUG": levelDebug
    of "INFO": levelInfo
    of "NOTICE": levelNotice
    of "WARN": levelWarn
    of "ERROR": levelError
    of "FATAL": levelFatal
    else: levelNotice

#----------------------------------------------------------------
var mgr{.global.}:LogMgr

proc getLogMgr*():ptr LogMgr {.hostapi.} =
  return addr mgr

template registerLogHandler*( handler:sink LogHandler ) =
  onModuleLoad:
    let mgr = getLogMgr()
    mgr.handlers.add handler

proc writeLog*( lv:LogLevel, msg:varargs[string, `$`] ) =
  {.gcsafe.}:
    let mgr = getLogMgr()
    # if mgr.handlers.len == 0:
      
    # else:
    for h in mgr.handlers:
      h.handleProc( lv, msg )
    
    if true: #stdout logging
      var line = "[" & $lv & "] "
      for part in msg:
        line.add part
      echo line

template infoLog*(msg: varargs[string, `$`]) =
  when pilLogLevelValue.int <= levelInfo.int:
    writeLog( levelInfo, msg)

template debugLog*(msg: varargs[string, `$`]) =
  when pilLogLevelValue.int <= levelDebug.int:
    writeLog( levelDebug, msg)

template warnLog*(msg: varargs[string, `$`]) =
  when pilLogLevelValue.int <= levelWarn.int:
    writeLog( levelWarn, msg)

template errorLog*(msg: varargs[string, `$`]) =
  when pilLogLevelValue.int <= levelError.int:
    writeLog( levelError, msg)

template noticeLog*(msg: varargs[string, `$`]) =
  when pilLogLevelValue.int <= levelNotice.int:
    writeLog( levelNotice, msg)

template fatalLog*(msg: varargs[string, `$`]) =
  when pilLogLevelValue.int <= levelFatal.int:
    writeLog( levelFatal, msg)

template alwaysLog*(msg: varargs[string, `$`]) =
  when pilLogLevelValue.int <= levelAlways.int:
    writeLog( levelAlways, msg)

# #----------------------------------------------------------------
# when isMainModule:
#   import strutils
#   import times

#   proc substituteLog(frmt: string, level: LogLevel,
#                     args: varargs[string, `$`]): string =
#     var msgLen = 0
#     for arg in args:
#       msgLen += arg.len
#     result = newStringOfCap(frmt.len + msgLen + 20)
#     var i = 0
#     while i < frmt.len:
#       if frmt[i] != '$':
#         result.add(frmt[i])
#         inc(i)
#       else:
#         inc(i)
#         var v = ""
#         while i < frmt.len and frmt[i] in IdentChars:
#           v.add(toLowerAscii(frmt[i]))
#           inc(i)
#         case v
#         of "date": result.add(getDateStr())
#         of "time": result.add(getClockStr())
#         of "datetime": result.add(getDateStr() & "T" & getClockStr())
#         of "levelid": result.add(($level)[0])
#         of "levelname": result.add($level)
#         else: discard
#     for arg in args:
#       result.add(arg)

#   proc okLog( lv:LogLevel, msg:varargs[string] ) =
#     echo substituteLog( "$time[$levelname] ", lv, msg)

#   # registerLogHandler( LogHandler( handleProc:okLog ))
#   error( "hello" )
