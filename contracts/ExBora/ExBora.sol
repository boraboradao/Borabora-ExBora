// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interface/IExBora.sol";

// This token can not transfer
contract ExBora is IExBora, Ownable, ERC20 {
  mapping(address => bool) private _managers;

  modifier onlyManager() {
    require(_managers[msg.sender], "ExBora: caller is not the manager");
    _;
  }

  constructor() ERC20("ExBora", "EXB") {
    _mint(msg.sender, 3510000 * 10 ** decimals());
  }

  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public virtual override onlyManager returns (bool) {
    address spender = msg.sender;
    _spendAllowance(from, spender, amount);
    _transfer(from, to, amount);
    return true;
  }

  function transfer(
    address to,
    uint256 amount
  ) public virtual override onlyManager returns (bool) {
    _transfer(msg.sender, to, amount);
    return true;
  }

  function approve(
    address spender,
    uint256 amount
  ) public virtual override returns (bool) {
    require(_managers[spender], "ExBora: spender is not valid manager");
    _approve(msg.sender, spender, amount);
    return true;
  }

  function setManager(address manager, bool isValid) public onlyOwner {
    _managers[manager] = isValid;

    emit SetManager(manager, isValid);
  }

  function mint(
    address receiver,
    uint256 amount
  ) public onlyManager returns (bool) {
    _mint(receiver, amount);
    return true;
  }

  function burn(uint256 amount) public onlyManager returns (bool) {
    _burn(msg.sender, amount);
    return true;
  }

  function isManager(address manager) public view returns (bool) {
    return _managers[manager];
  }
}
