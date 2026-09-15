// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Answers AQUITY-SPEC.md §3.2's open question on Robinhood Chain
/// mainnet: can a smart contract (not just an EOA wallet) hold a Stock
/// Token? Deliberately empty — a standard ERC-20 `transfer()` calls
/// nothing on the recipient, so existing as a contract address is the
/// entire test. If it can't hold one, the token's transfer() itself
/// enforces that (an allowlist/KYC check, a `to.code.length == 0` guard,
/// etc.) and the send reverts; nothing here needs to anticipate that.
///
/// Not part of the production contract set — throwaway, one-off test.
contract StockTokenCustodyTest {}
