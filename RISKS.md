# deploy-all-v6 — Risks

## Trust Assumptions

1. **Sphinx Platform** — Deployment orchestrated via Sphinx proposals. Sphinx controls execution order and atomicity per phase.
2. **Hardcoded Addresses** — External contract addresses (Uniswap factories, Chainlink feeds, WETH) are hardcoded per chain. Must match canonical deployments.
3. **Constructor Parameters** — All initialization parameters are in the script. Wrong parameters = wrong behavior, potentially irreversible.
4. **Deployment Ordering** — Contracts deployed in phases. Partially deployed state between phases could theoretically be exploited, but contracts aren't usable until fully wired.

## Known Risks

| Risk | Description | Mitigation |
|------|-------------|------------|
| Deployment ordering | Partially deployed state between Sphinx phases | Contracts aren't usable until wiring phase completes |
| Oracle hook dependency ordering | `JBBuybackHook` and `JBUniswapV4LPSplitHook` both require a deployed `JBUniswapV4Hook` (oracle hook) address at construction. Deploying them before the oracle hook, or passing the wrong address, means TWAP queries fail and swaps fall back to spot price (vulnerable to single-block manipulation) | Deploy `JBUniswapV4Hook` first; pass its address as `oracleHook` to buyback and LP split hook constructors |
| Hardcoded addresses | External addresses (Uniswap, Chainlink) must match canonical per chain | Addresses verified against canonical deployments |
| Constructor errors | Wrong parameters could lock funds or grant wrong permissions | Script tested via `forge build`; CI verifies compilation |
| No optimizer | `optimizer = false` means very large bytecode | Acceptable for deployment scripts; not deployed as contracts |
| Cross-chain consistency | Same contracts must deploy to same addresses across chains | Sphinx ensures consistent deployment via CREATE2 |
| Gas limits | Full ecosystem deployment is gas-intensive | Sphinx handles gas management per phase |

## Privileged Roles

| Role | Capabilities | Scope |
|------|-------------|-------|
| Sphinx proposer | Submit deployment proposals | Multi-chain |
| Sphinx safe | Approve and execute deployments | Multi-chain |

## Post-Deployment Verification

After deployment, verify:
1. All contracts deployed to expected addresses
2. Directory correctly routes projects to terminals/controllers
3. Price feeds are live and not stale
4. Sucker deployers are registered
5. Fee project (#1) is correctly configured
