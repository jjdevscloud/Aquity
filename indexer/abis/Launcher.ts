export const LauncherAbi = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "_owner",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_registry",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_factory",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_paymentToken",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_router",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "DEFAULT_RATE",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "DUST_THRESHOLD",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "MAX_SLIPPAGE_BPS",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "STOCK_LIQUIDITY_SEED",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "factory",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract ILaunchpadFactory"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "feeEscrowByStock",
    "inputs": [
      {
        "name": "stockToken",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "feeEscrow",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "launch",
    "inputs": [
      {
        "name": "p",
        "type": "tuple",
        "internalType": "struct Launcher.LaunchParams",
        "components": [
          {
            "name": "name",
            "type": "string",
            "internalType": "string"
          },
          {
            "name": "ticker",
            "type": "string",
            "internalType": "string"
          },
          {
            "name": "agentId",
            "type": "string",
            "internalType": "string"
          },
          {
            "name": "agentKey",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "agentKeySignature",
            "type": "bytes",
            "internalType": "bytes"
          },
          {
            "name": "xHandle",
            "type": "string",
            "internalType": "string"
          },
          {
            "name": "xNonce",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "verifierSignature",
            "type": "bytes",
            "internalType": "bytes"
          },
          {
            "name": "stockName",
            "type": "string",
            "internalType": "string"
          },
          {
            "name": "stockSymbol",
            "type": "string",
            "internalType": "string"
          },
          {
            "name": "sector",
            "type": "string",
            "internalType": "string"
          },
          {
            "name": "minTokensOut",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "vestingReporter",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "vestingRevenueTarget",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "vaultShareBps",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "feeSplitBps",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      }
    ],
    "outputs": [
      {
        "name": "tokenId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "agentToken",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "vault",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "vesting",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "owner",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "paymentToken",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IERC20"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "registry",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract AgentRegistry"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "renounceOwnership",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "router",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract MockRouter"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "setFactory",
    "inputs": [
      {
        "name": "_factory",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setVestingAdmin",
    "inputs": [
      {
        "name": "_vestingAdmin",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "stockTokenBySymbol",
    "inputs": [
      {
        "name": "symbolHash",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [
      {
        "name": "stockToken",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "transferOwnership",
    "inputs": [
      {
        "name": "newOwner",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "vestingAdmin",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "AgentFullyLaunched",
    "inputs": [
      {
        "name": "tokenId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "owner",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "ticker",
        "type": "string",
        "indexed": false,
        "internalType": "string"
      },
      {
        "name": "name",
        "type": "string",
        "indexed": false,
        "internalType": "string"
      },
      {
        "name": "sector",
        "type": "string",
        "indexed": false,
        "internalType": "string"
      },
      {
        "name": "agentToken",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "vault",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "splitter",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "feeRouter",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "distributor",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "vesting",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "pool",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "stockToken",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "OwnershipTransferred",
    "inputs": [
      {
        "name": "previousOwner",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "newOwner",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "OwnableInvalidOwner",
    "inputs": [
      {
        "name": "owner",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "OwnableUnauthorizedAccount",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "ZeroAddress",
    "inputs": []
  }
] as const;
