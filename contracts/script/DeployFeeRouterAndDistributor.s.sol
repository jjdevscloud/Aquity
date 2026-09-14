// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {FeeRouter} from "../src/FeeRouter.sol";
import {Distributor} from "../src/Distributor.sol";
import {Vault} from "../src/Vault.sol";

/// @notice Deploys FeeRouter + Distributor for an already-deployed Vault
/// (see DeploySplitter.s.sol) and wires the Vault's depositor/distributor
/// roles to them.
///
/// Required env vars:
///   PRIVATE_KEY            deployer key
///   OWNER_ADDRESS           admin for both contracts
///   VAULT_ADDRESS           the agent's existing Vault
///   STOCK_TOKEN_ADDRESS     the paired stock token the vault holds
///   AGENT_TOKEN_ADDRESS     the agent's own token (for fee-escrow lookups)
///   FEE_ESCROW_ADDRESS      the launchpad's real fee escrow, once confirmed
///                           to match IFeeEscrow (AQUITY-SPEC §3.2)
///   AGENT_WALLET_ADDRESS    receives the non-holder share of trading fees
///   FEE_SPLIT_BPS           e.g. 7000 for 70% to holders
///   ROOT_POSTER_ADDRESS     the indexer's on-chain-facing key
///   DUST_THRESHOLD          minimum per-holder amount `sweep` pushes automatically
///
/// Run against a fork first, broadcast only once confirmed:
///   forge script script/DeployFeeRouterAndDistributor.s.sol --rpc-url robinhood
///   forge script script/DeployFeeRouterAndDistributor.s.sol --rpc-url robinhood --broadcast --verify
contract DeployFeeRouterAndDistributor is Script {
    function run() external returns (FeeRouter feeRouter, Distributor distributor) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address stockToken = vm.envAddress("STOCK_TOKEN_ADDRESS");
        address agentToken = vm.envAddress("AGENT_TOKEN_ADDRESS");
        address feeEscrow = vm.envAddress("FEE_ESCROW_ADDRESS");
        address agentWallet = vm.envAddress("AGENT_WALLET_ADDRESS");
        uint256 feeSplitBps = vm.envUint("FEE_SPLIT_BPS");
        address rootPoster = vm.envAddress("ROOT_POSTER_ADDRESS");
        uint256 dustThreshold = vm.envUint("DUST_THRESHOLD");

        Vault vault = Vault(vaultAddress);

        vm.startBroadcast(deployerKey);

        feeRouter =
            new FeeRouter(owner, agentToken, stockToken, vaultAddress, feeEscrow, agentWallet, feeSplitBps);
        distributor = new Distributor(stockToken, vaultAddress, owner, rootPoster, dustThreshold);

        // Vault is owned by OWNER_ADDRESS already (see DeploySplitter.s.sol),
        // so the deployer can't wire these roles unless it's also the owner.
        if (msg.sender == vault.owner()) {
            vault.setDepositor(address(feeRouter), true);
            vault.setDistributor(address(distributor));
        } else {
            console.log("Deployer is not Vault owner - run setDepositor/setDistributor separately as", vault.owner());
        }

        vm.stopBroadcast();

        console.log("FeeRouter:", address(feeRouter));
        console.log("Distributor:", address(distributor));
    }
}
