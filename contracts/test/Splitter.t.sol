// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Splitter} from "../src/Splitter.sol";
import {Vault} from "../src/Vault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockRouter} from "../src/mocks/MockRouter.sol";

contract SplitterTest is Test {
    MockERC20 usdg;
    MockERC20 stock;
    MockRouter router;
    Vault vault;
    Splitter splitter;

    address owner = makeAddr("owner");
    address builder = makeAddr("builder");
    address client = makeAddr("client");

    uint256 constant VAULT_SHARE_BPS = 3000; // 30% to vault, per spec §3(Phase 1): pay() sends 70% builder / 30% vault
    uint256 constant MAX_SLIPPAGE_BPS = 500; // 5%
    uint256 constant RATE = 2e18; // 1 USDG -> 2 stock, scaled by 1e18

    function setUp() public {
        usdg = new MockERC20("USDG", "USDG");
        stock = new MockERC20("Palantir (tokenized)", "PLTRx");
        router = new MockRouter();

        vault = new Vault(address(stock), owner);

        address[] memory path = new address[](2);
        path[0] = address(usdg);
        path[1] = address(stock);

        splitter = new Splitter(
            owner, builder, address(vault), address(usdg), address(stock),
            address(router), path, VAULT_SHARE_BPS, MAX_SLIPPAGE_BPS
        );

        vm.prank(owner);
        vault.setDepositor(address(splitter), true);

        router.setRate(address(usdg), address(stock), RATE);
        // Fund the router with enough stock to fill swaps.
        stock.mint(address(router), 1_000_000e18);

        usdg.mint(client, 1_000e18);
        vm.prank(client);
        usdg.approve(address(splitter), type(uint256).max);
    }

    function test_pay_splitsRevenueAndFillsVault() public {
        uint256 amount = 100e18;
        bytes32 jobId = keccak256("job-1");

        uint256 expectedVaultPortion = (amount * VAULT_SHARE_BPS) / splitter.BPS_DENOMINATOR();
        uint256 expectedBuilderPortion = amount - expectedVaultPortion;
        uint256 expectedStockOut = (expectedVaultPortion * RATE) / router.RATE_PRECISION();

        vm.expectEmit(true, true, false, true, address(splitter));
        emit Splitter.WorkReceipt(
            jobId, client, amount, expectedBuilderPortion, expectedVaultPortion, expectedStockOut
        );

        vm.prank(client);
        splitter.pay(amount, jobId);

        assertEq(usdg.balanceOf(builder), expectedBuilderPortion, "builder got its cut in USDG");
        assertEq(stock.balanceOf(address(vault)), expectedStockOut, "vault received stock, not USDG");
        assertEq(usdg.balanceOf(address(splitter)), 0, "splitter holds nothing after settlement");
        assertEq(stock.balanceOf(address(splitter)), 0, "splitter holds nothing after settlement");
    }

    function test_pay_revertsOnZeroAmount() public {
        vm.prank(client);
        vm.expectRevert(Splitter.ZeroAmount.selector);
        splitter.pay(0, keccak256("job-2"));
    }

    function test_pay_revertsWhenSlippageExceedsCap() public {
        // Venue quotes at RATE but delivers 10% less at execution time — beyond
        // the 5% cap configured in setUp, so the swap must revert rather than
        // silently short the vault.
        router.setExecutionHaircutBps(1000);

        vm.prank(client);
        vm.expectRevert("MockRouter: insufficient output");
        splitter.pay(1e18, keccak256("job-3"));
    }

    function test_onlyOwner_canUpdateVaultShare() public {
        vm.prank(owner);
        splitter.setVaultShareBps(5000);
        assertEq(splitter.vaultShareBps(), 5000);

        vm.expectRevert();
        splitter.setVaultShareBps(1000);
    }

    function test_vault_rejectsDepositsFromNonDepositors() public {
        stock.mint(address(this), 1e18);
        stock.approve(address(vault), 1e18);
        vm.expectRevert(Vault.NotDepositor.selector);
        vault.deposit(1e18);
    }
}
