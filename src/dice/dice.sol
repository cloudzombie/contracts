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

  // for each type of bet, chance = <odds>/36 occurences (return), test is the value to be tested
  struct Test {
    uint bet;
    uint chance;
    uint test;
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
  uint constant public CONFIG_FEES_MUL = 1; // 5/1000 = 1/200, the 0.5% goes to the owner (comm only on winnings)
  uint constant public CONFIG_FEES_DIV = 200; // 5/1000 = 1/200, divisor
  uint constant public CONFIG_DICE_SIDES = 6;

  // go old-skool here to save on lookups (could have been a more expensive mapping)
  uint constant private ASCII_LOWER = 0x20; // added to uppercase to convert to lower
  uint constant private ASCII_0 = 0x30; // '0' ascii
  uint constant private ASCII_1 = 0x31; // '1' ascii
  uint constant private ASCII_2 = 0x32; // '2' ascii
  uint constant private ASCII_3 = 0x33; // '3' ascii
  uint constant private ASCII_4 = 0x34; // '4' ascii
  uint constant private ASCII_5 = 0x35; // '5' ascii
  uint constant private ASCII_6 = 0x36; // '6' ascii
  uint constant private ASCII_7 = 0x37; // '7' ascii
  uint constant private ASCII_8 = 0x38; // '8' ascii
  uint constant private ASCII_9 = 0x39; // '9' ascii
  uint constant private ASCII_EX = 0x21; // '!' ascii
  uint constant private ASCII_LT = 0x3c; // '<' ascii
  uint constant private ASCII_EQ = 0x3d; // '=' ascii
  uint constant private ASCII_GT = 0x3e; // '>' ascii
  uint constant private ASCII_D = 0x44; // 'D' ascii
  uint constant private ASCII_E = 0x45; // 'E' ascii
  uint constant private ASCII_O = 0x4f; // 'O' ascii
  uint constant private ASCII_S = 0x53; // 'S' ascii
  uint constant private ASCII_X = 0x58; // 'X' ascii

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

  // dices, both has not been rolled yet
  uint private dicea = 0;
  uint private diceb = 0;

  // based on the type of bet (Even, Odd, Seven, etc.) map to the applicable test with odds
  Test[128] private tests; // cater for printable ascii range

  // the market-makers, i.e. the funding queues
  MM[] public mms;

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

  // allow market-makers to add funds that is to be used for bet matching
  function invest() public {
    // we need a minimum amount to allow the funding to take place
    if (msg.value < CONFIG_MIN_FUNDS) {
      throw;
    }

    // we may have an overflow (i.e. > max), track it
    uint overflow = 0;
    uint value = msg.value;

    // check for the overflow, adjust accordingly
    if (value > CONFIG_MAX_FUNDS) {
      overflow = value - CONFIG_MAX_FUNDS;
      value = CONFIG_MAX_FUNDS;
    }

    // allocate the value to the overall available pool
    funds += value;

    // add the funder into our funding array, FIFO
    mms.push(MM({ addr: msg.sender, value: value }));

    // transfer any amounts >max back to the market-maker
    if (overflow > 0) {
      msg.sender.call.value(overflow)();
    }
  }

  // intialize the tests, done here so it is close to the actual test execution
  function initTests() private {
    // even & odd
    tests[ASCII_E] = Test({ bet: ASCII_E, chance: 18, test: 0 });
    tests[ASCII_O] = Test({ bet: ASCII_O, chance: 18, test: 1 });

    // 2-12 (no coincidence it is at same idx), chance peaks at 7, then decreases to max
    tests[ASCII_2] = Test({ bet: ASCII_2, chance: 1, test: 2 });
    tests[ASCII_3] = Test({ bet: ASCII_3, chance: 2, test: 3 });
    tests[ASCII_4] = Test({ bet: ASCII_4, chance: 3, test: 4 });
    tests[ASCII_5] = Test({ bet: ASCII_5, chance: 4, test: 5 });
    tests[ASCII_6] = Test({ bet: ASCII_6, chance: 5, test: 6 });
    tests[ASCII_7] = Test({ bet: ASCII_7, chance: 6, test: 7 });
    tests[ASCII_8] = Test({ bet: ASCII_8, chance: 5, test: 8 });
    tests[ASCII_9] = Test({ bet: ASCII_9, chance: 4, test: 9 });
    tests[ASCII_0] = Test({ bet: ASCII_0, chance: 3, test: 10 });
    tests[ASCII_1] = Test({ bet: ASCII_1, chance: 2, test: 11 });
    tests[ASCII_X] = Test({ bet: ASCII_X, chance: 1, test: 12 });

    // >7 & <7, both 15/36 chance
    tests[ASCII_GT] = Test({ bet: ASCII_GT, chance: 15, test: 0 });
    tests[ASCII_LT] = Test({ bet: ASCII_LT, chance: 15, test: 0 });

    // two dice are equal or not equal
    tests[ASCII_EQ] = Test({ bet: ASCII_EQ, chance: 6, test: 0 });
    tests[ASCII_EX] = Test({ bet: ASCII_EX, chance: 30, test: 0 });

    // single & double digits
    tests[ASCII_D] = Test({ bet: ASCII_D, chance: 6, test: 0 });
    tests[ASCII_S] = Test({ bet: ASCII_S, chance: 30, test: 0 });

    // lowercase
    tests[ASCII_LOWER + ASCII_D] = tests[ASCII_D];
    tests[ASCII_LOWER + ASCII_E] = tests[ASCII_E];
    tests[ASCII_LOWER + ASCII_O] = tests[ASCII_O];
    tests[ASCII_LOWER + ASCII_S] = tests[ASCII_S];
    tests[ASCII_LOWER + ASCII_X] = tests[ASCII_X];

    // failsafe, nothing passed in as message data, then we do the default evens
    tests[0x00] = tests[ASCII_E];
  }

  // calculates the winner based on inputs & test
  function isWinner(Test test) private returns (bool) {
    // ok, this is the sum, I'm sure it is useful...
    uint sum = dicea + diceb;

    // greater-than
    if (test.bet == ASCII_GT) {
      return sum > 7;
    }

    // less-than
    if (test.bet == ASCII_LT) {
      return sum < 7;
    }

    // dice are equal
    if (test.bet == ASCII_EQ) {
      return dicea == diceb;
    }

    // dice are not equal
    if (test.bet == ASCII_EX) {
      return dicea != diceb;
    }

    // double digit sum
    if (test.bet == ASCII_D) {
      return sum >= 10;
    }

    // single digit sum
    if (test.bet == ASCII_S) {
      return sum < 10;
    }

    // number matching
    if (test.test >= 2) {
      return sum == test.test;
    }

    // odd & even
    return (sum % 2) == test.test;
  }

  function roll() private returns (uint) {
    // adjust this Lehmer pseudo generator to the next value
    seedb = (seedb * LEHMER_MUL) % LEHMER_MOD;

    // adjust the overall random number based on the Lehmer input value
    random ^= seedb;

    // return the number of the side represented
    return (random % CONFIG_DICE_SIDES) + 1;
  }

  // set the random number generator for the specific generation
  function randomize() private {
    // calculate the next number from the pseudo Lehmer sequence
    seeda = (seeda * LEHMER_MUL) % LEHMER_MOD;

    // adjust the overall random value, taking the seed, available funds & block details into account
    random ^= uint(sha3(block.coinbase, block.blockhash(block.number - 1), funds, seeda));

    // roll the dices, effectively using the second generator
    dicea = roll();
    diceb = roll();
  }

  // distribute fees, grabbing from the market-makers, allocating wins/losses as applicable
  function play(uint input) private returns (uint) {
    // grab the bet from the message and set the accociated test
    Test memory test = tests[uint(msg.data[0])];

    // we weren't able to get the type, do nothing
    if (test.bet == 0) {
      throw;
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
    }

    // we will need to calculate the owner fees, either way
    uint fee = 0;
    uint result = 0;

    // winning or losing outcome here?
    if (winner) {
      // calculate the fees only on the profit portion of the bet
      fee = output / CONFIG_FEES_DIV;

      // remove the mathed bets from total funds & market-maker
      funds -= output;
      funder.value -= output;

      // if the funding bucket is empty, move to the next
      if (funder.value == 0) {
        mmidx++;
      }

      // use the overflow value to return
      result = output + input - fee;

      // we have one more win for the contract
      wins += 1;
    } else {
      // fees are only applied to the actual profits made by the mm
      fee = input / CONFIG_FEES_DIV;

      // send the funder the profit
      funder.addr.call.value(input - fee)();

      // one more loss for the record books
      losses++;
    }

    // fees go to the owner
    fees += fee;

    // one more transaction & input climbing up
    turnover += input;
    txs += 1;

    // notify the world of this outcome
    notifyPlayer(test, winner, input, result);

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
  function notifyPlayer(Test test, bool winner, uint input, uint output) private {
    Player(msg.sender, uint32(now), byte(test.bet), uint8(dicea), uint8(diceb), winner, input, output, funds, txs, turnover);
  }
}
