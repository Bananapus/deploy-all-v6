# Architecture

## Purpose

`deploy-all-v6` is the canonical deployment orchestrator for the V6 ecosystem. It does not introduce runtime protocol behavior. It owns sequencing, chain-specific wiring, canonical address selection, verification follow-up, and recovery from partial deployment.

## System Overview

The repo exists because the V6 stack is intentionally multi-repo and cross-chain. `Deploy.s.sol` performs the main phased rollout. `Resume.s.sol` is not a convenience script; it is the deterministic recovery path for partially completed deployments. `Verify.s.sol` closes the loop by checking that the deployed stack matches the expected shape.

## Core Invariants

- Deployment order is a dependency graph, not a presentation choice.
- Canonical addresses must stay aligned with the expectations embedded in sibling repos and fork tests.
- Recovery logic must remain current with main deployment logic.
- Verification is part of the deployment contract, not an optional afterthought. `Verify.s.sol` encodes assumptions that should stay synchronized with both deploy and resume paths.
- Testnet support is intentionally narrower than mainnet support for some phases; asymmetry is expected and should stay explicit.

## Modules

| Module | Responsibility | Notes |
| --- | --- | --- |
| `script/Deploy.s.sol` | Main phased rollout via Sphinx | Happy-path deployment |
| `script/Resume.s.sol` | Partial-execution recovery | Deterministic continuation path |
| `script/Verify.s.sol` | Deployment verification follow-up | Sanity and consistency checks |

## Trust Boundaries

- Runtime semantics live in sibling repos.
- This repo is trusted for deployment ordering, parameter selection, and chain-specific dependency wiring.
- Deterministic deployment assumptions depend on downstream salts, constructor args, and registry expectations remaining synchronized.

## Critical Flows

### Full Deployment

```text
operator
  -> runs Deploy.s.sol
  -> repo deploys the core stack first
  -> deploys registries, hooks, cross-chain infrastructure, and product repos in dependency order
  -> records canonical addresses for later phases
```

### Resume

```text
operator
  -> runs Resume.s.sol after partial success
  -> script checks which deterministic addresses already contain code
  -> deploys only the missing remainder
  -> preserves the original rollout assumptions
```

## Accounting Model

This repo does not own protocol accounting. Its economic risk is indirect: a bad deployment order or wrong constructor argument can instantiate the wrong accounting system downstream.

## Security Model

- CREATE2 makes naive replay unsafe after partial success.
- A stale recovery script is a broken production path.
- Cross-repo drift is the main hazard: constructor args, salts, and deployment assumptions move in sibling repos before this repo is updated.
- Verification drift is also hazardous. A script that still deploys correctly but verifies the wrong invariants gives false confidence about production state.

## Safe Change Guide

- If a sibling repo changes a constructor, salt, or required dependency, update `Deploy.s.sol` and `Resume.s.sol` together.
- If a deployment assumption changes, update `Verify.s.sol` in the same change set or document why the old check still holds.
- Validate deployment changes with the target chain matrix they affect.
- Prefer explicit wiring over inferred discovery when determinism matters.

## Canonical Checks

- deploy/resume continuity:
  `test/fork/DeployResumeRehearsalFork.t.sol`
- post-deploy verification assumptions:
  `test/fork/DeployScriptVerification.t.sol`
- full-stack rollout coherence:
  `test/fork/FullStackFork.t.sol`

## Source Map

- `script/Deploy.s.sol`
- `script/Resume.s.sol`
- `script/Verify.s.sol`
- `test/fork/DeployResumeRehearsalFork.t.sol`
- `test/fork/DeployScriptVerification.t.sol`
- `test/fork/FullStackFork.t.sol`
