import lib/nimutils/config
import lib/utils/pathutils

task boot, "bootstrap tools":
  exec "nim cpp --out:bin/pil -d:release lib/pcli"


task testapp, "testapp":
  const binPath = currentSourceDir/"bin"
  const pilPath = binPath/"pil"
  let target = currentSourceDir/"packages"/"foo"/"app"
  let cmdLine = pilPath & " load --rebuild " & target
  echo cmdLine
  exec cmdLine