# import std/macros
# import std/with

type
  SimpleTaskState* = enum
    stsInit,
    stsRunning,
    stsStopped

  SimpleTask* = object
    name*:string
    state*:SimpleTaskState
    onStart*:proc()
    onUpdate*:proc():bool
    onStop*:proc()

  SimpleTaskQueue* = object
    tasks:seq[SimpleTask]

proc isEmpty*( queue:SimpleTaskQueue ):bool =
  queue.tasks.len == 0

proc addTask*( queue:var SimpleTaskQueue, task:SimpleTask ):ptr SimpleTask =
  queue.tasks.add( task )
  result = addr queue.tasks[^1]

proc newTask*( queue:var SimpleTaskQueue, name:string = "" ):ptr SimpleTask =
  queue.addTask( SimpleTask( name:name ) )

proc stopAll*( queue:var SimpleTaskQueue ) =
  var i = 0
  while i < queue.tasks.len:
    let t = addr queue.tasks[i]
    if t.state == stsRunning:
      if t.onStop != nil:
        t.onStop()
      t.state = stsStopped
    i.inc
  queue.tasks.setlen(0)
  
proc update*( queue:var SimpleTaskQueue ) =
  var i = 0
  try:
    while i < queue.tasks.len:
      let t = addr queue.tasks[i]
      if t.state == stsInit:
        if t.onStart != nil:
          t.onStart()
        t.state = stsRunning

      assert t.state == stsRunning
      var done = true
      if t.onUpdate != nil:
        done = t.onUpdate()
      if done:
        if t.onStop != nil:
          t.onStop()
        t.state = stsStopped
        queue.tasks.delete(i)
      else:
        i.inc
  except CatchableError as e:
    raise e
      
# template withNewTask*( queue:var SimpleTaskQueue, body:untyped ) =
#   with queue.newTask():
#     body

#----------------------------------------------------------------
when isMainModule:
  # import sugar
  var q:SimpleTaskQueue
  
  let task = q.newTask()
  var count = 2
  task.onStart = proc() = 
    echo "start"

  task.onUpdate = proc():bool =
    echo "onUpdate:", count
    count.dec
    return count == 0 #done

  task.onStop = proc() =
    echo "stop"

  q.update()
  q.update()
  q.update()
