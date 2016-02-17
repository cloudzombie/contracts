// LooneyFifty pays out 50% of the relevant pool, 50% of the time
//
// git: https://github.com/thelooneyfarm/contracts/tree/master/src/fifty
// url: http://the.looney.farm/game/fifty
contract LooneyFifty {
  // modifier for the owner protected functions
  modifier owneronly {
    // yeap, you need to own this contract to action it
    if (msg.sender != owner) {
      throw;
    }

    // function execution inserted here
    _
  }

  // constants for the Lehmer RNGs
  uint constant private LEHMER_MOD = 4294967291;
  uint constant private LEHMER_MUL = 279470273;
  uint constant private LEHMER_SDA = 1299709;
  uint constant private LEHMER_SDB = 7919;

  // various game-related constants, also available in the interface
  uint constant public CONFIG_MAX_TICKETS = 999;
  uint constant public CONFIG_PRICE = 10 finney;
  uint constant public CONFIG_MIN_VALUE = CONFIG_PRICE;
  uint constant public CONFIG_MAX_VALUE = CONFIG_PRICE * CONFIG_MAX_TICKETS;
  uint constant public CONFIG_FEES_MUL = 5;
  uint constant public CONFIG_FEES_DIV = 1000;

  // store the owner and initialise the collectable owner fees
  address private owner = msg.sender;
  uint private fees = 0;

  // we have a random pool for each digit, i.e. 10 finney, 100 finney & 1 ether
  uint[3] private PRICES = [CONFIG_PRICE, CONFIG_PRICE * 10, CONFIG_PRICE * 100];
  uint[3] private pool = [0, 0, 0];

  // basic initialisation for the RNG, ready to go
  uint private random = uint(sha3(block.coinbase, block.blockhash(block.number - 1), now));
  uint private seeda = LEHMER_SDA;
  uint private seedb = LEHMER_SDB;

  // lifetime game stats
  uint public tktotal = 0;
  uint public tkwins = 0;
  uint public tklosses = 0;
  uint public turnover = 0;
  uint public txs = 0;

  // nothing much to do in the construction, we have the owner set & init done
  function LooneyFifty() {
  }

  // owner-only withdrawal function
  function ownerWithdraw() owneronly public {
    // if we have fees, send it to the owner and reset the count
    if (fees > 0) {
      owner.call.value(fees)();
      fees = 0;
    }
  }

  // calculate the next pseudo random number
  function randomize() private {
    // get the next Lehmer value
    seeda = (seeda * LEHMER_MUL) % LEHMER_MOD;

    // adjust the pseudo random number with Lehmer, pool info & blockchain details
    random ^= uint(sha3(block.coinbase, block.blockhash(block.number - 1), pool[0] + pool[1] + pool[2], seeda));
  }

  // play the actual round, allocating from the pools
  function play(uint input, uint number) private returns (uint) {
    // setup the player details, ether won, the number of wins & losses
    uint output = 0;
    uint pwins = 0;
    uint plosses = 0;

    // loop through each indivisula price pool, allocating the numbers
    for (uint pidx = 0; pidx < PRICES.length; pidx++) {
      // current lower digit has a ticket for each increment
      uint max = number % 10;

      // add the tickets to the overall totals
      tktotal += max;

      // allocate a win/loss for each increment we have here
      for (uint num = 0; num < max; num++) {
        // for the inner-loops, the second Lehmer generator comes into play
        seedb = (seedb * LEHMER_MUL) % LEHMER_MOD;
        random ^= seedb;

        // on even numbers, we considder a win, add some ether
        if (random % 2 == 0) {
          // grab 50% of the available pool and calculate the fees from it
          uint win = pool[pidx] / 2;
          uint fee = (win * CONFIG_FEES_MUL) / CONFIG_FEES_DIV;

          // allocate a win and adjust the pool, fees and return
          pwins += 1;
          pool[pidx] -= win;
          fees += fee;
          output += win - fee + PRICES[pidx];
        } else {
          // allocate a loss and increment the available digit pool
          plosses += 1;
          pool[pidx] += PRICES[pidx];
        }
      }

      // go for the next digit and record the transaction
      number = number / 10;
    }

    // adjust the overall wins & losses based on what the player did
    tkwins += pwins;
    tklosses += plosses;

    // let the world know we have another player
    notifyPlayer(pwins, plosses, input, output);

    return output;
  }

  // a very simple play interface, send it ether, it does the calculations - no ABI needed
  function() public {
    // we really only want to play with set amounts
    if (msg.value < CONFIG_MIN_VALUE) {
      throw;
    }

    // adjust the random numbers
    randomize();

    // the number of total plays (based on min tickets values)
    uint number = 0;

    // set to max if above max, or calculate the tickets based on the min price
    if (msg.value >= CONFIG_MAX_VALUE) {
      number = CONFIG_MAX_TICKETS;
    } else {
      number = msg.value / CONFIG_PRICE;
    }

    // input is the playable amount, overflow is the value to be returned, >max or not a multiple of min
    uint input = number * CONFIG_PRICE;

    // turnover increased, as did transactions
    turnover += input;
    txs += 1;

    // play whatever the player gave us, include overflow for send
    uint output = play(input, number) + (msg.value - input);

    // send whatever we have back to the player
    if (output > 0) {
      msg.sender.call.value(output)();
    }
  }

  // log events
  event Player(address addr, uint32 at, uint8 wins, uint8 losses, uint input, uint output, uint tkwins, uint tklosses, uint turnover);

  // notify that a new player has entered the fray
  function notifyPlayer(uint pwins, uint plosses, uint input, uint output) private {
    Player(msg.sender, uint32(now), uint8(pwins), uint8(plosses), input, output, tkwins, tklosses, turnover);
  }
}
