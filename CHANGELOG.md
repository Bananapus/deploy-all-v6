# Changelog

## 0.0.54 - Bump sibling packages to the latest fixes

Dependency bumps:

- `@rev-net/core-v6`: `^0.0.83 -> ^0.0.84`.
- `@bananapus/core-v6`: `^0.0.77 -> ^0.0.78`.
- `@bananapus/router-terminal-v6`: `^0.0.59 -> ^0.0.60`.
- `@bananapus/buyback-hook-v6`: `^0.0.65 -> ^0.0.66`.
- `@bananapus/suckers-v6`: `^0.0.66 -> ^0.0.67`.
- `@bananapus/distributor-v6`: `^0.0.35 -> ^0.0.36`.
- `@bananapus/referral-split-hook-v6`: `^0.0.9 -> ^0.0.10`.
- `@bananapus/project-handles-v6`: `^0.0.23 -> ^0.0.24`.
- `@bananapus/address-registry-v6`: `^0.0.31 -> ^0.0.32`.
- `@bannynet/core-v6`: `^0.0.41 -> ^0.0.42`.

Adaptations and tests:

- Adapt to the two-value borrowable-amount return: `REVLoans.borrowableAmountFrom(...)` now returns both the immediately executable amount and the total capacity. Every call site now takes the first (executable) value, which equals the previous single return.
- Add a fee-routing fork test (`test/fork/USDCFeeRoutingFork.t.sol`). It proves a USDC cash-out fee from a USDC revnet now reaches the fee project (NANA, project 1): the directory resolves the router-terminal registry as the fee project's USDC terminal (instead of resolving nothing), and the fee is credited to the fee project's balance rather than being forgiven back to the paying revnet. Runs against the Ethereum mainnet fork in CI.

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
- `@bananapus/referral-split-hook-v6`: `^0.0.8 -> ^0.0.9`.
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
