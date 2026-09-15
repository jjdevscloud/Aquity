// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PonsLauncher} from "../src/PonsLauncher.sol";

/// @notice Deploys AgentRegistry + PonsLauncher for real on Robinhood Chain
/// mainnet (chain 4663), wired to the real, live Pons v2 factory
/// (0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e — see IPonsFactory.sol).
///
/// Required env vars:
///   PRIVATE_KEY        deployer/owner key (real mainnet ETH for gas)
///   VERIFIER_ADDRESS   mainnet-only verifier key's address — never reuse
///                      the testnet verifier key for real attestations
///
/// Run:
///   forge script script/DeployPonsMainnet.s.sol --rpc-url robinhood_mainnet --broadcast
contract DeployPonsMainnet is Script {
    address constant PONS_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;

    function run() external returns (AgentRegistry registry, PonsLauncher launcher) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address verifier = vm.envAddress("VERIFIER_ADDRESS");

        vm.startBroadcast(deployerPk);
        registry = new AgentRegistry(deployer, verifier);
        launcher = new PonsLauncher(deployer, address(registry), PONS_FACTORY);
        registry.setLauncher(address(launcher));
        vm.stopBroadcast();

        console.log("AgentRegistry:", address(registry));
        console.log("PonsLauncher:", address(launcher));
        console.log("verifier:", verifier);
        console.log("Pons factory:", PONS_FACTORY);
    }
}
