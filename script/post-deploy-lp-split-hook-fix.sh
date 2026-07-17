#!/usr/bin/env bash
# Focused post-deploy for the LP split hook fix (univ4-lp-split-hook-v6 1.3.0).
#
# Dumps ONLY the three LP-split contract addresses per chain (JBUniswapV4LPSplitHookMath, JBUniswapV4LPSplitHook,
# JBUniswapV4LPSplitHookDeployer) via DeployLpSplitHookFix.dumpAddresses(), then verifies + emits + distributes
# just those through the shared post-deploy pipeline (post-deploy.sh --skip-dump reuses our focused dump). This
# avoids re-running the full Deploy.s.sol dump / re-touching every other contract's artifacts.
#
# Usage:
#   ./script/post-deploy-lp-split-hook-fix.sh --chains=all-testnets
#   ./script/post-deploy-lp-split-hook-fix.sh --chains=all-mainnets
#   ./script/post-deploy-lp-split-hook-fix.sh --chains=base_sepolia          # one chain
#   ./script/post-deploy-lp-split-hook-fix.sh --chains=all-mainnets --skip-verify   # emit + distribute only
#
# Requires ETHERSCAN_API_KEY (unless --skip-verify) and each chain's RPC env var, same as post-deploy.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$SCRIPT_DIR/post-deploy/.cache"
CHAINS_JSON="$SCRIPT_DIR/post-deploy/chains.json"

CHAINS_ARG=""
PASSTHRU=()
for arg in "$@"; do
  case "$arg" in
    --chains=*) CHAINS_ARG="${arg#*=}" ;;
    *) PASSTHRU+=("$arg") ;;
  esac
done
[[ -z "$CHAINS_ARG" ]] && { echo "ERROR: --chains=<csv|all-testnets|all-mainnets> required"; exit 2; }

resolve_chains() {
  case "$1" in
    all-mainnets) echo "ethereum optimism base arbitrum" ;;
    all-testnets) echo "sepolia optimism_sepolia base_sepolia arbitrum_sepolia" ;;
    all) echo "ethereum optimism base arbitrum sepolia optimism_sepolia base_sepolia arbitrum_sepolia" ;;
    *) echo "$1" | tr ',' ' ' ;;
  esac
}
alias_to_chain_id() { jq -r --arg a "$1" '.chains | to_entries[] | select(.value.alias == $a) | .key' "$CHAINS_JSON"; }
alias_to_rpc_env() {
  case "$1" in
    ethereum) echo RPC_ETHEREUM_MAINNET ;;
    optimism) echo RPC_OPTIMISM_MAINNET ;;
    base) echo RPC_BASE_MAINNET ;;
    arbitrum) echo RPC_ARBITRUM_MAINNET ;;
    sepolia) echo RPC_ETHEREUM_SEPOLIA ;;
    optimism_sepolia) echo RPC_OPTIMISM_SEPOLIA ;;
    base_sepolia) echo RPC_BASE_SEPOLIA ;;
    arbitrum_sepolia) echo RPC_ARBITRUM_SEPOLIA ;;
    *) echo "" ;;
  esac
}

FAIL=0
for alias in $(resolve_chains "$CHAINS_ARG"); do
  echo ""
  echo "═════════════════════════════════════════════════════════"
  echo " Chain: $alias"
  echo "═════════════════════════════════════════════════════════"
  cid="$(alias_to_chain_id "$alias")"
  rpc_env="$(alias_to_rpc_env "$alias")"
  rpc="${!rpc_env:-}"
  if [[ -z "$cid" || -z "$rpc" ]]; then
    echo "  SKIP — missing chainId or \$$rpc_env"; FAIL=1; continue
  fi

  # Fresh focused dump — remove any stale full-deploy dump so post-deploy processes ONLY the 3 LP-split contracts.
  rm -f "$CACHE_DIR/addresses-${cid}.json"
  echo "  [dump] LP-split addresses…"
  (cd "$DEPLOY_ROOT" && forge script script/DeployLpSplitHookFix.s.sol --sig "dumpAddresses()" --rpc-url "$rpc" --silent) \
    || { echo "  dump failed on $alias"; FAIL=1; continue; }

  if [[ ! -f "$CACHE_DIR/addresses-${cid}.json" ]]; then
    echo "  $alias has no LP stack (no PositionManager) — nothing to verify/emit."
    continue
  fi

  echo "  [post-deploy] verify + emit + distribute (focused)…"
  if [[ ${#PASSTHRU[@]} -gt 0 ]]; then
    (cd "$DEPLOY_ROOT" && ./script/post-deploy.sh --chains="$alias" --skip-dump "${PASSTHRU[@]}") || FAIL=1
  else
    (cd "$DEPLOY_ROOT" && ./script/post-deploy.sh --chains="$alias" --skip-dump) || FAIL=1
  fi
done

[[ "$FAIL" -eq 0 ]] && echo "" && echo "✅ LP split hook fix post-deploy complete." || { echo ""; echo "⚠ completed with failures — review above."; exit 1; }
