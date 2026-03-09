# Deploy All V6

Single Foundry script that deploys the entire Juicebox V6 ecosystem via [Sphinx](https://github.com/sphinx-labs/sphinx) across 8 chains.

## Chains

**Mainnets:** Ethereum, Optimism, Base, Arbitrum
**Testnets:** Ethereum Sepolia, Optimism Sepolia, Base Sepolia, Arbitrum Sepolia

## Deployment Phases

The script deploys contracts in dependency order within one Sphinx proposal:

| Phase | What's deployed | Key contracts |
|-------|----------------|---------------|
| 01 | Core protocol | ERC2771Forwarder, JBPermissions, JBProjects, JBDirectory, JBSplits, JBRulesets, JBPrices, JBTokens, JBERC20, JBFundAccessLimits, JBFeelessAddresses, JBTerminalStore, JBMultiTerminal |
| 02 | Address registry | JBAddressRegistry |
| 03a | 721 tier hook | JB721TiersHook, JB721TiersHookDeployer, JB721TiersHookProjectDeployer, JB721TiersHookStore |
| 03b | Buyback hook | JBBuybackHook, JBBuybackHookRegistry |
| 03c | Router terminal | JBRouterTerminal, JBRouterTerminalRegistry |
| 03d | Cross-chain suckers | JBOptimismSucker, JBBaseSucker, JBArbitrumSucker, JBCCIPSucker, JBSuckerRegistry + deployers |
| 04 | Omnichain deployer | JBOmnichainDeployer |
| 05 | Periphery | JBController, price feeds (Chainlink V3 + sequencer), deadlines (3h, 1d, 3d, 7d) |
| 06 | Croptop | CPN project (ID 2), CTDeployer, CTPublisher |
| 07 | Revnet | REV project (ID 3), REVLoans, REVDeployer |
| 08 | CPN + NANA revnets | Configure project 2 and project 1 as revnets |
| 09 | Banny | BAN project (ID 4) |

Defifa deployment (phase 10) is stubbed but not yet active.

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
