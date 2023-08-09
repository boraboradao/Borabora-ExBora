// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

import "../Pool/interface/IPoolPositionHandler.sol";
import "../Pool/PoolStructs.sol";
import "../ExBora/interface/IExBoraLock.sol";
import "../Helper/interface/IBoraSwap.sol";

import "../library/Price.sol";
import "./interface/IBoraRouter.sol";

import "hardhat/console.sol";

contract BoraRouter is
  IBoraRouter,
  Initializable,
  OwnableUpgradeable,
  UUPSUpgradeable
{
  address public usdt;
  address public boraPVE;
  address public sagesNFT;
  address public exBoraLock;
  address public boraHelper;
  address public bnbUsdtPriceFeed;
  uint8 public bnbUsdtPriceFeedDecimals;

  bool public isSagesNFTLimited;

  uint256 public feeRateForSwap;
  uint256 public closePositionGasUsage;
  uint256 public executorFeeRate;
  mapping(address => bool) private _executors;

  uint256[50] private __gap;

  function initialize(
    address usdt_,
    address priceFeed_,
    address boraPVE_,
    address sagesNFT_,
    address exBoraLock_,
    address boraHelper_
  ) public initializer {
    __Ownable_init();

    setBoraPVE(boraPVE_);
    setSagesNFT(sagesNFT_);
    setUsdt(usdt_);
    setExBoraLock(exBoraLock_);
    setBoraHelper(boraHelper_);
    setBnbUsdtPriceFeed(priceFeed_);
  }

  receive() external payable {}

  function closePosition(
    ClosePositionInput memory input
  ) external returns (bool) {
    Position memory position = IPoolPositionHandler(boraPVE).getPosition(
      input.positionId
    );

    require(
      position.owner == msg.sender || isExecutor(msg.sender),
      "Router: Not position owner or executor"
    );

    // Step 1. Close position
    uint256 helperBeforePoolTokenBalance = IERC20(usdt).balanceOf(boraHelper);
    uint256 beforePoolTokenBalance = IERC20(usdt).balanceOf(address(this));
    IPoolPositionHandler(boraPVE).closePosition(input);
    uint256 retrunPoolTokenAmount = IERC20(usdt).balanceOf(address(this)) -
      beforePoolTokenBalance;

    // Step 2. Edit Helper's AMM (injectUsdt)
    uint256 addAmmUsdtAmount = Price.mulE4(
      (IERC20(usdt).balanceOf(boraHelper) - helperBeforePoolTokenBalance),
      feeRateForSwap
    );
    IBoraSwap(boraHelper).addUsdtAmount(addAmmUsdtAmount);

    // Step 3. Call Lock Contract & Allocate exBora to position owner
    uint256 exBoraNewAllocateAmount = 0;
    if (!isSagesNFTLimited || IERC721(sagesNFT).balanceOf(position.owner) > 0) {
      uint256 positionVolume = position.initMargin * position.leverage;

      try
        IExBoraLock(exBoraLock).allocateWithVolume(
          position.owner,
          positionVolume
        )
      returns (uint256 allocateAmount) {
        exBoraNewAllocateAmount = allocateAmount;
      } catch {}

      // exBoraNewAllocateAmount = IExBoraLock(exBoraLock).allocateWithVolume(
      //   position.owner,
      //   positionVolume
      // );
    }

    // Step 3. Check if caller is executor
    bool isCalledByExecutor = isExecutor(msg.sender);

    // Step 4. Calculate executor fee & final return amount
    uint256 executorFeeInPoolToken;
    if (isCalledByExecutor) {
      uint256 gasAmount = (closePositionGasUsage +
        Price.mulE4(closePositionGasUsage, executorFeeRate)) * tx.gasprice;

      uint256 cryptoPriceToPoolToken = uint256(
        AggregatorV2V3Interface(bnbUsdtPriceFeed).latestAnswer()
      );

      executorFeeInPoolToken =
        (gasAmount * cryptoPriceToPoolToken) /
        10 ** bnbUsdtPriceFeedDecimals;

      if (executorFeeInPoolToken > retrunPoolTokenAmount) {
        executorFeeInPoolToken = retrunPoolTokenAmount;
      }

      retrunPoolTokenAmount -= executorFeeInPoolToken;

      (bool success, ) = payable(msg.sender).call{ value: gasAmount }("");
      require(success, "Router: Failed to send executor fee");
    }

    if (retrunPoolTokenAmount > 0) {
      SafeERC20.safeTransfer(
        IERC20(usdt),
        position.owner,
        retrunPoolTokenAmount
      );
    }

    emit ClosePosition(
      msg.sender,
      input.positionId,
      position.owner,
      retrunPoolTokenAmount,
      executorFeeInPoolToken,
      exBoraNewAllocateAmount
    );

    return true;
  }

  function setBoraPVE(address pool) public onlyOwner {
    boraPVE = pool;
    emit SetBoraPVE(pool);
  }

  function setSagesNFT(address nft) public onlyOwner {
    sagesNFT = nft;
    emit SetSagesNFT(nft);
  }

  function setIsSagesNFTLimited(bool isLimited) public onlyOwner {
    isSagesNFTLimited = isLimited;
    emit SetIsSagesNFTLimited(isLimited);
  }

  function setUsdt(address token) public onlyOwner {
    usdt = token;
    emit SetUsdt(token);
  }

  function setExBoraLock(address lock) public onlyOwner {
    exBoraLock = lock;
    emit SetExBoraLock(lock);
  }

  function setBoraHelper(address helper) public onlyOwner {
    boraHelper = helper;
    emit SetBoraHelper(helper);
  }

  function setBnbUsdtPriceFeed(address priceFeed) public onlyOwner {
    bnbUsdtPriceFeed = priceFeed;
    bnbUsdtPriceFeedDecimals = AggregatorV2V3Interface(priceFeed).decimals();

    emit SetBnbUsdtPriceFeed(priceFeed, bnbUsdtPriceFeedDecimals);
  }

  function setFeeRateForSwap(uint256 feeRate) public onlyOwner {
    feeRateForSwap = feeRate;
    emit SetFeeRateForSwap(feeRate);
  }

  function setClosePositionGasUsage(
    uint256 gasUsage,
    uint256 feeRate
  ) public onlyOwner {
    closePositionGasUsage = gasUsage;
    executorFeeRate = feeRate;

    emit SetClosePositionGasUsage(gasUsage, feeRate);
  }

  function setExecutors(
    address[] memory executors,
    bool isValid
  ) public onlyOwner {
    for (uint256 i = 0; i < executors.length; ++i) {
      _executors[executors[i]] = isValid;
      emit SetExecutor(executors[i], isValid);
    }
  }

  function isExecutor(address executor) public view returns (bool) {
    return _executors[executor];
  }

  function _authorizeUpgrade(
    address newImplementation
  ) internal virtual override onlyOwner {}
}
