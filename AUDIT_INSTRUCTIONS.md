# Audit Instructions

This repo is the full-stack deployment orchestrator. Treat it as production code: wrong wiring here can make correct runtime contracts unsafe.

## Audit Objective

Find issues that:
- deploy the wrong contract, implementation, hook, registry, or price feed
- wire correct contracts together with incorrect parameters
- mis-sequence deployments so ownership, permissions, or dependencies are wrong
- make recovery or resume flows diverge from clean deployment behavior
- leave partial deployment states exploitable or unverifiable

## Scope

In scope:
- `script/Deploy.s.sol`
- `script/Resume.s.sol`
- `script/Verify.s.sol`
- any helper logic under `script/`

Out of scope:
- re-auditing the internal logic of every deployed dependency in `node_modules`

## Start Here

1. `script/Deploy.s.sol`
2. `script/Resume.s.sol`
3. `script/Verify.s.sol`

## Security Model

This repo does not introduce a new treasury or hook. It assembles the ecosystem:
- deploys or references shared singletons
- wires constructor and initializer arguments
- configures owners, registries, permissions, and addresses
- creates canonical projects and compositions in a specific order
- provides recovery and verification tooling for interrupted or resumed runs

The key audit mindset here is that many runtime trust assumptions are born during deployment:
- which hook is the default
- which registry is authoritative
- which project ID receives fees
- which deployers are approved to create privileged bridge peers

## Roles And Privileges

| Role | Powers | How constrained |
|------|--------|-----------------|
| Deployment script caller | Execute the full rollout | Must not retain post-deploy authority |
| Resume flow | Continue partially completed deployment | Must converge to the same final state as a clean run |
| Verify flow | Certify deployment correctness | Must fail on real drift, not just missing contracts |

## Integration Assumptions

| Dependency | Assumption | What breaks if wrong |
|------------|------------|----------------------|
| Per-chain constants | Match canonical addresses and chain intent | Deployment succeeds but wires the wrong system |
| Downstream deployers and registries | Expose expected ownership and pairing behavior | Privileged peers and fee sinks misconfigure silently |

## Critical Invariants

1. Deployment order is semantically correct
Every contract must be deployed only after the dependencies it relies on exist and are in the expected state.

2. Canonical singleton wiring is correct
Registries, router hooks, deployers, fee project references, price feeds, and bridge deployers must all point to the intended contracts.

3. Ownership and permissions end in the intended hands
Temporary deploy-time authority must not remain on scripts, implementations, or helpers after the deployment completes.

4. Resume behavior is equivalent
A resumed deployment must converge to the same final state as a clean deployment, not a subtly different one.

5. Cross-chain assumptions stay aligned
Project ordering, bridge deployer sets, and per-chain constants must remain consistent across all target chains.

6. Verification actually proves the deployed state
`Verify`-style checks must fail when addresses, ownership, or critical configuration drift, not just when contracts are missing.

## Attack Surfaces

- any chain-specific constant selection
- hook-mining or deterministic-address assumptions
- fee-project and revnet bootstrapping
- sucker deployer approval and pairing
- address registry writes
- verification passes that can report success despite mismatched state

Replay these sequences:
1. clean deployment versus resumed deployment from mid-phase
2. deployment on two chains with different chain-specific branches
3. project creation ordering and the assumptions later repos make about those IDs
4. ownership transfer and approval steps immediately before first use

## Accepted Risks Or Behaviors

- This repo intentionally centralizes authority during deployment and is only safe if that authority is fully relinquished.

## Verification

- `npm install`
- `forge build`
- `forge test`
