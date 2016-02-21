// LooneyDice is a traditional dice-game (ala craps), allowing bets on the outcomes of a 2 dice throw
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

  // publically available contract information
  uint public funds = 0;
  uint public turnover = 0;
  uint public wins = 0;
  uint public losses = 0;
  uint public txs = 0;

  // basic constructor, since the initial values are set, just do something for the test/bet types
  function LooneyDice() {
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

    // default
    tests[0] = tests[ASCII_E];
  }

  // allow the owner to withdraw his/her fees
  function ownerWithdraw() owneronly public {
    // send any fees we have and result the value back
    if (fees > 0) {
      owner.call.value(fees)();
      fees = 0;
    }
  }

  // allow withdrawal of investment
  function ownerWithdrawPool() owneronly public {
    if (funds > 0) {
      owner.call.value(funds)();
      funds = 0;
    }
  }

  // calculates the winner based on inputs & test
  function isWinner(Test test) constant private returns (bool) {
    // ok, this is the sum, quite useful for the next ones
    uint sum = dicea + diceb;

    // number matching
    if (test.test >= 2) {
      return sum == test.test;
    }

    // dice are equal/not equal
    else if (test.bet == ASCII_EQ) {
      return dicea == diceb;
    } else if (test.bet == ASCII_EX) {
      return dicea != diceb;
    }

    // greater-than/less-than
    else if (test.bet == ASCII_GT) {
      return sum > 7;
    } else if (test.bet == ASCII_LT) {
      return sum < 7;
    }

    // double/single digit sum
    else if (test.bet == ASCII_D) {
      return sum >= 10;
    } else if (test.bet == ASCII_S) {
      return sum < 10;
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
    return 0;

    // grab the bet from the message and set the associated test
    Test test = tests[0];

    // if we got data, attempt to grab the actual bet
    /*if (msg.data.length == 1) {
      test = tests[uint8(msg.data[0])];
    }*/

    // invalid type defaults to evens bet
    /*if (test.bet == 0) {
      test = tests[0];
    }*/

    // the actual returns that we send back to the user
    uint result = 0;

    // winning or losing outcome here?
    if (isWinner(test)) {
      // odds used as in divisor, i.e. evens = 36/18 = 200%, however input also gets added, so adjust
      uint output = ((input * MAX_ROLLS) / test.chance) - input;

      // failsafe for the case where the contract runs out of funds
      if (output > funds) {
        return input;
      }

      // calculate the fees on the profit portion of the bet
      uint fee = output / CONFIG_FEES_DIV;

      // remove the mathed bets from total funds
      funds -= output;
      fees += fee;

      // set the actual return amount, including the original stake
      result = output + input - fee;

      // we have one more win for the contract
      wins += 1;
    } else {
      // send the lost amount to the pool
      funds += input;

      // one more loss for the record books
      losses++;
    }

    // notify the world of this outcome
    notifyPlayer(test.bet, input, result);

    // ok, this is now what we owe the player
    return result;
  }

  // a simple sendTransaction with data (optional) is enought to drive the contract
  function() public {
    // owner sends his value to the funding pool
    if (msg.sender == owner) {
      funds += msg.value;
      return;
    }

    // we need to comply with the actual minimum values to be allowed to play
    if (msg.value < CONFIG_MIN_VALUE) {
      throw;
    }

    // fire up the random generator, we need some entropy in here
    randomize();

    // keep track of the input value as sent by the user
    uint input = msg.value;

    // erm, more than we allow, set to the cap (extras to be returned)
    if (input > CONFIG_MAX_VALUE) {
      input = CONFIG_MAX_VALUE;
    }

    // one more transaction & input climbing up
    turnover += input;
    txs += 1;

    // get the actual return value for the player
    uint output = play(input) + (msg.value - input);

    // do we need to send the player some ether, do it
    if (output > 0) {
      msg.sender.call.value(output)();
    }
  }

  // log events
  event Player(address addr, uint32 at, uint8 bet, uint8 dice, uint input, uint output, uint wins, uint txs, uint turnover);

  // send the player event, i.e. somebody has played, this is what he/she/it did
  function notifyPlayer(uint bet, uint input, uint output) private {
    Player(msg.sender, uint32(now), uint8(bet), uint8((dicea * 0xf) + diceb), input, output, wins, txs, turnover);
  }
}
