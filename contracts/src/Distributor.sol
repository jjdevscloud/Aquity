// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Vault} from "./Vault.sol";

/// @title Distributor
/// @notice AQUITY-SPEC §3.3: "Time-weighted balance snapshots from Transfer
/// logs → Merkle root per epoch → claim. Auto-sweep for balances above a
/// dust threshold."
///
/// Computing a time-weighted balance from historical Transfer events is an
/// off-chain indexing job — not representable in Solidity. That job runs
/// off-chain, then `rootPoster` posts the resulting Merkle root for the
/// epoch on-chain. Holders below `dustThreshold` for an epoch are simply left
/// out of that epoch's tree by the indexer and carried forward off-chain
/// until they cross it (AQUITY-SPEC §11.5) — nothing on-chain needs to track
/// that rollover.
contract Distributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Epoch {
        bytes32 merkleRoot;
        uint256 totalAllocated;
        uint256 claimed;
    }

    IERC20 public immutable stockToken;
    Vault public immutable vault;

    /// @notice Off-chain indexer's on-chain-facing key. Posts one Merkle
    /// root per epoch after computing time-weighted balances.
    address public rootPoster;
    /// @notice Minimum per-holder amount `sweep` will push automatically;
    /// AQUITY-SPEC §11.5's dust floor.
    uint256 public dustThreshold;

    mapping(uint256 epochId => Epoch) public epochs;
    mapping(uint256 epochId => mapping(address holder => bool)) public claimed;

    event RootPoster(address rootPoster);
    event DustThresholdUpdated(uint256 dustThreshold);
    event RootPosted(uint256 indexed epochId, bytes32 merkleRoot, uint256 totalAllocated);
    event Claimed(uint256 indexed epochId, address indexed holder, uint256 amount);

    error NotRootPoster();
    error EpochAlreadyPosted();
    error EpochNotPosted();
    error AlreadyClaimed();
    error InvalidProof();
    error BelowDustThreshold();
    error LengthMismatch();
    error ZeroAddress();

    constructor(address _stockToken, address _vault, address _owner, address _rootPoster, uint256 _dustThreshold)
        Ownable(_owner)
    {
        if (_stockToken == address(0) || _vault == address(0) || _rootPoster == address(0)) revert ZeroAddress();
        stockToken = IERC20(_stockToken);
        vault = Vault(_vault);
        rootPoster = _rootPoster;
        dustThreshold = _dustThreshold;
    }

    function setRootPoster(address _rootPoster) external onlyOwner {
        if (_rootPoster == address(0)) revert ZeroAddress();
        rootPoster = _rootPoster;
        emit RootPoster(_rootPoster);
    }

    function setDustThreshold(uint256 _dustThreshold) external onlyOwner {
        dustThreshold = _dustThreshold;
        emit DustThresholdUpdated(_dustThreshold);
    }

    /// @notice Posts epoch `epochId`'s Merkle root and pulls exactly
    /// `totalAllocated` out of the Vault to fund holder claims against it.
    function postRoot(uint256 epochId, bytes32 merkleRoot, uint256 totalAllocated) external nonReentrant {
        if (msg.sender != rootPoster) revert NotRootPoster();
        if (epochs[epochId].merkleRoot != bytes32(0)) revert EpochAlreadyPosted();

        epochs[epochId] = Epoch({merkleRoot: merkleRoot, totalAllocated: totalAllocated, claimed: 0});
        if (totalAllocated > 0) {
            vault.release(address(this), totalAllocated);
        }
        emit RootPosted(epochId, merkleRoot, totalAllocated);
    }

    /// @notice Claims `holder`'s allocation for `epochId`. Callable by
    /// anyone on the holder's behalf — the payout always goes to `holder`.
    function claim(uint256 epochId, address holder, uint256 amount, bytes32[] calldata proof)
        external
        nonReentrant
    {
        _claim(epochId, holder, amount, proof);
    }

    /// @notice Batch-pushes payouts for holders whose allocation clears
    /// `dustThreshold`, so most holders never need to call `claim` themselves.
    function sweep(
        uint256 epochId,
        address[] calldata holders,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external nonReentrant {
        if (holders.length != amounts.length || holders.length != proofs.length) revert LengthMismatch();
        for (uint256 i = 0; i < holders.length; i++) {
            if (amounts[i] < dustThreshold) revert BelowDustThreshold();
            _claim(epochId, holders[i], amounts[i], proofs[i]);
        }
    }

    function _claim(uint256 epochId, address holder, uint256 amount, bytes32[] calldata proof) internal {
        Epoch storage epoch = epochs[epochId];
        if (epoch.merkleRoot == bytes32(0)) revert EpochNotPosted();
        if (claimed[epochId][holder]) revert AlreadyClaimed();

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(epochId, holder, amount))));
        if (!MerkleProof.verify(proof, epoch.merkleRoot, leaf)) revert InvalidProof();

        claimed[epochId][holder] = true;
        epoch.claimed += amount;
        stockToken.safeTransfer(holder, amount);
        emit Claimed(epochId, holder, amount);
    }
}
