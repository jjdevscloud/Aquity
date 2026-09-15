// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RevenueRouter} from "../src/RevenueRouter.sol";
import {Vault} from "../src/Vault.sol";
import {IPonsFactory} from "../src/interfaces/IPonsFactory.sol";
import {IPonsCurve} from "../src/interfaces/IPonsCurve.sol";

/// @notice Forks Robinhood Chain mainnet to test RevenueRouter against REAL,
/// live infra: Pons v2's factory + fee escrow, and Uniswap V3's SwapRouter02
/// + a real liquid AAPL/WETH pool. Every address here was independently
/// confirmed this session via direct eth_call/eth_getCode against
/// rpc.mainnet.chain.robinhood.com — not assumed from any prior memory.
contract RevenueRouterTest is Test {
    address constant REAL_AAPL = 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9;
    address constant SWAP_ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    uint24 constant POOL_FEE = 500;
    uint256 constant FEE_SPLIT_BPS = 7000; // 70% to holders

    IPonsFactory factory = IPonsFactory(0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e);

    address owner = makeAddr("owner");
    address agentWallet = makeAddr("agentWallet");

    Vault vault;
    RevenueRouter router;
    address realFeeEscrow;

    function setUp() public {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string("https://rpc.mainnet.chain.robinhood.com"));
        vm.createSelectFork(rpc);
        vm.deal(address(this), 20 ether);

        vault = new Vault(REAL_AAPL, owner);

        realFeeEscrow = factory.feeEscrow();
        assertEq(realFeeEscrow, 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e, "fee escrow address drifted from what was confirmed this session");

        router = new RevenueRouter(
            owner, agentWallet, REAL_AAPL, address(vault), realFeeEscrow, SWAP_ROUTER, WETH, POOL_FEE, FEE_SPLIT_BPS
        );

        vm.prank(owner);
        vault.setDepositor(address(router), true);
    }

    function _launchRealTokenWithCreatorFeeRecipient(address recipient) internal returns (address curve) {
        uint256 fee = factory.launchFee();
        bytes32 economics = factory.previewLaunchEconomics(0, address(0));

        IPonsFactory.TokenParams memory tp = IPonsFactory.TokenParams({
            name: "RevenueRouter Test",
            symbol: "RRTEST",
            logo: "",
            description: "RevenueRouter.t.sol fixture",
            socials: IPonsFactory.Socials({twitter: "", telegram: "", discord: "", website: "", farcaster: ""}),
            creatorFeeRecipient: recipient,
            creatorTaxBps: 1000, // max, to make accrued fees easy to detect in a small test buy
            buybackEnabled: false,
            expectedEconomics: economics,
            salt: keccak256(abi.encodePacked("RevenueRouter Test", " ", recipient, " ", block.timestamp, " ", vm.getNonce(address(this))))
        });

        address[] memory noExemptions = new address[](0);
        (, curve) = factory.launchToken{value: fee}(tp, 0, address(0), noExemptions);
    }

    // ---------- contribute() — voluntary path, no real Pons launch needed ----------

    function test_contribute_splitsEthAndDepositsRealAaplIntoVault() public {
        address contributor = makeAddr("contributor");
        vm.deal(contributor, 1 ether);

        vm.prank(contributor);
        router.contribute{value: 1 ether}(0);

        assertEq(agentWallet.balance, 0.3 ether, "agent should keep the 30% non-holder share as raw ETH");
        assertEq(address(router).balance, 0, "router should not hold leftover ETH");
        assertGt(IERC20(REAL_AAPL).balanceOf(address(vault)), 0, "vault should have received real AAPL from the real swap");
    }

    function test_contribute_revertsOnZeroValue() public {
        vm.expectRevert(RevenueRouter.NothingToRoute.selector);
        router.contribute(0);
    }

    function test_contribute_allToAgent_whenFeeSplitIsZero() public {
        vm.prank(owner);
        router.setFeeSplitBps(0);

        address contributor = makeAddr("contributor");
        vm.deal(contributor, 1 ether);
        vm.prank(contributor);
        router.contribute{value: 1 ether}(0);

        assertEq(agentWallet.balance, 1 ether);
        assertEq(IERC20(REAL_AAPL).balanceOf(address(vault)), 0);
    }

    // ---------- setCurve() ----------

    function test_setCurve_onlyOwnerAndOnlyOnce() public {
        address curve = _launchRealTokenWithCreatorFeeRecipient(address(router));

        vm.expectRevert();
        router.setCurve(curve);

        vm.prank(owner);
        router.setCurve(curve);
        assertEq(address(router.curve()), curve);

        vm.prank(owner);
        vm.expectRevert(RevenueRouter.CurveAlreadySet.selector);
        router.setCurve(curve);
    }

    // ---------- pullFromEscrow() — enforced path, needs a real Pons launch ----------

    function test_pullFromEscrow_revertsWhenCurveNotSet() public {
        vm.expectRevert(RevenueRouter.CurveNotSet.selector);
        router.pullFromEscrow(0);
    }

    function test_pullFromEscrow_revertsWhenNotTheCurvesFeeSweepOperator() public {
        // A real curve exists, but its creatorFeeRecipient is someone else
        // — Pons itself (not us) is what enforces this, via the real
        // NotFeeSweepOperator() revert confirmed this session.
        address someoneElsesCurve = _launchRealTokenWithCreatorFeeRecipient(makeAddr("someoneElse"));
        vm.prank(owner);
        router.setCurve(someoneElsesCurve);

        vm.expectRevert(); // Pons's own NotFeeSweepOperator(), not ours
        router.pullFromEscrow(0);
    }

    function test_pullFromEscrow_revertsWhenNothingAccrued() public {
        // router genuinely owns this curve (its real creatorFeeRecipient),
        // but no trade has happened against it yet — sweepFees succeeds
        // (nothing to sweep) and the escrow balance is genuinely zero.
        address curve = _launchRealTokenWithCreatorFeeRecipient(address(router));
        vm.prank(owner);
        router.setCurve(curve);

        vm.expectRevert(RevenueRouter.NothingToRoute.selector);
        router.pullFromEscrow(0);
    }

    function test_pullFromEscrow_claimsRealFeesAfterARealTrade() public {
        address curve = _launchRealTokenWithCreatorFeeRecipient(address(router));
        vm.prank(owner);
        router.setCurve(curve);

        // A real buy against the real curve — the 10% creatorTaxBps set in
        // _launchRealTokenWithCreatorFeeRecipient means this generates
        // real, claimable creator fees for `router`, via Pons's own real
        // fee logic, not anything we control.
        address trader = makeAddr("trader");
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        IPonsCurve(curve).buy{value: 2 ether}(2 ether, 0, trader);

        uint256 vaultBefore = IERC20(REAL_AAPL).balanceOf(address(vault));
        router.pullFromEscrow(0);

        assertGt(agentWallet.balance, 0, "agent should have received its ETH share of the real creator fee");
        assertGt(IERC20(REAL_AAPL).balanceOf(address(vault)), vaultBefore, "vault should have received real AAPL from the real swap");
        assertEq(address(router).balance, 0, "router should not hold leftover ETH after routing");
    }

    // ---------- access control / bounds ----------

    function test_setFeeSplitBps_onlyOwner() public {
        vm.expectRevert();
        router.setFeeSplitBps(5000);

        vm.prank(owner);
        router.setFeeSplitBps(5000);
        assertEq(router.feeSplitBps(), 5000);
    }

    function test_constructor_revertsOnInvalidBps() public {
        // Resolve every arg to a local BEFORE vm.expectRevert — otherwise it
        // can attach to one of these view calls (the first subsequent call)
        // instead of the `new` we actually mean to assert on.
        address escrowAddr = realFeeEscrow;

        vm.expectRevert(RevenueRouter.InvalidBps.selector);
        new RevenueRouter(owner, agentWallet, REAL_AAPL, address(vault), escrowAddr, SWAP_ROUTER, WETH, POOL_FEE, 10_001);
    }
}
