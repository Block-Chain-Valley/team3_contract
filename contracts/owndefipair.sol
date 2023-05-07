// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ERC20.sol";

contract owndefipair is ERC20 {
    address private immutable factory;
    address public token0;
    address public token1;

    constructor() ERC20("owndefi", "odf") {
        factory = msg.sender;
    }

    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "UniswapV2: FORBIDDEN"); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }
}
