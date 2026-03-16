# deploy-all-v6 -- Risks

Deployment-specific vulnerability vectors for auditors. This repo deploys the entire Juicebox V6 ecosystem via a single Sphinx-orchestrated script (`script/Deploy.s.sol`, ~1,600 lines). It has no runtime contracts of its own -- all risk lives in the deployment configuration itself.

For protocol-level risks, see the ecosystem [RISKS.md](../RISKS.md).

## Trust Assumptions

1. **Sphinx Platform** -- Deployment is orchestrated via Sphinx proposals. Sphinx controls execution order, gas management, and atomicity per chain. The Sphinx Safe (`safeAddress()`) receives ownership of every deployed contract.
2. **Hardcoded Addresses** -- External contract addresses (Uniswap V4 PoolManager, Uniswap V3 Factory, WETH, Chainlink feeds, bridge contracts, CCIP routers, Permit2) are hardcoded per chain in the script. A wrong address means the deployed contract is permanently misconfigured.
3. **Constructor Parameters** -- All initialization values (salts, prices, revnet stages, auto-issuance amounts, tier configs) are baked into the script. Many parameters are immutable after deployment -- constructor errors cannot be patched.
4. **Deployment Ordering** -- Contracts deploy in dependency order within a single `deploy()` call. Between Sphinx proposal submission and execution, no intermediate state is exploitable because contracts are not usable until the full wiring phase completes. However, a partially executed proposal (Sphinx failure mid-execution) leaves the ecosystem in an inconsistent state.
5. **Permit2** -- Hardcoded to canonical address `0x000000000022D473030F116dDEE9F6B43aC78BA3`. Assumed deployed on all target chains.

## Deployment Ordering Risks

| Risk | Severity | Description | Mitigation |
|------|----------|-------------|------------|
| Partial deployment | HIGH | If Sphinx execution halts mid-proposal (gas, revert, platform failure), core contracts may exist without wiring. Example: `JBDirectory` deployed but `setIsAllowedToSetFirstController` never called -- no projects can launch. | Sphinx atomic execution per chain. On failure, re-propose the full script. Contracts are not usable without wiring. |
| Controller deploys after omnichain deployer | MEDIUM | `JBController` constructor takes `omnichainRulesetOperator: address(_omnichainDeployer)` (line 930). If the omnichain deployer address changes between phases, the controller is permanently misconfigured. | Single-proposal atomicity ensures deterministic ordering. Verify the `_omnichainDeployer` address in the controller's constructor after deployment. |
| Sucker deployers before registry | LOW | All sucker deployers (OP, Base, Arb, CCIP) are deployed before `JBSuckerRegistry` (lines 551-568). Deployers are pushed to `_preApprovedSuckerDeployers[]`, then batch-approved on registry creation. If any deployer creation reverts, the array is incomplete. | The `if (_preApprovedSuckerDeployers.length != 0)` guard prevents empty-array revert but means a silently missing deployer is possible. |
| Project ID determinism | HIGH | Project IDs are determined by deployment order: project 1 (fee project, auto-created), project 2 (CPN, line 1070), project 3 (REV, line 1093), project 4 (BAN, created by `deployFor` with `revnetId: 0`). If any `createFor` call is reordered or another project is inserted, all subsequent project IDs shift. Every revnet configuration, sucker config, and cross-reference hardcodes these IDs. | Verify project IDs match expected values after deployment. `REVLoans` constructor takes `revId: _revProjectId` -- if this ID is wrong, the loans contract references a non-existent or wrong project. |

## Oracle and Price Feed Risks

| Risk | Severity | Description | Mitigation |
|------|----------|-------------|------------|
| Wrong Chainlink feed address | CRITICAL | ETH/USD and USDC/USD feeds are hardcoded per chain (lines 941-1057). A wrong address passes a non-Chainlink contract to `JBChainlinkV3PriceFeed`, which calls `latestRoundData()`. If the address is a contract that happens to implement that function, it could return arbitrary prices. If not, it reverts -- DoS on all multi-currency operations. | Cross-reference every Chainlink address against the official Chainlink feeds directory for each chain. Feeds are immutable once set in `JBPrices`. |
| Missing sequencer feed on L2 | HIGH | Optimism, Base, and Arbitrum mainnets use `JBChainlinkV3SequencerPriceFeed` with L2 sequencer uptime feeds (lines 954-989). Testnets use `JBChainlinkV3PriceFeed` without sequencer checks. If a mainnet address is accidentally given the non-sequencer variant, L2 sequencer downtime will not trigger price rejections. | Verify that mainnet L2 chains use `JBChainlinkV3SequencerPriceFeed` and that the sequencer feed addresses match canonical Chainlink L2 sequencer feeds. |
| Staleness threshold mismatch | MEDIUM | ETH/USD feeds use `3600 seconds` threshold. USDC/USD feeds use `86_400 seconds`. If the Chainlink ETH/USD feed on a chain actually updates less frequently than hourly (unlikely but possible during congestion), operations revert. | Verify Chainlink heartbeat intervals match configured thresholds for each chain. |
| JBMatchingPriceFeed (1:1) for ETH/NATIVE_TOKEN | LOW | Line 891: `JBMatchingPriceFeed` returns 1:1 for ETH abstract currency to NATIVE_TOKEN concrete currency. This is correct by definition but only if the pair is correct. If accidentally set for USD/NATIVE_TOKEN, all USD-denominated operations compute wrong values. | Verify the three `addPriceFeedFor` calls in `_deployPeriphery()` set the correct currency pairs. |

## Cross-Chain Consistency Risks

| Risk | Severity | Description | Mitigation |
|------|----------|-------------|------------|
| Non-deterministic addresses across chains | HIGH | Sphinx uses CREATE2 from its deterministic deployer. Contract addresses depend on `(deployer, salt, initCodeHash)`. Different bytecode across chains (due to chain-specific constructor args like `_weth`, `_poolManager`, `_v3Factory`) means different addresses. Core contracts use the same salt (`CORE_DEPLOYMENT_NONCE = 6`) but chain-specific addresses in constructors change `initCodeHash`. | Sphinx handles cross-chain determinism. However, sucker deployers, buyback hooks, and router terminals have chain-specific constructor args and WILL have different addresses per chain. Verify that cross-chain references (sucker pairs) use the correct per-chain addresses. |
| Chain-specific constants per sucker | HIGH | Each sucker deployer calls `setChainSpecificConstants()` with bridge addresses that differ by chain and by mainnet/testnet (lines 570-846). Wrong bridge address = bridge operations fail or, worse, route to a malicious contract. | Verify every bridge address: OP Messenger, OP Standard Bridge, Arbitrum Inbox, Arbitrum Gateway Router, CCIP Router, and CCIP chain selectors. Each has a mainnet and testnet variant. |
| CCIP chain selector mismatch | HIGH | CCIP sucker deployers use `CCIPHelper.selectorOfChain(remoteChainId)` to look up CCIP selectors (lines 856-860). If `CCIPHelper` has a wrong mapping, CCIP messages route to the wrong destination. | Verify `CCIPHelper` mappings against official CCIP documentation. |

## Hardcoded Address Risks

| Risk | Severity | Description | Affected Lines |
|------|----------|-------------|----------------|
| Permit2 | LOW | `0x000000000022D473030F116dDEE9F6B43aC78BA3` -- canonical, same on all chains. | 146 |
| WETH | HIGH | Different per chain. 7 distinct addresses across 8 chains. L2 chains share `0x4200000000000000000000000000000000000006`. | 372-419 |
| Uniswap V3 Factory | HIGH | Different per chain. Used by `JBRouterTerminal` for swap routing. | 372-419 |
| Uniswap V4 PoolManager | HIGH | Different per chain except testnets sharing `0x000000000004444c5dc75cB358380D2e3dE08A90`. Used by `JBBuybackHook` and `JBRouterTerminal`. | 372-419 |
| Chainlink ETH/USD feeds | CRITICAL | 8 distinct addresses, one per chain. | 941-998 |
| Chainlink USDC/USD feeds | CRITICAL | 8 distinct addresses. | 1006-1057 |
| L2 Sequencer feeds | HIGH | 3 addresses (OP, Base, Arb mainnets). | 957, 972, 987 |
| USDC token addresses | HIGH | 8 distinct addresses. | 1007-1051 |
| OP Messenger/Bridge (L1) | HIGH | Mainnet and Sepolia variants for both Optimism and Base. 4 addresses each side. | 583-660 |
| OP Messenger/Bridge (L2) | LOW | Canonical predeploys `0x42...07` and `0x42...10`. | 619-620, 687-688 |
| Arbitrum Inbox/Gateway | HIGH | Uses `ARBAddresses` library constants. | 718-753 |

## Constructor Parameter Risks

| Risk | Severity | Description |
|------|----------|-------------|
| Buyback hook with `oracleHook: address(0)` | MEDIUM | Line 515: `JBBuybackHook` receives `IHooks(address(0))` as its oracle hook. This means TWAP queries go to `address(0)`, which must be mocked for testing. In production, the buyback hook will use spot prices (no TWAP protection) until pools are created with proper hook addresses. Payments are vulnerable to single-block price manipulation during this window. |
| Revnet start times in the past | MEDIUM | `REV_START_TIME = 1_740_089_444` (Feb 20, 2025), `NANA_START_TIME = 1_740_089_444`, `BAN_START_TIME = 1_740_435_044`. If deployed after these timestamps, the first ruleset stage is already active and issuance decay has already been ticking. Auto-issuances may calculate differently than expected. |
| Auto-issuance amounts | HIGH | Lines 212-229: Per-chain auto-issuance amounts for REV, NANA, and BAN are large uint104 constants. These represent preminted token allocations. If any amount is wrong, tokens are permanently minted to the wrong quantity. Cannot be corrected post-deployment. |
| CPN revnet not configured | MEDIUM | `_deployCpnRevnet()` (line 1224) approves `_revDeployer` for project 2 but the actual configuration is commented out. Project 2 exists as an empty project owned by the Sphinx Safe with an approved-but-unused REVDeployer. Anyone who front-runs the separate CPN configuration could exploit the approval. |
| Banny 721 tiers all same category | LOW | All 4 Banny tiers use `category: 0` (lines 1426-1497). The 721 hook store requires ascending category order -- same category is valid but means no category-based sorting or filtering. |

## CREATE2 Salt Risks

| Risk | Severity | Description | Mitigation |
|------|----------|-------------|------------|
| Salt front-running | MEDIUM | All salts are deterministic string hashes (e.g., `keccak256("_JBDeadlinesV6_")`). An attacker who knows the salt and initcode can compute the CREATE2 address and deploy a malicious contract there before the legitimate deployment. | Sphinx deploys from its own deterministic deployer address. The `CREATE2` address depends on `(sphinxDeployer, salt, initCodeHash)`. An attacker would need to deploy from the same Sphinx deployer -- which requires Safe approval. LOW practical risk. |
| Salt reuse across contracts | LOW | `BUYBACK_HOOK_SALT` is used for both `JBBuybackHookRegistry` and `JBBuybackHook` (lines 504, 508). Similarly, `OP_SALT` is used for both `JBOptimismSuckerDeployer` and `JBOptimismSucker`. This is safe because different constructor args produce different initcode hashes, yielding different addresses. But if constructor args were identical, CREATE2 would collide. | No action needed -- different types guarantee different initcode. |

## Sphinx Deployment Mechanics Risks

| Risk | Severity | Description |
|------|----------|-------------|
| Sphinx Safe compromise | CRITICAL | The Sphinx Safe owns every deployed contract. Compromise of Safe signers means total protocol control: add malicious controllers, drain fee-exempt addresses, change sucker deployers, adjust splits on all revnets. |
| Sphinx replay across networks | LOW | Sphinx proposals are network-scoped. A proposal for testnets cannot be replayed on mainnets and vice versa (enforced by `sphinxConfig.mainnets` and `sphinxConfig.testnets`). |
| Sphinx artifact name collision | LOW | `sphinxConfig.projectName = "juicebox-v6"`. If a previous deployment used a different project name, Sphinx may create a new deployment context rather than upgrading. |

## Fee Project Configuration Risks

| Risk | Severity | Description |
|------|----------|-------------|
| Fee project is project #1 | HIGH | `JBMultiTerminal` hardcodes fee payments to project ID 1. The deployment creates project 1 automatically in the `JBProjects` constructor. If the constructor mints to the wrong owner, fees flow to an attacker. The script sets `safeAddress()` as both `initialOwner` and `initialOperator` (line 433). |
| NANA revnet misconfiguration | HIGH | Project 1 is configured as the NANA revnet (lines 1242-1308). If the revnet configuration is wrong (e.g., wrong `splitPercent`, wrong `cashOutTaxRate`), fee distributions are permanently affected. NANA has 62% split and 10% cashout tax. |
| REVDeployer approval on fee project | MEDIUM | Line 1301: `_projects.approve(address(_revDeployer), feeProjectId)`. This gives `_revDeployer` ERC-721 transfer approval on project 1. After `deployFor` completes, REVDeployer becomes the project's controller and the approval is consumed. But if `deployFor` reverts, the approval remains dangling -- though `_revDeployer` is a trusted contract. |

## Incomplete Deployment Sections

| Section | Status | Risk |
|---------|--------|------|
| CPN Revnet (project 2) | Approved but not configured (TODO, line 1225) | Project 2 has dangling REVDeployer approval |
| Defifa | Fully commented out (lines 128-135, 360-361) | No deployment risk -- contracts simply not deployed |
| Defifa Revnet | Commented out | No risk |

## Post-Deployment Verification Checklist

After deployment, verify:

1. All core contracts deployed and linked (directory, controller, terminal, store, tokens).
2. `JBDirectory.isAllowedToSetFirstController(controllerAddress)` returns true.
3. `JBPrices` has feeds for USD/NATIVE_TOKEN, USD/ETH, ETH/NATIVE_TOKEN, and USD/USDC.
4. Each price feed returns a non-zero, non-stale price.
5. L2 sequencer feeds are responsive (for Optimism, Base, Arbitrum mainnets).
6. All sucker deployers are approved in `JBSuckerRegistry`.
7. `JBBuybackHookRegistry.defaultHook()` returns the buyback hook address.
8. `JBRouterTerminalRegistry.defaultTerminal()` returns the router terminal address.
9. Project 1 (NANA), 2 (CPN), 3 (REV), 4 (BAN) exist with correct owners.
10. Revnet configurations match expected stage parameters.
11. All chain-specific addresses resolve to live contracts (not EOAs, not self-destructed).
12. CCIP chain selectors match official CCIP documentation.
13. Bridge contracts (OP Messenger, OP Standard Bridge, Arb Inbox, Arb Gateway Router) are live on each chain.
