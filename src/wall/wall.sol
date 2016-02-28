// Proxy sits before a deployed contract, forwarding all calls accross
//
// git: https://github.com/thelooneyfarm/contracts/tree/master/src/wall
contract LooneyWall {
  // modifier for the owner protected functions
  modifier owneronly {
    // yeap, you need to own this contract to action it
    if (msg.sender != owner) {
      throw;
    }

    // actual execution goes here
    _
  }

  // log events
  event Message(address addr, uint32 at, uint value, string message);

  // the owner of this contract
  address private owner = msg.sender;

  // do nothing on the constructor
  function LooneyWall() {
  }

  // allow the owner to withdraw any associated funds
  function ownerWithdraw() owneronly public {
    if (this.balance > 0) {
      owner.call.value(this.balance)();
    }
  }

  // write a message on the wall (sends an event)
  function write(string message) public {
    Message(msg.sender, uint8(now), msg.value, message);
  }

  // no default function, allways use write
  function() {
    throw;
  }
}
