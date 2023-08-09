// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IExBoraLock {
  struct LockInfo {
    address owner;
    uint64 startDate;
    uint256 amount;
  }

  struct ExBoraAllocation {
    uint256 lastAllocatedDate;
    uint256 dailyAllocatedAmount;
    uint256 unlockedAmount;
    uint256 lockedAmount;
  }

  struct DeflationStage {
    uint256 amount;
    uint256 coeff;
  }

  event AllocationChange(
    uint256 traderAllocatedAmount,
    uint256 traderUnAllocatedAmount
  );

  event UserAllocationChange(address user, ExBoraAllocation allocation);

  event LockInfoChange(uint256 lockId, LockInfo lockInfo);

  event ReleaseAllExBora(address user, uint256 releaseAmount);

  event SetSignatureLifetime(uint256 lifetime);

  event DeleteLockInfo(
    uint256 lockId,
    uint256 releaseAmount,
    uint256 freezeAmount
  );

  event Claim(
    address indexed owner,
    uint256 indexed lockId,
    uint256 amount,
    ExBoraAllocation exBoraAssignment
  );

  event UnAllocateReason(string reason);

  event SetAllocateCoeff(uint256 coeff);

  event SetDeflationStages(uint256[] amounts, uint256[] coeffs);

  event SetAllocationLimits(uint256 totalDailyLimit, uint256 userDailyLimit);

  event UpdateDeflationCoeff(uint256 coeff);

  event SetExBora(address exBora);

  event SetManager(address indexed account, bool isValid);

  function allocateWithVolume(
    address user,
    uint256 volume
  ) external returns (uint256);

  function lockInfoOf(uint256 lockId) external returns (LockInfo memory);
}
