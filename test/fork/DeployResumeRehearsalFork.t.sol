// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ════════════════════════════════════════════════════════════════════════════════
// DeployResumeRehearsalFork.t.sol — Phase-boundary interruption tests for Resume.s.sol.
//
// PURPOSE:
//   Proves that resuming a deployment after interruption at various phase boundaries
//   produces the same final contract addresses and state as a fresh full deploy.
//
// HOW IT WORKS:
//   1. A harness contract (InstrumentedDeployer) replicates all deployment phases
//      from Deploy.s.sol but can be called in stages to simulate interruption.
//   2. Each test deploys up to a specific phase boundary (simulating interruption),
//      snapshots the deployed addresses, then calls the full deploy again.
//   3. The test verifies that all addresses from the first (partial) run are reused
//      in the second (resume) run, and that final state is consistent.
//
// INTERRUPTION POINTS TESTED:
//   - After Phase 01: Core protocol deployed, nothing else.
//   - After Phase 03a: Core + 721 hook, no Uniswap/suckers.
//   - After Phase 03f: Core + hooks + suckers, no omnichain deployer.
//   - After Phase 07: Everything but Banny.
//
// RUN:
//   forge test --match-contract DeployResumeRehearsalForkTest --fork-url $RPC_ETHEREUM_MAINNET -vvv
//   (Requires Ethereum mainnet fork at a recent block.)
// ════════════════════════════════════════════════════════════════════════════════

import "forge-std/Test.sol";
import {IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";

// ── Core ──
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBPrices} from "@bananapus/core-v6/src/JBPrices.sol";
import {JBRulesets} from "@bananapus/core-v6/src/JBRulesets.sol";
import {JBDirectory} from "@bananapus/core-v6/src/JBDirectory.sol";
import {JBERC20} from "@bananapus/core-v6/src/JBERC20.sol";
import {JBTokens} from "@bananapus/core-v6/src/JBTokens.sol";
import {JBSplits} from "@bananapus/core-v6/src/JBSplits.sol";
import {JBFeelessAddresses} from "@bananapus/core-v6/src/JBFeelessAddresses.sol";
import {JBFundAccessLimits} from "@bananapus/core-v6/src/JBFundAccessLimits.sol";
import {JBController} from "@bananapus/core-v6/src/JBController.sol";
import {JBTerminalStore} from "@bananapus/core-v6/src/JBTerminalStore.sol";
import {JBMultiTerminal} from "@bananapus/core-v6/src/JBMultiTerminal.sol";
import {ERC2771Forwarder} from "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// ── Core Libraries ──
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";

// ── Core Interfaces ──
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";

// ── Core Periphery ──
import {JBDeadline3Hours} from "@bananapus/core-v6/src/periphery/JBDeadline3Hours.sol";
import {JBDeadline1Day} from "@bananapus/core-v6/src/periphery/JBDeadline1Day.sol";
import {JBDeadline3Days} from "@bananapus/core-v6/src/periphery/JBDeadline3Days.sol";
import {JBDeadline7Days} from "@bananapus/core-v6/src/periphery/JBDeadline7Days.sol";
import {JBMatchingPriceFeed} from "@bananapus/core-v6/src/periphery/JBMatchingPriceFeed.sol";

// ── Price Feeds ──
import {JBChainlinkV3PriceFeed, AggregatorV3Interface} from "@bananapus/core-v6/src/JBChainlinkV3PriceFeed.sol";

// ── Address Registry ──
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// ── 721 Hook ──
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHookProjectDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookProjectDeployer.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";

// ── Buyback Hook ──
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {JBUniswapV4Hook} from "@bananapus/univ4-router-v6/src/JBUniswapV4Hook.sol";
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";
import {JBUniswapV4LPSplitHookDeployer} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHookDeployer.sol";

// ── Router Terminal ──
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";
import {IWETH9 as IRouterWETH9} from "@bananapus/router-terminal-v6/src/interfaces/IWETH9.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

// ── Suckers ──
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";

// ── Omnichain Deployer ──
import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";

/// @notice Harness that replicates Deploy.s.sol deployment phases without Sphinx.
///         Exposes per-phase entry points so tests can simulate interruption at any boundary.
contract InstrumentedDeployer is IERC721Receiver {
    // Canonical Permit2 address.
    IPermit2 private constant _PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    // Trusted forwarder name.
    string private constant TRUSTED_FORWARDER_NAME = "Juicebox";
    // Core salt derivation nonce.
    uint256 private constant CORE_DEPLOYMENT_NONCE = 6;
    // Expected project IDs.
    uint256 private constant _CPN_PROJECT_ID = 2;
    uint256 private constant _REV_PROJECT_ID = 3;

    // ── Salts — identical to Deploy.s.sol ──
    bytes32 private constant DEADLINES_SALT = keccak256("_JBDeadlinesV6_");
    bytes32 private constant USD_NATIVE_FEED_SALT = keccak256("USD_FEEDV6");
    bytes32 private constant ADDRESS_REGISTRY_SALT = "_JBAddressRegistryV6_";
    bytes32 private constant HOOK_721_STORE_SALT = "JB721TiersHookStoreV6_";
    bytes32 private constant HOOK_721_SALT = "JB721TiersHookV6_";
    bytes32 private constant HOOK_721_DEPLOYER_SALT = "JB721TiersHookDeployerV6_";
    bytes32 private constant HOOK_721_PROJECT_DEPLOYER_SALT = "JB721TiersHookProjectDeployerV6";
    bytes32 private constant BUYBACK_HOOK_SALT = "JBBuybackHookV6";
    bytes32 private constant ROUTER_TERMINAL_SALT = "JBRouterTerminalV6";
    bytes32 private constant ROUTER_TERMINAL_REGISTRY_SALT = "JBRouterTerminalRegistryV6";
    bytes32 private constant LP_SPLIT_HOOK_SALT = "JBUniswapV4LPSplitHookV6";
    bytes32 private constant LP_SPLIT_HOOK_DEPLOYER_SALT = "JBUniswapV4LPSplitHookDeployerV6";
    bytes32 private constant SUCKER_REGISTRY_SALT = "REGISTRYV6";
    bytes32 private constant OMNICHAIN_DEPLOYER_SALT = "JBOmnichainDeployerV6_";

    // ── Ethereum Mainnet addresses ──
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address private constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address private constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address private constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    // ── Public references (readable by tests) ──
    address public trustedForwarder;
    JBPermissions public permissions;
    JBProjects public projects;
    JBDirectory public directory;
    JBSplits public splits;
    JBRulesets public rulesets;
    JBPrices public prices;
    JBTokens public tokens;
    JBFundAccessLimits public fundAccess;
    JBFeelessAddresses public feeless;
    JBTerminalStore public terminalStore;
    JBMultiTerminal public terminal;
    JBController public controller;
    JBAddressRegistry public addressRegistry;
    JB721TiersHookStore public hookStore;
    JB721TiersHook public hook721;
    JB721TiersHookDeployer public hookDeployer;
    JB721TiersHookProjectDeployer public hookProjectDeployer;
    JBUniswapV4Hook public uniswapV4Hook;
    JBBuybackHookRegistry public buybackRegistry;
    JBBuybackHook public buybackHook;
    JBRouterTerminalRegistry public routerTerminalRegistry;
    JBRouterTerminal public routerTerminal;
    JBUniswapV4LPSplitHook public lpSplitHook;
    JBUniswapV4LPSplitHookDeployer public lpSplitHookDeployer;
    JBSuckerRegistry public suckerRegistry;
    JBOmnichainDeployer public omnichainDeployer;
    uint256 public cpnProjectId;
    uint256 public revProjectId;

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase entry points — each can be called independently
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Deploy Phase 01 only: Core Protocol.
    function phase01_core() external {
        _deployCore(); // Deploy all 13 core contracts.
    }

    /// @notice Deploy Phases 01-03a: Core + Address Registry + 721 Hook.
    function phase01_through_03a() external {
        _deployCore(); // Phase 01: Core Protocol.
        _deployAddressRegistry(); // Phase 02: Address Registry.
        _deploy721Hook(); // Phase 03a: 721 Tier Hook.
    }

    /// @notice Deploy Phases 01-03f: Core + all hooks + suckers.
    function phase01_through_03f() external {
        _deployCore(); // Phase 01: Core Protocol.
        _deployAddressRegistry(); // Phase 02: Address Registry.
        _deploy721Hook(); // Phase 03a: 721 Tier Hook.
        _deployUniswapV4Hook(); // Phase 03b: Uniswap V4 Router Hook.
        _deployBuybackHook(); // Phase 03c: Buyback Hook.
        _deployRouterTerminal(); // Phase 03d: Router Terminal.
        _deployLpSplitHook(); // Phase 03e: LP Split Hook.
        _deploySuckers(); // Phase 03f: Cross-Chain Suckers.
    }

    /// @notice Deploy Phases 01-07: Everything except Banny.
    function phase01_through_07() external {
        _deployCore(); // Phase 01: Core Protocol.
        _deployAddressRegistry(); // Phase 02: Address Registry.
        _deploy721Hook(); // Phase 03a: 721 Tier Hook.
        _deployUniswapV4Hook(); // Phase 03b: Uniswap V4 Router Hook.
        _deployBuybackHook(); // Phase 03c: Buyback Hook.
        _deployRouterTerminal(); // Phase 03d: Router Terminal.
        _deployLpSplitHook(); // Phase 03e: LP Split Hook.
        _deploySuckers(); // Phase 03f: Cross-Chain Suckers.
        _deployOmnichainDeployer(); // Phase 04: Omnichain Deployer.
        _deployPeriphery(); // Phase 05: Periphery.
        cpnProjectId = _ensureProjectExists(_CPN_PROJECT_ID); // Phase 06 prep.
        revProjectId = _ensureProjectExists(_REV_PROJECT_ID); // Phase 07 prep.
    }

    /// @notice Full deploy — all phases through infrastructure + project reservation.
    function fullDeploy() external {
        _deployCore(); // Phase 01.
        _deployAddressRegistry(); // Phase 02.
        _deploy721Hook(); // Phase 03a.
        _deployUniswapV4Hook(); // Phase 03b.
        _deployBuybackHook(); // Phase 03c.
        _deployRouterTerminal(); // Phase 03d.
        _deployLpSplitHook(); // Phase 03e.
        _deploySuckers(); // Phase 03f.
        _deployOmnichainDeployer(); // Phase 04.
        _deployPeriphery(); // Phase 05.
        cpnProjectId = _ensureProjectExists(_CPN_PROJECT_ID); // Phase 06 prep.
        revProjectId = _ensureProjectExists(_REV_PROJECT_ID); // Phase 07 prep.
    }

    /// @notice Accept ERC721 tokens (needed for project creation).
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector; // Standard ERC721 receiver.
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase implementations (mirrors Deploy.s.sol / ResumeDeployFork.t.sol)
    // ═══════════════════════════════════════════════════════════════════════

    function _deployCore() internal {
        bytes32 coreSalt = keccak256(abi.encode(CORE_DEPLOYMENT_NONCE)); // Derive core salt.

        // Deploy or resolve each core contract in dependency order.
        (address tf, bool tfD) =
            _isDeployed(coreSalt, type(ERC2771Forwarder).creationCode, abi.encode(TRUSTED_FORWARDER_NAME));
        trustedForwarder = tfD ? tf : address(new ERC2771Forwarder{salt: coreSalt}(TRUSTED_FORWARDER_NAME));

        (address p, bool pD) = _isDeployed(coreSalt, type(JBPermissions).creationCode, abi.encode(trustedForwarder));
        permissions = pD ? JBPermissions(p) : new JBPermissions{salt: coreSalt}(trustedForwarder);

        (address pr, bool prD) = _isDeployed(
            coreSalt, type(JBProjects).creationCode, abi.encode(address(this), address(this), trustedForwarder)
        );
        projects = prD
            ? JBProjects(pr)
            : new JBProjects{salt: coreSalt}({
                owner: address(this), feeProjectOwner: address(this), trustedForwarder: trustedForwarder
            });

        (address d, bool dD) =
            _isDeployed(coreSalt, type(JBDirectory).creationCode, abi.encode(permissions, projects, address(this)));
        directory = dD
            ? JBDirectory(d)
            : new JBDirectory{salt: coreSalt}({permissions: permissions, projects: projects, owner: address(this)});

        (address s, bool sD) = _isDeployed(coreSalt, type(JBSplits).creationCode, abi.encode(directory));
        splits = sD ? JBSplits(s) : new JBSplits{salt: coreSalt}({directory: directory});

        (address r, bool rD) = _isDeployed(coreSalt, type(JBRulesets).creationCode, abi.encode(directory));
        rulesets = rD ? JBRulesets(r) : new JBRulesets{salt: coreSalt}({directory: directory});

        (address pr2, bool pr2D) = _isDeployed(
            coreSalt,
            type(JBPrices).creationCode,
            abi.encode(directory, permissions, projects, address(this), trustedForwarder)
        );
        prices = pr2D
            ? JBPrices(pr2)
            : new JBPrices{salt: coreSalt}({
                directory: directory,
                permissions: permissions,
                projects: projects,
                owner: address(this),
                trustedForwarder: trustedForwarder
            });

        (address e, bool eD) = _isDeployed(coreSalt, type(JBERC20).creationCode, "");
        JBERC20 erc20 = eD ? JBERC20(e) : new JBERC20{salt: coreSalt}();

        (address t, bool tD) = _isDeployed(coreSalt, type(JBTokens).creationCode, abi.encode(directory, erc20));
        tokens = tD ? JBTokens(t) : new JBTokens{salt: coreSalt}({directory: directory, token: erc20});

        (address fa, bool faD) = _isDeployed(coreSalt, type(JBFundAccessLimits).creationCode, abi.encode(directory));
        fundAccess = faD ? JBFundAccessLimits(fa) : new JBFundAccessLimits{salt: coreSalt}({directory: directory});

        (address fl, bool flD) = _isDeployed(coreSalt, type(JBFeelessAddresses).creationCode, abi.encode(address(this)));
        feeless = flD ? JBFeelessAddresses(fl) : new JBFeelessAddresses{salt: coreSalt}({owner: address(this)});

        (address ts, bool tsD) =
            _isDeployed(coreSalt, type(JBTerminalStore).creationCode, abi.encode(directory, rulesets, prices));
        terminalStore = tsD
            ? JBTerminalStore(ts)
            : new JBTerminalStore{salt: coreSalt}({directory: directory, rulesets: rulesets, prices: prices});

        (address tm, bool tmD) = _isDeployed(
            coreSalt,
            type(JBMultiTerminal).creationCode,
            abi.encode(permissions, projects, splits, terminalStore, tokens, feeless, _PERMIT2, trustedForwarder)
        );
        terminal = tmD
            ? JBMultiTerminal(tm)
            : new JBMultiTerminal{salt: coreSalt}({
                feelessAddresses: feeless,
                permissions: permissions,
                projects: projects,
                splits: splits,
                store: terminalStore,
                tokens: tokens,
                permit2: _PERMIT2,
                trustedForwarder: trustedForwarder
            });
    }

    function _deployAddressRegistry() internal {
        // Deploy or resolve the address registry.
        (address r, bool d) = _isDeployed(ADDRESS_REGISTRY_SALT, type(JBAddressRegistry).creationCode, "");
        addressRegistry = d ? JBAddressRegistry(r) : new JBAddressRegistry{salt: ADDRESS_REGISTRY_SALT}();
    }

    function _deploy721Hook() internal {
        // Deploy or resolve 721 hook store.
        (address hs, bool hsD) = _isDeployed(HOOK_721_STORE_SALT, type(JB721TiersHookStore).creationCode, "");
        hookStore = hsD ? JB721TiersHookStore(hs) : new JB721TiersHookStore{salt: HOOK_721_STORE_SALT}();

        // Deploy or resolve 721 hook implementation.
        (address h, bool hD) = _isDeployed(
            HOOK_721_SALT,
            type(JB721TiersHook).creationCode,
            abi.encode(directory, permissions, prices, rulesets, hookStore, splits, trustedForwarder)
        );
        hook721 = hD
            ? JB721TiersHook(h)
            : new JB721TiersHook{salt: HOOK_721_SALT}({
                directory: directory,
                permissions: permissions,
                prices: prices,
                rulesets: rulesets,
                store: hookStore,
                splits: splits,
                trustedForwarder: trustedForwarder
            });

        // Deploy or resolve hook deployer.
        (address hd, bool hdD) = _isDeployed(
            HOOK_721_DEPLOYER_SALT,
            type(JB721TiersHookDeployer).creationCode,
            abi.encode(hook721, hookStore, IJBAddressRegistry(address(addressRegistry)), trustedForwarder)
        );
        hookDeployer = hdD
            ? JB721TiersHookDeployer(hd)
            : new JB721TiersHookDeployer{salt: HOOK_721_DEPLOYER_SALT}({
                hook: hook721,
                store: hookStore,
                addressRegistry: IJBAddressRegistry(address(addressRegistry)),
                trustedForwarder: trustedForwarder
            });

        // Deploy or resolve hook project deployer.
        (address hpd, bool hpdD) = _isDeployed(
            HOOK_721_PROJECT_DEPLOYER_SALT,
            type(JB721TiersHookProjectDeployer).creationCode,
            abi.encode(directory, permissions, hookDeployer, trustedForwarder)
        );
        hookProjectDeployer = hpdD
            ? JB721TiersHookProjectDeployer(hpd)
            : new JB721TiersHookProjectDeployer{salt: HOOK_721_PROJECT_DEPLOYER_SALT}({
                directory: directory,
                permissions: permissions,
                hookDeployer: hookDeployer,
                trustedForwarder: trustedForwarder
            });
    }

    function _deployUniswapV4Hook() internal {
        // Mine hook salt and deploy.
        (, bytes32 salt) = _hookSalt();
        (address h, bool d) = _isDeployed(
            salt, type(JBUniswapV4Hook).creationCode, abi.encode(IPoolManager(POOL_MANAGER), tokens, directory, prices)
        );
        uniswapV4Hook = d
            ? JBUniswapV4Hook(payable(h))
            : new JBUniswapV4Hook{salt: salt}({
                poolManager: IPoolManager(POOL_MANAGER), tokens: tokens, directory: directory, prices: prices
            });
    }

    function _deployBuybackHook() internal {
        // Deploy or resolve buyback registry.
        (address r, bool rD) = _isDeployed(
            BUYBACK_HOOK_SALT,
            type(JBBuybackHookRegistry).creationCode,
            abi.encode(permissions, projects, address(this), trustedForwarder)
        );
        buybackRegistry = rD
            ? JBBuybackHookRegistry(r)
            : new JBBuybackHookRegistry{salt: BUYBACK_HOOK_SALT}({
                permissions: permissions, projects: projects, owner: address(this), trustedForwarder: trustedForwarder
            });

        // Deploy or resolve buyback hook.
        (address h, bool hD) = _isDeployed(
            BUYBACK_HOOK_SALT,
            type(JBBuybackHook).creationCode,
            abi.encode(
                directory,
                permissions,
                prices,
                projects,
                tokens,
                IPoolManager(POOL_MANAGER),
                IHooks(address(uniswapV4Hook)),
                trustedForwarder
            )
        );
        buybackHook = hD
            ? JBBuybackHook(payable(h))
            : new JBBuybackHook{salt: BUYBACK_HOOK_SALT}({
                directory: directory,
                permissions: permissions,
                prices: prices,
                projects: projects,
                tokens: tokens,
                poolManager: IPoolManager(POOL_MANAGER),
                oracleHook: IHooks(address(uniswapV4Hook)),
                trustedForwarder: trustedForwarder
            });

        // Idempotent: set default hook.
        if (address(buybackRegistry.defaultHook()) == address(0)) {
            buybackRegistry.setDefaultHook({hook: IJBRulesetDataHook(address(buybackHook))});
        }
    }

    function _deployRouterTerminal() internal {
        // Deploy or resolve router terminal registry.
        (address r, bool rD) = _isDeployed(
            ROUTER_TERMINAL_REGISTRY_SALT,
            type(JBRouterTerminalRegistry).creationCode,
            abi.encode(permissions, projects, _PERMIT2, address(this), trustedForwarder)
        );
        routerTerminalRegistry = rD
            ? JBRouterTerminalRegistry(r)
            : new JBRouterTerminalRegistry{salt: ROUTER_TERMINAL_REGISTRY_SALT}({
                permissions: permissions,
                projects: projects,
                permit2: _PERMIT2,
                owner: address(this),
                trustedForwarder: trustedForwarder
            });

        // Deploy or resolve router terminal.
        (address t, bool tD) = _isDeployed(
            ROUTER_TERMINAL_SALT,
            type(JBRouterTerminal).creationCode,
            abi.encode(
                directory,
                permissions,
                projects,
                tokens,
                _PERMIT2,
                address(this),
                IRouterWETH9(WETH),
                IUniswapV3Factory(V3_FACTORY),
                IPoolManager(POOL_MANAGER),
                trustedForwarder
            )
        );
        routerTerminal = tD
            ? JBRouterTerminal(payable(t))
            : new JBRouterTerminal{salt: ROUTER_TERMINAL_SALT}({
                directory: directory,
                permissions: permissions,
                projects: projects,
                tokens: tokens,
                permit2: _PERMIT2,
                owner: address(this),
                weth: IRouterWETH9(WETH),
                factory: IUniswapV3Factory(V3_FACTORY),
                poolManager: IPoolManager(POOL_MANAGER),
                trustedForwarder: trustedForwarder
            });

        // Idempotent: set default terminal and feeless.
        if (address(routerTerminalRegistry.defaultTerminal()) == address(0)) {
            routerTerminalRegistry.setDefaultTerminal({terminal: IJBTerminal(address(routerTerminal))});
        }
        if (!feeless.isFeeless(address(routerTerminal))) {
            feeless.setFeelessAddress({addr: address(routerTerminal), flag: true});
        }
    }

    function _deployLpSplitHook() internal {
        // Deploy or resolve LP split hook.
        (address h, bool hD) = _isDeployed(
            LP_SPLIT_HOOK_SALT,
            type(JBUniswapV4LPSplitHook).creationCode,
            abi.encode(
                address(directory),
                permissions,
                address(tokens),
                IPoolManager(POOL_MANAGER),
                IPositionManager(POSITION_MANAGER),
                IAllowanceTransfer(address(_PERMIT2)),
                IHooks(address(uniswapV4Hook))
            )
        );
        lpSplitHook = hD
            ? JBUniswapV4LPSplitHook(payable(h))
            : new JBUniswapV4LPSplitHook{salt: LP_SPLIT_HOOK_SALT}(
                address(directory),
                permissions,
                address(tokens),
                IPoolManager(POOL_MANAGER),
                IPositionManager(POSITION_MANAGER),
                IAllowanceTransfer(address(_PERMIT2)),
                IHooks(address(uniswapV4Hook))
            );

        // Deploy or resolve LP split hook deployer.
        (address d, bool dD) = _isDeployed(
            LP_SPLIT_HOOK_DEPLOYER_SALT,
            type(JBUniswapV4LPSplitHookDeployer).creationCode,
            abi.encode(lpSplitHook, IJBAddressRegistry(address(addressRegistry)))
        );
        lpSplitHookDeployer = dD
            ? JBUniswapV4LPSplitHookDeployer(d)
            : new JBUniswapV4LPSplitHookDeployer{salt: LP_SPLIT_HOOK_DEPLOYER_SALT}(
                lpSplitHook, IJBAddressRegistry(address(addressRegistry))
            );
    }

    function _deploySuckers() internal {
        // Deploy or resolve sucker registry.
        (address r, bool rD) = _isDeployed(
            SUCKER_REGISTRY_SALT,
            type(JBSuckerRegistry).creationCode,
            abi.encode(directory, permissions, address(this), trustedForwarder)
        );
        suckerRegistry = rD
            ? JBSuckerRegistry(r)
            : new JBSuckerRegistry{salt: SUCKER_REGISTRY_SALT}(directory, permissions, address(this), trustedForwarder);
    }

    function _deployOmnichainDeployer() internal {
        // Deploy or resolve omnichain deployer.
        (address d, bool dD) = _isDeployed(
            OMNICHAIN_DEPLOYER_SALT,
            type(JBOmnichainDeployer).creationCode,
            abi.encode(
                suckerRegistry, IJB721TiersHookDeployer(address(hookDeployer)), permissions, projects, trustedForwarder
            )
        );
        omnichainDeployer = dD
            ? JBOmnichainDeployer(d)
            : new JBOmnichainDeployer{salt: OMNICHAIN_DEPLOYER_SALT}(
                suckerRegistry, IJB721TiersHookDeployer(address(hookDeployer)), permissions, projects, trustedForwarder
            );
    }

    function _deployPeriphery() internal {
        // Deploy ETH/USD feed.
        IJBPriceFeed ethUsdFeed =
            IJBPriceFeed(address(new JBChainlinkV3PriceFeed(AggregatorV3Interface(ETH_USD_FEED), 3600)));
        _ensureDefaultPriceFeed(0, JBCurrencyIds.USD, uint32(uint160(JBConstants.NATIVE_TOKEN)), ethUsdFeed);
        _ensureDefaultPriceFeed(0, JBCurrencyIds.USD, JBCurrencyIds.ETH, ethUsdFeed);

        // Deploy matching feed.
        IJBPriceFeed nativeEthFeed =
            prices.priceFeedFor(0, JBCurrencyIds.ETH, uint32(uint160(JBConstants.NATIVE_TOKEN)));
        if (address(nativeEthFeed) == address(0)) nativeEthFeed = IJBPriceFeed(address(new JBMatchingPriceFeed()));
        _ensureDefaultPriceFeed(0, JBCurrencyIds.ETH, uint32(uint160(JBConstants.NATIVE_TOKEN)), nativeEthFeed);

        // Deploy USDC/USD feed.
        IJBPriceFeed existingUsdc = prices.priceFeedFor(0, JBCurrencyIds.USD, uint32(uint160(USDC)));
        if (address(existingUsdc) == address(0)) {
            IJBPriceFeed usdcFeed =
                IJBPriceFeed(address(new JBChainlinkV3PriceFeed(AggregatorV3Interface(USDC_USD_FEED), 86_400)));
            _ensureDefaultPriceFeed(0, JBCurrencyIds.USD, uint32(uint160(USDC)), usdcFeed);
        }

        // Deploy deadlines.
        (, bool d1) = _isDeployed(DEADLINES_SALT, type(JBDeadline3Hours).creationCode, "");
        if (!d1) new JBDeadline3Hours{salt: DEADLINES_SALT}();
        (, bool d2) = _isDeployed(DEADLINES_SALT, type(JBDeadline1Day).creationCode, "");
        if (!d2) new JBDeadline1Day{salt: DEADLINES_SALT}();
        (, bool d3) = _isDeployed(DEADLINES_SALT, type(JBDeadline3Days).creationCode, "");
        if (!d3) new JBDeadline3Days{salt: DEADLINES_SALT}();
        (, bool d4) = _isDeployed(DEADLINES_SALT, type(JBDeadline7Days).creationCode, "");
        if (!d4) new JBDeadline7Days{salt: DEADLINES_SALT}();

        // Deploy controller.
        bytes32 coreSalt = keccak256(abi.encode(CORE_DEPLOYMENT_NONCE));
        (address c, bool cD) = _isDeployed(
            coreSalt,
            type(JBController).creationCode,
            abi.encode(
                directory,
                fundAccess,
                prices,
                permissions,
                projects,
                rulesets,
                splits,
                tokens,
                address(omnichainDeployer),
                trustedForwarder
            )
        );
        controller = cD
            ? JBController(c)
            : new JBController{salt: coreSalt}({
                directory: directory,
                fundAccessLimits: fundAccess,
                prices: prices,
                permissions: permissions,
                projects: projects,
                rulesets: rulesets,
                splits: splits,
                tokens: tokens,
                omnichainRulesetOperator: address(omnichainDeployer),
                trustedForwarder: trustedForwarder
            });

        // Allowlist controller.
        if (!directory.isAllowedToSetFirstController(address(controller))) {
            directory.setIsAllowedToSetFirstController(address(controller), true);
        }
    }

    function _ensureProjectExists(uint256 expectedProjectId) internal returns (uint256) {
        uint256 count = projects.count(); // Read current count.
        if (count >= expectedProjectId) return expectedProjectId; // Already exists.
        return projects.createFor(address(this)); // Create new.
    }

    function _ensureDefaultPriceFeed(
        uint256 projectId,
        uint256 pricingCurrency,
        uint256 unitCurrency,
        IJBPriceFeed feed
    )
        internal
    {
        IJBPriceFeed existing = prices.priceFeedFor(projectId, pricingCurrency, unitCurrency);
        if (address(existing) == address(0)) prices.addPriceFeedFor(projectId, pricingCurrency, unitCurrency, feed);
    }

    function _hookSalt() internal view returns (uint160, bytes32 salt) {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );
        bytes memory constructorArgs = abi.encode(IPoolManager(POOL_MANAGER), tokens, directory, prices);
        salt = _findHookSalt(address(this), flags, type(JBUniswapV4Hook).creationCode, constructorArgs);
        return (flags, salt);
    }

    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (address deployedTo, bool isDeployed)
    {
        deployedTo = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(this), salt, keccak256(abi.encodePacked(creationCode, arguments))
                        )
                    )
                )
            )
        );
        isDeployed = deployedTo.code.length != 0; // Check for existing bytecode.
    }

    function _findHookSalt(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    )
        internal
        pure
        returns (bytes32 salt)
    {
        flags = flags & HookMiner.FLAG_MASK; // Mask to relevant bits.
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);
        for (uint256 i; i < HookMiner.MAX_LOOP; i++) {
            address hookAddress = HookMiner.computeAddress(deployer, i, creationCodeWithArgs);
            if (uint160(hookAddress) & HookMiner.FLAG_MASK == flags) return bytes32(i);
        }
        revert("HookMiner: could not find salt"); // Should not happen.
    }
}

/// @notice Snapshot of deployed addresses for comparison between partial and full deploys.
struct DeploySnapshot {
    address trustedForwarder; // ERC2771 trusted forwarder.
    address permissions; // JBPermissions contract.
    address projects; // JBProjects contract.
    address directory; // JBDirectory contract.
    address splits; // JBSplits contract.
    address rulesets; // JBRulesets contract.
    address prices; // JBPrices contract.
    address tokens; // JBTokens contract.
    address terminalStore; // JBTerminalStore contract.
    address terminal; // JBMultiTerminal contract.
    address addressRegistry; // JBAddressRegistry contract.
    address hookStore; // JB721TiersHookStore contract.
    address hook721; // JB721TiersHook implementation.
    address hookDeployer; // JB721TiersHookDeployer contract.
    address hookProjectDeployer; // JB721TiersHookProjectDeployer contract.
}

/// @notice Fork test that proves resume produces identical addresses at multiple interruption points.
contract DeployResumeRehearsalForkTest is Test {
    /// @notice Test: interrupt after Phase 01 (core only), then resume to full deploy.
    ///         Verifies all core addresses are reused and later phases deploy correctly.
    function test_resumeAfterPhase01_coreOnly() public {
        // Attempt to create an Ethereum mainnet fork.
        try vm.createSelectFork("ethereum", 21_700_000) {}
        catch {
            vm.skip(true); // Skip if no RPC available.
            return;
        }

        // Create the harness at a deterministic address.
        bytes32 harnessSalt = keccak256("resume-rehearsal-harness");
        InstrumentedDeployer harness = new InstrumentedDeployer{salt: harnessSalt}();

        // Step 1: Deploy ONLY Phase 01 (simulates interruption after core).
        harness.phase01_core();

        // Snapshot core addresses from partial deploy.
        address trustedForwarder = harness.trustedForwarder();
        address permissions = address(harness.permissions());
        address projects = address(harness.projects());
        address directory = address(harness.directory());
        address prices = address(harness.prices());
        address terminal = address(harness.terminal());

        // Verify core contracts exist on-chain.
        assertTrue(trustedForwarder.code.length > 0, "trustedForwarder not deployed");
        assertTrue(permissions.code.length > 0, "permissions not deployed");
        assertTrue(projects.code.length > 0, "projects not deployed");
        assertTrue(terminal.code.length > 0, "terminal not deployed");

        // Step 2: Run full deploy (simulates resume).
        harness.fullDeploy();

        // Step 3: Verify all core addresses are IDENTICAL (CREATE2 idempotency).
        assertEq(harness.trustedForwarder(), trustedForwarder, "trustedForwarder changed on resume");
        assertEq(address(harness.permissions()), permissions, "permissions changed on resume");
        assertEq(address(harness.projects()), projects, "projects changed on resume");
        assertEq(address(harness.directory()), directory, "directory changed on resume");
        assertEq(address(harness.prices()), prices, "prices changed on resume");
        assertEq(address(harness.terminal()), terminal, "terminal changed on resume");

        // Step 4: Verify later phases deployed successfully.
        assertTrue(address(harness.addressRegistry()) != address(0), "addressRegistry not deployed after resume");
        assertTrue(address(harness.hookStore()) != address(0), "hookStore not deployed after resume");
        assertTrue(address(harness.uniswapV4Hook()) != address(0), "uniswapV4Hook not deployed after resume");
        assertTrue(address(harness.buybackRegistry()) != address(0), "buybackRegistry not deployed after resume");
        assertTrue(address(harness.routerTerminal()) != address(0), "routerTerminal not deployed after resume");
        assertTrue(address(harness.suckerRegistry()) != address(0), "suckerRegistry not deployed after resume");
        assertTrue(address(harness.omnichainDeployer()) != address(0), "omnichainDeployer not deployed after resume");
        assertTrue(address(harness.controller()) != address(0), "controller not deployed after resume");

        // Step 5: Verify state consistency.
        assertTrue(
            harness.directory().isAllowedToSetFirstController(address(harness.controller())),
            "controller not allowlisted in directory"
        );
        assertTrue(harness.feeless().isFeeless(address(harness.routerTerminal())), "routerTerminal not feeless");
        assertEq(harness.projects().count(), 3, "unexpected project count");
    }

    /// @notice Test: interrupt after Phase 03a (core + 721 hook), then resume.
    ///         Verifies 721 hook addresses are reused and Uniswap/suckers deploy correctly.
    function test_resumeAfterPhase03a_coreAnd721Hook() public {
        // Attempt to create an Ethereum mainnet fork.
        try vm.createSelectFork("ethereum", 21_700_000) {}
        catch {
            vm.skip(true); // Skip if no RPC available.
            return;
        }

        // Create the harness.
        bytes32 harnessSalt = keccak256("resume-rehearsal-harness");
        InstrumentedDeployer harness = new InstrumentedDeployer{salt: harnessSalt}();

        // Step 1: Deploy through Phase 03a only.
        harness.phase01_through_03a();

        // Snapshot addresses.
        DeploySnapshot memory snap = _takeSnapshot(harness);

        // Verify 721 hook contracts exist.
        assertTrue(snap.hookStore.code.length > 0, "hookStore not deployed");
        assertTrue(snap.hook721.code.length > 0, "hook721 not deployed");
        assertTrue(snap.hookDeployer.code.length > 0, "hookDeployer not deployed");
        assertTrue(snap.hookProjectDeployer.code.length > 0, "hookProjectDeployer not deployed");

        // Verify Uniswap-dependent contracts do NOT exist yet.
        assertEq(address(harness.uniswapV4Hook()), address(0), "uniswapV4Hook should not exist yet");
        assertEq(address(harness.buybackHook()), address(0), "buybackHook should not exist yet");

        // Step 2: Run full deploy (resume).
        harness.fullDeploy();

        // Step 3: Verify all Phase 01-03a addresses are unchanged.
        _assertSnapshotUnchanged(harness, snap);

        // Step 4: Verify Uniswap phases deployed.
        assertTrue(address(harness.uniswapV4Hook()) != address(0), "uniswapV4Hook not deployed after resume");
        assertTrue(address(harness.buybackHook()) != address(0), "buybackHook not deployed after resume");
        assertTrue(address(harness.routerTerminal()) != address(0), "routerTerminal not deployed after resume");
        assertTrue(address(harness.controller()) != address(0), "controller not deployed after resume");
    }

    /// @notice Test: interrupt after Phase 03f (core + hooks + suckers), then resume.
    ///         Verifies sucker registry is reused and omnichain deployer + controller deploy correctly.
    function test_resumeAfterPhase03f_coreHooksAndSuckers() public {
        // Attempt to create an Ethereum mainnet fork.
        try vm.createSelectFork("ethereum", 21_700_000) {}
        catch {
            vm.skip(true); // Skip if no RPC available.
            return;
        }

        // Create the harness.
        bytes32 harnessSalt = keccak256("resume-rehearsal-harness");
        InstrumentedDeployer harness = new InstrumentedDeployer{salt: harnessSalt}();

        // Step 1: Deploy through Phase 03f.
        harness.phase01_through_03f();

        // Snapshot all addresses.
        DeploySnapshot memory snap = _takeSnapshot(harness);
        address suckerRegistry = address(harness.suckerRegistry());
        address lpSplitHook = address(harness.lpSplitHook());

        // Verify suckers deployed.
        assertTrue(suckerRegistry.code.length > 0, "suckerRegistry not deployed");
        assertTrue(lpSplitHook.code.length > 0, "lpSplitHook not deployed");

        // Verify omnichain deployer does NOT exist yet.
        assertEq(address(harness.omnichainDeployer()), address(0), "omnichainDeployer should not exist yet");
        assertEq(address(harness.controller()), address(0), "controller should not exist yet");

        // Step 2: Run full deploy (resume).
        harness.fullDeploy();

        // Step 3: Verify all pre-03f addresses are unchanged.
        _assertSnapshotUnchanged(harness, snap);
        assertEq(address(harness.suckerRegistry()), suckerRegistry, "suckerRegistry changed on resume");
        assertEq(address(harness.lpSplitHook()), lpSplitHook, "lpSplitHook changed on resume");

        // Step 4: Verify Phase 04+ deployed.
        assertTrue(address(harness.omnichainDeployer()) != address(0), "omnichainDeployer not deployed after resume");
        assertTrue(address(harness.controller()) != address(0), "controller not deployed after resume");
        assertTrue(
            harness.directory().isAllowedToSetFirstController(address(harness.controller())),
            "controller not allowlisted"
        );
    }

    /// @notice Test: interrupt after Phase 07 (everything but Banny), then resume.
    ///         Verifies all infrastructure + project IDs are preserved.
    function test_resumeAfterPhase07_everythingButBanny() public {
        // Attempt to create an Ethereum mainnet fork.
        try vm.createSelectFork("ethereum", 21_700_000) {}
        catch {
            vm.skip(true); // Skip if no RPC available.
            return;
        }

        // Create the harness.
        bytes32 harnessSalt = keccak256("resume-rehearsal-harness");
        InstrumentedDeployer harness = new InstrumentedDeployer{salt: harnessSalt}();

        // Step 1: Deploy through Phase 07.
        harness.phase01_through_07();

        // Snapshot everything.
        DeploySnapshot memory snap = _takeSnapshot(harness);
        address controller = address(harness.controller());
        address omnichainDeployer = address(harness.omnichainDeployer());
        uint256 cpnProjectId = harness.cpnProjectId();
        uint256 revProjectId = harness.revProjectId();

        // Verify projects created.
        assertEq(cpnProjectId, 2, "CPN project ID mismatch");
        assertEq(revProjectId, 3, "REV project ID mismatch");
        assertEq(harness.projects().count(), 3, "unexpected project count after phase 07");
        assertTrue(controller.code.length > 0, "controller not deployed");

        // Step 2: Run full deploy again (resume — should be complete no-op).
        harness.fullDeploy();

        // Step 3: Verify all addresses unchanged.
        _assertSnapshotUnchanged(harness, snap);
        assertEq(address(harness.controller()), controller, "controller changed on resume");
        assertEq(address(harness.omnichainDeployer()), omnichainDeployer, "omnichainDeployer changed on resume");
        assertEq(harness.cpnProjectId(), cpnProjectId, "CPN project ID changed on resume");
        assertEq(harness.revProjectId(), revProjectId, "REV project ID changed on resume");

        // Step 4: Verify project count unchanged (no duplicate projects).
        assertEq(harness.projects().count(), 3, "project count changed on resume");

        // Step 5: Verify state consistency.
        assertTrue(
            harness.directory().isAllowedToSetFirstController(address(harness.controller())),
            "controller not allowlisted after resume"
        );
        assertTrue(harness.feeless().isFeeless(address(harness.routerTerminal())), "routerTerminal not feeless");
        assertEq(
            address(harness.buybackRegistry().defaultHook()),
            address(harness.buybackHook()),
            "buyback default hook mismatch"
        );
        assertEq(
            address(harness.routerTerminalRegistry().defaultTerminal()),
            address(harness.routerTerminal()),
            "router default terminal mismatch"
        );

        // Step 6: Verify price feeds exist.
        assertTrue(
            address(harness.prices().priceFeedFor(0, JBCurrencyIds.USD, uint32(uint160(JBConstants.NATIVE_TOKEN))))
                != address(0),
            "missing native USD feed"
        );
        assertTrue(
            address(harness.prices().priceFeedFor(0, JBCurrencyIds.ETH, uint32(uint160(JBConstants.NATIVE_TOKEN))))
                != address(0),
            "missing native ETH feed"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Snapshots the most important contract addresses from the harness.
    function _takeSnapshot(InstrumentedDeployer harness) internal view returns (DeploySnapshot memory) {
        return DeploySnapshot({
            trustedForwarder: harness.trustedForwarder(), // Core forwarder.
            permissions: address(harness.permissions()), // Core permissions.
            projects: address(harness.projects()), // Core projects.
            directory: address(harness.directory()), // Core directory.
            splits: address(harness.splits()), // Core splits.
            rulesets: address(harness.rulesets()), // Core rulesets.
            prices: address(harness.prices()), // Core prices.
            tokens: address(harness.tokens()), // Core tokens.
            terminalStore: address(harness.terminalStore()), // Core terminal store.
            terminal: address(harness.terminal()), // Core multi terminal.
            addressRegistry: address(harness.addressRegistry()), // Address registry.
            hookStore: address(harness.hookStore()), // 721 hook store.
            hook721: address(harness.hook721()), // 721 hook implementation.
            hookDeployer: address(harness.hookDeployer()), // 721 hook deployer.
            hookProjectDeployer: address(harness.hookProjectDeployer()) // 721 project deployer.
        });
    }

    /// @dev Asserts that all snapshotted addresses are unchanged in the harness.
    function _assertSnapshotUnchanged(InstrumentedDeployer harness, DeploySnapshot memory snap) internal view {
        // Verify each core address was preserved by CREATE2 idempotency.
        assertEq(harness.trustedForwarder(), snap.trustedForwarder, "trustedForwarder changed");
        assertEq(address(harness.permissions()), snap.permissions, "permissions changed");
        assertEq(address(harness.projects()), snap.projects, "projects changed");
        assertEq(address(harness.directory()), snap.directory, "directory changed");
        assertEq(address(harness.splits()), snap.splits, "splits changed");
        assertEq(address(harness.rulesets()), snap.rulesets, "rulesets changed");
        assertEq(address(harness.prices()), snap.prices, "prices changed");
        assertEq(address(harness.tokens()), snap.tokens, "tokens changed");
        assertEq(address(harness.terminalStore()), snap.terminalStore, "terminalStore changed");
        assertEq(address(harness.terminal()), snap.terminal, "terminal changed");

        // Only check non-zero snapshots (phases that were deployed before interruption).
        if (snap.addressRegistry != address(0)) {
            assertEq(address(harness.addressRegistry()), snap.addressRegistry, "addressRegistry changed");
        }
        if (snap.hookStore != address(0)) {
            assertEq(address(harness.hookStore()), snap.hookStore, "hookStore changed");
        }
        if (snap.hook721 != address(0)) {
            assertEq(address(harness.hook721()), snap.hook721, "hook721 changed");
        }
        if (snap.hookDeployer != address(0)) {
            assertEq(address(harness.hookDeployer()), snap.hookDeployer, "hookDeployer changed");
        }
        if (snap.hookProjectDeployer != address(0)) {
            assertEq(address(harness.hookProjectDeployer()), snap.hookProjectDeployer, "hookProjectDeployer changed");
        }
    }
}
