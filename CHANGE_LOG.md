# deploy-all-v6 Changelog (v5 → v6)

This document describes the changes between `deploy-all` (v5) and `deploy-all-v6` (v6). This repo contains no runtime contracts — it is a Sphinx-based deployment orchestrator for the entire Juicebox V6 ecosystem.

## Summary

- **10-phase deployment pipeline**: Deterministic, dependency-ordered deployment of the full V6 stack across 8 chains (Ethereum, Optimism, Base, Arbitrum + their testnets).
- **Uniswap V4 integration**: New deployment phases for `JBUniswapV4Hook`, V4-based buyback hook with oracle, and LP split hook — none of which existed in v5.
- **Cross-chain suckers**: Full sucker infrastructure (registry + OP/Base/Arbitrum/CCIP deployers) deployed as a canonical phase.
- **Omnichain deployer**: Data hook proxy enabling 0% cashout tax for cross-chain operations, deployed as its own phase.
- **Defifa included in the canonical rollout**: Phase 10 now deploys `DefifaHook`, `DefifaTokenUriResolver`, `DefifaGovernor`, and `DefifaDeployer`.
- **Comprehensive test suite**: Fork tests covering full-stack integration, ecosystem interactions, price feed failures, and sucker end-to-end operations.

## ABI Status

This repo is a deployment orchestrator, not a runtime protocol surface.

For ABI migration purposes:
- there is no canonical user-facing contract ABI here to port from v5;
- the important outputs are deployed addresses, deployment phases, and manifest/artifact structure;
- consumers should use this changelog to understand where v6 ABIs come from, not as an ABI diff source itself.

---

## 1. Deployment Phases

v6 organizes deployment into 10 deterministic phases with explicit dependency ordering:

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
| 10 | Defifa (`DefifaHook`, `DefifaTokenUriResolver`, `DefifaGovernor`, `DefifaDeployer`) | New in `deploy-all-v6` |

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

### 2.5 Defifa Rollout

`deploy-all-v6` now deploys the Defifa game stack directly instead of treating it as out-of-band:
- `DefifaHook` code origin for clone-based game deployment
- `DefifaTokenUriResolver` for on-chain SVG metadata
- `DefifaGovernor` for scorecard attestation and ratification
- `DefifaDeployer` as the game factory

This matters for integrators because a full ecosystem rollout now includes the Defifa addresses and ownership handoff in the same canonical proposal as the rest of the V6 stack.

---

## 3. V5 → V6 Differences

### 3.1 Removed Components
- Uniswap V3-only swap terminal (`JBSwapTerminal`) — replaced by `JBRouterTerminal`
- Manual pool configuration — replaced by automatic pool discovery
- WETH wrapping/unwrapping in buyback — V4 handles native ETH natively

### 3.2 Compiler & Tooling
| Aspect | v5 | v6 |
|--------|----|----|
| Solidity | `0.8.23` | `^0.8.28` |
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

## 5. Integration Notes

`deploy-all-v6` is a deployment orchestrator, so the most important migration output is not runtime ABI surface but artifact availability and naming:
- canonical deployments now include router-terminal, buyback-hook, LP-split, suckers, omnichain deployer, revnet stack, Banny, and Defifa in one ordered rollout;
- consumers of deployment artifacts should expect Defifa addresses to exist in canonical v6 rollouts;
- there are no repo-specific runtime events or custom errors to index here beyond what the deployed component repos expose.

For integrators that consume deployment manifests rather than source code, the main migration task is verifying that your artifact readers understand the expanded phase set and the additional deployed addresses.

## 6. Audit Fixes (2026-03-26)

### H-3: Resume.s.sol phases 08-10 implemented
- `_resumeCpnRevnet()` now fully configures the CPN revnet (project 2) with all stage configs, 721 hook, croptop allowed posts, and sucker deployment -- mirrors `Deploy.s.sol._deployCpnRevnet()`.
- `_resumeNanaRevnet()` now fully configures the NANA revnet (project 1) with stage config and sucker deployment -- mirrors `Deploy.s.sol._deployNanaRevnet()`.
- `_resumeBanny()` now fully deploys the Banny resolver, builds 721 tiers, and creates the $BAN revnet (project 4) -- mirrors `Deploy.s.sol._deployBanny()`.
- `_resumeDefifa()` added as Phase 10: deploys `DefifaHook`, `DefifaTokenUriResolver`, `DefifaGovernor`, and `DefifaDeployer` with CREATE2 idempotency checks -- mirrors `Deploy.s.sol._deployDefifa()`.
- All resume functions preserve idempotency: already-deployed contracts are detected via `code.length` at the deterministic CREATE2 address and skipped.

### M-5: Verify.s.sol chain-conditional project count
- `_verifyProjectIds()` now checks `buybackRegistry` address to determine if the Uniswap stack was deployed.
- On chains without the Uniswap stack (e.g. Optimism Sepolia), the project count threshold is lowered to 2 and project 3 (REV) and 4 (BAN) checks are skipped.
- `_verifyDirectoryWiring()` iterates only over deployed projects (2 on non-Uniswap chains, 4 on full chains).

## 7. Enable Revnets on Chains Without Uniswap V4

### Buyback registry deployment split from hook deployment
- `_deployBuybackRegistry()` extracted from `_deployBuybackHook()` and called unconditionally (outside the `_shouldDeployUniswapStack()` gate).
- `_deployBuybackHook()` now only deploys the `JBBuybackHook` and sets it as the default — still gated behind `_shouldDeployUniswapStack()`.
- Revnet deploy functions (`_deployRevnet`, `_deployCpnRevnet`, `_deployNanaRevnet`, `_deployBanny`) no longer early-return when `_buybackRegistry` is set — they deploy on all chains.
- Terminal configs conditionally include the router terminal only when `_routerTerminalRegistry` is deployed. On chains without Uniswap V4, revnets deploy with only the primary terminal.

## 8. Not Yet Deployed

- `JBOwnable` (v6 exists but is not included in the canonical deploy phases)
