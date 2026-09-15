import { createConfig, factory } from "ponder";

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
const launcherStartBlock = Number(process.env.LAUNCHER_START_BLOCK ?? 0);

const agentFullyLaunchedEvent = LauncherAbi.find(
  (item) => item.type === "event" && item.name === "AgentFullyLaunched",
);
if (!agentFullyLaunchedEvent) throw new Error("LauncherAbi is missing AgentFullyLaunched — regenerate abis/Launcher.ts");

export default createConfig({
  chains: {
    robinhood: {
      id: chainId,
      rpc: rpcUrl,
      // Without this, Ponder auto-shrinks the eth_getLogs range based on
      // error messages it sees (it dropped to 8-9 blocks after early
      // failures against the public RPC), which then fires enough parallel
      // requests to trip Alchemy's free-tier rate limit. Pin it explicitly.
      ethGetLogsBlockRange: 2000,
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
      startBlock: launcherStartBlock,
    },
    // The original curated cohort (AQUITY-SPEC.md §10 Phase 5's "twenty
    // hand-picked agents") — deployed one-off via the Foundry scripts in
    // /contracts and address-listed here from agents.config.json, not
    // discovered on-chain. See src/lib/agents.ts and the README.
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
    // Everything below is any agent launched since Launcher.sol grew its
    // own Vault/Splitter/FeeRouter/Distributor auto-deployment — addresses
    // aren't known ahead of time, so Ponder discovers them itself from
    // Launcher's own AgentFullyLaunched event (one factory contract per
    // address field in that event). See src/Launcher.ts, which is what
    // actually makes these findable by ticker, and src/*.ts's shared
    // handlers, registered under both the curated and Auto contract names.
    SplitterAuto: {
      chain: "robinhood",
      abi: SplitterAbi,
      address: factory({ address: launcherAddress, event: agentFullyLaunchedEvent, parameter: "splitter" }),
      startBlock: launcherStartBlock,
    },
    VaultAuto: {
      chain: "robinhood",
      abi: VaultAbi,
      address: factory({ address: launcherAddress, event: agentFullyLaunchedEvent, parameter: "vault" }),
      startBlock: launcherStartBlock,
    },
    FeeRouterAuto: {
      chain: "robinhood",
      abi: FeeRouterAbi,
      address: factory({ address: launcherAddress, event: agentFullyLaunchedEvent, parameter: "feeRouter" }),
      startBlock: launcherStartBlock,
    },
    DistributorAuto: {
      chain: "robinhood",
      abi: DistributorAbi,
      address: factory({ address: launcherAddress, event: agentFullyLaunchedEvent, parameter: "distributor" }),
      startBlock: launcherStartBlock,
    },
    VestingAuto: {
      chain: "robinhood",
      abi: VestingAbi,
      address: factory({ address: launcherAddress, event: agentFullyLaunchedEvent, parameter: "vesting" }),
      startBlock: launcherStartBlock,
    },
    AgentTokenAuto: {
      chain: "robinhood",
      abi: ERC20Abi,
      address: factory({ address: launcherAddress, event: agentFullyLaunchedEvent, parameter: "agentToken" }),
      startBlock: launcherStartBlock,
    },
  },
});
