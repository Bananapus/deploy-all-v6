#!/usr/bin/env bash
set -euo pipefail

# Juicebox V6 One-Shot Ecosystem Deployment
# ==========================================
#
# Orchestrates deployment of the entire V6 ecosystem by running each
# repo's own deploy script in the correct dependency order.
#
# No Solidity is duplicated — each repo's Deploy.s.sol is used as-is.
# Artifacts are downloaded to a shared directory so downstream phases
# can read upstream deployment addresses.
#
# Usage:
#   ./deploy.sh [testnets|mainnets]
#
# Prerequisites:
#   1. Copy .env.example to .env and fill in SPHINX_ORG_ID
#   2. Each source repo must have npm installed and .env configured
#   3. Run `npm install` in this directory for the Sphinx CLI
#   4. Run `npx sphinx setup` if not already configured
#
# Deployment Order:
#   01.  Core protocol                           (nana-core-v6)
#   02.  Address registry                        (nana-address-registry-v6)
#   03a. 721 tier hook         ┐
#   03b. Buyback hook          │ PARALLEL
#   03c. Router terminal       │ no cross-deps
#   03d. Cross-chain suckers   ┘
#   04.  Omnichain deployer                      (nana-omnichain-deployers-v6)
#   05.  Periphery / Controller                  (nana-core-v6 DeployPeriphery)
#   06.  Croptop contracts                       (croptop-core-v6)
#   07.  Revnet infra + $REV revnet              (revnet-core-v6)
#   08.  NANA fee project (project ID 1)         (nana-fee-project-deployer-v6)
#   09.  Banny Network revnet                    (banny-retail-v6)
#   10.  Defifa contracts                        (defifa-collection-deployer-v6)
#
# NOTE: A Defifa revnet deploy script does not exist yet. It needs to be
# created to establish project ID 3 before the Defifa contracts are deployed.
# Once created, insert it between phases 08 and 10.

# ── Setup ──

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOS_DIR="$(dirname "$DEPLOY_DIR")"
SHARED_DEPLOYMENTS="$DEPLOY_DIR/deployments/"

NETWORK="${1:-${DEPLOY_NETWORK:-testnets}}"

if [[ "$NETWORK" != "testnets" && "$NETWORK" != "mainnets" ]]; then
  echo "Usage: ./deploy.sh [testnets|mainnets]"
  exit 1
fi

# Load our .env for SPHINX_ORG_ID.
if [[ -f "$DEPLOY_DIR/.env" ]]; then
  source "$DEPLOY_DIR/.env"
fi

if [[ -z "${SPHINX_ORG_ID:-}" ]]; then
  echo "Error: SPHINX_ORG_ID not set. Copy .env.example to .env and fill it in."
  exit 1
fi

mkdir -p "$SHARED_DEPLOYMENTS"

echo "========================================="
echo " Juicebox V6 Deployment — $NETWORK"
echo "========================================="
echo ""
echo " Repos:       $REPOS_DIR"
echo " Artifacts:   $SHARED_DEPLOYMENTS"
echo ""

# ── Helpers ──

propose() {
  local phase="$1"
  local repo="$2"
  local script="$3"
  local description="$4"
  shift 4

  echo "-------------------------------------------"
  echo " Phase $phase: $description"
  echo "-------------------------------------------"

  # cd into the source repo so forge can resolve imports & foundry.toml.
  (
    cd "$REPOS_DIR/$repo"

    # Point all artifact-reading env vars to the shared deployments dir.
    export NANA_CORE_DEPLOYMENT_PATH="$SHARED_DEPLOYMENTS"
    export NANA_ADDRESS_REGISTRY_DEPLOYMENT_PATH="$SHARED_DEPLOYMENTS"
    export NANA_721_DEPLOYMENT_PATH="$SHARED_DEPLOYMENTS"
    export NANA_BUYBACK_HOOK_DEPLOYMENT_PATH="$SHARED_DEPLOYMENTS"
    export NANA_ROUTER_TERMINAL_DEPLOYMENT_PATH="$SHARED_DEPLOYMENTS"
    export NANA_SUCKERS_DEPLOYMENT_PATH="$SHARED_DEPLOYMENTS"
    export CROPTOP_CORE_DEPLOYMENT_PATH="$SHARED_DEPLOYMENTS"
    export REVNET_CORE_DEPLOYMENT_PATH="$SHARED_DEPLOYMENTS"

    npx sphinx propose "$script" --networks "$NETWORK"
  )

  echo ""
  echo ">> Phase $phase proposed. Approve and execute via Sphinx UI."
  echo ">> Then press ENTER to download artifacts and continue."
  read -r
}

download_artifacts() {
  local project_name="$1"
  echo "   Downloading artifacts for $project_name..."
  (
    cd "$DEPLOY_DIR"
    npx sphinx artifacts --org-id "$SPHINX_ORG_ID" --project-name "$project_name" 2>/dev/null || true
  )
}

# ── Phase 01: Core Protocol ──

propose "01" \
  "nana-core-v6" \
  "script/Deploy.s.sol" \
  "Core Protocol (JBPermissions, JBProjects, JBDirectory, ...)"

download_artifacts "nana-core-v5"

# ── Phase 02: Address Registry ──

propose "02" \
  "nana-address-registry-v6" \
  "script/Deploy.s.sol" \
  "Address Registry (JBAddressRegistry)"

download_artifacts "nana-address-registry-v6"

# ── Phase 03a-d: Hooks & Suckers (PARALLEL — no cross-dependencies) ──

echo "==========================================="
echo " Phases 03a-03d can be proposed in parallel."
echo " They only depend on Core (01) and have no"
echo " cross-dependencies with each other."
echo "==========================================="
echo ""

propose "03a" \
  "nana-721-hook-v6" \
  "script/Deploy.s.sol" \
  "721 Tier Hook (JB721TiersHookStore, JB721TiersHook, ...)"

download_artifacts "nana-721-hook-v6"

propose "03b" \
  "nana-buyback-hook-v6" \
  "script/Deploy.s.sol" \
  "Buyback Hook (JBBuybackHook)"

download_artifacts "nana-buyback-hook-v6"

propose "03c" \
  "nana-router-terminal-v6" \
  "script/Deploy.s.sol" \
  "Router Terminal (JBRouterTerminal)"

download_artifacts "nana-router-terminal-v6"

propose "03d" \
  "nana-suckers-v6" \
  "script/Deploy.s.sol" \
  "Cross-Chain Suckers (OP, Base, Arbitrum, CCIP)"

download_artifacts "nana-suckers-v5"

# ── Phase 04: Omnichain Deployer ──

propose "04" \
  "nana-omnichain-deployers-v6" \
  "script/Deploy.s.sol" \
  "Omnichain Deployer (JBOmnichainDeployer)"

download_artifacts "nana-omnichain-deployers-v6"

# ── Phase 05: Periphery / Controller ──
# NOTE: This must come AFTER the omnichain deployer because JBController
# takes the omnichain deployer address as its omnichainRulesetOperator.

propose "05" \
  "nana-core-v6" \
  "script/DeployPeriphery.s.sol" \
  "Periphery (JBController, Price Feeds, Deadlines)"

download_artifacts "nana-core-v5"

# ── Phase 06: Croptop ──

propose "06" \
  "croptop-core-v6" \
  "script/Deploy.s.sol" \
  "Croptop (CTPublisher, CTDeployer, CTProjectOwner)"

download_artifacts "croptop-core-v6"

# ── Phase 07: Revnet ──

propose "07" \
  "revnet-core-v6" \
  "script/Deploy.s.sol" \
  "Revnet (REVLoans, REVDeployer, \$REV fee project)"

download_artifacts "revnet-core-v6"

# ── Phase 08: NANA Fee Project ──

propose "08" \
  "nana-fee-project-deployer-v6" \
  "script/Deploy.s.sol" \
  "NANA Fee Project (Bananapus — project ID 1)"

download_artifacts "nana-core-v6"

# ── Phase 09: Banny Network ──

propose "09" \
  "banny-retail-v6" \
  "script/Deploy.s.sol" \
  "Banny Network Revnet (\$BAN + 721 tiers)"

download_artifacts "banny-core-v6"

# ── Phase 10: Defifa Contracts ──
# NOTE: Requires a Defifa revnet (project ID 3) to exist first.
# A deploy script for the Defifa revnet does not exist yet — it needs
# to be created (with "standard" revnet specs) and run before this phase.

echo ""
echo "==========================================="
echo " TODO: Deploy Defifa revnet (project ID 3)"
echo " A deploy script with standard revnet specs"
echo " needs to be created for this step."
echo "==========================================="
echo ""
echo ">> Press ENTER once the Defifa revnet is deployed."
read -r

propose "10" \
  "defifa-collection-deployer-v6" \
  "script/Deploy.s.sol" \
  "Defifa Contracts (DefifaHook, DefifaDeployer, DefifaGovernor)"

download_artifacts "defifa-v5"

# ── Done ──

echo ""
echo "========================================="
echo " Deployment Complete!"
echo "========================================="
echo ""
echo "All artifacts are in: $SHARED_DEPLOYMENTS"
echo ""
