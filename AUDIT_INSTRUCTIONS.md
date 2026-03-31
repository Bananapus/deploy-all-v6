# Audit Instructions

This repo is the full-stack deployment orchestrator. Treat it as production code: wrong wiring here can make correct runtime contracts unsafe.

## Objective

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
- fork-heavy tests under `test/fork/`

Out of scope:
- re-auditing the internal logic of every deployed dependency in `node_modules`

## System Model

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

## Threat Model

Prioritize:
- stale hardcoded addresses
- omitted initialization calls
- missing registry registration
- misordered ownership transfer or permission grants
- deployment branches that only run on some chains
- resume or verify logic that silently accepts partial drift

Common high-value failure modes here are:
- the deployment succeeds but wires a correct contract to the wrong singleton
- a partial resume skips a one-time transfer or approval that the clean path performs
- per-chain constants are individually plausible but ecosystem-inconsistent

## Hotspots

- any chain-specific constant selection
- hook-mining or deterministic-address assumptions
- fee-project and revnet bootstrapping
- sucker deployer approval and pairing
- address registry writes
- verification passes that can report success despite mismatched state

## Sequences Worth Replaying

1. Clean deployment versus resumed deployment from mid-phase.
2. Deployment on two different chains with chain-specific branches enabled.
3. Project creation ordering and the assumptions other repos make about those IDs afterward.
4. Approval and ownership transfer steps that happen immediately before a dependent contract is first used.

## Build And Verification

Standard workflow:
- `npm install`
- `forge build`
- `forge test`

This repo’s tests are mostly fork and composition rehearsals. Use them to validate:
- full-stack deployment ordering
- resume paths
- cross-feature interoperability
- chain-specific constant selection

Strong findings here usually show a concrete deployment state that looks successful but leaves a production system miswired, over-privileged, or economically incorrect.
