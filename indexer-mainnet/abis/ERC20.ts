/**
 * Minimal standard ERC-20 surface — the agent token itself is deployed by
 * Pons (not one of our own contracts), so there's no local build artifact
 * for it. Transfer is the only event Phase B's distribution job needs.
 */
export const ERC20Abi = [
  {
    type: "event",
    name: "Transfer",
    inputs: [
      { name: "from", type: "address", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "value", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
] as const;
