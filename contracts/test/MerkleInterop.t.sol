// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Distributor} from "../src/Distributor.sol";
import {Vault} from "../src/Vault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @notice Proves @openzeppelin/merkle-tree (the JS library Phase B's
/// distribution job — indexer-mainnet/src/jobs/postEpochRoot.ts — uses to
/// build Merkle roots off-chain) produces a root and proofs that Distributor
/// .sol's on-chain claim() actually accepts. The root/proofs below are NOT
/// computed here — they were generated once by the real JS library for
/// these exact values (epochId=1, two holders, amounts 10/20) and hardcoded,
/// so a passing test is real cross-language interop, not a tautology.
contract MerkleInteropTest is Test {
    address constant HOLDER_A = 0x1111111111111111111111111111111111111111;
    address constant HOLDER_B = 0x2222222222222222222222222222222222222222;

    bytes32 constant ROOT = 0xcef896330e91aaca29c7c1c76c8d471507e949c25a46143c25e3602efec5bd27;

    function test_realJsGeneratedRootAndProofsAreAcceptedOnChain() public {
        MockERC20 stock = new MockERC20("Test Stock", "TSTx");
        address owner = makeAddr("owner");
        address rootPoster = makeAddr("rootPoster");

        Vault vault = new Vault(address(stock), owner);
        Distributor distributor = new Distributor(address(stock), address(vault), owner, rootPoster, 0);

        vm.prank(owner);
        vault.setDistributor(address(distributor));
        vm.prank(owner);
        vault.setDepositor(address(this), true);

        stock.mint(address(this), 30e18);
        stock.approve(address(vault), 30e18);
        vault.deposit(30e18);

        vm.prank(rootPoster);
        distributor.postRoot(1, ROOT, 30e18);

        bytes32[] memory proofA = new bytes32[](1);
        proofA[0] = 0x8b88e0da4a4d51db18726aff89c7be092ba084fb2a4f1962945bab14e15a2b80;
        distributor.claim(1, HOLDER_A, 10e18, proofA);
        assertEq(stock.balanceOf(HOLDER_A), 10e18);

        bytes32[] memory proofB = new bytes32[](1);
        proofB[0] = 0xd78fbead9d165db7627811afcd04df8037cabd1bf0a4338915be532511d5df6f;
        distributor.claim(1, HOLDER_B, 20e18, proofB);
        assertEq(stock.balanceOf(HOLDER_B), 20e18);
    }
}
