// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Real Uniswap V3 SwapRouter02 on Robinhood Chain mainnet, at
/// 0xCaf681a66D020601342297493863E78C959E5cb2 — confirmed this session
/// against real deployed bytecode (eth_getCode) and cross-referenced live
/// (its own `factory()` call returns the real V3 factory at
/// 0x1F7d7550B1b028F7571e69A784071F0205fd2EfA). This is the SwapRouter02
/// shape — `ExactInputSingleParams` has no `deadline` field, unlike the
/// original SwapRouter; confirmed by checking which selector
/// (0x04e45aaf vs 0x414bf389) is actually present in the deployed bytecode.
interface ISwapRouterV3 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of `params.tokenIn` for `params.tokenOut`.
    /// Caller must have approved this router for `amountIn` of tokenIn
    /// first (no native-ETH path is used here — RevenueRouter always wraps
    /// to WETH before calling this).
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    function factory() external view returns (address);
    function WETH9() external view returns (address);
}
