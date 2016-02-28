# proxy

A very simple proxy that forwards any inputs to the specified output address. Be aware that proxies contracts should not rely on msg.sender (it will be the proxy), rather it should use tx.origin if it really needs to know which actual account interacted with the proxy

(this does open up holes from Mist contract wallets, i.e. the tx.origin is probably Etherbase, so the interaction comes from the wrong place)
