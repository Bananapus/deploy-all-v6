# deploy-all-v6 -- Architecture

## Purpose

Master deployment script for the current canonical Juicebox V6 rollout. This repo exists to describe what
`script/Deploy.s.sol` actually deploys today, not every sibling package that exists in the workspace.

## Directory Map

```
script/
└── Deploy.s.sol — Sphinx deployment script (~1,600 lines)
```

There is no `src/` directory. This repo exists solely to orchestrate ecosystem deployment.

## What It Deploys

The script deploys the following production-scoped stack in dependency order:

### Core Protocol
- `JBPermissions`
- `JBProjects`
- `JBPrices`
- `JBRulesets`
- `JBDirectory`
- `JBERC20`
- `JBTokens`
- `JBSplits`
- `JBFeelessAddresses`
- `JBFundAccessLimits`
- `JBController`
- `JBTerminalStore`
- `JBMultiTerminal`
- `ERC2771Forwarder`

### Periphery
- `JBDeadline` variants (3h, 1d, 3d, 7d)
- `JBChainlinkV3PriceFeed` / `JBChainlinkV3SequencerPriceFeed`
- `JBMatchingPriceFeed`
- `JBAddressRegistry`

### Hooks & Extensions
- `JB721TiersHook` + `JB721TiersHookStore` + deployers
- `JBUniswapV4Hook`
- `JBBuybackHook` + `JBBuybackHookRegistry`
- `JBUniswapV4LPSplitHook` + `JBUniswapV4LPSplitHookDeployer`
- `JBRouterTerminal` + `JBRouterTerminalRegistry`

### Cross-Chain
- `JBSuckerRegistry`
- `JBOptimismSuckerDeployer`
- `JBBaseSuckerDeployer`
- `JBArbitrumSuckerDeployer`
- `JBCCIPSuckerDeployer`

### Applications
- `REVDeployer`
- `REVLoans`
- `CTPublisher`
- `CTDeployer`
- `CTProjectOwner`
- `Banny721TokenUriResolver`

## What It Does Not Deploy

The current script does not instantiate:

- `JBOwnable`
- Defifa contracts

## Deployment Order

```
Sphinx proposal → Deploy.deploy()
  Phase 01: Core protocol
  Phase 02: Address registry
  Phase 03a: 721 hook stack
  Phase 03b: Uniswap V4 router hook
  Phase 03c: Buyback hook stack
  Phase 03d: Router terminal stack
  Phase 03e: LP split hook stack
  Phase 03f: Cross-chain suckers
  Phase 04: Omnichain deployer
  Phase 05: Periphery and controller wiring
  Phase 06: Croptop
  Phase 07: REV revnet
  Phase 08: Existing project configuration
  Phase 09: Banny
```

## Deployment Transport Limits

Each chain executes one Sphinx-managed `deploy()` call, but this repo does not yet ship a resumable recovery script.
If execution halts after some CREATE2 deployments succeed, operators must either resume with a purpose-built script
that skips already-deployed contracts or redeploy from fresh salts. Re-proposing the full script with the same salts
is not a safe recovery path.

## Target Chains

- Mainnets: Ethereum, Optimism, Base, Arbitrum
- Testnets: Ethereum Sepolia, Optimism Sepolia, Base Sepolia, Arbitrum Sepolia

Configured addresses exist for the supported chains, but the testnet path is not equally production-ready. On
Optimism Sepolia the canonical core/periphery rollout still deploys, but the Uniswap-dependent phases are skipped
because there is no published Uniswap V4 `PositionManager`.

## Dependencies

All V6 ecosystem packages plus Sphinx, OpenZeppelin, Chainlink, Uniswap, PRB Math, Solady.
