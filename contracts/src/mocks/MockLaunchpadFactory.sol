// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILaunchpadFactory, ILaunchpadPool} from "../interfaces/ILaunchpadFactory.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice Test-only stand-in for a third-party launchpad's trading pool:
/// one per agent token, fixed-price, mints on buy. Not part of the
/// production contract set.
///
/// A previous version of this had the factory itself double as a single
/// shared pool holding one mutable `token` — fine for Launcher's own
/// atomic createPair+buy, broken for any *later*, separate buy() call: a
/// newer agent launching would silently repoint `token` out from under
/// every older agent's pool. One pool per agent, deployed at createPair
/// time, has no such shared state to clobber.
contract MockLaunchpadPool is ILaunchpadPool {
    address public immutable token;
    /// @dev tokens minted per wei of ETH sent to buy().
    uint256 public constant TOKENS_PER_WEI = 1000;

    constructor(address _token) {
        token = _token;
    }

    function buy(address to, uint256 minTokensOut) external payable returns (uint256 tokensOut) {
        tokensOut = msg.value * TOKENS_PER_WEI;
        require(tokensOut >= minTokensOut, "MockLaunchpadPool: insufficient output");
        MockERC20(token).mint(to, tokensOut);
    }
}

/// @notice Test-only stand-in for a third-party launchpad factory: deploys a
/// new MockERC20 as the agent token plus a dedicated MockLaunchpadPool for
/// it. Not part of the production contract set.
contract MockLaunchpadFactory is ILaunchpadFactory {
    function createPair(string calldata name, string calldata symbol, address /* pairAsset */ )
        external
        returns (address token_, address pool_)
    {
        MockERC20 t = new MockERC20(name, symbol);
        MockLaunchpadPool p = new MockLaunchpadPool(address(t));
        return (address(t), address(p));
    }
}
