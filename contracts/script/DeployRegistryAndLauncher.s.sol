// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {Launcher} from "../src/Launcher.sol";

/// @notice Deploys AgentRegistry + Launcher and wires them together.
///
/// Required env vars:
///   PRIVATE_KEY       deployer key (funds gas in ETH)
///   OWNER_ADDRESS      admin for both contracts (can be a multisig)
///   VERIFIER_ADDRESS   backend key that signs XVerification attestations
///                      after confirming a handle's verification post —
///                      see AQUITY-SPEC §2.4. Not built here: this script
///                      only wires the on-chain half.
///   FACTORY_ADDRESS    the third-party launchpad factory — confirm its real
///                      ABI matches ILaunchpadFactory (AQUITY-SPEC §3.2)
///                      before pointing this at anything but a fork.
///
/// Run against a fork first:
///   forge script script/DeployRegistryAndLauncher.s.sol --rpc-url robinhood
/// Broadcast for real:
///   forge script script/DeployRegistryAndLauncher.s.sol --rpc-url robinhood --broadcast --verify
contract DeployRegistryAndLauncher is Script {
    function run() external returns (AgentRegistry registry, Launcher launcher) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address verifier = vm.envAddress("VERIFIER_ADDRESS");
        address factory = vm.envAddress("FACTORY_ADDRESS");

        vm.startBroadcast(deployerKey);

        // Deployed owner=deployer so the deployer can wire setLauncher in
        // this same script, then ownership moves to OWNER_ADDRESS — same
        // pattern as DeploySplitter.s.sol's Vault handoff.
        registry = new AgentRegistry(msg.sender, verifier);
        launcher = new Launcher(owner, address(registry), factory);
        registry.setLauncher(address(launcher));
        if (owner != msg.sender) {
            registry.transferOwnership(owner);
        }

        vm.stopBroadcast();

        console.log("AgentRegistry:", address(registry));
        console.log("Launcher:", address(launcher));
    }
}
