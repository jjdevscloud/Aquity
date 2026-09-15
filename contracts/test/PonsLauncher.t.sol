// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {PonsLauncher} from "../src/PonsLauncher.sol";
import {IPonsFactory} from "../src/interfaces/IPonsFactory.sol";

/// @notice Forks Robinhood Chain mainnet to test PonsLauncher against the
/// REAL, live Pons v2 factory (0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e)
/// — the only way to actually prove our ABI encoding matches Pons's real
/// deployed bytecode byte-for-byte, without spending real ETH or waiting
/// for a real broadcast. Requires ROBINHOOD_MAINNET_RPC_URL (or falls back
/// to the public rate-limited endpoint).
///
/// The agent's own wallet (`agentKey`) is the caller throughout — matching
/// the real product flow: the owner funds the agent's wallet first (out of
/// scope here, a plain transfer), the agent spends its own balance to
/// launch.
contract PonsLauncherTest is Test {
    bytes32 private constant AGENT_KEY_BINDING_TYPEHASH = keccak256("AgentKeyBinding(string agentId,address owner)");
    bytes32 private constant X_VERIFICATION_TYPEHASH =
        keccak256("XVerification(address owner,string agentId,string xHandle,uint256 nonce)");
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    address constant PONS_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant REAL_AAPL = 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9;

    AgentRegistry registry;
    PonsLauncher launcher;

    address admin = makeAddr("admin");
    address owner = makeAddr("owner");

    uint256 agentKeyPk;
    address agentKey;
    uint256 verifierPk;
    address verifier;

    function setUp() public {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string("https://rpc.mainnet.chain.robinhood.com"));
        vm.createSelectFork(rpc);

        (agentKey, agentKeyPk) = makeAddrAndKey("agentKey");
        (verifier, verifierPk) = makeAddrAndKey("verifier");

        registry = new AgentRegistry(admin, verifier);
        launcher = new PonsLauncher(admin, address(registry), PONS_FACTORY);

        vm.prank(admin);
        registry.setLauncher(address(launcher));

        // The owner funding the agent's wallet — a plain transfer in the
        // real product, stood in for here with vm.deal directly.
        vm.deal(agentKey, 10 ether);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("AquityAgentRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                address(registry)
            )
        );
    }

    function _digest(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    function _validLaunchParams() internal view returns (PonsLauncher.LaunchParams memory p) {
        string memory agentId = "agent.pons-test.eth";
        string memory xHandle = "ponstest_agent";

        bytes32 keyStructHash = keccak256(abi.encode(AGENT_KEY_BINDING_TYPEHASH, keccak256(bytes(agentId)), owner));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(agentKeyPk, _digest(keyStructHash));

        bytes32 xStructHash = keccak256(
            abi.encode(X_VERIFICATION_TYPEHASH, owner, keccak256(bytes(agentId)), keccak256(bytes(xHandle)), uint256(1))
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(verifierPk, _digest(xStructHash));

        p = PonsLauncher.LaunchParams({
            owner: owner,
            name: "Pons Test Agent",
            ticker: "PONST",
            agentId: agentId,
            agentKey: agentKey,
            agentKeySignature: abi.encodePacked(r1, s1, v1),
            xHandle: xHandle,
            xNonce: 1,
            verifierSignature: abi.encodePacked(r2, s2, v2),
            pairStock: REAL_AAPL,
            logo: "",
            description: "Testing PonsLauncher against the real factory on a mainnet fork",
            twitterHandle: xHandle,
            creatorTaxBps: 500,
            buybackEnabled: false
        });
    }

    function test_launch_calledByAgentRegistersAndLaunchesOnRealPonsFactory() public {
        PonsLauncher.LaunchParams memory p = _validLaunchParams();
        uint256 fee = IPonsFactory(PONS_FACTORY).launchFee();

        vm.prank(agentKey);
        (uint256 tokenId, address agentToken, address curve) = launcher.launch{value: fee}(p);

        // Identity belongs to the human owner, even though the agent's own
        // wallet was the one that sent this transaction and paid for it.
        assertEq(registry.ownerOf(tokenId), owner);
        assertTrue(agentToken != address(0), "agentToken should be a real deployed address");
        assertTrue(curve != address(0), "curve should be a real deployed address");
        assertTrue(agentToken.code.length > 0, "agentToken must have real code");
        assertTrue(curve.code.length > 0, "curve must have real code");

        (,,, address recordedAgentKey,, address recordedPair, address recordedAgentToken,) = registry.agents(tokenId);
        assertEq(recordedAgentKey, agentKey);
        assertEq(recordedPair, REAL_AAPL);
        assertEq(recordedAgentToken, agentToken);

        // creatorFeeRecipient really is the agent's own wallet — read back
        // from the real curve's own on-chain state, not just our own event.
        (bool ok, bytes memory ret) = curve.staticcall(abi.encodeWithSignature("deployer()"));
        assertTrue(ok, "curve should respond to deployer()");
        assertEq(abi.decode(ret, (address)), agentKey, "Pons's own creatorFeeRecipient must be the agent, not the owner");
    }

    function test_launch_revertsWhenCallerIsNotTheAgentKey() public {
        PonsLauncher.LaunchParams memory p = _validLaunchParams();
        uint256 fee = IPonsFactory(PONS_FACTORY).launchFee();

        // Even the owner themselves can't call this — only the agent's own
        // wallet may, matching the product requirement that the agent
        // launches its own token.
        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(PonsLauncher.NotAgentKey.selector);
        launcher.launch{value: fee}(p);
    }

    function test_launch_revertsOnDuplicateTicker() public {
        PonsLauncher.LaunchParams memory p = _validLaunchParams();
        uint256 fee = IPonsFactory(PONS_FACTORY).launchFee();

        vm.prank(agentKey);
        launcher.launch{value: fee}(p);

        (address agentKey2, uint256 agentKeyPk2) = makeAddrAndKey("agentKey2");
        vm.deal(agentKey2, 10 ether);
        PonsLauncher.LaunchParams memory p2 = p;
        p2.agentKey = agentKey2;
        bytes32 keyStructHash = keccak256(abi.encode(AGENT_KEY_BINDING_TYPEHASH, keccak256(bytes(p.agentId)), owner));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(agentKeyPk2, _digest(keyStructHash));
        p2.agentKeySignature = abi.encodePacked(r1, s1, v1);

        vm.prank(agentKey2);
        vm.expectRevert(PonsLauncher.TickerTaken.selector);
        launcher.launch{value: fee}(p2);
    }

    function test_launch_revertsOnWrongFee() public {
        PonsLauncher.LaunchParams memory p = _validLaunchParams();
        uint256 fee = IPonsFactory(PONS_FACTORY).launchFee();

        vm.prank(agentKey);
        vm.expectRevert(abi.encodeWithSelector(PonsLauncher.WrongLaunchFee.selector, fee, fee - 1));
        launcher.launch{value: fee - 1}(p);
    }
}
