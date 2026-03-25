# deploy-all-v6 Changelog (v5 → v6)

This document describes the changes between `deploy-all` (v5) and `deploy-all-v6` (v6). This repo contains no runtime contracts — it is a Sphinx-based deployment orchestrator for the entire Juicebox V6 ecosystem.

## Summary

- **9-phase deployment pipeline**: Deterministic, dependency-ordered deployment of the full V6 stack across 8 chains (Ethereum, Optimism, Base, Arbitrum + their testnets).
- **Uniswap V4 integration**: New deployment phases for `JBUniswapV4Hook`, V4-based buyback hook with oracle, and LP split hook — none of which existed in v5.
- **Cross-chain suckers**: Full sucker infrastructure (registry + OP/Base/Arbitrum/CCIP deployers) deployed as a canonical phase.
- **Omnichain deployer**: Data hook proxy enabling 0% cashout tax for cross-chain operations, deployed as its own phase.
- **Comprehensive test suite**: Fork tests covering full-stack integration, ecosystem interactions, price feed failures, and sucker end-to-end operations.

---

## 1. Deployment Phases

v6 organizes deployment into 9 deterministic phases with explicit dependency ordering:

| Phase | Contents | v5 Equivalent |
|-------|----------|---------------|
| 01 | Core protocol (`JBController`, `JBMultiTerminal`, `JBDirectory`, `JBProjects`, etc.) | Similar |
| 02 | Address registry (`JBAddressRegistry`) | Similar |
| 03a | 721 tier hook (`JB721TiersHook`, deployer, store) | Similar |
| 03b | Uniswap V4 router hook (`JBUniswapV4Hook`) | **New** |
| 03c | Buyback hook with V4 oracle (`JBBuybackHook`, registry) | Rearchitected (was V3) |
| 03d | Router terminal (`JBRouterTerminal`, registry) | Replaces swap terminal |
| 03e | LP split hook (`JBUniswapV4LPSplitHook`) | **New** |
| 03f | Cross-chain suckers (registry + 4 bridge deployers) | **New** |
| 04 | Omnichain deployer (`JBOmnichainDeployer`) | **New** |
| 05 | Periphery + Controller wiring | Similar |
| 06 | Croptop (`CTDeployer`, `CTPublisher`) | Similar |
| 07 | Revnet (`REVDeployer`, `REVLoans`) | Similar |
| 08 | CPN/NANA revnet configuration | Similar |
| 09 | Banny (`Banny721TokenUriResolver`) | Similar |

### Phase Dependencies

Each phase depends on artifacts from earlier phases. The Sphinx plugin ensures all phases within a single proposal are deployed atomically per chain.

---

## 2. New in V6

### 2.1 Uniswap V4 Stack

The entire Uniswap V4 integration is new in v6:
- `JBUniswapV4Hook` — canonical router hook for V4 pool interactions
- `TruncGeoOracle` — geometric mean oracle hook providing TWAP data for buyback
- `JBBuybackHook` — now targets V4's `PoolManager` singleton instead of individual V3 pools
- `JBUniswapV4LPSplitHook` — manages LP positions as split recipients
- `JBRouterTerminal` — discovers pools across both V3 and V4

### 2.2 Cross-Chain Infrastructure

Sucker infrastructure deployed as a canonical phase:
- `JBSuckerRegistry` — central registry for all sucker pairs
- `JBOptimismSuckerDeployer` — OP Stack bridges (Optimism, Base)
- `JBArbitrumSuckerDeployer` — Arbitrum bridge
- `JBCCIPSuckerDeployer` — Chainlink CCIP bridges
- Per-chain bridge address configuration (messengers, routers, inbox contracts)
- CCIP chain selector mappings for arbitrary chain pairs

### 2.3 Omnichain Deployer

`JBOmnichainDeployer` acts as a data hook proxy, composing 721 hooks and extra data hooks (buyback) with proportional weight scaling. Enables 0% cashout tax for sucker-mediated cross-chain operations.

### 2.4 Chain Support

| Chain | Mainnet | Testnet |
|-------|---------|---------|
| Ethereum | ✅ | ✅ (Sepolia) |
| Optimism | ✅ | ✅ (Sepolia) |
| Base | ✅ | ✅ (Sepolia) |
| Arbitrum | ✅ | ✅ (Sepolia) |

**Note**: Optimism Sepolia skips V4 phases due to missing `PositionManager` deployment.

---

## 3. V5 → V6 Differences

### 3.1 Removed Components
- Uniswap V3-only swap terminal (`JBSwapTerminal`) — replaced by `JBRouterTerminal`
- Manual pool configuration — replaced by automatic pool discovery
- WETH wrapping/unwrapping in buyback — V4 handles native ETH natively

### 3.2 Compiler & Tooling
| Aspect | v5 | v6 |
|--------|----|----|
| Solidity | `0.8.23` | `0.8.26` |
| EVM target | `paris` | `cancun` |
| `via_ir` | varies | `true` (required for stack depth) |
| Optimizer | enabled | disabled |
| Deployment tool | Sphinx | Sphinx (updated plugin path) |

### 3.3 Testing
v6 adds comprehensive deployment verification tests:
- Full-stack fork tests against live chain state
- Ecosystem integration tests (buyback + 721 + LP-split + V4)
- Price feed failure scenarios
- Sucker end-to-end operations
- Address verification for deployed contracts

---

## 4. Documentation

v6 ships with comprehensive operational documentation:
- `ARCHITECTURE.md` — dependency graph and design decisions
- `RISKS.md` — cross-repo composition risk analysis
- `ADMINISTRATION.md` — admin privilege mapping
- `AUDIT_INSTRUCTIONS.md` — audit preparation guide
- `SKILLS.md` — orchestration knowledge base
- `USER_JOURNEYS.md` — deployment workflows

---

## 5. Not Yet Deployed

- `JBOwnable` (v6 exists but not included in deploy phases)
