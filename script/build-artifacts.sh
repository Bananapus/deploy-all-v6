#!/usr/bin/env bash
# build-artifacts.sh — Build each source repo with its own foundry.toml and
# copy pre-compiled creation bytecodes for oversized contracts into artifacts/.
#
# Usage:  ./script/build-artifacts.sh
# Run from the deploy-all-v6 root directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MONO_ROOT="$(cd "$DEPLOY_ROOT/.." && pwd)"
ARTIFACTS_DIR="$DEPLOY_ROOT/artifacts"

# Clean previous artifacts.
rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

# ── Mapping: repo → contracts to extract ──────────────────────────────────
# Each entry is "repo_dir:ContractName:src_path" where src_path is the
# source file relative to the repo root (used to locate the Forge artifact).

CONTRACTS=(
  # nana-core-v6 (via_ir=false, optimizer=true, runs=200)
  "nana-core-v6:JBMultiTerminal:src/JBMultiTerminal.sol"
  "nana-core-v6:JBTerminalStore:src/JBTerminalStore.sol"
  "nana-core-v6:JBController:src/JBController.sol"

  # nana-721-hook-v6 (via_ir=false, optimizer=true, runs=200)
  "nana-721-hook-v6:JB721TiersHook:src/JB721TiersHook.sol"
  "nana-721-hook-v6:JB721TiersHookStore:src/JB721TiersHookStore.sol"

  # univ4-router-v6 (via_ir=true, optimizer=true, runs=200)
  "univ4-router-v6:JBUniswapV4Hook:src/JBUniswapV4Hook.sol"

  # nana-buyback-hook-v6 (via_ir=true, optimizer=true, runs=200)
  "nana-buyback-hook-v6:JBBuybackHook:src/JBBuybackHook.sol"

  # nana-router-terminal-v6 (via_ir=true, optimizer=true, runs=200)
  "nana-router-terminal-v6:JBRouterTerminal:src/JBRouterTerminal.sol"

  # univ4-lp-split-hook-v6 (via_ir=true, optimizer=true, runs=200)
  "univ4-lp-split-hook-v6:JBUniswapV4LPSplitHook:src/JBUniswapV4LPSplitHook.sol"

  # nana-suckers-v6 (via_ir=false, optimizer=true, runs=200)
  "nana-suckers-v6:JBOptimismSucker:src/JBOptimismSucker.sol"
  "nana-suckers-v6:JBBaseSucker:src/JBBaseSucker.sol"
  "nana-suckers-v6:JBArbitrumSucker:src/JBArbitrumSucker.sol"
  "nana-suckers-v6:JBCCIPSucker:src/JBCCIPSucker.sol"

  # nana-omnichain-deployers-v6 (via_ir=true, optimizer=true, runs=200)
  "nana-omnichain-deployers-v6:JBOmnichainDeployer:src/JBOmnichainDeployer.sol"

  # revnet-core-v6 (via_ir=true, optimizer=true, runs=200)
  "revnet-core-v6:REVDeployer:src/REVDeployer.sol"
  "revnet-core-v6:REVLoans:src/REVLoans.sol"

  # banny-retail-v6 (via_ir=true, optimizer=true, runs=200)
  "banny-retail-v6:Banny721TokenUriResolver:src/Banny721TokenUriResolver.sol"

  # defifa (via_ir=false, optimizer=true, runs=200)
  "defifa:DefifaHook:src/DefifaHook.sol"
  "defifa:DefifaDeployer:src/DefifaDeployer.sol"
)

# Track which repos we've already built.
declare -A BUILT_REPOS

errors=0

for entry in "${CONTRACTS[@]}"; do
  IFS=':' read -r repo contract src_path <<< "$entry"
  repo_dir="$MONO_ROOT/$repo"

  if [[ ! -d "$repo_dir" ]]; then
    echo "ERROR: repo not found: $repo_dir"
    errors=$((errors + 1))
    continue
  fi

  # Build the repo if we haven't already.
  if [[ -z "${BUILT_REPOS[$repo]+x}" ]]; then
    echo "Building $repo..."
    (cd "$repo_dir" && forge build --skip test script 2>&1) || {
      echo "ERROR: forge build failed for $repo"
      errors=$((errors + 1))
      BUILT_REPOS[$repo]=1
      continue
    }
    BUILT_REPOS[$repo]=1
  fi

  # Locate the artifact. Forge output is: out/<filename>/<ContractName>.json
  src_filename="$(basename "$src_path")"
  artifact="$repo_dir/out/$src_filename/$contract.json"

  if [[ ! -f "$artifact" ]]; then
    echo "ERROR: artifact not found: $artifact"
    errors=$((errors + 1))
    continue
  fi

  # Copy the artifact.
  cp "$artifact" "$ARTIFACTS_DIR/$contract.json"
  echo "  Copied $contract.json from $repo"
done

echo ""
echo "Artifacts written to: $ARTIFACTS_DIR"
echo "Total artifacts: $(ls -1 "$ARTIFACTS_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')"

if [[ $errors -gt 0 ]]; then
  echo "WARNING: $errors error(s) encountered"
  exit 1
fi

echo "All artifacts built successfully."
