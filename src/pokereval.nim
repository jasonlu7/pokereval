const
  RecalculatePerfHashOffsets = false

import pokereval/hand, pokereval/perfhashoffsets
export hand

when RecalculatePerfHashOffsets:
  import algorithm, strutils

const
  RankCount = 13
  FlushRanks: array[13, uint32] = [1'u32, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096]
  FlushLookupSize = 8192
  LookupSize = 86547
  # More rows means slightly smaller lookup table but much bigger offset table.
  PerfHashRowShift = 12

  HandCategoryOffset: uint16 = 0x1000 # 4096
  HighCardOffset: uint16 = 1 * HandCategoryOffset
  PairOffset: uint16 = 2 * HandCategoryOffset
  TwoPairOffset: uint16 = 3 * HandCategoryOffset
  ThreeOfKindOffset: uint16 = 4 * HandCategoryOffset
  StraightOffset: uint16 = 5 * HandCategoryOffset
  FlushOffset: uint16 = 6 * HandCategoryOffset
  FullHouseOffset: uint16 = 7 * HandCategoryOffset
  FourOfKindOffset: uint16 = 8 * HandCategoryOffset
  StraightFlushOffset: uint16 = 9 * HandCategoryOffset

when RecalculatePerfHashOffsets:
  type
    HandEvaluator = ref object
      flushLookup: array[FlushLookupSize, uint16]
      lookup: array[1_000_000, uint16]
      perfHashOffsets: array[100_000, uint32]
      origLookup: array[MaxKey + 1, uint16]
  const
    PerfHashColumnMask: uint32 = (1 shl PerfHashRowShift) - 1
else:
  type
    HandEvaluator* = ref object
      flushLookup: array[FlushLookupSize, uint16]
      lookup: array[LookupSize, uint16]

proc perfHash(key: uint32): uint32 =
  assert(key <= MaxKey)
  key + PerfHashOffsets[key shr PerfHashRowShift]

proc getKey(ranks: uint64, flush: bool): uint32 =
  # calculate lookup table key from rank counts
  for r in 0..<RankCount:
    result += uint32((ranks shr (r * 4)) and 0xf) * (if flush: FlushRanks[r] else: uint32(RankMultipliers[r]))

proc getBiggestStraight(ranks: uint64): int =
  let rankMask = (0x1111111111111'u64 and ranks) or ((0x2222222222222'u64 and ranks) shr 1) or ((0x4444444444444'u64 and ranks) shr 2)
  for i in countdown(8, 0):
    if ((rankMask shr (4 * i)) and 0x11111'u64) == 0x11111'u64:
      return i + 4
  if (rankMask and 0x1000000001111'u64) == 0x1000000001111'u64:
    return 3
  return 0

proc populateLookup(eval: HandEvaluator, ranks: uint64, ncards: int,
                    handValue: uint16, endRank: int, maxPair: int,
                    maxTrips: int, maxStraight: int, flush: bool): uint16 =
  # iterates recursively over the remaining cards in a hand and
  # writes the hand values for each combination to lookup table.
  # Parameters maxPair, maxTrips, maxStraight are used for checking that the hand 
  # doesn't improve.
  
  # only increment hand value counter for every valid 5 card combination
  var handValue = if ncards <= 5: handValue + 1 else: handValue

  # write hand value to lookup
  var key = getKey(ranks, flush)
  when RecalculatePerfHashOffsets:
    if flush:
      eval.flushLookup[key] = handValue
    else:
      eval.origLookup[key] = handValue
  else:
    if flush:
      eval.flushLookup[key] = handValue
    else:
      assert(eval.lookup[perfHash(key)] == 0 or eval.lookup[perfHash(key)] == handValue, "handValue mismatch in lookup")
      eval.lookup[perfHash(key)] = handValue

  if ncards == 7:
    return handValue

  # iterate next card rank and recurse
  for r in 0..<endRank:
    var newRanks = ranks + (1'u64 shl (4 * r))
    # check that hand doesn't improve
    var rankCount = uint(((newRanks shr (r * 4)) and 0xf))
    if rankCount == 2 and r >= maxPair:
      continue
    if rankCount == 3 and r >= maxTrips:
      continue
    if rankCount >= 4: # don't allow new quads
      continue
    if getBiggestStraight(newRanks) > maxStraight:
      continue

    handValue = eval.populateLookup(newRanks, ncards + 1, handValue, r + 1, maxPair, maxTrips, maxStraight, flush)

  return handValue

when RecalculatePerfHashOffsets:
  proc calculatePerfHashOffsets(eval: HandEvaluator) =
    # store locations of all non-zero elements in original lookup table, divided into rows.
    var rows: seq[tuple[idx: uint32, keys: seq[uint32]]]
    for i in 0..MaxKey:
      if eval.origLookup[i] != 0:
        let rowIdx = int(i shr PerfHashRowShift)
        if rowIdx >= rows.len:
          rows.setLen(rowIdx + 1)
        rows[rowIdx].keys.add(uint32(i))
  
    # store the original row indices because we need them after sorting
    for i in 0..<rows.len:
      rows[i].idx = uint32(i)
  
    # sort rows by descending size
    rows.sort(proc(x, y: tuple[idx: uint32, keys: seq[uint32]]):int = cmp(x.keys.len, y.keys.len), Descending)
  
    # for each row, find (using brute force) the first offset that doesn't cause a collision with previous rows.
    var maxIdx: uint32 = 0
    for i in 0..<rows.len:
      var offset: uint32 = 0
      while true:
        var ok = true
        for key in rows[i].keys:
          let val = eval.lookup[(key and PerfHashColumnMask) + offset]
          if val != 0 and val != eval.origLookup[key]: # collision
            ok = false
            break
        if ok:
          break
        offset += 1
      # echo "row: ", i, " size: ", rows[i].keys.len, " offset: ", offset
      eval.perfHashOffsets[rows[i].idx] = offset - (rows[i].idx shl PerfHashRowShift)
      for key in rows[i].keys:
        let newIdx = (key and PerfHashColumnMask) + offset
        maxIdx = max(maxIdx, newIdx)
        eval.lookup[newIdx] = eval.origLookup[key]
  
    # output offset array
    echo "offsets: "
    for i in 0..<rows.len:
      if i mod 8 == 0:
        stdout.write "\n"
      stdout.write "0x", eval.perfHashOffsets[i].toHex, "'u32, "
    stdout.write "\n"

proc newHandEvaluator*(): HandEvaluator =
  result = HandEvaluator()
  # initialize lookup tables
  # high card
  var handValue: uint16 = HighCardOffset
  handValue = result.populateLookup(0, 0, handValue, RankCount, 0, 0, 0, false)

  # pair
  handValue = PairOffset
  for r in 0..<RankCount:
    handValue = result.populateLookup(2'u64 shl (4*r), 2, handValue, RankCount, 0, 0, 0, false)

  # two pair
  handValue = TwoPairOffset
  for r1 in 0..<RankCount:
    for r2 in 0..<r1:
      handValue = result.populateLookup((2'u64 shl (4*r1)) + (2'u64 shl (4*r2)), 4, handValue, RankCount, r2, 0, 0, false)

  # trips
  handValue = ThreeOfKindOffset
  for r in 0..<RankCount:
    handValue = result.populateLookup(3'u64 shl (4*r), 3, handValue, RankCount, 0, r, 0, false)

  # straight
  handValue = StraightOffset
  handValue = result.populateLookup(0x1000000001111'u64, 5, handValue, RankCount, RankCount, RankCount, 3, false) # wheel
  for r in 4..<RankCount:
    handValue = result.populateLookup(0x11111'u64 shl (4*(r-4)), 5, handValue, RankCount, RankCount, RankCount, r, false)

  # flush
  handValue = FlushOffset
  handValue = result.populateLookup(0, 0, handValue, RankCount, 0, 0, 0, true)

  # full house
  handValue = FullHouseOffset
  for r1 in 0..<RankCount:
    for r2 in 0..<RankCount:
      if r1 != r2:
        handValue = result.populateLookup((3'u64 shl (4*r1)) + (2'u64 shl (4*r2)), 5, handValue, RankCount, r2, r1, RankCount, false)

  # quads
  handValue = FourOfKindOffset
  for r in 0..<RankCount:
    handValue = result.populateLookup(4'u64 shl (4*r), 4, handValue, RankCount, RankCount, RankCount, RankCount, false)

  # straight flush
  handValue = StraightFlushOffset
  handValue = result.populateLookup(0x1000000001111'u64, 5, handValue, RankCount, 0, 0, 3, true) # wheel
  for r in 4..<RankCount:
    handValue = result.populateLookup(0x11111'u64 shl (4*(r-4)), 5, handValue, RankCount, 0, 0, r, true)

  when RecalculatePerfHashOffsets:
    result.calculatePerfHashOffsets()

proc evaluate*(eval: HandEvaluator, hand: Hand): int =
  if hand.hasFlush:
    let key = hand.flushKey
    return int(eval.flushLookup[key])
  else:
    let key = hand.rankKey
    return int(eval.lookup[perfHash(key)])
