# Deploy All V6

`deploy-all-v6` is the orchestration repo for the wider Juicebox V6 stack in this workspace. Use it when you want to deploy or rehearse the ecosystem together instead of deploying packages one by one.

Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md)  
User journeys: [USER_JOURNEYS.md](./USER_JOURNEYS.md)  
Skills: [SKILLS.md](./SKILLS.md)  
Risks: [RISKS.md](./RISKS.md)  
Administration: [ADMINISTRATION.md](./ADMINISTRATION.md)  
Review instructions: [REVIEW_GUIDE.md](./REVIEW_GUIDE.md)

## Overview

This repo does not define protocol behavior of its own. Its job is to stitch together deployment artifacts, cross-package addresses, and multi-chain sequencing for the V6 ecosystem.

It is responsible for:

- workspace-level deployment orchestration
- resume and recovery flows
- post-deploy verification
- fork rehearsals of cross-feature compositions

Use this repo when the question is "does the combined deployment still work?" Do not use it as the main place to understand subsystem runtime behavior.

## Key Scripts

| Script | Role |
| --- | --- |
| `script/Deploy.s.sol` | Main end-to-end deployment entrypoint |
| `script/Resume.s.sol` | Resume and recovery tooling for interrupted deployments |
| `script/Verify.s.sol` | Post-deploy verification checks |

## Mental Model

This repo owns sequencing, not business logic. It is where the intended cross-repo deployment shape is exercised under chain-specific conditions.

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

- this repo has almost no runtime protocol logic of its own, so many assumptions live in sibling packages
- a successful deployment sequence can still encode bad cross-repo configuration
- resume and recovery paths are part of the intended operational surface
- artifact drift and chain-specific environment mismatches are the main failure classes here

## Where State Lives

- orchestration logic lives in the deployment scripts
- high-signal behavior checks live in `test/fork/`
- deployed runtime state ultimately lives in the sibling repos this package composes

## Workspace Use

This repo is a private workspace package, not a published reusable library. Use it from a cloned `v6/evm` checkout or as a sibling repo in the same multi-repo workspace.

## Development

```bash
npm install
forge build --deny notes --skip "*/test/**"
forge test --deny notes --fail-fast --summary --detailed --skip "*/script/**"
```

The test suite is fork-heavy and exercises realistic multi-repo compositions rather than isolated mocks.

## Deployment Notes

This repo assumes the sibling V6 packages are present and their deployment artifacts are internally consistent. Some phases are intentionally chain-dependent, including skipping parts of the Uniswap stack on networks without the required external infrastructure. `Verify.s.sol` is a deployment check, not a full runtime review.

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
- deployment recovery paths should be treated as production code
- fork rehearsals reduce deployment risk, but they do not remove chain-specific operational risk
- artifact drift across sibling packages is one of the main failure modes
- stale verification logic can report green while checking the wrong assumptions

## For AI Agents

- Do not treat this repo as the source of truth for subsystem behavior.
- Start with the deployment scripts, then use the fork tests to see which deployment and recovery assumptions are pinned.
- When summarizing a failure, name the sibling package that actually owns the affected runtime behavior.
