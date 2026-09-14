// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";

/// @notice Test-only fixed-price swap venue standing in for Robinhood Chain's
/// real router. Must be pre-funded with the output token. Not part of the
/// production contract set.
contract MockRouter is ISwapRouter {
    using SafeERC20 for IERC20;

    uint256 public constant RATE_PRECISION = 1e18;

    /// @dev price of tokenIn expressed in tokenOut, scaled by RATE_PRECISION.
    mapping(address => mapping(address => uint256)) public rate;

    /// @dev extra haircut applied only at execution time, not in getAmountsOut's
    /// quote — lets tests simulate a venue that delivers less than it quoted.
    uint256 public executionHaircutBps;

    function setRate(address tokenIn, address tokenOut, uint256 rate_) external {
        rate[tokenIn][tokenOut] = rate_;
    }

    function setExecutionHaircutBps(uint256 bps) external {
        executionHaircutBps = bps;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        public
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 1; i < path.length; i++) {
            uint256 r = rate[path[i - 1]][path[i]];
            amounts[i] = (amounts[i - 1] * r) / RATE_PRECISION;
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        uint256 amountOut = amounts[amounts.length - 1];
        amountOut = (amountOut * (10_000 - executionHaircutBps)) / 10_000;
        amounts[amounts.length - 1] = amountOut;
        require(amountOut >= amountOutMin, "MockRouter: insufficient output");

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(path[path.length - 1]).safeTransfer(to, amountOut);
    }
}
