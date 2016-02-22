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

  // number of different combinations for 2 six-sided dice
  uint constant private MAX_ROLLS = 6 * 6;

  // game configuration, also available extrenally for queries
  uint constant public CONFIG_MIN_VALUE = 10 finney;
  uint constant public CONFIG_MAX_VALUE = 999 finney;
  uint constant public CONFIG_FEES_MUL = 1; // 5/1000 = 1/200, the 0.5% goes to the owner (comm only on winnings)
  uint constant public CONFIG_FEES_DIV = 200; // 5/1000 = 1/200, divisor
  uint constant public CONFIG_DICE_SIDES = 6;
  uint constant public CONFIG_MAX_EXPOSURE_MUL = 1; // 5/100 = 1/20, the 5% is the max drawdown we allow
  uint constant public CONFIG_MAX_EXPOSURE_DIV = 20; // 5/100 = 1/20, divisor

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

  // the chances that a specific sum would arrise - 0, 1 (even, odd) & 2-12 (sum)
  uint[13] private chances = [18, 18, 1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1];

  // publically available contract information
  uint public funds = msg.value;
  uint public turnover = 0;
  uint public wins = 0;
  uint public losses = 0;
  uint public txs = 0;

  // basic constructor, since the initial values are set, just do something for the test/play plays
  function LooneyDice() {
  }

  // calculates the winner based on inputs & test
  function testWinner(uint play) constant private returns (uint, bool) {
    // ok, this is the sum, quite useful for the next ones
    uint sum = dicea + diceb;

    // equal/odd matching
    if (play <= 1) {
      return (chances[play], (sum % 2) == play);
    }

    // single number matching
    if (play <= 12) {
      return (chances[play], sum == play);
    }

    // get the number range from the input - <max><min>
    uint maxsum = play / 10;
    uint minsum = play % 10;

    // a > b, both >= 2 & <= 12
    if (minsum < maxsum && minsum >= 2 && maxsum <= 12) {
      // store the calculated chance
      uint chance = 0;

      // look through the options and add the chances
      for (uint test = minsum; test <= maxsum; test++) {
        chance += chances[test];
      }

      // return the success & chance
      return (chance, sum >= minsum && sum <= maxsum);
    }

    // I still haven't found what I'm looking for
    throw;
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
    // fire up the random generator & roll the dice
    randomize();

    // store if a winner as well as the overall chance of this play
    bool winner = false;
    uint chance = 0;

    // get the winning result, enabling us to see where & what
    (chance, winner) = testWinner(play);

    // odds used as in divisor, i.e. evens = 36/18 = 200%, however input also gets added, so adjust
    uint output = ((input * MAX_ROLLS) / chance) - input;

    // failsafe for the case where the contract could run dry
    if (output > (funds / CONFIG_MAX_EXPOSURE_DIV)) {
      throw;
    }

    // the actual returns that we send back to the user
    uint result = 0;

    // winning or losing outcome here?
    if (winner) {
      // calculate the fees on the profit portion of the play
      uint fee = output / CONFIG_FEES_DIV;

      // remove the matched plays from total funds
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
    notifyPlayer(play, chance, input, result);

    // ok, this is now what we owe the player
    return result;
  }

  // the play interface, used in the cases where we want to send a different-than-equal play through
  function enter(uint8 play) public {
    // we need to comply with the actual minimum/maximum values to be allowed to play
    if (msg.value < CONFIG_MIN_VALUE || msg.value > CONFIG_MAX_VALUE) {
      throw;
    }

    // get the actual return value for the player
    uint output = execute(play, msg.value);

    // do we need to send the player some ether, do it
    if (output > 0) {
      msg.sender.call.value(output)();
    }
  }

  // a simple sendTransaction with data (optional) is enough to drive the contract
  function() public {
    // owner sends his value to the funding pool
    if (msg.sender == owner) {
      funds += msg.value;
      return;
    }

    enter(0);
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
  function ownerWithdrawBank(uint size) owneronly public {
    if (size > funds) {
      throw;
    }

    owner.call.value(size)();
    funds -= size;
  }

  // log events
  event Player(address addr, uint32 at, uint8 play, uint8 chance, uint8 dicea, uint8 diceb, uint input, uint output, uint wins, uint txs, uint turnover);

  // send the player event, i.e. somebody has played, this is what he/she/it did
  function notifyPlayer(uint play, uint chance, uint input, uint output) private {
    Player(msg.sender, uint32(now), uint8(play), uint8(chance), uint8(dicea), uint8(diceb), input, output, wins, txs, turnover);
  }
}
