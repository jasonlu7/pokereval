# pokereval
A nim poker hand evaluator for Texas Hold'em poker.
This is a nim rewrite of [OMPEval](https://github.com/zekyll/OMPEval).

It evaluates hands with 0 to 7 cards (hands with less than 5 cards are filled in with the worst kicker).

The evaluator gives a hand an integer ranking; higher rankings correspond to better hands.
The ranking divided by 4096 also gives the hand category (e.g. high card, flush).

## Installation
```
nimble install pokereval
```

## Usage

```nim
import pokereval

let eval = newHandEvaluator()
echo eval.evaluate(newHand(@["Ad", "As", "2s", "2h", "2c"]))
```
