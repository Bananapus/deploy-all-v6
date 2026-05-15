# Changelog

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
- `script/Resume.s.sol`
- `script/Verify.s.sol`
- fork-heavy integration coverage under `test/fork/`

## Summary

- This repo exists to deploy and rehearse the v6 stack as a coordinated system rather than as isolated repos.
- The current repo contents clearly assume the router-terminal era, the v6 buyback hook, v6 suckers, and the v6 revnet/omnichain stack.
- The test suite is oriented around cross-repo integration and recovery scenarios: resume flows, multi-chain deployment, price-feed failures, routing, sucker paths, and other system-level compositions.

## Migration notes

- Use this changelog as deployment-context documentation, not as a canonical ABI diff.
- When this repo changes, the important question is usually "which v6 components are orchestrated together now?" rather than "which callable surface changed here?"
