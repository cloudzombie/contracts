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

Randomness is always an issue on the Ethereum blockchain, so we should probably take some time to explain how we calculate some randomness. The basics of the approach is to use a Linear Congruential Generator, specifically the [Lehmer generator](https://en.wikipedia.org/wiki/Lehmer_random_number_generator) along with values from the blockhash and previous calculations.

On initialization of the contracts, an initial result value is set to provide a base to work from. Since payouts can't happen immediately, the randomness of this number can be weak, so we allow initialization with the mining timestamp.

For the Lehmer generator, all starting values needs to be a co-prime to the modulus N, to comply with no room for error, we start with X as a prime, [522227](http://www.isprimenumber.com/prime/522227). In this case, choosing any number >0 should work with the chosen G & N values since they are co-primes, and suggested defaults with proper statistical properties.

```
  uint constant private LEHMER_G = 279470273;
  uint constant private LEHMER_N = 4294967291;
  uint constant private LEHMER_X = 522227;
  ...
  uint private result = now;
  uint private lehmer = LEHMER_X;
```

After receiving a transaction, the contract mutates the result number using as hash of the available/previous blockhash, the current result and the next calculated Lehmer number.

```
  lehmer = (lehmer * LEHMER_G) % LEHMER_N;
  result = uint(sha3(block.blockhash(block.number - 1), result, lehmer));
```

With each transaction received, more entropy is added to the actual random number, with each previous value feeding back into the pool, both for the Lehmer value and resulting outcome. In this case results are evolving based on the whole chain of transactions that has gone before.

When a winner is to be chosen, the result number chain is used to determine the ticket index of the final winner

```
  uint winidx = tickets[result % numtickets];
```
