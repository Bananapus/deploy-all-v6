# V5 to V6 Changelog

## Scope

This is a V5-to-V6 migration changelog, not a package release log or commit history. `deploy-all-v6` is a V6 deployment and artifact package; it has no direct deployed V5 contract-package counterpart. The closest V5 tree context is the deployed V5 ecosystem in `../../v5/evm`.

## Current V6 Surface

- Deployment scripts and configuration for the canonical V6 contract cohort.
- Published artifacts for the V6 contracts deployed together.
- Deployment docs and administration notes for V6 operations.

## Summary

- The deployment cohort now includes the router-terminal stack rather than the V5 swap-terminal stack.
- The cohort includes V6-only packages such as project handles, project payer, Uniswap V4 router, and Uniswap V4 LP split hook.
- Canonical artifacts include V6 ABIs for core, 721 hook, buyback hook, router terminal, suckers, revnet, Croptop, Banny, Defifa, and the V6-only packages.
- Deployment wiring assumes the V6 permission map and V6 sibling package addresses. V5 hardcoded permission IDs or swap-terminal addresses should not be reused.

## ABI, Event, and Error Changes

- This package does not define a runtime contract ABI of its own.
- Its migration impact is the artifact set it publishes. Consumers should treat its artifacts as the source of truth for current V6 ABIs, events, and errors.
- The highest-risk artifact changes are:
  - `JBSwapTerminal` artifacts are replaced by `JBRouterTerminal` and `JBRouterTerminalRegistry`.
  - `REVDeployer` artifacts now pair with `REVOwner`.
  - V6-only artifacts such as `JBProjectHandles`, `JBProjectPayer`, `JBUniswapV4Hook`, and `JBUniswapV4LPSplitHook` have no V5 ABI.

## Machine-Checked ABI Coverage

Generated from Foundry artifacts, filtered to this repo's own runtime source roots and excluding tests, scripts, and dependencies.

- Own-source runtime ABI artifacts compared: V6 `0`, V5 `0`.
- This repo has no standalone runtime ABI in the audited source roots; migration impact comes from scripts, deployment artifacts, and sibling package ABIs.

## Migration Notes

- Rebuild deployments from the V6 deployment scripts and artifacts instead of adapting a V5 deployment manifest by hand.
- Update address books, artifact consumers, and docs to use router-terminal names and V6-only package addresses.
- Treat this package as an ecosystem deployment guide, not as a commit-by-commit changelog.
