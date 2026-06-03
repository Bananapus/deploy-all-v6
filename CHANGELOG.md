# Changelog

## 0.0.59 - Add regression fork tests; bump @ballkidz/defifa to ^0.0.56

- Added fork tests covering: launching a Defifa game with splits, REVLoans partial repayment after the collateral appreciates, Chainlink price-feed staleness-threshold boundaries, and protocol-fee handling when a USDC revnet's fee project has no resolvable USDC route.
- Bumped `@ballkidz/defifa` to `^0.0.56`.

## 0.0.57 - Remove fee attribution wiring from deploy-all

Change:

- Remove deploy-all references to protocol fee-attribution arguments now that the ecosystem packages no longer expose them.
- Delete the obsolete cross-chain fee-attribution fork scenario; the protocol no longer rewards volume attribution.
- Keep Defifa on the shared `JB721TiersHookStore` and verify that wiring in post-deploy checks.
- Update the post-deploy verifier/rehearsal docs so REV deployer and owner addresses are wired through the correct env vars.

Dependency bumps:

- `@ballkidz/defifa`: `^0.0.53 -> ^0.0.54`.
- `@bananapus/721-hook-v6`: `^0.0.67 -> ^0.0.68`.
- `@bananapus/buyback-hook-v6`: `^0.0.67 -> ^0.0.68`.
- `@bananapus/router-terminal-v6`: `^0.0.61 -> ^0.0.63`.
- `@bananapus/suckers-v6`: `^0.0.69 -> ^0.0.71`.
- `@bananapus/univ4-lp-split-hook-v6`: `^0.0.59 -> ^0.0.60`.
- `@bananapus/univ4-router-v6`: `^0.0.50 -> ^0.0.52`.
- `@croptop/core-v6`: `^0.0.65 -> ^0.0.66`.
- `@rev-net/core-v6`: `^0.0.87 -> ^0.0.88`.

## 0.0.56 - Adopt the per-context cross-chain surplus ecosystem

Change:

- Stop deploying and registering the ETH<->USDC `JBTriangularPriceFeed`, and drop it from the artifact build spec. The per-context cross-chain surplus design in `@bananapus/suckers-v6` values matched-currency peer contexts at par (no oracle) and routes genuinely cross-asset surplus through swap-suckers, so the triangulated default feed is no longer consulted for USDC revnets. The contract itself is removed in `@bananapus/core-v6`.
- Bump the ecosystem to the per-context release: `@bananapus/core-v6` `^0.0.79 -> ^0.0.80`, `@bananapus/suckers-v6` `^0.0.68 -> ^0.0.69`, `@bananapus/omnichain-deployers-v6` `^0.0.56 -> ^0.0.57`, `@rev-net/core-v6` `^0.0.86 -> ^0.0.87`, `@bananapus/univ4-lp-split-hook-v6` `^0.0.57 -> ^0.0.59`, and `@ballkidz/defifa` `^0.0.51 -> ^0.0.53`.
- Update the suckers/registry construction in the deploy script for the new constructor signatures: `JBSuckerRegistry` now takes `IJBPrices prices` (added as the third argument), and the sucker singletons (`JBOptimismSucker`, `JBBaseSucker`, `JBArbitrumSucker`, `JBCCIPSucker`) no longer take `prices` (removed).

Tests:

- Remove the USDC/USD cross-chain surplus fork test. It was premised on the superseded model that stamped a single ETH-denominated currency onto the remote snapshot and triangulated it into USDC; the per-context redesign carries each accounting context in its own currency instead, so that scenario no longer exists. The new behavior is covered by the suckers package's own tests.
- Update the fork and invariant tests to the new suckers/registry constructor signatures (registry gains `prices`, sucker singletons drop it).

## 0.0.55 - Build the triangular price-feed artifact

Fix:

- Add `JBTriangularPriceFeed` to the artifact build. The deploy registers a triangulated ETH<->USDC price feed (the derived feed that lets USDC-accepting projects price ETH against USDC through the shared USD pivot) and loads its precompiled creation code from `artifacts/JBTriangularPriceFeed.json`. That artifact was not produced, so the deploy reverted at the price-feed phase on every chain. The contract is now in the build spec.

Tests:

- Guard that every precompiled artifact the deploy loads is produced by the artifact build, derived directly from the deploy source so the list cannot drift from the code. The fork tests rebuild the protocol with direct constructor calls and never exercise the artifact-loading path, so a missing artifact would otherwise surface only at deploy time.
- Add a cross-chain surplus fork test for USDC/USD revnets. It funds a revnet with a local USDC surplus plus a remote, ETH-denominated surplus snapshot, then values both through the real `JBTriangularPriceFeed`: with the feed registered the remote leg converts to its USDC value and the borrowable/cash-out amount reflects both legs; without it the remote surplus silently resolves to zero while the remote supply still sits in the denominator, so the valuation under-prices (rather than reverting). The test proves the triangular feed is load-bearing for cross-chain USDC accounting.

## 0.0.54 - Bump sibling packages to the latest fixes and document conventions

Dependency bumps:

- `@bananapus/721-hook-v6`: `^0.0.65 -> ^0.0.67`.
- `@bananapus/address-registry-v6`: `^0.0.31 -> ^0.0.33`.
- `@bananapus/buyback-hook-v6`: `^0.0.65 -> ^0.0.67`.
- `@bananapus/core-v6`: `^0.0.77 -> ^0.0.79`.
- `@bananapus/distributor-v6`: `^0.0.35 -> ^0.0.37`.
- `@bananapus/omnichain-deployers-v6`: `^0.0.55 -> ^0.0.56`.
- `@bananapus/ownable-v6`: `^0.0.34 -> ^0.0.36`.
- `@bananapus/permission-ids-v6`: `^0.0.28 -> ^0.0.29`.
- `@bananapus/project-handles-v6`: `^0.0.23 -> ^0.0.25`.
- `@bananapus/project-payer-v6`: `^0.0.20 -> ^0.0.21`.
- `@bananapus/router-terminal-v6`: `^0.0.59 -> ^0.0.61`.
- `@bananapus/suckers-v6`: `^0.0.66 -> ^0.0.68`.
- `@bananapus/univ4-lp-split-hook-v6`: `^0.0.56 -> ^0.0.57`.
- `@bananapus/univ4-router-v6`: `^0.0.49 -> ^0.0.50`.
- `@bannynet/core-v6`: `^0.0.41 -> ^0.0.43`.
- `@croptop/core-v6`: `^0.0.64 -> ^0.0.65`.
- `@rev-net/core-v6`: `^0.0.83 -> ^0.0.86`.

Adaptations and tests:

- Adapt to the two-value borrowable-amount return: `REVLoans.borrowableAmountFrom(...)` now returns both the immediately executable amount and the total capacity. Every call site now takes the first (executable) value, which equals the previous single return.
- Add a fee-routing fork test (`test/fork/USDCFeeRoutingFork.t.sol`). It proves a USDC cash-out fee from a USDC revnet now reaches the fee project (NANA, project 1): the directory resolves the router-terminal registry as the fee project's USDC terminal (instead of resolving nothing), and the fee is credited to the fee project's balance rather than being forgiven back to the paying revnet. Runs against an Ethereum mainnet fork.

Documentation:

- Document the NatSpec, comment, and lint conventions in `STYLE_GUIDE.md`: every member carries complete NatSpec, every non-trivial statement carries a plain-English comment explaining why it exists, comments and NatSpec describe the current behavior as the only behavior, and the build, lint, and tests stay clean with zero notes.

Continuous integration:

- Gate the full fork and integration suite in CI: a `forge-test` job builds the deploy artifacts and runs `forge test`, backed by the Ethereum, Optimism, Base, and Arbitrum mainnet RPCs so the cross-chain fork tests run rather than skip.
- Align the price-verifier fork tests with the current behavior so the suite is green: the price verifier reaches its specific oracle-exactness checks once a valid ETH/USDC triangular feed is present.

## 0.0.53 - Correct the documented recovery path

Documentation fix:

- The docs described an interrupted-deployment recovery script that does not exist in this repo. Every reference to it has been removed.
- The documented recovery path is now the one this repo actually supports: bump the deployment nonce in `script/Deploy.s.sol` so every CREATE2/CREATE3 salt re-namespaces into a fresh, non-colliding address space, redeploy the full stack from those fresh salts, then run `script/Verify.s.sol` to validate the deployed shape and ownership.
- Updated `ARCHITECTURE.md`, `RISKS.md`, `USER_JOURNEYS.md`, `AUDIT_INSTRUCTIONS.md`, `DEPLOY.md`, `ADMINISTRATION.md`, `README.md`, `SKILLS.md`, `references/runtime.md`, `references/operations.md`, and this changelog so the recovery story is coherent throughout.

## 0.0.52 - Register USDC revnet price feed

Deployment updates:

- Registers the ETH/USDC triangular price feed for USDC revnets.
- `@bananapus/ownable-v6`: add explicit `^0.0.34` dependency so root package-name resolution uses the latest owner policy.

## 0.0.51 - Bump v6 deployment cohort

Dependency bumps:

- `@ballkidz/defifa`: `^0.0.50 -> ^0.0.51`.
- `@bananapus/721-hook-v6`: `^0.0.63 -> ^0.0.65`.
- `@bananapus/core-v6`: `^0.0.76 -> ^0.0.77`.
- `@bananapus/router-terminal-v6`: `^0.0.58 -> ^0.0.59`.
- `@bananapus/suckers-v6`: `^0.0.65 -> ^0.0.66`.
- `@bananapus/univ4-lp-split-hook-v6`: `^0.0.54 -> ^0.0.56`.
- `@bananapus/univ4-router-v6`: `^0.0.48 -> ^0.0.49`.
- `@croptop/core-v6`: `^0.0.61 -> ^0.0.64`.

Deployment updates:

- Wired `CTPublisher` deployments to the canonical Permit2 singleton.
- Extended deployment verification to pin `CTPublisher.PERMIT2` alongside the other Permit2-enabled contracts.

## 0.0.33 — Bump v6 deps to nana-core-v6 0.0.53 cohort

`nana-core-v6@0.0.50+` extracted two new `external`-function libraries from `JBMultiTerminal` to keep the terminal under EIP-170 after the cross-project cashout entrypoints landed:

- **`JBHeldFeesLib`** (DELEGATECALL'd by `JBMultiTerminal` for held-fee bookkeeping — `_returnHeldFees`, `_processHeldFees`, `_holdFee`).
- **`JBCashOutHookSpecsLib`** (DELEGATECALL'd by `JBMultiTerminal.fulfill` for cash-out hook specification execution).

Both must be deployed BEFORE `JBMultiTerminal` (a DELEGATECALL into a not-yet-deployed library is a silent revert) and their deterministic CREATE2 addresses must be linked into `JBMultiTerminal`'s bytecode at artifact-build time.

`script/Deploy.s.sol`:
- Added `HELD_FEES_LIB_SALT` and `CASH_OUT_HOOK_SPECS_LIB_SALT` constants alongside the existing `PAYOUT_SPLIT_GROUP_LIB_SALT`.
- Added both libraries to `_deployLibraries()` (Phase 00, before `_deployCore`).
- Added both to the deployments artifact serializer.

`script/build-artifacts.sh`:
- Added both library contracts to the `CONTRACTS` list (with `src/libraries/...` source paths) so their artifacts get copied into `artifacts/`.
- Added both to `LIB_SALTS` so the deferred-linking pass resolves each library's placeholder hash to the deterministic CREATE2 address and substitutes it in dependents' bytecode. After this PR, `JBMultiTerminal.json` carries 3 placeholder linkings (was 1).

Dependency bumps (cohort to nana-core-v6 0.0.53 + companions):

- `@bananapus/core-v6`: `^0.0.49 → ^0.0.53` ([PR #145](https://github.com/Bananapus/nana-core-v6/pull/145)).
- `@bananapus/721-hook-v6`: `^0.0.49 → ^0.0.50`.
- `@bananapus/buyback-hook-v6`: `^0.0.45 → ^0.0.46`.
- `@bananapus/distributor-v6`: `^0.0.15 → ^0.0.16`.
- `@bananapus/omnichain-deployers-v6`: `^0.0.42 → ^0.0.43`.
- `@bananapus/project-handles-v6`: `^0.0.11 → ^0.0.12`.
- `@bananapus/project-payer-v6`: `^0.0.11 → ^0.0.12`.
- `@bananapus/router-terminal-v6`: stayed at `^0.0.43` (no router PR yet — semver picks up 0.0.53 transitively).
- `@bananapus/suckers-v6`: `^0.0.43 → ^0.0.46`.
- `@bananapus/univ4-lp-split-hook-v6`: `^0.0.39 → ^0.0.40`.
- `@bananapus/univ4-router-v6`: `^0.0.30 → ^0.0.31`.
- `@rev-net/core-v6`: `^0.0.55 → ^0.0.56`.
- `@ballkidz/defifa`: `^0.0.34 → ^0.0.35`.

## Scope

`deploy-all-v6` is a deployment-orchestration repo, not a runtime protocol package. There is no one-for-one deployed v5 repo to diff against in the same way as the contract repos.

## Current v6 surface

- `script/Deploy.s.sol`
- `script/Verify.s.sol`
- fork-heavy integration coverage under `test/fork/`

## Summary

- This repo exists to deploy and rehearse the v6 stack as a coordinated system rather than as isolated repos.
- The current repo contents clearly assume the router-terminal era, the v6 buyback hook, v6 suckers, and the v6 revnet/omnichain stack.
- The test suite is oriented around cross-repo integration and recovery scenarios: fresh-salt redeploys, multi-chain deployment, price-feed failures, routing, sucker paths, and other system-level compositions.

## Migration notes

- Use this changelog as deployment-context documentation, not as a canonical ABI diff.
- When this repo changes, the important question is usually "which v6 components are orchestrated together now?" rather than "which callable surface changed here?"
