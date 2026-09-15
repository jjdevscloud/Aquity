import { createConfig } from "ponder";

import { AgentRegistryAbi } from "./abis/AgentRegistry";
import { PonsLauncherAbi } from "./abis/PonsLauncher";

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
      startBlock: Number(process.env.PONS_LAUNCHER_START_BLOCK ?? 0),
    },
  },
});
