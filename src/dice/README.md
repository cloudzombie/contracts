# dice

A traditional dice game (1-6 per dice), played with 2 dice. For the currently deployed version (as compiled), you can verify the [compiler outputs](verify.md)

## randomness

In addition to using available details such as the blockhash, current pool, the miner address to adapt the generator chain, 2 Lehmer deterministic generators are used. The first Lehmer adapts the overall seed based on the block info and the continuous running values mutated from the start of the contract.

```
// calculate the next number from the pseudo Lehmer sequence
seeda = (seeda * LEHMER_MUL) % LEHMER_MOD;

// adjust the overall random value, taking the seed, available funds & block details into account
random ^= uint(sha3(block.coinbase, block.blockhash(block.number - 1), funds, seeda));
```

The second Lehmer adapts the random chain on a per dice-roll basis.

```
// adjust this Lehmer pseudo generator to the next value
seedb = (seedb * LEHMER_MUL) % LEHMER_MOD;

// adjust the overall random number based on the Lehmer input value
random ^= seedb;

// return the number of the side represented
```

The approach is adapted from what is employed in the [lottery](../lottery/README.md).

## matching

Sending a transaction with a value calls `enter(0)`, playing evens. Calling the `enter(sumOrRange)` function on the contract, allows for the following:

0, 1 = even sum & odd sum
2,3,4,5,6,7,8,9,10,11,12 = matches the exact number sum

For range combinations, specify the large number first

122 = between 12 and 2 (inclusive, 100% probability)
113 = between 11 and 3
104 = between 10 and 4
etc.

For ranges the large number always needs to be specified first (42 is valid, 24 is not), and the range is evaluated inclusive of the min and max values specified.
