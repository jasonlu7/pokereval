import unittest
import pokereval

const
  HandCategoryOffset: int = 0x1000 # 4096
  HandCategoryShift = 12
  ranks = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A']
  suits = ['s', 'h', 'd', 'c']

proc intToCard(i: int): string =
  ranks[i div 4] & suits[i mod 4]

proc enumerate(counts: var array[10, int], eval: HandEvaluator, cardsLeft: int, cards: seq[string] = @[], start: int = 0) =
  for i in start..<52:
    if cardsLeft == 1:
      counts[eval.evaluate(newHand(cards & @[intToCard(i)])) shr HandCategoryShift] += 1;
    else:
      enumerate(counts, eval, cardsLeft-1, cards & @[intToCard(i)], i + 1)

proc run() =
  suite "handevaluator test":
    setup:
      var eval = newHandEvaluator()

    test "0 cards":
      let v = eval.evaluate(newHand(@[]))
      check v == HandCategoryOffset + 1

    test "enumerate 1 card hands":
      let expected = [0, 52, 0, 0, 0, 0, 0, 0, 0, 0]
      var v: array[10, int]
      enumerate(v, eval, 1)
      for i in 0..<10:
        check v[i] == expected[i]

    test "enumerate 2 card hands":
      let expected = [0, 1248, 78, 0, 0, 0, 0, 0, 0, 0]
      var v: array[10, int]
      enumerate(v, eval, 2)
      for i in 0..<10:
        check v[i] == expected[i]

    test "enumerate 3 card hands":
      let expected = [0, 18304, 3744, 0, 52, 0, 0, 0, 0, 0]
      var v: array[10, int]
      enumerate(v, eval, 3)
      for i in 0..<10:
        check v[i] == expected[i]

    test "enumerate 4 card hands":
      let expected = [0, 183040, 82368, 2808, 2496, 0, 0, 0, 13, 0]
      var v: array[10, int]
      enumerate(v, eval, 4)
      for i in 0..<10:
        check v[i] == expected[i]

    test "enumerate 5 card hands":
      let expected = [0, 1302540, 1098240, 123552, 54912, 10200, 5108, 3744, 624, 40]
      var v: array[10, int]
      enumerate(v, eval, 5)
      for i in 0..<10:
        check v[i] == expected[i]

    test "enumerate 6 card hands":
      let expected = [0, 6612900, 9730740, 2532816, 732160, 361620, 205792, 165984, 14664, 1844]
      var v: array[10, int]
      enumerate(v, eval, 6)
      for i in 0..<10:
        check v[i] == expected[i]

    test "enumerate 7 card hands":
      let expected = [0, 23294460, 58627800, 31433400, 6461620, 6180020, 4047644, 3473184, 224848, 41584]
      var v: array[10, int]
      enumerate(v, eval, 7)
      for i in 0..<10:
        check v[i] == expected[i]

run()
