/**
 * Minimal standard ERC-20 surface, hand-written rather than pulled from
 * Foundry output — the agent token itself is deployed by the third-party
 * launchpad (AQUITY-SPEC.md §3.2), not one of our own contracts, so there's
 * no local build artifact for it. Transfer is the only event we index.
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
