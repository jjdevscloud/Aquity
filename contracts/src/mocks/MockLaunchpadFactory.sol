// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILaunchpadFactory, ILaunchpadPool} from "../interfaces/ILaunchpadFactory.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice Test-only stand-in for a third-party launchpad: deploys a new
/// MockERC20 as the agent token and itself as a fixed-price "pool" that
/// mints on buy. Not part of the production contract set.
contract MockLaunchpadFactory is ILaunchpadFactory, ILaunchpadPool {
    address public token;
    /// @dev tokens minted per wei of ETH sent to buy().
    uint256 public constant TOKENS_PER_WEI = 1000;

    function createPair(string calldata name, string calldata symbol, address /* pairAsset */ )
        external
        returns (address token_, address pool_)
    {
        MockERC20 t = new MockERC20(name, symbol);
        token = address(t);
        return (address(t), address(this));
    }

    function buy(address to, uint256 minTokensOut) external payable returns (uint256 tokensOut) {
        tokensOut = msg.value * TOKENS_PER_WEI;
        require(tokensOut >= minTokensOut, "MockLaunchpadFactory: insufficient output");
        MockERC20(token).mint(to, tokensOut);
    }
}
