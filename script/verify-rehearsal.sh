#!/usr/bin/env bash
# Verify-rehearsal harness: maps `script/post-deploy/.cache/addresses-<chainId>.json`
# into the `VERIFY_*` env var manifest the verifier reads, then runs `forge script
# script/Verify.s.sol:Verify` against the chain's RPC. The output is the evidence
# that the canonical-pass identity gates (CK, CL, CM, CN, CO, BE, BF, BJ, CI, CJ, CP)
# fire as expected on a live deploy.
#
# Usage:
#   ./script/verify-rehearsal.sh <chainId>             # uses RPC_<NETWORK> env var
#   ./script/verify-rehearsal.sh <chainId> <rpcUrl>    # explicit override
#
# Requires `jq` and a `.env` populated with the chain's RPC URL (RPC_ETHEREUM_MAINNET,
# RPC_ETHEREUM_SEPOLIA, RPC_OPTIMISM_MAINNET, etc.). Operator-supplied per-project
# manifest vars (VERIFY_SUCKER_PAIRS_*, VERIFY_CONFIG_HASH_*, VERIFY_BANNY_*) must
# already be exported before invoking the script — the helper only fills in the
# contract-address vars derivable from the address dump.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <chainId> [rpcUrl]" >&2
    exit 1
fi

CHAIN_ID=$1
RPC_URL_OVERRIDE=${2:-}

ADDR_FILE="script/post-deploy/.cache/addresses-${CHAIN_ID}.json"
if [[ ! -f "$ADDR_FILE" ]]; then
    echo "error: $ADDR_FILE not found — run a deploy first" >&2
    exit 1
fi

# Load .env if present so RPC_<NETWORK> picks up.
if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

# Map chainId → RPC env var name.
case "$CHAIN_ID" in
    1)         RPC_VAR=RPC_ETHEREUM_MAINNET ;;
    11155111)  RPC_VAR=RPC_ETHEREUM_SEPOLIA ;;
    10)        RPC_VAR=RPC_OPTIMISM_MAINNET ;;
    11155420)  RPC_VAR=RPC_OPTIMISM_SEPOLIA ;;
    8453)      RPC_VAR=RPC_BASE_MAINNET ;;
    84532)     RPC_VAR=RPC_BASE_SEPOLIA ;;
    42161)     RPC_VAR=RPC_ARBITRUM_MAINNET ;;
    421614)    RPC_VAR=RPC_ARBITRUM_SEPOLIA ;;
    *)         echo "error: chainId $CHAIN_ID unmapped" >&2; exit 1 ;;
esac

if [[ -n "$RPC_URL_OVERRIDE" ]]; then
    RPC_URL=$RPC_URL_OVERRIDE
else
    RPC_URL=${!RPC_VAR:-}
fi
if [[ -z "$RPC_URL" ]]; then
    echo "error: no RPC URL for chain $CHAIN_ID (set $RPC_VAR or pass as arg)" >&2
    exit 1
fi

# Pull an address from the dump by JSON key. Empty string if absent.
addr_of() { jq -r --arg k "$1" '.[$k] // ""' "$ADDR_FILE"; }

# Required canonical-address vars (always set when the dump has them).
export VERIFY_PROJECTS=$(addr_of JBProjects)
export VERIFY_DIRECTORY=$(addr_of JBDirectory)
export VERIFY_CONTROLLER=$(addr_of JBController)
export VERIFY_TERMINAL=$(addr_of JBMultiTerminal)
export VERIFY_TERMINAL_STORE=$(addr_of JBTerminalStore)
export VERIFY_TOKENS=$(addr_of JBTokens)
export VERIFY_FUND_ACCESS_LIMITS=$(addr_of JBFundAccessLimits)
export VERIFY_PRICES=$(addr_of JBPrices)
export VERIFY_RULESETS=$(addr_of JBRulesets)
export VERIFY_SPLITS=$(addr_of JBSplits)
export VERIFY_FEELESS=$(addr_of JBFeelessAddresses)
export VERIFY_PERMISSIONS=$(addr_of JBPermissions)
export VERIFY_HOOK_STORE=$(addr_of JB721TiersHookStore)
export VERIFY_HOOK_DEPLOYER=$(addr_of JB721TiersHookDeployer)
export VERIFY_HOOK_PROJECT_DEPLOYER=$(addr_of JB721TiersHookProjectDeployer)
export VERIFY_SUCKER_REGISTRY=$(addr_of JBSuckerRegistry)
export VERIFY_OMNICHAIN_DEPLOYER=$(addr_of JBOmnichainDeployer)
export VERIFY_CT_PUBLISHER=$(addr_of CTPublisher)
export VERIFY_CT_DEPLOYER=$(addr_of CTDeployer)
export VERIFY_CT_PROJECT_OWNER=$(addr_of CTProjectOwner)

# Optional canonical vars (set when present; production chains require these).
export VERIFY_ADDRESS_REGISTRY=$(addr_of JBAddressRegistry)
export VERIFY_BUYBACK_REGISTRY=$(addr_of JBBuybackHookRegistry)
export VERIFY_ROUTER_TERMINAL_REGISTRY=$(addr_of JBRouterTerminalRegistry)
export VERIFY_ROUTER_TERMINAL=$(addr_of JBRouterTerminal)
export VERIFY_REV_DEPLOYER=$(addr_of REVDeployer)
export VERIFY_REV_OWNER=$(addr_of REVOwner)
export VERIFY_REV_LOANS=$(addr_of REVLoans)
export VERIFY_DEFIFA_DEPLOYER=$(addr_of DefifaDeployer)
export VERIFY_DEFIFA_HOOK_STORE=$(addr_of JB721TiersHookStore)
export VERIFY_TRUSTED_FORWARDER=$(addr_of ERC2771Forwarder)
export VERIFY_PROJECT_HANDLES=$(addr_of JBProjectHandles)
export VERIFY_721_DISTRIBUTOR=$(addr_of JB721Distributor)
export VERIFY_TOKEN_DISTRIBUTOR=$(addr_of JBTokenDistributor)
export VERIFY_PROJECT_PAYER_DEPLOYER=$(addr_of JBProjectPayerDeployer)
export VERIFY_LP_SPLIT_HOOK_DEPLOYER=$(addr_of JBUniswapV4LPSplitHookDeployer)
export VERIFY_CHECKPOINTS_DEPLOYER=$(addr_of JB721CheckpointsDeployer)
export VERIFY_BUYBACK_HOOK=$(addr_of JBBuybackHook)

# Per-bridge sucker deployers (filled when the dump has them — testnet partial-deploys
# may omit one or more, in which case the verifier skips with a logged note).
export VERIFY_OP_SUCKER_DEPLOYER=$(addr_of JBOptimismSuckerDeployer)
export VERIFY_BASE_SUCKER_DEPLOYER=$(addr_of JBBaseSuckerDeployer)
export VERIFY_ARB_SUCKER_DEPLOYER=$(addr_of JBArbitrumSuckerDeployer)

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Verify rehearsal — chainId=$CHAIN_ID  rpc=$RPC_VAR"
echo "═══════════════════════════════════════════════════════════════"

# Use --slow + low verbosity by default; bump VERIFY_VVV to "-vvv" for trace.
forge script script/Verify.s.sol:Verify \
    --rpc-url "$RPC_URL" \
    ${VERIFY_VVV:-}
