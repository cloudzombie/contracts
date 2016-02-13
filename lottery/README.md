## lottery

Ethereum contract for [http://the.looney.farm/game/lottery](http://the.looney.farm/game/lottery)

### implementation notes

We are not using the stock-standard approch to sending value, i.e.

```
msg.sender.send(_value);
```

anywhere, rather we calling back into the sender with

```
msg.sender.call.value(_value)();
```

This approach is due to [https://github.com/ethereum/mist/issues/135](https://github.com/ethereum/mist/issues/135) where Mist contract wallet sends may (and do) fail silently. Rather than not being able to return funds or warning against Mist, we took the view that it should always work for the user.

tl;dr - Sending from an etherbase account is fine, however mist wallets contract are not and fees cannot be returned


### random numbers

Randomness is always an issue on the Ethereum blockchain, so we should probably take some time to explain how we calculate some randomness.

On initialization of the contracts, the random seed is set to some value as a base. (As we will see later each iteration builds on this number so it is ever evolving with all new transactions)

```
  uint random = uint(block.coinbase) ^ uint(msg.sender) ^ now;
```

On receiving a transaction, the contract mutates the random number using available block information. The view was to do this after the transaction was received (i.e. the number cannot be changed), however with deep block inspection the stored contract data can be found, so the best approach is to mutate before doing anything else

```
  random = random ^ uint(sha3(block.blockhash(block.number - 1), uint(block.coinbase) ^ uint(msg.sender) ^ now));
```

The above happens with each transaction received, adding more entropy to the actual random number. Basically the seed continues building with each oppportunity it gets. This removes one vector of attack where the numbers aren't independent, rather it is a result of the whole chain of transactions that has gone before it.

When a winner is to be chosen, the random number is first updated (as above) and then the result is calculated. This result is used to pick the outcome

```
  uint result = uint(sha3(random ^ this.balance));
```
