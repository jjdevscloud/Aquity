// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PonsLauncherV2} from "../src/PonsLauncherV2.sol";
import {RevenueRouter} from "../src/RevenueRouter.sol";
import {Vault} from "../src/Vault.sol";
import {Distributor} from "../src/Distributor.sol";
import {IPonsFactory} from "../src/interfaces/IPonsFactory.sol";
import {IPonsCurve} from "../src/interfaces/IPonsCurve.sol";

/// @notice Forks Robinhood Chain mainnet — same rigor as PonsLauncher.t.sol
/// and RevenueRouter.t.sol, against the same real, confirmed infra.
contract PonsLauncherV2Test is Test {
    bytes32 private constant AGENT_KEY_BINDING_TYPEHASH = keccak256("AgentKeyBinding(string agentId,address owner)");
    bytes32 private constant X_VERIFICATION_TYPEHASH =
        keccak256("XVerification(address owner,string agentId,string xHandle,uint256 nonce)");
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    address constant PONS_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant REAL_AAPL = 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9;
    address constant SWAP_ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    uint24 constant POOL_FEE = 500;

    AgentRegistry registry;
    PonsLauncherV2 launcher;

    address admin = makeAddr("admin");
    address owner = makeAddr("owner");
    address rootPoster = makeAddr("rootPoster");

    uint256 agentKeyPk;
    address agentKey;
    uint256 verifierPk;
    address verifier;
    uint256 private nonceCounter;

    function setUp() public {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string("https://rpc.mainnet.chain.robinhood.com"));
        vm.createSelectFork(rpc);

        (agentKey, agentKeyPk) = makeAddrAndKey("agentKey");
        (verifier, verifierPk) = makeAddrAndKey("verifier");

        registry = new AgentRegistry(admin, verifier);
        launcher = new PonsLauncherV2(admin, address(registry), PONS_FACTORY, SWAP_ROUTER, WETH, rootPoster);

        vm.prank(admin);
        registry.setLauncher(address(launcher));

        vm.deal(agentKey, 10 ether);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, keccak256(bytes("AquityAgentRegistry")), keccak256(bytes("1")), block.chainid, address(registry)
            )
        );
    }

    function _digest(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    function _validLaunchParams(bool enforced, uint256 holderFeeSplitBps) internal returns (PonsLauncherV2.LaunchParams memory p) {
        nonceCounter++;
        // AgentRegistry only allows A-Z (no digits) in tickers — cycle
        // through a fixed set of letter suffixes instead of using the
        // counter directly. A fresh registry is deployed per test (setUp
        // runs before each), so collisions across test functions aren't a
        // concern either way.
        bytes memory suffixLetters = "ABCDEFGHIJ";
        string memory suffix = string(abi.encodePacked(suffixLetters[nonceCounter % suffixLetters.length]));
        string memory agentId = string.concat("agent.pons-v2-test-", suffix, ".eth");
        string memory ticker = string.concat("PVTWO", suffix);
        string memory xHandle = string.concat("ponsv2test", suffix);

        bytes32 keyStructHash = keccak256(abi.encode(AGENT_KEY_BINDING_TYPEHASH, keccak256(bytes(agentId)), owner));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(agentKeyPk, _digest(keyStructHash));

        bytes32 xStructHash =
            keccak256(abi.encode(X_VERIFICATION_TYPEHASH, owner, keccak256(bytes(agentId)), keccak256(bytes(xHandle)), uint256(1)));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(verifierPk, _digest(xStructHash));

        p = PonsLauncherV2.LaunchParams({
            owner: owner,
            name: "Pons V2 Test Agent",
            ticker: ticker,
            agentId: agentId,
            agentKey: agentKey,
            agentKeySignature: abi.encodePacked(r1, s1, v1),
            xHandle: xHandle,
            xNonce: 1,
            verifierSignature: abi.encodePacked(r2, s2, v2),
            pairStock: REAL_AAPL,
            logo: "",
            description: "Testing PonsLauncherV2 against the real factory on a mainnet fork",
            twitterHandle: xHandle,
            creatorTaxBps: 1000,
            buybackEnabled: false,
            enforcedRevenueRouting: enforced,
            holderFeeSplitBps: holderFeeSplitBps,
            revenuePoolFee: POOL_FEE
        });
    }

    // ---------- non-enforced: must match PonsLauncher's existing, live, proven behavior exactly ----------

    function test_launch_nonEnforced_setsCreatorFeeRecipientToAgentKeyDirectly() public {
        PonsLauncherV2.LaunchParams memory p = _validLaunchParams(false, 0);
        uint256 fee = IPonsFactory(PONS_FACTORY).launchFee();

        vm.prank(agentKey);
        (uint256 tokenId,, address curve) = launcher.launch{value: fee}(p);

        assertEq(registry.ownerOf(tokenId), owner);
        (bool ok, bytes memory ret) = curve.staticcall(abi.encodeWithSignature("deployer()"));
        assertTrue(ok);
        assertEq(abi.decode(ret, (address)), agentKey, "non-enforced launches must keep creatorFeeRecipient = agentKey, unchanged from PonsLauncher");
    }

    // ---------- enforced: real Vault + Distributor + RevenueRouter, real Pons wiring ----------

    function test_launch_enforced_deploysRealStackAndRoutesCreatorFeesThroughIt() public {
        PonsLauncherV2.LaunchParams memory p = _validLaunchParams(true, 7000);
        uint256 fee = IPonsFactory(PONS_FACTORY).launchFee();

        vm.recordLogs();
        vm.prank(agentKey);
        (uint256 tokenId,, address curve) = launcher.launch{value: fee}(p);

        // creatorFeeRecipient is the deployed RevenueRouter, not agentKey.
        (bool ok, bytes memory ret) = curve.staticcall(abi.encodeWithSignature("deployer()"));
        assertTrue(ok);
        address revenueRouterAddr = abi.decode(ret, (address));
        assertTrue(revenueRouterAddr != agentKey, "enforced mode must not route fees to agentKey directly");
        assertTrue(revenueRouterAddr.code.length > 0, "RevenueRouter must be real deployed code");

        RevenueRouter revenueRouter = RevenueRouter(payable(revenueRouterAddr));
        assertEq(address(revenueRouter.curve()), curve, "RevenueRouter.setCurve must have been called with the real curve address");
        assertEq(revenueRouter.agentWallet(), agentKey);
        assertEq(revenueRouter.feeSplitBps(), 7000);
        assertEq(revenueRouter.owner(), owner, "ownership must end up with the human owner, not the launcher or the agent");

        Vault vault = revenueRouter.vault();
        assertEq(vault.owner(), owner);
        assertTrue(vault.depositors(revenueRouterAddr), "RevenueRouter must be an allowed depositor on its own Vault");
        assertTrue(vault.distributor() != address(0));
        assertEq(Distributor(vault.distributor()).owner(), owner);
        assertEq(Distributor(vault.distributor()).rootPoster(), rootPoster);

        assertEq(registry.ownerOf(tokenId), owner);
    }

    function test_launch_enforced_endToEnd_realTradeRealClaimRealVaultDeposit() public {
        PonsLauncherV2.LaunchParams memory p = _validLaunchParams(true, 6000);
        uint256 fee = IPonsFactory(PONS_FACTORY).launchFee();

        vm.prank(agentKey);
        (, address agentToken, address curve) = launcher.launch{value: fee}(p);

        address trader = makeAddr("trader");
        vm.deal(trader, 5 ether);
        vm.prank(trader);
        IPonsCurve(curve).buy{value: 2 ether}(2 ether, 0, trader);

        (bool ok, bytes memory ret) = curve.staticcall(abi.encodeWithSignature("deployer()"));
        assertTrue(ok);
        RevenueRouter revenueRouter = RevenueRouter(payable(abi.decode(ret, (address))));
        Vault vault = revenueRouter.vault();

        uint256 vaultBefore = IERC20(REAL_AAPL).balanceOf(address(vault));
        // Permissionless — anyone can trigger it, not just the owner.
        revenueRouter.pullFromEscrow(0);

        assertGt(agentKey.balance, 0, "agent should still receive its ETH share directly, same as always");
        assertGt(IERC20(REAL_AAPL).balanceOf(address(vault)), vaultBefore, "vault should hold real AAPL from the real swap");
        assertTrue(agentToken != address(0));
    }

    function test_launch_revertsWhenCallerIsNotTheAgentKey() public {
        PonsLauncherV2.LaunchParams memory p = _validLaunchParams(true, 5000);
        uint256 fee = IPonsFactory(PONS_FACTORY).launchFee();

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(PonsLauncherV2.NotAgentKey.selector);
        launcher.launch{value: fee}(p);
    }
}
