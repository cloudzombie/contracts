## lottery

Ethereum contract for [http://the.looney.farm/game/lottery](http://the.looney.farm/game/lottery)

### implementation notes

We are not using the stock-standard approach to sending value, i.e.

```
msg.sender.send(_value);
```

anywhere, rather we calling back into the sender with

```
msg.sender.call.value(_value)();
```

This approach is due to [Mist contract -> contract-based wallets transactions](https://github.com/ethereum/mist/issues/135) where Mist contract wallet sends may (and do) fail silently. Rather than not being able to return funds or warning against Mist, we took the view that it should always work for the user.

tl;dr - Sending from an etherbase account is fine, however mist wallets contract are not and fees cannot be returned


### random numbers

Randomness is always an issue on the Ethereum blockchain, so we should probably take some time to explain how we calculate some randomness. The basics of the approach is to use a Linear Congruential Generator, specifically the [Lehmer generator](https://en.wikipedia.org/wiki/Lehmer_random_number_generator) along with rolling values from the blockhash.

On initialization of the contracts, an initial random value is set to some value to provide a base to work from. Since payouts can't happen immediately, the randomness of this number is weak, however the miner, sender and now value is used to initialize it. In addition the Lehmer source (rngseed) is initialized to the same starting point

```
  uint constant private LEHMER_G = 279470273;
  uint constant private LEHMER_N = 4294967291;
  ...
  uint private random = uint(block.coinbase) ^ uint(msg.sender) ^ now;
  uint private rngseed = random;
```

After receiving a transaction and adding everything to the pool, the contract mutates the random number using the available blockhash information, the current random number and the next calculated `rndseed`.

```
  rngseed = (rngseed * LEHMER_G) % LEHMER_N;
  random = uint(sha3(block.blockhash(block.number - 1), random ^ rngseed));
```

With each transaction received, more entropy is added to the actual random number, with each previous value feeding back into the pool, both for the rngseed and random outcome. In this case results are a evolving based on the whole chain of transactions that has gone before.

When a winner is to be chosen, the random number chain is converted to a SHA3 and this value is used to calculate the winning outcome

```
  uint result = uint(sha3(random));
  uint winidx = tickets[result % numtickets];
```
