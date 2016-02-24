# dice

A traditional dice game (1-6 per dice), played with 2 dice.

## randomness

The approach is adapted from what is employed in the [lottery](../lottery/README.md), so the reader should be familiar with that.

## matching

Sending a transaction with a value calls `enter(0)`, playing evens. Calling the `enter(sumOrRange)` function on the contract, allows for the following:

0, 1 = even sum & odd sum
2,3,4,5,6,7,8,9,10,11,12 = matches the exact number sum

For range combinations, specify the large number first

122 = between 12 and 2 (inclusive, 100% probability)
113 = between 11 and 3
104 = between 10 and 4
etc.

For ranges, large number is specified first, evaluating a range inclusiv of the min and max
