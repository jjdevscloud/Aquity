// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Splitter} from "../src/Splitter.sol";
import {Vault} from "../src/Vault.sol";

/// @notice Deploys one agent's Vault + Splitter pair to Robinhood Chain.
///
/// Required env vars:
///   PRIVATE_KEY          deployer key (funds gas in ETH)
///   OWNER_ADDRESS         admin for both contracts (can be a multisig)
///   BUILDER_ADDRESS       receives the non-vault share of each job payment
///   PAYMENT_TOKEN_ADDRESS USDG (or whatever revenue arrives in)
///   STOCK_TOKEN_ADDRESS   the agent's permanent paired tokenized stock — see
///                         AQUITY-SPEC §3.2: confirm this token has no transfer
///                         restriction that would block a contract holding it
///                         before running this against anything but a fork.
///   ROUTER_ADDRESS        Robinhood Chain's real swap router once known
///   VAULT_SHARE_BPS       e.g. 3000 for 30%
///   MAX_SLIPPAGE_BPS      e.g. 500 for 5%
///
/// Run against Robinhood Chain (see [rpc_endpoints] in foundry.toml):
///   forge script script/DeploySplitter.s.sol --rpc-url robinhood --broadcast --verify
///
/// Run against a local fork first — do this before ever broadcasting for real:
///   forge script script/DeploySplitter.s.sol --rpc-url robinhood
contract DeploySplitter is Script {
    function run() external returns (Vault vault, Splitter splitter) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address builder = vm.envAddress("BUILDER_ADDRESS");
        address paymentToken = vm.envAddress("PAYMENT_TOKEN_ADDRESS");
        address stockToken = vm.envAddress("STOCK_TOKEN_ADDRESS");
        address router = vm.envAddress("ROUTER_ADDRESS");
        uint256 vaultShareBps = vm.envUint("VAULT_SHARE_BPS");
        uint256 maxSlippageBps = vm.envUint("MAX_SLIPPAGE_BPS");

        address[] memory path = new address[](2);
        path[0] = paymentToken;
        path[1] = stockToken;

        vm.startBroadcast(deployerKey);

        // Vault is deployed owner=deployer so the deployer can wire the
        // depositor allowlist in this same script, then ownership moves to
        // OWNER_ADDRESS. Splitter takes its final owner directly since no
        // further owner-gated calls happen here.
        vault = new Vault(stockToken, msg.sender);
        splitter = new Splitter(
            owner, builder, address(vault), paymentToken, stockToken, router, path, vaultShareBps, maxSlippageBps
        );
        vault.setDepositor(address(splitter), true);
        if (owner != msg.sender) {
            vault.transferOwnership(owner);
        }

        vm.stopBroadcast();

        console.log("Vault:", address(vault));
        console.log("Splitter:", address(splitter));
    }
}
