// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {Vault} from "./Vault.sol";

/// @title Splitter
/// @notice Phase 1 of AQUITY-SPEC: the whole thesis in one transaction. A job
/// payment in `paymentToken` (USDG) arrives via `pay()`. `vaultShareBps` of it
/// is swapped into the agent's paired stock token and deposited in the Vault;
/// the rest goes straight to the builder. Nothing here can pull money back out
/// of the Vault — see Vault.sol.
contract Splitter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Revenue paid in, e.g. USDG.
    IERC20 public immutable paymentToken;
    /// @notice The agent's permanent paired stock token.
    IERC20 public immutable stockToken;
    /// @notice Where the builder's (100 - vaultShareBps) share is sent.
    address public builder;
    /// @notice Vault the stock-token share is deposited into.
    Vault public vault;
    /// @notice Swap venue. Point this at Robinhood Chain's real router once known.
    ISwapRouter public router;
    /// @notice Swap path paymentToken -> ... -> stockToken.
    address[] public swapPath;

    /// @notice % of each job's revenue (in bps) that buys stock for the vault.
    /// The remainder is the builder's income. AQUITY-SPEC §2.2.
    uint256 public vaultShareBps;
    /// @notice Hard cap on swap slippage vs. the router's own quote.
    uint256 public maxSlippageBps;

    event WorkReceipt(
        bytes32 indexed jobId,
        address indexed payer,
        uint256 amountIn,
        uint256 builderAmount,
        uint256 vaultAmountIn,
        uint256 stockOut
    );
    event VaultShareUpdated(uint256 vaultShareBps);
    event MaxSlippageUpdated(uint256 maxSlippageBps);
    event RouterUpdated(address router, address[] swapPath);
    event BuilderUpdated(address builder);

    error InvalidBps();
    error ZeroAmount();
    error SlippageExceeded();
    error EmptyPath();
    error ZeroAddress();

    constructor(
        address _owner,
        address _builder,
        address _vault,
        address _paymentToken,
        address _stockToken,
        address _router,
        address[] memory _swapPath,
        uint256 _vaultShareBps,
        uint256 _maxSlippageBps
    ) Ownable(_owner) {
        if (_vaultShareBps > BPS_DENOMINATOR) revert InvalidBps();
        if (_maxSlippageBps > BPS_DENOMINATOR) revert InvalidBps();
        if (_swapPath.length < 2) revert EmptyPath();
        if (_builder == address(0)) revert ZeroAddress();

        builder = _builder;
        vault = Vault(_vault);
        paymentToken = IERC20(_paymentToken);
        stockToken = IERC20(_stockToken);
        router = ISwapRouter(_router);
        swapPath = _swapPath;
        vaultShareBps = _vaultShareBps;
        maxSlippageBps = _maxSlippageBps;
    }

    /// @notice Pay the agent for a completed job. Splits `amount` of
    /// paymentToken between the builder and the vault per `vaultShareBps`.
    function pay(uint256 amount, bytes32 jobId) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 vaultPortion = (amount * vaultShareBps) / BPS_DENOMINATOR;
        uint256 builderPortion = amount - vaultPortion;

        if (builderPortion > 0) {
            paymentToken.safeTransfer(builder, builderPortion);
        }

        uint256 stockOut = 0;
        if (vaultPortion > 0) {
            stockOut = _swapToVault(vaultPortion);
        }

        emit WorkReceipt(jobId, msg.sender, amount, builderPortion, vaultPortion, stockOut);
    }

    function _swapToVault(uint256 vaultPortion) internal returns (uint256 stockOut) {
        uint256[] memory quoted = router.getAmountsOut(vaultPortion, swapPath);
        uint256 quotedOut = quoted[quoted.length - 1];
        uint256 minOut = (quotedOut * (BPS_DENOMINATOR - maxSlippageBps)) / BPS_DENOMINATOR;

        paymentToken.forceApprove(address(router), vaultPortion);
        uint256[] memory amounts = router.swapExactTokensForTokens(
            vaultPortion, minOut, swapPath, address(this), block.timestamp
        );
        stockOut = amounts[amounts.length - 1];
        if (stockOut < minOut) revert SlippageExceeded();

        stockToken.forceApprove(address(vault), stockOut);
        vault.deposit(stockOut);
    }

    function setVaultShareBps(uint256 _vaultShareBps) external onlyOwner {
        if (_vaultShareBps > BPS_DENOMINATOR) revert InvalidBps();
        vaultShareBps = _vaultShareBps;
        emit VaultShareUpdated(_vaultShareBps);
    }

    function setMaxSlippageBps(uint256 _maxSlippageBps) external onlyOwner {
        if (_maxSlippageBps > BPS_DENOMINATOR) revert InvalidBps();
        maxSlippageBps = _maxSlippageBps;
        emit MaxSlippageUpdated(_maxSlippageBps);
    }

    function setRouter(address _router, address[] calldata _swapPath) external onlyOwner {
        if (_swapPath.length < 2) revert EmptyPath();
        router = ISwapRouter(_router);
        swapPath = _swapPath;
        emit RouterUpdated(_router, _swapPath);
    }

    function setBuilder(address _builder) external onlyOwner {
        if (_builder == address(0)) revert ZeroAddress();
        builder = _builder;
        emit BuilderUpdated(_builder);
    }
}
