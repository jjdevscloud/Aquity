// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Real Pons v2 launchpad factory on Robinhood Chain mainnet
/// (chain 4663), at 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e — not a mock.
/// Struct layout and function selectors verified against
/// github.com/ponsmcp/pons-mcp's self-checking ABI table (src/abi.ts, which
/// recomputes every selector from its canonical signature string and
/// asserts it against a hardcoded constant, crashing on mismatch) and its
/// launch flow (src/launch.ts) — not guessed. Reshape only if Pons itself
/// changes its ABI.
interface IPonsFactory {
    struct Socials {
        string twitter;
        string telegram;
        string discord;
        string website;
        string farcaster;
    }

    struct TokenParams {
        string name;
        string symbol;
        string logo;
        string description;
        Socials socials;
        address creatorFeeRecipient;
        uint16 creatorTaxBps;
        bool buybackEnabled;
        bytes32 expectedEconomics;
        bytes32 salt;
    }

    event TokenLaunched(
        address indexed token, address indexed curve, address indexed deployer, address pairToken, uint256 launchConfigId, uint256 graduationThreshold
    );

    function launchFee() external view returns (uint256);
    function launchEnabled() external view returns (bool);
    function canLaunch(address account) external view returns (bool);
    function maxCreatorTaxBps() external view returns (uint256);
    function previewLaunchEconomics(uint256 launchConfigId, address pairToken) external view returns (bytes32);
    function launchForwarder() external view returns (address);
    /// @notice The real, live PonsV2FeeEscrow — confirmed on mainnet at
    /// 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e via this exact getter
    /// (selector 0xc4b7de97, "feeEscrow()"). Read live rather than
    /// hardcoded so a Pons-side redeploy can't silently strand claims.
    function feeEscrow() external view returns (address);

    /// @notice No dev buy. `msg.value` must equal `launchFee()` exactly.
    /// Returns the freshly deployed token and its bonding-curve pool —
    /// confirmed via pons-mcp's simulation path (src/launch.ts), which
    /// decodes these as the eth_call return value.
    function launchToken(TokenParams calldata params, uint256 launchConfigId, address pairToken, address[] calldata snipeTaxExemptions)
        external
        payable
        returns (address token, address curve);
}

/// @notice The live `launchForwarder()` — a separate router contract — for
/// the atomic dev-buy path. Same TokenParams; `msg.value = launchFee + devBuy`.
interface IPonsLaunchAndBuyRouter {
    function launchAndBuy(
        IPonsFactory.TokenParams calldata params,
        uint256 launchConfigId,
        address pairToken,
        uint256 devBuyAmount,
        uint256 minTokensOut,
        address devBuyRecipient,
        address[] calldata snipeTaxExemptions
    ) external payable;
}
