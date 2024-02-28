import pmodules
import api

pimport foo.sub

proc testCallHello*() {.pimpl.} =
  testHello()

