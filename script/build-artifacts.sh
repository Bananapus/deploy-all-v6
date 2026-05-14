#!/usr/bin/env bash
# build-artifacts.sh — Build each source repo with its own foundry.toml and
# copy the full Forge artifact JSON for every contract Deploy.s.sol will deploy.
# Emits a sidecar `artifacts.manifest.json` recording per-contract compile
# settings + source repo + git commit, used by the post-deploy verify and
# artifact-emit pipeline.
#
# Usage:  ./script/build-artifacts.sh [--rehearsal]
# Run from the deploy-all-v6 root directory.
#
# Flags:
#   --rehearsal   Allow source repos to be dirty (uncommitted changes). Without
#                 this flag, a dirty source tree is a hard error so production
#                 artifact builds cannot be published with unknown local edits.
#                 With this flag, the manifest stamps gitDirty:true and every
#                 downstream production-chain step (verify, artifact emit) will
#                 refuse to run unless the same --rehearsal flag is passed.
#
# Requires: forge, jq, git.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MONO_ROOT="$(cd "$DEPLOY_ROOT/.." && pwd)"
ARTIFACTS_DIR="$DEPLOY_ROOT/artifacts"
MANIFEST="$ARTIFACTS_DIR/artifacts.manifest.json"

REHEARSAL=0
for arg in "$@"; do
  case "$arg" in
    --rehearsal) REHEARSAL=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag '$arg' (try --help)"; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq)"; exit 1; }
command -v forge >/dev/null 2>&1 || { echo "ERROR: forge is required (foundry)"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "ERROR: git is required"; exit 1; }

# Clean previous artifacts.
rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

# ── Per-repo compile profile ──────────────────────────────────────────────
# Keyed by repo name. Values: "viaIr|optimizer|optimizerRuns|evmVersion|solcVersion".
declare -A REPO_PROFILE=(
  [nana-core-v6]="false|true|200|cancun|0.8.28"
  [nana-address-registry-v6]="false|true|200|cancun|0.8.28"
  [nana-721-hook-v6]="false|true|200|cancun|0.8.28"
  [nana-buyback-hook-v6]="true|true|200|cancun|0.8.28"
  [univ4-router-v6]="true|true|200|cancun|0.8.28"
  [nana-router-terminal-v6]="true|true|200|cancun|0.8.28"
  [univ4-lp-split-hook-v6]="true|true|200|cancun|0.8.28"
  [nana-suckers-v6]="false|true|200|cancun|0.8.28"
  [nana-omnichain-deployers-v6]="true|true|200|cancun|0.8.28"
  [croptop-core-v6]="false|true|200|cancun|0.8.28"
  [revnet-core-v6]="true|true|200|cancun|0.8.28"
  [banny-retail-v6]="true|true|200|cancun|0.8.28"
  [defifa]="true|true|200|cancun|0.8.28"
  [nana-project-handles-v6]="false|true|200|cancun|0.8.28"
  [nana-distributor-v6]="false|true|200|cancun|0.8.28"
  [nana-project-payer-v6]="true|true|200|cancun|0.8.28"
  # deploy-all-v6 hosts ERC2771Forwarder (compiled from node_modules/@openzeppelin).
  [deploy-all-v6]="true|true|200|cancun|0.8.28"
)

# ── Mapping: every contract Deploy.s.sol deploys → source repo + src path ─
# Each entry is "repo:ContractName:src_path".
# src_path is relative to the repo root and is used to locate the Forge artifact.
# Order: roughly mirrors Deploy.s.sol phase order for readability.
CONTRACTS=(
  # ── nana-core-v6 (viaIr=false, optimizer=true, runs=200) ──
  "nana-core-v6:JBPermissions:src/JBPermissions.sol"
  "nana-core-v6:JBProjects:src/JBProjects.sol"
  "nana-core-v6:JBDirectory:src/JBDirectory.sol"
  "nana-core-v6:JBSplits:src/JBSplits.sol"
  "nana-core-v6:JBRulesets:src/JBRulesets.sol"
  "nana-core-v6:JBPrices:src/JBPrices.sol"
  "nana-core-v6:JBERC20:src/JBERC20.sol"
  "nana-core-v6:JBTokens:src/JBTokens.sol"
  "nana-core-v6:JBFundAccessLimits:src/JBFundAccessLimits.sol"
  "nana-core-v6:JBFeelessAddresses:src/JBFeelessAddresses.sol"
  "nana-core-v6:JBPayoutSplitGroupLib:src/libraries/JBPayoutSplitGroupLib.sol"
  "nana-core-v6:JBTerminalStore:src/JBTerminalStore.sol"
  "nana-core-v6:JBMultiTerminal:src/JBMultiTerminal.sol"
  "nana-core-v6:JBController:src/JBController.sol"
  "nana-core-v6:JBChainlinkV3PriceFeed:src/JBChainlinkV3PriceFeed.sol"
  "nana-core-v6:JBChainlinkV3SequencerPriceFeed:src/JBChainlinkV3SequencerPriceFeed.sol"
  "nana-core-v6:JBMatchingPriceFeed:src/periphery/JBMatchingPriceFeed.sol"
  "nana-core-v6:JBDeadline3Hours:src/periphery/JBDeadline3Hours.sol"
  "nana-core-v6:JBDeadline1Day:src/periphery/JBDeadline1Day.sol"
  "nana-core-v6:JBDeadline3Days:src/periphery/JBDeadline3Days.sol"
  "nana-core-v6:JBDeadline7Days:src/periphery/JBDeadline7Days.sol"

  # ── nana-address-registry-v6 ──
  "nana-address-registry-v6:JBAddressRegistry:src/JBAddressRegistry.sol"

  # ── nana-721-hook-v6 ──
  "nana-721-hook-v6:JB721TiersHookLib:src/libraries/JB721TiersHookLib.sol"
  "nana-721-hook-v6:JB721TiersHookStore:src/JB721TiersHookStore.sol"
  "nana-721-hook-v6:JB721TiersHook:src/JB721TiersHook.sol"
  "nana-721-hook-v6:JB721Checkpoints:src/JB721Checkpoints.sol"
  "nana-721-hook-v6:JB721CheckpointsDeployer:src/JB721CheckpointsDeployer.sol"
  "nana-721-hook-v6:JB721TiersHookDeployer:src/JB721TiersHookDeployer.sol"
  "nana-721-hook-v6:JB721TiersHookProjectDeployer:src/JB721TiersHookProjectDeployer.sol"

  # ── nana-buyback-hook-v6 ──
  "nana-buyback-hook-v6:JBBuybackHook:src/JBBuybackHook.sol"
  "nana-buyback-hook-v6:JBBuybackHookRegistry:src/JBBuybackHookRegistry.sol"

  # ── univ4-router-v6 ──
  "univ4-router-v6:JBUniswapV4Hook:src/JBUniswapV4Hook.sol"

  # ── nana-router-terminal-v6 ──
  "nana-router-terminal-v6:JBRouterTerminal:src/JBRouterTerminal.sol"
  "nana-router-terminal-v6:JBRouterTerminalRegistry:src/JBRouterTerminalRegistry.sol"

  # ── univ4-lp-split-hook-v6 ──
  "univ4-lp-split-hook-v6:JBUniswapV4LPSplitHook:src/JBUniswapV4LPSplitHook.sol"
  "univ4-lp-split-hook-v6:JBUniswapV4LPSplitHookDeployer:src/JBUniswapV4LPSplitHookDeployer.sol"

  # ── nana-suckers-v6 ──
  "nana-suckers-v6:JBSuckerLib:src/libraries/JBSuckerLib.sol"
  "nana-suckers-v6:JBCCIPLib:src/libraries/JBCCIPLib.sol"
  "nana-suckers-v6:CCIPHelper:src/libraries/CCIPHelper.sol"
  "nana-suckers-v6:JBSwapPoolLib:src/libraries/JBSwapPoolLib.sol"
  "nana-suckers-v6:JBSuckerRegistry:src/JBSuckerRegistry.sol"
  "nana-suckers-v6:JBOptimismSucker:src/JBOptimismSucker.sol"
  "nana-suckers-v6:JBBaseSucker:src/JBBaseSucker.sol"
  "nana-suckers-v6:JBArbitrumSucker:src/JBArbitrumSucker.sol"
  "nana-suckers-v6:JBCCIPSucker:src/JBCCIPSucker.sol"
  "nana-suckers-v6:JBSwapCCIPSucker:src/JBSwapCCIPSucker.sol"
  "nana-suckers-v6:JBOptimismSuckerDeployer:src/deployers/JBOptimismSuckerDeployer.sol"
  "nana-suckers-v6:JBBaseSuckerDeployer:src/deployers/JBBaseSuckerDeployer.sol"
  "nana-suckers-v6:JBArbitrumSuckerDeployer:src/deployers/JBArbitrumSuckerDeployer.sol"
  "nana-suckers-v6:JBCCIPSuckerDeployer:src/deployers/JBCCIPSuckerDeployer.sol"
  "nana-suckers-v6:JBSwapCCIPSuckerDeployer:src/deployers/JBSwapCCIPSuckerDeployer.sol"

  # ── nana-omnichain-deployers-v6 ──
  "nana-omnichain-deployers-v6:JBOmnichainDeployer:src/JBOmnichainDeployer.sol"

  # ── croptop-core-v6 ──
  "croptop-core-v6:CTPublisher:src/CTPublisher.sol"
  "croptop-core-v6:CTDeployer:src/CTDeployer.sol"
  "croptop-core-v6:CTProjectOwner:src/CTProjectOwner.sol"

  # ── revnet-core-v6 ──
  "revnet-core-v6:REVDeployer:src/REVDeployer.sol"
  "revnet-core-v6:REVOwner:src/REVOwner.sol"
  "revnet-core-v6:REVLoans:src/REVLoans.sol"

  # ── banny-retail-v6 ──
  "banny-retail-v6:Banny721TokenUriResolver:src/Banny721TokenUriResolver.sol"

  # ── defifa ──
  "defifa:DefifaHookLib:src/libraries/DefifaHookLib.sol"
  "defifa:DefifaHook:src/DefifaHook.sol"
  "defifa:DefifaDeployer:src/DefifaDeployer.sol"
  "defifa:DefifaGovernor:src/DefifaGovernor.sol"
  "defifa:DefifaTokenUriResolver:src/DefifaTokenUriResolver.sol"

  # ── nana-project-handles-v6 ──
  "nana-project-handles-v6:JBProjectHandles:src/JBProjectHandles.sol"

  # ── nana-distributor-v6 ──
  "nana-distributor-v6:JB721Distributor:src/JB721Distributor.sol"
  "nana-distributor-v6:JBTokenDistributor:src/JBTokenDistributor.sol"

  # ── nana-project-payer-v6 ──
  "nana-project-payer-v6:JBProjectPayer:src/JBProjectPayer.sol"
  "nana-project-payer-v6:JBProjectPayerDeployer:src/JBProjectPayerDeployer.sol"

  # ── deploy-all-v6 itself (OpenZeppelin's ERC2771Forwarder, compiled here) ──
  "deploy-all-v6:ERC2771Forwarder:node_modules/@openzeppelin/contracts/metatx/ERC2771Forwarder.sol"
)

# ── Build each repo (cached) and collect git metadata ─────────────────────
declare -A BUILT_REPOS
declare -A REPO_COMMIT
declare -A REPO_DIRTY

errors=0

build_repo() {
  local repo="$1"
  local repo_dir="$2"

  if [[ -n "${BUILT_REPOS[$repo]+x}" ]]; then
    return 0
  fi
  echo "Building $repo..."
  # `forge clean` so a stale artifact from a previous compilation (different
  # source state, different settings) cannot survive into this run's manifest.
  # Without this, e.g. a `git pull` that updates source files but leaves
  # `out/*.json` untouched would silently publish out-of-date artifacts.
  (cd "$repo_dir" && forge clean 2>&1) || {
    echo "ERROR: forge clean failed for $repo"
    BUILT_REPOS[$repo]=1
    return 1
  }
  if [[ "$repo" == "deploy-all-v6" ]]; then
    # Build everything in deploy-all-v6 (includes ERC2771Forwarder via node_modules).
    (cd "$repo_dir" && forge build --skip test 2>&1) || {
      echo "ERROR: forge build failed for $repo"
      BUILT_REPOS[$repo]=1
      return 1
    }
  else
    (cd "$repo_dir" && forge build --skip test script 2>&1) || {
      echo "ERROR: forge build failed for $repo"
      BUILT_REPOS[$repo]=1
      return 1
    }
  fi
  BUILT_REPOS[$repo]=1

  # Capture git commit + dirty state for the manifest.
  if [[ -d "$repo_dir/.git" ]] || git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
    REPO_COMMIT[$repo]="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || echo unknown)"
    if [[ -z "$(git -C "$repo_dir" status --porcelain 2>/dev/null || true)" ]]; then
      REPO_DIRTY[$repo]="false"
    else
      REPO_DIRTY[$repo]="true"
    fi
  else
    REPO_COMMIT[$repo]="unknown"
    REPO_DIRTY[$repo]="unknown"
  fi
  return 0
}

# ── Per-contract manifest accumulator (built incrementally as JSON object) ──
MANIFEST_ENTRIES=""

for entry in "${CONTRACTS[@]}"; do
  IFS=':' read -r repo contract src_path <<< "$entry"
  repo_dir="$MONO_ROOT/$repo"

  if [[ "$repo" == "deploy-all-v6" ]]; then
    repo_dir="$DEPLOY_ROOT"
  fi

  if [[ ! -d "$repo_dir" ]]; then
    echo "ERROR: repo not found: $repo_dir"
    errors=$((errors + 1))
    continue
  fi

  if ! build_repo "$repo" "$repo_dir"; then
    errors=$((errors + 1))
    continue
  fi

  # The source file must actually exist in the source repo, otherwise the
  # manifest entry is pointing to a path that doesn't compile in this checkout
  # (and any matching out/*.json would be from a previous source state).
  if [[ ! -f "$repo_dir/$src_path" ]]; then
    echo "ERROR: source file missing: $repo_dir/$src_path"
    errors=$((errors + 1))
    continue
  fi

  # Locate the Forge artifact. Output is: out/<basename(src_path)>/<ContractName>.json
  src_filename="$(basename "$src_path")"
  artifact="$repo_dir/out/$src_filename/$contract.json"

  if [[ ! -f "$artifact" ]]; then
    echo "ERROR: artifact not found: $artifact"
    errors=$((errors + 1))
    continue
  fi

  # Verify the artifact's metadata.settings.compilationTarget binds the
  # expected sourcePath → contractName pair. If forge clean ran above this
  # should always hold, but the check defends against any future bypass of
  # the clean step (e.g. --skip flags, CI cache layers, manual edits).
  compilation_target=$(jq -r --arg path "$src_path" --arg name "$contract" '
    (.metadata | (if type == "string" then fromjson else . end)).settings.compilationTarget[$path] // ""
  ' "$artifact" 2>/dev/null)
  if [[ "$compilation_target" != "$contract" ]]; then
    echo "ERROR: $contract.json compilationTarget=\"$compilation_target\", expected \"$contract\" (source=$src_path)"
    errors=$((errors + 1))
    continue
  fi

  cp "$artifact" "$ARTIFACTS_DIR/$contract.json"
  echo "  Copied $contract.json from $repo"

  # Compose manifest entry. Compile profile is keyed by repo.
  profile="${REPO_PROFILE[$repo]:-}"
  if [[ -z "$profile" ]]; then
    echo "ERROR: no REPO_PROFILE for $repo"
    errors=$((errors + 1))
    continue
  fi
  IFS='|' read -r p_via_ir p_optimizer p_runs p_evm p_solc <<< "$profile"

  entry_json=$(jq -nc \
    --arg repo "$repo" \
    --arg sourcePath "$src_path" \
    --argjson viaIr "$p_via_ir" \
    --argjson optimizer "$p_optimizer" \
    --argjson optimizerRuns "$p_runs" \
    --arg evmVersion "$p_evm" \
    --arg solcVersion "$p_solc" \
    --arg gitCommit "${REPO_COMMIT[$repo]:-unknown}" \
    --arg gitDirty "${REPO_DIRTY[$repo]:-unknown}" \
    '{
      repo: $repo,
      sourcePath: $sourcePath,
      viaIr: $viaIr,
      optimizer: $optimizer,
      optimizerRuns: $optimizerRuns,
      evmVersion: $evmVersion,
      solcVersion: $solcVersion,
      gitCommit: $gitCommit,
      gitDirty: ($gitDirty == "true")
    }')

  if [[ -z "$MANIFEST_ENTRIES" ]]; then
    MANIFEST_ENTRIES="\"$contract\": $entry_json"
  else
    MANIFEST_ENTRIES="$MANIFEST_ENTRIES, \"$contract\": $entry_json"
  fi
done

# ── Dirty-source gate ─────────────────────────────────────────────────────
# Production artifact builds must be reproducible from a clean source tree.
# Without --rehearsal, any dirty repo is a hard failure. With --rehearsal, we
# print a loud warning and stamp gitDirty:true in the manifest so downstream
# production-chain verification/emit refuses to publish the resulting artifacts.
DIRTY_REPOS=()
for repo in "${!REPO_DIRTY[@]}"; do
  if [[ "${REPO_DIRTY[$repo]}" == "true" ]]; then
    DIRTY_REPOS+=("$repo")
  fi
done

ANY_DIRTY="false"
if [[ ${#DIRTY_REPOS[@]} -gt 0 ]]; then
  ANY_DIRTY="true"
  if [[ "$REHEARSAL" -eq 0 ]]; then
    echo ""
    echo "ERROR: source repo(s) have uncommitted changes:"
    for r in "${DIRTY_REPOS[@]}"; do echo "  - $r"; done
    echo ""
    echo "Production artifact builds must be reproducible from a clean tree."
    echo "Either commit/stash the changes, or re-run with --rehearsal to build"
    echo "a marked-dirty rehearsal artifact set (production verify/emit will"
    echo "still refuse to publish it)."
    exit 1
  fi
  echo ""
  echo "════════════════════════════════════════════════════════════════════"
  echo " WARNING: rehearsal build — source repo(s) have uncommitted changes:"
  for r in "${DIRTY_REPOS[@]}"; do echo "   - $r"; done
  echo " Artifacts will be stamped gitDirty:true and production verify/emit"
  echo " will refuse to publish them. Use only for fork rehearsal."
  echo "════════════════════════════════════════════════════════════════════"
  echo ""
fi

# ── Write the manifest sidecar ────────────────────────────────────────────
GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
printf '{\n  "format": "jb-v6-artifacts-manifest-1",\n  "generatedAt": "%s",\n  "monorepoRoot": "%s",\n  "gitDirty": %s,\n  "rehearsal": %s,\n  "contracts": {%s}\n}\n' \
  "$GENERATED_AT" "$MONO_ROOT" "$ANY_DIRTY" "$([[ $REHEARSAL -eq 1 ]] && echo true || echo false)" "$MANIFEST_ENTRIES" \
  | jq '.' > "$MANIFEST"

# ── Phase 2: deferred library linking ─────────────────────────────────────
# Source repos compile dependents with `__$<keccak(srcPath:libName)[:34]>$__`
# placeholders inside their bytecode. We resolve each placeholder to the
# deterministic CREATE2 address the library will deploy at (computed from
# the library's own creationCode + factory + salt) and substitute the bytes
# in `bytecode.object` + `deployedBytecode.object` of every dependent artifact.
#
# Why post-compile instead of `libraries = [...]` in foundry.toml: putting the
# pin in foundry.toml bakes the address into `metadata.settings.libraries`,
# which gets hashed into the CBOR trailer, which mutates the bytecode hash —
# shifting the deterministic CREATE2 address and breaking the pin. Source
# repos stay clean (no library config, full Sourcify match); we link here.

echo ""
echo "── Phase 2: deferred library linking ────────────────────────────────"

CREATE2_FACTORY=0x4e59b44847b379578588920cA78FbF26c0B4956C

# Map: contract name → keccak256("_<libName>V6_") salt-string used by
# `_deployPrecompiledIfNeeded` in deploy-all-v6/script/Deploy.s.sol's
# `_deployLibraries()` phase. These must match the SALT constants there.
LIB_SALTS=(
  "JBPayoutSplitGroupLib:_JBPayoutSplitGroupLibV6_"
  "JB721TiersHookLib:_JB721TiersHookLibV6_"
  "JBSuckerLib:_JBSuckerLibV6_"
  "JBCCIPLib:_JBCCIPLibV6_"
  "CCIPHelper:_CCIPHelperV6_"
  "JBSwapPoolLib:_JBSwapPoolLibV6_"
  "DefifaHookLib:_DefifaHookLibV6_"
)

declare -A LIB_ADDR_HEX        # libName → 40-char lowercase hex (no 0x prefix)
declare -A PLACEHOLDER_TO_LIB  # 34-char hex → libName

# Compute each library's deterministic CREATE2 address + its placeholder hash.
for entry in "${LIB_SALTS[@]}"; do
  IFS=':' read -r libname salt_str <<< "$entry"
  art="$ARTIFACTS_DIR/$libname.json"
  if [[ ! -f "$art" ]]; then
    echo "ERROR: missing library artifact $art (linking will be incomplete)"
    errors=$((errors + 1))
    continue
  fi
  bytecode=$(jq -r '.bytecode.object' "$art")
  salt=$(cast keccak "$salt_str")
  initcode_hash=$(cast keccak "$bytecode")
  addr=$(cast create2 --deployer "$CREATE2_FACTORY" --salt "$salt" --init-code-hash "$initcode_hash")
  # Lowercase, strip 0x. Solc placeholder substitution requires lowercase hex.
  addr_hex=$(echo "$addr" | sed 's/^0x//' | awk '{print tolower($0)}')
  LIB_ADDR_HEX[$libname]=$addr_hex

  # Solc placeholder = "__$" + keccak256("<sourcePath>:<libName>")[:17 bytes as 34 hex] + "$__"
  src_path=$(jq -r ".contracts.\"$libname\".sourcePath" "$MANIFEST")
  full_hash=$(cast keccak "${src_path}:${libname}" | sed 's/^0x//')
  short="${full_hash:0:34}"
  PLACEHOLDER_TO_LIB[$short]=$libname

  echo "  $libname → 0x$addr_hex  (placeholder __\$${short}\$__)"
done

# Walk every non-manifest artifact and substitute every known placeholder.
linked_total=0
for f in "$ARTIFACTS_DIR"/*.json; do
  [[ "$f" == *"artifacts.manifest.json" ]] && continue

  before=$(jq -r '.bytecode.object' "$f")
  before_deployed=$(jq -r '.deployedBytecode.object' "$f")
  after="$before"
  after_deployed="$before_deployed"

  changed_count=0
  for short in "${!PLACEHOLDER_TO_LIB[@]}"; do
    libname="${PLACEHOLDER_TO_LIB[$short]}"
    libaddr_hex="${LIB_ADDR_HEX[$libname]}"
    placeholder="__\$${short}\$__"
    if [[ "$after" == *"$placeholder"* ]] || [[ "$after_deployed" == *"$placeholder"* ]]; then
      after="${after//$placeholder/$libaddr_hex}"
      after_deployed="${after_deployed//$placeholder/$libaddr_hex}"
      changed_count=$((changed_count + 1))
    fi
  done

  if [[ $changed_count -gt 0 ]]; then
    tmp=$(mktemp)
    jq --arg bc "$after" --arg dc "$after_deployed" \
      '.bytecode.object = $bc | .deployedBytecode.object = $dc' \
      "$f" > "$tmp" && mv "$tmp" "$f"
    linked_total=$((linked_total + 1))
    echo "  linked $changed_count placeholder(s) in $(basename "$f")"
  fi
done

echo ""
echo "Linked $linked_total artifact(s) with library placeholders."

# ── Phase 3: persist library addresses in the manifest ───────────────────
# Surface the deterministic CREATE2 addresses + source paths so verify.mjs
# can pass `--libraries <path>:<LibName>:<addr>` for every dependent contract.
# Without this, forge verify-contract attempts to re-link against unknown
# placeholders and Etherscan rejects the verification.
LIBRARIES_JSON="{}"
for libname in "${!LIB_ADDR_HEX[@]}"; do
  src_path=$(jq -r ".contracts.\"$libname\".sourcePath" "$MANIFEST")
  addr_hex="${LIB_ADDR_HEX[$libname]}"
  LIBRARIES_JSON=$(jq -n \
    --argjson existing "$LIBRARIES_JSON" \
    --arg name "$libname" \
    --arg path "$src_path" \
    --arg addr "0x$addr_hex" \
    '$existing + {($name): {sourcePath: $path, address: $addr}}'
  )
done
tmp=$(mktemp)
jq --argjson libs "$LIBRARIES_JSON" '. + {libraries: $libs}' "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"

# Sanity check: confirm no unlinked `__$...$__` placeholders survive.
unlinked=0
for f in "$ARTIFACTS_DIR"/*.json; do
  [[ "$f" == *"artifacts.manifest.json" ]] && continue
  if jq -r '.bytecode.object' "$f" 2>/dev/null | grep -q '__\$'; then
    echo "ERROR: unlinked placeholder remains in $(basename "$f")"
    jq -r '.bytecode.object' "$f" | grep -oE "__\\\$[a-f0-9]+\\\$__" | sort -u | sed 's/^/    /'
    unlinked=$((unlinked + 1))
  fi
done

if [[ $unlinked -gt 0 ]]; then
  echo ""
  echo "ERROR: $unlinked artifact(s) still have unlinked library placeholders."
  errors=$((errors + 1))
fi

echo ""
echo "Artifacts written to: $ARTIFACTS_DIR"
echo "Manifest:             $MANIFEST"
echo "Total artifacts:      $(ls -1 "$ARTIFACTS_DIR"/*.json 2>/dev/null | grep -v artifacts.manifest.json | wc -l | tr -d ' ')"

if [[ $errors -gt 0 ]]; then
  echo "WARNING: $errors error(s) encountered"
  exit 1
fi

echo "All artifacts built + linked successfully."
