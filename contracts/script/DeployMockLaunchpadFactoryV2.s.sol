// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockLaunchpadFactory} from "../src/mocks/MockLaunchpadFactory.sol";
import {Launcher} from "../src/Launcher.sol";

/// @notice Redeploys MockLaunchpadFactory with the per-agent-pool fix (see
/// its own doc comment: the old version shared one mutable `token` across
/// every agent, so buying an older agent's token after a newer one
/// launched would silently mint the newer one instead) and points the
/// existing Launcher at it via setFactory — no Launcher redeploy needed,
/// `factory` was always meant to be rotatable.
///
/// Required env vars:
///   PRIVATE_KEY        existing deployer/owner key (owns Launcher)
///   LAUNCHER_ADDRESS   existing Launcher
///
/// Run:
///   forge script script/DeployMockLaunchpadFactoryV2.s.sol --rpc-url robinhood --broadcast
contract DeployMockLaunchpadFactoryV2 is Script {
    function run() external returns (MockLaunchpadFactory factory) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address launcherAddress = vm.envAddress("LAUNCHER_ADDRESS");
        Launcher launcher = Launcher(launcherAddress);

        vm.startBroadcast(deployerPk);
        factory = new MockLaunchpadFactory();
        launcher.setFactory(address(factory));
        vm.stopBroadcast();

        console.log("New MockLaunchpadFactory:", address(factory));
        console.log("Launcher.factory() now:", address(launcher.factory()));
    }
}
