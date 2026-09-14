// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal Uniswap-V2-shaped router interface. Robinhood Chain is a
/// standard EVM (Arbitrum Orbit L2); most Orbit-chain DEXs (Camelot, Uniswap
/// V2 forks) expose this surface. Point `router` at the real deployed router
/// once it's known — nothing else in Splitter needs to change.
interface ISwapRouter {
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
