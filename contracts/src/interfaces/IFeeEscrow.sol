// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal stand-in for the third-party launchpad's trading-fee
/// escrow (AQUITY-SPEC §2.1: 1% fee on every trade, 70% of that is the
/// creator's share). Reshape to match the real launchpad's fee-claim ABI
/// once confirmed — nothing else in FeeRouter needs to change.
interface IFeeEscrow {
    /// @notice Claims accrued trading fees owed to `agentToken`'s creator
    /// share and transfers them to msg.sender. Fees arrive in the pool's
    /// quote asset — the agent's paired stock — so no swap is needed
    /// (AQUITY-SPEC §2.1).
    function claimFees(address agentToken) external returns (uint256 amount);
}
