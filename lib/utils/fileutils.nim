import os, times

proc getLastContentModificationTime*( path:string, filter:proc( name:string ):bool = nil ):Time =
  if filter == nil:
    for f in walkDirRec( path ):
      let t = f.getLastModificationTime() 
      if t > result: result = t
  else:
    for f in walkDirRec( path ):
      if filter( f ):
        let t = f.getLastModificationTime() 
        if t > result: result = t
