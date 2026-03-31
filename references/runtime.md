# Deploy All Runtime

## Core Scripts

- [`script/Deploy.s.sol`](../script/Deploy.s.sol) is the main end-to-end deployment sequence.
- [`script/Resume.s.sol`](../script/Resume.s.sol) handles interrupted or partial rollouts.
- [`script/Verify.s.sol`](../script/Verify.s.sol) handles post-deployment verification.

## High-Risk Areas

- Cross-repo artifact drift: this repo amplifies stale assumptions imported from sibling packages.
- Phase ordering: many failures are ordering failures, not contract failures.
- Resume safety: recovery behavior must preserve idempotence and deployed-address assumptions.

## Tests To Trust First

- [`test/fork/`](../test/fork/) for full-stack and recovery rehearsals.
