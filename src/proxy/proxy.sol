// Proxy sits before a deployed contract, forwarding all calls accross
//
// git: https://github.com/thelooneyfarm/contracts/tree/master/src/proxy
contract Proxy {
  // modifier for the owner protected functions
  modifier owneronly {
    // yeap, you need to own this contract to action it
    if (msg.sender != owner) {
      throw;
    }

    // actual execution goes here
    _
  }

  // the owner of this proxy
  address private owner = msg.sender;

  // our proxy forwarding address
  address public forwardAddr = 0;
  uint public forwardVersion = 0;

  // do nothing on the constructor
  function Proxy() {
  }

  // set the forwarding address & version (timestamp)
  function ownerForward(address addr) owneronly public {
    forwardAddr = addr;
    forwardVersion = now;
  }

  // transparently pass through any calls to the receiver
  function() {
    forwardAddr.call.value(msg.value)(msg.data);
  }
}
