# lottery

Ethereum contract for [http://the.looney.farm/game/lottery](http://the.looney.farm/game/lottery). For the currently deployed version (as compiled), you can verify the [compiler outputs](verify.md)


## implementation notes

We are not using the stock-standard approach to sending value, i.e.

```
msg.sender.send(_value);
```

anywhere, rather we calling back into the sender with

```
msg.sender.call.value(_value)();
```

This approach is due to [Mist contract -> contract-based wallets transactions](https://github.com/ethereum/mist/issues/135) where Mist contract wallet sends may (and do) fail silently. Rather than not being able to return funds or warning against Mist, we took the view that it should always work for the user.

tl;dr - Sending from an etherbase account is fine, however Mist wallets contract are not and fees cannot be returned


## random numbers

Randomness is always an issue on the Ethereum blockchain, with a distributed environment along with the deterministic nature of random number generators. The basics of our approach is to use a Linear Congruential Generator, specifically the [Lehmer generator](https://en.wikipedia.org/wiki/Lehmer_random_number_generator) along with values from the coinbase, blockhash and previous iterations.

### initialization

On initialization of the contracts, an initial result value is set to provide a base to work from. Since payouts can't happen immediately and the first transactions will start mutations, we initialize this part of the seed with the coinbase, blockhash (previous) and timestamp.

We utilize 2 Lehmer generators, seeda is always calculated and used in the current block, seedb is calculated and stored for use in the next block. For the Lehmer generators, we start with seed values of [1299709 (100,000th prime)](http://www.isprimenumber.com/prime/1299709) and [7919 (1,000th prime)](http://www.isprimenumber.com/prime/7919).

```
  uint private result = uint(sha3(block.coinbase, block.blockhash(block.number - 1), now));
  uint private seeda = LEHMER_SDA;
  uint private seedb = LEHMER_SDB;
```

### calculation

After receiving a transaction, the contract mutates the result number using the coinbase, previous blockhash, the previous & next calculated Lehmer numbers and the current balance.

```
  seeda = (seeda * LEHMER_MUL) % LEHMER_MOD;
  result ^= uint(sha3(block.coinbase, block.blockhash(block.number - 1), seeda, seedb));
  seedb = (seedb * LEHMER_MUL) % LEHMER_MOD;

  ...

  uint winidx = tickets[result % numtickets];
```

With each transaction received, more entropy is added to the actual random number, with each previous value feeding back into the pool, both for the Lehmer generators and resulting outcome. In this case results are always evolving based on the whole chain of transactions that has gone before.

When a winner is to be chosen, the result number chain is used to determine the ticket index of the final winner.

### notes

- Miners can still choose to not mine a specific block when the outcome detracts from their expectations
- Any pseudo random sequence, i.e. Lehmer, is based on the initial seeds and deterministic in nature, by design
- Users can provide extra entropy by sending values not a multiple of the ticket price, i.e. 0.011 ether will add to the balance and influence the result, while the extra 0.001 will be returned
