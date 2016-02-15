# fifty

Ethereum contract for the [Looney Fifty](http://the.looney.farm/game/fifty)

## randomness

The approach is adpated from what is employed in the [lottery](../lottery/README.md), so the reader should be familiar with that.

Two Lehmer generators are used, the first running for each transaction received combining the long-running result with a mix from the coinbase and blockhash, the second for executes for each play that occurs within the transaction, adapting the overall running result chain.

```
  seeda = (seeda * LEHMER_MUL) % LEHMER_MOD;
  result = result ^ uint(sha3(block.coinbase, block.blockhash(block.number - 1), pool, seeda));
  ...
  for (uint num = 0; num < number; num++) {
    seedb = (seedb * LEHMER_MUL) % LEHMER_MOD;
    result = result ^ seedb;

    if (result % 2 == 0) {
      ...
```

## events

The NextPlayer event gets sent when each transaction has been evaluated, with the input amount, output (win/loss) as well as the current pool size.

```
  event NextPlayer(address addr, uint32 at, uint input, uint output, uint pool);
```
