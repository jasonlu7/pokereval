# pokereval
A nim poker hand evaluator for Texas Hold'em poker.
This is a nim rewrite of [OMPEval](https://github.com/zekyll/OMPEval).

It evaluates hands with 0 to 7 cards (hands with less than 5 cards are filled in with the worst kicker).

## Usage

```
import pokereval

let eval = newHandEvaluator()
echo eval.evaluate(newHand(@["Ad", "As", "2s", "2h", "2c"]))
```
