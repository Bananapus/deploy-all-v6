# User Journeys

## Repo Purpose

This repo orchestrates deployment of the full V6 ecosystem. It owns sequencing, recovery, and verification for the composed stack. It does not own subsystem business logic.

## Primary Actors

- operators rehearsing the full ecosystem before a live rollout
- engineers executing multi-package deployments across chains
- responders recovering from interrupted deployments
- reviewers validating cross-package composition after upstream changes

## Key Surfaces

- `script/Deploy.s.sol`: full deployment entrypoint
- `script/Resume.s.sol`: recovery path for interrupted deployments
- `script/Verify.s.sol`: verification and drift-check path
- fork-heavy tests in `test/`: composition and deployment-shape regression coverage

## Journey 1: Rehearse A Full Ecosystem Deployment On Forks

**Actor:** release engineer or reviewer.

**Intent:** prove the current sibling repos still deploy and compose correctly.

**Preconditions**

- sibling repos and artifacts are present and current
- the team wants deployment-shape confidence, not just isolated unit coverage

**Main Flow**

1. Run the fork-heavy suite in this repo.
2. Exercise end-to-end deployment plus high-value cross-feature interactions.
3. Treat failures here as composition or deployment-shape problems until proven otherwise.

**Failure Modes**

- isolated package tests pass while cross-package behavior is broken
- stale artifacts make a healthy codebase look broken, or the reverse

**Postconditions**

- the team either has cross-package deployment confidence or a concrete composition failure to investigate

## Journey 2: Execute A Phased Main Deployment

**Actor:** deployment operator.

**Intent:** deploy the ecosystem in dependency order.

**Preconditions**

- artifact drift has already been checked
- chain-specific config and credentials are ready

**Main Flow**

1. Feed `script/Deploy.s.sol` the chain config and sibling-package artifacts it expects.
2. Deploy core dependencies before downstream packages that reference them.
3. Record outputs carefully because later resume and verify paths depend on them.

**Failure Modes**

- outputs are incomplete or manually edited mid-flight
- packages are deployed out of order or with mismatched artifacts

**Postconditions**

- deployment outputs exist in dependency order and can be consumed by resume and verify paths

## Journey 3: Recover From An Interrupted Deployment

**Actor:** deployment responder.

**Intent:** continue from the last known-good state without double-deploying or corrupting outputs.

**Preconditions**

- the interrupted run left artifacts or recorded outputs behind
- responders know which phase completed and which did not

**Main Flow**

1. Inspect the partial outputs from the interrupted run.
2. Use `script/Resume.s.sol` to continue from that state.
3. Re-check downstream expectations against the resumed addresses before moving forward.

**Failure Modes**

- stale artifacts or manually patched outputs no longer match chain state
- responders treat resume as ad hoc glue instead of a production path

**Postconditions**

- the deployment either resumes from a coherent checkpoint or stops before more drift is introduced

## Journey 4: Verify The Deployment Before Calling It Live

**Actor:** reviewer or deployment lead.

**Intent:** prove the resulting deployment matches the intended ecosystem shape.

**Preconditions**

- contracts are already deployed
- expected addresses and composition assumptions are available for comparison

**Main Flow**

1. Run `script/Verify.s.sol` and the verification-focused fork coverage.
2. Compare deployed addresses, hook composition, and imported assumptions against expected outputs.
3. Treat verification as part of deployment, not as a cosmetic afterthought.

**Failure Modes**

- deploy scripts succeed but the deployed graph is still wrong
- operators skip verification because contracts exist at expected addresses

**Postconditions**

- the team either accepts the deployment as live-ready or has a concrete mismatch to fix

## Trust Boundaries

- this repo trusts sibling packages and their artifacts to represent the intended code
- operators trust resume and verification state to reflect the real deployment accurately
- live-chain correctness still depends on chain-specific conditions this repo cannot abstract away

## Hand-Offs

- Use individual package repos to understand subsystem behavior; this repo only proves that the combined system still deploys and composes correctly.
- Use [nana-fee-project-deployer-v6](../nana-fee-project-deployer-v6/USER_JOURNEYS.md) when the operational question is specifically about project `#1` rather than the whole rollout.
