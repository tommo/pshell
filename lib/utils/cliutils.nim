import extern/docopt
import extern/docopt/dispatch

export docopt
export dispatch


# import std/streams

proc echoErr*(msg:varargs[string, `$`]) =
  for m in msg:
    write(stdErr, m)
  write(stdErr, "\n")

#----------------------------------------------------------------
when isMainModule:
  import strutils
  import sequtils

  let doc = """
  Naval Fate Lite

  Usage:
    naval_fate ship new <name>...
    naval_fate ship <name> move <x> <y> [--speed=<kn>]
    naval_fate (-h | --help)
    naval_fate --version

  Options:
    -h --help     Show this screen.
    --version     Show version.
    --speed=<kn>  Speed in knots [default: 10].
"""

  
  let args = docopt(doc, version = "Naval Fate Lite")

  # Define procedures with parameters named the same as the arguments
  proc newShip(name: seq[string]) =
    for ship in name:
      echo "Creating ship $#" % ship

  proc moveShip(name: string, x, y: int, speed: int) =
    echo "Moving ship $# to ($#, $#) at $# kn".format(
      name, x, y, speed)

  if args.dispatchProc(newShip, "ship", "new") or # Runs newShip if "ship" and "new" is set
    args.dispatchProc(moveShip, "ship", "move"): # Runs newShip if "ship" and "move" is set
    echo "Ran something"
  else:
    echo doc