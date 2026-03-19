# User Journeys -- deploy-all-v6

Deployment verification journeys for auditors. This is a deployment-only repo -- all journeys describe the deployment process, its verification, and post-deployment smoke testing.

## Journey 1: Full Ecosystem Deployment

The canonical path from zero to a fully deployed Juicebox V6 ecosystem across all target chains.

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

### What Can Go Wrong

| Failure Point | Symptom | Recovery |
|--------------|---------|----------|
| Compilation error | `forge build` fails | Fix source, rebuild |
| Sphinx proposal rejection | Dashboard shows rejected | Fix parameters, re-propose |
| Gas estimation failure | Sphinx reports insufficient gas | Fund Safe with more ETH |
| Chain RPC failure during execution | Partial deployment on that chain | If retries do not clear it, prepare a resume script that skips completed CREATE2 deployments or redeploy from fresh salts |
| Constructor revert on one chain | That chain's deployment fails entirely | Fix the chain-specific parameter, then either resume from the failed phase boundary or redeploy from fresh salts |
| Wrong chain ID match | Chain-specific addresses from wrong chain | **Cannot recover without redeployment**. Contracts with wrong external addresses are permanently misconfigured. |

### Deployment Creates These Projects

| Order | Project ID | Name | Owner | Configured As |
|-------|------------|------|-------|---------------|
| 1 | 1 | NANA (fee project) | `safeAddress()` then REVDeployer | Revnet (1 stage) |
| 2 | 2 | CPN (Croptop) | `safeAddress()` | Not yet configured (TODO) |
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
20. `JBBuybackHookRegistry`
21. `JBBuybackHook`
22. `JBRouterTerminalRegistry`
23. `JBRouterTerminal`
24. `JBSuckerRegistry`
25. Chain-specific sucker deployers and singletons
26. `JBOmnichainDeployer`
27. `JBChainlinkV3PriceFeed` or `JBChainlinkV3SequencerPriceFeed` (ETH/USD)
28. `JBChainlinkV3PriceFeed` or `JBChainlinkV3SequencerPriceFeed` (USDC/USD)
29. `JBMatchingPriceFeed`
30. `JBDeadline3Hours`, `JBDeadline1Day`, `JBDeadline3Days`, `JBDeadline7Days`
31. `CTPublisher`
32. `CTDeployer`
33. `CTProjectOwner`
34. `REVLoans`
35. `REVDeployer`
36. `Banny721TokenUriResolver`

### Phase B: Wiring Verification

These are the critical post-deployment state checks. Each call verifies that a wiring step was executed correctly.

**Directory configuration:**
```bash
# Controller is allowed to be first controller
cast call <directory> "isAllowedToSetFirstController(address)(bool)" <controller>
# Must return true
```

**Price feeds:**
```bash
# USD/NATIVE_TOKEN feed exists and returns a price
cast call <prices> "pricePerUnitOf(uint256,uint32,uint32,uint256)(uint256)" 0 2 <native_currency> 18
# Must return non-zero (current ETH/USD price with 18 decimals)

# USD/USDC feed exists
cast call <prices> "pricePerUnitOf(uint256,uint32,uint32,uint256)(uint256)" 0 2 <usdc_currency> 18
# Must return approximately 1e18 (USDC ~ $1)
```

**Buyback registry:**
```bash
cast call <buyback_registry> "defaultHook()(address)"
# Must return buyback hook address
```

**Router terminal registry:**
```bash
cast call <router_terminal_registry> "defaultTerminal()(address)"
# Must return router terminal address
```

**Sucker registry:**
```bash
# For each sucker deployer address:
cast call <sucker_registry> "isSuckerDeployerAllowed(address)(bool)" <deployer>
# Must return true
```

**Project existence:**
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

---

## Journey 3: Post-Deployment Smoke Test

End-to-end functional verification that the deployed ecosystem accepts payments, mints tokens, processes cashouts, and handles cross-component interactions.

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

**Verify:**
- Transaction succeeds
- `JBTokens.totalSupplyOf(1)` increased
- `JBTokens.totalBalanceOf(<your_address>, 1)` > 0 (you received project tokens)
- `JBTerminalStore.balanceOf(<terminal>, 1, <NATIVE_TOKEN>)` increased by ~0.01 ETH minus 2.5% fee

### Test 2: Price Feed Integration

```bash
# Query ETH/USD price through JBPrices
cast call <prices> "pricePerUnitOf(uint256,uint32,uint32,uint256)(uint256)" \
  0 2 <native_currency> 18
# Should return current ETH price in 18-decimal USD
```

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

**Verify:**
- Router swaps the payment token
- Project receives the correct accounting token
- Tokens minted to beneficiary

---

## Journey 4: Fork Test Validation

Run the existing fork tests to validate the ecosystem interactions work correctly on forked mainnet state.

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

| Test | What It Proves |
|------|---------------|
| `EcosystemForkTest` | Multi-stage revnet with buyback, 721 tiers, LP split hook, and V4 router all interoperate correctly |
| `FullStackForkTest` | Complete deployment stack (core + hooks + revnets + loans) works end-to-end |
| `BuybackRouterForkTest` | Buyback hook correctly routes between mint and DEX swap; router terminal integrates |
| `CrossCurrencyForkTest` | Multi-currency payments with price feed conversions produce correct token amounts |
| `LPBuybackInteropForkTest` | LP split hook and buyback hook work together without conflicts |
| `USDCEcosystemForkTest` | USDC-denominated operations through the full stack |
| `USDCRevnetForkTest` | USDC-denominated revnet lifecycle (pay, earn, cashout, borrow) |

### What a Test Failure Means

- **Fork block too old**: If Uniswap V4 PoolManager is not deployed at the fork block, tests revert in `setUp()`. Update the fork block to a post-V4-deployment block.
- **RPC rate limit**: Fork tests make many RPC calls. Use a high-throughput RPC provider.
- **Dependency version mismatch**: If `npm install` pulled different versions than expected, interface mismatches cause compilation errors. Pin versions in `package.json`.
- **Mainnet state changes**: Fork tests assume specific mainnet state. If Chainlink feed behavior or Uniswap pool state changed significantly, edge-case tests may fail.

---

## Journey 5: Verifying a Specific Chain Deployment

When you need to verify a single chain's deployment (e.g., after a targeted redeployment).

### Step 1: Identify the chain

```bash
# Get chain ID
cast chain-id --rpc-url <chain_rpc>
```

### Step 2: Verify chain-specific addresses were used

Cross-reference the chain ID against `_setupChainAddresses()` in Deploy.s.sol:

- Is `_weth` correct for this chain?
- Is `_v3Factory` correct for this chain?
- Is `_poolManager` correct for this chain?

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
