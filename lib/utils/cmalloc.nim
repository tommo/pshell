proc c_malloc*(size: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>".}
proc c_free*(p: pointer) {.importc: "free", header: "<stdlib.h>".}
proc c_realloc*(p: pointer, newsize: csize_t): pointer {.importc: "realloc", header: "<stdlib.h>".}

#----------------------------------------------------------------
proc c_malloc*(size: int):pointer {.inline.} =
  c_malloc(size.csize_t)