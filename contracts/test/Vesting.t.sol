// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vesting} from "../src/Vesting.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract VestingTest is Test {
    MockERC20 token;
    Vesting vesting;

    address owner = makeAddr("owner");
    address beneficiary = makeAddr("beneficiary");
    address reporter = makeAddr("reporter");
    address launcher = makeAddr("launcher");

    uint256 constant REVENUE_TARGET = 1_000e18;
    uint256 constant ALLOCATION = 100e18;

    function setUp() public {
        token = new MockERC20("Agent Token", "SENTRY");
        vesting = new Vesting(address(token), beneficiary, owner, reporter, launcher, REVENUE_TARGET);
    }

    function _lockWithAllocation(uint256 amount) internal {
        token.mint(address(vesting), amount);
        vm.prank(launcher);
        vesting.lock();
    }

    function test_lock_snapshotsCurrentBalance() public {
        _lockWithAllocation(ALLOCATION);
        assertEq(vesting.totalAllocation(), ALLOCATION);
        assertTrue(vesting.locked());
    }

    function test_lock_revertsIfCalledTwice() public {
        _lockWithAllocation(ALLOCATION);
        vm.prank(launcher);
        vm.expectRevert(Vesting.AlreadyLocked.selector);
        vesting.lock();
    }

    function test_lock_revertsWhenNotCalledByLauncher() public {
        token.mint(address(vesting), ALLOCATION);
        vm.expectRevert(Vesting.NotLauncher.selector);
        vesting.lock();
    }

    function test_release_vestsProportionallyToReportedRevenue() public {
        _lockWithAllocation(ALLOCATION);

        vm.prank(reporter);
        vesting.reportRevenue(300e18); // 30% of target

        vesting.release();
        assertEq(token.balanceOf(beneficiary), 30e18);
        assertEq(vesting.released(), 30e18);
    }

    function test_release_capsAtFullAllocationBeyondTarget() public {
        _lockWithAllocation(ALLOCATION);

        vm.prank(reporter);
        vesting.reportRevenue(5_000e18); // way past target

        vesting.release();
        assertEq(token.balanceOf(beneficiary), ALLOCATION);
    }

    function test_release_onlyReleasesTheDelta() public {
        _lockWithAllocation(ALLOCATION);

        vm.prank(reporter);
        vesting.reportRevenue(300e18);
        vesting.release();

        vm.prank(reporter);
        vesting.reportRevenue(600e18);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), 60e18);
        assertEq(vesting.released(), 60e18);
    }

    function test_release_revertsWhenNothingNewToRelease() public {
        _lockWithAllocation(ALLOCATION);
        vm.expectRevert(Vesting.NothingToRelease.selector);
        vesting.release();
    }

    function test_reportRevenue_revertsWhenNotMonotonic() public {
        _lockWithAllocation(ALLOCATION);
        vm.prank(reporter);
        vesting.reportRevenue(300e18);

        vm.prank(reporter);
        vm.expectRevert(Vesting.RevenueNotMonotonic.selector);
        vesting.reportRevenue(200e18);
    }

    function test_reportRevenue_revertsWhenNotReporter() public {
        vm.expectRevert(Vesting.NotReporter.selector);
        vesting.reportRevenue(100e18);
    }

    function test_setReporter_onlyOwner() public {
        address newReporter = makeAddr("newReporter");
        vm.prank(owner);
        vesting.setReporter(newReporter);
        assertEq(vesting.reporter(), newReporter);

        vm.expectRevert();
        vesting.setReporter(reporter);
    }
}
