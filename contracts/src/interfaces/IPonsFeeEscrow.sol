// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Real PonsV2FeeEscrow on Robinhood Chain mainnet, at
/// 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e (read live via
/// IPonsFactory.feeEscrow(), not hardcoded here) — not a mock. Selectors
/// verified against github.com/ponsmcp/pons-mcp's self-checking ABI table
/// (src/abi.ts) and confirmed against real deployed bytecode this session
/// (eth_getCode + eth_call against rpc.mainnet.chain.robinhood.com).
///
/// Fees accrue in the curve's own quote asset. Every agent launched through
/// PonsLauncher.sol uses native ETH as that quote asset (NATIVE_PAIR =
/// address(0)), so `claim()` — not `claimToken` — is what pays out here.
///
/// IMPORTANT (found via this session's own fork test, not assumed): fees do
/// NOT show up here automatically as trades happen. They accrue on the
/// CURVE itself first (see IPonsCurve.creatorTaxBalance) and only land in
/// this escrow once someone calls `sweepFees` on that curve — `claim()`
/// reverts with the curve's own `NoBalance()` (confirmed: selector
/// 0xc2caa2a6) until that's done. Also: the native-ETH claimable balance is
/// the plain `balanceOf(address)` (standard ERC20-style selector,
/// 0x70a08231) — NOT `balanceOfToken(account, address(0))`, which returned
/// 0 for a real, nonzero balance when tried directly against this escrow.
interface IPonsFeeEscrow {
    /// @notice Claims all of msg.sender's accrued native-ETH creator fees
    /// and sends them to msg.sender. The selector table only fixes the
    /// signature, not whether it actually returns the claimed amount — real
    /// callers (RevenueRouter) don't trust this return value either way and
    /// measure their own balance delta instead. Reverts with `NoBalance()`
    /// when there's nothing accrued — callers should check `balanceOf`
    /// first rather than assume.
    function claim() external returns (uint256 amount);

    /// @notice Read-only accrued **native ETH** balance for `account`. The
    /// one that actually reflects reality for our launches — see the
    /// interface-level doc comment above.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Read-only accrued balance for `account`, denominated in a
    /// specific ERC-20 `token` — for creators whose curve quotes in an
    /// ERC-20 rather than native ETH. Not used by our own launches.
    function balanceOfToken(address account, address token) external view returns (uint256);
}
