contract LooneyDice {
  struct Funder {
    address addr;
    uint value;
  }

  struct Test {
    uint8 odds;
    uint8 tidx;
  }

  event Player(address addr, uint32 at, byte bet, uint8 dicea, uint8 diceb, bool winner, uint input, uint output, uint txs, uint funds);

  uint constant private MAX_ROLLS = 36;

  uint constant public CONFIG_MIN_VALUE = 10 finney;
  uint constant public CONFIG_MAX_VALUE = 1 ether;
  uint constant public CONFIG_MIN_FUNDS = 1 ether;
  uint constant public CONFIG_MAX_FUNDS = 100 ether;
  uint constant public CONFIG_RETURN_MUL = 99;
  uint constant public CONFIG_RETURN_DIV = 100;
  uint constant public CONFIG_FEES_MUL = 5;
  uint constant public CONFIG_FEES_DIV = 1000;
  uint constant public CONFIG_DICE_SIDES = 6;

  uint constant private LEHMER_MOD = 4294967291;
  uint constant private LEHMER_MUL = 279470273;
  uint constant private LEHMER_SDA = 1299709;
  uint constant private LEHMER_SDB = 7919;

  address private owner = msg.sender;
  uint private fees = 0;

  uint private result = uint(sha3(block.coinbase, block.blockhash(block.number - 1), now));
  uint private seeda = LEHMER_SDA;
  uint private seedb = LEHMER_SDB;

  mapping (byte => Test) private tests;

  Funder[] public funders;
  mapping (address => uint) public profits;

  uint public fundidx = 0;
  uint public funds = 0;
  uint public txs = 0;

  function LooneyDice() {
    addFunds(msg.sender, msg.value);
    initTests();
  }

  function ownerWithdraw() public {
    if (msg.sender != owner) {
      throw;
    }

    if (fees > 0) {
      owner.call.value(fees)();
      fees = 0;
    }
  }

  function addFunds(address funder, uint value) private returns (uint) {
    uint overflow = 0;

    if (value > 0) {
      if (value > CONFIG_MAX_FUNDS) {
        overflow = value - CONFIG_MAX_FUNDS;
        value = CONFIG_MAX_FUNDS;
      }

      funds += value;
      funders.length += 1;

      funders[funders.length - 1].addr = msg.sender;
      funders[funders.length - 1].value = value;
    }

    return overflow;
  }

  function invest() public {
    if (msg.value < CONFIG_MIN_FUNDS) {
      throw;
    }

    uint overflow = addFunds(msg.sender, msg.value);

    if (overflow > 0) {
      msg.sender.call.value(overflow)();
    }
  }

  function reinvest() public {
    profits[msg.sender] = addFunds(msg.sender, profits[msg.sender]);
  }

  function withdraw() public {
    uint value = profits[msg.sender];

    if (value > 0) {
      msg.sender.call.value(value)();
      profits[msg.sender] = 0;
    }
  }

  function initTests() private {
    tests['E'] = Test({ odds: 18, tidx: 0 });
    tests['e'] = tests['E'];

    tests['O'] = Test({ odds: 18, tidx: 1 });
    tests['o'] = tests['O'];

    tests['2'] = Test({ odds: 1, tidx: 2 });
    tests[':'] = tests['2'];
    tests['%'] = tests['2'];

    tests['3'] = Test({ odds: 2, tidx: 3 });
    tests['4'] = Test({ odds: 3, tidx: 4 });
    tests['5'] = Test({ odds: 4, tidx: 5 });
    tests['6'] = Test({ odds: 5, tidx: 6 });

    tests['7'] = Test({ odds: 6, tidx: 7 });
    tests['='] = tests['7'];

    tests['8'] = Test({ odds: 5, tidx: 8 });
    tests['9'] = Test({ odds: 4, tidx: 9 });
    tests['0'] = Test({ odds: 3, tidx: 10 });
    tests['1'] = Test({ odds: 2, tidx: 11 });

    tests['X'] = Test({ odds: 1, tidx: 12 });
    tests['x'] = tests['x'];

    tests['>'] = Test({ odds: 15, tidx: 13 });
    tests['<'] = Test({ odds: 15, tidx: 14 });
  }

  function calculate(uint dicea, uint diceb) private returns (bool, byte) {
    byte bet = msg.data[0];
    Test test = tests[bet];

    uint sum = dicea + diceb;
    bool winner = false;

    if (test.odds == 0) {
      test = tests['E'];
      bet = 'E';
    }

    if (test.tidx  >= 2 && test.tidx  <= 12) {
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

    return (winner, bet);
  }

  function distribute(bool winner, uint input, byte bet) private returns (uint) {
    uint output = (input * MAX_ROLLS * CONFIG_RETURN_MUL) / (tests[bet].odds * CONFIG_RETURN_DIV);
    uint fee = 0;

    while (output > 0) {
      Funder funder = funders[fundidx];
      uint moutput = output;
      uint minput = input;

      if (output >= funder.value) {
        moutput = funder.value;
        minput = (input * moutput) / output;
        fundidx++;
      }

      funds -= moutput;
      output -= moutput;
      input -= minput;
      funder.value -= moutput;

      if (!winner) {
        fee = (minput * CONFIG_FEES_MUL) / CONFIG_FEES_DIV;
        fees += fee;
        profits[funder.addr] += moutput + minput - fee;
      }
    }

    if (winner) {
      fee = (output * CONFIG_FEES_MUL) / CONFIG_FEES_DIV;
      fees += fee;

      return input + output - fee;
    }

    return 0;
  }

  function randomize() private {
    seeda = (seeda * LEHMER_MUL) % LEHMER_MOD;
    result ^= uint(sha3(block.coinbase, block.blockhash(block.number - 1), funds, seeda));
  }

  function roll() private returns (uint) {
    seedb = (seedb * LEHMER_MUL) % LEHMER_MOD;
    result ^= seedb;

    return (result % CONFIG_DICE_SIDES) + 1;
  }

  function() public {
    if (msg.value < CONFIG_MIN_VALUE) {
      throw;
    }

    randomize();

    uint dicea = roll();
    uint diceb = roll();

    uint retval = 0;
    uint input = msg.value;

    if (input > CONFIG_MAX_VALUE) {
      input = CONFIG_MAX_VALUE;
      retval = msg.value - CONFIG_MAX_VALUE;
    }

    bool winner = false;
    byte bet = 0;

    (winner, bet) = calculate(dicea, diceb);
    uint result = distribute(winner, input, bet);

    retval += result;
    txs += 1;

    if (retval > 0) {
      msg.sender.call.value(retval)();
    }

    Player(msg.sender, uint32(now), bet, uint8(dicea), uint8(diceb), winner, input, result, txs, funds);
  }
}
