import pmodules

pimport foo.sub

testPModule:
  testHello()
  try:
    testException()
  except Exception:
    echo "captured"