# Audit Instructions

This repo is the full-stack deployment orchestrator. Treat it as production code: wrong wiring here can make correct runtime contracts unsafe.

There is a billion dollars of well-meaning projects' money in the Juicebox Money Engine, growing exponentially. Your job is to hack it before anyone else. Whoever hacks it first saves/steals the money, and you are obsessed with being this winner, while also being a steward of the protocol and wanting it to keep growing safely.

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
- helper logic under `script/`

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

The key audit mindset is that many runtime trust assumptions are born during deployment:

- which hook is the default
- which registry is authoritative
- which project ID receives fees
- which deployers are approved to create privileged bridge peers

## Roles And Privileges

| Role | Powers | How constrained |
|------|--------|-----------------|
| Deployment script caller | Execute the full rollout | Must not retain post-deploy authority |
| Resume flow | Continue partially completed deployment | Must converge to the same final state as a clean run |
| Verify flow | Certify deployment correctness | Must fail on real drift, not only missing contracts |

## Integration Assumptions

| Dependency | Assumption | What breaks if wrong |
|------------|------------|----------------------|
| Per-chain constants | Match canonical addresses and chain intent | Deployment succeeds but wires the wrong system |
| Downstream deployers and registries | Expose expected ownership and pairing behavior | Privileged peers and fee sinks misconfigure silently |

## Critical Invariants

1. Deployment order is semantically correct.
   Every contract must be deployed only after its dependencies exist and are in the expected state.

2. Canonical singleton wiring is correct.
   Registries, router hooks, deployers, fee project references, price feeds, and bridge peers must point at the intended contracts.

3. Resume converges to the same final state.
   Recovery from partial deployment must not create a different topology than a clean deployment.

4. Verification matches real intent.
   `Verify.s.sol` must fail on actual drift and stay synchronized with deploy and resume logic.

5. Deployment does not leave hidden authority behind.
   Ownership, wildcard permissions, and allowlists must converge to the intended steady-state trust model.

## Attack Surfaces

- hardcoded chain-specific addresses
- constructor and initializer parameters
- phased deployment ordering
- resume checkpoints and identity checks
- verification scripts that can go stale while deployments still succeed

## Accepted Risks Or Behaviors

- Some phases intentionally differ by chain because external infrastructure is not uniform across all targets.
- Deployment recovery is part of the supported operational surface, not an emergency-only side path.

## Verification

- run `forge build --deny notes --skip "*/test/**"` to compile the deployment scripts without lint notes
- run the fork-based deployment and resume tests with `forge test --deny notes --fail-fast --summary --detailed --skip "*/script/**"`
- compare deployed addresses and owner targets against the expected chain config
- run `script/Verify.s.sol` after concrete deployment changes
