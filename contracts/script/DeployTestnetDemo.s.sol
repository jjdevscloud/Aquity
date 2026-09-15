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

/// @notice Same one-shot demo as DeployLocalDemo.s.sol, adapted to run for
/// real against Robinhood Chain testnet instead of anvil: deploys the mock
/// infra (payment token, stock token, swap router, launchpad factory, fee
/// escrow — the real Robinhood DEX/launchpad ABIs aren't confirmed yet, see
/// /contracts/README.md "Before deploying anything real"), launches one
/// agent through Launcher with real EIP-712 signatures, wires up its Vault /
/// Splitter / FeeRouter / Distributor, and seeds one job payment plus one
/// fee claim.
///
/// Differs from DeployLocalDemo.s.sol only in funding: anvil's public test
/// mnemonic has no real balance on a real chain (and would be front-run
/// instantly if it ever did), so this uses one real funded key for both the
/// deployer and client roles, and a much smaller ETH amount for the
/// Launcher's first-buy. agentKey/verifier never send transactions or hold
/// funds — they only sign EIP-712 attestations — so they stay as
/// deterministic throwaway keys.
///
/// Required env var:
///   PRIVATE_KEY   funded deployer/client key (see /contracts/.env, gitignored)
///
/// Run:
///   forge script script/DeployTestnetDemo.s.sol --rpc-url robinhood --broadcast
contract DeployTestnetDemo is Script {
    // Real ETH first-buy amount for Launcher.launch — sized for a testnet
    // faucet drip, not the 1 ether DeployLocalDemo.s.sol uses on anvil.
    uint256 constant LAUNCH_VALUE = 0.001 ether;

    bytes32 constant AGENT_KEY_BINDING_TYPEHASH = keccak256("AgentKeyBinding(string agentId,address owner)");
    bytes32 constant X_VERIFICATION_TYPEHASH =
        keccak256("XVerification(address owner,string agentId,string xHandle,uint256 nonce)");
    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    struct Accounts {
        uint256 deployerPk;
        uint256 agentKeyPk;
        uint256 verifierPk;
        address deployer;
        address agentKey;
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
        acc.deployerPk = vm.envUint("PRIVATE_KEY");
        acc.deployer = vm.addr(acc.deployerPk);

        // Never broadcast, never hold funds — only sign EIP-712 structs — so
        // deterministic throwaway keys are fine here.
        acc.agentKeyPk = uint256(keccak256("aquity-testnet-demo-agent-key"));
        acc.verifierPk = uint256(keccak256("aquity-testnet-demo-verifier-key"));
        acc.agentKey = vm.addr(acc.agentKeyPk);
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
        // NOTE: Launcher.sol has since grown its own automated
        // Vault/Splitter/FeeRouter/Distributor deployment (see its own doc
        // comment) — this script predates that and still wires them up by
        // hand below in _wireAgentContracts. Fixed up to compile against
        // the current 5-arg constructor, not re-validated as a script meant
        // to run again: re-running it would deploy a second, disconnected
        // Vault/Splitter/etc alongside whatever launch() now sets up
        // itself. See DeployLauncherV2.s.sol for the current deploy path.
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
        string memory agentId = "erc8004:testnet-demo-1";
        string memory xHandle = "yourrival_agent";
        bytes32 domainSeparator = _domainSeparator(address(infra.registry));

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
        // launch() would resolve/deploy its own MSFTx-symbol stock token
        // here too (see Launcher._resolveStock) — this script instead
        // pre-deploys `infra.stock` itself and wires everything by hand in
        // _wireAgentContracts below, predating that automation. Left as-is
        // for the historical record; not meant to run again.
        (, dep.agentToken,, dep.vesting) = infra.launcher.launch{value: LAUNCH_VALUE}(p);
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

        // Deployer plays "client" too — same funded key, no separate account
        // needed for a smoke test.
        infra.usdg.mint(acc.deployer, 1_000e18);
        infra.stock.mint(address(infra.feeEscrow), 20e18);
        infra.feeEscrow.accrue(dep.agentToken, 20e18);

        vm.stopBroadcast();
    }

    function _seedActivity(Accounts memory acc, Infra memory infra, AgentDeployment memory dep) internal {
        vm.startBroadcast(acc.deployerPk);
        infra.usdg.approve(address(dep.splitter), type(uint256).max);
        dep.splitter.pay(100e18, keccak256("testnet-demo-job-1"));
        dep.feeRouter.claimFees();
        vm.stopBroadcast();
    }

    function _writeOutput(Infra memory infra, AgentDeployment memory dep) internal {
        string memory agentObj = "agent";
        vm.serializeString(agentObj, "ticker", "YREV");
        vm.serializeString(agentObj, "name", "Rival ops monitoring");
        vm.serializeString(agentObj, "company", "Microsoft");
        vm.serializeString(agentObj, "sector", "Infrastructure ops");
        vm.serializeString(agentObj, "operator", "testnet-demo");
        vm.serializeString(agentObj, "pairSymbol", "MSFTx");
        vm.serializeAddress(agentObj, "pairAddress", address(infra.stock));
        vm.serializeAddress(agentObj, "agentTokenAddress", dep.agentToken);
        vm.serializeAddress(agentObj, "splitterAddress", address(dep.splitter));
        vm.serializeAddress(agentObj, "vaultAddress", address(dep.vault));
        vm.serializeAddress(agentObj, "feeRouterAddress", address(dep.feeRouter));
        vm.serializeAddress(agentObj, "distributorAddress", address(dep.distributor));
        vm.serializeAddress(agentObj, "vestingAddress", dep.vesting);
        string memory agentJson = vm.serializeUint(agentObj, "startBlock", block.number);
        vm.writeJson(agentJson, "./testnet-demo-output.json");

        string memory envObj = "env";
        vm.serializeAddress(envObj, "registryAddress", address(infra.registry));
        vm.serializeAddress(envObj, "launcherAddress", address(infra.launcher));
        vm.serializeUint(envObj, "chainId", block.chainid);
        string memory envJson = vm.serializeString(envObj, "rpcUrl", "https://rpc.testnet.chain.robinhood.com");
        vm.writeJson(envJson, "./testnet-demo-env.json");
    }

    function _logSummary(Accounts memory acc, Infra memory infra, AgentDeployment memory dep) internal view {
        console.log("=== Testnet demo deployed ===");
        console.log("Deployer:           ", acc.deployer);
        console.log("AgentRegistry:      ", address(infra.registry));
        console.log("Launcher:           ", address(infra.launcher));
        console.log("Agent token ($YREV):", dep.agentToken);
        console.log("Vault:              ", address(dep.vault));
        console.log("Splitter:           ", address(dep.splitter));
        console.log("FeeRouter:          ", address(dep.feeRouter));
        console.log("Distributor:        ", address(dep.distributor));
        console.log("Vesting:            ", dep.vesting);
        console.log("");
        console.log("Wrote testnet-demo-output.json and testnet-demo-env.json");
    }
}
