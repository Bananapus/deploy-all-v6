# Juicebox Deploy All

Single Foundry script that deploys the current canonical Juicebox V6 rollout via [Sphinx](https://github.com/sphinx-labs/sphinx) across the configured chains.

## Chains

**Mainnets:** Ethereum, Optimism, Base, Arbitrum
**Testnets:** Ethereum Sepolia, Optimism Sepolia, Base Sepolia, Arbitrum Sepolia

The script contains chain-specific addresses for all 8 chains, but the testnet matrix is not equally mature. In
particular, OP Sepolia still carries a PoolManager TODO in `script/Deploy.s.sol`, so treat testnet deployments as
chain-by-chain validation targets rather than a blanket "all testnets are production-shaped" guarantee.

## Deployment Phases

The script deploys contracts in dependency order within one Sphinx proposal:

| Phase | What's deployed | Key contracts |
|-------|----------------|---------------|
| 01 | Core protocol | ERC2771Forwarder, JBPermissions, JBProjects, JBDirectory, JBSplits, JBRulesets, JBPrices, JBTokens, JBERC20, JBFundAccessLimits, JBFeelessAddresses, JBTerminalStore, JBMultiTerminal |
| 02 | Address registry | JBAddressRegistry |
| 03a | 721 tier hook | JB721TiersHook, JB721TiersHookDeployer, JB721TiersHookProjectDeployer, JB721TiersHookStore |
| 03b | Uniswap V4 router hook | JBUniswapV4Hook |
| 03c | Buyback hook | JBBuybackHook, JBBuybackHookRegistry |
| 03d | Router terminal | JBRouterTerminal, JBRouterTerminalRegistry |
| 03e | LP split hook | JBUniswapV4LPSplitHook, JBUniswapV4LPSplitHookDeployer |
| 03f | Cross-chain suckers | JBOptimismSucker, JBBaseSucker, JBArbitrumSucker, JBCCIPSucker, JBSuckerRegistry + deployers |
| 04 | Omnichain deployer | JBOmnichainDeployer |
| 05 | Periphery | JBController, price feeds (Chainlink V3 + sequencer), deadlines (3h, 1d, 3d, 7d) |
| 06 | Croptop | CPN project (ID 2), CTDeployer, CTPublisher |
| 07 | Revnet | REV project (ID 3), REVLoans, REVDeployer |
| 08 | CPN + NANA revnets | Configure project 2 and project 1 as revnets |
| 09 | Banny | BAN project (ID 4) |

The current script does **not** deploy Defifa or `JBOwnable`. It does deploy the canonical Uniswap V4 stack:
`JBUniswapV4Hook`, `JBBuybackHook` wired to that router hook as its oracle, and
`JBUniswapV4LPSplitHook` plus `JBUniswapV4LPSplitHookDeployer`.

## Recovery Model

This repo does **not** currently ship a resumable partial-deployment recovery script. If a live Sphinx execution stops
after some CREATE2 deployments succeed, re-proposing the full script with the same salts is not a safe recovery path:
those deployments will collide with contracts that already exist.

Operationally, treat recovery as one of two explicit options:

1. Resume with a purpose-built script that skips already-deployed contracts and performs only the remaining wiring.
2. Redeploy from fresh salts and discard the partial deployment.

Do not rely on ad hoc re-proposal of the full script after a partial execution.

## Prerequisites

- [Foundry](https://getfoundry.sh)
- Node.js >= 20
- All sibling V6 repos cloned as siblings (this repo uses `file:` dependencies)

## Setup

```bash
npm install
forge build
```

## Dependencies

This repo references all other V6 repos via `file:../` paths in `package.json`:

```
../nana-core-v6
../nana-permission-ids-v6
../nana-address-registry-v6
../nana-721-hook-v6
../nana-buyback-hook-v6
../nana-router-terminal-v6
../nana-suckers-v6
../nana-omnichain-deployers-v6
../nana-ownable-v6
../univ4-router-v6
../univ4-lp-split-hook-v6
../revnet-core-v6
../croptop-core-v6
../banny-retail-v6
../defifa-collection-deployer-v6
```

Clone all repos as siblings, or use the [meta-repo](https://github.com/Bananapus/version-6):

```bash
git clone --recursive https://github.com/Bananapus/version-6.git
```

## Build Configuration

- Solidity 0.8.26, Cancun EVM
- `via_ir = true` (required for stack depth)
- Optimizer disabled (stack-too-deep with optimization enabled)
- Sphinx plugin for multi-chain atomic deployment

## License

MIT
