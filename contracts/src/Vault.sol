// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Vault
/// @notice Holds one agent's paired stock token. The only way money leaves is
/// `release`, and the only caller ever allowed to invoke it is `distributor`
/// — the Phase 3 Distributor paying holders out via Merkle-verified claims.
/// There is deliberately no path for the agent or builder to withdraw
/// (AQUITY-SPEC §2.3, "Never touch the vault").
contract Vault is Ownable {
    using SafeERC20 for IERC20;

    /// @notice The paired stock token this vault custodies.
    IERC20 public immutable stockToken;

    /// @notice Addresses allowed to deposit into the vault (Splitter, FeeRouter).
    mapping(address => bool) public depositors;

    /// @notice The only address allowed to release funds — always the
    /// Distributor, and always to holders it has verified, never to the
    /// agent or builder directly.
    address public distributor;

    event Deposited(address indexed from, uint256 amount);
    event DepositorSet(address indexed depositor, bool allowed);
    event DistributorUpdated(address distributor);
    event Released(address indexed to, uint256 amount);

    error NotDepositor();
    error NotDistributor();

    constructor(address _stockToken, address _owner) Ownable(_owner) {
        stockToken = IERC20(_stockToken);
    }

    modifier onlyDepositor() {
        _checkDepositor();
        _;
    }

    function _checkDepositor() internal view {
        if (!depositors[msg.sender]) revert NotDepositor();
    }

    function setDepositor(address depositor, bool allowed) external onlyOwner {
        depositors[depositor] = allowed;
        emit DepositorSet(depositor, allowed);
    }

    function setDistributor(address _distributor) external onlyOwner {
        distributor = _distributor;
        emit DistributorUpdated(_distributor);
    }

    /// @notice Pulls `amount` of stockToken from the caller into the vault.
    /// Caller must have approved this vault first.
    function deposit(uint256 amount) external onlyDepositor {
        stockToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    /// @notice Sends `amount` of stockToken to `to`. Only the Distributor can
    /// call this, and it only ever does so to fund a posted epoch's Merkle
    /// root, pulling the funds into itself before holders claim against it.
    function release(address to, uint256 amount) external {
        if (msg.sender != distributor) revert NotDistributor();
        stockToken.safeTransfer(to, amount);
        emit Released(to, amount);
    }

    function balance() external view returns (uint256) {
        return stockToken.balanceOf(address(this));
    }
}
