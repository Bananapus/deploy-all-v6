# Changelog

## Scope

`deploy-all-v6` is a deployment-orchestration repo, not a runtime protocol package. There is no one-for-one deployed v5 repo to diff against in the same way as the contract repos.

## Current v6 surface

- `script/Deploy.s.sol`
- `script/Resume.s.sol`
- `script/Verify.s.sol`
- fork-heavy integration coverage under `test/fork/`

## Summary

- This repo exists to deploy and rehearse the v6 stack as a coordinated system rather than as isolated repos.
- The current repo contents clearly assume the router-terminal era, the v6 buyback hook, v6 suckers, and the v6 revnet/omnichain stack.
- The test suite is oriented around cross-repo integration and recovery scenarios: resume flows, multi-chain deployment, price-feed failures, routing, sucker paths, and other system-level compositions.

## Migration notes

- Use this changelog as deployment-context documentation, not as a canonical ABI diff.
- When this repo changes, the important question is usually "which v6 components are orchestrated together now?" rather than "which callable surface changed here?"
