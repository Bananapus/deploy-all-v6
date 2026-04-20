# Juicebox Deploy All

## Use This File For

- Use this file when the task is about multi-chain deployment, partial-rollout recovery, artifact verification, or dependency ordering across the ecosystem.
- Start here for deployment sequencing, then decide whether the failure is bad ordering, stale artifact input, resume drift, or downstream package drift.

## Read This Next

| If you need... | Open this next |
|---|---|
| Repo overview and operator expectations | [`README.md`](./README.md), [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| Primary deployment sequence | [`script/Deploy.s.sol`](./script/Deploy.s.sol) |
| Recovery or resume behavior | [`script/Resume.s.sol`](./script/Resume.s.sol) |
| Verification flow | [`script/Verify.s.sol`](./script/Verify.s.sol) |
| Deployment-phase and operator invariants | [`references/runtime.md`](./references/runtime.md), [`references/operations.md`](./references/operations.md) |
| Full-stack or recovery rehearsals | [`test/fork/DeployFullStack.t.sol`](./test/fork/DeployFullStack.t.sol), [`test/fork/DeployResumeRehearsalFork.t.sol`](./test/fork/DeployResumeRehearsalFork.t.sol), [`test/fork/DeployScriptVerification.t.sol`](./test/fork/DeployScriptVerification.t.sol) |
| Cross-feature composition and failure drills | [`test/fork/CrossFeatureLifecycleFork.t.sol`](./test/fork/CrossFeatureLifecycleFork.t.sol), [`test/fork/SuckerEndToEndFork.t.sol`](./test/fork/SuckerEndToEndFork.t.sol), [`test/fork/WildcardPermissionKillChain.t.sol`](./test/fork/WildcardPermissionKillChain.t.sol) |

## Repo Map

| Area | Where to look |
|---|---|
| Scripts | [`script/`](./script/) |
| Fork tests | [`test/fork/`](./test/fork/) |
| Config | [`foundry.toml`](./foundry.toml), [`package.json`](./package.json) |

## Purpose

Deployment orchestration repo for the full Juicebox V6 ecosystem. It does not define new runtime behavior. It coordinates deployment order, resume flows, and verification across many sibling packages.

## Reference Files

- Open [`references/runtime.md`](./references/runtime.md) for deployment phases, dependency ordering, and the main invariants around resume-safe orchestration.
- Open [`references/operations.md`](./references/operations.md) for operator guidance, recovery breadcrumbs, and common stale-data traps caused by cross-repo artifact drift.

## Working Rules

- Start in [`script/Deploy.s.sol`](./script/Deploy.s.sol) for phase ordering.
- Treat recovery and verification paths as production paths, not optional extras.
- Many bugs here are wrong assumptions imported from sibling repos. Prove the inputs are current before editing orchestration logic.
- When debugging a failure, separate bad script logic from stale addresses or assumptions imported from sibling repos.
