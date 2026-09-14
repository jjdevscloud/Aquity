// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AgentRegistry
/// @notice ERC-721 identity per agent (AQUITY-SPEC §3.3). Binds an agent key
/// to an owner wallet and an X handle, and stores the agent's permanent
/// stock pairing. Sybil resistance follows §2.4:
///
///   1. Connect wallet             -> msg.sender / `owner` param
///   2. Prove ownership            -> agentKey signs an EIP-712 message off-chain,
///                                     verified on-chain in `register`
///   3. Verify on X                -> the Aquity backend reads the poster's
///                                     timeline off-chain (not representable in
///                                     Solidity) and, once confirmed, signs an
///                                     EIP-712 attestation with `verifier`'s key
///   4. One agent per X account    -> enforced by `usedXHandle`
///
/// Registration itself happens once, atomically, through `Launcher` so token
/// creation and identity registration land in the same transaction.
contract AgentRegistry is ERC721, EIP712, Ownable {
    struct Agent {
        string ticker;
        string name;
        string agentId;
        address agentKey;
        string xHandle;
        address pair; // permanent: the chosen company's tokenized stock
        address agentToken; // permanent: this agent's own token, from Launcher
        uint256 registeredAt;
    }

    struct RegisterParams {
        address owner;
        string name;
        string ticker;
        string agentId;
        address agentKey;
        bytes agentKeySignature;
        string xHandle;
        uint256 xNonce;
        bytes verifierSignature;
        address pair;
        address agentToken;
    }

    bytes32 private constant AGENT_KEY_BINDING_TYPEHASH =
        keccak256("AgentKeyBinding(string agentId,address owner)");
    bytes32 private constant X_VERIFICATION_TYPEHASH =
        keccak256("XVerification(address owner,string agentId,string xHandle,uint256 nonce)");

    uint256 public nextTokenId = 1;

    /// @notice Backend key that signs an XVerification attestation once it has
    /// confirmed the verification post on the agent owner's timeline.
    address public verifier;
    /// @notice Only address allowed to call `register` — the Launcher, so
    /// token creation and identity registration are atomic. Settable by owner
    /// in case Launcher is redeployed.
    address public launcher;

    mapping(uint256 tokenId => Agent) public agents;
    mapping(string ticker => bool used) public tickerUsed;
    mapping(bytes32 xHandleHash => bool used) public xHandleUsed;

    event AgentRegistered(
        uint256 indexed tokenId, address indexed owner, string ticker, string agentId, address pair, address agentToken
    );
    event VerifierUpdated(address verifier);
    event LauncherUpdated(address launcher);

    error NotLauncher();
    error TickerTaken();
    error InvalidTicker();
    error InvalidAgentKeySignature();
    error InvalidVerifierSignature();
    error XHandleTaken();
    error ZeroAddress();

    constructor(address _owner, address _verifier)
        ERC721("Aquity Agent", "AGENT")
        EIP712("AquityAgentRegistry", "1")
        Ownable(_owner)
    {
        if (_verifier == address(0)) revert ZeroAddress();
        verifier = _verifier;
    }

    modifier onlyLauncher() {
        if (msg.sender != launcher) revert NotLauncher();
        _;
    }

    function setVerifier(address _verifier) external onlyOwner {
        if (_verifier == address(0)) revert ZeroAddress();
        verifier = _verifier;
        emit VerifierUpdated(_verifier);
    }

    function setLauncher(address _launcher) external onlyOwner {
        if (_launcher == address(0)) revert ZeroAddress();
        launcher = _launcher;
        emit LauncherUpdated(_launcher);
    }

    function register(RegisterParams calldata p) external onlyLauncher returns (uint256 tokenId) {
        if (p.owner == address(0) || p.pair == address(0) || p.agentToken == address(0)) revert ZeroAddress();
        _validateTicker(p.ticker);
        if (tickerUsed[p.ticker]) revert TickerTaken();

        _checkAgentKeySignature(p.agentId, p.owner, p.agentKey, p.agentKeySignature);

        bytes32 handleHash = keccak256(bytes(p.xHandle));
        if (xHandleUsed[handleHash]) revert XHandleTaken();
        _checkVerifierSignature(p.owner, p.agentId, p.xHandle, p.xNonce, p.verifierSignature);

        tickerUsed[p.ticker] = true;
        xHandleUsed[handleHash] = true;

        tokenId = nextTokenId++;
        agents[tokenId] = Agent({
            ticker: p.ticker,
            name: p.name,
            agentId: p.agentId,
            agentKey: p.agentKey,
            xHandle: p.xHandle,
            pair: p.pair,
            agentToken: p.agentToken,
            registeredAt: block.timestamp
        });

        _safeMint(p.owner, tokenId);

        emit AgentRegistered(tokenId, p.owner, p.ticker, p.agentId, p.pair, p.agentToken);
    }

    function _validateTicker(string calldata ticker) internal pure {
        bytes memory b = bytes(ticker);
        if (b.length < 3 || b.length > 8) revert InvalidTicker();
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] < 0x41 || b[i] > 0x5A) revert InvalidTicker(); // A-Z only
        }
    }

    function _checkAgentKeySignature(
        string calldata agentId,
        address owner_,
        address agentKey,
        bytes calldata signature
    ) internal view {
        bytes32 structHash = keccak256(abi.encode(AGENT_KEY_BINDING_TYPEHASH, keccak256(bytes(agentId)), owner_));
        address signer = ECDSA.recover(_hashTypedDataV4(structHash), signature);
        if (signer != agentKey) revert InvalidAgentKeySignature();
    }

    function _checkVerifierSignature(
        address owner_,
        string calldata agentId,
        string calldata xHandle,
        uint256 nonce,
        bytes calldata signature
    ) internal view {
        bytes32 structHash =
            keccak256(abi.encode(X_VERIFICATION_TYPEHASH, owner_, keccak256(bytes(agentId)), keccak256(bytes(xHandle)), nonce));
        address signer = ECDSA.recover(_hashTypedDataV4(structHash), signature);
        if (signer != verifier) revert InvalidVerifierSignature();
    }
}
