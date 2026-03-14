# Administration

Admin privileges and their scope in deploy-all-v6.

## Overview

This repo is a single Foundry/Sphinx deployment script (`script/Deploy.s.sol`, ~1,600 lines) that deploys the entire Juicebox V6 ecosystem in one atomic proposal. It has no `src/` directory and no runtime contracts of its own. All admin privileges originate from constructor arguments and post-deployment wiring calls made during the script's execution.

The deployer identity is the **Sphinx Safe** (`safeAddress()`). Every contract that accepts an owner, configurator, or operator address receives `safeAddress()`. After deployment, the Sphinx Safe holds all protocol-level admin powers.

## Deployment Ownership

Every contract that accepts an owner or admin address at construction receives the Sphinx Safe. The table below lists each contract and how it uses that address.

| Contract | Constructor Parameter(s) Set to `safeAddress()` | What It Grants |
|----------|--------------------------------------------------|----------------|
| `JBProjects` | `initialOwner`, `initialOperator` | ERC-721 ownership of project NFTs; creates project #1 (fee project) for the safe |
| `JBDirectory` | `initialOwner` | Can call `setIsAllowedToSetFirstController()` |
| `JBPrices` | `initialOwner` | Can add protocol-default price feeds (projectId=0) |
| `JBFeelessAddresses` | `initialOwner` | Can add/remove fee-exempt addresses |
| `JBBuybackHookRegistry` | `initialOwner` | Can call `setDefaultHook()` |
| `JBRouterTerminalRegistry` | `initialOwner` | Can call `setDefaultTerminal()` |
| `JBRouterTerminal` | `owner` | Owner of the router terminal instance |
| `JBSuckerRegistry` | `initialOwner` | Can call `allowSuckerDeployers()` to whitelist new sucker deployers |
| `REVLoans` | `owner` | Owner of the loans contract |
| All sucker deployers (OP, Base, Arb, CCIP) | `configurator` | Can call `setChainSpecificConstants()` and `configureSingleton()` |

### Project Ownership

The script creates projects in a deterministic order. Each project NFT is minted to `safeAddress()`:

| Project ID | Name | Created By | Initial Owner |
|------------|------|------------|---------------|
| 1 | NANA (fee project) | `JBProjects` constructor (automatic) | Sphinx Safe |
| 2 | CPN (Croptop) | `_projects.createFor(safeAddress())` | Sphinx Safe |
| 3 | REV (Revnet) | `_projects.createFor(safeAddress())` | Sphinx Safe |
| 4 | BAN (Banny) | Created by `_revDeployer.deployWith721sFor()` (revnetId=0) | REVDeployer (managed by revnet rules) |

For projects 1, 2, and 3 the script explicitly approves the `REVDeployer` to take ownership via `_projects.approve(address(_revDeployer), projectId)`. The REVDeployer then configures each as a revnet, which locks the project into revnet governance rules (no further manual configuration by the original owner).

## Protocol-Level Administration

After deployment completes, the Sphinx Safe retains admin capabilities over the following protocol-level functions:

### JBDirectory

- `setIsAllowedToSetFirstController(address, bool)` -- Controls which controllers can be set for new projects. The script calls this once to allow `JBController`. The safe can allow additional controllers.

### JBPrices

- `addPriceFeedFor(projectId=0, ...)` -- The safe sets default (protocol-wide) price feeds. Once a feed is set for a currency pair, it is **immutable** and cannot be replaced. The script sets:
  - USD/NATIVE_TOKEN (ETH/USD via Chainlink)
  - USD/ETH (same feed)
  - ETH/NATIVE_TOKEN (matching feed)
  - USD/USDC (via Chainlink)

### JBFeelessAddresses

- `setAddress(address, bool)` -- The safe can mark addresses as fee-exempt, meaning payments to/from those addresses skip the 2.5% protocol fee.

### JBSuckerRegistry

- `allowSuckerDeployers(address[])` -- The safe can approve new sucker deployer implementations. During deployment, all chain-appropriate deployers (OP, Base, Arb, CCIP) are pre-approved. The safe can add more later.

### JBBuybackHookRegistry

- `setDefaultHook(JBBuybackHook)` -- Sets the default buyback hook implementation. Called once during deployment.

### JBRouterTerminalRegistry

- `setDefaultTerminal(JBRouterTerminal)` -- Sets the default router terminal. Called once during deployment.

### Sucker Deployer Configuration

- Each sucker deployer (`JBOptimismSuckerDeployer`, `JBBaseSuckerDeployer`, `JBArbitrumSuckerDeployer`, `JBCCIPSuckerDeployer`) has its `configurator` set to the safe. This grants:
  - `setChainSpecificConstants()` -- Set bridge addresses, chain selectors, etc.
  - `configureSingleton()` -- Set the singleton sucker implementation used for clones.

These are called during deployment and are typically one-time operations.

## Deployment Configuration

The following hardcoded parameters affect admin privileges and protocol behavior:

### Revnet Stage Configurations

Each revnet (REV, NANA, BAN) is configured with `splitOperator: safeAddress()`. The split operator has limited powers within revnet rules:
- Can adjust how the reserved token split percentage is distributed among split recipients.
- Cannot change the overall split percentage, issuance schedule, or cashout tax rate (those are locked by revnet stages).

### Revnet Stages (Immutable After Deploy)

Revnet configurations are locked at deployment. Key parameters:

**$REV** (project 3): 3 stages, 90-day issuance cuts, 38% split, 10% cashout tax, auto-issuances across 4 chains.

**$NANA** (project 1): 1 stage, 360-day issuance cuts, 62% split, 10% cashout tax, auto-issuances across 4 chains.

**$BAN** (project 4): 3 stages, 60-day issuance cuts, 38% split, 10% cashout tax, 721 tiers with URI resolver. The split operator can adjust tiers, update metadata, mint, and increase discount percent (via `REVDeploy721TiersHookConfig` flags).

### Controller Omnichain Operator

The `JBController` is deployed with `omnichainRulesetOperator: address(_omnichainDeployer)`. This grants the omnichain deployer the ability to configure rulesets that mirror cross-chain project settings.

### Auto-Issuance Beneficiary

All auto-issuance entries across all revnets set `beneficiary: safeAddress()`. These are preminted token allocations that go to the Sphinx Safe.

## Post-Deployment

### Actions the Sphinx Safe Can Take

1. **Add price feeds** -- New currency pairs can be added to `JBPrices` (but existing pairs are immutable).
2. **Approve new controllers** -- Additional controller implementations can be whitelisted in `JBDirectory`.
3. **Approve new sucker deployers** -- New cross-chain bridge implementations can be added to `JBSuckerRegistry`.
4. **Mark addresses as feeless** -- Grant fee exemptions via `JBFeelessAddresses`.
5. **Adjust revnet splits** -- As split operator, redistribute reserved tokens within the allowed split percentage.
6. **Banny metadata** -- The `Banny721TokenUriResolver` is deployed with `safeAddress()` as its owner, allowing metadata updates (description, external URL, base URI).
7. **Banny 721 tiers** -- The split operator flags allow tier adjustments, metadata updates, minting, and discount percent increases for the Banny project.

### Actions That Cannot Be Taken Post-Deployment

1. **Replace price feeds** -- Once set, price feeds for a currency pair are immutable.
2. **Change revnet stages** -- Issuance schedules, split percentages, and cashout tax rates are locked at deployment.
3. **Change the JBController's omnichain operator** -- Set at construction, immutable.
4. **Reconfigure sucker deployer singletons** -- `configureSingleton()` is typically a one-time call.
5. **Change the fee percentage** -- The 2.5% fee is a constant in `JBMultiTerminal`, not configurable.
6. **Change the fee beneficiary** -- Hardcoded as project ID 1 in `JBMultiTerminal`.

### Unfinished Deployment Steps

- **CPN revnet** (project 2) -- `_deployCpnRevnet()` approves the REVDeployer but the actual revnet configuration is commented out (TODO placeholder).
- **Defifa** -- `_deployDefifa()` and `_deployDefifaRevnet()` are commented out entirely.
