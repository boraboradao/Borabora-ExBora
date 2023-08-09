// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBoraRouter {
  event ClosePosition(
    address sender,
    uint256 positionId,
    address positionOwner,
    uint256 returnAmount,
    uint256 executorFeeAmount,
    uint256 exBoraNewAllocateAmount
  );

  event SetBoraPVE(address boraPVE);

  event SetSagesNFT(address sagesNFT);

  event SetIsSagesNFTLimited(bool isLimited);

  event SetUsdt(address usdt);

  event SetExBoraLock(address exBoraLock);

  event SetBoraHelper(address boraHelper);

  event SetBnbUsdtPriceFeed(address priceFeed, uint8 decimals);

  event SetExecutor(address executor, bool isExecutor);

  event SetClosePositionGasUsage(uint256 gasUsage, uint256 feeRate);

  event SetFeeRateForSwap(uint256 feeRate);
}
