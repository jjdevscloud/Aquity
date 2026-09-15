// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {Launcher} from "../src/Launcher.sol";
import {Vesting} from "../src/Vesting.sol";
import {Vault} from "../src/Vault.sol";
import {Splitter} from "../src/Splitter.sol";
import {FeeRouter} from "../src/FeeRouter.sol";
import {Distributor} from "../src/Distributor.sol";
import {MockLaunchpadFactory} from "../src/mocks/MockLaunchpadFactory.sol";
import {MockRouter} from "../src/mocks/MockRouter.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract LauncherTest is Test {
    bytes32 private constant AGENT_KEY_BINDING_TYPEHASH = keccak256("AgentKeyBinding(string agentId,address owner)");
    bytes32 private constant X_VERIFICATION_TYPEHASH =
        keccak256("XVerification(address owner,string agentId,string xHandle,uint256 nonce)");
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    AgentRegistry registry;
    Launcher launcher;
    MockLaunchpadFactory factory;
    MockERC20 paymentToken;
    MockRouter router;

    address admin = makeAddr("admin");
    address builder = makeAddr("builder");
    address reporter = makeAddr("reporter");

    uint256 agentKeyPk;
    address agentKey;
    uint256 verifierPk;
    address verifier;

    function setUp() public {
        (agentKey, agentKeyPk) = makeAddrAndKey("agentKey");
        (verifier, verifierPk) = makeAddrAndKey("verifier");

        registry = new AgentRegistry(admin, verifier);
        factory = new MockLaunchpadFactory();
        paymentToken = new MockERC20("USDG", "USDG");
        router = new MockRouter();
        launcher = new Launcher(admin, address(registry), address(factory), address(paymentToken), address(router));

        vm.prank(admin);
        registry.setLauncher(address(launcher));

        vm.deal(builder, 10 ether);
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

    function _validLaunchParams() internal view returns (Launcher.LaunchParams memory p) {
        string memory agentId = "erc8004:1";
        string memory xHandle = "sentry_agent";

        bytes32 keyStructHash = keccak256(abi.encode(AGENT_KEY_BINDING_TYPEHASH, keccak256(bytes(agentId)), builder));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(agentKeyPk, _digest(keyStructHash));

        bytes32 xStructHash = keccak256(
            abi.encode(X_VERIFICATION_TYPEHASH, builder, keccak256(bytes(agentId)), keccak256(bytes(xHandle)), uint256(1))
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(verifierPk, _digest(xStructHash));

        p = Launcher.LaunchParams({
            name: "Contract risk flagging",
            ticker: "SENTRY",
            agentId: agentId,
            agentKey: agentKey,
            agentKeySignature: abi.encodePacked(r1, s1, v1),
            xHandle: xHandle,
            xNonce: 1,
            verifierSignature: abi.encodePacked(r2, s2, v2),
            stockName: "Acme (tokenized)",
            stockSymbol: "ACMEx",
            sector: "Legal & risk",
            minTokensOut: 0,
            vestingReporter: reporter,
            vestingRevenueTarget: 1_000e18,
            vaultShareBps: 3000,
            feeSplitBps: 7000
        });
    }

    function test_launch_registersMintsAndLocksVesting() public {
        Launcher.LaunchParams memory p = _validLaunchParams();

        vm.prank(builder);
        (uint256 tokenId, address agentToken, address vaultAddr, address vestingAddr) =
            launcher.launch{value: 1 ether}(p);

        assertEq(registry.ownerOf(tokenId), builder);

        Vesting vesting = Vesting(vestingAddr);
        assertTrue(vesting.locked());
        uint256 expectedTokens = 1 ether * factory.TOKENS_PER_WEI();
        assertEq(vesting.totalAllocation(), expectedTokens);
        assertEq(MockERC20(agentToken).balanceOf(vestingAddr), expectedTokens);
        assertEq(vesting.beneficiary(), builder);

        // The whole revenue-sharing stack should exist and be wired up —
        // this is what used to be a manual per-agent follow-up deploy.
        Vault vault = Vault(vaultAddr);
        address stockToken = launcher.stockTokenBySymbol(keccak256(bytes("ACMEx")));
        assertTrue(stockToken != address(0));
        assertEq(address(vault.stockToken()), stockToken);
        assertEq(vault.owner(), builder);
        assertTrue(vault.distributor() != address(0));
    }

    function test_launch_secondAgentReusesStockTokenForSameCompany() public {
        vm.prank(builder);
        (,, address vaultAddr1,) = launcher.launch{value: 1 ether}(_validLaunchParams());
        address stock1 = address(Vault(vaultAddr1).stockToken());

        address builder2 = makeAddr("builder2");
        vm.deal(builder2, 10 ether);
        (uint256 agentKeyPk2, address agentKey2) = (0, address(0));
        (agentKey2, agentKeyPk2) = makeAddrAndKey("agentKey2");

        string memory agentId = "erc8004:2";
        string memory xHandle = "sentry_agent_2";
        bytes32 keyStructHash = keccak256(abi.encode(AGENT_KEY_BINDING_TYPEHASH, keccak256(bytes(agentId)), builder2));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(agentKeyPk2, _digest(keyStructHash));
        bytes32 xStructHash = keccak256(
            abi.encode(X_VERIFICATION_TYPEHASH, builder2, keccak256(bytes(agentId)), keccak256(bytes(xHandle)), uint256(1))
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(verifierPk, _digest(xStructHash));

        Launcher.LaunchParams memory p2 = Launcher.LaunchParams({
            name: "Second agent",
            ticker: "SENTRB",
            agentId: agentId,
            agentKey: agentKey2,
            agentKeySignature: abi.encodePacked(r1, s1, v1),
            xHandle: xHandle,
            xNonce: 1,
            verifierSignature: abi.encodePacked(r2, s2, v2),
            stockName: "Acme (tokenized)",
            stockSymbol: "ACMEx",
            sector: "Legal & risk",
            minTokensOut: 0,
            vestingReporter: reporter,
            vestingRevenueTarget: 1_000e18,
            vaultShareBps: 2000,
            feeSplitBps: 8000
        });

        vm.prank(builder2);
        (,, address vaultAddr2,) = launcher.launch{value: 1 ether}(p2);
        address stock2 = address(Vault(vaultAddr2).stockToken());

        assertEq(stock1, stock2);
    }

    function test_launch_revertsWhenFirstBuySlippageNotMet() public {
        Launcher.LaunchParams memory p = _validLaunchParams();
        p.minTokensOut = type(uint256).max;

        vm.prank(builder);
        vm.expectRevert("MockLaunchpadFactory: insufficient output");
        launcher.launch{value: 1 ether}(p);
    }
}
