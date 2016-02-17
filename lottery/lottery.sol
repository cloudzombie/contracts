// LooneyLottery that pays out the full pool once a day
//
// git: https://github.com/thelooneyfarm/contracts/tree/master/lottery
// url: http://the.looney.farm/game/lottery
contract LooneyLottery {
  // modifier for the protected functions
  modifier owneronly {
    // yeap, you need to own this contract to action it
    if (msg.sender != owner) {
      throw;
    }

    _
  }

  // when a new person enters, we let the world know
  event NewEntry(address addr, uint32 at, uint32 round, uint32 tickets, uint32 total);

  // when a new winner is available, let the world know
  event NewWinner(address addr, uint32 at, uint32 round, uint32 tickets);

  // constants for the Lehmer RNG
  uint constant private LEHMER_MOD = 4294967291;
  uint constant private LEHMER_MUL = 279470273;
  uint constant private LEHMER_SDA = 1299709;
  uint constant private LEHMER_SDB = 7919;

  // various game-related constants, also available externally
  uint constant public CONFIG_DURATION = 24 hours;
  uint constant public CONFIG_MIN_ENTRIES = 5;
  uint constant public CONFIG_MAX_ENTRIES = 222;
  uint constant public CONFIG_MAX_TICKETS = 100;
  uint constant public CONFIG_PRICE = 10 finney;
  uint constant public CONFIG_FEES = 50 szabo;
  uint constant public CONFIG_RETURN = CONFIG_PRICE - CONFIG_FEES;
  uint constant public CONFIG_MIN_VALUE = CONFIG_PRICE;
  uint constant public CONFIG_MAX_VALUE = CONFIG_PRICE * CONFIG_MAX_TICKETS;

  // our owner, stored for owner-related functions
  address private owner = msg.sender;

  // these are the values for the RNG
  uint private result = uint(sha3(block.coinbase, block.blockhash(block.number - 1), now));
  uint private seeda = LEHMER_SDA;
  uint private seedb = LEHMER_SDB;

  // we allow 222 * 100 max tickets, allocate a bit more and store the mapping of entry => address
  uint8[25000] private tickets;
  mapping (uint => address) private entries;

  // public game-related values
  uint public round = 1;
  uint public numentries = 0;
  uint public numtickets = 0;
  uint public start = now;
  uint public end = start + CONFIG_DURATION;
  uint public txs = 0;

  // nothing much to do in the constructor
  function LooneyLottery() {
  }

  // owner withdrawal of fees
  function ownerWithdraw() owneronly public {
    // calculate the fees collected previously (exclusing current round)
    uint fees = this.balance - (numtickets * CONFIG_PRICE);

    // return it if we have someting
    if (fees > 0) {
      owner.call.value(fees)();
    }
  }

  // calculate the next random number with a two-phase Lehmer
  function randomize() private {
    // calculate the next seed for the first phase
    seeda = (seeda * LEHMER_MUL) % LEHMER_MOD;

    // adjust the result accordingly, getting extra info from the blockchain together with the seeds
    result ^= uint(sha3(block.coinbase, block.blockhash(block.number - 1), this.balance, seeda ^ seedb));

    // adjust the second phase seed for the next iteration (i.e. non-changeable random value)
    seedb = (seedb * LEHMER_MUL) % LEHMER_MOD;
  }

  // pick a random winner when the time is right
  function pickWinner() private {
    // do we have >222 players or >= 5 tickets and an expired timer
    if ((numentries >= CONFIG_MAX_ENTRIES) || ((numentries >= CONFIG_MIN_ENTRIES) && (now > end))) {
      // get the winner based on the number of tickets (each player has multiple tickets)
      uint winidx = tickets[result % numtickets];

      // send the winnings to the winner and let the world know
      entries[winidx].call.value(numtickets * CONFIG_RETURN)();
      NewWinner(entries[winidx], uint32(now), uint32(round), uint32(numtickets));

      // reset the round, and start a new one
      numentries = 0;
      numtickets = 0;
      start = now;
      end = start + CONFIG_DURATION;
      round++;
    }
  }

  // allocate tickets to the entry based on the value of the transaction
  function buyTickets() private {
    // here we store the number of tickets
    uint number = 0;

    // get either a max number based on the over-the-top entry or calculate based on inputs
    if (msg.value >= CONFIG_MAX_VALUE) {
      number = CONFIG_MAX_TICKETS;
    } else {
      number = msg.value / CONFIG_PRICE;
    }

    // overflow is the value to be returned, >max or not a multiple of min
    uint overflow = msg.value - (number * CONFIG_PRICE);

    // send it back if we have something we don't want to handle
    if (overflow > 0) {
      msg.sender.call.value(overflow)();
    }

    // the last index of the ticket we will be adding to the pool
    uint ticketmax = numtickets + number;

    // loop through and allocate a ticket based on the number bought
    for (uint idx = numtickets; idx < ticketmax; idx++) {
      tickets[idx] = uint8(numentries);
    }

    // our new value of bought tickets is the same as max, store it
    numtickets = ticketmax;

    // let the world know that we have made an entry
    entries[numentries] = msg.sender;
    NewEntry(msg.sender, uint32(now), uint32(round), uint32(number), uint32(numtickets));

    // one more entry, one more transaction
    numentries++;
    txs += number;
  }

  // we only have a default function, send an amount and it gets allocated, no ABI needed
  function() public {
    // oops, we need at least 10 finney to play :(
    if (msg.value < CONFIG_MIN_VALUE) {
      throw;
    }

    // adjust the random value, see if we need a winner and buy the tickets
    randomize();
    pickWinner();
    buyTickets();
  }
}
