contract LooneyFifty {
  modifier owneronly {
    if (msg.sender != owner) {
      throw;
    }

    _
  }

  modifier pricecheck {
    if (msg.value < CONFIG_MIN_VALUE) {
      throw;
    }

    _
  }

  event NextPlayer(address addr, uint32 at, uint8 pwins, uint8 plosses, uint input, uint output, uint wins, uint txs);

  uint constant private LEHMER_MOD = 4294967291;
  uint constant private LEHMER_MUL = 279470273;
  uint constant private LEHMER_SDA = 1299709;
  uint constant private LEHMER_SDB = 7919;

  uint constant public CONFIG_MAX_PLAYS = 100;
  uint constant public CONFIG_PRICE = 10 finney;
  uint constant public CONFIG_MIN_VALUE = CONFIG_PRICE;
  uint constant public CONFIG_MAX_VALUE = CONFIG_PRICE * CONFIG_MAX_PLAYS;
  uint constant public CONFIG_FEES_MUL = 5;
  uint constant public CONFIG_FEES_DIV = 1000;

  address private owner = msg.sender;
  uint private pool = msg.value;
  uint private fees = 0;

  uint private result = uint(sha3(block.coinbase, block.blockhash(block.number - 1), pool, now));
  uint private seeda = LEHMER_SDA;
  uint private seedb = LEHMER_SDB;

  uint public txs = 0;
  uint public wins = 0;
  uint public losses = 0;

  function LooneyFifty() {
  }

  function ownerWithdraw() owneronly public {
    if (fees > 0) {
      owner.call.value(fees)();
    }
  }

  function ownerFees() owneronly public returns (uint) {
    return fees;
  }

  function() pricecheck public {
    seeda = (seeda * LEHMER_MUL) % LEHMER_MOD;
    result = result ^ uint(sha3(block.coinbase, block.blockhash(block.number - 1), pool, seeda));

    uint number = 0;

    if (msg.value >= CONFIG_MAX_VALUE) {
      number = CONFIG_MAX_PLAYS;
    } else {
      number = msg.value / CONFIG_PRICE;
    }

    uint input = number * CONFIG_PRICE;
    uint output = 0;
    uint pwins = 0;
    uint plosses = 0;

    for (uint num = 0; num < number; num++) {
      seedb = (seedb * LEHMER_MUL) % LEHMER_MOD;
      result = result ^ seedb;

      if (result % 2 == 0) {
        uint win = pool / 2;
        uint fee = (win * CONFIG_FEES_MUL) / CONFIG_FEES_DIV;

        pwins += 1;
        pool -= win;
        fees += fee;
        output += win - fee + CONFIG_PRICE;
      } else {
        plosses += 1;
        pool += CONFIG_PRICE;
      }
    }

    txs += number;
    wins += pwins;
    losses += plosses;

    NextPlayer(msg.sender, uint32(now), uint8(pwins), uint8(plosses), input, output, wins, txs);

    output += msg.value - input;

    if (output > 0) {
      msg.sender.call.value(output)();
    }
  }
}