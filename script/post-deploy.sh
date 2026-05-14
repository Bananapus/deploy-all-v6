#!/usr/bin/env bash
# post-deploy.sh — Verify + emit + distribute artifacts AFTER a Sphinx deploy.
#
# Replaces Sphinx's auto-verify + auto-artifact pipeline (which is disabled in
# the v6 setup). Each contract is verified against its SOURCE REPO's compile
# settings (read from artifacts.manifest.json) and the emitted JSON matches
# the v5 sphinx-sol-ct-artifact-1 schema byte-for-byte (sans merkleRoot).
#
# Workflow:
#   1. Pre-flight checks (artifacts/, manifest, node, forge, ETHERSCAN_API_KEY).
#   2. For each chain:
#        a. Dump addresses (forge script Deploy.s.sol --rpc-url $RPC).
#        b. Verify every deployed contract on Etherscan (with retry+backoff).
#        c. Emit sphinx-format artifact JSON per contract.
#        d. Distribute to deploy-all-v6/deployments/juicebox-v6/<chain>/
#           AND each source repo's deployments/<sphinxProject>/<chain>/.
#   3. Print a per-chain summary.
#
# Usage:
#   ./script/post-deploy.sh --chains=ethereum,optimism,base,arbitrum
#   ./script/post-deploy.sh --chains=sepolia                     # one chain
#   ./script/post-deploy.sh --chains=all-testnets
#   ./script/post-deploy.sh --chains=all-mainnets
#   ./script/post-deploy.sh --skip-verify                        # artifact emit + distribute only
#   ./script/post-deploy.sh --skip-artifacts                     # verify only
#   ./script/post-deploy.sh --dry-run                            # show what would happen
#   ./script/post-deploy.sh --rehearsal                          # allow gitDirty manifest on prod chains
#
# Env vars (required):
#   ETHERSCAN_API_KEY       single key for Etherscan v2 unified API
#   RPC_ETHEREUM_MAINNET    \
#   RPC_OPTIMISM_MAINNET     \
#   RPC_BASE_MAINNET          \  one per chain you want to process
#   RPC_ARBITRUM_MAINNET      /
#   RPC_ETHEREUM_SEPOLIA     /
#   RPC_OPTIMISM_SEPOLIA    /  (etc.)
#   RPC_BASE_SEPOLIA       /
#   RPC_ARBITRUM_SEPOLIA  /
#
# Optional:
#   SAFE_ADDRESS          Sphinx multi-sig safe address. Passed as `--sender` to forge script
#                         so auth-gated phases (REVOwner.setDeployer, safeAddress()-bound
#                         permissions) don't revert during the address-dump dry-run on fresh
#                         chains. Required on a never-deployed chain; optional otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="$DEPLOY_ROOT/artifacts"
POST_DEPLOY_DIR="$SCRIPT_DIR/post-deploy"
CACHE_DIR="$POST_DEPLOY_DIR/.cache"
CHAINS_JSON="$POST_DEPLOY_DIR/chains.json"

# ── CLI args ──────────────────────────────────────────────────────────────
CHAINS_ARG=""
SKIP_VERIFY=0
SKIP_ARTIFACTS=0
SKIP_DISTRIBUTE=0
DRY_RUN=0
REHEARSAL=0

for arg in "$@"; do
  case "$arg" in
    --chains=*) CHAINS_ARG="${arg#*=}" ;;
    --skip-verify) SKIP_VERIFY=1 ;;
    --skip-artifacts) SKIP_ARTIFACTS=1 ;;
    --skip-distribute) SKIP_DISTRIBUTE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --rehearsal) REHEARSAL=1 ;;
    -h|--help)
      sed -n '2,40p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $arg"; exit 2 ;;
  esac
done

[[ -z "$CHAINS_ARG" ]] && { echo "ERROR: --chains=<csv> required (e.g. --chains=sepolia or --chains=all-testnets)"; exit 2; }

# ── Pre-flight ────────────────────────────────────────────────────────────
command -v node >/dev/null || { echo "ERROR: node required"; exit 2; }
command -v forge >/dev/null || { echo "ERROR: forge required"; exit 2; }
command -v jq >/dev/null || { echo "ERROR: jq required (brew install jq)"; exit 2; }

[[ -d "$ARTIFACTS_DIR" ]] || { echo "ERROR: artifacts/ missing. Run ./script/build-artifacts.sh first."; exit 2; }
[[ -f "$ARTIFACTS_DIR/artifacts.manifest.json" ]] || { echo "ERROR: artifacts.manifest.json missing."; exit 2; }
[[ -f "$CHAINS_JSON" ]] || { echo "ERROR: chains.json missing."; exit 2; }

# Dirty-source preflight: if the manifest is gitDirty and any chain in this run
# is production, refuse to proceed unless --rehearsal is passed. This is a
# defense-in-depth check; verify.mjs and artifacts.mjs enforce the same gate.
MANIFEST_DIRTY="$(jq -r '.gitDirty // false' "$ARTIFACTS_DIR/artifacts.manifest.json")"

if [[ "$SKIP_VERIFY" -eq 0 ]]; then
  [[ -n "${ETHERSCAN_API_KEY:-}" ]] || {
    echo "ERROR: ETHERSCAN_API_KEY env var required for verification. Get one at https://etherscan.io/myapikey"
    echo "       (Use --skip-verify to skip verification.)"
    exit 2
  }
fi

mkdir -p "$CACHE_DIR"

# ── Resolve chain aliases → (chainId, rpc env var) ────────────────────────
resolve_chains() {
  local arg="$1"
  case "$arg" in
    all-mainnets) echo "ethereum optimism base arbitrum" ;;
    all-testnets) echo "sepolia optimism_sepolia base_sepolia arbitrum_sepolia" ;;
    all) echo "ethereum optimism base arbitrum sepolia optimism_sepolia base_sepolia arbitrum_sepolia" ;;
    *) echo "$arg" | tr ',' ' ' ;;
  esac
}

alias_to_chain_id() {
  jq -r --arg a "$1" '.chains | to_entries[] | select(.value.alias == $a) | .key' "$CHAINS_JSON"
}

alias_to_rpc_env() {
  case "$1" in
    ethereum) echo "RPC_ETHEREUM_MAINNET" ;;
    optimism) echo "RPC_OPTIMISM_MAINNET" ;;
    base) echo "RPC_BASE_MAINNET" ;;
    arbitrum) echo "RPC_ARBITRUM_MAINNET" ;;
    sepolia) echo "RPC_ETHEREUM_SEPOLIA" ;;
    optimism_sepolia) echo "RPC_OPTIMISM_SEPOLIA" ;;
    base_sepolia) echo "RPC_BASE_SEPOLIA" ;;
    arbitrum_sepolia) echo "RPC_ARBITRUM_SEPOLIA" ;;
    *) echo "" ;;
  esac
}

CHAINS_LIST=$(resolve_chains "$CHAINS_ARG")
echo "Processing chains: $CHAINS_LIST"
[[ "$DRY_RUN" -eq 1 ]] && echo "(DRY RUN — no writes)"

# ── Process each chain ────────────────────────────────────────────────────
GLOBAL_FAIL=0
SUMMARY=""

for alias in $CHAINS_LIST; do
  echo ""
  echo "═════════════════════════════════════════════════════════"
  echo " Chain: $alias"
  echo "═════════════════════════════════════════════════════════"

  chain_id="$(alias_to_chain_id "$alias")"
  if [[ -z "$chain_id" ]]; then
    echo "  SKIP — unknown alias '$alias' (not in chains.json)"
    GLOBAL_FAIL=1
    SUMMARY+="  $alias: SKIP (unknown alias)\n"
    continue
  fi

  # Dirty-source preflight: refuse production chains with dirty manifest unless --rehearsal.
  chain_production="$(jq -r --arg cid "$chain_id" '.chains[$cid].production // false' "$CHAINS_JSON")"
  if [[ "$MANIFEST_DIRTY" == "true" && "$chain_production" == "true" && "$REHEARSAL" -eq 0 ]]; then
    echo "  SKIP — production chain $alias refuses dirty manifest. Rebuild clean or pass --rehearsal."
    GLOBAL_FAIL=1
    SUMMARY+="  $alias: SKIP (dirty manifest)\n"
    continue
  fi

  rpc_env="$(alias_to_rpc_env "$alias")"
  rpc="${!rpc_env:-}"
  if [[ -z "$rpc" ]]; then
    echo "  SKIP — \$$rpc_env not set"
    GLOBAL_FAIL=1
    SUMMARY+="  $alias: SKIP (no RPC)\n"
    continue
  fi

  # ── Step 1: dump addresses by running Deploy.s.sol (no broadcast) ──
  # Note: --sender must match the Sphinx Safe so that auth-gated setup calls (REVOwner,
  # safeAddress()-bound permissions) don't revert. Without --sender, forge picks a default that
  # fails REVOwner's auth check on a fresh chain. If SAFE_ADDRESS is unset, we fall back to a
  # zero-arg `forge script` which works fine on chains where the deploy has already happened
  # (each phase's `_isDeployed` short-circuits) but not on fresh chains.
  sender_flag=""
  if [[ -n "${SAFE_ADDRESS:-}" ]]; then
    sender_flag="--sender $SAFE_ADDRESS"
  fi
  echo "  [1/4] Dumping addresses (forge script, dry-run)..."
  if [[ "$DRY_RUN" -eq 0 ]]; then
    (cd "$DEPLOY_ROOT" && forge script script/Deploy.s.sol --rpc-url "$rpc" $sender_flag --silent) || {
      echo "    forge script failed for $alias — skipping chain"
      GLOBAL_FAIL=1
      SUMMARY+="  $alias: forge dump FAILED\n"
      continue
    }
    if [[ ! -f "$CACHE_DIR/addresses-${chain_id}.json" ]]; then
      echo "    No addresses-${chain_id}.json produced (chain not in _setupChainAddresses?). Skipping."
      GLOBAL_FAIL=1
      SUMMARY+="  $alias: no address dump\n"
      continue
    fi
    addr_count=$(jq '[.[] | strings | select(startswith("0x"))] | length' "$CACHE_DIR/addresses-${chain_id}.json")
    echo "    → $addr_count address(es) captured."
  else
    echo "    (skipped — dry-run)"
  fi

  rehearsal_flag=""
  [[ "$REHEARSAL" -eq 1 ]] && rehearsal_flag="--rehearsal"

  # ── Step 2: verify each contract on Etherscan ──
  if [[ "$SKIP_VERIFY" -eq 0 ]]; then
    echo "  [2/4] Verifying on Etherscan..."
    if [[ "$DRY_RUN" -eq 0 ]]; then
      node "$POST_DEPLOY_DIR/lib/verify.mjs" --chain "$chain_id" $rehearsal_flag || {
        echo "    Some contracts failed verification. Continuing to artifact emission."
        GLOBAL_FAIL=1
      }
    else
      echo "    (skipped — dry-run)"
    fi
  else
    echo "  [2/4] (skip-verify)"
  fi

  # ── Step 3: emit sphinx-format artifacts ──
  if [[ "$SKIP_ARTIFACTS" -eq 0 ]]; then
    echo "  [3/4] Emitting artifacts..."
    if [[ "$DRY_RUN" -eq 0 ]]; then
      node "$POST_DEPLOY_DIR/lib/artifacts.mjs" --chain "$chain_id" $rehearsal_flag || {
        echo "    Some artifacts failed to generate."
        GLOBAL_FAIL=1
      }
    else
      echo "    (skipped — dry-run)"
    fi
  else
    echo "  [3/4] (skip-artifacts)"
  fi

  # ── Step 4: fan out to per-repo deployments/ ──
  if [[ "$SKIP_DISTRIBUTE" -eq 0 ]]; then
    echo "  [4/4] Distributing artifacts..."
    extra=""
    [[ "$DRY_RUN" -eq 1 ]] && extra="--dry-run"
    node "$POST_DEPLOY_DIR/lib/distribute.mjs" --chain "$chain_id" $extra || {
      echo "    Some artifacts failed to distribute."
      GLOBAL_FAIL=1
    }
  else
    echo "  [4/4] (skip-distribute)"
  fi

  # Per-chain summary
  if [[ -f "$CACHE_DIR/status-${chain_id}.json" ]]; then
    verified=$(jq '[.contracts | to_entries[] | select(.value.status == "verified")] | length' "$CACHE_DIR/status-${chain_id}.json")
    failed=$(jq '[.contracts | to_entries[] | select(.value.status == "failed")] | length' "$CACHE_DIR/status-${chain_id}.json")
    SUMMARY+="  $alias: $verified verified, $failed failed\n"
  else
    SUMMARY+="  $alias: (no status file)\n"
  fi
done

# ── Final report ──────────────────────────────────────────────────────────
echo ""
echo "═════════════════════════════════════════════════════════"
echo " post-deploy.sh summary"
echo "═════════════════════════════════════════════════════════"
printf "%b" "$SUMMARY"

if [[ "$GLOBAL_FAIL" -ne 0 ]]; then
  echo ""
  echo "One or more chains had failures. Inspect .cache/status-<chainId>.json for details."
  echo "Re-run the same command to retry failed contracts (verification is idempotent)."
  exit 1
fi

echo ""
echo "All chains processed successfully."
