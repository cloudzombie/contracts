// LooneyBox
//
// git: https://github.com/thelooneyfarm/contracts/tree/master/src/box
// url: http://the.looney.farm/game/box
contract LooneyBox {
  // modifier for the owner protected functions
  modifier owneronly {
    // yeap, you need to own this contract to action it
    if (msg.sender != owner) {
      throw;
    }

    // actual execution goes here
    _
  }

  // holder of our participant information
  struct Participant {
    address addr;
    uint value;
  }

  // game configuration, also available extrenally for queries
  uint constant public CONFIG_MIN_VALUE = 10 finney;
  uint constant public CONFIG_MAX_VALUE = 9990 finney;
  uint constant public CONFIG_FEES_DIV = 200; // 5/1000 = 1/200, divisor
  uint constant public CONFIG_NUM_PARTICIPANTS = 12;

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

  // our actual participants
  Participant[] public participants;

  // publically available contract information
  uint public turnover = 0;
  uint public pool = 0;
  uint public txs = 0;

  // basic constructor, since the initial values are set, no action required
  function LooneyBox() {
  }

  // do we have an entry from this person yet?
  function hasPrevious() constant private returns (bool) {
    for (uint idx = 0; idx < participants.length; idx++) {
      if (participants[idx].addr == msg.sender) {
        return true;
      }
    }

    // nothing found, this one is not in the pool
    return false;
  }

  // set the random number generator for the specific generation
  function randomize() private {
    // calculate the next number from the pseudo Lehmer sequence
    seeda = (seeda * LEHMER_MUL) % LEHMER_MOD;

    // adjust the overall random value, taking the seeds and block details into account
    random ^= uint(sha3(block.coinbase, block.blockhash(block.number - 1), seeda));
  }

  // get a random participant
  function randomParticipantIdx() constant private returns (uint) {
    // fire up our second Lehmer generator
    seedb = (seedb * LEHMER_MUL) % LEHMER_MOD;

    // adjust the random value as per the generator
    random ^= seedb;

    // return the random participant
    return random % participants.length;
  }

  // swap both the adresses and values
  function swapAddresses(Participant one) private {
    // get a random position for the swap
    Participant two = participants[randomParticipantIdx()];

    // swap the addresses around
    address temp = one.addr;
    one.addr = two.addr;
    two.addr = temp;
  }

  // swap the participant with somebody else (values)
  function swapValuesRandom(Participant one) private {
    // get another random guy
    Participant two = participants[randomParticipantIdx()];

    // swap the values around
    uint temp = one.value;
    one.value = two.value;
    two.value = temp;
  }

  // find a recipient and send him/her/it some Ether
  function getReceiver() private returns (Participant) {
    // create a participant for this player
    Participant memory receiver = Participant({ addr: msg.sender, value: msg.value });

    // adjust the random values, re-initializing the rng
    randomize();

    // do we have enough participants for a value swap?
    if (participants.length > 0) {
      // create a swap of the input amount with somebody else
      swapValuesRandom(receiver);
    }

    // do we have enough participants for a payout?
    if (participants.length == CONFIG_NUM_PARTICIPANTS) {
      // swap the adresses around between the receiver (currently sender) & real random receiver
      swapAddresses(receiver);
    } else {
      // still early with <12 players, just add the participant to the list
      participants.push(receiver);
    }

    // return the receiver
    return receiver;
  }

  // go! a simple sendTransaction is enough to drive the contract
  function() public {
    // we need to comply with the actual minimum/maximum values to be allowed to play
    if (msg.value < CONFIG_MIN_VALUE || msg.value > CONFIG_MAX_VALUE || hasPrevious()) {
      throw;
    }

    // adjust the pool, txs & turnover
    turnover += msg.value;
    pool += msg.value;
    txs += 1;

    // recipient
    Participant memory receiver = getReceiver();

    // do we have something to send to somebody that is not the originator?
    if (receiver.addr != msg.sender) {
      // calculate the fee & adjust overall
      uint fee = receiver.value / CONFIG_FEES_DIV;
      fees += fee;

      // remove the actual amount due from the pool now
      pool -= receiver.value;
      receiver.value -= fee;

      // send it & hope they are happy
      receiver.addr.call.value(receiver.value)();

      // notify that somebody has received
      notifyPlayer(receiver);
    }
  }

  // allow the owner to withdraw his/her fees
  function ownerWithdraw() owneronly public {
    // we can only return what we have
    if (fees == 0) {
      throw;
    }

    // return to owner
    owner.call.value(fees)();

    // remove the actual payout values
    fees = 0;
  }

  // log events
  event Player(address sender, uint32 at, address receiver, uint output, uint pool, uint txs, uint turnover);

  // send the player event, i.e. somebody has played, this is what he/she/it did
  function notifyPlayer(Participant receiver) private {
    Player(msg.sender, uint32(now), receiver.addr, receiver.value, pool, txs, turnover);
  }
}
