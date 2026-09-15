// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PonsLauncherV2} from "../src/PonsLauncherV2.sol";

/// @notice Deploys PonsLauncherV2 (adds Phase B's optional enforced revenue
/// routing on top of PonsLauncher's existing, live, unchanged behavior) and
/// repoints the existing mainnet AgentRegistry at it. The original
/// PonsLauncher and every agent already launched through it (MPROOF,
/// MPROOFB, KITHGOFO) are entirely unaffected — their creatorFeeRecipient
/// is immutable, set at their own past launch transaction. This only
/// changes where *future* launches go.
///
/// Required env vars:
///   PRIVATE_KEY              existing deployer/owner key (owns AgentRegistry)
///   AGENT_REGISTRY_ADDRESS   existing mainnet AgentRegistry
///   ROOT_POSTER_ADDRESS      signs Distributor's Merkle roots for every
///                            enforced-mode agent (Phase B, M3's off-chain
///                            job) — settable later via
///                            PonsLauncherV2.setRootPoster if it needs to
///                            rotate.
///
/// Run:
///   forge script script/DeployPonsLauncherV2Mainnet.s.sol --rpc-url robinhood_mainnet --broadcast
contract DeployPonsLauncherV2Mainnet is Script {
    address constant PONS_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    /// @dev Real Uniswap V3 SwapRouter02 + wrapped-native token on
    /// Robinhood Chain mainnet — independently confirmed via direct
    /// eth_call/eth_getCode this session (see RevenueRouter.sol and
    /// RevenueRouter.t.sol), not assumed.
    address constant SWAP_ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    function run() external returns (PonsLauncherV2 launcher) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address registryAddress = vm.envAddress("AGENT_REGISTRY_ADDRESS");
        address rootPoster = vm.envAddress("ROOT_POSTER_ADDRESS");
        AgentRegistry registry = AgentRegistry(registryAddress);

        vm.startBroadcast(deployerPk);
        launcher = new PonsLauncherV2(deployer, registryAddress, PONS_FACTORY, SWAP_ROUTER, WETH, rootPoster);
        registry.setLauncher(address(launcher));
        vm.stopBroadcast();

        console.log("New PonsLauncherV2:", address(launcher));
        console.log("Registry.launcher() now:", registry.launcher());
        console.log("rootPoster:", rootPoster);
    }
}
