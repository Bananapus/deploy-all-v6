# N E M E S I S — Verified Findings

## Scope
- **Language:** Solidity 0.8.26
- **Files analyzed:** `script/Deploy.s.sol` (1572 lines)
- **src/ files:** None (this repo is a deployment orchestrator only; all protocol contracts are imported from sibling repos via `file:` dependencies)
- **Functions analyzed:** 18 (15 internal deploy functions + `run()` + `deploy()` + `configureSphinx()`)
- **Lines interrogated:** 1572
- **Coupled state pairs mapped:** 16 (deployment dependency pairs)
- **Nemesis loop iterations:** 2 (converged — no new findings after Pass 2)

## Verification Summary

| ID | Raw Finding | Original Severity | Verdict | Final Severity |
|----|------------|-------------------|---------|----------------|
| RAW-001 | Dangling ERC-721 approval for CPN project | MEDIUM | **FALSE POSITIVE** | — |
| RAW-002 | Incomplete CPN revnet deployment | LOW | **TRUE POSITIVE** | LOW |
| RAW-003 | Project ID 1 hardcoded assumption | MEDIUM | **FALSE POSITIVE** | — |
| RAW-004 | Shared Chainlink feed address across chains | LOW | **FALSE POSITIVE** | — |
| RAW-005 | Missing salt for USDC price feed deployments | LOW | **TRUE POSITIVE** | LOW |
| RAW-006 | L2 sucker configs only use native bridge | INFO | **TRUE POSITIVE** | INFO |
| RAW-007 | Missing inverse price feeds | LOW | **FALSE POSITIVE** | — |
| RAW-008 | BAN stage 2 splitPercent drops to 0 | INFO | **TRUE POSITIVE** | INFO |

**Final: 0 CRITICAL | 0 HIGH | 0 MEDIUM | 2 LOW | 2 INFORMATIONAL**

---

## Nemesis Map (Phase 1 Cross-Reference)

All 16 deployment dependency pairs verified. Every contract is deployed before it is referenced. The deployment follows correct topological ordering:

```
Phase 01: Core (12 contracts, no deps)
Phase 02: Address Registry (no deps)
Phase 03a: 721 Hook (deps: core)
Phase 03b: Buyback Hook (deps: core)
Phase 03c: Router Terminal (deps: core)
Phase 03d: Suckers (deps: core)
Phase 04: Omnichain Deployer (deps: suckers, 721 hook, core)
Phase 05: Periphery/Controller (deps: omnichain deployer, core)  ← intentional ordering
Phase 06: Croptop (deps: core, 721 hook, sucker registry)
Phase 07: Revnet (deps: controller, sucker registry, 721 hook, buyback, croptop)
Phase 08: CPN + NANA revnet config (deps: revDeployer)
Phase 09: Banny (deps: revDeployer)
```

No gaps, no circular dependencies, no use-before-set.

---

## Verified Findings (TRUE POSITIVES only)

### Finding NM-001: Incomplete CPN Revnet Deployment
**Severity:** LOW
**Source:** Feynman Pass 1 (Category 1: Purpose)
**Verification:** Code trace — confirmed

**Function:** `_deployCpnRevnet()` at `script/Deploy.s.sol:1222-1234`

**Feynman Question that exposed this:**
> Q1.2: What happens if I DELETE the commented-out `deployFor()` call entirely? What state is the system left in?

**The code:**
```solidity
function _deployCpnRevnet() internal {
    // TODO: Configure CPN (project 2) as a revnet.
    // Approve the deployer, build config, call _revDeployer.deployFor.
    _projects.approve(address(_revDeployer), _cpnProjectId);

    // Placeholder — fill in CPN revnet config.
    // _revDeployer.deployFor({
    //     revnetId: _cpnProjectId,
    //     configuration: cpnConfig,
    //     terminalConfigurations: terminalConfigs,
    //     suckerDeploymentConfiguration: suckerConfig
    // });
}
```

**Why this matters:**

After deployment, project 2 (CPN) exists but has:
- No controller set
- No rulesets launched
- No terminals configured
- No sucker deployment
- A dangling `ERC-721` approval to the REVDeployer (harmless — see False Positives)

The project is a blank shell. While not directly exploitable (the REVDeployer requires `_msgSender() == owner` to configure existing projects), shipping this creates:
1. **Confusion risk** — users or frontends may discover project 2 and attempt interaction
2. **Wasted gas** — the `_projects.approve()` call and project creation are unnecessary if CPN is not being configured
3. **Governance debt** — the safe must remember to configure this project in a follow-up transaction

**Impact:** No fund risk. Operational/UX concern only. The safe can configure CPN later by calling `_revDeployer.deployFor(_cpnProjectId, config, terminalConfigs, suckerConfig)`.

**Suggested fix:** Either implement the CPN configuration or remove the function body (skip project 2 creation and approval until CPN config is finalized):
```solidity
function _deployCpnRevnet() internal {
    // CPN not yet ready — skip entirely.
    // When ready: create project, approve deployer, call deployFor.
}
```

---

### Finding NM-002: Missing Salt for USDC Price Feed Deployments
**Severity:** LOW
**Source:** Feynman Pass 1 (Category 3: Consistency)
**Verification:** Code trace — confirmed

**Function:** `_deployUsdcFeed()` at `script/Deploy.s.sol:999-1060`

**Feynman Question that exposed this:**
> Q3.3: If `_deployEthUsdFeed()` uses `{salt: USD_NATIVE_FEED_SALT}` for deterministic addresses, why doesn't `_deployUsdcFeed()` use a salt?

**The code:**
```solidity
// ETH/USD feed — uses salt ✓
feed = new JBChainlinkV3PriceFeed{salt: USD_NATIVE_FEED_SALT}(
    AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419), 3600 seconds
);

// USDC/USD feed — no salt ✗
usdcFeed = new JBChainlinkV3PriceFeed(
    AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6), 86_400 seconds
);
```

**Why this matters:**

Within a single Sphinx deployment proposal, this is likely fine — Sphinx maintains deterministic nonces. However:

1. **Inconsistency with ETH/USD pattern** — ETH/USD feeds use explicit salts; USDC/USD feeds don't. This inconsistency could cause address unpredictability if the deployment script is modified or re-ordered.
2. **Address determinism** — Without a salt, the USDC feed addresses depend on the deployer's nonce at the time of deployment. If any deployment step is added or removed before the USDC feed deployment, the USDC feed addresses change.
3. **Cross-deployment consistency** — If this script is forked or adapted, missing salts could produce different USDC feed addresses unexpectedly.

The USDC feed addresses are only stored in `JBPrices` (via `addPriceFeedFor`), never referenced directly by address elsewhere, so this does not affect protocol correctness.

**Impact:** No fund risk. Address determinism concern for deployment reproducibility.

**Suggested fix:**
```solidity
bytes32 private constant USDC_FEED_SALT = keccak256("USDC_FEEDV6");

// Then in _deployUsdcFeed():
usdcFeed = new JBChainlinkV3PriceFeed{salt: USDC_FEED_SALT}(
    AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6), 86_400 seconds
);
```

---

## INFORMATIONAL Findings

### NM-003: L2 Revnet Sucker Configs Only Include Native Bridge
**Lines:** 1559-1567

On L2 chains, `_buildSuckerConfig()` deploys only 1 sucker deployer (the native bridge back to L1). CCIP deployers for cross-L2 routes (e.g., OP→Base, Arb→OP) are pre-approved in the `JBSuckerRegistry` but are not included in the revnet deployment configs for REV, NANA, or BAN.

This means revnets can bridge L2→L1 natively but cannot bridge L2→L2 directly. Cross-L2 bridging requires two hops through L1. This appears to be an intentional design choice (native bridges are cheaper and more established), but it limits cross-L2 interoperability for the three launch revnets.

### NM-004: BAN Stage 2 splitPercent Drops to 0
**Lines:** 1399-1409

BAN stages 0 and 1 set `splitPercent: 3800` (38%), but stage 2 sets `splitPercent: 0`. This means in the final stage (starting ~1560 days after stage 0), the split operator receives no share of incoming funds. The `splits` array still references the operator at 100%, but with `splitPercent: 0` no split is applied.

Contrast with REV, where all 3 stages maintain `splitPercent: 3800`. This appears to be an intentional economic design decision for BAN (the project eventually becomes fully community-owned), but should be confirmed with the team.

---

## False Positives Eliminated

### FP-001: Dangling ERC-721 Approval Exploitation (RAW-001)
**Original severity:** MEDIUM
**Reason for elimination:**

The REVDeployer's `deployFor()` function checks `if (_msgSender() != owner) revert REVDeployer_Unauthorized(revnetId, _msgSender())` at line 1010 of `REVDeployer.sol`. The caller must be the project NFT owner — ERC-721 approval alone is insufficient. Even with the dangling approval, only `safeAddress()` (the gnosis safe) can configure project 2. The approval is consumed when `deployFor()` internally calls `safeTransferFrom(owner, this, tokenId)` which clears the approval.

### FP-002: Project ID 1 Hardcoded Assumption (RAW-003)
**Original severity:** MEDIUM
**Reason for elimination:**

Verified the `JBProjects` constructor. When `feeProjectOwner != address(0)`, the constructor calls `createFor(feeProjectOwner)`, creating project 1. The deploy script passes `safeAddress()` as `feeProjectOwner`, confirming project 1 is auto-created during `_deployCore()`. Project ID sequence:
- Project 1: Auto-created by JBProjects constructor (fee project, owned by safe)
- Project 2: `_projects.createFor(safeAddress())` in `_deployCroptop()` (CPN)
- Project 3: `_projects.createFor(safeAddress())` in `_deployRevnet()` (REV)
- Project 4: Created by `_revDeployer.deployWith721sFor(revnetId: 0, ...)` in `_deployBanny()` (BAN)

### FP-003: Shared Chainlink Feed Address Across Chains (RAW-004)
**Original severity:** LOW
**Reason for elimination:**

Verified against official Chainlink documentation. The address `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165` is:
- **USDC/USD** on Base Sepolia (chain 84532) — correct per Chainlink docs
- **ETH/USD** on Arbitrum Sepolia (chain 421614) — correct per Chainlink docs

Different chains have independent contract deployments. Address reuse across chains is a Chainlink deployment pattern, not a bug.

### FP-004: Missing Inverse Price Feeds (RAW-007)
**Original severity:** LOW
**Reason for elimination:**

Verified the JBPrices contract. It implements automatic inverse feed lookup at lines 182-191: when a direct feed for A→B doesn't exist, it checks for B→A and returns the mathematical inverse. The deploy script's registrations are sufficient:
- USD→NATIVE_TOKEN ✓ → NATIVE_TOKEN→USD derived automatically
- USD→ETH ✓ → ETH→USD derived automatically
- ETH→NATIVE_TOKEN ✓ → NATIVE_TOKEN→ETH derived automatically
- USD→USDC ✓ → USDC→USD derived automatically

---

## Additional Verification Notes

### Chain-Specific Addresses — All Verified
- **WETH addresses:** Canonical across all 8 chains ✓
- **Uniswap V3 Factory addresses:** Correct per official Uniswap deployments ✓
- **Uniswap V4 PoolManager addresses:** Correct per official Uniswap V4 deployments ✓
- **Chainlink ETH/USD feeds:** All 8 chains verified correct ✓
- **Chainlink USDC/USD feeds:** All 8 chains verified correct ✓
- **L2 Sequencer feeds:** Optimism, Base, Arbitrum — all correct ✓
- **Bridge addresses (OP Messenger, OP Standard Bridge, Arb Inbox/Gateway):** Correct per official bridge deployments ✓

### Permit2 Address
`0x000000000022D473030F116dDEE9F6B43aC78BA3` — canonical Permit2 address across all chains ✓

### Salt Collision Analysis
All CREATE2 deployments use either unique salts or the same salt with different contract bytecodes (which produces different addresses). No collision risk identified.

### Constructor Argument Analysis
All 30+ contract deployments pass correct constructor arguments in the correct order. No type mismatches, no missing arguments, no zero-address where non-zero is required.

### uint104 Overflow Analysis
All auto-issuance values (`uint104`) are well within the maximum `uint104` range (max ≈ 2.03 × 10³¹). Largest value: `REV_MAINNET_AUTO_ISSUANCE = 1.05 × 10²⁴`. No overflow risk.

### Price Feed Staleness Thresholds
- ETH/USD: 3600 seconds (1 hour) — appropriate for volatile asset
- USDC/USD: 86,400 seconds (24 hours) — appropriate for stablecoin with slow Chainlink heartbeat
- L2 Sequencer grace period: 3600 seconds — standard practice

---

## Summary

```
Total functions analyzed: 18
Lines interrogated: 1572
Deployment dependency pairs verified: 16
Chain-specific addresses verified: 40+
Constructor argument sets verified: 30+
Salt collision checks: 20+
Nemesis loop iterations: 2 (converged)

Raw findings (pre-verification): 0 C | 0 H | 2 M | 4 L | 2 I
After verification:              4 FALSE POSITIVE | 0 DOWNGRADED
Final verified:                  0 CRITICAL | 0 HIGH | 0 MEDIUM | 2 LOW | 2 INFO

Discovery paths:
  - Feynman-only: 2 (NM-001, NM-002)
  - State-only: 0
  - Cross-feed: 0

False positives eliminated via cross-reference:
  - FP-001: REVDeployer access control verification eliminated dangling approval concern
  - FP-002: JBProjects constructor verification eliminated project ID assumption concern
  - FP-003: Chainlink docs verification eliminated address reuse concern
  - FP-004: JBPrices inverse lookup verification eliminated missing feed concern
```

This deployment script is well-structured with correct dependency ordering, verified chain-specific addresses, and proper constructor arguments. The two LOW findings are quality/consistency issues rather than security vulnerabilities. No fund risk identified.
