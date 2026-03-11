# deploy-all-v6 — Architecture

## Purpose

Master deployment script for the entire Juicebox V6 ecosystem. Deploys all core contracts, hooks, registries, and periphery in a single Sphinx-orchestrated multi-chain deployment. This is the canonical deployment path for production.

## Directory Map

```
script/
└── Deploy.s.sol — Sphinx deployment script (~1,600 lines)
```

There is no `src/` directory. This repo exists solely to orchestrate ecosystem deployment.

## What It Deploys

The script deploys the complete V6 ecosystem in dependency order:

### Core Protocol
- `JBPermissions` — Permission system
- `JBProjects` — ERC-721 project ownership
- `JBPrices` — Price feed registry
- `JBRulesets` — Ruleset lifecycle
- `JBDirectory` — Terminal/controller routing
- `JBERC20` — Cloneable ERC-20 implementation
- `JBTokens` — Token management
- `JBSplits` — Split distribution
- `JBFeelessAddresses` — Fee exemptions
- `JBFundAccessLimits` — Payout/surplus limits
- `JBController` — Project orchestrator
- `JBTerminalStore` — Bookkeeping
- `JBMultiTerminal` — Multi-token terminal
- `ERC2771Forwarder` — Meta-transaction forwarder

### Periphery
- `JBDeadline` variants (3h, 1d, 3d, 7d) — Approval hooks
- `JBChainlinkV3PriceFeed` / `JBChainlinkV3SequencerPriceFeed` — Price feeds
- `JBMatchingPriceFeed` — Price mediation
- `JBAddressRegistry` — Deployer verification

### Hooks & Extensions
- `JB721TiersHook` + `JB721TiersHookStore` + Deployers — NFT tiers
- `JBUniswapV4Hook` — Uniswap V4 router hook (oracle hook providing TWAP via `observe()`)
- `JBBuybackHook` + `JBBuybackHookRegistry` — DEX buyback (wired to `JBUniswapV4Hook` as its oracle)
- `JBUniswapV4LPSplitHook` — LP split hook (wired to `JBUniswapV4Hook` as its oracle)
- `JBRouterTerminal` + `JBRouterTerminalRegistry` — Payment routing
- `JBOwnable` — JB-aware ownership

### Cross-Chain
- `JBSuckerRegistry` — Sucker management
- `JBOptimismSuckerDeployer` / `JBBaseSuckerDeployer` / `JBArbitrumSuckerDeployer` / `JBCCIPSuckerDeployer`

### Applications
- `REVDeployer` (basic + croptop variants) — Revnet deployers
- `REVLoans` — Revnet loans
- `CTPublisher` — Croptop publisher
- Defifa contracts — Prediction games

## Deployment Order

```
Sphinx proposal → Deploy.deploy()
  Phase 1: Core contracts (no external dependencies)
  Phase 2: Periphery (depends on core)
  Phase 3: Hooks (depends on core + periphery)
  Phase 4: Cross-chain (depends on core + hooks)
  Phase 5: Applications (depends on everything above)
  Phase 6: Wiring (set terminals, controllers, registrations)
```

### Oracle Hook Dependency Chain

The `JBUniswapV4Hook` (router hook) acts as the oracle hook for both the buyback hook and the LP split hook. It implements `IGeomeanOracle`-compatible `observe()` for TWAP queries. Both `JBBuybackHook` and `JBUniswapV4LPSplitHook` accept an `oracleHook` constructor parameter that must point to a deployed `JBUniswapV4Hook` instance.

Required deployment ordering within Phase 3:
1. `JBUniswapV4Hook` (router hook / oracle hook) -- deployed first, provides TWAP oracle
2. `JBBuybackHook` -- constructor receives `JBUniswapV4Hook` address as `oracleHook`
3. `JBUniswapV4LPSplitHook` -- constructor receives `JBUniswapV4Hook` address as `oracleHook`

## Target Chains
- Mainnets: Ethereum, Optimism, Base, Arbitrum
- Testnets: Ethereum Sepolia, Optimism Sepolia, Base Sepolia, Arbitrum Sepolia

## Dependencies
All V6 ecosystem packages plus Sphinx, OpenZeppelin, Chainlink, Uniswap, PRB Math, Solady.
