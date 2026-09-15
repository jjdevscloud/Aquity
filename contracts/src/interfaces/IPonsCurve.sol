// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Real Pons v2 bonding-curve pool (one per launched token) —
/// selectors verified against github.com/ponsmcp/pons-mcp's self-checking
/// ABI table and, for `sweepFees`, against its own doc comment in
/// src/trade.ts: "sweepFees(minBuybackTokensOut) sweeps ALL pending fees;
/// the argument is a token-denominated minimum-output floor for the
/// internal buyback swap, not an amount to sweep." Confirmed by this
/// session's own fork test: creator-tax fees accrue on the CURVE first
/// (`creatorTaxBalance()`), not in PonsV2FeeEscrow — `sweepFees` is what
/// moves them there, and PonsV2FeeEscrow.claim() finds nothing until it's
/// called.
///
/// IMPORTANT (also confirmed via this session's own fork test, via a real
/// revert trace — not documented anywhere before that): `sweepFees` is NOT
/// permissionless. It reverts `NotFeeSweepOperator()` (confirmed selector
/// 0x8d42130c) for any caller other than the curve's actual fee-sweep
/// operator. In practice this means RevenueRouter.pullFromEscrow() only
/// ever succeeds when the router itself is that curve's
/// `creatorFeeRecipient` — i.e. enforced-mode agents only, exactly as
/// intended, just enforced by Pons itself rather than by us.
///
/// Separate, not-yet-exercised nuance (our launches all use
/// buybackEnabled=false): pons-mcp's own comment notes sweepFees "reverts
/// ... InternalSwapRequiresOperator for non-operator callers when a buyback
/// is pending" — a second, distinct gate that may apply once buyback is
/// enabled for a given curve. Revisit if RevenueRouter is ever used with an
/// enforced-mode agent that also has buybackEnabled=true.
interface IPonsCurve {
    function buy(uint256 amountIn, uint256 minOut, address who) external payable returns (uint256);
    function sell(uint256 tokensIn, uint256 minOut, address who) external returns (uint256);
    function sweepFees(uint256 minBuybackTokensOut) external;
    function quoteFeeBalance() external view returns (uint256);
    function creatorTaxBalance() external view returns (uint256);
    function buybackQuoteBalance() external view returns (uint256);
    function deployer() external view returns (address);
}
