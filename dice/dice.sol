// LooneyDice is a traditional dice-game (ala craps) allowing players to play market makers as well
//
// git: https://github.com/thelooneyfarm/contracts/tree/master/dice
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
    uint8 odds;
    uint8 tidx;
  }

  // event that fires when a new player has been made a move
  event Player(address addr, uint32 at, byte bet, uint8 dicea, uint8 diceb, bool winner, uint input, uint output, uint txs, uint funds);

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

  // based on the type of bet (Even, Odd, Sevents, etc.) map to the applicable test with odds
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
      if (!(profits[msg.sender] > 0)) {
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
  function investProfits() public {
    // if we don't have enough, don't do this
    if (profits[msg.sender] < CONFIG_MIN_FUNDS) {
      throw;
    }

    // take any overflow value and keep it as profits for the market maker
    profits[msg.sender] = addFunds(msg.sender, profits[msg.sender]);
  }

  // allow market-makers to withdraw their profits
  function withdrawProfits() public {
    // see what they have in the kitty
    uint value = profits[msg.sender];

    // if we have something real, send it back
    if (value > 0) {
      msg.sender.call.value(value)();
      profits[msg.sender] = 0;
    }
  }

  // intialize the tests, done here so it is close to the actual testing
  function initTests() private {
    // key = 'bet type', odds = <odds>/36 occurences (return), tidx is the value to be tested
    // NOTE: odds used as in divisor, i.e. evens = 36/18 = 200%, however input also gets added, so adjust

    // evens, 18/36
    tests['E'] = Test({ odds: 2 * 18, tidx: 0 });
    tests['e'] = tests['E'];

    // odds, 18/36
    tests['O'] = Test({ odds: 2 * 18, tidx: 1 });
    tests['o'] = tests['O'];

    // snake eyes, 1/36 (for ease of calc, number tidx equals the number value)
    tests['2'] = Test({ odds: 2 * 1, tidx: 2 });
    tests[':'] = tests['2'];
    tests['%'] = tests['2'];

    // 3-6, more popular as it increases
    tests['3'] = Test({ odds: 2 * 2, tidx: 3 });
    tests['4'] = Test({ odds: 2 * 3, tidx: 4 });
    tests['5'] = Test({ odds: 2 * 4, tidx: 5 });
    tests['6'] = Test({ odds: 2 * 5, tidx: 6 });

    // 7, middle number, highest single number chance
    tests['7'] = Test({ odds: 2 * 6, tidx: 7 });
    tests['='] = tests['7'];

    // 8-11, less popular as it increases
    tests['8'] = Test({ odds: 2 * 5, tidx: 8 });
    tests['9'] = Test({ odds: 2 * 4, tidx: 9 });
    tests['0'] = Test({ odds: 2 * 3, tidx: 10 });
    tests['1'] = Test({ odds: 2 * 2, tidx: 11 });

    // 12, the maxium value, 1/36 chance
    tests['X'] = Test({ odds: 2 * 1, tidx: 12 });
    tests['x'] = tests['x'];

    // >7 & <7, both 15/36 chance
    tests['>'] = Test({ odds: 2 * 15, tidx: 13 });
    tests['<'] = Test({ odds: 2 * 15, tidx: 14 });
  }

  // calculate an outcome based on the two dices, winner=bool, bettype=byte
  function calculate(uint dicea, uint diceb) private returns (bool, byte) {
    // grab the bet from the message and set the accociated test
    byte bet = msg.data[0];
    Test test = tests[bet];

    // if the odds are not >0, it means we don't have a valid bettype, fall back to evens
    if (!(test.odds > 0)) {
      test = tests['E'];
      bet = 'E';
    }

    // get the sum and set the initial winner state
    uint sum = dicea + diceb;
    bool winner = false;

    // grab the test according to the bet mapping and calculate the outcome
    if (test.tidx >= 2 && test.tidx <= 12) {
      winner = sum == test.tidx;
    } else if (test.tidx == 13) {
      winner = sum > 7;
    } else if (test.tidx == 14) {
      winner = sum < 7;
    } else if (test.tidx == 1) {
      winner = (sum % 2) == 1;
    } else {
      winner = (sum % 2) == 0;
    }

    // return both the winner and the bet type (as evaluated)
    return (winner, bet);
  }

  // distribute fees, grabbing from the market-makers, allocating wins/losses as applicable
  function distribute(bool winner, uint input, uint odds) private returns (uint) {
    // output is 99% of the actual expected return (still lower than casinos)
    uint output = (input * MAX_ROLLS * CONFIG_RETURN_MUL) / (odds * CONFIG_RETURN_DIV);
    uint fee = 0;

    // while we have something to allocate, do so
    while (output > 0) {
      // grab the current funder in the queue
      MM funder = mms[mmidx];

      // first allocate all inputs/outputs to this funder
      uint moutput = output;
      uint minput = input;

      // ummm, expected >available, just grab what we can from this market-maker and jump to next
      if (output >= funder.value) {
        moutput = funder.value;
        minput = (input * moutput) / output;
        mmidx++;
      }

      // remove the mathed bets as applicable
      funds -= moutput;
      output -= moutput;
      input -= minput;

      // yes, even removed from the funder - like BetFair, the bet is matched, so not available
      funder.value -= moutput;

      // ok, we have a loser on our hands, allocate the profits to the market-maker
      if (!winner) {
        // fees are only applied to the actual profits made, not the total
        fee = (minput * CONFIG_FEES_MUL) / CONFIG_FEES_DIV;
        fees += fee;

        // move the matched part & actual profit (- fee) to the profit pool for the funder
        profits[funder.addr] += moutput + minput - fee;
      }
    }

    // one more transaction
    txs += 1;

    // ding-ding, we have a winner
    if (winner) {
      // calculate the fees only on the won portion of the bet
      fee = (output * CONFIG_FEES_MUL) / CONFIG_FEES_DIV;
      fees += fee;

      // we have one more win for the contract
      wins += 1;

      // return the original bet, profit (- fee)
      return input + output - fee;
    }

    // increment the losses
    losses += 1;

    // nothing gained, better luck next time
    return 0;
  }

  // set the random number generator for the specific generation
  function randomize() private {
    // calculate the next number from the pseudo Lehmer sequence
    seeda = (seeda * LEHMER_MUL) % LEHMER_MOD;

    // adjust the overall random value, taking the seed, available funds & block details into account
    random ^= uint(sha3(block.coinbase, block.blockhash(block.number - 1), funds, seeda));
  }

  // rool the dice, returning a random value as the number (1-6)
  function roll() private returns (uint) {
    // adjust this Lehmer pseudo generator to the next value
    seedb = (seedb * LEHMER_MUL) % LEHMER_MOD;

    // adjust the overall random number based on the Lehmer input value
    random ^= seedb;

    // get the number of the side represented
    return (random % CONFIG_DICE_SIDES) + 1;
  }

  // a simple sendTransaction with data (optional) is enought ot drive the contract
  function() public {
    // we need to comply with the actual minimum values to be allowed to play
    if (msg.value < CONFIG_MIN_VALUE) {
      throw;
    }

    // fire up the random generator, we need some entropy in here
    randomize();

    // randomly roll the dices
    uint dicea = roll();
    uint diceb = roll();

    // store the actual overflow and input value as sent by the user
    uint overflow = 0;
    uint input = msg.value;

    // erm, more than we allow, set to the cap and make ready to return the extras
    if (input > CONFIG_MAX_VALUE) {
      input = CONFIG_MAX_VALUE;
      overflow = msg.value - CONFIG_MAX_VALUE;
    }

    // calculate the outcome based on the dices rolled
    bool winner = false;
    byte bet = 0;
    (winner, bet) = calculate(dicea, diceb);

    // distribute the winnings based on the actual odds of the play
    uint output = distribute(winner, input, tests[bet].odds);

    // notify the world of this outcome
    Player(msg.sender, uint32(now), bet, uint8(dicea), uint8(diceb), winner, input, output, txs, funds);

    // adjust the overall turnover and add overflow to player funds (if applicable)
    turnover += input;
    output += overflow;

    // do we need to send the player some ether, do it
    if (output > 0) {
      msg.sender.call.value(output)();
    }
  }
}
