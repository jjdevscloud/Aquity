// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPonsFeeEscrow} from "./interfaces/IPonsFeeEscrow.sol";
import {IPonsCurve} from "./interfaces/IPonsCurve.sol";
import {ISwapRouterV3} from "./interfaces/ISwapRouterV3.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {Vault} from "./Vault.sol";

/// @title RevenueRouter
/// @notice Real mainnet replacement for FeeRouter.sol's mock-shaped
/// assumptions (see that file — it assumed fees already arrive in the
/// paired stock token; real Pons creator fees accrue in native ETH). One
/// instance per agent. Serves both Phase B trust models with the same
/// splitting logic:
///
///   - `pullFromEscrow` — permissionless; only does anything when this
///     contract itself is the agent's Pons `creatorFeeRecipient`
///     (enforced mode, set at launch by PonsLauncherV2.sol).
///   - `contribute` — permissionless; for voluntary mode, where the
///     agent's own wallet is still `creatorFeeRecipient` and claims its
///     own fees itself, then forwards some of that ETH here whenever it
///     wants to honor "return capital to holders."
///
/// Both split the ETH they receive by `feeSplitBps`: the agent's share is
/// sent as raw ETH (useful for compute costs, no needless swap); the
/// holder share is swapped to the agent's paired stock token via the real
/// Uniswap V3 SwapRouter02 and deposited into the existing, unchanged
/// Vault.sol/Distributor.sol pair for time-weighted Merkle payout.
///
/// Slippage protection is deliberately the CALLER's responsibility
/// (`minStockOut`), not computed on-chain — this contract has no oracle or
/// Quoter dependency, and hand-rolling sqrtPriceX96 math on-chain as a
/// "safe" bound is itself a real bug surface for a contract that moves
/// real money. Whoever triggers these functions (our own keeper, or the
/// agent's own bot for `contribute`) must fetch a fresh quote first.
contract RevenueRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public immutable agentWallet;
    IERC20 public immutable stockToken;
    Vault public immutable vault;
    /// @notice This agent's own Pons bonding-curve pool — creator-tax fees
    /// accrue here first (Pons's own design) and must be swept via
    /// `sweepFees` before PonsV2FeeEscrow has anything to claim. See
    /// IPonsCurve.sol's doc comment; found via this session's own fork test,
    /// not documented anywhere before that.
    ///
    /// NOT set at construction — deliberately mutable, set once via
    /// `setCurve`. The real enforced-mode launch flow (PonsLauncherV2.sol)
    /// must deploy this router BEFORE calling Pons's factory (since
    /// `creatorFeeRecipient` in that call needs this router's address), but
    /// Pons only returns the curve's address AFTER that same call returns —
    /// an unavoidable ordering constraint, not a design choice.
    IPonsCurve public curve;
    IPonsFeeEscrow public immutable feeEscrow;
    ISwapRouterV3 public immutable swapRouter;
    IWETH public immutable weth;
    /// @notice The real Uniswap V3 fee tier with confirmed liquidity for
    /// stockToken/WETH — set once per agent at deploy time (e.g. 500 for
    /// the real AAPL/WETH 0.05% pool confirmed this session), since
    /// different stocks may only have liquidity at a different tier.
    uint24 public immutable poolFee;

    /// @notice bps of every ETH amount routed here that goes to holders
    /// (via Vault, swapped into stockToken); the remainder goes to
    /// agentWallet as raw ETH. Mirrors the mandate's "return to holders" %.
    uint256 public feeSplitBps;

    event Routed(uint256 ethIn, uint256 agentShareEth, uint256 holderShareEth, uint256 stockOut);
    event FeeSplitUpdated(uint256 feeSplitBps);

    error NothingToRoute();
    error InvalidBps();
    error ZeroAddress();
    error AgentTransferFailed();
    error CurveAlreadySet();
    error CurveNotSet();

    event CurveSet(address curve);

    constructor(
        address _owner,
        address _agentWallet,
        address _stockToken,
        address _vault,
        address _feeEscrow,
        address _swapRouter,
        address _weth,
        uint24 _poolFee,
        uint256 _feeSplitBps
    ) Ownable(_owner) {
        if (
            _agentWallet == address(0) || _stockToken == address(0) || _vault == address(0)
                || _feeEscrow == address(0) || _swapRouter == address(0) || _weth == address(0)
        ) revert ZeroAddress();
        if (_feeSplitBps > BPS_DENOMINATOR) revert InvalidBps();

        agentWallet = _agentWallet;
        stockToken = IERC20(_stockToken);
        vault = Vault(_vault);
        feeEscrow = IPonsFeeEscrow(_feeEscrow);
        swapRouter = ISwapRouterV3(_swapRouter);
        weth = IWETH(_weth);
        poolFee = _poolFee;
        feeSplitBps = _feeSplitBps;
    }

    /// @notice Set once, right after this agent's real Pons launch returns
    /// its curve address (see PonsLauncherV2.sol) — see `curve`'s doc
    /// comment for why this can't happen at construction.
    function setCurve(address _curve) external onlyOwner {
        if (address(curve) != address(0)) revert CurveAlreadySet();
        if (_curve == address(0)) revert ZeroAddress();
        curve = IPonsCurve(_curve);
        emit CurveSet(_curve);
    }

    function setFeeSplitBps(uint256 _feeSplitBps) external onlyOwner {
        if (_feeSplitBps > BPS_DENOMINATOR) revert InvalidBps();
        feeSplitBps = _feeSplitBps;
        emit FeeSplitUpdated(_feeSplitBps);
    }

    /// @notice Pulls this contract's own accrued native-ETH creator fees
    /// from Pons's real fee escrow and routes them. Sweeps the curve first
    /// — fees sit there, not in the escrow, until swept (see `curve`'s doc
    /// comment); only the curve's actual fee-sweep operator can do this
    /// (reverts `NotFeeSweepOperator()`, confirmed via a real fork test —
    /// this router must itself be that curve's `creatorFeeRecipient` for
    /// this to ever succeed, i.e. enforced mode only). `minStockOut` bounds
    /// the swap leg — caller must supply a real, freshly-fetched quote.
    function pullFromEscrow(uint256 minStockOut) external nonReentrant {
        if (address(curve) == address(0)) revert CurveNotSet();
        curve.sweepFees(0);
        if (feeEscrow.balanceOf(address(this)) == 0) revert NothingToRoute();

        uint256 before = address(this).balance;
        feeEscrow.claim();
        uint256 received = address(this).balance - before;
        if (received == 0) revert NothingToRoute();
        _splitAndRoute(received, minStockOut);
    }

    /// @notice Voluntary contribution path — anyone (typically the agent's
    /// own wallet, already holding fees Pons paid it directly) can send ETH
    /// here to be split and routed exactly like an enforced claim.
    function contribute(uint256 minStockOut) external payable nonReentrant {
        if (msg.value == 0) revert NothingToRoute();
        _splitAndRoute(msg.value, minStockOut);
    }

    function _splitAndRoute(uint256 ethAmount, uint256 minStockOut) internal {
        uint256 holderShare = (ethAmount * feeSplitBps) / BPS_DENOMINATOR;
        uint256 agentShare = ethAmount - holderShare;

        uint256 stockOut = 0;
        if (holderShare > 0) {
            stockOut = _swapToStock(holderShare, minStockOut);
            stockToken.forceApprove(address(vault), stockOut);
            vault.deposit(stockOut);
        }
        if (agentShare > 0) {
            (bool ok,) = agentWallet.call{value: agentShare}("");
            if (!ok) revert AgentTransferFailed();
        }

        emit Routed(ethAmount, agentShare, holderShare, stockOut);
    }

    function _swapToStock(uint256 ethAmount, uint256 minStockOut) internal returns (uint256 stockOut) {
        weth.deposit{value: ethAmount}();
        IERC20(address(weth)).forceApprove(address(swapRouter), ethAmount);

        stockOut = swapRouter.exactInputSingle(
            ISwapRouterV3.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(stockToken),
                fee: poolFee,
                recipient: address(this),
                amountIn: ethAmount,
                amountOutMinimum: minStockOut,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /// @dev Receives ETH from feeEscrow.claim() and from contribute()'s
    /// plain value transfer.
    receive() external payable {}
}
