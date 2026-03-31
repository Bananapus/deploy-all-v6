# Deploy All V6

`deploy-all-v6` is the orchestration repo for the full Juicebox V6 stack. It is the package you use when you want to deploy or rehearse the entire ecosystem together instead of deploying individual repos one by one.

Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md)

## Overview

This repo does not define a protocol surface of its own. Its job is to stitch together deployment artifacts, cross-package addresses, and multi-chain sequencing for the broader V6 ecosystem.

It is responsible for:

- full-stack deployment orchestration
- deployment resume and recovery flows
- verification passes after deployment
- fork-based rehearsals of cross-feature compositions

Use this repo when the question is "does the full ecosystem deploy and compose correctly?" Do not use it as the primary place to understand subsystem behavior; that lives in the individual package repos.

If you are debugging runtime behavior before deployment shape is even known to be correct, this is usually the wrong repo to start in.

## Key Scripts

| Script | Role |
| --- | --- |
| `script/Deploy.s.sol` | Main end-to-end deployment entrypoint for the full V6 ecosystem. |
| `script/Resume.s.sol` | Resume and recovery tooling for interrupted deployment sequences. |
| `script/Verify.s.sol` | Verification-oriented deployment follow-up. |

## Mental Model

This repo owns sequencing, not business logic. It is the place where "all the pieces together" is exercised under deployment conditions.

## Development

```bash
npm install
forge build
forge test
```

The test suite is fork-heavy and exercises realistic multi-repo compositions rather than isolated local mocks.

## Deployment Notes

This repo assumes the sibling V6 packages are available and their deployment artifacts remain internally consistent. Treat it as the last mile of deployment orchestration, not the source of truth for subsystem behavior.

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
