import math

type
  SimpleTimerKind* = enum
    tkOneShot
    tkRepeat

  SimpleTimer* = object
    kind*:SimpleTimerKind
    time*:float64
    timeout*:float64
    stopped*:bool
    callback*:proc()

#----------------------------------------------------------------
proc update*( t:var SimpleTimer, delta:float64 ) =
  if t.stopped: return
  t.time += delta
  if t.time >= t.timeout:
    case t.kind
    of tkOneShot:
      t.stopped = false
    of tkRepeat:
      t.time = t.time mod t.timeout
    if t.callback != nil:
      t.callback()

#----------------------------------------------------------------
proc newSimpleTimer*( timeout:float64, callback:proc(), kind = tkOneShot ):SimpleTimer =
  result.kind = kind
  result.timeout = timeout
  result.callback = callback

#----------------------------------------------------------------
func mapTimeReverse*( t, span:float64 ):float64 {.inline.} =
  max( span - t, 0 )

#----------------------------------------------------------------
func mapTimeReverseContinue*( t, span:float64 ):float64 {.inline.} =
  span - t

#----------------------------------------------------------------
func mapTimeReverseLoop*( t, span:float64 ):float64 {.inline.} =
  span - ( t mod span )

#----------------------------------------------------------------
func mapTimePingPong*( t, span:float64 ):float64 {.inline.} =
  let f = t mod span
  if (floor( t / span ) mod 2) == 0:
    f
  else:
    span - f

#----------------------------------------------------------------
func mapTimeLoop*( t, span:float64 ):float64 {.inline.} =
  t mod span



#================================================================
when isMainModule:
  for i in 0..<10:
    let t = i.float64 * 0.2
    echo mapTimeLoop( t, 1 )
  echo "----"

  for i in 0..<10:
    let t = i.float64 * 0.1
    echo mapTimeReverse( t, 5 )
  echo "----"

  for i in 0..<10:
    let t = i.float64 * 0.1
    echo mapTimePingPong( t, 0.2 )
  echo "----"

  var timer = newSimpleTimer( 0.5, 
    proc()=
      echo "Time out!"
    )
  timer.update( 1 )
  assert timer.stopped

