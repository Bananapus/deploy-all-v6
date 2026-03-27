# Juicebox Deploy All

## Purpose

One-shot Foundry deployment script that deploys the entire Juicebox V6 ecosystem in dependency order within a single Sphinx proposal across Ethereum, Optimism, Base, and Arbitrum (mainnets and testnets).

## Contracts

| Contract | Role |
|----------|------|
| `Deploy` | Forge `Script` + Sphinx deployment script in `script/Deploy.s.sol`. No runtime contracts in `src/`. |

## Key Functions

| Function | What it does |
|----------|--------------|
| `run()` | Entry point. Calls `_setupChainAddresses()` then `deploy()`. |
| `deploy()` | Sphinx-guarded. Executes all 9 deployment phases in order. |
| `_setupChainAddresses()` | Sets WETH, Uniswap V3 factory, V4 PoolManager, and PositionManager addresses based on `block.chainid`. |
| `_shouldDeployUniswapStack()` | Returns `false` for Optimism Sepolia (no PositionManager published there), skipping Uniswap-dependent phases. |
| `_deployCore()` | Phase 01: deploys 13 core contracts (ERC2771Forwarder through JBMultiTerminal). |
| `_deployAddressRegistry()` | Phase 02: deploys JBAddressRegistry. |
| `_deploy721Hook()` | Phase 03a: deploys 721 tier hook stack (store, hook, deployer, project deployer). |
| `_deployUniswapV4Hook()` | Phase 03b: mines a salt for the correct Uniswap V4 hook flags, then deploys JBUniswapV4Hook. |
| `_deployBuybackHook()` | Phase 03c: deploys JBBuybackHookRegistry and JBBuybackHook, wires default hook. |
| `_deployRouterTerminal()` | Phase 03d: deploys JBRouterTerminalRegistry and JBRouterTerminal, marks terminal as feeless. |
| `_deployLpSplitHook()` | Phase 03e: deploys JBUniswapV4LPSplitHook and its deployer. |
| `_deploySuckers()` | Phase 03f: deploys sucker deployers and singletons for OP, Base, Arbitrum (native bridges + CCIP), then JBSuckerRegistry with pre-approved deployers. |
| `_deployOmnichainDeployer()` | Phase 04: deploys JBOmnichainDeployer. |
| `_deployPeriphery()` | Phase 05: deploys JBController (needs omnichain deployer address), ETH/USD and USDC/USD Chainlink price feeds, matching price feed, and deadline contracts (3h, 1d, 3d, 7d). |
| `_deployCroptop()` | Phase 06: creates CPN project (ID 2), deploys CTPublisher, CTDeployer, CTProjectOwner. |
| `_deployRevnet()` | Phase 07: creates REV project (ID 3), deploys REVLoans and REVDeployer, configures $REV revnet (3-stage). |
| `_deployCpnRevnet()` | Phase 08a: configures CPN (project 2) as a 3-stage revnet. |
| `_deployNanaRevnet()` | Phase 08b: configures NANA (project 1, the fee project) as a 1-stage revnet. |
| `_deployBanny()` | Phase 09: creates BAN project (ID 4) with 721 tiers and Banny721TokenUriResolver. |
| `_isDeployed()` | Helper: computes CREATE2 address and checks if bytecode already exists (resume-safe). |
| `_buildSuckerConfig()` | Helper: builds L1-to-L2 (3 deployers) or L2-to-L1 (1 deployer) sucker config. |
| `_ensureProjectExists()` | Helper: creates a project if it does not already exist at the expected ID. |
| `_ensureDefaultPriceFeed()` | Helper: adds a price feed only if one is not already set, reverts if mismatched. |
| `_findHookSalt()` | Helper: brute-force mines a CREATE2 salt matching Uniswap V4 hook flag requirements. |

## Deployment Phases

| Phase | What | Key Contracts |
|-------|------|---------------|
| 01 | Core protocol | ERC2771Forwarder, JBPermissions, JBProjects, JBDirectory, JBSplits, JBRulesets, JBPrices, JBTokens, JBERC20, JBFundAccessLimits, JBFeelessAddresses, JBTerminalStore, JBMultiTerminal |
| 02 | Address registry | JBAddressRegistry |
| 03a | 721 tier hook | JB721TiersHookStore, JB721TiersHook, JB721TiersHookDeployer, JB721TiersHookProjectDeployer |
| 03b | Uniswap V4 router hook | JBUniswapV4Hook (skipped on OP Sepolia) |
| 03c | Buyback hook | JBBuybackHookRegistry, JBBuybackHook (skipped on OP Sepolia) |
| 03d | Router terminal | JBRouterTerminalRegistry, JBRouterTerminal (skipped on OP Sepolia) |
| 03e | LP split hook | JBUniswapV4LPSplitHook, JBUniswapV4LPSplitHookDeployer (skipped on OP Sepolia) |
| 03f | Cross-chain suckers | JBOptimismSuckerDeployer, JBBaseSuckerDeployer, JBArbitrumSuckerDeployer, JBCCIPSuckerDeployer, JBSuckerRegistry + singletons |
| 04 | Omnichain deployer | JBOmnichainDeployer |
| 05 | Periphery | JBController, Chainlink ETH/USD + USDC/USD price feeds, JBMatchingPriceFeed, JBDeadline{3Hours,1Day,3Days,7Days} |
| 06 | Croptop | CPN project (ID 2), CTPublisher, CTDeployer, CTProjectOwner |
| 07 | Revnet | REV project (ID 3), REVLoans, REVDeployer, $REV revnet configuration |
| 08 | CPN + NANA revnets | Configure project 2 (CPN) and project 1 (NANA) as revnets |
| 09 | Banny | BAN project (ID 4) with 721 tiers and Banny721TokenUriResolver |

## Project IDs

| ID | Name | Configured As |
|----|------|---------------|
| 1 | NANA | Fee recipient project. 1-stage revnet (10,000 tokens/ETH, 62% split, 38% issuance cut per 360 days, 10% cashout tax). |
| 2 | CPN | Croptop project. 3-stage revnet. |
| 3 | REV | Revnet project. 3-stage revnet (90-day issuance cuts in stage 1, transitions to 30-day in stage 2, then terminal stage 3). |
| 4 | BAN | Banny project. Revnet with 721 tier hook (NFT tiers). |

## Errors

| Error | Trigger |
|-------|---------|
| `Deploy_ExistingAddressMismatch(expected, actual)` | On a rerun, an already-deployed contract does not match the expected address. Happens when `JBBuybackHookRegistry.defaultHook()` or `JBRouterTerminalRegistry.defaultTerminal()` returns a different address. |
| `Deploy_ProjectIdMismatch(expected, actual)` | `JBProjects.createFor()` returned a different ID than expected (projects were created out of order). |
| `Deploy_PriceFeedMismatch(projectId, pricingCurrency, unitCurrency)` | A price feed already exists for the given currency pair but does not match the expected feed address. |
| `Resume_PriceFeedMismatch(projectId, pricingCurrency, unitCurrency)` | Same check in `Resume.s.sol`: a registered price feed does not match the expected feed. The resume script now reverts on mismatch instead of silently accepting the wrong feed. |
| `revert("Unsupported chain")` | `_setupChainAddresses()` called on a chain not in the supported list. |
| `revert("Unsupported chain for ETH/USD feed")` | No Chainlink ETH/USD aggregator is configured for the current chain. |
| `revert("Unsupported chain for USDC feed")` | No Chainlink USDC/USD aggregator is configured for the current chain. |
| `revert("HookMiner: could not find salt")` | `_findHookSalt()` exhausted `MAX_LOOP` iterations without finding a valid hook address. Should not happen in practice. |

## Environment Variables

| Variable | Required | Source | Purpose |
|----------|----------|--------|---------|
| `SPHINX_ORG_ID` | Yes (deployment) | `.env` | Sphinx organization ID for multi-chain proposal |
| `DEPLOY_NETWORK` | No | `.env` | `"testnets"` or `"mainnets"` -- informational, actual target set in the `sphinx propose` CLI flag |
| `RPC_ETHEREUM_MAINNET` | Yes (fork tests) | `foundry.toml` | Ethereum mainnet RPC URL |
| `RPC_OPTIMISM_MAINNET` | Yes (fork tests) | `foundry.toml` | Optimism mainnet RPC URL |
| `RPC_BASE_MAINNET` | Yes (fork tests) | `foundry.toml` | Base mainnet RPC URL |
| `RPC_ARBITRUM_MAINNET` | Yes (fork tests) | `foundry.toml` | Arbitrum mainnet RPC URL |

## Execution

### Commands

```bash
# Install dependencies
npm install

# Build
forge build

# Run fork tests (requires mainnet RPC URLs)
forge test --match-path "test/fork/*" -vvv --fork-url $RPC_ETHEREUM_MAINNET

# Propose testnet deployment via Sphinx
npx sphinx propose script/Deploy.s.sol --networks testnets

# Propose mainnet deployment via Sphinx
npx sphinx propose script/Deploy.s.sol --networks mainnets
```

### Deployment Chains

Configured in `configureSphinx()`:

- **Mainnets**: Ethereum (1), Optimism (10), Base (8453), Arbitrum (42161)
- **Testnets**: Ethereum Sepolia (11155111), Optimism Sepolia (11155420), Base Sepolia (84532), Arbitrum Sepolia (421614)

## Chain-Specific Considerations

- **Optimism Sepolia** (`11155420`): Uniswap V4 PositionManager is not published. `_shouldDeployUniswapStack()` returns `false`, skipping phases 03b-03e (Uniswap V4 hook, buyback hook, router terminal, LP split hook). All other phases proceed normally.
- **L2 sequencer feeds**: On Optimism, Base, and Arbitrum mainnets, the ETH/USD and USDC/USD price feeds use `JBChainlinkV3SequencerPriceFeed` with a sequencer uptime check and 1-hour grace period after restart. Testnets use the simpler `JBChainlinkV3PriceFeed` without sequencer checks.
- **Arbitrum L2 inbox**: On Arbitrum L2, the sucker deployer is configured with `inbox = address(0)` (inbox is only used on L1 for retryable tickets). The deployer's validation is layer-aware and accepts this.
- **CCIP suckers**: On L1, CCIP sucker deployers are created for all three L2s (OP, Base, Arbitrum). Each L2 deploys CCIP deployers for the other two L2s plus L1 (full mesh).
- **Native bridge suckers**: OP and Base use the same OP-stack bridge pattern (`JBOptimismSucker`/`JBBaseSucker`). Arbitrum uses `JBArbitrumSucker` with its gateway router. Native bridge deployers only connect L1 to a single L2 (no L2-to-L2).

## Integration Points

| Dependency | Used For |
|------------|----------|
| `nana-core-v6` | Core protocol contracts (JBProjects through JBMultiTerminal) |
| `nana-721-hook-v6` | NFT tier hook stack |
| `nana-buyback-hook-v6` | Buyback hook and registry |
| `nana-router-terminal-v6` | Router terminal for token swaps |
| `nana-suckers-v6` | Cross-chain sucker infrastructure |
| `nana-omnichain-deployers-v6` | Omnichain deployer (controller data hook) |
| `revnet-core-v6` | REVDeployer, REVLoans, and revnet structs |
| `croptop-core-v6` | CTPublisher, CTDeployer, CTProjectOwner |
| `banny-retail-v6` | Banny721TokenUriResolver |
| `univ4-router-v6` | JBUniswapV4Hook |
| `univ4-lp-split-hook-v6` | JBUniswapV4LPSplitHook and deployer |
| `@sphinx-labs/plugins` | Multi-chain deployment coordination with team approval |
| `@uniswap/v4-core` | IPoolManager, Hooks, HookMiner |
| `@uniswap/v4-periphery` | IPositionManager, HookMiner |
| `@uniswap/v3-core` | IUniswapV3Factory (for router terminal) |
| `@uniswap/permit2` | IPermit2, IAllowanceTransfer |
| `@chainlink/contracts` | AggregatorV3Interface for price feeds |

## Recovery Model

The script uses `_isDeployed()` to check each CREATE2 address before deploying. If bytecode already exists, it reuses the existing contract. This makes reruns partially safe for contract creation, but **not** for wiring calls (`setDefaultHook`, `setDefaultTerminal`, `setIsAllowedToSetFirstController`, etc.).

If a Sphinx execution stops mid-proposal:

1. **Safe to re-propose**: contract deployments will be skipped if already deployed (CREATE2 collision detection).
2. **Wiring calls**: guarded by `if` checks (e.g., `if (address(_buybackRegistry.defaultHook()) == address(0))`), so they are also idempotent.
3. **Project creation**: `_ensureProjectExists()` checks `_projects.count()` and skips if the project already exists.
4. **Revnet configuration**: guarded by `if (address(_directory.controllerOf(_revProjectId)) == address(0))`, so a configured revnet will not be re-deployed.

If wiring state is partially set and mismatches expectations, the script will revert with `Deploy_ExistingAddressMismatch` or `Deploy_PriceFeedMismatch` to prevent inconsistent state.

## Gotchas

- **No `src/` directory** -- this repo is purely a deployment script. All deployed contracts come from dependencies.
- **Optimizer disabled** -- `via_ir = true` but `optimizer = false` in `foundry.toml`. Enabling the optimizer causes stack-too-deep errors due to the script's size (~2,230 lines). The `ci_sizes` profile enables it for size checks only.
- **Phase ordering matters** -- JBController deployment (Phase 05) depends on JBOmnichainDeployer (Phase 04) for the `omnichainRulesetOperator` constructor argument. Reordering phases will cause incorrect wiring.
- **Project ID ordering matters** -- Projects are created sequentially (1=NANA, 2=CPN, 3=REV, 4=BAN). If any project is created out of order, `_ensureProjectExists()` reverts with `Deploy_ProjectIdMismatch`.
- **`safeAddress()` is the deployer** -- All `owner` parameters use `safeAddress()` (the Sphinx multisig). This is the admin for JBDirectory, JBPrices, JBFeelessAddresses, JBBuybackHookRegistry, JBRouterTerminalRegistry, and JBSuckerRegistry.
- **Deterministic addresses** -- All contracts use CREATE2 with explicit salts. The same proposal on different chains produces the same addresses (assuming the same Sphinx safe address).
- **Uniswap V4 hook salt mining** -- `_findHookSalt()` brute-forces a salt that produces a hook address matching the required Uniswap V4 flag bits. This is a pure computation that runs at proposal time.
- **CCIP sucker full mesh** -- L1 deploys 3 CCIP deployers (one per L2). Each L2 deploys 3 CCIP deployers (one per L2 + L1). This creates a full mesh of CCIP cross-chain bridges.
- **Fork tests require multiple RPCs** -- The test suite needs `RPC_ETHEREUM_MAINNET`, `RPC_OPTIMISM_MAINNET`, `RPC_BASE_MAINNET`, and `RPC_ARBITRUM_MAINNET` for comprehensive coverage.
- **Feeless router terminal** -- The router terminal is automatically marked feeless via `_feeless.setFeelessAddress()`. Payments through it do not incur protocol fees.
- **Defifa is deployed in Phase 10** -- `_deployDefifa()` deploys DefifaHook, DefifaTokenUriResolver, DefifaGovernor, and DefifaDeployer. Uses the REV project (ID 3) as the fee project.
- **`DEFIFA_SALT` is `bytes32(keccak256("0.0.2"))`** -- Both `Deploy.s.sol` and `Resume.s.sol` now use the same salt value. An earlier version of `Resume.s.sol` used the literal `"_DEFIFA_SALTV6_"`, which would produce different CREATE2 addresses and fail to detect already-deployed Defifa contracts.
