// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IFeeEscrow} from "./interfaces/IFeeEscrow.sol";
import {Vault} from "./Vault.sol";

/// @title FeeRouter
/// @notice AQUITY-SPEC §3.3: "Claims trading fees from the launchpad escrow.
/// Splits by feeSplit, sends the holder share to Vault and the rest to the
/// agent's wallet." Fees already arrive in the paired stock token (the pool
/// is quoted in it — AQUITY-SPEC §2.1), so unlike Splitter there is no swap
/// leg here.
contract FeeRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    IERC20 public immutable stockToken;
    address public immutable agentToken;
    Vault public vault;
    IFeeEscrow public feeEscrow;
    /// @notice Where the (100 - feeSplitBps) share goes — funds the agent's
    /// own skills (AQUITY-SPEC §2.2).
    address public agentWallet;
    /// @notice % of each claimed fee batch (in bps) paid to holders via Vault.
    uint256 public feeSplitBps;

    event FeesClaimedAndSplit(uint256 totalClaimed, uint256 holderShare, uint256 agentShare);
    event FeeSplitUpdated(uint256 feeSplitBps);
    event VaultUpdated(address vault);
    event FeeEscrowUpdated(address feeEscrow);
    event AgentWalletUpdated(address agentWallet);

    error InvalidBps();
    error NothingToClaim();
    error ZeroAddress();

    constructor(
        address _owner,
        address _agentToken,
        address _stockToken,
        address _vault,
        address _feeEscrow,
        address _agentWallet,
        uint256 _feeSplitBps
    ) Ownable(_owner) {
        if (_agentToken == address(0) || _stockToken == address(0) || _vault == address(0) || _feeEscrow == address(0))
        {
            revert ZeroAddress();
        }
        if (_agentWallet == address(0)) revert ZeroAddress();
        if (_feeSplitBps > BPS_DENOMINATOR) revert InvalidBps();

        agentToken = _agentToken;
        stockToken = IERC20(_stockToken);
        vault = Vault(_vault);
        feeEscrow = IFeeEscrow(_feeEscrow);
        agentWallet = _agentWallet;
        feeSplitBps = _feeSplitBps;
    }

    /// @notice Claims accrued trading fees and splits them between the Vault
    /// (holder share) and the agent's own wallet.
    function claimFees() external nonReentrant returns (uint256 totalClaimed) {
        totalClaimed = feeEscrow.claimFees(agentToken);
        if (totalClaimed == 0) revert NothingToClaim();

        uint256 holderShare = (totalClaimed * feeSplitBps) / BPS_DENOMINATOR;
        uint256 agentShare = totalClaimed - holderShare;

        if (holderShare > 0) {
            stockToken.forceApprove(address(vault), holderShare);
            vault.deposit(holderShare);
        }
        if (agentShare > 0) {
            stockToken.safeTransfer(agentWallet, agentShare);
        }

        emit FeesClaimedAndSplit(totalClaimed, holderShare, agentShare);
    }

    function setFeeSplitBps(uint256 _feeSplitBps) external onlyOwner {
        if (_feeSplitBps > BPS_DENOMINATOR) revert InvalidBps();
        feeSplitBps = _feeSplitBps;
        emit FeeSplitUpdated(_feeSplitBps);
    }

    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert ZeroAddress();
        vault = Vault(_vault);
        emit VaultUpdated(_vault);
    }

    function setFeeEscrow(address _feeEscrow) external onlyOwner {
        if (_feeEscrow == address(0)) revert ZeroAddress();
        feeEscrow = IFeeEscrow(_feeEscrow);
        emit FeeEscrowUpdated(_feeEscrow);
    }

    function setAgentWallet(address _agentWallet) external onlyOwner {
        if (_agentWallet == address(0)) revert ZeroAddress();
        agentWallet = _agentWallet;
        emit AgentWalletUpdated(_agentWallet);
    }
}
