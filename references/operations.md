# Deploy All Operations

Use this file when the question is operational: what to rerun, what to trust, and whether a failure belongs to deployment orchestration or to a sibling runtime repo.

## Operator Checklist

- Confirm sibling package broadcasts, addresses, and constructor inputs before blaming this repo.
- Use [`script/Resume.s.sol`](../script/Resume.s.sol) for partially completed rollouts instead of replaying `Deploy.s.sol` against dirty on-chain state.
- Use [`script/Verify.s.sol`](../script/Verify.s.sol) after deployment to confirm the chain state still matches the expected published artifacts.
- If the symptom is isolated to one subsystem after a clean deploy, move into that subsystem repo instead of continuing to debug here.

## Common Failure Modes

- A subsystem deployment changed shape, but this repo still assumes the old artifact, salt, or address.
- Operators debug runtime behavior here before proving the deployment graph is even correct.
- Recovery steps are skipped and the rollout is restarted in a way that breaks deterministic assumptions.
- A chain-specific token, decimal, or price-feed assumption is wrong, so the integrated deployment fails while unit repos still look healthy.

## Tests To Trust First

- [`test/fork/DeployScriptVerification.t.sol`](../test/fork/DeployScriptVerification.t.sol) when the question is whether the scripts assembled the intended config.
- [`test/fork/ResumeDeployFork.t.sol`](../test/fork/ResumeDeployFork.t.sol) and [`test/fork/DeployResumeRehearsalFork.t.sol`](../test/fork/DeployResumeRehearsalFork.t.sol) for resume behavior.
- [`test/fork/SuckerEndToEndFork.t.sol`](../test/fork/SuckerEndToEndFork.t.sol), [`test/fork/BuybackRouterFork.t.sol`](../test/fork/BuybackRouterFork.t.sol), and [`test/fork/LPBuybackInteropFork.t.sol`](../test/fork/LPBuybackInteropFork.t.sol) for cross-package integration failures.
