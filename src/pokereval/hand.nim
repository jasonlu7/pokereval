import tables, bitops

# structure that combines data from multiple cards so that hand strength can be evaluated efficiently
type
  Hand* = object
    # bits 0-31: key to non-flush lookup table
    # bits 32-35: card counter
    # bits 48-63: suit counters
    key: uint64
    # bit mask for all cards
    mask: uint64

# combine two hands
proc `+`(x, y: Hand): Hand =
  assert((x.mask and y.mask) == 0, "When combining two hands, they must contain disjoint cards")
  result.key = x.key + y.key
  result.mask = (x.mask or y.mask)


const
  RankTable = {'2': 0, '3': 1, '4': 2, '5': 3, '6': 4, '7': 5, '8': 6, '9': 7, 'T': 8, 'J': 9, 'Q': 10, 'K': 11, 'A': 12}.toTable
  SuitTable = {'s': 0, 'h': 1, 'd': 2, 'c': 3}.toTable
  CardCountShift = 32
  SuitsShift = 48
  # Rank multipliers that guarantee a unique key for every rank combination in a 0-7 card hand.
  RankMultipliers* = [0x2000'u64, 0x8001'u64, 0x11000'u64, 0x3a000'u64, 0x91000'u64, 0x176005'u64, 0x366000'u64,
    0x41a013'u64, 0x47802e'u64, 0x479068'u64, 0x48c0e4'u64, 0x48f211'u64, 0x494493'u64]
  MaxKey* = 4 * RankMultipliers[12] + 3 * RankMultipliers[11]
  FlushCheckMask = 0x8888'u64 shl SuitsShift
  # Hand object for a hand with no cards. A valid Hand object must contain EmptyHand exactly once!
  EmptyHand = Hand(key: 0x3333'u64 shl SuitsShift, mask: 0)

proc getCardConstants(): Table[string, Hand] =
  # returns table of card string to Hand object for that card
  for rank, rankval in RankTable:
    for suit, suitval in SuitTable:
      result[rank & suit] = Hand(key: (1'u64 shl (4 * suitval + SuitsShift)) + (1'u64 shl CardCountShift) + RankMultipliers[rankval],
                                 mask: 1'u64 shl ((3 - suitval) * 16 + rankval))

const CardConstants = getCardConstants()

proc newHand*(cards: seq[string]): Hand =
  assert(cards.len <= 7, "Hand can contain at most 7 cards")
  result = EmptyHand
  for card in cards:
    result = result + CardConstants[card]

proc hasFlush*(hand: Hand): bool {.inline.} =
  (hand.key and FlushCheckMask) != 0

proc rankKey*(hand: Hand): uint32 {.inline.} =
  # Returns a 32 bit key that is unique for each card rank combination.
  uint32(hand.key)

proc flushKey*(hand: Hand): uint16 =
  # returns card mask for suit that has 5 or more cards
  let flushCheckBits: uint32 = uint32((hand.key and FlushCheckMask) shr CardCountShift)
  let shift = countLeadingZeroBits(flushCheckBits) shl 2
  uint16(hand.mask shr shift)
