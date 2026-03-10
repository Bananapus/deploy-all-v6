# N E M E S I S — Raw Findings (Pre-Verification)

## Scope

- **Language:** Solidity 0.8.26
- **Files analyzed:** `script/Deploy.s.sol` (1572 lines) — sole file in scope (`src/` is empty)
- **Type:** Deployment orchestrator for Juicebox V6 ecosystem
- **Framework:** Foundry + Sphinx (deterministic multi-chain deployment)

## Phase 0 — Attacker's Hit List

### Attack Goals (Q0.1)
1. Deploy with wrong constructor arguments → protocol misconfiguration → fund loss
2. Wrong chain-specific addresses (WETH, Uniswap, Chainlink) → broken pricing → value extraction
3. Wrong permissions/ownership → unauthorized control → fund theft
4. Wrong sucker (bridge) config → cross-chain fund loss
5. Deployment ordering bugs → uninitialized dependencies → broken state

### Novel Code (Q0.2)
- Entire deployment script is custom
- Configuration parameters (auto-issuance amounts, stage configs)
- Chain-specific address lookup tables (8 chains × multiple addresses)
- Multi-chain sucker deployment with CCIP + native bridges
- Revnet stage configuration (REV, NANA, BAN)

### Value Stores (Q0.3)
- JBMultiTerminal — holds all project funds
- JBController — manages project rulesets
- JBPrices — affects all pricing/valuations
- REVLoans — lending protocol
- JBSuckerRegistry — cross-chain bridging authorization

### Complex Paths (Q0.4)
- Multi-chain deployment across 8 chains
- Sucker deployer → registry → project sucker configuration chain
- Revnet: project creation → approval → deployer config → sucker setup
- Price feed: Chainlink address → JBPrices → JBTerminalStore → JBMultiTerminal

## Phase 1 — Function-State Matrix

| Function | Creates | Configures | Dependencies |
|----------|---------|------------|--------------|
| `_deployCore()` | 12 core contracts | N/A | None |
| `_deployAddressRegistry()` | JBAddressRegistry | N/A | None |
| `_deploy721Hook()` | 4 contracts | N/A | _directory, _permissions, _rulesets, _addressRegistry |
| `_deployBuybackHook()` | 2 contracts | setDefaultHook | _directory, _permissions, _prices, _projects, _tokens |
| `_deployRouterTerminal()` | 2 contracts | setDefaultTerminal | _directory, _permissions, _projects, _tokens |
| `_deploySuckers()` | Registry + deployers + singletons | allowSuckerDeployers | _directory, _permissions, _tokens |
| `_deployOmnichainDeployer()` | JBOmnichainDeployer | N/A | _suckerRegistry, _hookDeployer, _permissions, _projects |
| `_deployPeriphery()` | Controller + feeds + deadlines | addPriceFeedFor ×4, setIsAllowedToSetFirstController | _omnichainDeployer (for controller) |
| `_deployCroptop()` | Project 2 + 3 contracts | N/A | _directory, _permissions, _hookDeployer, _suckerRegistry |
| `_deployRevnet()` | Project 3 + REVLoans + REVDeployer | approve + deployFor | _controller, _suckerRegistry, _hookDeployer, _ctPublisher |
| `_deployCpnRevnet()` | Nothing | approve only (TODO) | _revDeployer, _cpnProjectId |
| `_deployNanaRevnet()` | Nothing | approve + deployFor | _revDeployer |
| `_deployBanny()` | Resolver + new project | deployWith721sFor | _revDeployer |

## Phase 2 — Feynman Interrogation Findings (Raw)

### RAW-001: Dangling ERC-721 Approval for CPN Project (MEDIUM hypothesis)
**Lines:** 1225
**Question:** Q4.1 — What does `_deployCpnRevnet()` assume about future configuration?
**Observation:** `_projects.approve(address(_revDeployer), _cpnProjectId)` grants approval without subsequent `deployFor()` call.
**Hypothesis:** Anyone could call `_revDeployer.deployFor(cpnProjectId, ...)` with arbitrary config.
→ NEEDS VERIFICATION of REVDeployer access control.

### RAW-002: Incomplete CPN Revnet (LOW hypothesis)
**Lines:** 1222-1234
**Question:** Q1.2 — What happens if the commented code stays commented?
**Observation:** Project 2 (CPN) exists but has no terminals, rulesets, or sucker config.

### RAW-003: Project ID 1 Assumption (MEDIUM hypothesis)
**Lines:** 1241
**Question:** Q4.3 — What does `feeProjectId = 1` assume about current state?
**Observation:** Hardcodes project ID 1, assuming JBProjects constructor auto-creates it.
→ NEEDS VERIFICATION of JBProjects constructor.

### RAW-004: Shared Chainlink Feed Address Across Chains (LOW hypothesis)
**Lines:** 992, 1038
**Question:** Q4.2 — What does this function assume about external data?
**Observation:** Address `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165` used for both Base Sepolia USDC/USD and Arbitrum Sepolia ETH/USD.
→ NEEDS VERIFICATION against Chainlink docs.

### RAW-005: Missing Salt for USDC Price Feed Deployments (LOW hypothesis)
**Lines:** 1006, 1011, 1024, 1037, 1050
**Question:** Q3.3 — If ETH/USD feeds use salt, why don't USDC/USD feeds?
**Observation:** ETH/USD feeds use `{salt: USD_NATIVE_FEED_SALT}` for deterministic addresses; USDC/USD feeds don't.

### RAW-006: L2 Sucker Configs Only Use Native Bridge (INFO hypothesis)
**Lines:** 1559-1567
**Question:** Q3.1 — If L1 has 3 sucker deployers, why does L2 only have 1?
**Observation:** `_buildSuckerConfig()` on L2 only includes native bridge; CCIP deployers pre-approved but not used in revnet configs.

### RAW-007: Missing Inverse/Multi-hop Price Feeds (LOW hypothesis)
**Lines:** 891-907
**Question:** Q4.2 — What does downstream code assume about price feed availability?
**Observation:** Only USD→NATIVE_TOKEN, USD→ETH, ETH→NATIVE_TOKEN, USD→USDC registered. No inverse or cross-pair.
→ NEEDS VERIFICATION of JBPrices inverse support.

### RAW-008: BAN Stage 2 splitPercent Drops to 0 (INFO hypothesis)
**Lines:** 1399-1409
**Question:** Q3.2 — BAN stages 0 and 1 use splitPercent 3800; stage 2 uses 0. Intentional?
**Observation:** Final stage removes split operator share. Design choice or config error?

## Phase 3 — State Cross-Check

### Mutation Matrix

This is a deployment script — state is one-shot, not runtime. The "coupled state" concept maps to:
- Constructor args must match dependencies
- Configuration calls must reference correct deployed addresses
- Project IDs must be deterministic

| State Variable | Set In | Used In | Verified |
|----------------|--------|---------|----------|
| `_controller` | `_deployPeriphery()` | `_deployRevnet()` | ✓ ordering correct |
| `_omnichainDeployer` | `_deployOmnichainDeployer()` | `_deployPeriphery()` (controller constructor) | ✓ ordering correct |
| `_hookDeployer` | `_deploy721Hook()` | `_deployOmnichainDeployer()`, `_deployCroptop()`, `_deployRevnet()` | ✓ ordering correct |
| `_suckerRegistry` | `_deploySuckers()` | `_deployOmnichainDeployer()`, `_deployCroptop()`, `_deployRevnet()` | ✓ ordering correct |
| `_ctPublisher` | `_deployCroptop()` | `_deployRevnet()` | ✓ ordering correct |
| `_buybackRegistry` | `_deployBuybackHook()` | `_deployRevnet()` | ✓ ordering correct |
| `_revDeployer` | `_deployRevnet()` | `_deployCpnRevnet()`, `_deployNanaRevnet()`, `_deployBanny()` | ✓ ordering correct |
| `_cpnProjectId` | `_deployCroptop()` | `_deployCpnRevnet()` | ✓ |
| `_revProjectId` | `_deployRevnet()` | N/A (used within deployRevnet) | ✓ |
| `_weth` | `_setupChainAddresses()` | `_deployBuybackHook()`, `_deployRouterTerminal()` | ✓ |
| `_v3Factory` | `_setupChainAddresses()` | `_deployRouterTerminal()` | ✓ |
| `_poolManager` | `_setupChainAddresses()` | `_deployBuybackHook()`, `_deployRouterTerminal()` | ✓ |
| `_optimismSuckerDeployer` | `_deploySuckersOptimism()` | `_buildSuckerConfig()` | ✓ per-chain |
| `_baseSuckerDeployer` | `_deploySuckersBase()` | `_buildSuckerConfig()` | ✓ per-chain |
| `_arbitrumSuckerDeployer` | `_deploySuckersArbitrum()` | `_buildSuckerConfig()` | ✓ per-chain |

All deployment ordering dependencies are satisfied. No variable is used before being set.

## Parallel Path Comparison

| Operation | ETH/USD Feed | USDC/USD Feed |
|-----------|-------------|---------------|
| Uses salt | ✓ `USD_NATIVE_FEED_SALT` | ✗ no salt |
| L2 sequencer check | ✓ (mainnet L2s) | ✓ (mainnet L2s) |
| Testnet fallback | ✓ plain feed | ✓ plain feed |
| Staleness threshold | 3600s | 86,400s |
| Registered directions | 3 (USD→NATIVE, USD→ETH, ETH→NATIVE) | 1 (USD→USDC) |

### Sucker Deployer Parallel Path

| Chain | Native Bridge Deployer | CCIP Deployers | Pre-approved Count |
|-------|----------------------|----------------|-------------------|
| Ethereum L1 | OP + Base + Arb | OP + Base + Arb | 6 |
| Optimism | OP | ETH + Arb + Base | 4 |
| Base | Base | ETH + OP + Arb | 4 |
| Arbitrum | Arb | ETH + OP + Base | 4 |

All chains have consistent coverage. ✓
