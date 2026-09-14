import { createConfig } from "ponder";

import { AgentRegistryAbi } from "./abis/AgentRegistry";
import { LauncherAbi } from "./abis/Launcher";
import { SplitterAbi } from "./abis/Splitter";
import { VaultAbi } from "./abis/Vault";
import { FeeRouterAbi } from "./abis/FeeRouter";
import { DistributorAbi } from "./abis/Distributor";
import { VestingAbi } from "./abis/Vesting";
import { ERC20Abi } from "./abis/ERC20";
import {
  agentTokenAddresses,
  distributorAddresses,
  feeRouterAddresses,
  minStartBlock,
  splitterAddresses,
  vaultAddresses,
  vestingAddresses,
} from "./src/lib/agents";

const chainId = Number(process.env.ROBINHOOD_CHAIN_ID);
const rpcUrl = process.env.ROBINHOOD_RPC_URL;
if (!rpcUrl) throw new Error("Set ROBINHOOD_RPC_URL — see .env.example");
if (!Number.isFinite(chainId)) throw new Error("Set ROBINHOOD_CHAIN_ID — see .env.example");

const registryAddress = process.env.AGENT_REGISTRY_ADDRESS as `0x${string}` | undefined;
const launcherAddress = process.env.LAUNCHER_ADDRESS as `0x${string}` | undefined;
if (!registryAddress) throw new Error("Set AGENT_REGISTRY_ADDRESS — see .env.example");
if (!launcherAddress) throw new Error("Set LAUNCHER_ADDRESS — see .env.example");

export default createConfig({
  chains: {
    robinhood: {
      id: chainId,
      rpc: rpcUrl,
      // Without this, Ponder auto-shrinks the eth_getLogs range based on
      // error messages it sees (it dropped to 8-9 blocks after early
      // failures against the public RPC), which then fires enough parallel
      // requests to trip Alchemy's free-tier rate limit. Pin it explicitly.
      ethGetLogsBlockRange: 10_000,
    },
  },
  contracts: {
    AgentRegistry: {
      chain: "robinhood",
      abi: AgentRegistryAbi,
      address: registryAddress,
      startBlock: Number(process.env.AGENT_REGISTRY_START_BLOCK ?? 0),
    },
    Launcher: {
      chain: "robinhood",
      abi: LauncherAbi,
      address: launcherAddress,
      startBlock: Number(process.env.LAUNCHER_START_BLOCK ?? 0),
    },
    // Everything below is per-agent and address-listed from agents.config.json
    // rather than discovered on-chain — AQUITY-SPEC.md §10 Phase 5 isn't
    // permissionless yet, and these contracts are deployed one-off per agent
    // via the Foundry scripts in /contracts, not through a factory Launcher
    // calls. See src/lib/agents.ts and the README.
    Splitter: {
      chain: "robinhood",
      abi: SplitterAbi,
      address: splitterAddresses,
      startBlock: minStartBlock,
    },
    Vault: {
      chain: "robinhood",
      abi: VaultAbi,
      address: vaultAddresses,
      startBlock: minStartBlock,
    },
    FeeRouter: {
      chain: "robinhood",
      abi: FeeRouterAbi,
      address: feeRouterAddresses,
      startBlock: minStartBlock,
    },
    Distributor: {
      chain: "robinhood",
      abi: DistributorAbi,
      address: distributorAddresses,
      startBlock: minStartBlock,
    },
    Vesting: {
      chain: "robinhood",
      abi: VestingAbi,
      address: vestingAddresses,
      startBlock: minStartBlock,
    },
    AgentToken: {
      chain: "robinhood",
      abi: ERC20Abi,
      address: agentTokenAddresses,
      startBlock: minStartBlock,
    },
  },
});
