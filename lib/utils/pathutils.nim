import os

template currentSourceDir*():string = 
  instantiationInfo(-1, true).filename.parentDir()

export `/`
export parentDir
