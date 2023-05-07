// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface Ipairfactory {
    function getPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}
