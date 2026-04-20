# Administration

## At A Glance

| Item | Details |
| --- | --- |
| Scope | Protocol-wide deployment-time owner assignment, default registry wiring, and revnet operator selection |
| Control posture | Deployment-only control |
| Highest-risk actions | Wrong constructor owner targets, wrong default registry wiring, and wrong revnet operator or stage config |
| Recovery posture | Most bad choices require redeployment of the affected layer and downstream migration |

## Purpose

`deploy-all-v6` does not create a runtime control plane of its own. Its job is to assign the right owners, registries, defaults, and operator addresses during deployment. The key question for this repo is who receives power at deployment time.

## Control Model

- The script is deployment-only.
- `safeAddress()` is the protocol-level owner target for most `Ownable` contracts and configurator roles.
- Revnet-specific operator addresses are hardcoded environment choices, not inferred from the safe.
- One-time post-deploy wiring such as default hooks, default router terminal, first-controller allowlisting, and sucker deployer approval happens here.

## Roles

| Role | How Assigned | Scope | Notes |
| --- | --- | --- | --- |
| Sphinx safe | `safeAddress()` in the deployment script | Protocol-wide | Receives ownership of most protocol-owned contracts |
| Revnet split operator | Hardcoded in deployment config per revnet | Per revnet | Distinct from the safe |
| Sucker deployer configurator | Constructor `configurator` | Per deployer | Usually the same safe |

## Privileged Surfaces

The important admin actions in this repo are deployment-time assignments, not runtime calls:

- choosing the `owner` or `initialOwner` constructor argument for `JBDirectory`, `JBProjects`, `JBPrices`, `JBFeelessAddresses`, `JBBuybackHookRegistry`, `JBRouterTerminalRegistry`, `JBSuckerRegistry`, and `REVLoans`
- choosing revnet operator addresses, auto-issuance beneficiaries, and immutable stage configs
- performing post-deploy wiring such as:
  - `JBDirectory.setIsAllowedToSetFirstController(...)`
  - `JBBuybackHookRegistry.setDefaultHook(...)`
  - `JBRouterTerminalRegistry.setDefaultTerminal(...)`
  - `JBSuckerRegistry.allowSuckerDeployers(...)`
  - chain-specific sucker deployer configuration calls

## Immutable And One-Way

- Constructor ownership targets are immutable once deployment succeeds.
- Revnet stage definitions and many revnet operator assignments are deployment-final.
- Price-feed additions and singleton deployer configuration create downstream immutables that are hard to unwind.
- A bad deployment ordering or constructor arg can poison later layers because those addresses are fed forward.

## Operational Notes

- Rehearse the full rollout before changing owner targets or post-deploy wiring.
- Treat changes to `safeAddress()`, revnet operator addresses, and fee-project assumptions as control-plane changes, not script refactors.
- Keep deployment order explicit; later phases assume earlier addresses are already final.

## Machine Notes

- Do not infer runtime authority from this repo after deployment; it only assigns authority to downstream contracts.
- Treat `script/Deploy.s.sol` as the source of truth for owner targets, registry defaults, and initial allowlists.
- If deployed addresses and expected constructor owners diverge, stop and resolve the mismatch before continuing rollout or documentation.

## Recovery

- If a transaction fails atomically, fix the script or config and rerun.
- If the deployment succeeds with bad immutable config, recovery usually means redeploying the affected layer and migrating projects or terminals to it.
- There is no generic in-place fix for wrong constructor owners or wrong revnet stage config.

## Admin Boundaries

- This repo cannot repair a bad immutable deployment after the fact by itself.
- It cannot override the runtime admin rules of downstream repos; it only instantiates them.
- Once ownership is handed to the safe or to downstream revnet machinery, this repo has no continuing authority.

## Source Map

- `script/Deploy.s.sol`
- `script/Resume.s.sol`
- `script/Verify.s.sol`
- `test/`
