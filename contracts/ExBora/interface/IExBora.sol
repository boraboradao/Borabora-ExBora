// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

// This token can not transfer
interface IExBora {
  event SetManager(address indexed manager, bool isValid);
}
