# Audit Instructions -- deploy-all-v6

You are auditing the ecosystem deployment script for Juicebox V6. This repo contains no runtime contracts. The entire
attack surface is a single Foundry/Sphinx deployment script (`script/Deploy.s.sol`, ~2,230 lines) that deploys and
wires the current canonical rollout across the configured chains, plus 21 fork test files that exercise the deployed
ecosystem.

Read [ARCHITECTURE.md](./ARCHITECTURE.md) for structure. Read [RISKS.md](./RISKS.md) for known risks. Read [ADMINISTRATION.md](./ADMINISTRATION.md) for post-deployment privileges. Then come back here.

## Scope

**In scope:**
```
script/Deploy.s.sol        # The deployment script (~2,230 lines)
test/fork/*.t.sol          # 21 fork integration tests (~13,100 lines total)
foundry.toml               # Build configuration
package.json               # Dependency versions
```

**Out of scope:** Everything in `node_modules/` and `lib/` (dependency source code). The deployed contracts themselves are audited separately -- see the ecosystem [AUDIT_INSTRUCTIONS.md](../AUDIT_INSTRUCTIONS.md).

**What you are looking for:** Deployment misconfigurations that would make the deployed ecosystem behave differently than intended. Wrong addresses, wrong parameters, wrong ordering, missing wiring steps, or dangling permissions.

## The Deployment in 90 Seconds

The `Deploy` contract inherits from both Foundry's `Script` and Sphinx's `Sphinx` base. A single `deploy()` function, gated by the `sphinx` modifier, deploys everything in sequence:

1. **Phase 01 -- Core Protocol**: `JBPermissions`, `JBProjects` (creates project #1), `JBDirectory`, `JBSplits`, `JBRulesets`, `JBPrices`, `JBTokens`, `JBERC20`, `JBFundAccessLimits`, `JBFeelessAddresses`, `JBTerminalStore`, `JBMultiTerminal`. All receive `safeAddress()` as owner.

2. **Phase 02 -- Address Registry**: `JBAddressRegistry`. No owner, no wiring.

3. **Phase 03a -- 721 Hook**: `JB721TiersHookStore`, `JB721TiersHook` (implementation), `JB721TiersHookDeployer`, `JB721TiersHookProjectDeployer`. The deployer clones the implementation for each project.

4. **Phase 03b -- Uniswap V4 Router Hook**: `JBUniswapV4Hook`. The hook address is mined with `HookMiner.find(...)` so its permission bits satisfy the Uniswap V4 hook flags.

5. **Phase 03c -- Buyback Hook**: `JBBuybackHookRegistry` and `JBBuybackHook`. Registry sets the hook as default. The buyback hook receives the deployed `JBUniswapV4Hook` as its oracle hook.

6. **Phase 03d -- Router Terminal**: `JBRouterTerminalRegistry` and `JBRouterTerminal`. Registry sets the terminal as default. Terminal receives chain-specific WETH, V3 Factory, and V4 PoolManager.

7. **Phase 03e -- LP Split Hook**: `JBUniswapV4LPSplitHook` and `JBUniswapV4LPSplitHookDeployer`. The implementation is wired to the same V4 router hook, chain-specific PoolManager and PositionManager, and the global address registry.

8. **Phase 03f -- Cross-Chain Suckers**: Deploys sucker deployers and singletons for Optimism, Base, Arbitrum (native bridges) and CCIP (all pairings). Each deployer gets chain-specific bridge addresses via `setChainSpecificConstants()`. All are pushed to `_preApprovedSuckerDeployers[]`, then batch-approved when `JBSuckerRegistry` is created.

9. **Phase 04 -- Omnichain Deployer**: `JBOmnichainDeployer`. Depends on sucker registry and 721 hook deployer.

10. **Phase 05 -- Periphery**: Chainlink price feeds (ETH/USD, USDC/USD), `JBMatchingPriceFeed` (ETH=NATIVE_TOKEN), four deadline contracts, and finally `JBController`. The controller depends on the omnichain deployer address. `JBDirectory.setIsAllowedToSetFirstController()` is called here.

11. **Phase 06 -- Croptop**: Creates project #2 (CPN). Deploys `CTPublisher`, `CTDeployer`, `CTProjectOwner`.

12. **Phase 07 -- Revnet**: Creates project #3 (REV). Deploys `REVLoans`, `REVDeployer`. Configures the $REV revnet with 3 stages, auto-issuances, and suckers.

13. **Phase 08 -- Existing Project Configuration**: Configures project #2 (CPN) as a revnet. Configures project #1 (NANA/fee project) as a revnet with 1 stage.

14. **Phase 09 -- Banny**: Deploys `Banny721TokenUriResolver` with inline SVG data. Creates project #4 (BAN) as a revnet with 3 stages and 4 NFT tiers.

Not deployed by this script: `JBOwnable` and Defifa.

## What Each Deployed Contract Does

This table maps every deployed contract to its role. Use it to understand what a misconfiguration would break.

| Contract | Role | Critical Constructor Args |
|----------|------|--------------------------|
| `ERC2771Forwarder` | Meta-transaction support | `name: "Juicebox"` |
| `JBPermissions` | 256-bit packed permission system | `trustedForwarder` |
| `JBProjects` | ERC-721 project NFTs. Auto-creates project #1 for `initialOwner`. | `initialOwner: safeAddress()` |
| `JBDirectory` | Routes projects to terminals/controllers | `initialOwner: safeAddress()` |
| `JBSplits` | Split distribution storage | `directory` |
| `JBRulesets` | Ruleset lifecycle, linked list | `directory` |
| `JBPrices` | Price feed registry. Feeds are immutable once set. | `initialOwner: safeAddress()` |
| `JBERC20` | Cloneable ERC-20 implementation | None |
| `JBTokens` | Token management (credits + ERC-20) | `erc20: JBERC20 clone source` |
| `JBFundAccessLimits` | Payout limits and surplus allowances | `directory` |
| `JBFeelessAddresses` | Fee-exempt address registry | `initialOwner: safeAddress()` |
| `JBTerminalStore` | Bookkeeping: balances, surplus, bonding curve | `directory, rulesets, prices` |
| `JBMultiTerminal` | Multi-token payment terminal. Holds all funds. | `permissions, projects, splits, store, tokens, feelessAddresses, permit2` |
| `JBController` | Project lifecycle orchestrator | `omnichainRulesetOperator: _omnichainDeployer` |
| `JBAddressRegistry` | Deployer verification registry | None |
| `JB721TiersHookStore` | NFT tier storage | None |
| `JB721TiersHook` | NFT hook implementation (cloned per project) | `directory, permissions, prices, rulesets, hookStore, splits` |
| `JB721TiersHookDeployer` | Deploys 721 hook clones | `hook721, hookStore, addressRegistry` |
| `JB721TiersHookProjectDeployer` | Creates projects with 721 hooks | `directory, permissions, hookDeployer` |
| `JBUniswapV4Hook` | Canonical Uniswap V4 router/oracle hook | `poolManager (chain-specific), directory, prices, tokens` |
| `JBBuybackHookRegistry` | Registry of buyback hooks | `initialOwner: safeAddress()` |
| `JBBuybackHook` | DEX buyback on payment | `poolManager (chain-specific), oracleHook: JBUniswapV4Hook` |
| `JBUniswapV4LPSplitHook` | LP split hook implementation | `poolManager (chain-specific), positionManager (chain-specific), oracleHook: JBUniswapV4Hook` |
| `JBUniswapV4LPSplitHookDeployer` | Clone deployer for LP split hooks | `hook: JBUniswapV4LPSplitHook, registry: JBAddressRegistry` |
| `JBRouterTerminalRegistry` | Registry of router terminals | `initialOwner: safeAddress()` |
| `JBRouterTerminal` | Payment routing via Uniswap | `weth, v3Factory, poolManager (all chain-specific)` |
| `JBSuckerRegistry` | Sucker deployer whitelist | `initialOwner: safeAddress()` |
| Sucker deployers (OP, Base, Arb, CCIP) | Deploy sucker clones per chain pair | Bridge addresses (chain-specific) |
| Sucker singletons (OP, Base, Arb, CCIP) | Implementation contracts for clone pattern | `deployer, directory, permissions, tokens` |
| `JBOmnichainDeployer` | Multi-chain project deployment | `suckerRegistry, hookDeployer, permissions, projects` |
| `JBChainlinkV3PriceFeed` | ETH/USD and USDC/USD price feeds | `feed: Chainlink aggregator, threshold` |
| `JBChainlinkV3SequencerPriceFeed` | L2 feeds with sequencer check | `feed, threshold, sequencerFeed, gracePeriod` |
| `JBMatchingPriceFeed` | Returns 1:1 (ETH == NATIVE_TOKEN) | None |
| `JBDeadline{3Hours,1Day,3Days,7Days}` | Approval hooks with time delays | None |
| `CTPublisher` | Croptop NFT publishing | `directory, permissions, cpnProjectId` |
| `CTDeployer` | Croptop project deployer | `permissions, projects, hookDeployer, ctPublisher, suckerRegistry` |
| `CTProjectOwner` | Croptop project ownership proxy | `permissions, projects, ctPublisher` |
| `REVLoans` | Lending against project tokens | `controller, projects, revId: _revProjectId` |
| `REVDeployer` | Revnet lifecycle deployer | `controller, suckerRegistry, revProjectId, hookDeployer, ctPublisher, buybackRegistry, revLoans` |
| `Banny721TokenUriResolver` | On-chain SVG renderer for Banny NFTs | `bannyBody SVG, defaultNecklace SVG, ...` |

## Permission Grants During Deployment

These are the permission/ownership actions taken during the script. Each is a potential misconfiguration vector.

| Action | Line | What It Does | What Could Go Wrong |
|--------|------|-------------|-------------------|
| `_directory.setIsAllowedToSetFirstController(_controller, true)` | 1329 | Allows `_controller` to be set as first controller for new projects | If called with wrong address, no projects can launch, or a malicious controller gets whitelist access |
| `_buybackRegistry.setDefaultHook(_buybackHook)` | 740 | Sets default buyback hook | Wrong hook = all projects using default get broken buyback |
| `_routerTerminalRegistry.setDefaultTerminal(_routerTerminal)` | 798 | Sets default router terminal | Wrong terminal = routing payments fail |
| `_suckerRegistry.allowSuckerDeployer(...)` | 877 | Whitelists sucker deployers | Missing deployer = that bridge pair is unavailable. Extra deployer = potential unauthorized bridge |
| `opDeployer.setChainSpecificConstants(...)` | 908+ | Sets bridge addresses per chain | Wrong bridge = cross-chain messages go to wrong contract |
| `opDeployer.configureSingleton(singleton)` | 921+ | Sets clone source for sucker deployer | Wrong singleton = all suckers for that pair are broken |
| `_prices.addPriceFeedFor(...)` | 2179 | Registers immutable price feeds | Wrong feed = permanent price miscalculation. Cannot be changed after set. |
| `_projects.createFor(safeAddress())` | 2189 | Creates projects | Wrong owner = project lost |
| `_projects.approve(_revDeployer, projectId)` | 1557, 1816, 1893 | Grants NFT transfer approval for REVDeployer to configure projects | If REVDeployer is malicious or wrong address, project ownership can be stolen |

## Chain-Specific Address Verification

Every hardcoded address in `_setupChainAddresses()` and the price feed functions must be verified against canonical sources. Here is the complete list.

### External Protocol Addresses

| Chain | Chain ID | WETH | Uni V3 Factory | Uni V4 PoolManager |
|-------|----------|------|-----------------|-------------------|
| Ethereum | 1 | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` | `0x1F98431c8aD98523631AE4a59f267346ea31F984` | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Sepolia | 11155111 | `0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9` | `0x0227628f3F023bb0B980b67D528571c95c6DaC1c` | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Optimism | 10 | `0x4200000000000000000000000000000000000006` | `0x1F98431c8aD98523631AE4a59f267346ea31F984` | `0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3` |
| OP Sepolia | 11155420 | `0x4200000000000000000000000000000000000006` | `0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24` | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Base | 8453 | `0x4200000000000000000000000000000000000006` | `0x33128a8fC17869897dcE68Ed026d694621f6FDfD` | `0x498581fF718922c3f8e6A244956aF099B2652b2b` |
| Base Sepolia | 84532 | `0x4200000000000000000000000000000000000006` | `0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24` | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` |
| Arbitrum | 42161 | `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1` | `0x1F98431c8aD98523631AE4a59f267346ea31F984` | `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32` |
| Arb Sepolia | 421614 | `0x980B62Da83eFf3D4576C647993b0c1D7faf17c73` | `0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e` | `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317` |

### Chainlink ETH/USD Feed Addresses

| Chain | Feed Address | Type | Staleness Threshold |
|-------|-------------|------|-------------------|
| Ethereum | `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419` | Standard | 3600s |
| Sepolia | `0x694AA1769357215DE4FAC081bf1f309aDC325306` | Standard | 3600s |
| Optimism | `0x13e3Ee699D1909E989722E753853AE30b17e08c5` | + Sequencer | 3600s |
| OP Sepolia | `0x61Ec26aA57019C486B10502285c5A3D4A4750AD7` | Standard | 3600s |
| Base | `0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70` | + Sequencer | 3600s |
| Base Sepolia | `0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1` | Standard | 3600s |
| Arbitrum | `0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612` | + Sequencer | 3600s |
| Arb Sepolia | `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165` | Standard | 3600s |

### L2 Sequencer Uptime Feed Addresses

| Chain | Sequencer Feed | Grace Period |
|-------|---------------|-------------|
| Optimism | `0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389` | 3600s |
| Base | `0xBCF85224fc0756B9Fa45aA7892530B47e10b6433` | 3600s |
| Arbitrum | `0xFdB631F5EE196F0ed6FAa767959853A9F217697D` | 3600s |

### USDC Token and Feed Addresses

| Chain | USDC Token | USDC/USD Feed | Type | Threshold |
|-------|-----------|---------------|------|-----------|
| Ethereum | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6` | Standard | 86400s |
| Sepolia | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` | `0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E` | Standard | 86400s |
| Optimism | `0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85` | `0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3` | + Sequencer | 86400s |
| OP Sepolia | `0x5fd84259d66Cd46123540766Be93DFE6D43130D7` | `0x6e44e50E3cc14DD16e01C590DC1d7020cb36eD4C` | Standard | 86400s |
| Base | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` | + Sequencer | 86400s |
| Base Sepolia | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165` | Standard | 86400s |
| Arbitrum | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | `0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3` | + Sequencer | 86400s |
| Arb Sepolia | `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d` | `0x0153002d20B96532C639313c2d54c3dA09109309` | Standard | 86400s |

**Verification note**: Base Sepolia reuses `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165` for both ETH/USD and USDC/USD feeds. This is likely a placeholder testnet feed. Verify this is intentional.

### Bridge Addresses (Suckers)

Verify all OP Messenger, OP Standard Bridge, Arbitrum Inbox, Arbitrum Gateway Router, and CCIP Router addresses against canonical bridge documentation. The script has distinct mainnet and testnet addresses for each.

## Verification Checklist

After reviewing the script, verify:

- [ ] Every hardcoded external address matches the canonical deployment for that chain.
- [ ] Every constructor passes the intended arguments (no swapped parameters).
- [ ] Price feeds use the correct variant: `JBChainlinkV3SequencerPriceFeed` for L2 mainnets, `JBChainlinkV3PriceFeed` for L1 and testnets.
- [ ] Price feed staleness thresholds match Chainlink heartbeat intervals.
- [ ] All sucker deployers for the current chain are created and pushed to the pre-approved array.
- [ ] `setChainSpecificConstants()` is called for every sucker deployer with correct per-chain bridge addresses.
- [ ] `configureSingleton()` is called for every sucker deployer after singleton creation.
- [ ] Project IDs 1-4 are created in the expected order with the expected owners.
- [ ] `_projects.approve()` is called for each project before `_revDeployer.deployFor()`.
- [ ] Revnet stage configurations match intended economic parameters (issuance, cut frequency, cut percent, cashout tax, splits).
- [ ] Auto-issuance amounts and beneficiaries are correct for each chain.
- [ ] The `JBController` receives `_omnichainDeployer` as its omnichain operator.
- [ ] `setIsAllowedToSetFirstController` is called for the correct controller address.
- [ ] No dangling approvals or permissions exist after deployment completes.
- [ ] Release claims match the script: the canonical rollout includes the V4 router/oracle stack and LP split hook deployer, while `JBOwnable` and Defifa remain out of scope.
- [ ] The CPN revnet (project #2) is correctly configured via `_deployCpnRevnet()` in Phase 08.
- [ ] Defifa is intentionally excluded and will be deployed separately.

## Revnet Economic Parameters

These are hardcoded and immutable after deployment. Verify each value against the intended economic design.

### $REV (Project 3) -- 3 Stages

| Parameter | Stage 1 | Stage 2 | Stage 3 |
|-----------|---------|---------|---------|
| `startsAtOrAfter` | 1740089444 (Feb 20, 2025) | +720 days | +3600 days |
| `initialIssuance` | 10,000 tokens/ETH | 1 (inherit) | 0 (no issuance) |
| `issuanceCutFrequency` | 90 days | 30 days | 0 |
| `issuanceCutPercent` | 38% | 7% | 0 |
| `cashOutTaxRate` | 10% (1000/10000) | 10% | 10% |
| `splitPercent` | 38% (3800/10000) | 38% | 38% |
| `autoIssuances` | 4 chains | 1 (1.55M to mainnet) | none |

### $NANA (Project 1) -- 1 Stage

| Parameter | Stage 1 |
|-----------|---------|
| `startsAtOrAfter` | 1740089444 |
| `initialIssuance` | 10,000 tokens/ETH |
| `issuanceCutFrequency` | 360 days |
| `issuanceCutPercent` | 38% |
| `cashOutTaxRate` | 10% |
| `splitPercent` | 62% (6200/10000) |
| `autoIssuances` | 4 chains |

### $BAN (Project 4) -- 3 Stages + 721 Tiers

| Parameter | Stage 1 | Stage 2 | Stage 3 |
|-----------|---------|---------|---------|
| `startsAtOrAfter` | 1740435044 | +360 days | +1200 days |
| `initialIssuance` | 10,000 tokens/ETH | 1 (inherit) | 0 |
| `issuanceCutFrequency` | 60 days | 21 days | 0 |
| `issuanceCutPercent` | 38% | 7% | 0 |
| `cashOutTaxRate` | 10% | 10% | 10% |
| `splitPercent` | 38% | 38% | 0% |
| `autoIssuances` | 4 chains | 1 (1M to mainnet) | none |
| 721 Tiers | 4 tiers at 1, 0.1, 0.01, 0.0001 ETH | | |

## How to Run Fork Tests

The repo includes 21 fork tests in `test/fork/`. These deploy a fresh JB core on forked Ethereum mainnet (block 21700000+) and exercise the full stack.

```bash
# Install dependencies
npm install
forge install

# Set up environment
cp .env.example .env
# Edit .env: set RPC_ETHEREUM_MAINNET to a mainnet RPC URL

# Build
forge build

# Run all fork tests
forge test --match-path "test/fork/*" -vvv

# Run a specific test
forge test --match-contract EcosystemForkTest -vvv
forge test --match-contract FullStackForkTest -vvv
forge test --match-contract BuybackRouterForkTest -vvv
forge test --match-contract CrossCurrencyForkTest -vvv
forge test --match-contract LPBuybackInteropForkTest -vvv
forge test --match-contract USDCEcosystemForkTest -vvv
forge test --match-contract USDCRevnetForkTest -vvv

# Run with gas reporting
forge test --match-path "test/fork/*" --gas-report
```

**Note**: Fork tests require a mainnet RPC endpoint. They fork at a fixed block for determinism. The `foundry.toml` configures `optimizer = false` and `via_ir = true` -- builds are slow but bytecode matches production deployment configuration.

### What the Fork Tests Cover

| Test File | What It Exercises |
|-----------|------------------|
| `ApprovalHookFork.t.sol` | Approval hook timing and ruleset transitions |
| `BuybackRouterFork.t.sol` | Buyback hook + router terminal integration |
| `CrossCurrencyFork.t.sol` | Multi-currency operations with price feed conversions |
| `DeployFork.t.sol` | Deployment script execution on fork |
| `DeployFullStack.t.sol` | Full deployment stack verification |
| `DeployScriptVerification.t.sol` | Post-deployment state verification |
| `EcosystemFork.t.sol` | Multi-stage revnet with buyback hook, 721 tier splits, LP-split hook, payments via terminal + V4 router |
| `FullStackFork.t.sol` | Full deployment stack: core + hooks + revnets + loans |
| `HookCompositionFork.t.sol` | Multi-hook composition and interaction |
| `LPBuybackInteropFork.t.sol` | LP split hook + buyback hook interoperability |
| `PayoutReentrancyFork.t.sol` | Reentrancy during payout distribution |
| `PriceFeedFailureFork.t.sol` | Price feed failure and staleness handling |
| `ReservedInflationFork.t.sol` | Reserved token inflation on cashout values |
| `ResumeDeployFork.t.sol` | Resuming partial deployments |
| `SuckerBuybackFork.t.sol` | Sucker + buyback hook interaction |
| `SuckerEndToEndFork.t.sol` | End-to-end sucker bridging flow |
| `TestFeeProcessingCascade.t.sol` | Fee processing cascade and held fees |
| `TestMultiCurrencyPayout.t.sol` | Multi-currency payout distribution |
| `TestTerminalMigration.t.sol` | Terminal migration lifecycle |
| `USDCEcosystemFork.t.sol` | USDC-denominated ecosystem operations |
| `USDCRevnetFork.t.sol` | USDC-denominated revnet configuration |

### What the Fork Tests Do NOT Cover

- Actual Sphinx proposal execution mechanics.
- Multi-chain deployment (tests run on forked Ethereum mainnet only).
- Cross-chain sucker operations (no L2 forks).
- The exact `Deploy.s.sol` script (tests recreate the ecosystem manually, not via the script).
- Deployment ordering failures or partial deployment recovery.
- Testnet-specific address correctness.
- CCIP sucker bridge operations.

## Post-Deployment Verification Commands

After deployment, use these `cast call` commands to verify on-chain state. Replace `$RPC` with the chain's RPC URL and substitute the actual deployed addresses for each placeholder (e.g., `$DIRECTORY`, `$CONTROLLER`).

### 1. Directory returns the correct controller for a project

```bash
# controllerOf(uint256 projectId) returns (address)
# Check project 1 (NANA/fee project)
cast call $DIRECTORY "controllerOf(uint256)(address)" 1 --rpc-url $RPC

# Check all four projects
for id in 1 2 3 4; do
  echo "Project $id controller:"
  cast call $DIRECTORY "controllerOf(uint256)(address)" $id --rpc-url $RPC
done
```

Expected: all projects return `$CONTROLLER`.

### 2. Controller is allowed to set first controller

```bash
# isAllowedToSetFirstController(address) returns (bool)
cast call $DIRECTORY "isAllowedToSetFirstController(address)(bool)" $CONTROLLER --rpc-url $RPC
```

Expected: `true`.

### 3. Terminal is registered for each project

```bash
# isTerminalOf(uint256 projectId, address terminal) returns (bool)
cast call $DIRECTORY "isTerminalOf(uint256,address)(bool)" 1 $TERMINAL --rpc-url $RPC

# List all terminals for a project
cast call $DIRECTORY "terminalsOf(uint256)(address[])" 1 --rpc-url $RPC
```

Expected: `isTerminalOf` returns `true` for the deployed `JBMultiTerminal`.

### 4. Project ownership

```bash
# ownerOf(uint256 tokenId) returns (address)  (ERC-721)
for id in 1 2 3 4; do
  echo "Project $id owner:"
  cast call $PROJECTS "ownerOf(uint256)(address)" $id --rpc-url $RPC
done
```

Expected: all projects owned by the Sphinx Safe (`$SAFE`), except projects configured as revnets (which transfer ownership to the `REVDeployer` during `deployFor` and then to the revnet's designated owner).

### 5. Price feed addresses

```bash
# priceFeedFor(uint256 projectId, uint256 pricingCurrency, uint256 unitCurrency) returns (address)
# projectId=0 for protocol-default feeds

# ETH(1) priced in NATIVE_TOKEN (uint256(uint160(0x...EEEe)))
NATIVE_CURRENCY=$(cast --to-uint256 0x000000000000000000000000000000000000EEEe)
cast call $PRICES "priceFeedFor(uint256,uint256,uint256)(address)" 0 1 $NATIVE_CURRENCY --rpc-url $RPC

# USD(2) priced in NATIVE_TOKEN
cast call $PRICES "priceFeedFor(uint256,uint256,uint256)(address)" 0 2 $NATIVE_CURRENCY --rpc-url $RPC

# USD(2) priced in USDC token
USDC_CURRENCY=$(cast --to-uint256 $USDC_TOKEN)
cast call $PRICES "priceFeedFor(uint256,uint256,uint256)(address)" 0 2 $USDC_CURRENCY --rpc-url $RPC
```

Expected: each returns the corresponding deployed price feed contract (not `address(0)`).

### 6. Price feed liveness

```bash
# Verify that a Chainlink feed returns a current price (not stale, not zero)
cast call $ETH_USD_FEED "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url $RPC
```

Expected: `answer > 0`, `updatedAt` within the staleness threshold of `block.timestamp`.

### 7. Buyback hook and router terminal defaults

```bash
# defaultHook() returns (address)
cast call $BUYBACK_REGISTRY "defaultHook()(address)" --rpc-url $RPC

# defaultTerminal() returns (address)
cast call $ROUTER_TERMINAL_REGISTRY "defaultTerminal()(address)" --rpc-url $RPC
```

Expected: returns the deployed `JBBuybackHook` and `JBRouterTerminal` respectively.

### 8. Sucker deployer whitelist

```bash
# suckerDeployerIsAllowed(address deployer) returns (bool)
cast call $SUCKER_REGISTRY "suckerDeployerIsAllowed(address)(bool)" $OP_SUCKER_DEPLOYER --rpc-url $RPC
cast call $SUCKER_REGISTRY "suckerDeployerIsAllowed(address)(bool)" $BASE_SUCKER_DEPLOYER --rpc-url $RPC
cast call $SUCKER_REGISTRY "suckerDeployerIsAllowed(address)(bool)" $ARB_SUCKER_DEPLOYER --rpc-url $RPC
# Repeat for each CCIP sucker deployer
```

Expected: `true` for every deployer that should be whitelisted on that chain.

### 9. Contract ownership

```bash
# Verify Sphinx Safe owns all ownable contracts
for addr in $DIRECTORY $PRICES $FEELESS $BUYBACK_REGISTRY $ROUTER_TERMINAL_REGISTRY $SUCKER_REGISTRY; do
  echo "Owner of $addr:"
  cast call $addr "owner()(address)" --rpc-url $RPC
done
```

Expected: all return `$SAFE` (the Sphinx Safe address).

### 10. Cross-chain project ID consistency

Run the same `ownerOf` calls on every chain and confirm project IDs 1-4 exist and map to the same logical project (same owner, same controller).

```bash
# On each chain:
for id in 1 2 3 4; do
  echo "Project $id owner:"
  cast call $PROJECTS "ownerOf(uint256)(address)" $id --rpc-url $RPC
  echo "Project $id controller:"
  cast call $DIRECTORY "controllerOf(uint256)(address)" $id --rpc-url $RPC
done
```

---

## Previous Audit Findings

No prior formal audit with finding IDs has been conducted for this deployment script. Known risk vectors are documented in [RISKS.md](./RISKS.md), which covers deployment ordering risks, oracle/price feed risks, cross-chain consistency risks, configuration risks, and catastrophic misconfiguration scenarios.

---

## Compiler and Version Info

These values are from [`foundry.toml`](./foundry.toml):

| Setting | Value |
|---------|-------|
| Solidity version | `0.8.26` |
| EVM target | `cancun` |
| Optimizer | `false` (disabled in default profile) |
| `via_ir` | `true` |
| Optimizer (CI sizes profile) | `true`, 200 runs |
| Fuzz runs | 4096 |
| Invariant runs | 1024, depth 100 |
| Libs | `node_modules`, `lib` |

**Note**: The default profile compiles with `optimizer = false` and `via_ir = true`. This means bytecode is generated through the IR pipeline without optimization passes -- builds are slower but bytecode matches the production deployment configuration. The `ci_sizes` profile enables the optimizer at 200 runs for size checks only.

---

## How to Report Findings

For each finding:

1. **Title** -- severity prefix (CRITICAL/HIGH/MEDIUM/LOW)
2. **Location** -- file path and line numbers in `Deploy.s.sol`
3. **Description** -- what is wrong
4. **Impact** -- what breaks (which chains, which contracts, is it permanent?)
5. **Proof** -- the specific line(s) and what the correct value should be
6. **Fix** -- the minimal code change

**Severity guide for deployment scripts:**
- **CRITICAL**: Wrong address or parameter that causes permanent fund loss or protocol insolvency. Cannot be fixed post-deployment.
- **HIGH**: Wrong configuration that permanently breaks a subsystem (e.g., wrong price feed, wrong bridge address). Requires full redeployment.
- **MEDIUM**: Misconfiguration that degrades functionality but has a workaround (e.g., missing feeless address, suboptimal staleness threshold).
- **LOW**: Cosmetic, informational, or testnet-only issues.
