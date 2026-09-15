// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AgentRegistry} from "./AgentRegistry.sol";
import {IPonsFactory} from "./interfaces/IPonsFactory.sol";
import {Vault} from "./Vault.sol";
import {Distributor} from "./Distributor.sol";
import {RevenueRouter} from "./RevenueRouter.sol";

/// @title PonsLauncherV2
/// @notice Fork of PonsLauncher.sol (the real, live, already-used mainnet
/// launcher — see that file's doc comment for the base flow, unchanged
/// here) adding Phase B's enforced-routing option. When
/// `p.enforcedRevenueRouting` is false, `launch()` is byte-for-byte what
/// PonsLauncher already does: `creatorFeeRecipient = p.agentKey`, nothing
/// else deployed. When true, this deploys a real Vault + Distributor +
/// RevenueRouter for the agent BEFORE calling Pons (RevenueRouter's address
/// is needed as `creatorFeeRecipient`), then finishes wiring RevenueRouter
/// with the curve's real address right after Pons returns it — see
/// RevenueRouter.sol's `curve` doc comment for why that has to happen in
/// this order, not the constructor.
///
/// Existing agents launched through PonsLauncher (the original) are
/// entirely unaffected — this is a separate deployment (see
/// script/DeployPonsLauncherV2Mainnet.s.sol), and AgentRegistry.setLauncher
/// only changes where *future* launches go.
contract PonsLauncherV2 is Ownable {
    IPonsFactory public factory;
    AgentRegistry public immutable registry;
    address public immutable swapRouter;
    address public immutable weth;

    /// @notice Signs Distributor's Merkle roots for every enforced-mode
    /// agent — the same off-chain distribution job (Phase B, M3) posts for
    /// all of them, so this is a launcher-level setting, not per-agent.
    address public rootPoster;

    uint256 public constant LAUNCH_CONFIG_ID = 0;
    address public constant NATIVE_PAIR = address(0);
    /// @dev Matches Launcher.sol's DUST_THRESHOLD — the minimum per-holder
    /// stock amount `Distributor.sweep` will push automatically.
    uint256 public constant DUST_THRESHOLD = 1e15;

    string public constant WEBSITE_BASE = "https://jjdevscloud.github.io/Aquity/aquity.html#agent/";

    struct LaunchParams {
        address owner;
        string name;
        string ticker;
        string agentId;
        address agentKey;
        bytes agentKeySignature;
        string xHandle;
        uint256 xNonce;
        bytes verifierSignature;
        address pairStock;
        string logo;
        string description;
        string twitterHandle;
        uint16 creatorTaxBps;
        bool buybackEnabled;
        /// @notice When true, creator fees route through a real,
        /// newly-deployed RevenueRouter instead of straight to `agentKey`.
        bool enforcedRevenueRouting;
        /// @notice bps of every routed ETH amount that goes to holders via
        /// the new Vault (the rest to `agentKey` as raw ETH) — ignored
        /// when `enforcedRevenueRouting` is false. Mirrors the mandate's
        /// "return to holders" %.
        uint256 holderFeeSplitBps;
        /// @notice The real Uniswap V3 fee tier with confirmed liquidity
        /// for pairStock/WETH (e.g. 500 for the real AAPL/WETH pool
        /// confirmed this session) — ignored when `enforcedRevenueRouting`
        /// is false. Not discovered on-chain here; whoever builds the
        /// launch package must have already confirmed it, same way this
        /// session confirmed AAPL's.
        uint24 revenuePoolFee;
    }

    event AgentLaunchedOnPons(
        uint256 indexed tokenId, address indexed owner, address indexed agentKey, string ticker, address agentToken, address curve
    );
    event EnforcedRevenueRoutingDeployed(uint256 indexed tokenId, address vault, address distributor, address revenueRouter);
    event RootPosterUpdated(address rootPoster);

    error ZeroAddress();
    error WrongLaunchFee(uint256 required, uint256 sent);
    error TickerTaken();
    error XHandleTaken();
    error NotAgentKey();

    constructor(address _owner, address _registry, address _factory, address _swapRouter, address _weth, address _rootPoster)
        Ownable(_owner)
    {
        if (_registry == address(0) || _factory == address(0) || _swapRouter == address(0) || _weth == address(0) || _rootPoster == address(0))
        {
            revert ZeroAddress();
        }
        registry = AgentRegistry(_registry);
        factory = IPonsFactory(_factory);
        swapRouter = _swapRouter;
        weth = _weth;
        rootPoster = _rootPoster;
    }

    function setFactory(address _factory) external onlyOwner {
        if (_factory == address(0)) revert ZeroAddress();
        factory = IPonsFactory(_factory);
    }

    function setRootPoster(address _rootPoster) external onlyOwner {
        if (_rootPoster == address(0)) revert ZeroAddress();
        rootPoster = _rootPoster;
        emit RootPosterUpdated(_rootPoster);
    }

    function launch(LaunchParams calldata p) external payable returns (uint256 tokenId, address agentToken, address curve) {
        if (msg.sender != p.agentKey) revert NotAgentKey();
        if (p.pairStock == address(0) || p.owner == address(0)) revert ZeroAddress();
        if (registry.tickerUsed(p.ticker)) revert TickerTaken();
        if (registry.xHandleUsed(keccak256(bytes(p.xHandle)))) revert XHandleTaken();

        uint256 fee = factory.launchFee();
        if (msg.value != fee) revert WrongLaunchFee(fee, msg.value);

        RevenueRouter revenueRouter;
        Vault vault;
        Distributor distributor;
        address creatorFeeRecipient = p.agentKey;

        if (p.enforcedRevenueRouting) {
            (vault, distributor, revenueRouter) = _deployRevenueStack(p);
            creatorFeeRecipient = address(revenueRouter);
        }

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
            creatorFeeRecipient: creatorFeeRecipient,
            creatorTaxBps: p.creatorTaxBps,
            buybackEnabled: p.buybackEnabled,
            expectedEconomics: factory.previewLaunchEconomics(LAUNCH_CONFIG_ID, NATIVE_PAIR),
            salt: keccak256(abi.encodePacked(p.name, " ", p.ticker, " "))
        });

        address[] memory noExemptions = new address[](0);
        (agentToken, curve) = factory.launchToken{value: msg.value}(tp, LAUNCH_CONFIG_ID, NATIVE_PAIR, noExemptions);

        if (p.enforcedRevenueRouting) {
            revenueRouter.setCurve(curve);
            vault.transferOwnership(p.owner);
            distributor.transferOwnership(p.owner);
            revenueRouter.transferOwnership(p.owner);
        }

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
        if (p.enforcedRevenueRouting) {
            emit EnforcedRevenueRoutingDeployed(tokenId, address(vault), address(distributor), address(revenueRouter));
        }
    }

    /// @dev All three deployed with `address(this)` as temporary owner so
    /// this contract can wire them together before handing ownership to
    /// `p.owner` at the end of `launch()` — same pattern Launcher.sol
    /// (the old testnet launcher) already used for its own revenue stack.
    function _deployRevenueStack(LaunchParams calldata p)
        internal
        returns (Vault vault, Distributor distributor, RevenueRouter revenueRouter)
    {
        vault = new Vault(p.pairStock, address(this));
        distributor = new Distributor(p.pairStock, address(vault), address(this), rootPoster, DUST_THRESHOLD);
        revenueRouter = new RevenueRouter(
            address(this),
            p.agentKey,
            p.pairStock,
            address(vault),
            factory.feeEscrow(),
            swapRouter,
            weth,
            p.revenuePoolFee,
            p.holderFeeSplitBps
        );

        vault.setDepositor(address(revenueRouter), true);
        vault.setDistributor(address(distributor));
    }
}
