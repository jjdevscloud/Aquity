// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Real wrapped-native token on Robinhood Chain mainnet, at
/// 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73 — read live from
/// SwapRouter02.WETH9() this session (not previously recorded anywhere;
/// there is no canonical "WETH" address to assume on a new chain).
interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}
