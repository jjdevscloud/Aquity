// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PonsLauncher} from "../src/PonsLauncher.sol";

/// @notice Redeploys PonsLauncher against the existing mainnet
/// AgentRegistry (unchanged, no redeploy needed) and repoints the registry
/// at it. Used when PonsLauncher's own interface changes.
///
/// Required env vars:
///   PRIVATE_KEY              existing deployer/owner key (owns AgentRegistry)
///   AGENT_REGISTRY_ADDRESS   existing mainnet AgentRegistry
///
/// Run:
///   forge script script/RedeployPonsLauncherMainnet.s.sol --rpc-url robinhood_mainnet --broadcast
contract RedeployPonsLauncherMainnet is Script {
    address constant PONS_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;

    function run() external returns (PonsLauncher launcher) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address registryAddress = vm.envAddress("AGENT_REGISTRY_ADDRESS");
        AgentRegistry registry = AgentRegistry(registryAddress);

        vm.startBroadcast(deployerPk);
        launcher = new PonsLauncher(deployer, registryAddress, PONS_FACTORY);
        registry.setLauncher(address(launcher));
        vm.stopBroadcast();

        console.log("New PonsLauncher:", address(launcher));
        console.log("Registry.launcher() now:", registry.launcher());
    }
}
