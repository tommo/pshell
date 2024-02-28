import pmodules
import api

proc testException*() {.pimpl.} =
  raise newException(ValueError, "BAD")

proc testHello*() {.pimpl.} =
  echo "hello,world!"

