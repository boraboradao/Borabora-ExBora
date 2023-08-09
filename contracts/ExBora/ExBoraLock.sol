// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./interface/IExBoraLock.sol";
import "../library/Price.sol";

contract ExBoraLock is
  IExBoraLock,
  Initializable,
  OwnableUpgradeable,
  UUPSUpgradeable
{
  using CountersUpgradeable for CountersUpgradeable.Counter;
  using ECDSA for bytes32;

  CountersUpgradeable.Counter public lockInfoCounter;
  uint256 public constant LOCK_PERIOND_IN_DAYS = 1460; // 4 years

  uint256 public sinatureLifetime;

  address public exBora;
  uint256 public traderUnAllocatedAmount;
  uint256 public traderAllocatedAmount;

  uint256 public allocateCoeff;
  uint256 public curDeflationStage;

  uint256 public totalDailyAllocationLimit;
  uint256 public userDailyAllocationLimit;

  mapping(uint256 => uint256) public dailyAllocatedAmount;

  mapping(uint256 => DeflationStage) public deflationStages;

  mapping(uint256 => LockInfo) private _lockInfos;
  mapping(address => ExBoraAllocation) private _exBoraAllocations;
  mapping(address => bool) private _managers;

  modifier onlyManager() {
    require(isManager(msg.sender), "ExBoraLock: Caller is not Manager");
    _;
  }

  function initialize(address exBora_) public initializer {
    __Ownable_init();
    setExBora(exBora_);
  }

  function lock(uint256 amount) public returns (uint256) {
    // Step 1. Check if the user has enough unlocked token
    require(
      _exBoraAllocations[msg.sender].unlockedAmount >= amount,
      "ExBoraLock: not enough unlocked token"
    );

    // Step 2. Update exBoraAssignment infos
    _exBoraAllocations[msg.sender].unlockedAmount -= amount;
    _exBoraAllocations[msg.sender].lockedAmount += amount;

    // Step 3. Create new LockInfo
    LockInfo memory newLockInfo = LockInfo({
      amount: amount,
      startDate: getDate(),
      owner: msg.sender
    });

    lockInfoCounter.increment();
    uint256 lockId = lockInfoCounter.current();
    _lockInfos[lockId] = newLockInfo;

    emit LockInfoChange(lockId, newLockInfo);
    emit UserAllocationChange(msg.sender, _exBoraAllocations[msg.sender]);
    return lockId;
  }

  function batchUnlockExpired(uint256[] memory lockIds) public returns (bool) {
    LockInfo memory lockInfo;
    uint256 releaseAmount;

    for (uint256 i; i < lockIds.length; ++i) {
      lockInfo = _lockInfos[lockIds[i]];
      require(
        lockInfo.owner == msg.sender,
        "ExBoraLock: only owner can claim the token"
      );
      require(
        uint256(getDate() - lockInfo.startDate) >= LOCK_PERIOND_IN_DAYS,
        "ExBoraLock: lock period is not over"
      );

      releaseAmount += lockInfo.amount;
      delete _lockInfos[lockIds[i]];

      emit DeleteLockInfo(lockIds[i], releaseAmount, 0);
    }

    _exBoraAllocations[msg.sender].lockedAmount -= releaseAmount;
    emit UserAllocationChange(msg.sender, _exBoraAllocations[msg.sender]);

    return true;
  }

  function unLock(uint256 lockId) public returns (bool) {
    // Step 1. Check if the caller is the owner of the lock
    LockInfo memory lockInfo = _lockInfos[lockId];
    require(
      lockInfo.owner == msg.sender,
      "ExBoraLock: only owner can claim the token"
    );

    // Step 2. Check if the lock period is over
    uint256 lockPeriodInDays = uint256(getDate() - lockInfo.startDate);
    require(lockPeriodInDays >= 2, "ExBoraLock: can not unlock now");

    uint256 releaseAmount;
    uint256 freezeAmount;
    if (lockPeriodInDays >= LOCK_PERIOND_IN_DAYS) {
      releaseAmount = lockInfo.amount;
    } else {
      releaseAmount =
        (lockPeriodInDays * lockInfo.amount) /
        LOCK_PERIOND_IN_DAYS;
      freezeAmount = lockInfo.amount - releaseAmount;
    }

    _exBoraAllocations[msg.sender].lockedAmount -= lockInfo.amount;
    _exBoraAllocations[msg.sender].unlockedAmount += freezeAmount;
    delete _lockInfos[lockId];

    SafeERC20Upgradeable.safeTransfer(
      IERC20Upgradeable(exBora),
      msg.sender,
      releaseAmount
    );

    emit UserAllocationChange(msg.sender, _exBoraAllocations[msg.sender]);
    emit DeleteLockInfo(lockId, releaseAmount, freezeAmount);
    return true;
  }

  function releaseAllExBora(
    uint256 timestamp,
    bytes memory signature
  ) public returns (uint256) {
    require(
      timestamp + sinatureLifetime > block.timestamp,
      "Signature Expired"
    );
    require(_validSignature(timestamp, signature), "Invalid Signature");

    ExBoraAllocation memory allocation = _exBoraAllocations[msg.sender];
    require(allocation.lockedAmount == 0, "ExBoraLock: have locked token");
    uint256 releaseAmount = allocation.unlockedAmount;

    delete _exBoraAllocations[msg.sender];

    emit ReleaseAllExBora(msg.sender, releaseAmount);
    return releaseAmount;
  }

  function allocateWithVolume(
    address user,
    uint256 volume
  ) public onlyManager returns (uint256) {
    // Step 1. Check if un-allocated / reamin-daily-total / remain-daily-user amount is enough
    uint256 remainTraderUnAllocatedAmount = traderUnAllocatedAmount;
    if (remainTraderUnAllocatedAmount > 0) {
      emit UnAllocateReason("trader un-allocated amount is empty");
    }

    uint256 today = getDate();
    uint256 remainDailyTotalAllocationAmount = totalDailyAllocationLimit -
      dailyAllocatedAmount[today];
    if (remainDailyTotalAllocationAmount > 0) {
      emit UnAllocateReason("daily total allocation amount is empty");
    }

    if (_exBoraAllocations[user].lastAllocatedDate != today) {
      _exBoraAllocations[user].lastAllocatedDate = today;
      _exBoraAllocations[user].dailyAllocatedAmount = 0;
    }
    uint256 remainDailyUserAllocationAmount = userDailyAllocationLimit -
      _exBoraAllocations[user].dailyAllocatedAmount;
    if (remainDailyUserAllocationAmount > 0) {
      emit UnAllocateReason("daily user allocation amount is empty");
    }

    // Step 2. Calculate allocate amount & filter out the valid amount
    uint256 allocateAmount = Price.mulE4(
      Price.mulE4(volume, allocateCoeff),
      deflationStages[curDeflationStage].coeff
    );

    if (allocateAmount > remainTraderUnAllocatedAmount) {
      allocateAmount = remainTraderUnAllocatedAmount;
    }

    if (allocateAmount > remainDailyTotalAllocationAmount) {
      allocateAmount = remainDailyTotalAllocationAmount;
    }

    if (allocateAmount > remainDailyUserAllocationAmount) {
      allocateAmount = remainDailyUserAllocationAmount;
    }

    // Step 3. Update allocation infos
    traderUnAllocatedAmount -= allocateAmount;
    traderAllocatedAmount += allocateAmount;
    totalDailyAllocationLimit += allocateAmount;
    _exBoraAllocations[user].dailyAllocatedAmount += allocateAmount;
    _exBoraAllocations[user].unlockedAmount += allocateAmount;

    // Step 4. Here to update deflationCoeff is necessary
    uint256 nextStage = curDeflationStage + 1;
    if (
      deflationStages[nextStage].amount > 0 &&
      traderAllocatedAmount >= deflationStages[nextStage].amount
    ) {
      curDeflationStage += 1;
      emit UpdateDeflationCoeff(deflationStages[curDeflationStage].coeff);
    }
    emit AllocationChange(traderAllocatedAmount, traderUnAllocatedAmount);
    emit UserAllocationChange(user, _exBoraAllocations[user]);
    return allocateAmount;
  }

  function setExBora(address token) public onlyOwner {
    exBora = token;
    emit SetExBora(token);
  }

  function setManager(address account, bool isValid) public onlyOwner {
    _managers[account] = isValid;
    emit SetManager(account, isValid);
  }

  function setAllocateCoeff(uint256 coeff) public onlyOwner {
    allocateCoeff = coeff;
    emit SetAllocateCoeff(coeff);
  }

  function setDeflationStages(
    uint256[] memory amounts,
    uint256[] memory coeffs
  ) public onlyOwner {
    require(amounts.length == coeffs.length, "ExBoraLock: Length is not equal");
    require(amounts.length <= 10, "ExBoraLock: Too many stages");

    for (uint256 i = 0; i < amounts.length; ++i) {
      if (i > 0) {
        require(
          amounts[i - 1] < amounts[i],
          "ExBoraLock: amount is not sorted"
        );
      }

      deflationStages[i] = DeflationStage({
        amount: amounts[i],
        coeff: coeffs[i]
      });
    }

    emit UpdateDeflationCoeff(coeffs[curDeflationStage]);
    emit SetDeflationStages(amounts, coeffs);
  }

  function setAllocationLimits(
    uint256 totalDailyLimit,
    uint256 userDailyLimit
  ) public onlyOwner {
    totalDailyAllocationLimit = totalDailyLimit;
    userDailyAllocationLimit = userDailyLimit;
    emit SetAllocationLimits(totalDailyLimit, userDailyLimit);
  }

  function setuserDailyAllocationLimit(uint256 limit) public onlyOwner {
    userDailyAllocationLimit = limit;
  }

  function setSignatureLifetime(uint256 lifetime) external onlyOwner {
    sinatureLifetime = lifetime;
    emit SetSignatureLifetime(lifetime);
  }

  function setNewAllocation(uint256 amount) public onlyOwner {
    traderUnAllocatedAmount = amount;
    traderAllocatedAmount = 0;

    emit AllocationChange(traderAllocatedAmount, traderUnAllocatedAmount);
  }

  function lockInfoOf(uint256 lockId) public view returns (LockInfo memory) {
    return _lockInfos[lockId];
  }

  function predictUnlockResult(
    uint256 lockId
  ) public view returns (uint256, uint256) {
    LockInfo memory lockInfo = _lockInfos[lockId];

    uint256 lockPeriodInDays = uint256(getDate() - lockInfo.startDate);

    uint256 releaseAmount;
    uint256 freezeAmount;
    if (lockPeriodInDays >= LOCK_PERIOND_IN_DAYS) {
      releaseAmount = lockInfo.amount;
    } else {
      releaseAmount =
        (lockPeriodInDays * lockInfo.amount) /
        LOCK_PERIOND_IN_DAYS;
      freezeAmount = lockInfo.amount - releaseAmount;
    }

    return (releaseAmount, freezeAmount);
  }

  function exBoraAllocationOf(
    address owner
  ) public view returns (ExBoraAllocation memory) {
    return _exBoraAllocations[owner];
  }

  function isManager(address account) public view returns (bool) {
    return _managers[account];
  }

  function getDate() public view returns (uint64) {
    return uint64(block.timestamp / 1 days);
  }

  function _validSignature(
    uint256 timestamp,
    bytes memory signature
  ) internal view returns (bool) {
    bytes32 message = keccak256(
      abi.encodePacked("EXBORA_LOCK", msg.sender, timestamp)
    );
    address signer = message.toEthSignedMessageHash().recover(signature);
    return isManager(signer);
  }

  function _authorizeUpgrade(
    address newImplementation
  ) internal virtual override onlyOwner {}
}
