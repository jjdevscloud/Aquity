import { createConfig, factory } from "ponder";

import { AgentRegistryAbi } from "./abis/AgentRegistry";
import { PonsLauncherAbi } from "./abis/PonsLauncher";
import { ERC20Abi } from "./abis/ERC20";

const chainId = Number(process.env.ROBINHOOD_CHAIN_ID);
const rpcUrl = process.env.ROBINHOOD_MAINNET_RPC_URL;
if (!rpcUrl) throw new Error("Set ROBINHOOD_MAINNET_RPC_URL — see .env.example");
if (!Number.isFinite(chainId)) throw new Error("Set ROBINHOOD_CHAIN_ID — see .env.example");
if (chainId !== 4663) {
  throw new Error(`ROBINHOOD_CHAIN_ID is ${chainId}, expected 4663 (mainnet) — this project never runs against testnet`);
}

const registryAddress = process.env.AGENT_REGISTRY_ADDRESS as `0x${string}` | undefined;
const launcherAddress = process.env.PONS_LAUNCHER_ADDRESS as `0x${string}` | undefined;
if (!registryAddress) throw new Error("Set AGENT_REGISTRY_ADDRESS — see .env.example");
if (!launcherAddress) throw new Error("Set PONS_LAUNCHER_ADDRESS — see .env.example");
const launcherStartBlock = Number(process.env.PONS_LAUNCHER_START_BLOCK ?? 0);

// PonsLauncherV2 (Phase B) — AgentRegistry.setLauncher() was repointed here
// mid-session, so every launch since (real or test) is invisible to this
// indexer unless it's tracked as its own contract too. AgentLaunchedOnPons's
// signature is byte-identical between V1 and V2 (confirmed against both
// source files), so reusing PonsLauncherAbi here is safe — V2's extra
// LaunchParams fields don't appear in this event. Required, not optional:
// src/PonsLauncher.ts and src/AgentToken.ts bind handlers to this contract
// name unconditionally, so a config without it would fail to start anyway —
// better to fail loudly here with a clear message.
const launcherV2Address = process.env.PONS_LAUNCHER_V2_ADDRESS as `0x${string}` | undefined;
if (!launcherV2Address) throw new Error("Set PONS_LAUNCHER_V2_ADDRESS — see .env.example");
const launcherV2StartBlock = Number(process.env.PONS_LAUNCHER_V2_START_BLOCK ?? 0);

const agentLaunchedEvent = PonsLauncherAbi.find(
  (item) => item.type === "event" && item.name === "AgentLaunchedOnPons",
);
if (!agentLaunchedEvent) throw new Error("PonsLauncherAbi is missing AgentLaunchedOnPons — regenerate abis/PonsLauncher.ts");

export default createConfig({
  chains: {
    robinhoodMainnet: {
      id: chainId,
      rpc: rpcUrl,
      // Same reasoning as /indexer's testnet config: pin this explicitly
      // rather than let Ponder auto-shrink it after early RPC errors.
      ethGetLogsBlockRange: 2000,
    },
  },
  contracts: {
    AgentRegistry: {
      chain: "robinhoodMainnet",
      abi: AgentRegistryAbi,
      address: registryAddress,
      startBlock: Number(process.env.AGENT_REGISTRY_START_BLOCK ?? 0),
    },
    PonsLauncher: {
      chain: "robinhoodMainnet",
      abi: PonsLauncherAbi,
      address: launcherAddress,
      startBlock: launcherStartBlock,
    },
    // Every agent's own token — address isn't known ahead of time, so
    // Ponder discovers it from PonsLauncher's own AgentLaunchedOnPons event
    // (same factory-discovery pattern the testnet indexer already uses for
    // Launcher.sol's auto-deployed contracts). Needed for Phase B's
    // distribution job (src/jobs/postEpochRoot.ts) to compute time-weighted
    // holder balances — see src/AgentToken.ts.
    AgentTokenAuto: {
      chain: "robinhoodMainnet",
      abi: ERC20Abi,
      address: factory({ address: launcherAddress, event: agentLaunchedEvent, parameter: "agentToken" }),
      startBlock: launcherStartBlock,
    },
    PonsLauncherV2: {
      chain: "robinhoodMainnet",
      abi: PonsLauncherAbi,
      address: launcherV2Address,
      startBlock: launcherV2StartBlock,
    },
    AgentTokenAutoV2: {
      chain: "robinhoodMainnet",
      abi: ERC20Abi,
      address: factory({ address: launcherV2Address, event: agentLaunchedEvent, parameter: "agentToken" }),
      startBlock: launcherV2StartBlock,
    },
  },
});
