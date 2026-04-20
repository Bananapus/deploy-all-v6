# Deploy All Risk Register

This file focuses on the operational risks in the canonical Juicebox V6 rollout: deployment ordering, multi-chain parity, recovery, and post-deploy verification. This repo has no runtime contracts of its own, so the main failure modes live in the deployment configuration and operator process.

For protocol-level risks, see the ecosystem [RISKS.md](../RISKS.md).

## How to use this file

- Read `Priority risks` first; these are the deployment mistakes that can invalidate otherwise-correct contracts.
- Use the detailed sections as an operator runbook for proposal, execution, verification, and recovery.
- Treat the verification checklist as mandatory, not optional documentation.

## Priority risks

| Priority | Risk | Why it matters | Primary controls |
|----------|------|----------------|------------------|
| P0 | Wrong-chain or wrong-order deployment | Project IDs, singleton wiring, and inter-repo assumptions depend on exact deployment sequence. | Fixed phase ordering, chain-specific config review, and post-deploy parity checks. |
| P0 | Unsafe replay after partial execution | Re-running a proposal after partial CREATE2 success can collide with already-deployed contracts and leave wiring inconsistent. | `Resume.s.sol`, explicit recovery procedures, and operator discipline not to replay blindly. |
| P0 | Resume-path identity mismatch | `Resume.s.sol` must be run with the exact expected Safe identity. If the operator uses the wrong configured safe or stale env, recovery halts or converges to the wrong deployment assumptions. | `RESUME_SAFE` enforcement, operator discipline, and post-resume ownership verification. |
| P1 | Configuration drift across supported chains | Oracle, bridge, and dependency differences can silently invalidate omnichain assumptions or leave certain features unavailable. | Chain-specific config review, skipped-phase documentation, and post-deploy smoke tests on each chain. |

## 1. Trust Assumptions

1. **Sphinx Platform and resume operator** -- Deployment is orchestrated via Sphinx proposals. Sphinx controls execution order, gas management, and atomicity per chain, and `Deploy.s.sol` assigns ownership to the Sphinx Safe (`safeAddress()`). Recovery via `script/Resume.s.sol` is gated by `RESUME_SAFE`: the script reverts unless `msg.sender == vm.envAddress("RESUME_SAFE")`, then sets `_deployer = _expectedSafe`. The main trust assumption is therefore not "any broadcaster can resume", but "operators provide the correct Safe identity and do not resume with stale or wrong env configuration".
2. **Hardcoded Addresses** -- External contract addresses (Uniswap V4 PoolManager, Uniswap V3 Factory, WETH, Chainlink feeds, bridge contracts, CCIP routers, Permit2) are hardcoded per chain in the script. A wrong address means the deployed contract is permanently misconfigured.
3. **Constructor Parameters** -- All initialization values (salts, prices, revnet stages, auto-issuance amounts, tier configs) are baked into the script. Many parameters are immutable after deployment -- constructor errors cannot be patched.
4. **Deployment Ordering** -- Contracts deploy in dependency order within a single `deploy()` call. Between Sphinx proposal submission and execution, no intermediate state is exploitable because contracts are not usable until the full wiring phase completes. If a proposal is partially executed, `script/Resume.s.sol` can resume from the first incomplete phase.
5. **Permit2** -- Hardcoded to canonical address `0x000000000022D473030F116dDEE9F6B43aC78BA3`. Assumed deployed on all target chains.

---

## 2. Deployment Ordering Risks

The script executes 10 top-level phases in strict sequence. Phase `03` is split into subphases (`03a` through `03f`), and Phase `08` is split into `08a` and `08b`. Each phase depends on state produced by prior phases. All phases run inside a single Sphinx `deploy()` call per chain.

| Risk | Severity | Description | Mitigation |
|------|----------|-------------|------------|
| Partial deployment | HIGH | If Sphinx execution halts mid-proposal (gas, revert, platform failure), core contracts may exist without wiring. Example: `JBDirectory` deployed but `setIsAllowedToSetFirstController` never called -- no projects can launch. | Do not re-propose the full script with the same salts. Use `script/Resume.s.sol` to resume from the first incomplete phase, then run `script/Verify.s.sol` to validate state and separately verify ownership/admin addresses. Alternatively, redeploy from fresh salts. |
| Resume identity mismatch | HIGH | `Resume.s.sol` now hard-reverts unless `msg.sender == RESUME_SAFE`, which prevents arbitrary-broadcaster drift. The remaining risk is operator error: using the wrong safe address in env/config, or resuming with a Safe that is not the canonical deployment authority for that chain. | Treat `RESUME_SAFE` as part of the trusted deployment config, use the same Safe identity as the original path, and still verify ownership/admin endpoints after recovery. |
| Controller deploys after omnichain deployer | MEDIUM | `JBController` constructor takes `omnichainRulesetOperator: address(_omnichainDeployer)`. If the omnichain deployer address changes between phases, the controller is permanently misconfigured. | Single-proposal atomicity ensures deterministic ordering. Verify the `_omnichainDeployer` address in the controller's constructor after deployment. |
| Sucker deployers before registry | LOW | All sucker deployers (OP, Base, Arb, CCIP) are deployed before `JBSuckerRegistry`. Deployers are pushed to `_preApprovedSuckerDeployers[]`, then batch-approved on registry creation. If any deployer creation reverts, the array is incomplete. | The `if (_preApprovedSuckerDeployers.length != 0)` guard prevents empty-array revert but means a silently missing deployer is possible. |
| Project ID determinism | HIGH | Project IDs are determined by deployment order: project 1 (fee project, auto-created), project 2 (CPN), project 3 (REV), project 4 (BAN, created by `deployFor` with `revnetId: 0`). If any `createFor` call is reordered or another project is inserted, all subsequent project IDs shift. Every revnet configuration, sucker config, and cross-reference hardcodes these IDs. | Verify project IDs match expected values after deployment. `REVLoans` constructor takes `revId: _revProjectId` -- if this ID is wrong, the loans contract references a non-existent or wrong project. |
| Omnichain deployer needs hooks + registry | MEDIUM | Phase 04 deploys `JBOmnichainDeployer` which takes `_hookDeployer` and `_suckerRegistry` as constructor args. Both must be deployed earlier in Phase 03. If Phase `03a` or `03f` fails, the omnichain deployer cannot be wired correctly. | Sphinx reverts the entire chain's deployment on any constructor failure. No partial recovery path. |
| NANA revnet after REV revnet | LOW | Phase 08b configures the fee project (ID 1) as a revnet. If Phase 07 ($REV) fails, `_revDeployer` is undeployed and the `_projects.approve` call in Phase 08b reverts. This blocks NANA configuration but does not leave the fee project in a dangerous state -- it just has no revnet rules. | Resume from the failed phase boundary or redeploy from fresh salts. The fee project without revnet rules still collects fees but has no issuance or cashout mechanics. |

### Dependency Graph

```
Phase 01: Core protocol (no deps)
Phase 02: Address registry (no deps)
Phase 03a: 721 hook (Core)
Phase 03b: Uniswap V4 router hook (Core, optional on supported chains)
Phase 03c: Buyback hook registry + buyback hook (Core, router hook required for the hook)
Phase 03d: Router terminal (Core, optional with Uniswap stack)
Phase 03e: LP split hook (Core, optional with Uniswap stack)
Phase 03f: Suckers (Core)
Phase 04: Omnichain deployer (Core + 721 hook + suckers)
Phase 05: Periphery/controller (Core + omnichain deployer)
Phase 06: Croptop (Core + 721 hook + suckers + controller)
Phase 07: Revnet (Core + controller + Croptop + buyback stack)
Phase 08a: CPN revnet config
Phase 08b: NANA revnet config
Phase 09: Banny (revnet deployer + 721 hook)
Phase 10: Defifa (721 hook + controller + tokens)
```

If deployment is interrupted at any phase boundary, all contracts from completed phases exist on-chain but are inert --
the controller is not yet authorized, price feeds are not yet registered, and no projects are configured.
**Re-proposing the full script is not a safe recovery path** because CREATE2 with the same salt and initcode will
revert once any matching deployment already exists. Use `script/Resume.s.sol` to resume from the first incomplete
phase, then run `script/Verify.s.sol` to validate post-deployment state.

---

## 3. Oracle / Price Feed Risks

| Risk | Severity | Description | Mitigation |
|------|----------|-------------|------------|
| Wrong Chainlink feed address | CRITICAL | ETH/USD and USDC/USD feeds are hardcoded per chain. A wrong address passes a non-Chainlink contract to `JBChainlinkV3PriceFeed`, which calls `latestRoundData()`. If the address is a contract that happens to implement that function, it could return arbitrary prices. If not, it reverts -- DoS on all multi-currency operations. | Cross-reference every Chainlink address against the official Chainlink feeds directory for each chain. Feeds are immutable once set in `JBPrices`. |
| Missing sequencer feed on L2 | HIGH | Optimism, Base, and Arbitrum mainnets use `JBChainlinkV3SequencerPriceFeed` with L2 sequencer uptime feeds. Testnets use `JBChainlinkV3PriceFeed` without sequencer checks. If a mainnet address is accidentally given the non-sequencer variant, L2 sequencer downtime will not trigger price rejections. | Verify that mainnet L2 chains use `JBChainlinkV3SequencerPriceFeed` and that the sequencer feed addresses match canonical Chainlink L2 sequencer feeds. |
| Staleness threshold mismatch | MEDIUM | ETH/USD feeds use `3600 seconds` threshold. USDC/USD feeds use `86_400 seconds`. If the Chainlink ETH/USD feed on a chain actually updates less frequently than hourly (unlikely but possible during congestion), operations revert. | Verify Chainlink heartbeat intervals match configured thresholds for each chain. |
| JBMatchingPriceFeed (1:1) for ETH/NATIVE_TOKEN | LOW | `JBMatchingPriceFeed` returns 1:1 for ETH abstract currency to NATIVE_TOKEN concrete currency. This is correct by definition but only if the pair is correct. If accidentally set for USD/NATIVE_TOKEN, all USD-denominated operations compute wrong values. | Verify the three `addPriceFeedFor` calls in `_deployPeriphery()` set the correct currency pairs. |
| Price feed immutability | HIGH | Once `JBPrices.addPriceFeedFor()` is called for a `(projectId, pricingCurrency, unitCurrency)` tuple, the feed cannot be replaced. A wrong feed address is permanent. The only workaround is project-specific feed overrides (which override the default but require per-project action). | Double-check all four `addPriceFeedFor` calls before proposal approval. |
| Shared sequencer feed address | LOW | Optimism and Base share sequencer feed addresses across their respective ETH/USD and USDC/USD feeds. If a sequencer feed goes offline permanently, both currency pairs revert simultaneously, halting all multi-currency operations on that L2. | Monitor Chainlink sequencer feed health. No on-chain mitigation -- feeds are immutable. |
| Base Sepolia USDC/ETH feed reuse | MEDIUM | Base Sepolia uses `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165` for USDC/USD, the same address used for Arbitrum Sepolia's ETH/USD feed. This may be intentional (testnet feeds are shared) or a copy-paste error. | Verify against Chainlink's testnet feed directory. |

---

## 4. Cross-Chain Consistency Risks

The script deploys across 8 chains (4 mainnets + 4 testnets). Consistency between chains is critical for sucker (bridge) operations.

| Risk | Severity | Description | Mitigation |
|------|----------|-------------|------------|
| Non-deterministic addresses across chains | HIGH | Sphinx uses CREATE2 from its deterministic deployer. Contract addresses depend on `(deployer, salt, initCodeHash)`. Core contracts share the same salt (`CORE_DEPLOYMENT_NONCE = 6`) but chain-specific constructor args (WETH, PoolManager, V3Factory) change `initCodeHash`, producing different addresses. | Sphinx handles cross-chain determinism for same-bytecode contracts. Contracts with chain-specific constructor args (router terminal, buyback hook, sucker deployers) WILL have different addresses per chain. Verify that cross-chain references (sucker pairs) use correct per-chain addresses. |
| Chain-specific constants per sucker | HIGH | Each sucker deployer calls `setChainSpecificConstants()` with bridge addresses that differ by chain and by mainnet/testnet. Wrong bridge address = bridge operations fail or, worse, route to a malicious contract. | Verify every bridge address: OP Messenger, OP Standard Bridge, Arbitrum Inbox, Arbitrum Gateway Router, CCIP Router, and CCIP chain selectors. Each has a mainnet and testnet variant. |
| CCIP chain selector mismatch | HIGH | CCIP sucker deployers use `CCIPHelper.selectorOfChain(remoteChainId)` to look up CCIP selectors. If `CCIPHelper` has a wrong mapping, CCIP messages route to the wrong destination. | Verify `CCIPHelper` mappings against official CCIP documentation. |
| L2-only sucker deployer on L1 | MEDIUM | L2 sucker deployers (OP, Base, Arb) use canonical predeploy addresses (`0x42...07`, `0x42...10`) that do not exist on L1. The script correctly gates deployment with `block.chainid` checks, but if a chain ID check is wrong, L1 gets an L2 sucker with non-existent bridge contracts. | Verify each `if (block.chainid == ...)` branch deploys only the appropriate bridge variant. |
| CCIP deployer per-chain coverage | MEDIUM | Each chain gets exactly 3 CCIP sucker deployers, one per remote chain. If a new chain is added without updating all existing chains' CCIP deployer lists, the new chain can bridge to existing chains but not vice versa. | Ensure symmetry: for every (chainA, chainB) pair, both chainA and chainB deploy a CCIP sucker targeting the other. |
| L2 sucker builds only one config | LOW | `_buildSuckerConfig()` on L2 chains creates only one sucker deployer config using whichever deployer is non-zero. If multiple deployers are deployed on the same L2 (e.g., both OP native bridge and CCIP), only the first non-zero is used for the revnet's default sucker config. Additional bridge paths require separate sucker deployment. | The first non-zero check order is: Optimism, then Base, then Arbitrum. Verify this matches the intended primary bridge for each L2. |
| Project IDs diverge across chains | HIGH | Each chain independently increments project IDs via `JBProjects.createFor()`. If the deployment order differs across chains (e.g., one chain's proposal has an extra `createFor` call), project 1 on chain A is not the same project as project 1 on chain B. Sucker operations reference project IDs -- a mismatch means bridged tokens go to the wrong project. | Sphinx executes the same script on all chains. Verify project IDs match across all chains after deployment. |
| Multi-chain partial failure | HIGH | Sphinx proposals execute independently per chain. If the proposal succeeds on 6 of 8 chains but fails on 2 (gas issues, RPC failure, bridge contract unavailable), the successful chains have fully wired contracts while the failed chains may have either no deployment at all or a partial phase boundary that still needs resume logic. Sucker pairs between successful and failed chains are unusable until the failed chains converge to the same deployment state. Cross-chain project IDs remain consistent only if recovery on the failed chains uses the identical deployment path. | Monitor Sphinx proposal status per chain. If partial failure occurs, inspect whether the failed chains are empty or partially deployed, then use `Resume.s.sol` or an identical per-chain reproposal as appropriate. Verify sucker peers are live before enabling bridge operations. |

---

## 5. Configuration Risks

### Hardcoded Address Risks

| Risk | Severity | Description |
|------|----------|-------------|
| WETH | HIGH | Different per chain. 7 distinct addresses across 8 chains. L2 chains share `0x4200000000000000000000000000000000000006`. |
| Uniswap V3 Factory | HIGH | Different per chain. Used by `JBRouterTerminal` for swap routing. |
| Uniswap V4 PoolManager | HIGH | Different per chain except Ethereum Mainnet and Optimism Sepolia sharing `0x000000000004444c5dc75cB358380D2e3dE08A90`. Used by `JBBuybackHook`, `JBRouterTerminal`, and `JBUniswapV4LPSplitHook`. |
| Uniswap V4 PositionManager | HIGH | Hardcoded per chain and required by `JBUniswapV4LPSplitHook` for pool initialization and liquidity management. A wrong address bricks LP split deployments on that chain. Optimism Sepolia intentionally skips the Uniswap-dependent phases because no canonical `PositionManager` is published there. |
| Chainlink ETH/USD feeds | CRITICAL | 8 distinct addresses, one per chain. |
| Chainlink USDC/USD feeds | CRITICAL | 8 distinct addresses. |
| L2 Sequencer feeds | HIGH | 3 addresses (OP, Base, Arb mainnets). |
| USDC token addresses | HIGH | 8 distinct addresses. |
| OP Messenger/Bridge (L1) | HIGH | Mainnet and Sepolia variants for both Optimism and Base. 4 addresses each side. |
| OP Messenger/Bridge (L2) | LOW | Canonical predeploys `0x42...07` and `0x42...10`. |
| Arbitrum Inbox/Gateway | HIGH | Uses `ARBAddresses` library constants. |

### Constructor Parameter Risks

| Risk | Severity | Description |
|------|----------|-------------|
| Hook-mined router hook | HIGH | `JBUniswapV4Hook` must be deployed to an address whose low bits match its declared Uniswap V4 hook permissions. The mined salt depends on the final constructor args and deployer address. If either drifts from execution reality, deployment reverts. |
| Shared oracle hook wiring | MEDIUM | `JBBuybackHook` and `JBUniswapV4LPSplitHook` now both rely on the deployed `JBUniswapV4Hook`. If that hook is missing or miswired, buyback TWAP protection and LP split pool initialization both fail or degrade together. |
| Revnet start times in the past | MEDIUM | `REV_START_TIME = 1_740_089_444` (Feb 20, 2025), `NANA_START_TIME = 1_740_089_444`, `BAN_START_TIME = 1_740_435_044`. If deployed after these timestamps, the first ruleset stage is already active and issuance decay has already been ticking. Auto-issuances may calculate differently than expected. |
| Auto-issuance amounts | HIGH | Per-chain auto-issuance amounts for REV, NANA, and BAN are large uint104 constants. These represent preminted token allocations. If any amount is wrong, tokens are permanently minted to the wrong quantity. Cannot be corrected post-deployment. |
| CPN revnet configuration | LOW | `_deployCpnRevnet()` is fully implemented and called during deployment. Verify stage parameters, splits, and terminal configs match intended CPN economics. |
| Fee percentage non-configurable | LOW | The 2.5% fee is a constant in `JBMultiTerminal` (`FEE = 25`, `MAX_FEE = 1000`). It cannot be changed post-deployment. This is by design but means a fee adjustment requires full protocol redeployment. |
| NANA 62% split percentage | HIGH | Project 1 (NANA/fee project) has `splitPercent: 6200` -- 62% of all tokens minted during payments go to reserved token splits. If this percentage is misconfigured, fee revenue distribution is permanently affected. |
| REV cashOutTaxRate of 10% | MEDIUM | All three revnets use `cashOutTaxRate: 1000` (10%). This is low enough that revnet loans become more attractive than cashouts above ~39% (per CryptoEconLab finding). If the intended rate was different, it cannot be changed. |

### CREATE2 Salt Risks

| Risk | Severity | Description | Mitigation |
|------|----------|-------------|------------|
| Salt front-running | MEDIUM | All salts are deterministic string hashes (e.g., `keccak256("_JBDeadlinesV6_")`). An attacker who knows the salt and initcode can compute the CREATE2 address and deploy a malicious contract there before the legitimate deployment. | Sphinx deploys from its own deterministic deployer address. The `CREATE2` address depends on `(sphinxDeployer, salt, initCodeHash)`. An attacker would need to deploy from the same Sphinx deployer -- which requires Safe approval. LOW practical risk. |

### Sphinx Deployment Mechanics Risks

| Risk | Severity | Description |
|------|----------|-------------|
| Sphinx Safe compromise | CRITICAL | The Sphinx Safe owns every deployed contract. Compromise of Safe signers means total protocol control: add malicious controllers, drain fee-exempt addresses, change sucker deployers, adjust splits on all revnets. |
| Sphinx artifact name collision | LOW | `sphinxConfig.projectName = "juicebox-v6"`. If a previous deployment used a different project name, Sphinx may create a new deployment context rather than upgrading. |

### Fee Project Configuration Risks

| Risk | Severity | Description |
|------|----------|-------------|
| Fee project is project #1 | HIGH | `JBMultiTerminal` hardcodes fee payments to project ID 1. The deployment creates project 1 automatically in the `JBProjects` constructor. If the constructor mints to the wrong owner, fees flow to an attacker. The script sets `safeAddress()` as both `owner` and `feeProjectOwner`. |
| NANA revnet misconfiguration | HIGH | Project 1 is configured as the NANA revnet. If the revnet configuration is wrong (e.g., wrong `splitPercent`, wrong `cashOutTaxRate`), fee distributions are permanently affected. NANA has 62% split and 10% cashout tax. |
| REVDeployer approval on fee project | MEDIUM | `_projects.approve(address(_revDeployer), feeProjectId)`. This gives `_revDeployer` ERC-721 transfer approval on project 1. After `deployFor` completes, REVDeployer becomes the project's controller and the approval is consumed. But if `deployFor` reverts, the approval remains dangling -- though `_revDeployer` is a trusted contract. |

### Incomplete Deployment Sections

| Section | Status | Risk |
|---------|--------|------|
| CPN Revnet (project 2) | Fully configured | Deployed as a revnet via `_deployCpnRevnet()` |
| Uniswap V4 router/oracle stack | Deployed by this script | Deployment now depends on correct hook mining plus correct PoolManager and PositionManager constants |
| JBOwnable | Not deployed by this script | Any ownership model depending on it is out of canonical-release scope |
| Defifa | Deployed (Phase 10) | DefifaHook, DefifaTokenUriResolver, DefifaGovernor, DefifaDeployer |

### Catastrophic Misconfiguration Scenarios

1. **Wrong WETH on L2**: If an L2 chain receives the wrong WETH address, the `JBRouterTerminal` cannot wrap/unwrap ETH. All router terminal payments on that chain revert. The router terminal is constructed with an immutable WETH reference -- no fix without redeployment.

2. **Wrong PoolManager**: If `_poolManager` points to a non-Uniswap contract, `JBBuybackHook` attempts swaps against a contract that may not implement the PoolManager interface. Best case: reverts (payments fall through to standard minting). Worst case: if the contract implements `swap()` with different semantics, funds could be lost.

3. **Swapped mainnet/testnet feed addresses**: Using a testnet Chainlink feed address on mainnet (or vice versa) results in either a revert (address has no code) or stale/wrong price data. Since feeds are immutable in `JBPrices`, this permanently breaks multi-currency operations.

4. **Auto-issuance on wrong chain ID**: Auto-issuances specify `chainId` (e.g., `chainId: 1` for mainnet). If a chain ID is wrong, the premint happens on the wrong chain's sucker deployment, minting tokens that don't correspond to any real cross-chain claim.

---

## 6. Post-Deployment Verification Checklist

### Contract Existence

For each of the 8 target chains, verify every expected contract is deployed at the expected address:

- [ ] `ERC2771Forwarder` -- has code
- [ ] Core contracts (JBPermissions, JBProjects, JBDirectory, JBSplits, JBRulesets, JBPrices, JBERC20, JBTokens, JBFundAccessLimits, JBFeelessAddresses, JBTerminalStore, JBMultiTerminal, JBController) -- all have code
- [ ] Address registry, 721 hook stack, buyback hook stack, router terminal stack -- all have code
- [ ] Chain-appropriate sucker deployers and singletons -- have code
- [ ] JBOmnichainDeployer -- has code

### Wiring Verification

- [ ] `JBDirectory.isAllowedToSetFirstController(controllerAddress)` returns `true`
- [ ] `JBBuybackHookRegistry.defaultHook()` returns the buyback hook address
- [ ] `JBRouterTerminalRegistry.defaultTerminal()` returns the router terminal address
- [ ] All sucker deployers registered in `JBSuckerRegistry` (call `suckerDeployerIsAllowed` for each)

### Price Feeds

- [ ] `JBPrices` has feeds for USD/NATIVE_TOKEN, USD/ETH, ETH/NATIVE_TOKEN, and USD/USDC
- [ ] Each price feed returns a non-zero, non-stale price
- [ ] L2 sequencer feeds are responsive (for Optimism, Base, Arbitrum mainnets)
- [ ] L2 mainnets use `JBChainlinkV3SequencerPriceFeed` (not the non-sequencer variant)
- [ ] Staleness thresholds match Chainlink heartbeat intervals (3600s for ETH/USD, 86400s for USDC/USD)

### Project Integrity

- [ ] Project 1 (NANA) and 2 (CPN) exist with correct owners on every target chain
- [ ] Project 3 (REV) and 4 (BAN) exist with correct owners on chains where the Uniswap stack was deployed
- [ ] Project IDs are consistent across all 8 chains
- [ ] Revnet configurations match expected stage parameters (splitPercent, cashOutTaxRate, issuanceCutFrequency)
- [ ] Auto-issuance amounts match constants for each chain
- [ ] Token symbols: NANA (project 1), CPN (project 2 -- when configured), REV (project 3), BAN (project 4)

### Cross-Chain

- [ ] All chain-specific addresses resolve to live contracts (not EOAs, not self-destructed)
- [ ] CCIP chain selectors match official CCIP documentation
- [ ] Bridge contracts (OP Messenger, OP Standard Bridge, Arb Inbox, Arb Gateway Router) are live on each chain
- [ ] Sucker deployer counts match expected per-chain configuration (3 on L1, varies on L2)
- [ ] CCIP router addresses are correct for each chain (mainnet vs testnet)

### Security

- [ ] Sphinx Safe address is the owner/admin of all ownable contracts
- [ ] No dangling approvals on project NFTs
- [ ] `JBFeelessAddresses` has no unexpected entries
- [ ] `JBDirectory` has exactly one allowed controller

## 7. Recovery Procedures

### Partial Deployment Recovery

If a Sphinx proposal fails mid-execution on a chain:

1. **Identify the failure boundary.** Check which contracts exist on-chain (have code) vs. which are missing.
2. **Do NOT re-propose the full script with the same salts.** CREATE2 with identical `(deployer, salt, initCodeHash)` reverts if the contract already exists.
3. **Run `script/Resume.s.sol`**, which skips already-deployed contracts (checks `extcodesize`) and performs only the remaining deployments and wiring.
4. **Verify ownership/admin convergence after resume.** The current resume script forces `_deployer = RESUME_SAFE`, so recovery should converge to the same Safe-owned boundary as the canonical path. Verification is still required because interrupted flows can leave intermediate handoffs incomplete until resume repairs them.
5. **Run `script/Verify.s.sol`** to validate post-deployment state.
6. **Verify project IDs match** across all chains before enabling sucker operations. A single mismatched project ID can route bridged tokens to the wrong treasury.

### Wrong Address Recovery

If a hardcoded address is wrong and already deployed:

- **Price feeds:** Cannot be replaced in `JBPrices`. The only recovery is per-project feed overrides (requires each affected project to act independently).
- **WETH/PoolManager/V3Factory:** These are immutable constructor args. The affected contracts must be redeployed with new salts.
- **Chainlink feed on wrong chain variant:** If a testnet feed is deployed on mainnet, all multi-currency operations halt. Redeploy with corrected addresses.
