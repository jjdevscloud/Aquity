// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Distributor} from "../src/Distributor.sol";
import {Vault} from "../src/Vault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract DistributorTest is Test {
    MockERC20 stock;
    Vault vault;
    Distributor distributor;

    address owner = makeAddr("owner");
    address rootPoster = makeAddr("rootPoster");
    address holderA = makeAddr("holderA");
    address holderB = makeAddr("holderB");
    address holderC = makeAddr("holderC"); // dust holder

    uint256 constant DUST_THRESHOLD = 1e18;
    uint256 constant EPOCH_0 = 0;

    // Three-leaf tree: A=10e18, B=20e18, C=0.5e18 (dust).
    uint256 constant AMOUNT_A = 10e18;
    uint256 constant AMOUNT_B = 20e18;
    uint256 constant AMOUNT_C = 5e17;

    bytes32 leafA;
    bytes32 leafB;
    bytes32 leafC;
    bytes32 root;

    function setUp() public {
        stock = new MockERC20("Palantir (tokenized)", "PLTRx");
        vault = new Vault(address(stock), owner);
        distributor = new Distributor(address(stock), address(vault), owner, rootPoster, DUST_THRESHOLD);

        vm.prank(owner);
        vault.setDistributor(address(distributor));

        stock.mint(address(vault), 1_000e18);

        leafA = _leaf(EPOCH_0, holderA, AMOUNT_A);
        leafB = _leaf(EPOCH_0, holderB, AMOUNT_B);
        leafC = _leaf(EPOCH_0, holderC, AMOUNT_C);

        // Simple sorted-pair Merkle tree over the three leaves.
        bytes32 ab = _hashPair(leafA, leafB);
        root = _hashPair(ab, leafC);
    }

    function _leaf(uint256 epochId, address holder, uint256 amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(epochId, holder, amount))));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _proofForA() internal view returns (bytes32[] memory proof) {
        proof = new bytes32[](2);
        proof[0] = leafB;
        proof[1] = leafC;
    }

    function _proofForB() internal view returns (bytes32[] memory proof) {
        proof = new bytes32[](2);
        proof[0] = leafA;
        proof[1] = leafC;
    }

    function _proofForC() internal view returns (bytes32[] memory proof) {
        proof = new bytes32[](1);
        proof[0] = _hashPair(leafA, leafB);
    }

    function _postRoot(uint256 totalAllocated) internal {
        vm.prank(rootPoster);
        distributor.postRoot(EPOCH_0, root, totalAllocated);
    }

    function test_postRoot_pullsAllocatedAmountFromVault() public {
        _postRoot(AMOUNT_A + AMOUNT_B + AMOUNT_C);
        assertEq(stock.balanceOf(address(distributor)), AMOUNT_A + AMOUNT_B + AMOUNT_C);
        assertEq(stock.balanceOf(address(vault)), 1_000e18 - (AMOUNT_A + AMOUNT_B + AMOUNT_C));
    }

    function test_postRoot_revertsWhenNotRootPoster() public {
        vm.expectRevert(Distributor.NotRootPoster.selector);
        distributor.postRoot(EPOCH_0, root, AMOUNT_A);
    }

    function test_postRoot_revertsOnDuplicateEpoch() public {
        _postRoot(AMOUNT_A + AMOUNT_B + AMOUNT_C);
        vm.prank(rootPoster);
        vm.expectRevert(Distributor.EpochAlreadyPosted.selector);
        distributor.postRoot(EPOCH_0, root, 1);
    }

    function test_claim_paysHolderWithValidProof() public {
        _postRoot(AMOUNT_A + AMOUNT_B + AMOUNT_C);

        distributor.claim(EPOCH_0, holderA, AMOUNT_A, _proofForA());

        assertEq(stock.balanceOf(holderA), AMOUNT_A);
        assertTrue(distributor.claimed(EPOCH_0, holderA));
    }

    function test_claim_revertsOnDoubleClaim() public {
        _postRoot(AMOUNT_A + AMOUNT_B + AMOUNT_C);
        distributor.claim(EPOCH_0, holderA, AMOUNT_A, _proofForA());

        vm.expectRevert(Distributor.AlreadyClaimed.selector);
        distributor.claim(EPOCH_0, holderA, AMOUNT_A, _proofForA());
    }

    function test_claim_revertsOnWrongAmount() public {
        _postRoot(AMOUNT_A + AMOUNT_B + AMOUNT_C);

        vm.expectRevert(Distributor.InvalidProof.selector);
        distributor.claim(EPOCH_0, holderA, AMOUNT_A + 1, _proofForA());
    }

    function test_claim_revertsWhenEpochNotPosted() public {
        vm.expectRevert(Distributor.EpochNotPosted.selector);
        distributor.claim(EPOCH_0, holderA, AMOUNT_A, _proofForA());
    }

    function test_claim_dustHolderCanStillClaimManually() public {
        _postRoot(AMOUNT_A + AMOUNT_B + AMOUNT_C);

        distributor.claim(EPOCH_0, holderC, AMOUNT_C, _proofForC());
        assertEq(stock.balanceOf(holderC), AMOUNT_C);
    }

    function test_sweep_paysMultipleHoldersAboveDustThreshold() public {
        _postRoot(AMOUNT_A + AMOUNT_B + AMOUNT_C);

        address[] memory holders = new address[](2);
        holders[0] = holderA;
        holders[1] = holderB;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = AMOUNT_A;
        amounts[1] = AMOUNT_B;
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = _proofForA();
        proofs[1] = _proofForB();

        distributor.sweep(EPOCH_0, holders, amounts, proofs);

        assertEq(stock.balanceOf(holderA), AMOUNT_A);
        assertEq(stock.balanceOf(holderB), AMOUNT_B);
    }

    function test_sweep_revertsOnBelowDustAmount() public {
        _postRoot(AMOUNT_A + AMOUNT_B + AMOUNT_C);

        address[] memory holders = new address[](1);
        holders[0] = holderC;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT_C; // below DUST_THRESHOLD
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = _proofForC();

        vm.expectRevert(Distributor.BelowDustThreshold.selector);
        distributor.sweep(EPOCH_0, holders, amounts, proofs);
    }

    function test_vault_rejectsReleaseFromNonDistributor() public {
        vm.expectRevert(Vault.NotDistributor.selector);
        vault.release(holderA, 1e18);
    }
}
