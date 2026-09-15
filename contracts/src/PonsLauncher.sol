// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AgentRegistry} from "./AgentRegistry.sol";
import {IPonsFactory} from "./interfaces/IPonsFactory.sol";

/// @title PonsLauncher
/// @notice Mainnet-only counterpart to Launcher.sol: registers the agent's
/// identity exactly the same way (AgentRegistry.register, unchanged), but
/// launches its token for real on Pons v2 — Robinhood Chain's live
/// launchpad (github.com/ponsmcp/pons-mcp; see IPonsFactory.sol) — instead
/// of a mock factory. Creator fees are mandatorily routed to the agent's
/// own wallet (`agentKey`), never the human owner's.
///
/// The agent's own wallet is the caller — `owner` is an explicit param
/// rather than `msg.sender`, since the human owner never sends this
/// transaction at all. The owner funds the agent's wallet first (a plain
/// transfer, handled entirely in the frontend — see aquity.html's "fund
/// your agent" step); the agent then spends that ETH itself to pay Pons's
/// launch fee and gas, submitting a transaction it signed for itself.
/// Requiring `msg.sender == agentKey` makes that a rule, not a convention
/// — see `launch()`. This is still just as safe if some *other* address
/// relayed the transaction on the agent's behalf, since the on-chain
/// guarantee is `agentKeySignature` (checked by AgentRegistry.register(),
/// unchanged), not who happens to submit the transaction — the
/// `msg.sender` check below is about matching the product's intent
/// (the agent, autonomously, launches its own token) on top of that.
///
/// Pons's own `pairToken` is just the bonding curve's quote asset (kept as
/// native ETH here, Pons's own default) — unrelated to which company's
/// Stock Token this agent is paired with on *our* identity layer
/// (`p.pairStock`, AgentRegistry's `pair` field). Nothing here buys that
/// stock; that's the agent's own Vault, Phase B.
contract PonsLauncher is Ownable {
    IPonsFactory public factory;
    AgentRegistry public immutable registry;

    /// @dev Pons's default launch config (id 0) and native-ETH quote asset
    /// — see IPonsFactory.previewLaunchEconomics. Not currently exposed as
    /// a param; every agent launches on the same config for now.
    uint256 public constant LAUNCH_CONFIG_ID = 0;
    address public constant NATIVE_PAIR = address(0);

    /// @dev Base for the real deep link embedded as this launch's
    /// socials.website — resolves to this exact agent's page (aquity.html
    /// reads `#agent/<ticker>` from location.hash — see openA()). Update if
    /// the site ever moves off GitHub Pages.
    string public constant WEBSITE_BASE = "https://jjdevscloud.github.io/Aquity/aquity.html#agent/";

    struct LaunchParams {
        /// @dev Explicit, not msg.sender — see contract-level doc comment.
        address owner;
        string name;
        string ticker;
        string agentId;
        address agentKey;
        bytes agentKeySignature;
        string xHandle;
        uint256 xNonce;
        bytes verifierSignature;
        /// @dev The real Robinhood Stock Token this agent is paired with —
        /// recorded on AgentRegistry, not passed to Pons.
        address pairStock;
        string logo;
        string description;
        /// @dev Embedded as-is into Pons's socials.twitter — the same
        /// handle the X-verification step already confirmed.
        string twitterHandle;
        /// @dev 0-10000 (0-100%), capped by Pons's own maxCreatorTaxBps().
        uint16 creatorTaxBps;
        bool buybackEnabled;
    }

    event AgentLaunchedOnPons(
        uint256 indexed tokenId, address indexed owner, address indexed agentKey, string ticker, address agentToken, address curve
    );

    error ZeroAddress();
    error WrongLaunchFee(uint256 required, uint256 sent);
    error TickerTaken();
    error XHandleTaken();
    error NotAgentKey();

    constructor(address _owner, address _registry, address _factory) Ownable(_owner) {
        if (_registry == address(0) || _factory == address(0)) revert ZeroAddress();
        registry = AgentRegistry(_registry);
        factory = IPonsFactory(_factory);
    }

    function setFactory(address _factory) external onlyOwner {
        if (_factory == address(0)) revert ZeroAddress();
        factory = IPonsFactory(_factory);
    }

    /// @notice One transaction, sent by the agent's own wallet (funded by
    /// the owner beforehand): launches the agent's token for real on Pons
    /// (creator fees to `agentKey`) and registers its identity. Pre-checks
    /// ticker/X-handle availability *before* spending Pons's real
    /// launchFee — AgentRegistry.register() can't be called first because
    /// it requires a nonzero `agentToken`, which only exists after Pons
    /// deploys it.
    function launch(LaunchParams calldata p) external payable returns (uint256 tokenId, address agentToken, address curve) {
        if (msg.sender != p.agentKey) revert NotAgentKey();
        if (p.pairStock == address(0) || p.owner == address(0)) revert ZeroAddress();
        if (registry.tickerUsed(p.ticker)) revert TickerTaken();
        if (registry.xHandleUsed(keccak256(bytes(p.xHandle)))) revert XHandleTaken();

        uint256 fee = factory.launchFee();
        if (msg.value != fee) revert WrongLaunchFee(fee, msg.value);

        IPonsFactory.TokenParams memory tp = IPonsFactory.TokenParams({
            name: p.name,
            symbol: p.ticker,
            logo: p.logo,
            description: p.description,
            socials: IPonsFactory.Socials({
                twitter: p.twitterHandle,
                telegram: "",
                discord: "",
                website: string.concat(WEBSITE_BASE, p.ticker),
                farcaster: ""
            }),
            creatorFeeRecipient: p.agentKey,
            creatorTaxBps: p.creatorTaxBps,
            buybackEnabled: p.buybackEnabled,
            expectedEconomics: factory.previewLaunchEconomics(LAUNCH_CONFIG_ID, NATIVE_PAIR),
            salt: keccak256(abi.encodePacked(p.name, " ", p.ticker, " "))
        });

        address[] memory noExemptions = new address[](0);
        (agentToken, curve) =
            factory.launchToken{value: msg.value}(tp, LAUNCH_CONFIG_ID, NATIVE_PAIR, noExemptions);

        tokenId = registry.register(
            AgentRegistry.RegisterParams({
                owner: p.owner,
                name: p.name,
                ticker: p.ticker,
                agentId: p.agentId,
                agentKey: p.agentKey,
                agentKeySignature: p.agentKeySignature,
                xHandle: p.xHandle,
                xNonce: p.xNonce,
                verifierSignature: p.verifierSignature,
                pair: p.pairStock,
                agentToken: agentToken
            })
        );

        emit AgentLaunchedOnPons(tokenId, p.owner, p.agentKey, p.ticker, agentToken, curve);
    }
}
