// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";

contract AgentRegistryTest is Test {
    bytes32 private constant AGENT_KEY_BINDING_TYPEHASH = keccak256("AgentKeyBinding(string agentId,address owner)");
    bytes32 private constant X_VERIFICATION_TYPEHASH =
        keccak256("XVerification(address owner,string agentId,string xHandle,uint256 nonce)");
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    AgentRegistry registry;
    address admin = makeAddr("admin");
    address launcher = makeAddr("launcher");
    address builder = makeAddr("builder");
    address agentToken = makeAddr("agentToken");
    address stock = makeAddr("stock");

    uint256 agentKeyPk;
    address agentKey;
    uint256 verifierPk;
    address verifier;

    function setUp() public {
        (agentKey, agentKeyPk) = makeAddrAndKey("agentKey");
        (verifier, verifierPk) = makeAddrAndKey("verifier");

        registry = new AgentRegistry(admin, verifier);
        vm.prank(admin);
        registry.setLauncher(launcher);
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

    function _signAgentKeyBinding(string memory agentId, address owner_, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(AGENT_KEY_BINDING_TYPEHASH, keccak256(bytes(agentId)), owner_));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _digest(structHash));
        return abi.encodePacked(r, s, v);
    }

    function _signXVerification(address owner_, string memory agentId, string memory xHandle, uint256 nonce, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(X_VERIFICATION_TYPEHASH, owner_, keccak256(bytes(agentId)), keccak256(bytes(xHandle)), nonce)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _digest(structHash));
        return abi.encodePacked(r, s, v);
    }

    function _validParams() internal view returns (AgentRegistry.RegisterParams memory p) {
        p = AgentRegistry.RegisterParams({
            owner: builder,
            name: "Contract risk flagging",
            ticker: "SENTRY",
            agentId: "erc8004:1",
            agentKey: agentKey,
            agentKeySignature: _signAgentKeyBinding("erc8004:1", builder, agentKeyPk),
            xHandle: "sentry_agent",
            xNonce: 1,
            verifierSignature: _signXVerification(builder, "erc8004:1", "sentry_agent", 1, verifierPk),
            pair: stock,
            agentToken: agentToken
        });
    }

    function test_register_mintsAgentNFTToOwner() public {
        AgentRegistry.RegisterParams memory p = _validParams();

        vm.prank(launcher);
        uint256 tokenId = registry.register(p);

        assertEq(registry.ownerOf(tokenId), builder);
        (string memory ticker,,,,, address pair, address token,) = registry.agents(tokenId);
        assertEq(ticker, "SENTRY");
        assertEq(pair, stock);
        assertEq(token, agentToken);
        assertTrue(registry.tickerUsed("SENTRY"));
    }

    function test_register_revertsWhenCalledByNonLauncher() public {
        AgentRegistry.RegisterParams memory p = _validParams();
        vm.expectRevert(AgentRegistry.NotLauncher.selector);
        registry.register(p);
    }

    function test_register_revertsOnDuplicateTicker() public {
        vm.prank(launcher);
        registry.register(_validParams());

        AgentRegistry.RegisterParams memory p2 = _validParams();
        p2.agentId = "erc8004:2";
        p2.agentKeySignature = _signAgentKeyBinding("erc8004:2", builder, agentKeyPk);
        p2.xHandle = "other_handle";
        p2.verifierSignature = _signXVerification(builder, "erc8004:2", "other_handle", 1, verifierPk);

        vm.prank(launcher);
        vm.expectRevert(AgentRegistry.TickerTaken.selector);
        registry.register(p2);
    }

    function test_register_revertsOnDuplicateXHandle() public {
        vm.prank(launcher);
        registry.register(_validParams());

        AgentRegistry.RegisterParams memory p2 = _validParams();
        p2.ticker = "OTHER";
        p2.agentId = "erc8004:2";
        p2.agentKeySignature = _signAgentKeyBinding("erc8004:2", builder, agentKeyPk);
        p2.verifierSignature = _signXVerification(builder, "erc8004:2", "sentry_agent", 1, verifierPk);

        vm.prank(launcher);
        vm.expectRevert(AgentRegistry.XHandleTaken.selector);
        registry.register(p2);
    }

    function test_register_revertsOnBadAgentKeySignature() public {
        AgentRegistry.RegisterParams memory p = _validParams();
        // Signed by the verifier key instead of the agent key -> wrong signer.
        p.agentKeySignature = _signAgentKeyBinding(p.agentId, builder, verifierPk);

        vm.prank(launcher);
        vm.expectRevert(AgentRegistry.InvalidAgentKeySignature.selector);
        registry.register(p);
    }

    function test_register_revertsOnBadVerifierSignature() public {
        AgentRegistry.RegisterParams memory p = _validParams();
        // Signed by the agent key instead of the verifier -> wrong signer.
        p.verifierSignature = _signXVerification(builder, p.agentId, p.xHandle, p.xNonce, agentKeyPk);

        vm.prank(launcher);
        vm.expectRevert(AgentRegistry.InvalidVerifierSignature.selector);
        registry.register(p);
    }

    function test_register_revertsOnInvalidTickerFormat() public {
        AgentRegistry.RegisterParams memory p = _validParams();
        p.ticker = "ab"; // too short, lowercase

        vm.prank(launcher);
        vm.expectRevert(AgentRegistry.InvalidTicker.selector);
        registry.register(p);
    }
}
