// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal stand-in for the third-party launchpad factory Launcher
/// deploys agent tokens through (AQUITY-SPEC §3.2 open question: which
/// launchpad, which pair assets have real depth). Robinhood Chain's own
/// launchpad ABI, or pump.fun Custom Pairs, must be confirmed and this
/// interface reshaped to match before any real deployment — nothing else in
/// Launcher needs to change once it is.
interface ILaunchpadFactory {
    /// @notice Deploys a new token paired against `pairAsset` (the chosen
    /// company's tokenized stock) and returns it plus its trading pool.
    function createPair(string calldata name, string calldata symbol, address pairAsset)
        external
        returns (address token, address pool);
}

/// @notice The pool/bonding-curve contract returned by ILaunchpadFactory.
interface ILaunchpadPool {
    function token() external view returns (address);

    /// @notice Buys the pool's token with native ETH, sending output to `to`.
    function buy(address to, uint256 minTokensOut) external payable returns (uint256 tokensOut);
}
