// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./BasicMaths.sol";

library Price {
  using BasicMaths for uint256;
  using BasicMaths for bool;

  uint256 private constant E18 = 1e18;
  uint256 private constant E9 = 1e9;
  uint256 private constant E4 = 1e4;

  function divE18(
    uint256 valueA,
    uint256 valueB
  ) internal pure returns (uint256) {
    return (valueA * E18) / valueB;
  }

  function divE4(
    uint256 valueA,
    uint256 valueB
  ) internal pure returns (uint256) {
    return (valueA * E4) / valueB;
  }

  function mulE18(
    uint256 valueA,
    uint256 valueB
  ) internal pure returns (uint256) {
    return (valueA * valueB) / E18;
  }

  function mulE4(
    uint256 valueA,
    uint256 valueB
  ) internal pure returns (uint256) {
    return (valueA * valueB) / E4;
  }

  function lpTokenPrice(
    uint256 totalSupply,
    uint256 liquidityPool
  ) internal pure returns (uint256) {
    if (totalSupply == 0 || liquidityPool == 0) {
      return E18;
    }

    return (liquidityPool * (E18)) / totalSupply;
  }

  function lpTokenByPoolToken(
    uint256 totalSupply,
    uint256 liquidityPool,
    uint256 poolToken
  ) internal pure returns (uint256) {
    if (liquidityPool != 0) {
      return (poolToken * totalSupply) / liquidityPool;
    }
    return poolToken;
  }

  function poolTokenByLPToken(
    uint256 totalSupply,
    uint256 liquidityPool,
    uint256 lpToken
  ) internal pure returns (uint256) {
    return (lpToken * lpTokenPrice(totalSupply, liquidityPool)) / E18;
  }

  function calFundingFee(
    uint256 positionAmount,
    uint256 rebaseSize
  ) internal pure returns (uint256) {
    return mulE18(positionAmount, rebaseSize);
  }

  function convertDecimal(
    uint256 amount,
    uint8 fromDecimal,
    uint8 toDecimal
  ) internal pure returns (uint256) {
    if (fromDecimal == toDecimal) {
      return amount;
    } else if (fromDecimal > toDecimal) {
      return amount / (10 ** (fromDecimal - toDecimal));
    } else {
      return amount * 10 ** (toDecimal - fromDecimal);
    }
  }
}
