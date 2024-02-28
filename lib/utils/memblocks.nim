type
  MemBlock* = tuple[ data:pointer, size:uint32 ]

template staticReadMemBlock*( path:string ):MemBlock =
  let memblock = static staticRead( path )
  ( pointer(memblock[0].addr), memblock.len.uint32 )

proc copyMemBlock*( b:MemBlock ):MemBlock =
  let memBlock = alloc( b.size )
  copyMem( memBlock, b.data, b.size )
  ( memBlock, b.size )

proc copyMemBlock*( data:string|seq[uint8] ):MemBlock =
  let memBlock = alloc( data.len )
  copyMem( memBlock, pointer(data[0].addr), data.len )
  ( memBlock, data.len.uint32 )

