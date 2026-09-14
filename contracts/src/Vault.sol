// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Vault
/// @notice Holds one agent's paired stock token. Deposit-only in this phase —
/// deliberately no withdrawal path for the agent or builder (AQUITY-SPEC §2.3,
/// "Never touch the vault"). Release-to-holders is added in Phase 3 by the
/// Distributor, which will be the only address ever granted a spend path here.
contract Vault is Ownable {
    using SafeERC20 for IERC20;

    /// @notice The paired stock token this vault custodies.
    IERC20 public immutable stockToken;

    /// @notice Addresses allowed to deposit into the vault (Splitter, FeeRouter).
    mapping(address => bool) public depositors;

    event Deposited(address indexed from, uint256 amount);
    event DepositorSet(address indexed depositor, bool allowed);

    error NotDepositor();

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

    /// @notice Pulls `amount` of stockToken from the caller into the vault.
    /// Caller must have approved this vault first.
    function deposit(uint256 amount) external onlyDepositor {
        stockToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    function balance() external view returns (uint256) {
        return stockToken.balanceOf(address(this));
    }
}
