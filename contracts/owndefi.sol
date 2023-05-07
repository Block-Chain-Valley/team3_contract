// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ipairfactory.sol";

contract owndefi {
    address private immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountToken
    ) public {
        address pair = Ipairfactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = Ipairfactory(factory).createPair(tokenA, tokenB);
        }
    }
}
