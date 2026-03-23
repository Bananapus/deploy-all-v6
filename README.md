# Juicebox Deploy All

Single Foundry script that deploys the current canonical Juicebox V6 rollout via [Sphinx](https://github.com/sphinx-labs/sphinx) across the configured chains.

## Chains

**Mainnets:** Ethereum, Optimism, Base, Arbitrum
**Testnets:** Ethereum Sepolia, Optimism Sepolia, Base Sepolia, Arbitrum Sepolia

The script contains chain-specific addresses for the supported chains, but the testnet matrix is not equally mature.
Optimism Sepolia remains supported for the non-Uniswap rollout. Its Uniswap-dependent phases are skipped because
Uniswap V4 does not publish a `PositionManager` there.

## Deployment Phases

The script deploys contracts in dependency order within one Sphinx proposal:

| Phase | What's deployed | Key contracts |
|-------|----------------|---------------|
| 01 | Core protocol | ERC2771Forwarder, JBPermissions, JBProjects, JBDirectory, JBSplits, JBRulesets, JBPrices, JBTokens, JBERC20, JBFundAccessLimits, JBFeelessAddresses, JBTerminalStore, JBMultiTerminal |
| 02 | Address registry | JBAddressRegistry |
| 03a | 721 tier hook | JB721TiersHook, JB721TiersHookDeployer, JB721TiersHookProjectDeployer, JB721TiersHookStore |
| 03b | Uniswap V4 router hook | JBUniswapV4Hook |
| 03c | Buyback hook | JBBuybackHook, JBBuybackHookRegistry |
| 03d | Router terminal | JBRouterTerminal, JBRouterTerminalRegistry |
| 03e | LP split hook | JBUniswapV4LPSplitHook, JBUniswapV4LPSplitHookDeployer |
| 03f | Cross-chain suckers | JBOptimismSucker, JBBaseSucker, JBArbitrumSucker, JBCCIPSucker, JBSuckerRegistry + deployers |
| 04 | Omnichain deployer | JBOmnichainDeployer |
| 05 | Periphery | JBController, price feeds (Chainlink V3 + sequencer), deadlines (3h, 1d, 3d, 7d) |
| 06 | Croptop | CPN project (ID 2), CTDeployer, CTPublisher |
| 07 | Revnet | REV project (ID 3), REVLoans, REVDeployer |
| 08 | CPN + NANA revnets | Configure project 2 and project 1 as revnets |
| 09 | Banny | BAN project (ID 4) |

The current script does **not** deploy Defifa or `JBOwnable`. It does deploy the canonical Uniswap V4 stack:
`JBUniswapV4Hook`, `JBBuybackHook` wired to that router hook as its oracle, and
`JBUniswapV4LPSplitHook` plus `JBUniswapV4LPSplitHookDeployer`.

## Recovery Model

This repo does **not** currently ship a resumable partial-deployment recovery script. If a live Sphinx execution stops
after some CREATE2 deployments succeed, re-proposing the full script with the same salts is not a safe recovery path:
those deployments will collide with contracts that already exist.

Operationally, treat recovery as one of two explicit options:

1. Resume with a purpose-built script that skips already-deployed contracts and performs only the remaining wiring.
2. Redeploy from fresh salts and discard the partial deployment.

Do not rely on ad hoc re-proposal of the full script after a partial execution.

## Prerequisites

- [Foundry](https://getfoundry.sh)
- Node.js >= 20
- All sibling V6 repos cloned as siblings (this repo uses `file:` dependencies)

## Setup

```bash
npm install
forge build
```

## Deployment Commands

| Command | Description |
|---------|-------------|
| `npx sphinx propose script/Deploy.s.sol --networks testnets` | Propose testnet deployment via Sphinx |
| `npx sphinx propose script/Deploy.s.sol --networks mainnets` | Propose mainnet deployment via Sphinx |
| `forge test --match-path "test/fork/*" -vvv --fork-url $RPC_ETHEREUM_MAINNET` | Run fork tests against mainnet state |

Set `SPHINX_ORG_ID` in `.env` before proposing. See `.env.example` for the required variables.

## Deployment Verification

After Sphinx executes an approved proposal, verify the deployment:

1. **Sphinx dashboard** -- confirm all transactions landed on every target chain. Each chain should show a completed execution with no skipped or failed steps.
2. **Contract existence** -- for each deployed address, run `cast code <address> --rpc-url <chain_rpc>` and confirm non-empty bytecode.
3. **Etherscan verification** -- Sphinx auto-verifies source on supported explorers. Spot-check a few contracts (e.g. `JBController`, `JBMultiTerminal`) on the relevant block explorer to confirm verified source is visible.
4. **Wiring checks** -- validate critical post-deployment state:
   - `JBDirectory.isAllowedToSetFirstController(controller)` returns `true`.
   - `JBPrices.pricePerUnitOf(...)` returns a live ETH/USD price.
   - `JBBuybackHookRegistry.defaultHook()` returns the buyback hook address.
   - `JBSuckerRegistry.isSuckerDeployerAllowed(deployer)` returns `true` for each deployer.
   - Projects 1-4 exist via `JBProjects.ownerOf(projectId)`.
5. **Smoke test** -- send a small payment to project 1 and confirm tokens are minted and the terminal balance increases.

## Dependencies

All V6 dependencies are installed from npm:

| Package | Repo |
|---------|------|
| `@bananapus/core-v6` | nana-core-v6 |
| `@bananapus/permission-ids-v6` | nana-permission-ids-v6 |
| `@bananapus/address-registry-v6` | nana-address-registry-v6 |
| `@bananapus/721-hook-v6` | nana-721-hook-v6 |
| `@bananapus/buyback-hook-v6` | nana-buyback-hook-v6 |
| `@bananapus/router-terminal-v6` | nana-router-terminal-v6 |
| `@bananapus/suckers-v6` | nana-suckers-v6 |
| `@bananapus/omnichain-deployers-v6` | nana-omnichain-deployers-v6 |
| `@bananapus/ownable-v6` | nana-ownable-v6 |
| `@bananapus/univ4-router-v6` | univ4-router-v6 |
| `@bananapus/univ4-lp-split-hook-v6` | univ4-lp-split-hook-v6 |
| `@rev-net/core-v6` | revnet-core-v6 |
| `@croptop/core-v6` | croptop-core-v6 |
| `@bannynet/core-v6` | banny-retail-v6 |
| `@ballkidz/defifa` | defifa-collection-deployer-v6 |

## Build Configuration

- Solidity 0.8.26, Cancun EVM
- `via_ir = true` (required for stack depth)
- Optimizer disabled (stack-too-deep with optimization enabled)
- Sphinx plugin for multi-chain atomic deployment

## Repository Layout

```
deploy-all-v6/
├── script/
│   └── Deploy.s.sol        # Single Sphinx deployment script (all 9 phases)
├── src/                     # Empty -- no application contracts (deployment-only repo)
├── test/
│   └── fork/                # Fork tests that replay the deployment against live mainnet state
│       ├── ApprovalHookFork.t.sol
│       ├── BuybackRouterFork.t.sol
│       ├── CrossCurrencyFork.t.sol
│       ├── DeployFork.t.sol
│       ├── DeployFullStack.t.sol
│       ├── DeployScriptVerification.t.sol
│       ├── EcosystemFork.t.sol
│       ├── FullStackFork.t.sol
│       ├── HookCompositionFork.t.sol
│       ├── LPBuybackInteropFork.t.sol
│       ├── PayoutReentrancyFork.t.sol
│       ├── PriceFeedFailureFork.t.sol
│       ├── ReservedInflationFork.t.sol
│       ├── ResumeDeployFork.t.sol
│       ├── SuckerBuybackFork.t.sol
│       ├── SuckerEndToEndFork.t.sol
│       ├── TestFeeProcessingCascade.t.sol
│       ├── TestMultiCurrencyPayout.t.sol
│       ├── TestTerminalMigration.t.sol
│       ├── USDCEcosystemFork.t.sol
│       └── USDCRevnetFork.t.sol
├── lib/
│   └── forge-std/           # Foundry standard library
├── foundry.toml             # Forge config (via_ir, Cancun, optimizer off)
├── package.json             # npm dependencies linking all sibling V6 repos
└── remappings.txt           # Solidity import remappings
```

## License

MIT
