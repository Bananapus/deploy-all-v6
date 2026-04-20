# Deploy All V6

`deploy-all-v6` is the orchestration repo for the wider active Juicebox V6 stack represented in this workspace. It is the package you use when you want to deploy or rehearse the ecosystem together instead of deploying individual repos one by one.

Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md)  
User journeys: [USER_JOURNEYS.md](./USER_JOURNEYS.md)  
Skills: [SKILLS.md](./SKILLS.md)  
Risks: [RISKS.md](./RISKS.md)  
Administration: [ADMINISTRATION.md](./ADMINISTRATION.md)  
Audit instructions: [AUDIT_INSTRUCTIONS.md](./AUDIT_INSTRUCTIONS.md)

## Overview

This repo does not define a protocol surface of its own. Its job is to stitch together deployment artifacts, cross-package addresses, and multi-chain sequencing for the broader V6 ecosystem.

It is responsible for:

- workspace-level deployment orchestration
- deployment resume and recovery flows
- verification passes after deployment
- fork-based rehearsals of cross-feature compositions

Use this repo when the question is "does the workspace deployment composition deploy and rehearse correctly?" Do not use it as the primary place to understand subsystem behavior; that lives in the individual package repos.

If you are debugging runtime behavior before deployment shape is even known to be correct, this is usually the wrong repo to start in.

## Key Scripts

| Script | Role |
| --- | --- |
| `script/Deploy.s.sol` | Main end-to-end deployment entrypoint for the workspace deployment composition. |
| `script/Resume.s.sol` | Resume and recovery tooling for interrupted deployment sequences. |
| `script/Verify.s.sol` | Verification-oriented deployment follow-up. |

## Mental Model

This repo owns sequencing, not business logic. It is the place where the intended cross-repo deployment composition is exercised under chain-specific deployment conditions.

## Read These Files First

1. `script/Deploy.s.sol`
2. `script/Resume.s.sol`
3. `script/Verify.s.sol`
4. `test/fork/DeployFullStack.t.sol`
5. `test/fork/DeployResumeRehearsalFork.t.sol`

## High-Signal Tests

1. `test/fork/DeployFullStack.t.sol`
2. `test/fork/DeployResumeRehearsalFork.t.sol`
3. `test/fork/DeployScriptVerification.t.sol`
4. `test/fork/ResumeDeployFork.t.sol`
5. `test/fork/SuckerEndToEndFork.t.sol`

## Integration Traps

- this repo has almost no runtime protocol logic of its own, so many important assumptions live in sibling packages
- a successful deployment sequence can still encode bad cross-repo configuration, which is why the fork suite matters
- resume and recovery paths are part of the intended operational surface, not just emergency tooling
- artifact drift and chain-specific environment mismatch are the main failure classes here

## Where State Lives

- orchestration logic lives in the deployment scripts, not in runtime contracts inside this repo
- high-signal behavior checks live in `test/fork/`
- deployed protocol state ultimately lives in the sibling repos this package composes

## Workspace Use

This repo is a private workspace package, not a published reusable library. Use it from a cloned `v6/evm` checkout or as a sibling repo in the same multi-repo workspace.

## Development

```bash
npm install
forge build
forge test
```

The test suite is fork-heavy and exercises realistic multi-repo compositions rather than isolated local mocks.

## Deployment Notes

This repo assumes the sibling V6 packages are available and their deployment artifacts remain internally consistent. Some phases are intentionally chain-dependent, including skipping parts of the Uniswap stack on networks without the required external infrastructure. `Verify.s.sol` is a post-deploy wiring check, not an exhaustive runtime audit. Treat this repo as the last mile of deployment orchestration, not the source of truth for subsystem behavior.

## Repository Layout

```text
script/
  Deploy.s.sol
  Resume.s.sol
  Verify.s.sol
test/fork/
  full-stack, recovery, cross-feature, and long-horizon deployment rehearsals
```

## Risks And Notes

- this repo amplifies configuration mistakes because it composes many packages at once
- deployment recovery paths are part of the intended surface and should be treated as production code
- fork rehearsals reduce deployment risk, but they do not remove chain-specific operational risk
- artifact drift across sibling packages is one of the main failure modes
- verification drift is also hazardous: a stale post-deploy check can report green while proving the wrong assumptions

## For AI Agents

- Do not treat this repo as the source of truth for subsystem behavior; it is the best workspace-level entrypoint for deployment composition.
- Start with the deployment scripts, then use `DeployResumeRehearsalFork.t.sol`, `ResumeDeployFork.t.sol`, and `DeployScriptVerification.t.sol` to see which deployment and recovery assumptions are pinned.
- When summarizing a failure, name the sibling package that actually owns the affected runtime behavior.
