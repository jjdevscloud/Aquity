// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILaunchpadFactory, ILaunchpadPool} from "./interfaces/ILaunchpadFactory.sol";
import {AgentRegistry} from "./AgentRegistry.sol";
import {Vesting} from "./Vesting.sol";

/// @title Launcher
/// @notice AQUITY-SPEC §3.3: "Calls the third-party launchpad factory to
/// deploy the token paired to the chosen stock, in the same transaction as
/// registration. Makes the first buy and routes it into Vesting." One call,
/// four effects: token created, identity registered, first buy made, builder
/// allocation locked.
contract Launcher is Ownable {
    ILaunchpadFactory public factory;
    AgentRegistry public immutable registry;
    /// @notice Owner/admin assigned to every Vesting contract this deploys —
    /// can rotate a Vesting's revenue reporter later. Defaults to this
    /// contract's owner.
    address public vestingAdmin;

    struct LaunchParams {
        string name;
        string ticker;
        string agentId;
        address agentKey;
        bytes agentKeySignature;
        string xHandle;
        uint256 xNonce;
        bytes verifierSignature;
        address pairStockToken;
        uint256 minTokensOut;
        address vestingReporter;
        uint256 vestingRevenueTarget;
    }

    event AgentLaunched(
        uint256 indexed tokenId, address indexed owner, address agentToken, address pool, address vesting
    );

    error ZeroAddress();

    constructor(address _owner, address _registry, address _factory) Ownable(_owner) {
        if (_registry == address(0) || _factory == address(0)) revert ZeroAddress();
        registry = AgentRegistry(_registry);
        factory = ILaunchpadFactory(_factory);
        vestingAdmin = _owner;
    }

    function setFactory(address _factory) external onlyOwner {
        if (_factory == address(0)) revert ZeroAddress();
        factory = ILaunchpadFactory(_factory);
    }

    function setVestingAdmin(address _vestingAdmin) external onlyOwner {
        if (_vestingAdmin == address(0)) revert ZeroAddress();
        vestingAdmin = _vestingAdmin;
    }

    function launch(LaunchParams calldata p)
        external
        payable
        returns (uint256 tokenId, address agentToken, address pool, address vesting)
    {
        (agentToken, pool) = factory.createPair(p.name, p.ticker, p.pairStockToken);

        tokenId = registry.register(
            AgentRegistry.RegisterParams({
                owner: msg.sender,
                name: p.name,
                ticker: p.ticker,
                agentId: p.agentId,
                agentKey: p.agentKey,
                agentKeySignature: p.agentKeySignature,
                xHandle: p.xHandle,
                xNonce: p.xNonce,
                verifierSignature: p.verifierSignature,
                pair: p.pairStockToken,
                agentToken: agentToken
            })
        );

        Vesting v = new Vesting(
            agentToken, msg.sender, vestingAdmin, p.vestingReporter, address(this), p.vestingRevenueTarget
        );
        vesting = address(v);

        ILaunchpadPool(pool).buy{value: msg.value}(vesting, p.minTokensOut);
        v.lock();

        emit AgentLaunched(tokenId, msg.sender, agentToken, pool, vesting);
    }
}
