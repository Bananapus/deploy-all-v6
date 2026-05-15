#!/usr/bin/env bash
# rehearse-addresses.sh — Compute the deterministic CREATE2 addresses + ABIs
# that the Sphinx broadcast would produce on every supported chain, without
# paying a single wei of gas.
#
# How it works:
#   - `pnpm artifacts` (or `./script/build-artifacts.sh --rehearsal`) builds
#     every source repo and writes the canonical artifact JSONs (with ABIs)
#     into `./artifacts/`. ABIs are chain-independent — one build covers all
#     chains.
#   - For each chain, `forge script Deploy.s.sol --rpc-url <chain> --sender <safe>`
#     runs the deploy as a SIMULATION (no `--broadcast`). The script's
#     `_dumpAddresses` step still writes the deterministic CREATE2 addresses
#     to `script/post-deploy/.cache/addresses-<chainId>.json`. Those are the
#     addresses the eventual Sphinx broadcast will land at — `salt + initcode
#     + canonical CREATE2 factory` reproducibility.
#   - This script collects all per-chain dumps into one `rehearsal-output/`
#     bundle so consumers (frontends, indexers, the auditor) can preview
#     where every contract will live before any broadcast happens.
#
# Usage:
#   ./script/rehearse-addresses.sh                          # all configured chains
#   ./script/rehearse-addresses.sh 1 11155111               # just specified chain IDs
#
# Requires the chain's RPC env var (RPC_ETHEREUM_MAINNET, RPC_OPTIMISM_SEPOLIA, …)
# to be exported (typically via `.env`).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="$DEPLOY_ROOT/artifacts"
CACHE_DIR="$DEPLOY_ROOT/script/post-deploy/.cache"
OUT_DIR="$DEPLOY_ROOT/rehearsal-output"
SAFE_SENDER="0x80a8F7a4bD75b539CE26937016Df607fdC9ABeb5" # canonical Sphinx Safe

# Map chainId → RPC env var name.
declare -A RPC_VAR=(
    [1]=RPC_ETHEREUM_MAINNET
    [11155111]=RPC_ETHEREUM_SEPOLIA
    [10]=RPC_OPTIMISM_MAINNET
    [11155420]=RPC_OPTIMISM_SEPOLIA
    [8453]=RPC_BASE_MAINNET
    [84532]=RPC_BASE_SEPOLIA
    [42161]=RPC_ARBITRUM_MAINNET
    [421614]=RPC_ARBITRUM_SEPOLIA
)

declare -A CHAIN_LABEL=(
    [1]="ethereum-mainnet"
    [11155111]="ethereum-sepolia"
    [10]="optimism-mainnet"
    [11155420]="optimism-sepolia"
    [8453]="base-mainnet"
    [84532]="base-sepolia"
    [42161]="arbitrum-mainnet"
    [421614]="arbitrum-sepolia"
)

# Default chain set = every key in RPC_VAR. Override with positional args.
if [[ $# -gt 0 ]]; then
    CHAINS=("$@")
else
    CHAINS=(1 10 8453 42161 11155111 11155420 84532 421614)
fi

# Load .env so RPC_<NETWORK> vars are visible.
if [[ -f "$DEPLOY_ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$DEPLOY_ROOT/.env"
    set +a
fi

mkdir -p "$OUT_DIR"

# Build artifacts once — they're chain-independent.
if [[ ! -f "$ARTIFACTS_DIR/artifacts.manifest.json" ]]; then
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo " Building canonical artifacts (one-shot, chain-independent ABIs)"
    echo "════════════════════════════════════════════════════════════════════"
    (cd "$DEPLOY_ROOT" && ./script/build-artifacts.sh --rehearsal)
fi

# Copy ABIs once into the rehearsal output. The full artifact JSONs include
# bytecode + ABI; consumers that only want the ABI surface can `jq .abi` them.
mkdir -p "$OUT_DIR/abis"
cp "$ARTIFACTS_DIR"/*.json "$OUT_DIR/abis/" 2>/dev/null || true

SUCCESS_CHAINS=()
FAILED_CHAINS=()

for CHAIN_ID in "${CHAINS[@]}"; do
    LABEL=${CHAIN_LABEL[$CHAIN_ID]:-chain-$CHAIN_ID}
    VAR=${RPC_VAR[$CHAIN_ID]:-}

    if [[ -z "$VAR" ]]; then
        echo "[skip] chain $CHAIN_ID — no RPC mapping"
        FAILED_CHAINS+=("$CHAIN_ID:no-mapping")
        continue
    fi

    RPC=${!VAR:-}
    if [[ -z "$RPC" ]]; then
        echo "[skip] chain $CHAIN_ID ($LABEL) — $VAR not set"
        FAILED_CHAINS+=("$CHAIN_ID:rpc-unset")
        continue
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo " Rehearsing chain $CHAIN_ID ($LABEL)"
    echo "════════════════════════════════════════════════════════════════════"

    # Spin up an anvil fork of the chain so we can credit the Sphinx Safe with
    # gas balance before simulating. Some RPCs (notably Optimism) enforce a
    # non-zero sender balance during eth_call simulation; the safe has no
    # native balance on most chains, so a direct `forge script --rpc-url <real>`
    # fails with `lack of funds (0)`. The anvil fork lets us `anvil_setBalance`
    # the safe to any amount.
    ANVIL_PORT=$((8700 + RANDOM % 100))
    ANVIL_PID_FILE="/tmp/anvil-rehearse-$CHAIN_ID.pid"
    # Pin a fork block slightly behind tip so non-archive RPCs don't reject the
    # state pull mid-handshake.
    TIP=$(cast block-number --rpc-url "$RPC" 2>/dev/null || echo 0)
    if [[ "$TIP" == "0" ]]; then
        echo "  ✗ cannot read tip block from $VAR"
        FAILED_CHAINS+=("$CHAIN_ID:tip-unreachable")
        continue
    fi
    FORK_BLOCK=$((TIP - 5))

    anvil --fork-url "$RPC" --fork-block-number "$FORK_BLOCK" --auto-impersonate \
        --port "$ANVIL_PORT" --silent > "$OUT_DIR/$LABEL-anvil.log" 2>&1 &
    echo $! > "$ANVIL_PID_FILE"
    sleep 6
    if ! cast chain-id --rpc-url "http://localhost:$ANVIL_PORT" >/dev/null 2>&1; then
        echo "  ✗ anvil fork failed to start"
        kill "$(cat "$ANVIL_PID_FILE")" 2>/dev/null || true
        rm -f "$ANVIL_PID_FILE"
        FAILED_CHAINS+=("$CHAIN_ID:fork-failed")
        continue
    fi
    cast rpc anvil_setBalance "$SAFE_SENDER" 0x1000000000000000000000 \
        --rpc-url "http://localhost:$ANVIL_PORT" >/dev/null 2>&1 || true

    # Simulate the deploy against the fork. No `--broadcast`, so the sphinx
    # modifier's `vm.startPrank` just makes _isDeployed compute the right
    # CREATE2 addresses; `_dumpAddresses` writes the deterministic addresses
    # to the cache file regardless.
    if (cd "$DEPLOY_ROOT" && forge script script/Deploy.s.sol \
            --rpc-url "http://localhost:$ANVIL_PORT" \
            --sender "$SAFE_SENDER" \
            --silent) > "$OUT_DIR/$LABEL-deploy.log" 2>&1
    then
        if [[ -f "$CACHE_DIR/addresses-$CHAIN_ID.json" ]]; then
            cp "$CACHE_DIR/addresses-$CHAIN_ID.json" "$OUT_DIR/addresses-$CHAIN_ID-$LABEL.json"
            echo "  ✓ wrote $OUT_DIR/addresses-$CHAIN_ID-$LABEL.json"
            SUCCESS_CHAINS+=("$CHAIN_ID:$LABEL")
        else
            echo "  ✗ simulation succeeded but no address dump produced"
            FAILED_CHAINS+=("$CHAIN_ID:no-dump")
        fi
    else
        echo "  ✗ simulation failed — see $OUT_DIR/$LABEL-deploy.log"
        FAILED_CHAINS+=("$CHAIN_ID:revert")
    fi

    # Tear down this chain's anvil fork.
    kill "$(cat "$ANVIL_PID_FILE")" 2>/dev/null || true
    rm -f "$ANVIL_PID_FILE"
done

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo " Rehearsal summary"
echo "════════════════════════════════════════════════════════════════════"
echo "  artifacts (ABIs): $OUT_DIR/abis/  ($(ls "$OUT_DIR/abis/" 2>/dev/null | wc -l | tr -d ' ') JSON files)"
echo "  successful chains: ${#SUCCESS_CHAINS[@]}"
for c in "${SUCCESS_CHAINS[@]}"; do echo "    - $c"; done
if [[ ${#FAILED_CHAINS[@]} -gt 0 ]]; then
    echo "  failed/skipped chains: ${#FAILED_CHAINS[@]}"
    for c in "${FAILED_CHAINS[@]}"; do echo "    - $c"; done
fi
echo ""
echo "Bundle contents:"
ls -1 "$OUT_DIR" | sed 's/^/  /'
