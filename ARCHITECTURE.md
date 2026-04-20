# Architecture

## Purpose

`deploy-all-v6` is the canonical deployment orchestrator for the V6 ecosystem. It does not add runtime protocol behavior. It owns sequencing, chain-specific wiring, canonical address selection, verification follow-up, and recovery from partial deployment.

## System Overview

The V6 stack is intentionally multi-repo and cross-chain. `Deploy.s.sol` performs the main phased rollout. `Resume.s.sol` is the deterministic recovery path for partial deployments. `Verify.s.sol` checks that the deployed stack matches the expected shape.

## Core Invariants

- Deployment order is a dependency graph, not a presentation choice.
- Canonical addresses must stay aligned with the expectations baked into sibling repos and fork tests.
- Recovery logic must stay in sync with main deployment logic.
- Verification is part of the deployment contract, not an optional afterthought.
- Testnet support is intentionally narrower than mainnet support for some phases; that asymmetry should stay explicit.

## Modules

| Module | Responsibility | Notes |
| --- | --- | --- |
| `script/Deploy.s.sol` | Main phased rollout via Sphinx | Happy-path deployment |
| `script/Resume.s.sol` | Partial-execution recovery | Deterministic continuation path |
| `script/Verify.s.sol` | Deployment verification follow-up | Sanity and consistency checks |

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

### Resume

```text
operator
  -> runs Resume.s.sol after partial success
  -> script checks which deterministic addresses already contain code
  -> deploys only the missing remainder
  -> preserves the original rollout assumptions
```

## Accounting Model

This repo does not own protocol accounting. Its economic risk is indirect: bad deployment order or wrong constructor args can instantiate the wrong accounting system downstream.

## Security Model

- CREATE2 makes naive replay unsafe after partial success.
- A stale recovery script is a broken production path.
- Cross-repo drift is the main hazard: constructors, salts, and deployment assumptions can move in sibling repos before this repo is updated.
- Verification drift is also dangerous. A script that deploys correctly but verifies the wrong invariants gives false confidence.

## Safe Change Guide

- If a sibling repo changes a constructor, salt, or required dependency, update `Deploy.s.sol` and `Resume.s.sol` together.
- If a deployment assumption changes, update `Verify.s.sol` in the same change set or document why the old check still holds.
- Validate deployment changes against the chain matrix they affect.
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
