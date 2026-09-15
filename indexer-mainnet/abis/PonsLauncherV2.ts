// Events-only ABI for the real deployed PonsLauncherV2 (Phase B) — a
// separate file from abis/PonsLauncher.ts because V2 emits one real event
// V1 never had (EnforcedRevenueRoutingDeployed), so sharing V1's ABI for
// V2's contract config would silently make that event undecodable. Only
// events are included; nothing here reads contract functions.
export const PonsLauncherV2Abi = [
  {
    "type": "event",
    "name": "AgentLaunchedOnPons",
    "inputs": [
      { "name": "tokenId", "type": "uint256", "indexed": true, "internalType": "uint256" },
      { "name": "owner", "type": "address", "indexed": true, "internalType": "address" },
      { "name": "agentKey", "type": "address", "indexed": true, "internalType": "address" },
      { "name": "ticker", "type": "string", "indexed": false, "internalType": "string" },
      { "name": "agentToken", "type": "address", "indexed": false, "internalType": "address" },
      { "name": "curve", "type": "address", "indexed": false, "internalType": "address" }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "EnforcedRevenueRoutingDeployed",
    "inputs": [
      { "name": "tokenId", "type": "uint256", "indexed": true, "internalType": "uint256" },
      { "name": "vault", "type": "address", "indexed": false, "internalType": "address" },
      { "name": "distributor", "type": "address", "indexed": false, "internalType": "address" },
      { "name": "revenueRouter", "type": "address", "indexed": false, "internalType": "address" }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "RootPosterUpdated",
    "inputs": [
      { "name": "rootPoster", "type": "address", "indexed": false, "internalType": "address" }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "OwnershipTransferred",
    "inputs": [
      { "name": "previousOwner", "type": "address", "indexed": true, "internalType": "address" },
      { "name": "newOwner", "type": "address", "indexed": true, "internalType": "address" }
    ],
    "anonymous": false
  }
] as const;
