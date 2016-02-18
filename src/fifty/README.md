# fifty

Ethereum contract for the [Looney Fifty](http://the.looney.farm/game/fifty). For the currently deployed version (as compiled), you can verify the [compiler outputs](verify.md)

## randomness

The approach is adapted from what is employed in the [lottery](../lottery/README.md), so the reader should be familiar with that.

Two Lehmer generators are used, the first running for each transaction received combining the long-running result with a mix from the coinbase and blockhash, the second for executes for each play that occurs within the transaction, adapting the overall running result chain.

```
  seeda = (seeda * LEHMER_MUL) % LEHMER_MOD;
  result ^= uint(sha3(block.coinbase, block.blockhash(block.number - 1), pool[0] + pool[1] + pool[2], seeda));
  ...
  for (uint num = 0; num < number; num++) {
    seedb = (seedb * LEHMER_MUL) % LEHMER_MOD;
    result ^= seedb;

    if (result % 2 == 0) {
      ...
```

## events

The NextPlayer event gets sent when each transaction has been evaluated, with the input amount, output (win/loss) as well as the number of overall bets placed and the overall wins.

## pools

This contract utilizes 3 separate pools - one for bets (and parts of bets) <= 0.09 ether with a ticket size of 0.01 ether. A second pool is utilized for values in multiples of 0.1 ether and a third for multiples of 1 ether.
