import std/[algorithm, unicode, strutils]

proc matchAsterisk*( pattern, input:string ):bool =
    var 
        pi = 0
        ii = 0
        pl = pattern.len
        il = input.len
    while pi < pl:
        let p = pattern[pi]
        if p == '*':
            var p1{.noinit.}:char 
            while pi < pl-1:
                pi.inc
                p1 = pattern[pi]
                if p1 != '*': break
            if pi == pl-1: return true
            while true:
                if input[ii] == p1: break
                ii.inc
                if ii == il: 
                    return false
        elif p != input[ii]:
            return false
        else:
            pi.inc
            ii.inc
            if ii == il:
                while pi < pl:
                    if pattern[pi] != '*': return false
                    pi.inc
                break

    return pi == pl and ii == il


import std/[algorithm, unicode, strutils]

func editDistance(a, b: string): int = #{.noSideEffect.} =
  ## Returns the edit distance between `a` and `b`.
  ##
  ## This uses the `Levenshtein`:idx: distance algorithm with only a linear
  ## memory overhead.  This implementation is highly optimized!
  var len1 = a.len
  var len2 = b.len
  if len1 > len2:
    # make `b` the longer string
    return editDistance(b, a)

  # strip common prefix:
  var s = 0
  while a[s] == b[s] and a[s] != '\0':
    inc(s)
    dec(len1)
    dec(len2)

  # strip common suffix:
  while len1 > 0 and len2 > 0 and a[s+len1-1] == b[s+len2-1]:
    dec(len1)
    dec(len2)

  # trivial cases:
  if len1 == 0: return len2
  if len2 == 0: return len1

  # another special case:
  if len1 == 1:
    for j in s..s+len2-1:
      if a[s] == b[j]: return len2 - 1

    return len2

  inc(len1)
  inc(len2)
  var row: seq[int]
  newSeq(row, len2)

  for i in 0..len2 - 1: row[i] = i

  for i in 1 .. len1- 1:
    var char1 = a[s + i - 1]
    var prevCost = i - 1;
    var newCost = i;

    for j in 1 .. len2 - 1:
      var char2 = b[s + j - 1]

      if char1 == char2:
        newCost = prevCost
      else:
        newCost = min(newCost, min(prevCost, row[j])) + 1

      prevCost = row[j]
      row[j] = newCost

  result = row[len2 - 1]

proc calcScore(item, term:string):float =
  let dist = editDistance(item, term)
  (item.len - dist)/item.len

proc match2(item, term:string):seq[int] =
  var pos = 0
  let itemLower = item.tolower()
  for c in term.tolower():
    let p = itemLower.find(c, pos)
    if p == -1: 
      result.setlen(0)
      break
    pos = p
    result.add pos

#----------------------------------------------------------------
type
  FuzzyMatchResult* = tuple
    idx:int
    score:float
    report:string

proc fuzzyMatch*(items:openarray[string], term:string):seq[FuzzyMatchResult] =
  var termTrim = ""
  var hi:seq[int]
  for i, c in term:
    if c == ' ': continue
    if c == '\t': continue
    termTrim.add c
  for idx, item in items:
    if item.len < termTrim.len: continue
    let matched = match2(item, termTrim)
    if matched.len == 0: continue
    var report:string
    var posScore:float
    var pos:int
    var p0:int = 0
    for i, p1 in matched:
      let l = p1-p0-1
      pos += p1
      posScore += max(float(5-l)/float(5*(i+1)),0)
      let m = item[p0..p1-1]
      report.add m
      report.add "<b>"
      report.add item[p1..p1]
      report.add "</b>"
      p0 = p1+1

    report.add item[p0..^1]
    posScore = posScore/float(matched.len)
    let editScore = calcScore(item, term)
    let score = (posScore + editScore)/2
    result.add (idx, score, report)
    result.sort proc(a,b:FuzzyMatchResult):int =
      result = cmp(b[1], a[1])
      if result == 0:
        result = cmp(a[2],b[2])


#----------------------------------------------------------------
when isMainModule:
  var terms = @[
    "This is",
    "A Good1",
    "A Good3",
    "A Good24",
    "A bay is good",
    "Day to die"
  ]

  for v in fuzzyMatch( terms, "Ad"):
    echo v

  echo matchAsterisk("*.a", "b.a")
  echo matchAsterisk("b.a", "b.a")