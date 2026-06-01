# Architecture

## Purpose

`deploy-all-v6` is the canonical deployment orchestrator for the V6 ecosystem. It does not add runtime protocol behavior. It owns sequencing, chain-specific wiring, canonical address selection, verification follow-up, and recovery from partial deployment.

## System Overview

The V6 stack is intentionally multi-repo and cross-chain. `Deploy.s.sol` performs the main phased rollout. If a rollout is interrupted, the recovery path is to bump the deployment nonce in `Deploy.s.sol` and redeploy from fresh salts into a clean, non-colliding address namespace. `Verify.s.sol` checks that the deployed stack matches the expected shape.

## Core Invariants

- Deployment order is a dependency graph, not a presentation choice.
- Canonical addresses must stay aligned with the expectations baked into sibling repos and fork tests.
- Recovery is a property of the main deployment script: bumping the deployment nonce must yield a fully fresh, non-colliding address namespace for every contract.
- Verification is part of the deployment contract, not an optional afterthought.
- Testnet support is intentionally narrower than mainnet support for some phases; that asymmetry should stay explicit.

## Modules

| Module | Responsibility | Notes |
| --- | --- | --- |
| `script/Deploy.s.sol` | Main phased rollout via Sphinx | Happy-path deployment; carries the deployment nonce that recovery bumps for a fresh-salt redeploy |
| `script/Verify.s.sol` | Deployment verification follow-up | Sanity and consistency checks; the verification step after any deploy or redeploy |

## Trust Boundaries

- Runtime semantics live in sibling repos.
- This repo is trusted for deployment order, parameter selection, and chain-specific dependency wiring.
- Deterministic deployment assumptions depend on downstream salts, constructor args, and registry expectations staying synchronized.

## Critical Flows

### Full Deployment

```text
operator
  -> runs Deploy.s.sol
  -> repo deploys the core stack first
  -> deploys registries, hooks, cross-chain infrastructure, and product repos in dependency order
  -> records canonical addresses for later phases
```

### Recovery from partial deployment

```text
operator
  -> bumps the deployment nonce in Deploy.s.sol after partial success
  -> every CREATE2/CREATE3 salt re-namespaces into a fresh, non-colliding address space
  -> re-runs Deploy.s.sol, which deploys the full stack from scratch at the new addresses
  -> runs Verify.s.sol to confirm the deployed shape and ownership
```

## Accounting Model

This repo does not own protocol accounting. Its economic risk is indirect: bad deployment order or wrong constructor args can instantiate the wrong accounting system downstream.

## Security Model

- CREATE2 makes naive replay unsafe after partial success: re-running the same script with the same salts collides with already-deployed contracts. Recovery bumps the deployment nonce so every salt re-namespaces into a fresh address space.
- Cross-repo drift is the main hazard: constructors, salts, and deployment assumptions can move in sibling repos before this repo is updated.
- Verification drift is also dangerous. A script that deploys correctly but verifies the wrong invariants gives false confidence.

## Safe Change Guide

- If a sibling repo changes a constructor, salt, or required dependency, update `Deploy.s.sol` accordingly.
- If a deployment assumption changes, update `Verify.s.sol` in the same change set or document why the old check still holds.
- Validate deployment changes against the chain matrix they affect.
- Prefer explicit wiring over inferred discovery when determinism matters.

## Canonical Checks

- fresh-salt redeploy continuity (same addresses on a clean re-run):
  `test/fork/DeployResumeRehearsalFork.t.sol`
- post-deploy verification assumptions:
  `test/fork/DeployScriptVerification.t.sol`
- full-stack rollout coherence:
  `test/fork/FullStackFork.t.sol`

## Source Map

- `script/Deploy.s.sol`
- `script/Verify.s.sol`
- `test/fork/DeployResumeRehearsalFork.t.sol`
- `test/fork/DeployScriptVerification.t.sol`
- `test/fork/FullStackFork.t.sol`
