// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FeeRouter} from "../src/FeeRouter.sol";
import {Vault} from "../src/Vault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockFeeEscrow} from "../src/mocks/MockFeeEscrow.sol";

contract FeeRouterTest is Test {
    MockERC20 stock;
    MockFeeEscrow escrow;
    Vault vault;
    FeeRouter feeRouter;

    address owner = makeAddr("owner");
    address agentWallet = makeAddr("agentWallet");
    address agentToken = makeAddr("agentToken");

    uint256 constant FEE_SPLIT_BPS = 7000; // 70% to holders, per spec example split

    function setUp() public {
        stock = new MockERC20("Palantir (tokenized)", "PLTRx");
        escrow = new MockFeeEscrow(address(stock));
        vault = new Vault(address(stock), owner);

        feeRouter = new FeeRouter(
            owner, agentToken, address(stock), address(vault), address(escrow), agentWallet, FEE_SPLIT_BPS
        );

        vm.prank(owner);
        vault.setDepositor(address(feeRouter), true);
    }

    function _fundEscrow(uint256 amount) internal {
        stock.mint(address(escrow), amount);
        escrow.accrue(agentToken, amount);
    }

    function test_claimFees_splitsBetweenVaultAndAgentWallet() public {
        _fundEscrow(100e18);

        uint256 totalClaimed = feeRouter.claimFees();

        assertEq(totalClaimed, 100e18);
        assertEq(stock.balanceOf(address(vault)), 70e18);
        assertEq(stock.balanceOf(agentWallet), 30e18);
        assertEq(stock.balanceOf(address(feeRouter)), 0);
    }

    function test_claimFees_revertsWhenNothingAccrued() public {
        vm.expectRevert(FeeRouter.NothingToClaim.selector);
        feeRouter.claimFees();
    }

    function test_claimFees_handlesFullSplitToHolders() public {
        vm.prank(owner);
        feeRouter.setFeeSplitBps(10_000);

        _fundEscrow(50e18);
        feeRouter.claimFees();

        assertEq(stock.balanceOf(address(vault)), 50e18);
        assertEq(stock.balanceOf(agentWallet), 0);
    }

    function test_setFeeSplitBps_onlyOwner() public {
        vm.expectRevert();
        feeRouter.setFeeSplitBps(5000);

        vm.prank(owner);
        feeRouter.setFeeSplitBps(5000);
        assertEq(feeRouter.feeSplitBps(), 5000);
    }

    function test_constructor_revertsOnInvalidBps() public {
        vm.expectRevert(FeeRouter.InvalidBps.selector);
        new FeeRouter(owner, agentToken, address(stock), address(vault), address(escrow), agentWallet, 10_001);
    }
}
