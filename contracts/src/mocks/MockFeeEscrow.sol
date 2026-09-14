// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeEscrow} from "../interfaces/IFeeEscrow.sol";

/// @notice Test-only stand-in for a launchpad's fee escrow. Must be
/// pre-funded with the fee token. Not part of the production contract set.
contract MockFeeEscrow is IFeeEscrow {
    using SafeERC20 for IERC20;

    IERC20 public immutable feeToken;
    mapping(address agentToken => uint256) public accrued;

    constructor(address _feeToken) {
        feeToken = IERC20(_feeToken);
    }

    function accrue(address agentToken, uint256 amount) external {
        accrued[agentToken] += amount;
    }

    function claimFees(address agentToken) external returns (uint256 amount) {
        amount = accrued[agentToken];
        accrued[agentToken] = 0;
        if (amount > 0) {
            feeToken.safeTransfer(msg.sender, amount);
        }
    }
}
