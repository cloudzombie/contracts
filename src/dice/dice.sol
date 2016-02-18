// LooneyDice is a traditional dice-game (ala craps) allowing players to play market-makers as well
//
// git: https://github.com/thelooneyfarm/contracts/tree/master/src/dice
// url: http://the.looney.farm/game/dice
contract LooneyDice {
  // modifier for the owner protected functions
  modifier owneronly {
    // yeap, you need to own this contract to action it
    if (msg.sender != owner) {
      throw;
    }

    // actual execution goes here
    _
  }

  // store the actual market-makers in the contract, so we know how much and who
  struct MM {
    address addr;
    uint value;
  }

  // for each type of bet, we need to store the odds and type/testindex
  struct Test {
    uint8 chance;
    uint8 test;
  }

  // number of different combinations for 2 six-sided dice
  uint constant private MAX_ROLLS = 6 * 6;

  // game configuration, also available extrenally for queries
  uint constant public CONFIG_MIN_VALUE = 10 finney;
  uint constant public CONFIG_MAX_VALUE = 1 ether;
  uint constant public CONFIG_MIN_FUNDS = 1 ether;
  uint constant public CONFIG_MAX_FUNDS = 100 ether;
  uint constant public CONFIG_RETURN_MUL = 99; // 99/100 return, the 1% is the market-maker edge
  uint constant public CONFIG_RETURN_DIV = 100;
  uint constant public CONFIG_FEES_MUL = 5; // 5/1000, the 0.5% goes to the owner (comm only on winnings)
  uint constant public CONFIG_FEES_DIV = 1000;
  uint constant public CONFIG_DICE_SIDES = 6;

  // configuration for the Lehmer RNG
  uint constant private LEHMER_MOD = 4294967291;
  uint constant private LEHMER_MUL = 279470273;
  uint constant private LEHMER_SDA = 1299709;
  uint constant private LEHMER_SDB = 7919;

  // the owner address as well as the owner-applicable fees
  address private owner = msg.sender;
  uint private fees = 0;

  // initialize the pseudo RNG, ready to rock & roll
  uint private random = uint(sha3(block.coinbase, block.blockhash(block.number - 1), now));
  uint private seeda = LEHMER_SDA;
  uint private seedb = LEHMER_SDB;

  // dices, both not initialized
  uint[2] private dices = [0, 0];

  // based on the type of bet (Even, Odd, Seven, etc.) map to the applicable test with odds
  mapping (byte => Test) private tests;

  // the market-makers and profits for each of them
  MM[] public mms;
  mapping (address => uint) public profits;

  // publically available contract information
  uint public mmidx = 0;
  uint public funds = 0;
  uint public turnover = 0;
  uint public wins = 0;
  uint public losses = 0;
  uint public txs = 0;

  // basic constructor, since the initial values are set, just do something for the test/bet types
  function LooneyDice() {
    initTests();
  }

  // allow the owner to withdraw his/her fees
  function ownerWithdraw() owneronly public {
    // send any fees we have and result the value back
    if (fees > 0) {
      owner.call.value(fees)();
      fees = 0;
    }
  }

  // internal function that adds funds into the funding queue
  function addFunds(address funder, uint value) private returns (uint) {
    // we may have an overflow (i.e. > max), track it
    uint overflow = 0;

    // do we have something here, if so start allocation
    if (value > 0) {
      // more than max available, grab what we can and set the rest as overflow
      if (value > CONFIG_MAX_FUNDS) {
        overflow = value - CONFIG_MAX_FUNDS;
        value = CONFIG_MAX_FUNDS;
      }

      // allocate the value to the overall available pool
      funds += value;

      // add the funder into our funding array, FIFO
      mms.push(MM({ addr: msg.sender, value: value }));

      // initialize the profit pool as required
      if (profits[msg.sender] == 0) {
        profits[msg.sender] = 0;
      }
    }

    // return the overflow value, to be send/not touched/etc.
    return overflow;
  }

  // allow market-makers to add funds that is to be used for bet matching
  function invest() public {
    // we need a minimum amount to allow the funding to take place
    if (msg.value < CONFIG_MIN_FUNDS) {
      throw;
    }

    // add the funds to the queue
    uint overflow = addFunds(msg.sender, msg.value);

    // transfer any amounts >max back to the market-maker
    if (overflow > 0) {
      msg.sender.call.value(overflow)();
    }
  }

  // allow any winnings & matched amounts to be re-invested
  function investProfit() public {
    // if we don't have enough, don't do this
    if (profits[msg.sender] < CONFIG_MIN_FUNDS) {
      throw;
    }

    // take any overflow value and keep it as profits for the market maker
    profits[msg.sender] = addFunds(msg.sender, profits[msg.sender]);
  }

  // allow market-makers to withdraw their profits
  function withdrawProfit() public {
    // see what they have in the kitty
    uint value = profits[msg.sender];

    // if we have something real, send it back
    if (value > 0) {
      msg.sender.call.value(value)();
      profits[msg.sender] = 0;
    }
  }

  // intialize the tests, done here so it is close to the actual test execution
  function initTests() private {
    // key = 'bet type', odds = <odds>/36 occurences (return), test is the value to be tested

    // evens & odds, both 18/36 chance
    tests['E'] = Test({ chance: 18, test: 0 });
    tests['O'] = Test({ chance: 18, test: 1 });

    // 2-12 (no coincidence it is at same idx), chance peaks at 7, then decreases to max
    tests['2'] = Test({ chance: 1, test: 2 });
    tests['3'] = Test({ chance: 2, test: 3 });
    tests['4'] = Test({ chance: 3, test: 4 });
    tests['5'] = Test({ chance: 4, test: 5 });
    tests['6'] = Test({ chance: 5, test: 6 });
    tests['7'] = Test({ chance: 6, test: 7 });
    tests['8'] = Test({ chance: 5, test: 8 });
    tests['9'] = Test({ chance: 4, test: 9 });
    tests['0'] = Test({ chance: 3, test: 10 });
    tests['1'] = Test({ chance: 2, test: 11 });
    tests['X'] = Test({ chance: 1, test: 12 });

    // >7 & <7, both 15/36 chance
    tests['>'] = Test({ chance: 15, test: 13 });
    tests['<'] = Test({ chance: 15, test: 14 });

    // aliasses
    tests['e'] = tests['E'];
    tests['o'] = tests['O'];
    tests[':'] = tests['2'];
    tests['%'] = tests['2'];
    tests['='] = tests['7'];
    tests['x'] = tests['X'];
  }

  // calculates the winner based on inputs & test
  function isWinner(Test test) private returns (bool) {
    // ok, this is the sum, I'm sure it is useful
    uint sum = dices[0] + dices[1];

    // number matching
    if (test.test >= 2 && test.test <= 12) {
      return sum == test.test;
    }

    // greater-than
    if (test.test == 13) {
      return sum > 7;
    }

    // less-than
    if (test.test == 14) {
      return sum < 7;
    }

    // odd & even
    return (sum % 2) == test.test;
  }

  // set the random number generator for the specific generation
  function randomize() private {
    // calculate the next number from the pseudo Lehmer sequence
    seeda = (seeda * LEHMER_MUL) % LEHMER_MOD;

    // adjust the overall random value, taking the seed, available funds & block details into account
    random ^= uint(sha3(block.coinbase, block.blockhash(block.number - 1), funds, seeda));

    // we have 2 dices, roll both
    for (uint idx = 0; idx < 2; idx++) {
      // adjust this Lehmer pseudo generator to the next value
      seedb = (seedb * LEHMER_MUL) % LEHMER_MOD;

      // adjust the overall random number based on the Lehmer input value
      random ^= seedb;

      // get the number of the side represented
      dices[idx] = (random % CONFIG_DICE_SIDES) + 1;
    }
  }

  // distribute fees, grabbing from the market-makers, allocating wins/losses as applicable
  function play(uint input) private returns (uint) {
    // grab the bet from the message and set the accociated test
    byte bet = msg.data[0];
    Test test = tests[bet];

    // if the odds are not >0, it means we don't have a valid bettype, fall back to evens
    if (test.chance == 0) {
      test = tests['E'];
      bet = 'E';
    }

    // see if we have an actual winner here
    bool winner = isWinner(test);

    // grab the current funder in the queue
    MM funder = mms[mmidx];

    // NOTE: odds used as in divisor, i.e. evens = 36/18 = 200%, however input also gets added, so adjust
    // output is 99% of the actual expected return (still lower than casinos)
    uint output = ((((input * MAX_ROLLS) / test.chance) - input) * CONFIG_RETURN_MUL) / CONFIG_RETURN_DIV;
    uint overflow = 0;

    // ummm, expected >available, just grab what we can from this market-maker
    if (output >= funder.value) {
      // calculate the new partial input value
      uint partial = (input * funder.value) / output;

      // ok, so now the output is only what the funder has in the pot
      output = funder.value;

      // set the overflows and new input
      overflow = input - partial;
      input = partial;

      // we need to move to the next market-maker
      mmidx++;
    }

    // remove the mathed bets from funds & funder (BetFair-like, when matched amount is not available anymore)
    funds -= output;
    funder.value -= output;

    // we will need to calculate the owner fees, either way
    uint fee = 0;
    uint result = 0;

    // winning or losing outcome here?
    if (winner) {
      // calculate the fees only on the won portion of the bet
      fee = (output * CONFIG_FEES_MUL) / CONFIG_FEES_DIV;

      // use the overflow value to return
      result = output + input - fee;

      // we have one more win for the contract
      wins += 1;
    } else {
      // fees are only applied to the actual profits made, not the total
      fee = (input * CONFIG_FEES_MUL) / CONFIG_FEES_DIV;

      // move the matched part & actual profit (- fee) to the profit pool for the funder
      profits[funder.addr] += output + input - fee;

      // one more loss for the record books
      losses++;
    }

    // fees go to the owner
    fees += fee;

    // one more transaction & input climbing up
    turnover += input;
    txs += 1;

    // notify the world of this outcome
    notifyPlayer(bet, winner, input, result);

    // ok, this is now what we owe the player
    return result + overflow;
  }

  // a simple sendTransaction with data (optional) is enought to drive the contract
  function() public {
    // we need to comply with the actual minimum values to be allowed to play
    if (msg.value < CONFIG_MIN_VALUE) {
      throw;
    }

    // erm, failsafe for when there are no MM funders available :(
    if (mmidx == mms.length) {
      throw;
    }

    // fire up the random generator, we need some entropy in here
    randomize();

    // store the actual overflow and input value as sent by the user
    uint output = 0;
    uint input = msg.value;

    // erm, more than we allow, set to the cap and make ready to return the extras
    if (input > CONFIG_MAX_VALUE) {
      input = CONFIG_MAX_VALUE;
      output = msg.value - CONFIG_MAX_VALUE;
    }

    // adjust the actual return value to send to the player
    output += play(input);

    // do we need to send the player some ether, do it
    if (output > 0) {
      msg.sender.call.value(output)();
    }
  }

  // log events
  event Player(address addr, uint32 at, byte bet, uint8 dicea, uint8 diceb, bool winner, uint input, uint output, uint funds, uint txs, uint turnover);

  // send the player event, i.e. somebody has played, this is what he/she/it did
  function notifyPlayer(byte bet, bool winner, uint input, uint output) private {
    Player(msg.sender, uint32(now), bet, uint8(dices[0]), uint8(dices[1]), winner, input, output, funds, txs, turnover);
  }
}
