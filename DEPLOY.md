# Juicebox V6 Deployment Runbook

Operator guide for deploying, resuming, and verifying the Juicebox V6 ecosystem.

## Supported Chains

| Chain | ID | Uniswap V4 | Suckers |
|---|---|---|---|
| Ethereum Mainnet | 1 | Yes | OP, Base, Arb, CCIP, Swap CCIP |
| Ethereum Sepolia | 11155111 | Yes | OP Sepolia, Base Sepolia, Arb Sepolia, CCIP, Swap CCIP |
| Optimism | 10 | Yes | Ethereum, CCIP, Swap CCIP |
| Optimism Sepolia | 11155420 | Partial (no PositionManager) | Ethereum Sepolia, CCIP, Swap CCIP |
| Base | 8453 | Yes | Ethereum, CCIP, Swap CCIP |
| Base Sepolia | 84532 | Yes | Ethereum Sepolia, CCIP, Swap CCIP |
| Arbitrum One | 42161 | Yes | Ethereum, CCIP, Swap CCIP |
| Arbitrum Sepolia | 421614 | Yes | Ethereum Sepolia, CCIP, Swap CCIP |

Chains without a PositionManager skip the Uniswap-dependent stack (buyback hook, router terminal, LP split hook, revnet). Core protocol + 721 hook + suckers + croptop still deploy.

The canonical deployment allowlists standard OP, Base, Arbitrum, CCIP, and `JBSwapCCIPSucker` deployers. Initial project configs still use the standard native bridge deployers unless a manifest explicitly selects a swap CCIP deployer, but the swap deployers and singletons are deployed and configured from day one.

## Deployment Phases

The deploy script (`script/Deploy.s.sol`) executes 11 phases in strict order:

| Phase | What | Creates |
|---|---|---|
| 01 | Core Protocol | Permissions, Projects, Prices, Rulesets, Directory, JBERC20, Tokens, Splits, Feeless, FundAccessLimits, TerminalStore, MultiTerminal, ERC2771Forwarder |
| 02 | Address Registry | JBAddressRegistry |
| 03a | 721 Tier Hook | HookStore, CheckpointsDeployer, TiersHook, HookDeployer, HookProjectDeployer |
| 03b | Uniswap V4 Router Hook | JBUniswapV4Hook (requires PoolManager) |
| 03c | Buyback Hook | JBBuybackHookRegistry (requires V3Factory) |
| 03d | Router Terminal | JBRouterTerminal, JBRouterTerminalRegistry |
| 03e | Cross-Chain Suckers | JBSuckerRegistry + per-bridge deployers (OP, Base, Arb, CCIP, Swap CCIP) |
| 03f | LP Split Hook | JBUniswapV4LPSplitHook (requires PositionManager and SuckerRegistry) |
| 04 | Omnichain Deployer | JBOmnichainDeployer |
| 05 | Periphery | Controller, Price Feeds (ETH/USD, USDC/USD, sequencer-aware on L2), Deadline hooks |
| 06 | Croptop | CTDeployer, CTPublisher, CTProjectOwner; creates CPN project (ID 2) |
| 07 | Revnet | REVLoans, REVDeployer; creates REV project (ID 3) |
| 08 | Revnet Config | Configures CPN (project 2) and NANA (project 1) as revnets |
| 09 | Banny | Banny721TokenUriResolver; creates BAN project (ID 4) |
| 10 | Defifa | DefifaHook, DefifaTokenUriResolver, DefifaGovernor, DefifaDeployer |
| 11 | Periphery Extensions | JBProjectHandles, JB721Distributor, JBTokenDistributor, JBProjectPayerDeployer |

All contracts use CREATE2 with deterministic salts. Addresses are identical across chains for the same salt + initcode.

## Pre-Deploy Checklist

Before running a deployment:

1. **Confirm chain support.** Verify the target chain ID is in `_setupChainAddresses()`.
2. **Confirm external dependencies exist.** For Uniswap-dependent chains, verify PoolManager + PositionManager are deployed at the expected addresses. Check https://docs.uniswap.org/contracts/v4/deployments.
3. **Confirm Chainlink feeds.** For L1: ETH/USD + USDC/USD feeds. For L2: same feeds + sequencer uptime feed. Addresses are in `_deployPeriphery()`.
4. **Confirm typeface.** The Capsules SVG font contract must be deployed at the chain-specific address in `_setupChainAddresses()`.
5. **Dry run.** Execute against a fork first:
   ```bash
   forge script script/Deploy.s.sol \
     --rpc-url <RPC_URL> \
     --sender 0x80a8F7a4bD75b539CE26937016Df607fdC9ABeb5 \
     -vvvv
   ```
   No `--broadcast` flag = simulation only. `--sender` must be the canonical Sphinx safe (also `_EXPECTED_SAFE` in `Deploy.s.sol`); without it, `REVOwner.setDeployer` reverts with `REVOwner_Unauthorized` because the binder cached at REVOwner construction differs from `msg.sender` at the wire-up call. Production runs via `npx sphinx propose` set this automatically — the override is only for raw `forge script`.
6. **Gas estimation.** Full deploy is ~50M+ gas across all phases. Ensure the deployer has sufficient ETH/native token.
7. **Safe address.** The deploy script uses Sphinx for multi-sig execution. Confirm `safeAddress()` returns the correct multi-sig for the target chain.

## Running the Deploy

Deployments are executed through [Sphinx](https://sphinx.dev), which batches the deploy transactions through the multi-sig safe. The Sphinx CLI proposes the deployment, which must then be approved by safe signers.

### Dry Run (Forge Simulation)

```bash
forge script script/Deploy.s.sol \
  --rpc-url <RPC_URL> \
  --sender 0x80a8F7a4bD75b539CE26937016Df607fdC9ABeb5 \
  -vvvv
```

No `--broadcast` flag = simulation only. The `--sender` override impersonates the Sphinx safe for the simulation so the REVOwner wire-up call (and any other safe-gated calls) passes; production via `npx sphinx propose` handles this automatically. Verify all phases complete without revert, and that `script/post-deploy/.cache/addresses-<chainId>.json` is emitted at the end.

### Production Deploy (via Sphinx)

```bash
pnpm artifacts                                # pre-compile every contract in its source repo
pnpm deploy:propose:testnets                  # → npx sphinx propose --networks testnets
# (or:)
pnpm deploy:propose:mainnets                  # → npx sphinx propose --networks mainnets

# After safe signers approve + Sphinx executes on-chain:
ETHERSCAN_API_KEY=... pnpm deploy:post:testnets   # verify + emit + distribute
```

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

### Execution Model

**Deploy.s.sol** is executed through Sphinx. The operator runs `npx sphinx propose`, which:
1. Compiles and simulates the deploy script locally
2. Proposes the resulting transactions to the multi-sig Safe
3. Safe signers approve the proposal in the Sphinx dashboard or Safe UI
4. Sphinx executes the approved transactions on-chain

**Resume.s.sol** is executed directly via `forge script --broadcast`. The operator (one of the Safe signers) runs the resume from the Safe using `vm.startBroadcast(safeAddress())`. This requires the operator to have signing authority on the Safe.

**Verify.s.sol** is read-only and requires no broadcast. It reads deployed state and validates wiring.

### Post-Deploy: Verification + Artifact Emission

**Sphinx's auto-verification and auto-artifact pipeline are intentionally bypassed in v6.** Every contract that Deploy.s.sol routes through `_loadCreationCode` + `_deployFromArtifact` is pre-compiled in its source repo with that repo's own foundry profile (`via_ir` + `optimizerRuns`), then deployed via raw bytecode. Sphinx's bundled verifier doesn't know about that pre-compile step and would submit the wrong settings to Etherscan. Instead, v6 ships a local pipeline at `script/post-deploy.sh`.

After a successful `npx sphinx propose` + safe-signer approval + on-chain execution, run:

```bash
export ETHERSCAN_API_KEY=...        # single key for Etherscan v2 unified API
./script/post-deploy.sh --chains=all-testnets   # or all-mainnets, or a CSV like ethereum,optimism
```

What it does, per chain:

1. **Dump addresses.** Runs `forge script Deploy.s.sol --rpc-url $RPC_<CHAIN>` (no broadcast) to compute every deployed contract's CREATE2 address and emit `script/post-deploy/.cache/addresses-<chainId>.json`.
2. **Verify on Etherscan.** Shells out to `forge verify-contract` from each contract's **source repo** so the right `foundry.toml` (with the right `via_ir` / `optimizerRuns`) is used. Retries transient failures (rate limits, 5xx, "pending in queue") with exponential backoff (1s → 60s, up to 10 attempts). Permanent failures (source mismatch, compiler mismatch) are logged per-contract; other contracts continue.
3. **Emit artifacts.** Produces v5-compatible `sphinx-sol-ct-artifact-1` JSON per contract (same schema as `nana-core-v5/deployments/...`, **minus** `merkleRoot` since we're not Sphinx-managed). Fields: `address`, `sourceName`, `contractName`, `chainId` (hex), `abi`, `args`, `solcInputHash`, `receipt`, `bytecode`, `deployedBytecode`, `metadata`, `gitCommit`, `gitDirty`, `history`. Tab-indented to match v5 byte-for-byte (gitDirty surfaces source-tree provenance per artifact, not just in the sidecar manifest).
4. **Distribute.** Copies each artifact to:
   - `deploy-all-v6/deployments/juicebox-v6/<chain_alias>/<Contract>.json` (aggregator)
   - `<repo>/deployments/<sphinxProject>/<chain_alias>/<Contract>.json` (per-repo, mirrors v5)

All four steps are idempotent. Reruns skip already-verified contracts via `.cache/status-<chainId>.json`. The compile-settings manifest is at `artifacts/artifacts.manifest.json` (regenerated by `./script/build-artifacts.sh`).

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

Production artifact builds must be reproducible from a clean source tree. Without acknowledgment, both `./script/build-artifacts.sh` and `./script/post-deploy.sh` (and the underlying `verify.mjs` / `artifacts.mjs`) refuse to proceed when any source repo has uncommitted changes, since the published artifacts would be unverifiable.

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
- **Per-route CCIP / SwapCCIP suckers** are emitted to `addresses-<chainId>.json` with a remote-chain suffix: `JBCCIPSucker__<RouteSuffix>`, `JBCCIPSuckerDeployer__<RouteSuffix>`, `JBSwapCCIPSucker__<RouteSuffix>`, `JBSwapCCIPSuckerDeployer__<RouteSuffix>` (where `<RouteSuffix>` is `ETH`, `OP`, `BASE`, `ARB`, or their `_SEP` variants). The standard per-source-chain singletons (`JBOptimismSucker`, `JBBaseSucker`, `JBArbitrumSucker`) and deployers are emitted without a suffix. The pipeline emits the full singleton implementation address for every pre-approved sucker deployer so the verifier can prove the implementation bytecode matches the published artifact. Together with the ~50 single-instance contracts plus the 4 deadlines + JBERC20 + ETH/USD + USDC/USD price feeds emitted by the base dump, this covers the full deployment surface.
- **No Blockscout fallback yet.** All supported chains are on Etherscan v2. Blockscout-only chains will need a `chains.json` entry with `"verifier": "blockscout"` + a Sourcify fallback.

### Project Identity Verification

The deploy and resume scripts use canonical identity gates to verify that pre-existing projects match the expected deployment shape. These go beyond simple `projects.count()` / `controllerOf` checks:

- **Projects 1-3 (NANA, CPN, REV):** Verified via `_isCanonicalRevnetProject()` — checks REVDeployer ownership, non-zero config hash, controller wiring, and token symbol.
- **Project 4 (BAN):** Verified via `_isCanonicalBannyProject()` — additionally checks REVOwner's 721 hook registration, hook PROJECT_ID, STORE, and BANNY symbol.

## Interrupted Deploy: Using Resume.s.sol

If a deploy is interrupted (gas spike, RPC timeout, operator error), use `Resume.s.sol` to continue from where it stopped.

### How Resume Works

Resume detects completed phases by checking `code.length != 0` at each contract's deterministic CREATE2 address. If a contract already has code, it's skipped. If not, it's deployed.

State-mutating calls (e.g., `setDefaultHook`, `setIsAllowedToSetFirstController`, `allowSuckerDeployer`) are guarded by idempotent checks that read current on-chain state before writing.

### Running Resume

Dry-run (simulation only):
```bash
forge script script/Resume.s.sol --rpc-url <RPC_URL> -vvvv
```

Production resume (via Sphinx):
```bash
npx sphinx propose --testnets   # for testnets
npx sphinx propose --mainnets   # for production
```

The resume script is proposed the same way as the initial deploy. Sphinx batches all remaining deployments into a single multi-sig proposal.

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
export VERIFY_DEFIFA_HOOK_STORE=0x...
export VERIFY_TRUSTED_FORWARDER=0x...
export VERIFY_SAFE=0x...
export VERIFY_PROJECT_HANDLES=0x...
export VERIFY_721_DISTRIBUTOR=0x...
export VERIFY_TOKEN_DISTRIBUTOR=0x...
export VERIFY_PROJECT_PAYER_DEPLOYER=0x...
export VERIFY_LP_SPLIT_HOOK_DEPLOYER=0x...  # Canonical Uniswap V4 LP-split hook deployer.
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

# Legacy CSV form still accepted (overridden by per-project values above when set).
# export VERIFY_CONFIG_HASHES=0x...,0x...,0x...,0x...

# Per-project split-operator manifest — required on production for projects 2..4
# so the verifier can authenticate the `splitOperator` (the address allowed to call
# OPERATOR-gated revnet functions) against the operator's commit.
export VERIFY_OPERATOR_2=0x...              # CPN(2) splitOperator
export VERIFY_OPERATOR_3=0x...              # REV(3) splitOperator
export VERIFY_OPERATOR_4=0x...              # BAN(4) splitOperator
```

#### Sucker deployer allowlist (mandatory on production)

The sucker registry's allowlist isn't enumerable on-chain, so the verifier accepts a
comma-separated list of expected deployers and authenticates each one's canonical wiring
(LAYER_SPECIFIC_CONFIGURATOR == VERIFY_SAFE, singleton has code, DIRECTORY/TOKENS/PERMISSIONS
match the core singletons). The off-chain `SuckerDeployerSetAllowed` event log is the
authoritative source for "no unexpected allowed deployers" — see Section 6a below.

```bash
# Ethereum mainnet / Sepolia (L1 hosts all four canonical-project deployers PLUS the
# CCIP and Swap-CCIP route deployers for each L2):
# - 3 standard canonical project deployers: OP, Base, Arb
# - 3 CCIP deployers allowlisted for OP, Base, Arb routes
# - 3 Swap CCIP deployers allowlisted for OP, Base, Arb routes
export VERIFY_SUCKER_DEPLOYER_COUNT=9
export VERIFY_SUCKER_DEPLOYERS=0x...,0x...,0x...,0x...,0x...,0x...,0x...,0x...,0x...

# Optimism / Base / Arbitrum mainnets and testnets:
# - 1 standard canonical project deployer back to Ethereum
# - 3 CCIP deployers allowlisted for Ethereum and the two sibling L2s
# - 3 Swap CCIP deployers allowlisted for Ethereum and the two sibling L2s
# export VERIFY_SUCKER_DEPLOYER_COUNT=7
# export VERIFY_SUCKER_DEPLOYERS=0x...,...

# Per-bridge deployer pointers (required on production where the bridge applies).
export VERIFY_OP_SUCKER_DEPLOYER=0x...                # L1 + Optimism deployer
export VERIFY_BASE_SUCKER_DEPLOYER=0x...              # L1 + Base deployer
export VERIFY_ARB_SUCKER_DEPLOYER=0x...               # L1 + Arbitrum deployer

# Per-route CCIP deployers — CSV of `<remoteChainId>:<address>` entries. The
# verifier asserts each one's ccipRouter/ccipRemoteChainId/ccipRemoteChainSelector
# matches the canonical per-chain manifest.
export VERIFY_CCIP_SUCKER_DEPLOYERS_BY_REMOTE=10:0x...,8453:0x...,42161:0x...

# Per-route swap-CCIP deployers — same shape, plus swap-specific endpoint checks
# (bridgeToken == canonical USDC, poolManager == canonical V4, v3Factory == canonical V3,
# wrappedNativeToken == canonical WETH, univ4Hook == canonical JBUniswapV4Hook).
export VERIFY_SWAP_CCIP_SUCKER_DEPLOYERS=10:0x...,8453:0x...,42161:0x...

# Optional extra feeless addresses — CSV of addresses that should be present in the
# feeless registry alongside the router terminal (which is checked separately).
# export VERIFY_FEELESS_ADDRESSES=0x...,0x...
```

#### Banny resolver + per-tier manifest (mandatory on production)

The Banny 721 hook resolver carries operator-supplied SVG metadata and a per-UPC product-name
/ SVG-hash commitment. On production every field below must be supplied so the verifier can
authenticate the resolver shell AND every individual tier.

```bash
export VERIFY_BAN_OPS_OPERATOR=0x...                  # Final resolver owner + BAN splitOperator
export VERIFY_BANNY_SVG_DESCRIPTION="A piece of Banny Retail."
export VERIFY_BANNY_SVG_EXTERNAL_URL="https://retail.banny.eth.shop"
export VERIFY_BANNY_SVG_BASE_URI="https://bannyverse.infura-ipfs.io/ipfs/"
export VERIFY_BANNY_TIER_COUNT=68                     # 4 baseline + 47 Drop 1 + 17 Drop 2

# Per-tier digest: the verifier walks tiers 1..VERIFY_BANNY_TIER_COUNT and accumulates
#   keccak256(running, tierId, price, initialSupply, category, reserveFrequency,
#             encodedIPFSUri, svgHash, keccak256(productName))
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
splitOperator.

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

### Running Verification

```bash
forge script script/Verify.s.sol:Verify \
  --rpc-url <RPC_URL> \
  -vvv
```

This is a read-only script — no `--broadcast` needed.

### Verification Categories

Verify checks 20 categories in order:

| # | Category | What It Checks |
|---|---|---|
| 1 | Project IDs | Projects 1-4 exist, `projects.count() >= 4`, canonical revnet ownership, token symbols, and Banny hook identity |
| 2 | Directory Wiring | `controllerOf()` returns controller for each project, terminal is registered |
| 3 | Controller Wiring | Controller references correct directory, tokens, rulesets, permissions |
| 4 | Terminal Wiring | Terminal references correct store, directory, permissions, feeless registry |
| 5 | Hook Registries | 721 hook store/deployer wiring, buyback registry default hook, project 1 buyback pinned, router terminal default |
| 6 | Omnichain | Omnichain deployer references correct controller/directory, sucker deployers are allowed |
| 7 | Address Registry & Defifa | Address registry code, Defifa deployer identity, dedicated hook store, token/governor/controller wiring |
| 8 | Price Feeds | Per-chain oracle provenance (ETH/USD, USDC/USD aggregator addresses), staleness thresholds, L2 sequencer feeds |
| 9 | Allowlists | Sucker deployer allowlist + count verification, feeless-address allowlist checks |
| 10 | Routes | All canonical projects include the router terminal registry in their terminal lists |
| 11 | Periphery Extensions | Project handles, distributors, and project payer deployer code and constructor wiring |
| 12 | Token Implementation | JBERC20 clone template PROJECTS and PERMISSIONS wiring |
| 13 | Ownership | Safe ownership of all ownable contracts (feeless, buyback registry, router terminal registry, REVLoans) |
| 14 | Permissions & Forwarder | PERMISSIONS immutable on all permissioned contracts, trusted forwarder consistency |
| 15 | Croptop | CTPublisher, CTDeployer, CTProjectOwner immutables and project 2 wiring |
| 16 | Hook Deployer Immutables | Base hook DIRECTORY, STORE wiring, clone surface verification |
| 17 | REV Singletons | REVDeployer, REVOwner, REVLoans immutables and PERMIT2 |
| 18 | Project Economics | Per-project config hash verification, primary terminal for native token, Banny resolver and contractURI |
| 19 | Sucker Manifest | Per-project sucker pair counts and remote chain connectivity |
| 20 | External Addresses | Terminal/Router/REVLoans PERMIT2 wiring, Router WETH, OmnichainDeployer DIRECTORY |

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

Skips are normal on testnets or chains with intentionally omitted components. On production chains, the verifier fail-closes for the full deployment surface.

## Operator Checklist: Full Deployment Cycle

This is the complete sequence for deploying to a new chain:

### 1. Prepare

- [ ] Target chain is in the supported chains table above
- [ ] Deployer wallet has sufficient native token for gas
- [ ] External dependencies verified (Uniswap, Chainlink, typeface)
- [ ] Multi-sig address configured in Sphinx

### 2. Dry Run

- [ ] `forge script script/Deploy.s.sol --rpc-url <RPC_URL> -vvvv` completes without revert
- [ ] All 11 phases logged as completed
- [ ] Gas usage is within budget

### 3. Deploy (via Sphinx)

- [ ] `npx sphinx propose --testnets` (or `--mainnets` for production)
- [ ] Safe signers approve the proposal in the Sphinx dashboard
- [ ] Record all deployed contract addresses from the Sphinx execution log
- [ ] If interrupted: proceed to step 4

### 4. Resume (if needed)

- [ ] `npx sphinx propose --testnets` (or `--mainnets`) with Resume.s.sol
- [ ] Confirm output shows `Phases skipped` + `Phases executed` totaling 11
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

### 6a. Off-Chain Event-Log Reconciliation (Required Before Sign-Off)

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
  - The four wildcard grants above (`projectId == 0`).
  - The 9-permission split-operator grant for each of canonical projects 2 / 3 / 4 (CPN /
    REV / BAN) → operator addresses supplied via `VERIFY_SPLIT_OPERATOR_{2,3,4}`.
  - Any per-project grants the deployment script makes when launching each canonical project.
- [ ] Flag any grant outside that manifest — every extra wildcard or canonical-project grant
      gives an unintended operator owner-equivalent powers and must be revoked or accepted
      explicitly before launch.

**Sucker deployer allowlist — `JBSuckerRegistry.SuckerDeployerSetAllowed` (BK / CP residual)**

`JBSuckerRegistry.suckerDeployerIsAllowed(addr)` answers per-address membership but does not
expose an enumeration. The verifier checks per-listed deployer code + canonical wiring + the
expected count via `VERIFY_SUCKER_DEPLOYER_COUNT`, but cannot prove the absence of an
allowed-but-unexpected deployer on chain.

- [ ] Pull all `SuckerDeployerSetAllowed(deployer, allowed, caller)` events from
      `JBSuckerRegistry` for the deployment block range.
- [ ] Reduce the event stream to the current allowed set (track each `(deployer, allowed)`
      pair, keeping only the last entry per deployer).
- [ ] Confirm the resulting set exactly matches `VERIFY_SUCKER_DEPLOYERS` — same addresses,
      same count.
- [ ] Flag any allowed deployer not on the expected list — an unintended allowlisted route
      can mint or move project tokens that the canonical deployment never sanctioned.

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
