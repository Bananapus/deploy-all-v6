# Juicebox V6 Deployment Runbook

Operator guide for deploying, resuming, and verifying the Juicebox V6 ecosystem.

## Supported Chains

| Chain | ID | Uniswap V4 | Suckers |
|---|---|---|---|
| Ethereum Mainnet | 1 | Yes | OP, Base, Arb, CCIP |
| Ethereum Sepolia | 11155111 | Yes | OP Sepolia, Base Sepolia, Arb Sepolia |
| Optimism | 10 | Yes | Ethereum |
| Optimism Sepolia | 11155420 | Partial (no PositionManager) | Ethereum Sepolia |
| Base | 8453 | Yes | Ethereum |
| Base Sepolia | 84532 | Yes | Ethereum Sepolia |
| Arbitrum One | 42161 | Yes | Ethereum |
| Arbitrum Sepolia | 421614 | Yes | Ethereum Sepolia |

Chains without a PositionManager skip the Uniswap-dependent stack (buyback hook, router terminal, LP split hook, revnet). Core protocol + 721 hook + suckers + croptop still deploy.

## Deployment Phases

The deploy script (`script/Deploy.s.sol`) executes 10 phases in strict order:

| Phase | What | Creates |
|---|---|---|
| 01 | Core Protocol | Permissions, Projects, Prices, Rulesets, Directory, JBERC20, Tokens, Splits, Feeless, FundAccessLimits, TerminalStore, MultiTerminal, ERC2771Forwarder |
| 02 | Address Registry | JBAddressRegistry |
| 03a | 721 Tier Hook | HookStore, HookDeployer, HookProjectDeployer |
| 03b | Uniswap V4 Router Hook | JBUniswapV4Hook (requires PoolManager) |
| 03c | Buyback Hook | JBBuybackHookRegistry (requires V3Factory) |
| 03d | Router Terminal | JBRouterTerminal, JBRouterTerminalRegistry |
| 03e | LP Split Hook | JBUniswapV4LPSplitHook (requires PositionManager) |
| 03f | Cross-Chain Suckers | JBSuckerRegistry + per-bridge deployers (OP, Base, Arb, CCIP) |
| 04 | Omnichain Deployer | JBOmnichainDeployer |
| 05 | Periphery | Controller, Price Feeds (ETH/USD, USDC/USD, sequencer-aware on L2), Deadline hooks |
| 06 | Croptop | CTDeployer, CTPublisher, CTProjectOwner; creates CPN project (ID 2) |
| 07 | Revnet | REVLoans, REVDeployer; creates REV project (ID 3) |
| 08 | Revnet Config | Configures CPN (project 2) and NANA (project 1) as revnets |
| 09 | Banny | Banny721TokenUriResolver; creates BAN project (ID 4) |
| 10 | Defifa | DefifaHook, DefifaTokenUriResolver, DefifaGovernor, DefifaDeployer |

All contracts use CREATE2 with deterministic salts. Addresses are identical across chains for the same salt + initcode.

## Pre-Deploy Checklist

Before running a deployment:

1. **Confirm chain support.** Verify the target chain ID is in `_setupChainAddresses()`.
2. **Confirm external dependencies exist.** For Uniswap-dependent chains, verify PoolManager + PositionManager are deployed at the expected addresses. Check https://docs.uniswap.org/contracts/v4/deployments.
3. **Confirm Chainlink feeds.** For L1: ETH/USD + USDC/USD feeds. For L2: same feeds + sequencer uptime feed. Addresses are in `_deployPeriphery()`.
4. **Confirm typeface.** The Capsules SVG font contract must be deployed at the chain-specific address in `_setupChainAddresses()`.
5. **Dry run.** Execute against a fork first:
   ```bash
   forge script script/Deploy.s.sol --rpc-url <RPC_URL> -vvvv
   ```
   No `--broadcast` flag = simulation only. Verify all phases complete without revert.
6. **Gas estimation.** Full deploy is ~50M+ gas across all phases. Ensure the deployer has sufficient ETH/native token.
7. **Safe address.** The deploy script uses Sphinx for multi-sig execution. Confirm `safeAddress()` returns the correct multi-sig for the target chain.

## Running the Deploy

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url <RPC_URL> \
  --broadcast \
  --sender <DEPLOYER_ADDRESS> \
  -vvvv
```

Monitor each phase in the `-vvvv` output. The script logs phase boundaries and contract addresses as it progresses.

## Interrupted Deploy: Using Resume.s.sol

If a deploy is interrupted (gas spike, RPC timeout, operator error), use `Resume.s.sol` to continue from where it stopped.

### How Resume Works

Resume detects completed phases by checking `code.length != 0` at each contract's deterministic CREATE2 address. If a contract already has code, it's skipped. If not, it's deployed.

State-mutating calls (e.g., `setDefaultHook`, `setIsAllowedToSetFirstController`, `allowSuckerDeployer`) are guarded by idempotent checks that read current on-chain state before writing.

### Running Resume

```bash
forge script script/Resume.s.sol:Resume \
  --rpc-url <RPC_URL> \
  --broadcast \
  --sender <DEPLOYER_ADDRESS> \
  -vvvv
```

### Resume Output

The script logs each phase as either `SKIPPED` (already deployed) or `EXECUTED` (deployed missing contracts). At completion:

```
[Resume] COMPLETE
[Resume] Phases skipped: N
[Resume] Phases executed: M
```

### Resume Limitations

1. **Project ID ordering.** Projects 1-4 (NANA, CPN, REV, BAN) are created in sequence. If a third party creates a project between interruption and resume, IDs will shift. Resume detects this by checking `projects.count()` and existing controller assignments, but operator verification is required.
2. **Revnet configuration (Phases 08a/08b).** These phases configure existing projects as revnets. Resume stubs log a `WARNING` if the configuration needs manual review — the revnet setup involves complex ruleset + split + limit configuration that may not be safely idempotent across all edge cases.
3. **Banny (Phase 09).** Same as above — project creation + NFT tier configuration needs manual review if interrupted mid-phase.

### Resume Rehearsal

The test suite includes rehearsal tests that simulate interruptions at different phases:

```bash
forge test --match-contract DeployResumeRehearsalFork -vvv --fork-url <RPC_URL>
```

These tests interrupt after Phase 01, Phase 03a, Phase 05, and Phase 07, then resume and verify all contracts end up correctly deployed.

## Post-Deploy Verification: Using Verify.s.sol

After a successful deploy (or resume), run `Verify.s.sol` to validate all contracts are correctly wired together.

### Setting Up Verification

Verify reads contract addresses from environment variables. Export each deployed address:

```bash
export VERIFY_PROJECTS=0x...
export VERIFY_DIRECTORY=0x...
export VERIFY_CONTROLLER=0x...
export VERIFY_TERMINAL=0x...
export VERIFY_TERMINAL_STORE=0x...
export VERIFY_TOKENS=0x...
export VERIFY_FUND_ACCESS_LIMITS=0x...
export VERIFY_PRICES=0x...
export VERIFY_RULESETS=0x...
export VERIFY_SPLITS=0x...
export VERIFY_FEELESS=0x...
export VERIFY_PERMISSIONS=0x...
export VERIFY_HOOK_STORE=0x...
export VERIFY_HOOK_DEPLOYER=0x...
export VERIFY_HOOK_PROJECT_DEPLOYER=0x...
export VERIFY_SUCKER_REGISTRY=0x...
export VERIFY_OMNICHAIN_DEPLOYER=0x...
export VERIFY_CT_PUBLISHER=0x...
export VERIFY_CT_DEPLOYER=0x...
export VERIFY_CT_PROJECT_OWNER=0x...
```

Optional (set to `address(0)` or omit if not deployed on this chain):
```bash
export VERIFY_BUYBACK_REGISTRY=0x...
export VERIFY_ROUTER_TERMINAL_REGISTRY=0x...
export VERIFY_ROUTER_TERMINAL=0x...
export VERIFY_REV_DEPLOYER=0x...
export VERIFY_REV_LOANS=0x...
```

### Running Verification

```bash
forge script script/Verify.s.sol:Verify \
  --rpc-url <RPC_URL> \
  -vvv
```

This is a read-only script — no `--broadcast` needed.

### Verification Categories

Verify checks 7 categories in order:

| # | Category | What It Checks |
|---|---|---|
| 1 | Project IDs | Projects 1-4 exist, `projects.count() >= 4`, each has correct controller |
| 2 | Directory Wiring | `controllerOf()` returns controller for each project, terminal is registered |
| 3 | Controller Wiring | Controller references correct directory, tokens, rulesets, permissions |
| 4 | Terminal Wiring | Terminal references correct store, directory, permissions, feeless registry |
| 5 | Hook Registries | 721 hook store/deployer wiring, buyback registry default hook, router terminal default |
| 6 | Omnichain | Omnichain deployer references correct controller/directory, sucker deployers are allowed |
| 7 | Price Feeds | ETH/USD and USDC/USD feeds resolve, prices are non-zero and sane |

### Interpreting Results

The script logs each check as `PASS`, `FAIL`, or `SKIP` and prints a summary:

```
========================================
  Verification Summary
========================================
  Passed:  52
  Failed:   0
  Skipped:  3
```

Any `FAIL` triggers a revert with a descriptive reason. Zero failures = deployment is correctly wired.

Skips are normal — they indicate chain-specific components that weren't deployed (e.g., buyback hook on chains without Uniswap V4).

## Operator Checklist: Full Deployment Cycle

This is the complete sequence for deploying to a new chain:

### 1. Prepare

- [ ] Target chain is in the supported chains table above
- [ ] Deployer wallet has sufficient native token for gas
- [ ] External dependencies verified (Uniswap, Chainlink, typeface)
- [ ] Multi-sig address configured in Sphinx

### 2. Dry Run

- [ ] `forge script script/Deploy.s.sol --rpc-url <RPC_URL> -vvvv` completes without revert
- [ ] All 10 phases logged as completed
- [ ] Gas usage is within budget

### 3. Deploy

- [ ] `forge script script/Deploy.s.sol:Deploy --rpc-url <RPC_URL> --broadcast --sender <ADDR> -vvvv`
- [ ] Record all deployed contract addresses from the broadcast log
- [ ] If interrupted: proceed to step 4

### 4. Resume (if needed)

- [ ] `forge script script/Resume.s.sol:Resume --rpc-url <RPC_URL> --broadcast --sender <ADDR> -vvvv`
- [ ] Confirm output shows `Phases skipped` + `Phases executed` totaling 10
- [ ] Check for any `WARNING` messages requiring manual review
- [ ] If Phases 08/09 show warnings: manually verify revnet configuration and Banny project via Etherscan or direct contract queries

### 5. Verify

- [ ] Export all `VERIFY_*` environment variables with deployed addresses
- [ ] `forge script script/Verify.s.sol:Verify --rpc-url <RPC_URL> -vvv`
- [ ] Confirm 0 failures in the summary
- [ ] Review any skipped checks — confirm they correspond to intentionally omitted components

### 6. Post-Verification Spot Checks

These manual checks complement the automated verification:

- [ ] `projects.count()` returns 4 (or expected total if other projects were created)
- [ ] `directory.controllerOf(1)` returns the controller address
- [ ] `prices.pricePerUnitOf(0, 2, 0x000000000000000000000000000000000000EEEe, 18)` returns a non-zero ETH/USD price
- [ ] `feelessAddresses.isFeeless(<routerTerminal>)` returns true
- [ ] `suckerRegistry.suckerDeployerIsAllowed(<deployer>)` returns true for each expected deployer
- [ ] Make a small test payment to project 1 via the terminal
- [ ] Verify the payment appears in the project's balance via `terminalStore.balanceOf()`

### 7. Cross-Chain (Multi-Chain Deployments)

When deploying to multiple chains:

- [ ] Deploy to L1 (Ethereum) first — it's the hub for all sucker bridges
- [ ] Deploy to each L2 using the same deployer + salts
- [ ] Verify each chain independently using `Verify.s.sol`
- [ ] Verify sucker deployer allowlists match across chains
- [ ] Test a cross-chain token bridge: map a token via sucker, send a small amount, verify arrival on the remote chain

## Troubleshooting

**Deploy reverts at Phase 05 (Periphery) with "price feed" error:**
Chainlink feed address may have changed or not be deployed on this chain. Verify feed addresses at https://data.chain.link.

**Resume shows all phases SKIPPED but project count is wrong:**
A third party created a project between the original deploy interruption and resume. Project IDs 1-4 may not correspond to NANA/CPN/REV/BAN. Check `directory.controllerOf()` for each project to determine which is which.

**Verify shows FAIL on "Directory Wiring":**
The controller may not have been set as allowed via `setIsAllowedToSetFirstController`. Resume handles this, but if the original deploy was interrupted between controller deployment and the permission call, resume should fix it.

**Uniswap-dependent phases skip on a chain that should support them:**
Check that `_positionManager` is set to a non-zero address for that chain in `_setupChainAddresses()`. Chains with `_positionManager = address(0)` skip the entire Uniswap stack.
