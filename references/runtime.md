# Deploy All Runtime

Use this file when the bug only appears after multiple V6 packages are composed together and you need the orchestration surface, not one protocol repo in isolation.

## Core Scripts

- [`script/Deploy.s.sol`](../script/Deploy.s.sol) is the canonical end-to-end rollout. Read it first when a system invariant only fails after the full stack is deployed. Its `DEPLOYMENT_NONCE` is the recovery lever: when the state on chain is partial but nonzero, bump the nonce and redeploy from fresh salts into a clean, non-colliding address namespace.
- [`script/Verify.s.sol`](../script/Verify.s.sol) is the final consistency pass for deployed addresses, permissions, and published artifacts.

## High-Risk Areas

- Cross-repo artifact drift: this repo amplifies stale assumptions imported from sibling packages and old broadcasts.
- Phase ordering: many failures are deployment-sequencing failures, not runtime contract bugs.
- Recovery safety: a fresh-salt redeploy must re-namespace every CREATE2/CREATE3 salt cleanly, and the same nonce must be used across chains when cross-chain address parity matters.
- Chain-shape assumptions: mixed decimals, base-currency wiring, and fee-project setup often fail only in the integrated deployment.

## Tests To Trust First

- [`test/fork/DeployFork.t.sol`](../test/fork/DeployFork.t.sol), [`test/fork/DeployFullStack.t.sol`](../test/fork/DeployFullStack.t.sol), and [`test/fork/FullStackFork.t.sol`](../test/fork/FullStackFork.t.sol) for baseline integrated deployment shape.
- [`test/fork/ResumeDeployFork.t.sol`](../test/fork/ResumeDeployFork.t.sol) and [`test/fork/DeployResumeRehearsalFork.t.sol`](../test/fork/DeployResumeRehearsalFork.t.sol) for interruption and recovery behavior.
- [`test/fork/EcosystemFork.t.sol`](../test/fork/EcosystemFork.t.sol), [`test/fork/CrossFeatureLifecycleFork.t.sol`](../test/fork/CrossFeatureLifecycleFork.t.sol), and [`test/fork/HookCompositionFork.t.sol`](../test/fork/HookCompositionFork.t.sol) when cross-repo composition is the suspected source of failure.
- [`test/fork/CrossCurrencyFork.t.sol`](../test/fork/CrossCurrencyFork.t.sol), [`test/fork/WBTC8DecimalFork.t.sol`](../test/fork/WBTC8DecimalFork.t.sol), and [`test/fork/MixedDecimalLoanComposition.t.sol`](../test/fork/MixedDecimalLoanComposition.t.sol) for denomination and decimal-edge behavior.
