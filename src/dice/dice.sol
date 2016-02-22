// LooneyDice is a traditional dice-game (ala craps), allowing plays on the outcomes of a 2 dice throw
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

  // for each play of play, chance = <odds>/36 occurences (return), test is the value to be tested
  struct Test {
    uint8 chance;
    uint8 test;
  }

  // these are the values of the input plays (byte in)
  uint constant private PLAY_EVEN_SUM = 0x0;
  uint constant private PLAY_ODD_SUM = 0x1;
  uint constant private PLAY_SUM_2 = 0x2;
  uint constant private PLAY_SUM_3 = 0x3;
  uint constant private PLAY_SUM_4 = 0x4;
  uint constant private PLAY_SUM_5 = 0x5;
  uint constant private PLAY_SUM_6 = 0x6;
  uint constant private PLAY_SUM_7 = 0x7;
  uint constant private PLAY_SUM_8 = 0x8;
  uint constant private PLAY_SUM_9 = 0x9;
  uint constant private PLAY_SUM_10 = 0x10;
  uint constant private PLAY_SUM_11 = 0x11;
  uint constant private PLAY_SUM_12 = 0x12;
  uint constant private PLAY_MORE_7 = 0xa;
  uint constant private PLAY_LESS_7 = 0xb;
  uint constant private PLAY_SINGLE = 0xc;
  uint constant private PLAY_DOUBLE = 0xd;
  uint constant private PLAY_EQUAL = 0xe;
  uint constant private PLAY_NOT_EQUAL = 0xf;

  // number of different combinations for 2 six-sided dice
  uint constant private MAX_ROLLS = 6 * 6;

  // game configuration, also available extrenally for queries
  uint constant public CONFIG_MIN_VALUE = 10 finney;
  uint constant public CONFIG_MAX_VALUE = 1 ether;
  uint constant public CONFIG_FEES_MUL = 1; // 5/1000 = 1/200, the 0.5% goes to the owner (comm only on winnings)
  uint constant public CONFIG_FEES_DIV = 200; // 5/1000 = 1/200, divisor
  uint constant public CONFIG_DICE_SIDES = 6;

  // configuration for the Lehmer RNG
  uint constant private LEHMER_MOD = 4294967291;
  uint constant private LEHMER_MUL = 279470273;
  uint constant private LEHMER_SDA = 1299709;
  uint constant private LEHMER_SDB = 7919;

  // the owner address as well as the owner-applicable fees
  address private owner = msg.sender;
  uint private fees = 0;
  uint private bank = msg.value;

  // initialize the pseudo RNG, ready to rock & roll
  uint private random = uint(sha3(block.coinbase, block.blockhash(block.number - 1), now));
  uint private seeda = LEHMER_SDA;
  uint private seedb = LEHMER_SDB;

  // dices, both has not been rolled yet
  uint private dicea = 0;
  uint private diceb = 0;

  // based on the play of play (Even, Odd, Seven, etc.) map to the applicable test with odds
  Test[255] private tests;

  // publically available contract information
  uint public funds = msg.value;
  uint public turnover = 0;
  uint public wins = 0;
  uint public losses = 0;
  uint public txs = 0;

  // basic constructor, since the initial values are set, just do something for the test/play plays
  function LooneyDice() {
    // even & odd
    tests[PLAY_EVEN_SUM] = Test({ chance: 18, test: 0 });
    tests[PLAY_ODD_SUM] = Test({ chance: 18, test: 1 });

    // sums 2-12, chance peaks at 7, then decreases to max
    tests[PLAY_SUM_2] = Test({ chance: 1, test: 2 });
    tests[PLAY_SUM_3] = Test({ chance: 2, test: 3 });
    tests[PLAY_SUM_4] = Test({ chance: 3, test: 4 });
    tests[PLAY_SUM_5] = Test({ chance: 4, test: 5 });
    tests[PLAY_SUM_6] = Test({ chance: 5, test: 6 });
    tests[PLAY_SUM_7] = Test({ chance: 6, test: 7 });
    tests[PLAY_SUM_8] = Test({ chance: 5, test: 8 });
    tests[PLAY_SUM_9] = Test({ chance: 4, test: 9 });
    tests[PLAY_SUM_10] = Test({ chance: 3, test: 10 });
    tests[PLAY_SUM_11] = Test({ chance: 2, test: 11 });
    tests[PLAY_SUM_12] = Test({ chance: 1, test: 12 });

    // >7 & <7, both 15/36 chance
    tests[PLAY_MORE_7] = Test({ chance: 15, test: 0 });
    tests[PLAY_LESS_7] = Test({ chance: 15, test: 0 });

    // two dice are equal or not equal
    tests[PLAY_EQUAL] = Test({ chance: 6, test: 0 });
    tests[PLAY_NOT_EQUAL] = Test({ chance: 30, test: 0 });

    // single & double digits
    tests[PLAY_DOUBLE] = Test({ chance: 6, test: 0 });
    tests[PLAY_SINGLE] = Test({ chance: 30, test: 0 });
  }

  // calculates the winner based on inputs & test
  function isWinner(uint play, Test test) constant private returns (bool) {
    // ok, this is the sum, quite useful for the next ones
    uint sum = dicea + diceb;

    // number matching
    if (test.test >= 2) {
      return sum == test.test;
    }

    // dice are equal/not equal
    else if (play == PLAY_EQUAL) {
      return dicea == diceb;
    } else if (play == PLAY_NOT_EQUAL) {
      return dicea != diceb;
    }

    // greater-than/less-than
    else if (play == PLAY_MORE_7) {
      return sum > 7;
    } else if (play == PLAY_LESS_7) {
      return sum < 7;
    }

    // double/single digit sum
    else if (play == PLAY_DOUBLE) {
      return sum >= 10;
    } else if (play == PLAY_SINGLE) {
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
  function execute(uint play, uint input) private returns (uint) {
    // setup the play/test we are executing
    Test memory test = tests[play];

    // invalid play, don't execute
    if (test.chance == 0) {
      throw;
    }

    // fire up the random generator & roll the dice
    randomize();

    // the actual returns that we send back to the user
    uint result = 0;

    // winning or losing outcome here?
    if (isWinner(play, test)) {
      // odds used as in divisor, i.e. evens = 36/18 = 200%, however input also gets added, so adjust
      uint output = ((input * MAX_ROLLS) / test.chance) - input;

      // failsafe for the case where the contract runs out of funds
      if (output > funds) {
        return input;
      }

      // calculate the fees on the profit portion of the play
      uint fee = output / CONFIG_FEES_DIV;

      // remove the mathed plays from total funds
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

    // one more transaction & input climbing up
    turnover += input;
    txs += 1;

    // notify the world of this outcome
    notifyPlayer(play, input, result);

    // ok, this is now what we owe the player
    return result;
  }

  // the play interface, used in the cases where we want to send a different-than-equal play through
  function enter(byte play) public {
    // we need to comply with the actual minimum values to be allowed to play
    if (msg.value < CONFIG_MIN_VALUE) {
      throw;
    }

    // keep track of the input value as sent by the user
    uint input = msg.value;

    // erm, more than we allow, set to the cap (extras to be returned)
    if (input > CONFIG_MAX_VALUE) {
      input = CONFIG_MAX_VALUE;
    }

    // get the actual return value for the player
    uint output = execute(uint(play), input) + (msg.value - input);

    // do we need to send the player some ether, do it
    if (output > 0) {
      msg.sender.call.value(output)();
    }
  }

  // a simple sendTransaction with data (optional) is enough to drive the contract
  function() public {
    // owner sends his value to the funding pool
    if (msg.sender == owner) {
      bank += msg.value;
      funds += msg.value;
      return;
    }

    enter(byte(PLAY_EVEN_SUM));
  }

  // allow the owner to withdraw his/her fees
  function ownerWithdrawFees() owneronly public {
    // send any fees we have and result the value back
    if (fees > 0) {
      owner.call.value(fees)();
      fees = 0;
    }
  }

  // allow withdrawal of investment
  function ownerWithdrawBank() owneronly public {
    if (bank > 0 && funds > bank) {
      owner.call.value(bank)();
      bank = 0;
      funds -= bank;
    }
  }

  // log events
  event Player(address addr, uint32 at, uint8 play, uint8 dicea, uint8 diceb, uint input, uint output, uint wins, uint txs, uint turnover);

  // send the player event, i.e. somebody has played, this is what he/she/it did
  function notifyPlayer(uint play, uint input, uint output) private {
    Player(msg.sender, uint32(now), uint8(play), uint8(dicea), uint8(diceb), input, output, wins, txs, turnover);
  }
}
