// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {Launcher} from "../src/Launcher.sol";

/// @notice Redeploys Launcher against the existing shared testnet infra
/// (AgentRegistry, MockLaunchpadFactory, USDG, MockRouter — all from
/// DeployTestnetDemo.s.sol / testnet-demo-env.json) and points the registry
/// at it. The old Launcher only created identity + token + vesting and left
/// Vault/Splitter/FeeRouter/Distributor as a manual per-agent follow-up
/// (see YREV); this one deploys the whole stack atomically — AQUITY-SPEC
/// §10 Phase 5.
///
/// Required env vars:
///   PRIVATE_KEY              existing deployer/owner key (owns AgentRegistry)
///   AGENT_REGISTRY_ADDRESS   existing AgentRegistry
///   LAUNCHPAD_FACTORY_ADDRESS  existing MockLaunchpadFactory
///   PAYMENT_TOKEN_ADDRESS    existing USDG (MockERC20)
///   ROUTER_ADDRESS           existing MockRouter
///
/// Run:
///   forge script script/DeployLauncherV2.s.sol --rpc-url robinhood --broadcast
contract DeployLauncherV2 is Script {
    function run() external returns (Launcher launcher) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address registryAddress = vm.envAddress("AGENT_REGISTRY_ADDRESS");
        address factory = vm.envAddress("LAUNCHPAD_FACTORY_ADDRESS");
        address paymentToken = vm.envAddress("PAYMENT_TOKEN_ADDRESS");
        address router = vm.envAddress("ROUTER_ADDRESS");

        AgentRegistry registry = AgentRegistry(registryAddress);

        vm.startBroadcast(deployerPk);
        launcher = new Launcher(deployer, registryAddress, factory, paymentToken, router);
        registry.setLauncher(address(launcher));
        vm.stopBroadcast();

        console.log("New Launcher:", address(launcher));
        console.log("Registry.launcher() now:", registry.launcher());
    }
}
