// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import {Distributor} from "../src/Distributor.sol";
import {RevenueRouter} from "../src/RevenueRouter.sol";
import {IPonsFactory} from "../src/interfaces/IPonsFactory.sol";

/// @notice Deploys a real Vault + Distributor + RevenueRouter for ONE
/// already-launched agent — the voluntary-mode path (Phase B's M1): the
/// agent stays its own Pons `creatorFeeRecipient` exactly as today and
/// simply gets somewhere real to voluntarily send some of its own claimed
/// fees via `RevenueRouter.contribute()`. Works for any of the 3 real
/// agents already live (MPROOF, MPROOFB, KITHGOFO) or any future one that
/// launched through the original (non-enforced) PonsLauncher.
///
/// CURVE_ADDRESS is optional — if set, `setCurve` is also called so
/// `pullFromEscrow` is available too (harmless either way: it only ever
/// succeeds if this RevenueRouter is that curve's real creatorFeeRecipient,
/// which isn't true for a voluntary-mode agent's own curve — see
/// RevenueRouter.sol's NotFeeSweepOperator() note).
///
/// Required env vars:
///   PRIVATE_KEY            deployer key (funds gas in ETH)
///   OWNER_ADDRESS          final owner of all three contracts (the human)
///   AGENT_WALLET_ADDRESS   the agent's own wallet (receives its ETH share)
///   STOCK_TOKEN_ADDRESS    the agent's paired real Stock Token
///   ROOT_POSTER_ADDRESS    signs Distributor's Merkle roots (Phase B, M3)
///   POOL_FEE               real Uniswap V3 fee tier with confirmed
///                          liquidity for stockToken/WETH (e.g. 500 for the
///                          real AAPL/WETH pool confirmed this session)
///   FEE_SPLIT_BPS          % of every routed ETH amount that goes to
///                          holders (mirrors the mandate's "return to
///                          holders" %)
/// Optional:
///   CURVE_ADDRESS          this agent's real Pons curve, if known
///
/// Run:
///   forge script script/DeployRevenueStackMainnet.s.sol --rpc-url robinhood_mainnet --broadcast
contract DeployRevenueStackMainnet is Script {
    address constant PONS_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant SWAP_ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    uint256 constant DUST_THRESHOLD = 1e15;

    function run() external returns (Vault vault, Distributor distributor, RevenueRouter revenueRouter) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address owner = vm.envAddress("OWNER_ADDRESS");
        address agentWallet = vm.envAddress("AGENT_WALLET_ADDRESS");
        address stockToken = vm.envAddress("STOCK_TOKEN_ADDRESS");
        address rootPoster = vm.envAddress("ROOT_POSTER_ADDRESS");
        uint24 poolFee = uint24(vm.envUint("POOL_FEE"));
        uint256 feeSplitBps = vm.envUint("FEE_SPLIT_BPS");
        address curveAddress = vm.envOr("CURVE_ADDRESS", address(0));

        address feeEscrow = IPonsFactory(PONS_FACTORY).feeEscrow();

        vm.startBroadcast(deployerKey);

        // Deployed owner=deployer so this script can wire depositor/
        // distributor/curve in this same transaction batch, then ownership
        // moves to OWNER_ADDRESS at the end.
        vault = new Vault(stockToken, deployer);
        distributor = new Distributor(stockToken, address(vault), deployer, rootPoster, DUST_THRESHOLD);
        revenueRouter =
            new RevenueRouter(deployer, agentWallet, stockToken, address(vault), feeEscrow, SWAP_ROUTER, WETH, poolFee, feeSplitBps);

        vault.setDepositor(address(revenueRouter), true);
        vault.setDistributor(address(distributor));
        if (curveAddress != address(0)) {
            revenueRouter.setCurve(curveAddress);
        }

        if (owner != deployer) {
            vault.transferOwnership(owner);
            distributor.transferOwnership(owner);
            revenueRouter.transferOwnership(owner);
        }

        vm.stopBroadcast();

        console.log("Vault:", address(vault));
        console.log("Distributor:", address(distributor));
        console.log("RevenueRouter:", address(revenueRouter));
    }
}
