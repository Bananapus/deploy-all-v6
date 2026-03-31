# User Journeys

## Who This Repo Serves

- protocol maintainers deploying the full V6 stack
- operators rehearsing recovery or resume paths before production rollout
- auditors reviewing the real operational sequence rather than isolated repo deployments

## Journey 1: Rehearse A Full Ecosystem Deployment

**Starting state:** sibling V6 repos are checked out together and their artifacts are expected to agree.

**Success:** you have a realistic fork-based rehearsal of the production deployment path.

**Flow**
1. Install dependencies for the orchestration repo and sibling packages it expects.
2. Run the build and test suite to catch artifact drift and integration mismatches.
3. Use the fork-heavy rehearsals to validate that the composed stack still deploys and wires together correctly.
4. Treat failures here as deployment blockers, not as "just test" noise.

## Journey 2: Execute A Phased Main Deployment

**Starting state:** chain credentials, Sphinx configuration, and dependency artifacts are ready.

**Success:** the complete V6 ecosystem is deployed in the intended order.

**Flow**
1. Run `script/Deploy.s.sol` through the intended deployment pipeline.
2. Progress phase by phase instead of reasoning about the stack as one opaque transaction.
3. Confirm critical dependencies such as the fee project, core protocol addresses, hooks, and cross-chain infrastructure at each boundary.
4. Record phase outputs because later resume and verify steps depend on them.

## Journey 3: Recover From An Interrupted Deployment

**Starting state:** a previous deployment sequence stopped mid-flight or produced partial state.

**Success:** you can resume safely without duplicating or corrupting ecosystem state.

**Flow**
1. Inspect what was already deployed and what phase failed.
2. Use `script/Resume.s.sol` to continue from the last valid checkpoint.
3. Use `script/Verify.s.sol` after completion to confirm the resulting addresses and relationships.
4. Compare outputs against the intended per-repo deployments before treating the rollout as final.

**Main risk:** this repo amplifies mistakes because it composes many packages at once. Recovery logic is part of the production surface.

## Hand-Offs

- Use the repo-level `USER_JOURNEYS.md` files in sibling packages to validate whether an upstream subsystem is behaving correctly before resuming.
