# Juicebox V6 Deployment Runbook

Operator guide for deploying, resuming, and verifying the Juicebox V6 ecosystem.

## Supported chains

| Chain | ID | Uniswap V4 | Suckers |
|---|---|---|---|
| Ethereum Mainnet | 1 | Yes | OP, Base, Arb, CCIP |
| Ethereum Sepolia | 11155111 | Yes | OP Sepolia, Base Sepolia, Arb Sepolia, CCIP |
| Optimism | 10 | Yes | Ethereum, CCIP |
| Optimism Sepolia | 11155420 | Partial (no PositionManager) | Ethereum Sepolia, CCIP |
| Base | 8453 | Yes | Ethereum, CCIP |
| Base Sepolia | 84532 | Yes | Ethereum Sepolia, CCIP |
| Arbitrum One | 42161 | Yes | Ethereum, CCIP |
| Arbitrum Sepolia | 421614 | Yes | Ethereum Sepolia, CCIP |

Chains without a PositionManager skip active Uniswap routing surfaces (buyback hook, router terminal, and LP split hook). Revnets still deploy; BAN keeps its reserved split routed to the operator on those chains.

The canonical deployment allowlists standard OP, Base, Arbitrum, and CCIP deployers. CPN, NANA, and REV use the standard native bridge deployers; BAN, DEFIFA, and MARKEE use the route-specific CCIP deployers with native-token mappings.

## Deployment phases

The deploy script (`script/Deploy.s.sol`) executes 11 phases in strict order:

| Phase | What | Creates |
|---|---|---|
| 01 | Core Protocol | Permissions, Projects, Prices, Rulesets, Directory, JBERC20, Tokens, Splits, Feeless, FundAccessLimits, TerminalStore, MultiTerminal, ERC2771Forwarder |
| 02 | Address Registry | JBAddressRegistry |
| 03a | 721 Tier Hook | HookStore, CheckpointsDeployer, TiersHook, HookDeployer, HookProjectDeployer |
| 03b | Uniswap V4 Router Hook | JBUniswapV4Hook (requires PoolManager) |
| 03c | Buyback Hook | JBBuybackHookRegistry; JBBuybackHook on chains with the Uniswap stack |
| 03d | Router Terminal | JBRouterTerminalRegistry; JBRouterTerminal on chains with the Uniswap stack |
| 03e | Cross-Chain Suckers | JBSuckerRegistry + per-bridge deployers (OP, Base, Arb, CCIP) |
| 03f | LP Split Hook | JBUniswapV4LPSplitHook (requires PositionManager and SuckerRegistry) |
| 04 | Omnichain Deployer | JBOmnichainDeployer |
| 05 | Periphery | Controller, Price Feeds (ETH/USD, USD/ETH, ETH/native, USDC/USD, sequencer-aware on L2), Deadline hooks |
| 06 | Croptop | CTDeployer, CTPublisher, CTProjectOwner; creates CPN project (ID 2) |
| 07 | Revnet | REVLoans, REVDeployer; creates REV project (ID 3) |
| 08 | Revnet Config | Configures CPN (project 2) and NANA (project 1) as revnets |
| 09 | Banny | Banny721TokenUriResolver; creates BAN project (ID 4) |
| 10 | Defifa | DefifaHook, DefifaTokenUriResolver, DefifaGovernor, DefifaDeployer |
| 11 | Periphery Extensions | JBProjectHandles, JBProjectPayerDeployer |

All contracts use CREATE2 with deterministic salts. Addresses are identical across chains for the same salt + initcode.

## Pre-deploy checklist

Before running a deployment:

1. **Confirm chain support.** Verify the target chain ID is in `_setupChainAddresses()`.
2. **Confirm external dependencies exist.** For Uniswap-dependent chains, verify PoolManager + PositionManager are deployed at the expected addresses. Check https://docs.uniswap.org/contracts/v4/deployments.
3. **Confirm Chainlink feeds.** For L1: ETH/USD + USDC/USD feeds. For L2: same feeds + sequencer uptime feed. Addresses are in `_deployPeriphery()`.
4. **Confirm typeface.** The Capsules SVG font contract must be deployed at the chain-specific address in `_setupChainAddresses()`.
5. **Dry run.** Execute against a fork first:
   ```bash
   forge script script/Deploy.s.sol \
     --rpc-url <RPC_URL> \
     --sender 0x4dc161eF837fF1C4485b08DDFcDB182F2157bE18 \
     -vvvv
   ```
   No `--broadcast` flag = simulation only. `--sender` must be the V6 deployment Sphinx safe (also `_EXPECTED_SAFE` in `Deploy.s.sol`); without it, `REVOwner.setDeployer` reverts with `REVOwner_Unauthorized` because the binder cached at REVOwner construction differs from `msg.sender` at the wire-up call. Production runs via `npx sphinx propose` set this automatically — the override is only for raw `forge script`.
6. **Gas estimation.** Full deploy is ~50M+ gas across all phases. Ensure the deployer has sufficient ETH/native token.
7. **Safe address.** The deploy script uses Sphinx for multi-sig execution. Confirm `safeAddress()` returns the correct multi-sig for the target chain.

## Running the deploy

Deployments are executed through [Sphinx](https://sphinx.dev), which batches the deploy transactions through the multi-sig safe. The Sphinx CLI proposes the deployment, which must then be approved by safe signers.

### Pre-deploy rehearsal (gas-free address + ABI preview)

Before any real broadcast, run `script/rehearse-addresses.sh` to produce the deterministic CREATE2 addresses and the full ABI bundle for every supported chain. Nothing is signed or sent on-chain — the simulation runs in a per-chain anvil fork and `_dumpAddresses` writes the same CREATE2 addresses the eventual Sphinx broadcast will land at. Use this to:

- Hand auditors / frontends / indexers the exact addresses ahead of launch.
- Confirm cross-chain CREATE2 determinism (every chain-independent contract — `JBProjects`, `JBController`, etc. — must land at the same address across all 8 chains).
- Catch deploy-script reverts (e.g. mis-ordered stage times, bad chain-specific constructor inputs) before paying gas.

```bash
./script/rehearse-addresses.sh                     # all 8 supported chains (~3–5 min)
./script/rehearse-addresses.sh 1 10 8453 42161     # production mainnets only
./script/rehearse-addresses.sh 11155111            # single chain (e.g. Sepolia)
```

Requires the chain's RPC env var (`RPC_ETHEREUM_MAINNET`, `RPC_OPTIMISM_SEPOLIA`, …) in `.env`. The script spins up an anvil fork per chain (so the safe's zero-balance doesn't trip Optimism's `lack of funds (0)` simulation gate), credits the safe via `anvil_setBalance`, runs the deploy simulation, and copies each chain's address dump into `rehearsal-output/`.

Output layout:

```
rehearsal-output/
├── abis/                                            # 71 chain-independent ABI JSONs
├── addresses-1-ethereum-mainnet.json                # per-chain CREATE2 addresses
├── addresses-10-optimism-mainnet.json
├── addresses-8453-base-mainnet.json
├── addresses-42161-arbitrum-mainnet.json
├── addresses-11155111-ethereum-sepolia.json
├── addresses-11155420-optimism-sepolia.json
├── addresses-84532-base-sepolia.json
├── addresses-421614-arbitrum-sepolia.json
└── <label>-deploy.log / <label>-anvil.log          # per-chain traces for debugging
```

The bundle is `.gitignore`d — re-run the script anytime to refresh.

### Dry run (Forge simulation)

```bash
forge script script/Deploy.s.sol \
  --rpc-url <RPC_URL> \
  --sender 0x4dc161eF837fF1C4485b08DDFcDB182F2157bE18 \
  -vvvv
```

No `--broadcast` flag = simulation only. The `--sender` override impersonates the Sphinx safe for the simulation so the REVOwner wire-up call (and any other safe-gated calls) passes; production via `npx sphinx propose` handles this automatically. Verify all phases complete without revert, and that `script/post-deploy/.cache/addresses-<chainId>.json` is emitted at the end.

### Production deploy (via Sphinx)

```bash
pnpm artifacts                                # pre-compile every contract from its installed package
pnpm deploy:propose:testnets                  # → npx sphinx propose script/Deploy.s.sol --networks testnets
# (or:)
pnpm deploy:propose:mainnets                  # → npx sphinx propose script/Deploy.s.sol --networks mainnets

# After safe signers approve + Sphinx executes on-chain:
ETHERSCAN_API_KEY=... pnpm deploy:post:testnets   # verify + emit + distribute
```

> **Always route propose through the `pnpm deploy:propose:*` scripts.** They prepend the required
> `DEFIFA_REV_START_TIME` env var and pass the correct CLI shape. If you must invoke the CLI
> directly, replicate both: the script positional and the `--networks <name>` flag (the CLI has no
> `--testnets` / `--mainnets` switches), and export `DEFIFA_REV_START_TIME` first (see below):
>
> ```bash
> # Defifa/REV game start time (seconds since epoch). Default: now + 1 day.
> DEFIFA_REV_START_TIME=$(($(date +%s) + 86400)) \
>   npx sphinx propose script/Deploy.s.sol --networks testnets   # or --networks mainnets
> ```
>
> A raw `npx sphinx propose` without `DEFIFA_REV_START_TIME` set deploys the Defifa/REV game with a
> different (un-pinned) start time than the canonical scripts intend.

Sphinx compiles the deploy script, simulates it, and proposes the resulting transactions to the multi-sig safe. Safe signers must approve the proposal before execution. Verification and artifact emission are then handled locally by `post-deploy.sh` (see [Post-Deploy: Verification + Artifact Emission](#post-deploy-verification--artifact-emission) below).

> **Note:** Sphinx replays `new Contract{salt: ...}(...)` through the canonical CREATE2 deployer (`0x4e59b44847b379578588920cA78FbF26c0B4956C`). The `_isDeployed` helper must compute addresses using this factory as the deployer (not `safeAddress()`) for Uniswap V4 hook deployments where address flags matter.

Monitor execution in the Sphinx dashboard or on-chain via the safe's transaction history.

### Sphinx and CREATE2

Sphinx 0.23.x routes Solidity `new {salt}` deployments through the deterministic deployment proxy (`0x4e59b44847b379578588920cA78FbF26c0B4956C`). This is handled automatically by the Sphinx TypeScript decoder (`isCreate2AccountAccess()`), which detects `CREATE2` opcodes in the simulation trace and replays them through the canonical factory.

Key points:
- Deploy.s.sol uses `new Contract{salt: ...}(...)` syntax throughout. Sphinx intercepts these and replays them as `CREATE2` calls to the deterministic proxy.
- The v5 deployment used the same pattern successfully.
- The `_isDeployed` helper computes expected addresses using `safeAddress()` as the deployer for most contracts. For Uniswap V4 hooks (where address bit-flags matter), addresses are computed using the `_CREATE2_FACTORY` instead.
- No special action is needed from operators — this is standard Sphinx behavior.

### Execution model

**Deploy.s.sol** is executed through Sphinx. The operator runs `npx sphinx propose`, which:
1. Compiles and simulates the deploy script locally
2. Proposes the resulting transactions to the multi-sig Safe
3. Safe signers approve the proposal in the Sphinx dashboard or Safe UI
4. Sphinx executes the approved transactions on-chain

If a deploy is interrupted, recovery is to bump the deployment nonce in **Deploy.s.sol** and re-propose it through Sphinx, which redeploys the full stack from fresh salts at a clean, non-colliding address namespace. See [Interrupted Deploy: Redeploying From Fresh Salts](#interrupted-deploy-redeploying-from-fresh-salts).

**Verify.s.sol** is read-only and requires no broadcast. It reads deployed state and validates wiring.

**LivePostDeploySmoke.s.sol** is executed through Sphinx after read-only verification. It proposes a small, budgeted set of real production actions from the V6 deployment Safe: core-project buyback payments, partial cash-outs when available, and a REV loan open/repay round trip.

### Post-deploy: verification and artifact emission

**Sphinx's auto-verification and auto-artifact pipeline are intentionally bypassed in v6.** Every contract that Deploy.s.sol routes through `_loadCreationCode` + `_deployFromArtifact` is pre-compiled from its installed npm package with the manifest's recorded compile profile (`via_ir` + `optimizerRuns`), then deployed via raw bytecode. Sphinx's bundled verifier doesn't know about that pre-compile step and would submit the wrong settings to Etherscan. Instead, v6 ships a local pipeline at `script/post-deploy.sh`.

After a successful `npx sphinx propose` + safe-signer approval + on-chain execution, run:

```bash
export ETHERSCAN_API_KEY=...        # single key for Etherscan v2 unified API
./script/post-deploy.sh --chains=all-testnets   # or all-mainnets, or a CSV like ethereum,optimism
```

What it does, per chain:

1. **Dump addresses.** Runs `forge script Deploy.s.sol --rpc-url $RPC_<CHAIN>` (no broadcast) to compute every deployed contract's CREATE2 address and emit `script/post-deploy/.cache/addresses-<chainId>.json`.
2. **Verify on Etherscan.** Shells out to `forge verify-contract` from each contract's manifest source root with the manifest's compiler flags, using `node_modules/` source paths for npm packages. Retries transient failures (rate limits, 5xx, "pending in queue") with exponential backoff (1s → 60s, up to 10 attempts). Permanent failures (source mismatch, compiler mismatch) are logged per-contract; other contracts continue.
3. **Emit artifacts.** Produces v5-compatible `sphinx-sol-ct-artifact-1` JSON per contract (same schema as `nana-core-v5/deployments/...`, **minus** `merkleRoot` since we're not Sphinx-managed). Fields: `address`, `sourceName`, `contractName`, `chainId` (hex), `abi`, `args`, `solcInputHash`, `receipt`, `bytecode`, `deployedBytecode`, `metadata`, `gitCommit`, `gitDirty`, `history`. Tab-indented to match v5 byte-for-byte (gitDirty surfaces source-tree provenance per artifact, not just in the sidecar manifest).
4. **Distribute.** Copies each artifact to:
   - `deploy-all-v6/deployments/<chain_alias>/<Contract>.json` (aggregator)
   - `<repo>/deployments/<sphinxProject>/<chain_alias>/<Contract>.json` (per-repo, mirrors v5)

All four steps are idempotent. Reruns skip already-verified contracts via `.cache/status-<chainId>.json`. The compile-settings manifest is at `artifacts/artifacts.manifest.json` (regenerated by `./script/build-artifacts.sh`).

#### Where deployed addresses live

- **Runtime address dump (per chain):** `script/post-deploy/.cache/addresses-<chainId>.json` — every deployed contract's CREATE2 address, emitted by the dump step (and by a no-broadcast `Deploy.s.sol` run). This is the working cache the verifier and distribute step read from.
- **Canonical published tree (aggregator):** `deployments/<chain_alias>/<Contract>.json` in this repo — one artifact JSON per contract, copied here by the distribute step.
- **Per-repo mirrors:** `<sibling-repo>/deployments/<sphinxProject>/<chain_alias>/<Contract>.json` (e.g. `nana-core-v6/deployments/<chain_alias>/...`), mirroring the v5 layout.

V6 is currently **testnet-only** — the published `deployments/` tree contains only the Sepolia aliases (`sepolia`, `optimism_sepolia`, `base_sepolia`, `arbitrum_sepolia`). No mainnet addresses are published yet.

#### Required env vars

- `ETHERSCAN_API_KEY` — one key, used for every chain via the Etherscan v2 unified API (sign up at https://etherscan.io/myapikey).
- `RPC_<CHAIN>` — one per chain processed. `RPC_ETHEREUM_MAINNET`, `RPC_OPTIMISM_MAINNET`, `RPC_BASE_MAINNET`, `RPC_ARBITRUM_MAINNET`, plus the `_SEPOLIA` variants for testnets.

#### Granular control

```bash
./script/post-deploy.sh --chains=sepolia                       # one chain
./script/post-deploy.sh --chains=base,arbitrum                 # subset
./script/post-deploy.sh --skip-verify                          # artifact emit + distribute only
./script/post-deploy.sh --skip-artifacts --skip-distribute     # verify only
./script/post-deploy.sh --chains=sepolia --dry-run             # show what would happen
./script/post-deploy.sh --chains=sepolia --rehearsal           # allow gitDirty manifest on prod chains
```

#### Source provenance gate (`--rehearsal`)

Production artifact builds must be reproducible from a clean source. Published dependency contracts are compiled from installed npm packages and are treated as clean by package version; local `deploy-all-v6` artifacts still use the working tree and are dirty-gated. Without acknowledgment, both `./script/build-artifacts.sh` and `./script/post-deploy.sh` (and the underlying `verify.mjs` / `artifacts.mjs`) refuse to proceed when a local source root has uncommitted changes, since the published artifacts would be unverifiable.

- **`./script/build-artifacts.sh`** scans every source repo. If any are dirty, it exits non-zero with the list of dirty repos. Re-run with `--rehearsal` to build a marked-dirty rehearsal artifact set (manifest top-level `"gitDirty": true`, every emitted artifact stamped `"gitDirty": true`).
- **`./script/post-deploy.sh`** (and the underlying `verify.mjs` + `artifacts.mjs`) consult the manifest's `gitDirty` flag and the chain's `production` flag in `script/post-deploy/chains.json`. If both are true and `--rehearsal` is not passed, the chain is skipped before any Etherscan call. Testnets (`sepolia`, `optimism_sepolia`, `base_sepolia`, `arbitrum_sepolia`) have `production: false` and are unaffected.

Required production-chain rehearsal flow:

```bash
./script/build-artifacts.sh                          # fails if anything dirty
./script/post-deploy.sh --chains=all-mainnets        # fails if manifest gitDirty
```

Rehearsal flow (only for local testing on a fork):

```bash
./script/build-artifacts.sh --rehearsal              # stamps gitDirty in manifest + artifacts
./script/post-deploy.sh --chains=ethereum --rehearsal
```

`gitDirty: true` entries are also surfaced inside every emitted artifact JSON (not just the sidecar manifest), so any downstream consumer of `deployments/<repo>/<chain>/<Contract>.json` can detect non-canonical builds without cross-referencing the manifest.

Source repos compile with `bytecode_hash = "none"` in their `foundry.toml` so the deployed runtime code is byte-equal to the artifact's `deployedBytecode.object`. This lets the verifier compare `extcodehash` directly against the artifact's runtime code hash; without `bytecode_hash = "none"`, solc embeds a per-build IPFS metadata hash in the trailing bytes which makes two byte-identical source compiles produce different on-chain code hashes.

`./script/build-artifacts.sh` runs `forge clean` in each source repo before its `forge build` step, so a stale `out/*.json` from a previous compilation cannot be picked up. After the build, before copying the artifact, the script also verifies that (a) the source file exists at the path declared in `CONTRACTS`, and (b) the copied artifact's `metadata.settings.compilationTarget` binds the expected `(sourcePath, contractName)` pair. Any mismatch is a hard error.

`artifacts.mjs` prunes `post-deploy/.cache/artifacts-<chainId>/` before writing each run's targets, and `distribute.mjs` derives its target list from the current `addresses-<chainId>.json` dump (not from `readdirSync` on the cache). Each artifact's `address` and `chainId` are validated against the current target before the file is copied to `deployments/`. Together these guarantee that the canonical published JSON tree never receives a stale file from a previous run. `post-deploy.sh` also skips distribution for any chain whose artifact emission failed.

#### Limitations (current scope)

- **Constructor-created clone implementations** (`JBProjectPayer` behind `JBProjectPayerDeployer.IMPLEMENTATION()`, `JB721Checkpoints` behind `JB721CheckpointsDeployer.IMPLEMENTATION()`) are emitted alongside their deployers so the verifier can prove the clone target bytecode matches the published artifact. Both are compiled and copied by `build-artifacts.sh` from their source repos.
- **Canonical project ERC-20 token clones** (`JBERC20__ProjectNANA`, `JBERC20__ProjectCPN`, `JBERC20__ProjectREV`, `JBERC20__ProjectBAN`) and **canonical project 721 hook clones** (`JB721TiersHook__ProjectCPN`, `JB721TiersHook__ProjectBAN`) are queried from `_tokens.tokenOf(projectId)` and `_revOwner.tiered721HookOf(projectId)` at dump time. Each clone shares the implementation bytecode but has its own deployed address; emitting both lets the post-deploy verifier prove every canonical project token/hook on chain matches its published artifact.
- **Per-route CCIP suckers** are emitted to `addresses-<chainId>.json` with a remote-chain suffix: `JBCCIPSucker__<RouteSuffix>`, `JBCCIPSuckerDeployer__<RouteSuffix>` (where `<RouteSuffix>` is `ETH`, `OP`, `BASE`, `ARB`, or their `_SEP` variants). The standard per-source-chain singletons (`JBOptimismSucker`, `JBBaseSucker`, `JBArbitrumSucker`) and deployers are emitted without a suffix. The pipeline emits the full singleton implementation address for every pre-approved sucker deployer so the verifier can prove the implementation bytecode matches the published artifact. Together with the ~50 single-instance contracts plus the 4 deadlines + JBERC20 + ETH/USD + USD/ETH + ETH/native + USDC/USD price feeds emitted by the base dump, this covers the full deployment surface.
- **No Blockscout fallback yet.** All supported chains are on Etherscan v2. Blockscout-only chains will need a `chains.json` entry with `"verifier": "blockscout"` + a Sourcify fallback.

### Project identity verification

The deploy script uses canonical identity gates to verify that pre-existing projects match the expected deployment shape. These go beyond simple `projects.count()` / `controllerOf` checks:

- **Canonical revnets (NANA, CPN, REV, BAN, DEFIFA, MARKEE, plus ART on Base):** Verified via `_verifyCanonicalRevnetProject()` — checks REVOwner ownership, non-zero REVDeployer config hash, controller wiring, and token symbol.
- **Project 4 (BAN):** Additionally checks REVOwner's 721 hook registration, hook PROJECT_ID, STORE, BANNY symbol, and Banny resolver manifest.
- **Project 6 (ART off-Base):** Verified as a placeholder project shell owned by `VERIFY_ART_OPS_OPERATOR`, preserving MARKEE's project ID without requiring revnet wiring.

## Interrupted deploy: redeploying from fresh salts

If a deploy is interrupted (gas spike, RPC timeout, operator error), do not re-propose the same script unchanged: CREATE2 with identical `(deployer, salt, initCodeHash)` reverts on every contract that already exists. Instead, redeploy the full stack from fresh salts.

### How fresh-salt recovery works

`Deploy.s.sol` carries a single salt-version lever, `DEPLOYMENT_NONCE`, that applies to the entire deployment. Every CREATE2/CREATE3 salt is folded with this nonce via `_saltOf` (and the core salt derives from it directly), so incrementing the nonce by one yields a fully fresh, non-colliding address namespace for every contract. The mined Uniswap V4 hook salt re-derives over the folded namespace as well.

Because the new addresses are empty, the redeploy runs from a clean slate: there are no half-deployed contracts to reconcile and no idempotency edge cases to worry about. The interrupted run's partial contracts are simply abandoned at their old addresses.

For CREATE3 deploys (currently only `JBOmnichainDeployer`), `_deployCreate3PrecompiledIfNeeded` checks `addr.codehash` against a sandbox-CREATE reference codehash: the deployed bytecode must match a reference computed by running the artifact's constructor in this script. This guards against a third party placing bytecode at the predicted CREATE3 address via the permissionless canonical factory; a mismatch reverts with `Deploy_Create3CodehashMismatch` rather than silently accepting foreign bytecode.

### Running a fresh-salt redeploy

1. Increment `DEPLOYMENT_NONCE` in `script/Deploy.s.sol`.
2. Re-propose through Sphinx, the same way as the initial deploy:

```bash
pnpm deploy:propose:testnets    # for testnets
pnpm deploy:propose:mainnets    # for production
```

These aliases prepend the required `DEFIFA_REV_START_TIME` env var and pass the correct CLI shape
(`npx sphinx propose script/Deploy.s.sol --networks <name>`). See [Production deploy (via Sphinx)](#production-deploy-via-sphinx) for the raw-CLI equivalent.

Sphinx batches the full deployment into a single multi-sig proposal at the new address namespace.

### Cross-chain note

The deployment nonce changes every contract address. When cross-chain address parity matters (sucker pairs, consistent project IDs), use the same `DEPLOYMENT_NONCE` across every chain in the set so addresses and project IDs stay aligned. Recovering only some chains to a different nonce would desynchronize them from the rest.

### Recovery rehearsal

The test suite includes fork tests that prove a clean re-run lands the full stack at the expected addresses with consistent project IDs:

```bash
forge test --match-contract DeployResumeRehearsalFork -vvv --fork-url <RPC_URL>
```

These tests exercise the full deploy and re-run it, asserting that core addresses and project IDs are stable across the repeat.

## Post-deploy verification: using Verify.s.sol

After a successful deploy (or redeploy), run `Verify.s.sol` to validate all contracts are correctly wired together.

### Setting up verification

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

Required on production chains (Ethereum, Optimism, Base, Arbitrum). Testnets may set these to `address(0)` or omit intentionally omitted components:
```bash
export VERIFY_ADDRESS_REGISTRY=0x...
export VERIFY_BUYBACK_REGISTRY=0x...
export VERIFY_ROUTER_TERMINAL_REGISTRY=0x...
export VERIFY_ROUTER_TERMINAL=0x...
export VERIFY_REV_DEPLOYER=0x...
export VERIFY_REV_OWNER=0x...
export VERIFY_REV_LOANS=0x...
export VERIFY_DEFIFA_DEPLOYER=0x...
export VERIFY_TRUSTED_FORWARDER=0x...
export VERIFY_SAFE=0x...                    # DEPLOYMENT Safe — sucker-deployer LAYER_SPECIFIC_CONFIGURATOR / admin-gate checks
export VERIFY_INFRA_OWNER=0x...             # Post-handoff owner of the Ownable singletons + fee project + creation-fee payer (distinct from VERIFY_SAFE)
export VERIFY_PROJECT_HANDLES=0x...
export VERIFY_PROJECT_PAYER_DEPLOYER=0x...
export VERIFY_LP_SPLIT_HOOK_DEPLOYER=0x...  # Canonical Uniswap V4 LP-split hook deployer.
export VERIFY_UNISWAP_V4_HOOK=0x...         # Actual JBUniswapV4Hook oracle/router hook address.
export VERIFY_CHECKPOINTS_DEPLOYER=0x...    # JB721Checkpoints deployer (clone-target source).
export VERIFY_BUYBACK_HOOK=0x...            # Canonical JBBuybackHook implementation address.
```

#### Per-project canonical manifest (mandatory on production)

Each canonical revnet's expected configuration must be supplied so the verifier can prove
on-chain state matches the operator's commit. Missing values fail closed on production chains
(chain IDs 1, 10, 8453, 42_161); on testnets they skip with a logged note.

```bash
# Sucker pair counts — REQUIRED on production for EVERY canonical project (1..7).
# Use "0" for projects that intentionally have no suckers on this chain. The verifier
# fails closed if ANY of VERIFY_SUCKER_PAIRS_{1..7} is unset on production.
#
# Topology (informational): projects 1-3 (NANA, CPN, REV) use native L1<->L2 suckers
# (OP/Base/Arb messengers); projects 4+ (BAN, DEFIFA, ART, MARKEE) use CCIP suckers to
# tie all chains. ART(6) lives only on Base — set VERIFY_SUCKER_PAIRS_6=0 off-Base.
export VERIFY_SUCKER_PAIRS_1=...
export VERIFY_SUCKER_PAIRS_2=...
export VERIFY_SUCKER_PAIRS_3=...
export VERIFY_SUCKER_PAIRS_4=...
export VERIFY_SUCKER_PAIRS_5=...            # DEFIFA(5)
export VERIFY_SUCKER_PAIRS_6=...            # ART(6) — set "0" off-Base
export VERIFY_SUCKER_PAIRS_7=...            # MARKEE(7)

# Optional per-pair manifest equality. For each project and pair index, supply
# `<peer>:<remoteChainId>:<remoteNativeToken>:<emergencyHatch>`.
#   <peer>                bytes32 (remote sucker, padded address or full bytes32)
#   <remoteChainId>       decimal uint
#   <remoteNativeToken>   bytes32 (canonical native token sentinel padded)
#   <emergencyHatch>      "0" or "1"
# Required on production when the corresponding VERIFY_SUCKER_PAIRS_<projectId> > 0.
export VERIFY_SUCKER_PAIR_1_0=0xpeer:10:0xnative:0
export VERIFY_SUCKER_PAIR_1_1=0xpeer:8453:0xnative:0
# ... one per (projectId, pairIndex)

# Per-project revnet config hash — required on production for projects 1..7
# (project 6 / ART only on Base; off-Base ART is a bare placeholder with no revnet config).
export VERIFY_CONFIG_HASH_1=0x...
export VERIFY_CONFIG_HASH_2=0x...
export VERIFY_CONFIG_HASH_3=0x...
export VERIFY_CONFIG_HASH_4=0x...
export VERIFY_CONFIG_HASH_5=0x...           # DEFIFA(5)
export VERIFY_CONFIG_HASH_6=0x...           # ART(6) — Base only
export VERIFY_CONFIG_HASH_7=0x...           # MARKEE(7)

# CSV form accepted as a fallback (overridden by per-project values above when set).
# export VERIFY_CONFIG_HASHES=0x...,0x...,0x...,0x...

# Per-project operator manifest — required on production for every canonical
# revnet on that chain. ART(6) is a full revnet only on Base; off-Base project 6
# is a bare placeholder checked with VERIFY_ART_OPS_OPERATOR instead.
export VERIFY_OPERATOR_1=0x...              # NANA(1) operator
export VERIFY_OPERATOR_2=0x...              # CPN(2) operator
export VERIFY_OPERATOR_3=0x...              # REV(3) operator
export VERIFY_OPERATOR_4=0x...              # BAN(4) operator
export VERIFY_OPERATOR_5=0x...              # DEFIFA(5) operator
export VERIFY_OPERATOR_6=0x...              # ART(6) operator — Base only
export VERIFY_OPERATOR_7=0x...              # MARKEE(7) operator
```

The artifact preflight also fails until `@bananapus/suckers-v6` contains the
nonzero-peer gate where only `bytes32(0)` keeps deterministic same-address peering.
The registry address is a normal explicit peer value, not a default sentinel.

#### Sucker deployer allowlist (mandatory on production)

The sucker registry's allowlist isn't enumerable on-chain, so the verifier accepts a
comma-separated list of expected deployers and authenticates each one's canonical wiring
(LAYER_SPECIFIC_CONFIGURATOR == VERIFY_SAFE, singleton has code, DIRECTORY/TOKENS/PERMISSIONS
match the core singletons). The off-chain `SuckerDeployerAllowed` / `SuckerDeployerRemoved` event log is the
authoritative source for "no unexpected allowed deployers" — see Section 6a below.

```bash
# Ethereum mainnet / Sepolia (L1 hosts all four canonical-project deployers PLUS the
# CCIP route deployers for each L2):
# - 3 standard canonical project deployers: OP, Base, Arb
# - 3 CCIP deployers allowlisted for OP, Base, Arb routes
export VERIFY_SUCKER_DEPLOYER_COUNT=6
export VERIFY_SUCKER_DEPLOYERS=0x...,0x...,0x...,0x...,0x...,0x...

# Optimism / Base / Arbitrum mainnets and testnets:
# - 1 standard canonical project deployer back to Ethereum
# - 3 CCIP deployers allowlisted for Ethereum and the two sibling L2s
# export VERIFY_SUCKER_DEPLOYER_COUNT=4
# export VERIFY_SUCKER_DEPLOYERS=0x...,...

# Per-bridge deployer pointers (required on production where the bridge applies).
export VERIFY_OP_SUCKER_DEPLOYER=0x...                # L1 + Optimism deployer
export VERIFY_BASE_SUCKER_DEPLOYER=0x...              # L1 + Base deployer
export VERIFY_ARB_SUCKER_DEPLOYER=0x...               # L1 + Arbitrum deployer

# Per-route CCIP deployers — CSV of `<remoteChainId>:<address>` entries. The
# verifier asserts each one's ccipRouter/ccipRemoteChainId/ccipRemoteChainSelector
# matches the canonical per-chain manifest.
export VERIFY_CCIP_SUCKER_DEPLOYERS_BY_REMOTE=10:0x...,8453:0x...,42161:0x...

# Optional extra feeless addresses — CSV of addresses that should be present in the
# feeless registry alongside the router terminal (which is checked separately).
# export VERIFY_FEELESS_ADDRESSES=0x...,0x...
```

#### Banny resolver + per-tier manifest (mandatory on production)

The Banny 721 hook resolver carries operator-supplied SVG metadata and per-UPC SVG hashes. On
production every field below must be supplied so the verifier can authenticate the resolver shell
AND every individual tier.

```bash
export VERIFY_BAN_OPS_OPERATOR=0x...                  # Final resolver owner + BAN operator
export VERIFY_BANNY_SVG_DESCRIPTION="A piece of Banny Retail."
export VERIFY_BANNY_SVG_EXTERNAL_URL="https://retail.banny.eth.shop"
export VERIFY_BANNY_SVG_BASE_URI="https://bannyverse.infura-ipfs.io/ipfs/"
export VERIFY_BANNY_TIER_COUNT=68                     # 4 baseline + 47 Drop 1 + 17 Drop 2

# Per-tier digest: the verifier walks tiers 1..VERIFY_BANNY_TIER_COUNT and accumulates
#   keccak256(running, tierId, price, initialSupply, category, reserveFrequency,
#             encodedIPFSUri, svgHash)
# starting from `bytes32(0)`. Off-chain manifest generator must produce the same digest.
export VERIFY_BANNY_TIER_MANIFEST_HASH=0x...

# Off-Base placeholder for ART(6) — owner of the bare project shell that reserves
# project ID 6 so MARKEE's expected ID 7 holds. On Base, ART is a full revnet and this
# var is ignored (the revnet identity check supersedes it).
export VERIFY_ART_OPS_OPERATOR=0x...
```

#### CPN posting criteria (optional but mandatory on production for full coverage)

When supplied, the verifier exactly pins every Croptop posting-criteria field for categories
0-4 against the operator's manifest. Use `VERIFY_OPERATOR_2` (above) to pin the CPN
operator.

```bash
# Per category 0..4, supply the four scalar fields plus optional allowed-poster CSV.
# Indices are the category; supply for every category the canonical launch configures.
export VERIFY_CPN_MIN_PRICE_0=0
export VERIFY_CPN_MIN_SUPPLY_0=1
export VERIFY_CPN_MAX_SUPPLY_0=...
export VERIFY_CPN_MAX_SPLIT_PERCENT_0=...
export VERIFY_CPN_ALLOWED_ADDRESSES_0=0x...,0x...
# ... repeat for categories 1..4
```

### Running verification

```bash
forge script script/Verify.s.sol:Verify \
  --rpc-url <RPC_URL> \
  -vvv
```

This is a read-only script — no `--broadcast` needed.

### Live smoke proposal

After `Verify.s.sol` is green and the V6 deployment Safe is funded, run the live smoke proposal. It uses `safeAddress()` as the holder, beneficiary, and loan owner, so the Safe must have enough native token on each target chain for the configured smoke budgets plus gas.

```bash
# Defaults spend at most 0.05 ETH-equivalent on buyback payment checks and 0.05 ETH-equivalent on loan checks per chain.
npm run deploy:propose:live-smoke:mainnets
```

Optional budget and behavior overrides:

```bash
export SMOKE_BUYBACK_BUDGET=50000000000000000
export SMOKE_BUYBACK_PAYMENT_AMOUNT=5000000000000000
export SMOKE_LOAN_BUDGET=50000000000000000
export SMOKE_LOAN_PAYMENT_AMOUNT=25000000000000000
export SMOKE_LOAN_PROJECT_ID=3
export SMOKE_BUYBACK_CASH_OUT_DIVISOR=4      # set 0 to skip the cash-out leg
```

The script reuses the core `VERIFY_*` addresses from `Verify.s.sol`. Set `VERIFY_BUYBACK_HOOK` to pin the expected hook implementation. If a buyback or loan budget is set to `0`, that section is skipped.

Optimism Sepolia skips the buyback, cash-out, and router-terminal smoke sections because that deployment intentionally has no PositionManager-backed Uniswap surfaces. Loan smoke is still budget-gated by REVLoans; set `SMOKE_LOAN_BUDGET=0` on Optimism Sepolia unless the no-buyback topology is explicitly being tested.

### Verification categories

Verify checks 20 categories in order:

| # | Category | What It Checks |
|---|---|---|
| 1 | Project IDs | Projects 1-4 exist, `projects.count() >= 4`, canonical revnet ownership, token symbols, and Banny hook identity |
| 2 | Directory Wiring | `controllerOf()` returns controller for each project, terminal is registered |
| 3 | Controller Wiring | Controller references correct directory, tokens, rulesets, permissions |
| 4 | Terminal Wiring | Terminal references correct store, directory, permissions, feeless registry |
| 5 | Hook Registries | 721 hook store/deployer wiring, buyback registry default hook, project 1 buyback pinned, router terminal default |
| 6 | Omnichain | Omnichain deployer references correct controller/directory, sucker deployers are allowed |
| 7 | Address Registry & Defifa | Address registry code, Defifa deployer identity, shared 721 hook store, token/governor/controller wiring |
| 8 | Price Feeds | Per-chain oracle provenance (ETH/USD, USDC/USD aggregator addresses), staleness thresholds, L2 sequencer feeds |
| 9 | Allowlists | Sucker deployer allowlist + count verification, feeless-address allowlist checks |
| 10 | Routes | All canonical projects include the router terminal registry in their terminal lists |
| 11 | Periphery Extensions | Project handles and project payer deployer code and constructor wiring |
| 12 | Token Implementation | JBERC20 clone template PROJECTS and PERMISSIONS wiring |
| 13 | Ownership | Safe ownership of all ownable contracts (feeless, buyback registry, router terminal registry, REVLoans) |
| 14 | Permissions & Forwarder | PERMISSIONS immutable on all permissioned contracts, trusted forwarder consistency |
| 15 | Croptop | CTPublisher, CTDeployer, CTProjectOwner immutables and project 2 wiring |
| 16 | Hook Deployer Immutables | Base hook DIRECTORY, STORE wiring, clone surface verification |
| 17 | REV Singletons | REVDeployer, REVOwner, REVLoans immutables and PERMIT2 |
| 18 | Project Economics | Per-project config hash verification, primary terminal for native token, Banny resolver and contractURI |
| 19 | Sucker Manifest | Per-project sucker pair counts and remote chain connectivity |
| 20 | External Addresses | Terminal/Router/REVLoans PERMIT2 wiring, Router WETH, OmnichainDeployer DIRECTORY |

### Interpreting results

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

Skips are normal on testnets or chains with intentionally omitted components. On production chains, the verifier fail-closes for the full deployment surface.

## Operator checklist: full deployment cycle

This is the complete sequence for deploying to a new chain:

### 1. Prepare

- [ ] Target chain is in the supported chains table above
- [ ] Deployer wallet has sufficient native token for gas
- [ ] External dependencies verified (Uniswap, Chainlink, typeface)
- [ ] Multi-sig address configured in Sphinx

### 2. Dry run

- [ ] `forge script script/Deploy.s.sol --rpc-url <RPC_URL> -vvvv` completes without revert
- [ ] All 11 phases logged as completed
- [ ] Gas usage is within budget

### 3. Deploy (via Sphinx)

- [ ] `pnpm deploy:propose:testnets` (or `pnpm deploy:propose:mainnets` for production) — these aliases set `DEFIFA_REV_START_TIME` and pass `script/Deploy.s.sol --networks <name>`
- [ ] Safe signers approve the proposal in the Sphinx dashboard
- [ ] Record all deployed contract addresses from the Sphinx execution log
- [ ] If interrupted: proceed to step 4

### 4. Recover from interruption (if needed)

- [ ] Increment `DEPLOYMENT_NONCE` in `script/Deploy.s.sol` so every salt re-namespaces into a fresh address space
- [ ] `pnpm deploy:propose:testnets` (or `pnpm deploy:propose:mainnets`) to redeploy the full stack from the fresh salts
- [ ] Confirm all 11 phases execute against the new (empty) addresses
- [ ] Use the same nonce across every chain in the set so cross-chain addresses and project IDs stay aligned

### 5. Verify

- [ ] Export all `VERIFY_*` environment variables with deployed addresses
- [ ] `forge script script/Verify.s.sol:Verify --rpc-url <RPC_URL> -vvv`
- [ ] Confirm 0 failures in the summary
- [ ] Review any skipped checks — confirm they correspond to intentionally omitted components

### 6. Live smoke proposal

- [ ] Fund the V6 deployment Safe with at least `SMOKE_BUYBACK_BUDGET + SMOKE_LOAN_BUDGET` native token plus gas per chain
- [ ] `npm run deploy:propose:live-smoke:testnets` or `npm run deploy:propose:live-smoke:mainnets`
- [ ] Safe signers approve and execute the smoke proposal
- [ ] Confirm buyback project payments, partial cash-outs, and REV loan borrow/repay pass

### 7. Post-verification spot checks

These manual checks complement the automated verification:

- [ ] `projects.count()` returns 4 (or expected total if other projects were created)
- [ ] `directory.controllerOf(1)` returns the controller address
- [ ] `prices.pricePerUnitOf(0, 2, 0x000000000000000000000000000000000000EEEe, 18)` returns a non-zero ETH/USD price
- [ ] `feelessAddresses.isFeeless(<routerTerminal>)` returns true
- [ ] `suckerRegistry.suckerDeployerIsAllowed(<deployer>)` returns true for each expected deployer
- [ ] Make a small test payment to project 1 via the terminal
- [ ] Verify the payment appears in the project's balance via `terminalStore.balanceOf()`

### 6a. Off-chain event-log reconciliation (required before sign-off)

Two surfaces cannot be exhaustively verified on-chain because the relevant registries are
not enumerable. Each requires a reviewer to reconcile the deployment's event log against the
expected manifest before signing off.

**Permissions — `JBPermissions.OperatorPermissionsSet` (P residual)**

`JBPermissions` exposes `permissionsOf(operator, account, projectId)` but has no on-chain
enumeration. The verifier proves every *expected* grant is present (REVLoans wildcard
USE_ALLOWANCE, BuybackRegistry wildcard SET_BUYBACK_POOL, OmnichainDeployer →
SuckerRegistry wildcard MAP_SUCKER_TOKEN, CTDeployer → CTPublisher wildcard
ADJUST_721_TIERS, plus the per-revnet split-operator grant sets), but cannot prove the
**absence** of unexpected grants on chain.

- [ ] Pull all `OperatorPermissionsSet(operator, account, projectId, permissionIds, packed,
      caller)` events from `JBPermissions` for the deployment block range.
- [ ] Confirm the set matches the canonical manifest:
  - The runtime REVOwner wildcard grants for REVLoans, BuybackRegistry, and REVDeployer
    plus the setup-only deployer wildcard grants described in Category 14b (`projectId == 0`).
  - The 9-permission split-operator grant for each canonical revnet on that chain
    (NANA / CPN / REV / BAN / DEFIFA / MARKEE, plus ART on Base) → operator
    addresses supplied via `VERIFY_OPERATOR_<projectId>`.
  - Any per-project grants the deployment script makes when launching each canonical project.
- [ ] Flag any grant outside that manifest — every extra wildcard or canonical-project grant
      gives an unintended operator owner-equivalent powers and must be revoked or accepted
      explicitly before launch.

**Sucker deployer allowlist — `JBSuckerRegistry.SuckerDeployerAllowed` / `SuckerDeployerRemoved` (BK / CP residual)**

`JBSuckerRegistry.suckerDeployerIsAllowed(addr)` answers per-address membership but does not
expose an enumeration. The verifier checks per-listed deployer code + canonical wiring + the
expected count via `VERIFY_SUCKER_DEPLOYER_COUNT`, but cannot prove the absence of an
allowed-but-unexpected deployer on chain.

- [ ] Pull all `SuckerDeployerAllowed(deployer, caller)` and
      `SuckerDeployerRemoved(deployer, caller)` events from
      `JBSuckerRegistry` for the deployment block range.
- [ ] Reduce the event stream to the current allowed set, keeping only deployers whose last
      event is `SuckerDeployerAllowed`.
- [ ] Confirm the resulting set exactly matches `VERIFY_SUCKER_DEPLOYERS` — same addresses,
      same count.
- [ ] Flag any allowed deployer not on the expected list — an unintended allowlisted route
      can mint or move project tokens that the canonical deployment never sanctioned.

### 7. Cross-chain (multi-chain deployments)

When deploying to multiple chains:

- [ ] Deploy to L1 (Ethereum) first — it's the hub for all sucker bridges
- [ ] Deploy to each L2 using the same deployer + salts
- [ ] Verify each chain independently using `Verify.s.sol`
- [ ] Verify sucker deployer allowlists match across chains
- [ ] Test a cross-chain token bridge: map a token via sucker, send a small amount, verify arrival on the remote chain

## Troubleshooting

**Deploy reverts at Phase 05 (Periphery) with "price feed" error:**
Chainlink feed address may have changed or not be deployed on this chain. Verify feed addresses at https://data.chain.link.

**After a redeploy, project count or project IDs look wrong:**
A third party may have created a project on the chain, shifting IDs. Project IDs 1-4 may not correspond to NANA/CPN/REV/BAN. Check `directory.controllerOf()` for each project to determine which is which, and confirm the same `DEPLOYMENT_NONCE` was used across every chain in the set.

**Verify shows FAIL on "Directory Wiring":**
The controller may not have been set as allowed via `setIsAllowedToSetFirstController`. A clean fresh-salt redeploy runs the full phase sequence including this permission call, so a redeploy from an incremented nonce resolves a deployment that was interrupted between controller deployment and the permission call.

**Uniswap-dependent phases skip on a chain that should support them:**
Check that `_positionManager` is set to a non-zero address for that chain in `_setupChainAddresses()`. Chains with `_positionManager = address(0)` skip active Uniswap routing surfaces, including the LP split hook.
