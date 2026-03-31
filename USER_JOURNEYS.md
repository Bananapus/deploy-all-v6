# User Journeys

## Who This Repo Serves

- operators rehearsing the full Juicebox V6 ecosystem before a live rollout
- engineers executing multi-package deployments across chains
- responders recovering from an interrupted deployment sequence
- reviewers verifying that the composed stack still works after upstream changes

## Journey 1: Rehearse A Full Ecosystem Deployment On Forks

**Starting state:** the team wants to prove the current sibling repos still deploy and compose correctly before touching a live chain.

**Success:** fork tests cover the deployment sequence plus the important multi-repo feature interactions.

**Flow**
1. Run the fork-heavy suite in this repo rather than testing only isolated packages.
2. Exercise end-to-end deployment, fee-project setup, router and buyback composition, sucker flows, and long-horizon lifecycle scenarios.
3. Treat failures here as a deployment-shape problem until proven otherwise.

## Journey 2: Execute A Phased Main Deployment

**Starting state:** the ecosystem is ready for live rollout and artifact drift has already been checked.

**Success:** `script/Deploy.s.sol` executes the intended sequencing so dependencies exist before downstream packages reference them.

**Flow**
1. Feed the deployment script the chain-specific config and sibling-package artifacts it expects.
2. Let the script deploy the core dependencies first and the composed packages after their prerequisites exist.
3. Record outputs carefully because later verification and resume flows depend on them being consistent.

## Journey 3: Recover From An Interrupted Deployment

**Starting state:** the deployment stopped mid-flight and the team needs to continue without duplicating or corrupting prior work.

**Success:** the resume path picks up from the last known-good state instead of pretending the deployment is atomic.

**Flow**
1. Inspect the partial artifacts and outputs from the interrupted run.
2. Use `script/Resume.s.sol` to continue from that state.
3. Verify that resumed addresses still match the expectations of the packages that have not deployed yet.

**Failure cases that matter:** stale artifacts, manually patched outputs that no longer match chain state, and assuming a resume flow is only ops tooling when tests explicitly treat it as production-critical behavior.

## Journey 4: Verify The Deployment Before Calling It Live

**Starting state:** contracts are deployed but the team still needs confidence that the resulting stack is the one it intended.

**Success:** verification catches address, artifact, or composition drift before users rely on the system.

**Flow**
1. Run `script/Verify.s.sol` and the verification-oriented fork tests.
2. Compare deployed addresses, hook composition, and cross-package assumptions against the expected outputs.
3. Treat verification as part of the deploy path, not a cosmetic last step.

## Hand-Offs

- Use the individual package repos to understand subsystem behavior; this repo only proves that the combined system still deploys and composes correctly.
- Use [nana-fee-project-deployer-v6](../nana-fee-project-deployer-v6/USER_JOURNEYS.md) when the operational question is specifically about project `#1` rather than the whole ecosystem rollout.
