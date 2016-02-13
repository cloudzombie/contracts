contract Lottery {
  struct Winner {
    address addr;
    uint32 at;
    uint32 round;
    uint32 tickets;
    uint result;
  }

  modifier owneronly {
    if (msg.sender != owner) {
      throw;
    }

    _
  }

  event NewEntry(address addr, uint32 at, uint32 round, uint32 tickets, uint32 total);
  event NewWinner(address addr, uint32 at, uint32 round, uint32 tickets, uint result);

  uint constant public CONFIG_DURATION = 24 hours;
  uint constant public CONFIG_MIN_ENTRIES = 5;
  uint constant public CONFIG_MAX_ENTRIES = 222;
  uint constant public CONFIG_MAX_TICKETS = 100;
  uint constant public CONFIG_PRICE = 10 finney;
  uint constant public CONFIG_FEES = 50 szabo;
  uint constant public CONFIG_RETURN = CONFIG_PRICE - CONFIG_FEES;
  uint constant public CONFIG_MIN_VALUE = CONFIG_PRICE;
  uint constant public CONFIG_MAX_VALUE = CONFIG_PRICE * CONFIG_MAX_TICKETS;

  address owner = msg.sender;
  uint random = uint(block.coinbase) ^ uint(msg.sender) ^ now;

  uint8[25000] tickets;
  mapping (uint => address) entries;

  Winner public winner;
  uint public round = 1;
  uint public numentries = 0;
  uint public numtickets = 0;
  uint public start = now;
  uint public end = start + CONFIG_DURATION;
  uint public txs = 0;

  function Lottery() {
  }

  function ownerWithdraw() owneronly public {
    uint fees = this.balance - (numtickets * CONFIG_PRICE);

    if (fees > 0) {
      owner.call.value(fees)();
    }
  }

  function() public {
    if (msg.value < CONFIG_MIN_VALUE) {
      throw;
    }

    if ((numentries >= CONFIG_MAX_ENTRIES) || ((numentries >= CONFIG_MIN_ENTRIES) && (now > end))) {
      uint result = uint(sha3(random));
      uint winidx = tickets[result % numtickets];

      winner = Winner({ addr: entries[winidx], at: uint32(now), round: uint32(round), tickets: uint32(numtickets), result: result });

      winner.addr.call.value(numtickets * CONFIG_RETURN)();
      NewWinner(winner.addr, uint32(now), uint32(round), uint32(numtickets), result);

      numentries = 0;
      numtickets = 0;
      start = now;
      end = start + CONFIG_DURATION;
      round++;
    }

    uint number = 0;

    if (msg.value >= CONFIG_MAX_VALUE) {
      number = CONFIG_MAX_TICKETS;
    } else {
      number = msg.value / CONFIG_PRICE;
    }

    uint overval = msg.value - (number * CONFIG_PRICE);

    if (overval > 0) {
      msg.sender.call.value(overval)();
    }

    uint ticketmax = numtickets + number;

    for (uint idx = numtickets; idx < ticketmax; idx++) {
      tickets[idx] = uint8(numentries);
    }

    numtickets = ticketmax;

    entries[numentries] = msg.sender;
    NewEntry(msg.sender, uint32(now), uint32(round), uint32(number), uint32(numtickets));

    numentries++;
    txs += number;
    random = random ^ uint(sha3(block.blockhash(block.number - 1), uint(block.coinbase) ^ uint(msg.sender) ^ txs));
  }
}
