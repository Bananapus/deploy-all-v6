# Architecture

## Purpose

`deploy-all-v6` is the canonical deployment orchestrator for the V6 ecosystem. Its job is not to introduce new runtime behavior. Its job is to deploy the right contracts, in the right order, with the right cross-repo wiring, across the supported chains, and to provide a recovery path when an execution partially succeeds.

## Boundaries

- Runtime protocol logic lives in sibling repos.
- This repo owns deployment sequencing, chain-specific constants, canonical address selection, and recovery assumptions.
- `Resume.s.sol` is part of the architecture, not a convenience script. The rollout is intentionally designed around resumable deployment.

## Main Components

| Component | Responsibility |
| --- | --- |
| `script/Deploy.s.sol` | Canonical phased rollout via Sphinx |
| `script/Resume.s.sol` | Recovery path for partially completed executions |
| deployment constants and helpers | Per-chain addresses, flags, and dependency wiring |

## Deployment Model

The deployment runs in dependency order:

1. Core protocol
2. Address registry
3. Hook and periphery stack
4. Cross-chain infrastructure
5. Omnichain deployer
6. Product repos and fee-bearing projects

That order is the main invariant. Many later phases assume earlier addresses are final and immediately usable.

## Why Recovery Is Separate

CREATE2 makes re-running a partially completed deployment unsafe. If some contracts already exist at their deterministic addresses, replaying the original script will collide with deployed bytecode. `Resume.s.sol` therefore checks what already exists and only performs the remaining steps.

## Critical Invariants

- Canonical addresses must stay aligned with the expectations baked into sibling deployment repos and tests.
- Phase ordering is a real dependency graph, not an organizational preference.
- Testnet support is intentionally narrower than mainnet support for certain Uniswap-dependent phases; scripts should preserve those skips rather than pretending the matrix is symmetric.
- Recovery logic must be kept current with deployment logic. A stale recovery script is a broken architecture.

## Where Complexity Lives

- Cross-repo constructor and initializer expectations all converge here.
- The recovery path has to model partial success precisely, which is often harder than the happy path.
- Chain-specific feature gaps make the rollout matrix asymmetric by design.

## Dependencies

- Every `*-v6` sibling repo that contributes deployed contracts
- Sphinx for multi-chain orchestration
- Chain-specific Uniswap, Chainlink, and bridge addresses

## Safe Change Guide

- If you add a dependency in a product repo, update the deployment phase model here at the same time.
- If you change a constructor argument or deployment salt downstream, verify both `Deploy.s.sol` and `Resume.s.sol`.
- Deployment changes need fork or dry-run validation against the actual target chains they affect.
- Avoid "helpful" implicit discovery in deployment scripts when determinism matters. Be explicit.
- Assume reviewers will care more about recovery correctness than deployment convenience.
