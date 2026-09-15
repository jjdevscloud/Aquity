// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockRouter} from "../src/mocks/MockRouter.sol";
import {MockLaunchpadFactory} from "../src/mocks/MockLaunchpadFactory.sol";
import {MockFeeEscrow} from "../src/mocks/MockFeeEscrow.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {Launcher} from "../src/Launcher.sol";
import {Vault} from "../src/Vault.sol";
import {Splitter} from "../src/Splitter.sol";
import {FeeRouter} from "../src/FeeRouter.sol";
import {Distributor} from "../src/Distributor.sol";

/// @notice One-shot local demo for testing the full stack end to end against
/// anvil: deploys every contract plus mocks (a payment token, a stock token,
/// a swap router, a launchpad factory, a fee escrow), launches one agent
/// through Launcher exactly like a real builder would, wires up its Vault /
/// Splitter / FeeRouter / Distributor, and seeds one job payment plus one
/// fee claim so there's something to see immediately.
///
/// Writes local-demo-output.json (one agent, matching indexer/agents.config.json's
/// shape) and local-demo-env.json (registry/launcher addresses + chain info)
/// into /contracts — see /run-local-demo.ps1 at the repo root, which drives
/// this script and copies the output into /indexer for you.
///
/// Run directly:
///   anvil                                                            # separate terminal
///   forge script script/DeployLocalDemo.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract DeployLocalDemo is Script {
    string constant MNEMONIC = "test test test test test test test test test test test junk";

    bytes32 constant AGENT_KEY_BINDING_TYPEHASH = keccak256("AgentKeyBinding(string agentId,address owner)");
    bytes32 constant X_VERIFICATION_TYPEHASH =
        keccak256("XVerification(address owner,string agentId,string xHandle,uint256 nonce)");
    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    struct Accounts {
        uint256 deployerPk;
        uint256 agentKeyPk;
        uint256 verifierPk;
        uint256 clientPk;
        address deployer;
        address agentKey;
        address client;
    }

    struct Infra {
        MockERC20 usdg;
        MockERC20 stock;
        MockRouter router;
        MockLaunchpadFactory factory;
        MockFeeEscrow feeEscrow;
        AgentRegistry registry;
        Launcher launcher;
    }

    struct AgentDeployment {
        address agentToken;
        address vesting;
        Vault vault;
        Splitter splitter;
        FeeRouter feeRouter;
        Distributor distributor;
    }

    function run() external {
        Accounts memory acc = _loadAccounts();
        Infra memory infra = _deployInfra(acc);
        AgentDeployment memory dep = _launchAgent(acc, infra);
        _wireAgentContracts(acc, infra, dep);
        _seedActivity(acc, infra, dep);
        _writeOutput(infra, dep);
        _logSummary(acc, infra, dep);
    }

    function _loadAccounts() internal returns (Accounts memory acc) {
        // anvil's default accounts, derived the same way anvil itself does —
        // no hardcoded keys to get wrong. Index 0-3 are pre-funded by anvil.
        acc.deployerPk = vm.deriveKey(MNEMONIC, 0);
        acc.agentKeyPk = vm.deriveKey(MNEMONIC, 1);
        acc.verifierPk = vm.deriveKey(MNEMONIC, 2);
        acc.clientPk = vm.deriveKey(MNEMONIC, 3);
        acc.deployer = vm.addr(acc.deployerPk);
        acc.agentKey = vm.addr(acc.agentKeyPk);
        acc.client = vm.addr(acc.clientPk);

        // anvil funds its default accounts with 10,000 ETH at genesis, but
        // this also needs to work when simulated with no --rpc-url at all
        // (Foundry's own ephemeral EVM starts every address at 0 balance).
        vm.deal(acc.deployer, 100 ether);
        vm.deal(acc.client, 100 ether);
    }

    function _deployInfra(Accounts memory acc) internal returns (Infra memory infra) {
        vm.startBroadcast(acc.deployerPk);

        infra.usdg = new MockERC20("USDG", "USDG");
        infra.stock = new MockERC20("Microsoft (tokenized)", "MSFTx");

        infra.router = new MockRouter();
        infra.router.setRate(address(infra.usdg), address(infra.stock), 2e18); // 1 USDG -> 2 MSFTx
        infra.stock.mint(address(infra.router), 1_000_000e18);

        infra.factory = new MockLaunchpadFactory();
        infra.feeEscrow = new MockFeeEscrow(address(infra.stock));

        infra.registry = new AgentRegistry(acc.deployer, vm.addr(acc.verifierPk));
        // NOTE: Launcher.sol now auto-deploys Vault/Splitter/FeeRouter/
        // Distributor itself (see its doc comment) — this script predates
        // that and still wires them up by hand below, so re-running it
        // deploys a second, disconnected set alongside what launch() sets
        // up on its own. Fixed up to compile against the current
        // constructor only.
        infra.launcher = new Launcher(acc.deployer, address(infra.registry), address(infra.factory), address(infra.usdg), address(infra.router));
        infra.registry.setLauncher(address(infra.launcher));

        vm.stopBroadcast();
    }

    function _domainSeparator(address registry) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("AquityAgentRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                registry
            )
        );
    }

    function _signAgentKeyBinding(bytes32 domainSeparator, string memory agentId, address owner_, uint256 pk)
        internal
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(AGENT_KEY_BINDING_TYPEHASH, keccak256(bytes(agentId)), owner_));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(pk, keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash)));
        return abi.encodePacked(r, s, v);
    }

    function _signXVerification(
        bytes32 domainSeparator,
        address owner_,
        string memory agentId,
        string memory xHandle,
        uint256 nonce,
        uint256 pk
    ) internal returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(X_VERIFICATION_TYPEHASH, owner_, keccak256(bytes(agentId)), keccak256(bytes(xHandle)), nonce)
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(pk, keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash)));
        return abi.encodePacked(r, s, v);
    }

    function _launchAgent(Accounts memory acc, Infra memory infra) internal returns (AgentDeployment memory dep) {
        string memory agentId = "erc8004:local-demo-1";
        string memory xHandle = "yourrival_agent";
        bytes32 domainSeparator = _domainSeparator(address(infra.registry));

        address[] memory path = new address[](2);
        path[0] = address(infra.usdg);
        path[1] = address(infra.stock);

        Launcher.LaunchParams memory p = Launcher.LaunchParams({
            name: "Rival ops monitoring",
            ticker: "YREV",
            agentId: agentId,
            agentKey: acc.agentKey,
            agentKeySignature: _signAgentKeyBinding(domainSeparator, agentId, acc.deployer, acc.agentKeyPk),
            xHandle: xHandle,
            xNonce: 1,
            verifierSignature: _signXVerification(domainSeparator, acc.deployer, agentId, xHandle, 1, acc.verifierPk),
            stockName: "Microsoft (tokenized)",
            stockSymbol: "MSFTx",
            sector: "Infrastructure ops",
            minTokensOut: 0,
            vestingReporter: acc.deployer,
            vestingRevenueTarget: 1_000e18,
            vaultShareBps: 3000,
            feeSplitBps: 7000
        });

        vm.startBroadcast(acc.deployerPk);
        (, dep.agentToken,, dep.vesting) = infra.launcher.launch{value: 1 ether}(p);
        vm.stopBroadcast();
    }

    function _wireAgentContracts(Accounts memory acc, Infra memory infra, AgentDeployment memory dep) internal {
        vm.startBroadcast(acc.deployerPk);

        dep.vault = new Vault(address(infra.stock), acc.deployer);

        address[] memory path = new address[](2);
        path[0] = address(infra.usdg);
        path[1] = address(infra.stock);
        dep.splitter = new Splitter(
            acc.deployer,
            acc.deployer,
            address(dep.vault),
            address(infra.usdg),
            address(infra.stock),
            address(infra.router),
            path,
            3000,
            500
        );
        dep.feeRouter = new FeeRouter(
            acc.deployer, dep.agentToken, address(infra.stock), address(dep.vault), address(infra.feeEscrow), acc.deployer, 7000
        );
        dep.distributor = new Distributor(address(infra.stock), address(dep.vault), acc.deployer, acc.deployer, 1e15);

        dep.vault.setDepositor(address(dep.splitter), true);
        dep.vault.setDepositor(address(dep.feeRouter), true);
        dep.vault.setDistributor(address(dep.distributor));

        infra.usdg.mint(acc.client, 1_000e18);
        infra.stock.mint(address(infra.feeEscrow), 20e18);
        infra.feeEscrow.accrue(dep.agentToken, 20e18);

        vm.stopBroadcast();
    }

    function _seedActivity(Accounts memory acc, Infra memory infra, AgentDeployment memory dep) internal {
        vm.startBroadcast(acc.clientPk);
        infra.usdg.approve(address(dep.splitter), type(uint256).max);
        dep.splitter.pay(100e18, keccak256("local-demo-job-1"));
        vm.stopBroadcast();

        vm.startBroadcast(acc.deployerPk);
        dep.feeRouter.claimFees();
        vm.stopBroadcast();
    }

    function _writeOutput(Infra memory infra, AgentDeployment memory dep) internal {
        string memory agentObj = "agent";
        vm.serializeString(agentObj, "ticker", "YREV");
        vm.serializeString(agentObj, "name", "Rival ops monitoring");
        vm.serializeString(agentObj, "company", "Microsoft");
        vm.serializeString(agentObj, "sector", "Infrastructure ops");
        vm.serializeString(agentObj, "operator", "local-demo");
        vm.serializeString(agentObj, "pairSymbol", "MSFTx");
        vm.serializeAddress(agentObj, "pairAddress", address(infra.stock));
        vm.serializeAddress(agentObj, "agentTokenAddress", dep.agentToken);
        vm.serializeAddress(agentObj, "splitterAddress", address(dep.splitter));
        vm.serializeAddress(agentObj, "vaultAddress", address(dep.vault));
        vm.serializeAddress(agentObj, "feeRouterAddress", address(dep.feeRouter));
        vm.serializeAddress(agentObj, "distributorAddress", address(dep.distributor));
        vm.serializeAddress(agentObj, "vestingAddress", dep.vesting);
        string memory agentJson = vm.serializeUint(agentObj, "startBlock", 0);
        vm.writeJson(agentJson, "./local-demo-output.json");

        string memory envObj = "env";
        vm.serializeAddress(envObj, "registryAddress", address(infra.registry));
        vm.serializeAddress(envObj, "launcherAddress", address(infra.launcher));
        vm.serializeUint(envObj, "chainId", block.chainid);
        string memory envJson = vm.serializeString(envObj, "rpcUrl", "http://127.0.0.1:8545");
        vm.writeJson(envJson, "./local-demo-env.json");
    }

    function _logSummary(Accounts memory acc, Infra memory infra, AgentDeployment memory dep) internal view {
        console.log("=== Local demo deployed ===");
        console.log("AgentRegistry:      ", address(infra.registry));
        console.log("Launcher:           ", address(infra.launcher));
        console.log("Agent token ($YREV):", dep.agentToken);
        console.log("Vault:              ", address(dep.vault));
        console.log("Splitter:           ", address(dep.splitter));
        console.log("FeeRouter:          ", address(dep.feeRouter));
        console.log("Distributor:        ", address(dep.distributor));
        console.log("Vesting:            ", dep.vesting);
        console.log("");
        console.log("Wrote local-demo-output.json and local-demo-env.json");
        console.log("");
        console.log("To send more test job payments as the client account:");
        console.log("  client address:", acc.client);
        console.log("  client private key:", vm.toString(bytes32(acc.clientPk)));
        console.log("  splitter address:", address(dep.splitter));
        console.log("  cast send <splitter> \"pay(uint256,bytes32)\" 50000000000000000000 $(cast keccak job-2) \\");
        console.log("    --rpc-url http://127.0.0.1:8545 --private-key <client private key>");
    }
}
