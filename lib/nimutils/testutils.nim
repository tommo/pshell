when not defined(nimscript):
  {.error:"nimscript module".}

import os
import strutils
import strformat

const pilRoot = getEnv "PIL_ROOT"

task httpd, "start httpd":
  when not defined(debug):
    const binPath = pilRoot / "bin" / "release"
    const cachePath = pilRoot / ".nimcache"/"release"
    const argBuildType = "-d:release"
  else:
    const binPath = pilRoot / "bin" / "debug"
    const cachePath = pilRoot / ".nimcache"/"debug"
    const argBuildType = "--debuginfo --debugger:native"
  const httpdBin = binPath / "httpd"
  let srcPath = currentSourcePath().parentDir()
  let httpdSrc = srcPath / "httpd.nim"
  let currentDir = getCurrentDir()
  withDir( pilRoot ):
    exec &"nim cpp -r {argBuildType} --nimcache:{cachePath} -o:{httpdBin} {httpdSrc} {currentDir}"
