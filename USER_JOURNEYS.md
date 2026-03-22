# User Journeys -- deploy-all-v6

Deployment verification journeys for auditors. This is a deployment-only repo -- all journeys describe the deployment process, its verification, and post-deployment smoke testing.

---

## Journey 1: Full Ecosystem Deployment

The canonical path from zero to a fully deployed Juicebox V6 ecosystem across all target chains.

### Entry point

`script/Deploy.s.sol` -- `Deploy.run()` which calls `_setupChainAddresses()` then `deploy()`.

When run through Sphinx: `npx sphinx propose script/Deploy.s.sol --networks <testnets|mainnets>`.

### Who can call

The Sphinx Safe multisig (`safeAddress()`). Sphinx serializes the script into a multi-chain deployment plan that must be approved in the Sphinx dashboard before execution.

### Parameters

- `DEPLOY_NETWORK` (env) -- `testnets` or `mainnets`; controls which set of chains is targeted
- `SPHINX_ORG_ID` (env) -- Sphinx organization ID for proposal submission
- `block.chainid` (implicit) -- Determines chain-specific addresses for WETH, Uniswap V3 factory, V4 PoolManager, and PositionManager via `_setupChainAddresses()`

### Prerequisites

- Node.js >= 20
- Foundry toolchain (`forge`, `cast`)
- Sphinx CLI configured with org credentials
- RPC endpoints for all 8 target chains
- Sphinx Safe deployed on all target chains with sufficient ETH for gas

### Step-by-Step

**1. Clone and install**
```bash
git clone https://github.com/Bananapus/deploy-all-v6.git
cd deploy-all-v6
npm install
forge install
```

**2. Configure environment**
```bash
cp .env.example .env
# Set SPHINX_ORG_ID and DEPLOY_NETWORK (testnets or mainnets)
```

**3. Build and verify compilation**
```bash
forge build
```
Build uses `via_ir = true`, `optimizer = false`, Solidity 0.8.26, Cancun EVM. This is slow (~5-10 minutes). Verify zero compilation errors.

**4. Propose deployment**

Sphinx proposal submission triggers the `deploy()` function, which calls `_setupChainAddresses()` and then executes all 9 phases sequentially. Sphinx serializes this into a multi-chain deployment plan.

```bash
npx sphinx propose script/Deploy.s.sol --networks <testnets|mainnets>
```

**5. Review and approve proposal**

In the Sphinx dashboard:
- Review every contract deployment and function call
- Verify deployment addresses match expectations
- Approve the proposal from the Sphinx Safe multisig

**6. Execution**

Sphinx executes the approved proposal on each target chain. Each chain gets one `deploy()` call, but operators should
not treat that as a validated resume-safe atomic transport. If execution halts after some CREATE2 deployments succeed,
the repo does not currently provide an in-repo resume script.

**7. Verify deployment (see Journey 2)**

### State changes (numbered by phase)

1. **Phase 01 -- Core Protocol** (`_deployCore`): CREATE2-deploys 13 core contracts: `ERC2771Forwarder`, `JBPermissions`, `JBProjects` (constructor creates project 1, the fee project, owned by `safeAddress()`), `JBDirectory`, `JBSplits`, `JBRulesets`, `JBPrices`, `JBERC20` (implementation), `JBTokens`, `JBFundAccessLimits`, `JBFeelessAddresses`, `JBTerminalStore`, `JBMultiTerminal`.
2. **Phase 02 -- Address Registry** (`_deployAddressRegistry`): CREATE2-deploys `JBAddressRegistry`.
3. **Phase 03a -- 721 Tier Hook** (`_deploy721Hook`): CREATE2-deploys `JB721TiersHookStore`, `JB721TiersHook` (implementation), `JB721TiersHookDeployer`, `JB721TiersHookProjectDeployer`.
4. **Phase 03b -- Uniswap V4 Hook** (`_deployUniswapV4Hook`): CREATE2-deploys `JBUniswapV4Hook` with flag-mined salt. Skipped on Optimism Sepolia (`_shouldDeployUniswapStack()` returns false).
5. **Phase 03c -- Buyback Hook** (`_deployBuybackHook`): CREATE2-deploys `JBBuybackHookRegistry` and `JBBuybackHook`. Calls `_buybackRegistry.setDefaultHook(_buybackHook)`. Skipped on Optimism Sepolia.
6. **Phase 03d -- Router Terminal** (`_deployRouterTerminal`): CREATE2-deploys `JBRouterTerminalRegistry` and `JBRouterTerminal`. Calls `_routerTerminalRegistry.setDefaultTerminal(_routerTerminal)` and `_feeless.setFeelessAddress(address(_routerTerminal), true)`. Skipped on Optimism Sepolia.
7. **Phase 03e -- LP Split Hook** (`_deployLpSplitHook`): CREATE2-deploys `JBUniswapV4LPSplitHook` and `JBUniswapV4LPSplitHookDeployer`. Skipped on Optimism Sepolia.
8. **Phase 03f -- Suckers** (`_deploySuckers`): CREATE2-deploys chain-specific sucker deployers (`JBOptimismSuckerDeployer`, `JBBaseSuckerDeployer`, `JBArbitrumSuckerDeployer`, `JBCCIPSuckerDeployer`) and their singletons. Calls `setChainSpecificConstants()` and `configureSingleton()` on each deployer. Deploys `JBSuckerRegistry` and calls `_suckerRegistry.allowSuckerDeployer()` for each deployer.
9. **Phase 04 -- Omnichain Deployer** (`_deployOmnichainDeployer`): CREATE2-deploys `JBOmnichainDeployer`.
10. **Phase 05 -- Periphery** (`_deployPeriphery`): CREATE2-deploys `JBChainlinkV3PriceFeed` or `JBChainlinkV3SequencerPriceFeed` for ETH/USD and USDC/USD. Deploys `JBMatchingPriceFeed` for ETH/NATIVE_TOKEN matching. Calls `_prices.addPriceFeedFor()` for each feed. CREATE2-deploys `JBDeadline3Hours`, `JBDeadline1Day`, `JBDeadline3Days`, `JBDeadline7Days`. CREATE2-deploys `JBController` with `omnichainRulesetOperator = address(_omnichainDeployer)`. Calls `_directory.setIsAllowedToSetFirstController(address(_controller), true)`.
11. **Phase 06 -- Croptop** (`_deployCroptop`): Creates CPN project (ID 2) via `_projects.createFor(safeAddress())`. CREATE2-deploys `CTPublisher`, `CTDeployer`, `CTProjectOwner`.
12. **Phase 07 -- Revnet** (`_deployRevnet`): Creates REV project (ID 3) via `_projects.createFor(safeAddress())`. CREATE2-deploys `REVLoans` and `REVDeployer`. Calls `_projects.approve(address(_revDeployer), _revProjectId)`. Calls `_revDeployer.deployFor()` to configure the $REV revnet (3 stages).
13. **Phase 08a -- CPN Revnet** (`_deployCpnRevnet`): Calls `_projects.approve(address(_revDeployer), _cpnProjectId)`. Calls `_revDeployer.deployFor()` with 721 hook config and 5 Croptop allowed post categories for CPN (project 2).
14. **Phase 08b -- NANA Revnet** (`_deployNanaRevnet`): Calls `_projects.approve(address(_revDeployer), feeProjectId)`. Calls `_revDeployer.deployFor()` to configure NANA (project 1) as a 1-stage revnet.
15. **Phase 09 -- Banny** (`_deployBanny`): CREATE2-deploys `Banny721TokenUriResolver`. Calls `_revDeployer.deployFor()` with `revnetId: 0` to create a new project (ID 4) with 721 tiers (4 tiers at 1 ETH, 0.1 ETH, 0.01 ETH, 0.0001 ETH).

### Events (downstream contract events emitted during deployment)

Phase 01--04 are pure CREATE2 deployments with no configuration events. Starting from Phase 03c:

- Phase 03c: `JBBuybackHookRegistry_SetDefaultHook(hook)` -- emitted by `JBBuybackHookRegistry.setDefaultHook()`
- Phase 03d: `JBRouterTerminalRegistry_SetDefaultTerminal(terminal, caller)` -- emitted by `JBRouterTerminalRegistry.setDefaultTerminal()`
- Phase 03d: `SetFeelessAddress(addr, isFeeless, caller)` -- emitted by `JBFeelessAddresses.setFeelessAddress()`
- Phase 03f: `SuckerDeployerAllowed(deployer, caller)` -- emitted by `JBSuckerRegistry.allowSuckerDeployer()` for each deployer
- Phase 05: `AddPriceFeed(projectId, pricingCurrency, unitCurrency, feed, caller)` -- emitted by `JBPrices.addPriceFeedFor()` for each feed (up to 4 feeds)
- Phase 05: `SetIsAllowedToSetFirstController(addr, isAllowed, caller)` -- emitted by `JBDirectory.setIsAllowedToSetFirstController()`
- Phase 06: `Create(projectId, owner, caller)` -- emitted by `JBProjects.createFor()` for CPN (project 2)
- Phase 07: `Create(projectId, owner, caller)` -- emitted by `JBProjects.createFor()` for REV (project 3)
- Phase 07: ERC-721 `Approval(owner, approved, tokenId)` -- emitted by `JBProjects.approve()` for REV project
- Phase 07: `DeployRevnet(revnetId, configuration, terminalConfigurations, suckerDeploymentConfiguration, rulesetConfigurations, encodedConfigurationHash, caller)` -- emitted by `REVDeployer.deployFor()` for $REV
- Phase 08a: `DeployRevnet(...)` -- emitted by `REVDeployer.deployFor()` for CPN
- Phase 08b: `DeployRevnet(...)` -- emitted by `REVDeployer.deployFor()` for NANA
- Phase 09: `DeployRevnet(...)` -- emitted by `REVDeployer.deployFor()` for BAN

Each `DeployRevnet` also triggers downstream events: `SetController(projectId, controller, caller)`, `AddTerminal(projectId, terminal, caller)`, `SuckerDeployedFor(...)` from `JBSuckerRegistry`, and ERC-20 token deployment.

### Edge cases

| Failure Point | Symptom | Recovery |
|--------------|---------|----------|
| Compilation error | `forge build` fails | Fix source, rebuild |
| Sphinx proposal rejection | Dashboard shows rejected | Fix parameters, re-propose |
| Gas estimation failure | Sphinx reports insufficient gas | Fund Safe with more ETH |
| Chain RPC failure during execution | Partial deployment on that chain | If retries do not clear it, prepare a resume script that skips completed CREATE2 deployments or redeploy from fresh salts |
| Constructor revert on one chain | That chain's deployment fails entirely | Fix the chain-specific parameter, then either resume from the failed phase boundary or redeploy from fresh salts |
| Wrong chain ID match | Chain-specific addresses from wrong chain | **Cannot recover without redeployment**. Contracts with wrong external addresses are permanently misconfigured. |
| CREATE2 address collision on rerun | `_isDeployed()` returns true, script skips redeployment | Safe by design -- the script detects existing deployments and reuses them |
| `Deploy_ExistingAddressMismatch` revert | Buyback default hook or router default terminal already set to a different address | Cannot recover without redeployment with fresh salts |
| `Deploy_ProjectIdMismatch` revert | `_ensureProjectExists()` created a project with unexpected ID | Means another project was created between phases; restart with awareness of new project count |
| `Deploy_PriceFeedMismatch` revert | Price feed already set to a different feed for same currency pair | Cannot override; existing feed is immutable in `JBPrices` |
| Optimism Sepolia missing Uniswap stack | `_shouldDeployUniswapStack()` returns false | By design -- `_positionManager = address(0)` on OP Sepolia; Uniswap-dependent contracts skipped |

### Deployment Creates These Projects

| Order | Project ID | Name | Owner | Configured As |
|-------|------------|------|-------|---------------|
| 1 | 1 | NANA (fee project) | `safeAddress()` then REVDeployer | Revnet (1 stage) |
| 2 | 2 | CPN (Croptop) | `safeAddress()` then REVDeployer | Revnet (3 stages + 721 hook + Croptop posts) |
| 3 | 3 | REV (Revnet) | `safeAddress()` then REVDeployer | Revnet (3 stages) |
| 4 | 4 | BAN (Banny) | REVDeployer | Revnet (3 stages + 721 tiers) |

### Recovery Rule

Do not blindly re-propose the full script after a partial execution. Once a CREATE2 deployment from this script lands
on-chain, re-running the same deployment step with the same salt and initcode collides with an existing contract.
Recovery must be an explicit operator action:

1. Inspect which phases completed on-chain.
2. Choose either a phase-aware resume script or a fresh deployment with new salts.
3. Verify post-recovery wiring before proceeding to user-facing launch checks.

---

## Journey 2: Deployment Verification

After deployment completes, verify the ecosystem is correctly configured. This journey is for auditors validating a completed deployment.

### Entry point

Manual verification via `cast` CLI commands against each deployed chain.

### Who can call

Anyone with RPC access -- all verification calls are read-only (`cast call`).

### Parameters

- Chain RPC URL for each target chain
- Expected contract addresses (deterministic via CREATE2 from `safeAddress()` + known salts)

### Phase A: Contract Existence

For each target chain, verify every expected contract is deployed (has code) at the expected address.

```bash
# For each contract address:
cast code <address> --rpc-url <chain_rpc>
# Must return non-empty bytecode
```

**Contracts to check (per chain):**
1. `ERC2771Forwarder`
2. `JBPermissions`
3. `JBProjects`
4. `JBDirectory`
5. `JBSplits`
6. `JBRulesets`
7. `JBPrices`
8. `JBERC20`
9. `JBTokens`
10. `JBFundAccessLimits`
11. `JBFeelessAddresses`
12. `JBTerminalStore`
13. `JBMultiTerminal`
14. `JBController`
15. `JBAddressRegistry`
16. `JB721TiersHookStore`
17. `JB721TiersHook` (implementation)
18. `JB721TiersHookDeployer`
19. `JB721TiersHookProjectDeployer`
20. `JBUniswapV4Hook` (skipped on Optimism Sepolia)
21. `JBBuybackHookRegistry` (skipped on Optimism Sepolia)
22. `JBBuybackHook` (skipped on Optimism Sepolia)
23. `JBRouterTerminalRegistry` (skipped on Optimism Sepolia)
24. `JBRouterTerminal` (skipped on Optimism Sepolia)
25. `JBUniswapV4LPSplitHook` (skipped on Optimism Sepolia)
26. `JBUniswapV4LPSplitHookDeployer` (skipped on Optimism Sepolia)
27. `JBSuckerRegistry`
28. Chain-specific sucker deployers and singletons
29. `JBOmnichainDeployer`
30. `JBChainlinkV3PriceFeed` or `JBChainlinkV3SequencerPriceFeed` (ETH/USD)
31. `JBChainlinkV3PriceFeed` or `JBChainlinkV3SequencerPriceFeed` (USDC/USD)
32. `JBMatchingPriceFeed`
33. `JBDeadline3Hours`, `JBDeadline1Day`, `JBDeadline3Days`, `JBDeadline7Days`
34. `CTPublisher`
35. `CTDeployer`
36. `CTProjectOwner`
37. `REVLoans`
38. `REVDeployer`
39. `Banny721TokenUriResolver`

### Phase B: Wiring Verification

These are the critical post-deployment state checks. Each call verifies that a wiring step was executed correctly.

**State changes to verify (numbered):**

1. **Directory -- controller allowed:**
```bash
cast call <directory> "isAllowedToSetFirstController(address)(bool)" <controller>
# Must return true
```

2. **Price feeds -- USD/NATIVE_TOKEN:**
```bash
cast call <prices> "pricePerUnitOf(uint256,uint256,uint256,uint256)(uint256)" 0 2 <native_currency> 18
# Must return non-zero (current ETH/USD price with 18 decimals)
```

3. **Price feeds -- USD/USDC:**
```bash
cast call <prices> "pricePerUnitOf(uint256,uint256,uint256,uint256)(uint256)" 0 2 <usdc_currency> 18
# Must return approximately 1e18 (USDC ~ $1)
```

4. **Buyback registry -- default hook set:**
```bash
cast call <buyback_registry> "defaultHook()(address)"
# Must return buyback hook address
```

5. **Router terminal registry -- default terminal set:**
```bash
cast call <router_terminal_registry> "defaultTerminal()(address)"
# Must return router terminal address
```

6. **Feeless addresses -- router terminal is feeless:**
```bash
cast call <feeless> "isFeeless(address)(bool)" <router_terminal>
# Must return true
```

7. **Sucker registry -- deployers allowed:**
```bash
# For each sucker deployer address:
cast call <sucker_registry> "suckerDeployerIsAllowed(address)(bool)" <deployer>
# Must return true
```

8. **Project existence and ownership:**
```bash
# Project 1 exists
cast call <projects> "ownerOf(uint256)(address)" 1

# Project 2 exists
cast call <projects> "ownerOf(uint256)(address)" 2

# Project 3 exists
cast call <projects> "ownerOf(uint256)(address)" 3

# Project 4 exists (on chains where BAN revnet was deployed)
cast call <projects> "ownerOf(uint256)(address)" 4
```

9. **Revnet controller wiring:**
```bash
# All 4 projects should have the controller set
cast call <directory> "controllerOf(uint256)(address)" 1
cast call <directory> "controllerOf(uint256)(address)" 2
cast call <directory> "controllerOf(uint256)(address)" 3
cast call <directory> "controllerOf(uint256)(address)" 4
# All must return the JBController address
```

### Events

None -- all verification calls are read-only `cast call` invocations that do not emit events.

### Phase C: Price Feed Liveness

For each chain, verify price feeds are live and not stale.

```bash
# ETH/USD feed -- call underlying Chainlink aggregator
cast call <chainlink_eth_usd> "latestRoundData()(uint80,int256,uint256,uint256,uint80)"
# Verify: answer > 0, updatedAt within threshold of current time

# USDC/USD feed
cast call <chainlink_usdc_usd> "latestRoundData()(uint80,int256,uint256,uint256,uint80)"
# Verify: answer > 0, answer ~ 1e8 (8 decimal Chainlink), updatedAt within threshold

# L2 sequencer feed (Optimism, Base, Arbitrum mainnets only)
cast call <sequencer_feed> "latestRoundData()(uint80,int256,uint256,uint256,uint80)"
# Verify: answer == 0 (sequencer is up), startedAt < current time
```

### Phase D: Revnet Configuration

Verify each revnet's on-chain configuration matches the expected parameters.

```bash
# Get current ruleset for project 1 (NANA)
cast call <rulesets> "currentOf(uint256)(tuple)" 1
# Verify: weight, duration, decayPercent match NANA Stage 1

# Get current ruleset for project 3 (REV)
cast call <rulesets> "currentOf(uint256)(tuple)" 3
# Verify: weight, duration, decayPercent match REV Stage 1

# Check token deployment
cast call <tokens> "tokenOf(uint256)(address)" 1  # NANA ERC-20
cast call <tokens> "tokenOf(uint256)(address)" 3  # REV ERC-20
```

### Edge cases

- **Stale price feed**: `latestRoundData().updatedAt` is older than the threshold (3600s for ETH/USD, 86400s for USDC/USD). The JBChainlinkV3PriceFeed wrapper will revert with `JBChainlinkV3PriceFeed_StalePrice()`.
- **L2 sequencer down**: `latestRoundData().answer != 0` on the sequencer feed. `JBChainlinkV3SequencerPriceFeed` will revert with `JBChainlinkV3SequencerPriceFeed_SequencerDownOrRestarting(timestamp, gracePeriodTime, startedAt)` or `JBChainlinkV3SequencerPriceFeed_InvalidRound()`.
- **Optimism Sepolia missing contracts**: Items 20--26 in Phase A are absent by design. Verification must skip these.
- **controllerOf returns IERC165**: The return type is `IERC165`, not `address`. Cast will still decode the raw address correctly.

---

## Journey 3: Post-Deployment Smoke Test

End-to-end functional verification that the deployed ecosystem accepts payments, mints tokens, processes cashouts, and handles cross-component interactions.

### Entry point

Manual transactions via `cast send` against each deployed chain.

### Who can call

Any externally-owned account with ETH for gas and payment value. All smoke test operations are permissionless.

### Test 1: Basic Payment and Token Minting

```bash
# Pay 0.01 ETH to project 1 (NANA)
cast send <terminal> "pay(uint256,address,uint256,address,uint256,string,bytes)" \
  1 \                    # projectId
  <NATIVE_TOKEN> \       # 0x000000000000000000000000000000000000EEEe
  10000000000000000 \    # 0.01 ETH
  <your_address> \       # beneficiary
  0 \                    # minReturnedTokens
  "" \                   # memo
  "" \                   # metadata
  --value 0.01ether
```

**State changes:**
1. `JBTerminalStore.balanceOf(terminal, 1, NATIVE_TOKEN)` increases by 0.01 ETH (payments do not incur fees; fees are only taken on cashouts and payouts)
2. `JBTokens.totalSupplyOf(1)` increases by minted token count (based on current ruleset weight)
3. `JBTokens.totalBalanceOf(your_address, 1)` increases (credits or ERC-20)

**Events:**
- `Pay(rulesetId, rulesetCycleNumber, projectId, payer, beneficiary, amount, newlyIssuedTokenCount, memo, metadata, caller)` -- emitted by `JBMultiTerminal`

**Verify:**
- Transaction succeeds
- `JBTokens.totalSupplyOf(1)` increased
- `JBTokens.totalBalanceOf(<your_address>, 1)` > 0 (you received project tokens)
- `JBTerminalStore.balanceOf(<terminal>, 1, <NATIVE_TOKEN>)` increased

### Test 2: Price Feed Integration

```bash
# Query ETH/USD price through JBPrices
cast call <prices> "pricePerUnitOf(uint256,uint256,uint256,uint256)(uint256)" \
  0 2 <native_currency> 18
# Should return current ETH price in 18-decimal USD
```

**Events:** None -- read-only call.

**Edge cases:**
- Reverts with `JBChainlinkV3PriceFeed_StalePrice()` if Chainlink feed is stale
- Reverts with `JBPrices_PriceFeedNotFound()` if feed was not registered in Phase 05

### Test 3: Cashout

After Test 1, cash out some tokens:

```bash
# Cash out tokens from project 1
cast send <terminal> "cashOutTokensOf(address,uint256,uint256,address,uint256,address,bytes)" \
  <your_address> \       # holder
  1 \                    # projectId
  <token_count> \        # cashOutCount
  <NATIVE_TOKEN> \       # tokenToReclaim
  0 \                    # minTokensReclaimed
  <your_address> \       # beneficiary
  ""                     # metadata
```

**State changes:**
1. `JBTokens.totalSupplyOf(1)` decreases by `cashOutCount`
2. `JBTokens.totalBalanceOf(your_address, 1)` decreases by `cashOutCount`
3. `JBTerminalStore.balanceOf(terminal, 1, NATIVE_TOKEN)` decreases by reclaimed amount
4. Beneficiary ETH balance increases by reclaimed amount minus 2.5% fee

**Events:**
- `CashOutTokens(rulesetId, rulesetCycleNumber, projectId, holder, beneficiary, cashOutCount, cashOutTaxRate, reclaimAmount, metadata, caller)` -- emitted by `JBMultiTerminal`

**Verify:**
- Transaction succeeds
- ETH was returned (balance increased)
- Project token supply decreased
- Terminal balance decreased

### Test 4: Buyback Hook Integration

If a Uniswap V4 pool exists for the project token:

```bash
# Pay with enough ETH that the buyback hook considers a swap
# The buyback hook compares mint rate vs. DEX rate and takes the better one
cast send <terminal> "pay(uint256,address,uint256,address,uint256,string,bytes)" \
  3 <NATIVE_TOKEN> 1000000000000000000 <your_address> 0 "" "" \
  --value 1ether
```

**Events:**
- `Pay(...)` -- emitted by `JBMultiTerminal`
- If DEX swap occurred: Uniswap V4 `Swap(...)` event from the PoolManager

**Verify:**
- If DEX rate is better: tokens came from the pool (lower terminal balance increase, more tokens minted)
- If mint rate is better: standard payment processing occurred

### Test 5: 721 Tier Mint (Banny)

```bash
# Pay exactly 1 ETH to project 4 (BAN) to mint tier 1 NFT (1 ETH price)
cast send <terminal> "pay(uint256,address,uint256,address,uint256,string,bytes)" \
  4 <NATIVE_TOKEN> 1000000000000000000 <your_address> 0 "" <tier_metadata> \
  --value 1ether
```

**State changes:**
1. `JBTerminalStore.balanceOf(terminal, 4, NATIVE_TOKEN)` increases
2. `JBTokens.totalSupplyOf(4)` increases (project tokens minted)
3. Banny 721 hook mints an NFT to the beneficiary

**Events:**
- `Pay(...)` -- emitted by `JBMultiTerminal`
- ERC-721 `Transfer(from, to, tokenId)` -- emitted by the 721 hook clone for project 4

**Verify:**
- Payment processed
- NFT minted to beneficiary
- Project tokens also minted

### Test 6: Router Terminal Payment

```bash
# Pay via router terminal (swaps payment token to project's accepted token)
cast send <router_terminal_registry> "pay(uint256,address,uint256,address,uint256,string,bytes)" \
  1 <some_token> <amount> <your_address> 0 "" "" \
  --value <if_native>
```

**Events:**
- `Pay(...)` -- emitted by `JBMultiTerminal` (after the router terminal forwards the swap result)

**Verify:**
- Router swaps the payment token
- Project receives the correct accounting token
- Tokens minted to beneficiary

---

## Journey 4: Fork Test Validation

Run the existing fork tests to validate the ecosystem interactions work correctly on forked mainnet state.

### Entry point

`forge test --match-path "test/fork/*"` from the `deploy-all-v6` root directory.

### Who can call

Any developer with Foundry installed and a valid Ethereum mainnet RPC endpoint.

### Parameters

- `RPC_ETHEREUM_MAINNET` (env) -- Full RPC URL for forking Ethereum mainnet
- `--fork-url` (CLI) -- Passed to `forge test` for fork mode

### Setup

```bash
cd deploy-all-v6

# Ensure .env has a valid Ethereum mainnet RPC
echo "RPC_ETHEREUM_MAINNET=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY" > .env

# Install dependencies
npm install
forge install
```

### Run All Fork Tests

```bash
forge test --match-path "test/fork/*" -vvv --fork-url $RPC_ETHEREUM_MAINNET
```

### Expected Test Coverage

| Test File | What It Proves |
|-----------|---------------|
| `EcosystemFork.t.sol` | Multi-stage revnet with buyback, 721 tiers, LP split hook, and V4 router all interoperate correctly |
| `FullStackFork.t.sol` | Complete deployment stack (core + hooks + revnets + loans) works end-to-end |
| `DeployFork.t.sol` | The `Deploy.s.sol` script itself executes without revert on a fork |
| `DeployFullStack.t.sol` | Full stack deployment + configuration succeeds on fork |
| `DeployScriptVerification.t.sol` | Post-deployment state assertions match expected values |
| `BuybackRouterFork.t.sol` | Buyback hook correctly routes between mint and DEX swap; router terminal integrates |
| `CrossCurrencyFork.t.sol` | Multi-currency payments with price feed conversions produce correct token amounts |
| `LPBuybackInteropFork.t.sol` | LP split hook and buyback hook work together without conflicts |
| `USDCEcosystemFork.t.sol` | USDC-denominated operations through the full stack |
| `USDCRevnetFork.t.sol` | USDC-denominated revnet lifecycle (pay, earn, cashout, borrow) |
| `ApprovalHookFork.t.sol` | Approval hooks (deadlines) correctly gate ruleset transitions |
| `HookCompositionFork.t.sol` | Multiple hooks composed together function correctly |
| `PriceFeedFailureFork.t.sol` | System behavior when price feeds fail or return stale data |
| `SuckerEndToEndFork.t.sol` | Cross-chain sucker lifecycle (outbox, bridge, inbox) |
| `ResumeDeployFork.t.sol` | Partial deployment recovery and resume behavior |
| `TestFeeProcessingCascade.t.sol` | Fee processing cascades correctly across split recipients |
| `TestMultiCurrencyPayout.t.sol` | Multi-currency payout distribution |
| `TestTerminalMigration.t.sol` | Terminal migration preserves balances and state |

### Events

None -- deployment script. Fork tests emit events internally but are validated by test assertions, not manual event inspection.

### Edge cases

- **Fork block too old**: If Uniswap V4 PoolManager is not deployed at the fork block, tests revert in `setUp()`. Update the fork block to a post-V4-deployment block.
- **RPC rate limit**: Fork tests make many RPC calls. Use a high-throughput RPC provider.
- **Dependency version mismatch**: If `npm install` pulled different versions than expected, interface mismatches cause compilation errors. Pin versions in `package.json`.
- **Mainnet state changes**: Fork tests assume specific mainnet state. If Chainlink feed behavior or Uniswap pool state changed significantly, edge-case tests may fail.

---

## Journey 5: Verifying a Specific Chain Deployment

When you need to verify a single chain's deployment (e.g., after a targeted redeployment).

### Entry point

Manual verification via `cast` CLI commands against a single chain.

### Who can call

Anyone with RPC access -- all verification calls are read-only.

### Parameters

- `<chain_rpc>` -- RPC URL for the target chain
- Chain ID -- used to look up expected chain-specific addresses from `_setupChainAddresses()`

### Step 1: Identify the chain

```bash
# Get chain ID
cast chain-id --rpc-url <chain_rpc>
```

### Step 2: Verify chain-specific addresses were used

Cross-reference the chain ID against `_setupChainAddresses()` in Deploy.s.sol:

| Chain | Chain ID | WETH | V3 Factory | V4 PoolManager | PositionManager |
|-------|----------|------|------------|----------------|-----------------|
| Ethereum | 1 | `0xC02a...Cc2` | `0x1F98...984` | `0x0000...A90` | `0xbD21...9e` |
| Sepolia | 11155111 | `0x7b79...E7f9` | `0x0227...f2c` | `0xE03A...543` | `0x429b...b4` |
| Optimism | 10 | `0x4200...0006` | `0x1F98...984` | `0x9a13...Ec3` | `0x3C3E...017` |
| OP Sepolia | 11155420 | `0x4200...0006` | `0x4752...D24` | `0x0000...A90` | `address(0)` |
| Base | 8453 | `0x4200...0006` | `0x3312...fD` | `0x4985...b2b` | `0x7C5f...Dc` |
| Base Sepolia | 84532 | `0x4200...0006` | `0x4752...D24` | `0x05E7...408` | `0x4B2C...80` |
| Arbitrum | 42161 | `0x82aF...ab1` | `0x1F98...984` | `0x360E...E32` | `0xd88F...869` |
| Arb Sepolia | 421614 | `0x980B...c73` | `0x248A...bE` | `0xFB3e...317` | `0xAc63...BAc` |

### Step 3: Verify bridge addresses (for chains with suckers)

For each sucker deployer on this chain, verify the bridge addresses:

```bash
# Optimism sucker deployer (if on L1 or Optimism)
# Check that messenger and bridge addresses match the canonical contracts

# Arbitrum sucker deployer (if on L1 or Arbitrum)
# Check inbox and gateway router addresses

# CCIP sucker deployer (all chains)
# Check CCIP router and chain selector
```

### Step 4: Verify price feeds for this chain

```bash
# ETH/USD feed
cast call <eth_usd_feed_wrapper> "currentUnitPrice(uint256)(uint256)" 18
# Should return current ETH/USD price

# USDC/USD feed
cast call <usdc_usd_feed_wrapper> "currentUnitPrice(uint256)(uint256)" 18
# Should return approximately 1e18
```

### Step 5: Verify L2 sequencer feed (L2 mainnets only)

```bash
# Only for Optimism, Base, Arbitrum mainnets
cast call <sequencer_feed> "latestRoundData()(uint80,int256,uint256,uint256,uint80)"
# answer == 0 means sequencer is up
# startedAt should be recent
```

### Step 6: Functional test on this chain

Execute Journey 3 (Smoke Test) Test 1 and Test 2 against this specific chain.

### Events

None -- all verification is read-only.

### Edge cases

- **Chain not in `_setupChainAddresses()`**: The deploy script reverts with `"Unsupported chain"` for unrecognized chain IDs. Only the 8 chains listed above are supported.
- **OP Sepolia missing Uniswap stack**: By design -- `_positionManager = address(0)`, so `_shouldDeployUniswapStack()` returns false. Contracts 20--26 from Phase A will not exist.
- **L2 sequencer feed only on mainnets**: Sepolia chains use `JBChainlinkV3PriceFeed` (no sequencer check), not `JBChainlinkV3SequencerPriceFeed`. Do not attempt Step 5 on testnets.
