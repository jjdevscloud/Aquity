// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILaunchpadFactory, ILaunchpadPool} from "./interfaces/ILaunchpadFactory.sol";
import {AgentRegistry} from "./AgentRegistry.sol";
import {Vesting} from "./Vesting.sol";
import {Vault} from "./Vault.sol";
import {Splitter} from "./Splitter.sol";
import {FeeRouter} from "./FeeRouter.sol";
import {Distributor} from "./Distributor.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFeeEscrow} from "./mocks/MockFeeEscrow.sol";
import {MockRouter} from "./mocks/MockRouter.sol";

/// @title Launcher
/// @notice AQUITY-SPEC §3.3 + §10 Phase 5: one permissionless call that both
/// registers the agent's identity AND stands up its entire revenue-sharing
/// stack — token, vault, splitter, fee router, distributor, vesting — so
/// registering an agent never again needs a manual per-agent follow-up
/// deploy the way the very first (YREV) agent did.
///
/// "Pick a company to pair with" is still backed by MockLaunchpadFactory and
/// MockRouter, not a real Robinhood Chain launchpad — AQUITY-SPEC §3.2's
/// "which stock tokens are approved as pair assets" is still unresolved.
/// But pairing is now real within that mock world instead of ignored: the
/// first agent to pick a given company's (name, symbol) deploys a dedicated
/// MockERC20 for it and seeds the shared MockRouter with a swap rate and
/// liquidity; every later agent that picks the same company reuses that
/// same stock token and fee escrow. Both mocks allow anyone to mint or set
/// a rate — a real deployment must replace this with the actual launchpad's
/// approved pair assets and swap venue.
contract Launcher is Ownable {
    ILaunchpadFactory public factory;
    AgentRegistry public immutable registry;
    IERC20 public immutable paymentToken;
    MockRouter public immutable router;
    /// @notice Owner/admin assigned to every Vesting contract this deploys —
    /// can rotate a Vesting's revenue reporter later. Defaults to this
    /// contract's owner.
    address public vestingAdmin;

    /// @dev 1 paymentToken -> 2 stock, MockRouter's RATE_PRECISION-scaled.
    uint256 public constant DEFAULT_RATE = 2e18;
    uint256 public constant STOCK_LIQUIDITY_SEED = 1_000_000e18;
    /// @dev Matches the slippage cap DeployTestnetDemo.s.sol used for the
    /// original hand-deployed YREV agent.
    uint256 public constant MAX_SLIPPAGE_BPS = 500;
    uint256 public constant DUST_THRESHOLD = 1e15;

    /// @notice One stock token per company symbol, auto-provisioned on first
    /// use and reused by every later agent pairing with the same company.
    mapping(bytes32 symbolHash => address stockToken) public stockTokenBySymbol;
    /// @notice One fee escrow per stock token, for the same reason —
    /// MockFeeEscrow tracks accrued fees per agentToken but is pinned to a
    /// single fee-paid-in token at construction.
    mapping(address stockToken => address feeEscrow) public feeEscrowByStock;

    struct LaunchParams {
        string name;
        string ticker;
        string agentId;
        address agentKey;
        bytes agentKeySignature;
        string xHandle;
        uint256 xNonce;
        bytes verifierSignature;
        string stockName;
        string stockSymbol;
        string sector;
        uint256 minTokensOut;
        address vestingReporter;
        uint256 vestingRevenueTarget;
        uint256 vaultShareBps;
        uint256 feeSplitBps;
    }

    /// @dev Bundles every contract address `launch` produces in memory so
    /// the function itself only ever holds one local variable for all of
    /// them — passing scalars for each one blows Solidity's stack limit.
    struct AgentContracts {
        address stockToken;
        address agentToken;
        address pool;
        address vault;
        address splitter;
        address feeRouter;
        address distributor;
        address vesting;
    }

    event AgentFullyLaunched(
        uint256 indexed tokenId,
        address indexed owner,
        string ticker,
        string name,
        string sector,
        address agentToken,
        address vault,
        address splitter,
        address feeRouter,
        address distributor,
        address vesting,
        address pool,
        address stockToken
    );

    error ZeroAddress();

    constructor(address _owner, address _registry, address _factory, address _paymentToken, address _router)
        Ownable(_owner)
    {
        if (
            _registry == address(0) || _factory == address(0) || _paymentToken == address(0)
                || _router == address(0)
        ) revert ZeroAddress();
        registry = AgentRegistry(_registry);
        factory = ILaunchpadFactory(_factory);
        paymentToken = IERC20(_paymentToken);
        router = MockRouter(_router);
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
        returns (uint256 tokenId, address agentToken, address vault, address vesting)
    {
        AgentContracts memory c;
        c.stockToken = _resolveStock(p.stockSymbol, p.stockName);
        (c.agentToken, c.pool) = factory.createPair(p.name, p.ticker, c.stockToken);

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
                pair: c.stockToken,
                agentToken: c.agentToken
            })
        );

        _deployRevenueStack(c, msg.sender, p);

        Vesting v = new Vesting(
            c.agentToken, msg.sender, vestingAdmin, p.vestingReporter, address(this), p.vestingRevenueTarget
        );
        c.vesting = address(v);
        ILaunchpadPool(c.pool).buy{value: msg.value}(c.vesting, p.minTokensOut);
        v.lock();

        emit AgentFullyLaunched(
            tokenId,
            msg.sender,
            p.ticker,
            p.name,
            p.sector,
            c.agentToken,
            c.vault,
            c.splitter,
            c.feeRouter,
            c.distributor,
            c.vesting,
            c.pool,
            c.stockToken
        );

        agentToken = c.agentToken;
        vault = c.vault;
        vesting = c.vesting;
    }

    /// @dev Deploys (or reuses) the stock token for a company symbol. First
    /// use per symbol seeds the shared MockRouter with a swap rate and
    /// enough liquidity to fill buys; later uses just return the same token.
    function _resolveStock(string calldata symbol, string calldata name) internal returns (address stockToken) {
        bytes32 key = keccak256(bytes(symbol));
        stockToken = stockTokenBySymbol[key];
        if (stockToken == address(0)) {
            MockERC20 stock = new MockERC20(name, symbol);
            stockToken = address(stock);
            stockTokenBySymbol[key] = stockToken;
            router.setRate(address(paymentToken), stockToken, DEFAULT_RATE);
            stock.mint(address(router), STOCK_LIQUIDITY_SEED);
        }
    }

    /// @dev Deploys this agent's Vault/Splitter/FeeRouter/Distributor and
    /// wires their access control, writing the results into `c` in place
    /// (memory structs are passed by reference).
    function _deployRevenueStack(AgentContracts memory c, address owner_, LaunchParams calldata p) internal {
        Vault vault_ = new Vault(c.stockToken, address(this));
        c.vault = address(vault_);

        address[] memory path = new address[](2);
        path[0] = address(paymentToken);
        path[1] = c.stockToken;
        c.splitter = address(
            new Splitter(
                owner_, owner_, c.vault, address(paymentToken), c.stockToken, address(router), path, p.vaultShareBps, MAX_SLIPPAGE_BPS
            )
        );

        address feeEscrow = feeEscrowByStock[c.stockToken];
        if (feeEscrow == address(0)) {
            feeEscrow = address(new MockFeeEscrow(c.stockToken));
            feeEscrowByStock[c.stockToken] = feeEscrow;
        }
        c.feeRouter = address(new FeeRouter(owner_, c.agentToken, c.stockToken, c.vault, feeEscrow, owner_, p.feeSplitBps));

        c.distributor = address(new Distributor(c.stockToken, c.vault, owner_, owner_, DUST_THRESHOLD));

        vault_.setDepositor(c.splitter, true);
        vault_.setDepositor(c.feeRouter, true);
        vault_.setDistributor(c.distributor);
        vault_.transferOwnership(owner_);
    }
}
