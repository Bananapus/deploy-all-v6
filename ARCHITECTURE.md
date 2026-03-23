# deploy-all-v6 -- Architecture

## Purpose

Master deployment script for the current canonical Juicebox V6 rollout. This repo exists to describe what
`script/Deploy.s.sol` actually deploys today, not every sibling package that exists in the workspace.

## Directory Map

```
script/
└── Deploy.s.sol — Sphinx deployment script (~1,600 lines)
```

There is no `src/` directory. This repo exists solely to orchestrate ecosystem deployment.

## What It Deploys

The script deploys the following production-scoped stack in dependency order:

### Core Protocol
- `JBPermissions`
- `JBProjects`
- `JBPrices`
- `JBRulesets`
- `JBDirectory`
- `JBERC20`
- `JBTokens`
- `JBSplits`
- `JBFeelessAddresses`
- `JBFundAccessLimits`
- `JBController`
- `JBTerminalStore`
- `JBMultiTerminal`
- `ERC2771Forwarder`

### Periphery
- `JBDeadline` variants (3h, 1d, 3d, 7d)
- `JBChainlinkV3PriceFeed` / `JBChainlinkV3SequencerPriceFeed`
- `JBMatchingPriceFeed`
- `JBAddressRegistry`

### Hooks & Extensions
- `JB721TiersHook` + `JB721TiersHookStore` + deployers
- `JBUniswapV4Hook`
- `JBBuybackHook` + `JBBuybackHookRegistry`
- `JBUniswapV4LPSplitHook` + `JBUniswapV4LPSplitHookDeployer`
- `JBRouterTerminal` + `JBRouterTerminalRegistry`

### Cross-Chain
- `JBSuckerRegistry`
- `JBOptimismSuckerDeployer`
- `JBBaseSuckerDeployer`
- `JBArbitrumSuckerDeployer`
- `JBCCIPSuckerDeployer`
- `JBOmnichainDeployer`

### Applications
- `REVDeployer`
- `REVLoans`
- `CTPublisher`
- `CTDeployer`
- `CTProjectOwner`
- `Banny721TokenUriResolver`

## What It Does Not Deploy

The current script does not instantiate:

- `JBOwnable`
- Defifa contracts

## Sphinx Proposal Flow

The script inherits from `Sphinx` and uses the `sphinx` modifier on `deploy()`. At a high level:

1. **Configure** -- `configureSphinx()` registers the project name (`juicebox-v6`) and target chains.
2. **Propose** -- A developer runs `forge script script/Deploy.s.sol` through the Sphinx CLI, which simulates the deployment, computes deterministic CREATE2 addresses, and submits the proposal to the Sphinx platform.
3. **Approve** -- The multisig (`safeAddress()`) reviews the proposal on the Sphinx dashboard and signs it. Sphinx requires the configured Gnosis Safe owners to reach the signing threshold before execution proceeds.
4. **Execute** -- Once approved, Sphinx relays the signed transactions to each target chain. All contract deployments use CREATE2 through the Safe so that addresses are deterministic and identical across chains.

Ownership of deployed contracts (JBProjects, JBDirectory, JBFeelessAddresses, etc.) is assigned to `safeAddress()`, giving the multisig administrative control post-deployment.

## Deployment Order

```
Sphinx proposal → Deploy.deploy()
  Phase 01: Core protocol
  Phase 02: Address registry
  Phase 03a: 721 hook stack
  Phase 03b: Uniswap V4 router hook
  Phase 03c: Buyback hook stack
  Phase 03d: Router terminal stack
  Phase 03e: LP split hook stack
  Phase 03f: Cross-chain suckers
  Phase 04: Omnichain deployer
  Phase 05: Periphery and controller wiring
  Phase 06: Croptop
  Phase 07: REV revnet
  Phase 08: Existing project configuration
  Phase 09: Banny
```

## Deployment Transport Limits

Each chain executes one Sphinx-managed `deploy()` call, but this repo does not yet ship a resumable recovery script.
If execution halts after some CREATE2 deployments succeed, operators must either resume with a purpose-built script
that skips already-deployed contracts or redeploy from fresh salts. Re-proposing the full script with the same salts
is not a safe recovery path.

## Target Chains

- Mainnets: Ethereum, Optimism, Base, Arbitrum
- Testnets: Ethereum Sepolia, Optimism Sepolia, Base Sepolia, Arbitrum Sepolia

Configured addresses exist for the supported chains, but the testnet path is not equally production-ready. On
Optimism Sepolia the canonical core/periphery rollout still deploys, but the Uniswap-dependent phases are skipped
because there is no published Uniswap V4 `PositionManager`.

## Dependencies

### Juicebox V6 Ecosystem

| Package | Role |
|---|---|
| `@bananapus/core-v6` | Core protocol contracts (JBController, JBMultiTerminal, etc.) |
| `@bananapus/permission-ids-v6` | Permission ID constants |
| `@bananapus/address-registry-v6` | JBAddressRegistry |
| `@bananapus/721-hook-v6` | ERC-721 tiered NFT hook |
| `@bananapus/buyback-hook-v6` | Buyback hook and registry |
| `@bananapus/univ4-router-v6` | JBUniswapV4Hook |
| `@bananapus/univ4-lp-split-hook-v6` | LP split hook and deployer |
| `@bananapus/router-terminal-v6` | JBRouterTerminal and registry |
| `@bananapus/suckers-v6` | Cross-chain suckers (OP, Base, Arbitrum, CCIP) |
| `@bananapus/omnichain-deployers-v6` | JBOmnichainDeployer |
| `@bananapus/ownable-v6` | Ownable extension |
| `@rev-net/core-v6` | REVDeployer, REVLoans |
| `@croptop/core-v6` | CTPublisher, CTDeployer, CTProjectOwner |
| `@bannynet/core-v6` | Banny 721 token URI resolver |
| `@ballkidz/defifa` | Defifa (not deployed by this script) |

### Third-Party

| Package | Role |
|---|---|
| `@openzeppelin/contracts` | ERC2771Forwarder, standard utilities |
| `@openzeppelin/uniswap-hooks` | OpenZeppelin Uniswap hook base |
| `@chainlink/contracts` | AggregatorV3Interface for price feeds |
| `@chainlink/contracts-ccip` | CCIP router interfaces for cross-chain suckers |
| `@uniswap/v4-core` | PoolManager interfaces |
| `@uniswap/v4-periphery` | PositionManager, HookMiner |
| `@uniswap/v3-core` | V3 factory interface (router terminal) |
| `@uniswap/v3-periphery` | V3 periphery interfaces |
| `@uniswap/permit2` | Permit2 integration |
| `@prb/math` | Fixed-point math |
| `solady` | Gas-optimized utilities |
| `solmate` | Solmate utilities |
| `@arbitrum/nitro-contracts` | Arbitrum Inbox interface for suckers |
| `base64-sol` | Base64 encoding (transitive dependency) |

### Dev / Tooling

| Package | Role |
|---|---|
| `@sphinx-labs/plugins` | Sphinx deployment framework (proposal, multisig approval, CREATE2 execution) |
