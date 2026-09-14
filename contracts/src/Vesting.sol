// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Vesting
/// @notice Locks the builder's launch-day allocation of their own agent
/// token, releasing it against cumulative verified revenue rather than time
/// (AQUITY-SPEC §3.3, §5 "new — ... Builder's own allocation is locked until
/// the agent has earned"). `reporter` is the revenue oracle/indexer (Phase 3+
/// infrastructure) — not built yet, so it's a plain authorized address here.
contract Vesting is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable beneficiary;
    address public immutable launcher;
    /// @notice Cumulative graded revenue (AQUITY-SPEC §3.4) at which the full
    /// allocation is vested.
    uint256 public immutable revenueTarget;

    address public reporter;
    uint256 public totalAllocation;
    uint256 public cumulativeRevenue;
    uint256 public released;
    bool public locked;

    event Locked(uint256 totalAllocation);
    event RevenueReported(uint256 cumulativeRevenue);
    event Released(uint256 amount);
    event ReporterUpdated(address reporter);

    error NotLauncher();
    error NotReporter();
    error AlreadyLocked();
    error NotLocked();
    error RevenueNotMonotonic();
    error ZeroAddress();
    error ZeroRevenueTarget();
    error NothingToRelease();

    constructor(
        address _token,
        address _beneficiary,
        address _owner,
        address _reporter,
        address _launcher,
        uint256 _revenueTarget
    ) Ownable(_owner) {
        if (_token == address(0) || _beneficiary == address(0) || _reporter == address(0) || _launcher == address(0))
        {
            revert ZeroAddress();
        }
        if (_revenueTarget == 0) revert ZeroRevenueTarget();

        token = IERC20(_token);
        beneficiary = _beneficiary;
        reporter = _reporter;
        launcher = _launcher;
        revenueTarget = _revenueTarget;
    }

    /// @notice Snapshots this contract's current token balance as the locked
    /// allocation. Called once by Launcher right after it directs the launch
    /// buy's output here.
    function lock() external {
        if (msg.sender != launcher) revert NotLauncher();
        if (locked) revert AlreadyLocked();
        locked = true;
        totalAllocation = token.balanceOf(address(this));
        emit Locked(totalAllocation);
    }

    function setReporter(address _reporter) external onlyOwner {
        if (_reporter == address(0)) revert ZeroAddress();
        reporter = _reporter;
        emit ReporterUpdated(_reporter);
    }

    /// @notice Reports the agent's cumulative graded revenue so far. Must be
    /// monotonically non-decreasing.
    function reportRevenue(uint256 newCumulative) external {
        if (msg.sender != reporter) revert NotReporter();
        if (newCumulative < cumulativeRevenue) revert RevenueNotMonotonic();
        cumulativeRevenue = newCumulative;
        emit RevenueReported(newCumulative);
    }

    function vestedAmount() public view returns (uint256) {
        if (!locked) return 0;
        uint256 earned = cumulativeRevenue >= revenueTarget ? revenueTarget : cumulativeRevenue;
        return (totalAllocation * earned) / revenueTarget;
    }

    function releasable() public view returns (uint256) {
        return vestedAmount() - released;
    }

    function release() external {
        if (!locked) revert NotLocked();
        uint256 amount = releasable();
        if (amount == 0) revert NothingToRelease();
        released += amount;
        token.safeTransfer(beneficiary, amount);
        emit Released(amount);
    }
}
