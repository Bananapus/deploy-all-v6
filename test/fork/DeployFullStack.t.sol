// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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

// ── Core Libraries ──
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";

// ── Core Interfaces ──
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";

// ── Core Periphery ──
import {JBDeadline3Hours} from "@bananapus/core-v6/src/periphery/JBDeadline3Hours.sol";
import {JBDeadline1Day} from "@bananapus/core-v6/src/periphery/JBDeadline1Day.sol";
import {JBDeadline3Days} from "@bananapus/core-v6/src/periphery/JBDeadline3Days.sol";
import {JBDeadline7Days} from "@bananapus/core-v6/src/periphery/JBDeadline7Days.sol";
import {JBMatchingPriceFeed} from "@bananapus/core-v6/src/periphery/JBMatchingPriceFeed.sol";

// ── Price Feeds ──
import {JBChainlinkV3PriceFeed, AggregatorV3Interface} from "@bananapus/core-v6/src/JBChainlinkV3PriceFeed.sol";
import {JBChainlinkV3SequencerPriceFeed} from "@bananapus/core-v6/src/JBChainlinkV3SequencerPriceFeed.sol";
import {AggregatorV2V3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";

// ── Address Registry ──
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// ── 721 Hook ──
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHookProjectDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookProjectDeployer.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {JB721CheckpointsDeployer} from "@bananapus/721-hook-v6/src/JB721CheckpointsDeployer.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";

// ── Buyback Hook ──
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
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
import {IWETH9} from "@bananapus/router-terminal-v6/src/interfaces/IWETH9.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

// ── Suckers ──
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {JBOptimismSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBOptimismSuckerDeployer.sol";
import {JBBaseSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBBaseSuckerDeployer.sol";
import {JBArbitrumSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBArbitrumSuckerDeployer.sol";
import {JBCCIPSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBCCIPSuckerDeployer.sol";
import {JBOptimismSucker} from "@bananapus/suckers-v6/src/JBOptimismSucker.sol";
import {JBBaseSucker} from "@bananapus/suckers-v6/src/JBBaseSucker.sol";
import {JBArbitrumSucker} from "@bananapus/suckers-v6/src/JBArbitrumSucker.sol";
import {JBCCIPSucker} from "@bananapus/suckers-v6/src/JBCCIPSucker.sol";
import {JBLayer} from "@bananapus/suckers-v6/src/enums/JBLayer.sol";
import {IJBSuckerDeployer} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerDeployer.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {IArbGatewayRouter} from "@bananapus/suckers-v6/src/interfaces/IArbGatewayRouter.sol";
import {ICCIPRouter} from "@bananapus/suckers-v6/src/interfaces/ICCIPRouter.sol";
import {IOPMessenger} from "@bananapus/suckers-v6/src/interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "@bananapus/suckers-v6/src/interfaces/IOPStandardBridge.sol";
import {ARBAddresses} from "@bananapus/suckers-v6/src/libraries/ARBAddresses.sol";
import {CCIPHelper} from "@bananapus/suckers-v6/src/libraries/CCIPHelper.sol";

// ── Omnichain Deployer ──
import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";

/// @notice Full-stack fork test that exercises the entire deployment pipeline on each supported chain.
///
/// The actual Deploy.s.sol is gated by the Sphinx `sphinx` modifier and requires Gnosis Safe
/// infrastructure. This test bypasses Sphinx by directly replicating the deployment phases in the
/// same order as Deploy.deploy(), calling them for each supported mainnet chain.
///
/// For each chain the test:
///   1. Creates a fork at a recent block
///   2. Deploys Phase 01 (Core Protocol) through Phase 05 (Periphery / Controller)
///   3. Asserts project #1 exists (via JBProjects.ownerOf(1))
///   4. Asserts all key contracts are deployed and wired correctly
///   5. Asserts price feeds return reasonable values
///
/// Phases 06-09 (Croptop, Revnet, CPN/NANA revnets, Banny) are not exercised here because they
/// depend on project-specific operators and complex multi-chain revnet configs. The infrastructure
/// phases (01-05) are the critical deployment correctness check.
///
/// Run with: forge test --match-contract DeployFullStackTest -vvv
///
/// Required environment variables for each chain (skip if not set):
///   RPC_ETHEREUM_MAINNET  (also available as foundry.toml alias "ethereum")
///   RPC_OPTIMISM_MAINNET
///   RPC_BASE_MAINNET
///   RPC_ARBITRUM_MAINNET
contract DeployFullStackTest is Test {
    // ════════════════════════════════════════════════════════════════════
    //  Constants (must match Deploy.s.sol)
    // ════════════════════════════════════════════════════════════════════

    IPermit2 private constant _PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    uint256 private constant FEE_PROJECT_ID = 1;

    // ════════════════════════════════════════════════════════════════════
    //  Chain configs
    // ════════════════════════════════════════════════════════════════════

    struct ChainConfig {
        string name;
        string rpcEnvVar;
        string rpcAlias;
        uint256 chainId;
        uint256 forkBlock;
        // Chain-specific addresses
        address weth;
        address v3Factory;
        address poolManager;
        address positionManager;
        // ETH/USD Chainlink feed
        address ethUsdFeed;
        // Sequencer feed (address(0) on L1 / chains without sequencer check)
        address sequencerFeed;
        // USDC addresses
        address usdc;
        address usdcUsdFeed;
        // Sucker infrastructure
        bool isL1;
        // OP bridge addresses (for L1 -> OP and L1 -> Base)
        address opMessenger;
        address opBridge;
        address baseMessenger;
        address baseBridge;
    }

    // ════════════════════════════════════════════════════════════════════
    //  Deployed contract references (reset per chain)
    // ════════════════════════════════════════════════════════════════════

    address private _deployer;
    address private _trustedForwarder;
    JBPermissions private _permissions;
    JBProjects private _projects;
    JBDirectory private _directory;
    JBSplits private _splits;
    JBRulesets private _rulesets;
    JBPrices private _prices;
    JBTokens private _tokens;
    JBFundAccessLimits private _fundAccess;
    JBFeelessAddresses private _feeless;
    JBTerminalStore private _terminalStore;
    JBMultiTerminal private _terminal;
    JBController private _controller;
    JBAddressRegistry private _addressRegistry;
    JB721TiersHookStore private _hookStore;
    JB721TiersHook private _hook721;
    JB721TiersHookDeployer private _hookDeployer;
    JB721TiersHookProjectDeployer private _hookProjectDeployer;
    JBUniswapV4Hook private _uniswapV4Hook;
    JBBuybackHookRegistry private _buybackRegistry;
    JBBuybackHook private _buybackHook;
    JBRouterTerminalRegistry private _routerTerminalRegistry;
    JBRouterTerminal private _routerTerminal;
    JBUniswapV4LPSplitHook private _lpSplitHook;
    JBUniswapV4LPSplitHookDeployer private _lpSplitHookDeployer;
    JBSuckerRegistry private _suckerRegistry;
    JBOmnichainDeployer private _omnichainDeployer;

    // ════════════════════════════════════════════════════════════════════
    //  Chain config builders
    // ════════════════════════════════════════════════════════════════════

    function _ethereumConfig() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            name: "Ethereum",
            rpcEnvVar: "RPC_ETHEREUM_MAINNET",
            rpcAlias: "ethereum",
            chainId: 1,
            forkBlock: 21_700_000,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            v3Factory: 0x1F98431c8aD98523631AE4a59f267346ea31F984,
            poolManager: 0x000000000004444c5dc75cB358380D2e3dE08A90,
            positionManager: 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e,
            ethUsdFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            sequencerFeed: address(0),
            usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            usdcUsdFeed: 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6,
            isL1: true,
            opMessenger: 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1,
            opBridge: 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1,
            baseMessenger: 0x866E82a600A1414e583f7F13623F1aC5d58b0Afa,
            baseBridge: 0x3154Cf16ccdb4C6d922629664174b904d80F2C35
        });
    }

    function _optimismConfig() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            name: "Optimism",
            rpcEnvVar: "RPC_OPTIMISM_MAINNET",
            rpcAlias: "",
            chainId: 10,
            forkBlock: 131_000_000,
            weth: 0x4200000000000000000000000000000000000006,
            v3Factory: 0x1F98431c8aD98523631AE4a59f267346ea31F984,
            poolManager: 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3,
            positionManager: 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e,
            ethUsdFeed: 0x13e3Ee699D1909E989722E753853AE30b17e08c5,
            sequencerFeed: 0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389,
            usdc: 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85,
            usdcUsdFeed: 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3,
            isL1: false,
            opMessenger: 0x4200000000000000000000000000000000000007,
            opBridge: 0x4200000000000000000000000000000000000010,
            baseMessenger: address(0),
            baseBridge: address(0)
        });
    }

    function _baseConfig() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            name: "Base",
            rpcEnvVar: "RPC_BASE_MAINNET",
            rpcAlias: "",
            chainId: 8453,
            forkBlock: 26_000_000,
            weth: 0x4200000000000000000000000000000000000006,
            v3Factory: 0x33128a8fC17869897dcE68Ed026d694621f6FDfD,
            poolManager: 0x498581fF718922c3f8e6A244956aF099B2652b2b,
            positionManager: 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e,
            ethUsdFeed: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70,
            sequencerFeed: 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433,
            usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            usdcUsdFeed: 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B,
            isL1: false,
            opMessenger: 0x4200000000000000000000000000000000000007,
            opBridge: 0x4200000000000000000000000000000000000010,
            baseMessenger: address(0),
            baseBridge: address(0)
        });
    }

    function _arbitrumConfig() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            name: "Arbitrum",
            rpcEnvVar: "RPC_ARBITRUM_MAINNET",
            rpcAlias: "",
            chainId: 42_161,
            forkBlock: 296_000_000,
            weth: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            v3Factory: 0x1F98431c8aD98523631AE4a59f267346ea31F984,
            poolManager: 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32,
            positionManager: 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e,
            ethUsdFeed: 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612,
            sequencerFeed: 0xFdB631F5EE196F0ed6FAa767959853A9F217697D,
            usdc: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
            usdcUsdFeed: 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3,
            isL1: false,
            opMessenger: address(0),
            opBridge: address(0),
            baseMessenger: address(0),
            baseBridge: address(0)
        });
    }

    // ════════════════════════════════════════════════════════════════════
    //  Fork helpers
    // ════════════════════════════════════════════════════════════════════

    /// @dev Attempts to create a fork. Returns true if successful, false if the RPC is unavailable.
    function _tryCreateFork(ChainConfig memory cfg) internal returns (bool) {
        // Try the env var first, then the foundry.toml alias.
        string memory rpcUrl;

        // Try env var.
        rpcUrl = vm.envOr(cfg.rpcEnvVar, string(""));
        if (bytes(rpcUrl).length > 0) {
            try vm.createSelectFork(rpcUrl, cfg.forkBlock) {
                return true;
            } catch {
                return false;
            }
        }

        // Try foundry.toml alias (only works for ethereum which has an alias configured).
        if (bytes(cfg.rpcAlias).length > 0) {
            try vm.createSelectFork(cfg.rpcAlias, cfg.forkBlock) {
                return true;
            } catch {
                return false;
            }
        }

        return false;
    }

    // ════════════════════════════════════════════════════════════════════
    //  Deployment phases (mirrors Deploy.s.sol internal functions)
    // ════════════════════════════════════════════════════════════════════

    /// @dev Phase 01: Core Protocol. Mirrors Deploy._deployCore().
    function _deployCore() internal {
        _trustedForwarder = address(new ERC2771Forwarder("Juicebox"));
        _permissions = new JBPermissions(_trustedForwarder);
        _projects = new JBProjects(_deployer, _deployer, _trustedForwarder);
        _directory = new JBDirectory(_permissions, _projects, _deployer);
        _splits = new JBSplits(_directory);
        _rulesets = new JBRulesets(_directory);
        _prices = new JBPrices(_directory, _permissions, _projects, _deployer, _trustedForwarder);
        _tokens = new JBTokens(_directory, new JBERC20(_permissions, _projects));
        _fundAccess = new JBFundAccessLimits(_directory);
        _feeless = new JBFeelessAddresses(_deployer);
        _terminalStore = new JBTerminalStore({directory: _directory, rulesets: _rulesets, prices: _prices});
        _terminal = new JBMultiTerminal({
            permissions: _permissions,
            projects: _projects,
            splits: _splits,
            store: _terminalStore,
            tokens: _tokens,
            feelessAddresses: _feeless,
            permit2: _PERMIT2,
            trustedForwarder: _trustedForwarder
        });
    }

    /// @dev Phase 02: Address Registry. Mirrors Deploy._deployAddressRegistry().
    function _deployAddressRegistry() internal {
        _addressRegistry = new JBAddressRegistry();
    }

    /// @dev Phase 03a: 721 Hook. Mirrors Deploy._deploy721Hook().
    function _deploy721Hook() internal {
        _hookStore = new JB721TiersHookStore();
        JB721CheckpointsDeployer _checkpointsDeployer = new JB721CheckpointsDeployer(_hookStore);
        _hook721 = new JB721TiersHook(
            _directory, _permissions, _prices, _rulesets, _hookStore, _splits, _checkpointsDeployer, _trustedForwarder
        );
        _hookDeployer = new JB721TiersHookDeployer(
            _hook721, _hookStore, IJBAddressRegistry(address(_addressRegistry)), _trustedForwarder
        );
        _hookProjectDeployer =
            new JB721TiersHookProjectDeployer(_directory, _permissions, _hookDeployer, _trustedForwarder);
    }

    /// @dev Phase 03b: Uniswap V4 hook. Mirrors Deploy._deployUniswapV4Hook().
    function _deployUniswapV4Hook(ChainConfig memory cfg) internal {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(IPoolManager(cfg.poolManager), _tokens, _directory, _prices);

        (, bytes32 salt) = HookMiner.find(address(this), flags, type(JBUniswapV4Hook).creationCode, constructorArgs);

        _uniswapV4Hook = new JBUniswapV4Hook{salt: salt}(IPoolManager(cfg.poolManager), _tokens, _directory, _prices);
    }

    /// @dev Phase 03c: Buyback Hook. Mirrors Deploy._deployBuybackHook().
    function _deployBuybackHook(ChainConfig memory cfg) internal {
        _buybackRegistry = new JBBuybackHookRegistry(_permissions, _projects, _deployer, _trustedForwarder);
        _buybackHook = new JBBuybackHook(
            _directory,
            _permissions,
            _prices,
            _projects,
            _tokens,
            IPoolManager(cfg.poolManager),
            IHooks(address(_uniswapV4Hook)),
            _trustedForwarder
        );
        _buybackRegistry.setDefaultHook(_buybackHook);
    }

    /// @dev Phase 03d: Router Terminal. Mirrors Deploy._deployRouterTerminal().
    function _deployRouterTerminal(ChainConfig memory cfg) internal {
        _routerTerminalRegistry =
            new JBRouterTerminalRegistry(_permissions, _projects, _PERMIT2, _deployer, _trustedForwarder);
        _routerTerminal = new JBRouterTerminal(
            _directory,
            _tokens,
            _PERMIT2,
            IWETH9(cfg.weth),
            IUniswapV3Factory(cfg.v3Factory),
            IPoolManager(cfg.poolManager),
            address(_buybackHook),
            address(_uniswapV4Hook),
            _trustedForwarder
        );
        _routerTerminalRegistry.setDefaultTerminal(_routerTerminal);
        _feeless.setFeelessAddress(address(_routerTerminal), true);
    }

    /// @dev Phase 03e: LP split hook. Mirrors Deploy._deployLpSplitHook().
    function _deployLpSplitHook(ChainConfig memory cfg) internal {
        _lpSplitHook = new JBUniswapV4LPSplitHook(
            address(_directory),
            _permissions,
            address(_tokens),
            IPoolManager(cfg.poolManager),
            IPositionManager(cfg.positionManager),
            IAllowanceTransfer(address(_PERMIT2)),
            IHooks(address(_uniswapV4Hook))
        );
        _lpSplitHookDeployer =
            new JBUniswapV4LPSplitHookDeployer(_lpSplitHook, IJBAddressRegistry(address(_addressRegistry)));
    }

    /// @dev Phase 03f: Suckers. Deploys chain-appropriate suckers and the registry.
    ///      Suckers require chain-specific bridge infrastructure. We wrap each sub-deployer in
    ///      try-catch so a missing bridge contract does not fail the entire test.
    function _deploySuckers(ChainConfig memory cfg) internal {
        address[] memory preApproved = new address[](10);
        uint256 count = 0;

        // ── Native bridge suckers ──
        if (cfg.chainId == 1) {
            // L1: Deploy OP sucker deployer.
            try this.deployOpSuckerL1(cfg) returns (address deployer) {
                preApproved[count++] = deployer;
            } catch {}
            // L1: Deploy Base sucker deployer.
            try this.deployBaseSuckerL1(cfg) returns (address deployer) {
                preApproved[count++] = deployer;
            } catch {}
            // L1: Deploy Arb sucker deployer.
            try this.deployArbSuckerL1() returns (address deployer) {
                preApproved[count++] = deployer;
            } catch {}
        } else if (cfg.chainId == 10) {
            // L2 Optimism.
            try this.deployOpSuckerL2() returns (address deployer) {
                preApproved[count++] = deployer;
            } catch {}
        } else if (cfg.chainId == 8453) {
            // L2 Base.
            try this.deployBaseSuckerL2() returns (address deployer) {
                preApproved[count++] = deployer;
            } catch {}
        } else if (cfg.chainId == 42_161) {
            // L2 Arbitrum.
            try this.deployArbSuckerL2() returns (address deployer) {
                preApproved[count++] = deployer;
            } catch {}
        }

        // ── CCIP Suckers ──
        // Wrap in try-catch because CCIPHelper.routerOfChain may reference addresses
        // that do not have code on the fork.
        try this.deployCCIPSuckers(cfg) returns (address[] memory ccipDeployers) {
            for (uint256 i; i < ccipDeployers.length; i++) {
                if (ccipDeployers[i] != address(0)) {
                    preApproved[count++] = ccipDeployers[i];
                }
            }
        } catch {}

        // Deploy the registry.
        _suckerRegistry = new JBSuckerRegistry({
            directory: _directory,
            permissions: _permissions,
            initialOwner: _deployer,
            trustedForwarder: _trustedForwarder
        });

        // Pre-approve deployers.
        if (count > 0) {
            address[] memory trimmed = new address[](count);
            for (uint256 i; i < count; i++) {
                trimmed[i] = preApproved[i];
            }
            _suckerRegistry.allowSuckerDeployers(trimmed);
        }
    }

    /// @dev Phase 04: Omnichain Deployer. Mirrors Deploy._deployOmnichainDeployer().
    function _deployOmnichainDeployer() internal {
        _omnichainDeployer = new JBOmnichainDeployer(
            _suckerRegistry,
            IJB721TiersHookDeployer(address(_hookDeployer)),
            _permissions,
            _projects,
            _directory,
            _trustedForwarder
        );
    }

    /// @dev Phase 05: Periphery (Controller + Price Feeds + Deadlines). Mirrors Deploy._deployPeriphery().
    function _deployPeriphery(ChainConfig memory cfg) internal {
        // Deploy ETH/USD feed.
        IJBPriceFeed ethUsdFeed = _deployEthUsdFeed(cfg);
        IJBPriceFeed matchingFeed = IJBPriceFeed(address(new JBMatchingPriceFeed()));

        _prices.addPriceFeedFor({
            projectId: 0,
            pricingCurrency: JBCurrencyIds.USD,
            unitCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            feed: ethUsdFeed
        });
        _prices.addPriceFeedFor({
            projectId: 0, pricingCurrency: JBCurrencyIds.USD, unitCurrency: JBCurrencyIds.ETH, feed: ethUsdFeed
        });
        _prices.addPriceFeedFor({
            projectId: 0,
            pricingCurrency: JBCurrencyIds.ETH,
            unitCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            feed: matchingFeed
        });

        // Deploy USDC/USD feed.
        _deployUsdcFeed(cfg);

        // Deadlines.
        new JBDeadline3Hours();
        new JBDeadline1Day();
        new JBDeadline3Days();
        new JBDeadline7Days();

        // Controller (must come after omnichain deployer).
        _controller = new JBController({
            directory: _directory,
            fundAccessLimits: _fundAccess,
            prices: _prices,
            permissions: _permissions,
            projects: _projects,
            rulesets: _rulesets,
            splits: _splits,
            tokens: _tokens,
            omnichainRulesetOperator: address(_omnichainDeployer),
            trustedForwarder: _trustedForwarder
        });

        _directory.setIsAllowedToSetFirstController(address(_controller), true);
    }

    // ────────────────────────────────────────────────────────────────────
    //  Price feed helpers
    // ────────────────────────────────────────────────────────────────────

    function _deployEthUsdFeed(ChainConfig memory cfg) internal returns (IJBPriceFeed feed) {
        uint256 gracePeriod = 3600 seconds;

        if (cfg.sequencerFeed == address(0)) {
            // L1 or chain without sequencer feed.
            feed = new JBChainlinkV3PriceFeed(AggregatorV3Interface(cfg.ethUsdFeed), 3600 seconds);
        } else {
            // L2 with sequencer uptime feed.
            feed = new JBChainlinkV3SequencerPriceFeed(
                AggregatorV3Interface(cfg.ethUsdFeed),
                3600 seconds,
                AggregatorV2V3Interface(cfg.sequencerFeed),
                gracePeriod
            );
        }
    }

    function _deployUsdcFeed(ChainConfig memory cfg) internal {
        uint256 gracePeriod = 3600 seconds;
        IJBPriceFeed usdcFeed;

        if (cfg.sequencerFeed == address(0)) {
            usdcFeed = new JBChainlinkV3PriceFeed(AggregatorV3Interface(cfg.usdcUsdFeed), 86_400 seconds);
        } else {
            usdcFeed = new JBChainlinkV3SequencerPriceFeed(
                AggregatorV3Interface(cfg.usdcUsdFeed),
                86_400 seconds,
                AggregatorV2V3Interface(cfg.sequencerFeed),
                gracePeriod
            );
        }

        _prices.addPriceFeedFor({
            projectId: 0, pricingCurrency: JBCurrencyIds.USD, unitCurrency: uint32(uint160(cfg.usdc)), feed: usdcFeed
        });
    }

    // ────────────────────────────────────────────────────────────────────
    //  Sucker deployer helpers (external so they can be called via try-catch)
    // ────────────────────────────────────────────────────────────────────

    function deployOpSuckerL1(ChainConfig memory cfg) external returns (address) {
        JBOptimismSuckerDeployer opDeployer = new JBOptimismSuckerDeployer({
            directory: _directory,
            permissions: _permissions,
            tokens: _tokens,
            configurator: _deployer,
            trustedForwarder: _trustedForwarder
        });
        opDeployer.setChainSpecificConstants(IOPMessenger(cfg.opMessenger), IOPStandardBridge(cfg.opBridge));
        JBOptimismSucker singleton = new JBOptimismSucker(
            opDeployer, _directory, _permissions, _prices, _tokens, FEE_PROJECT_ID, _suckerRegistry, _trustedForwarder
        );
        opDeployer.configureSingleton(singleton);
        return address(opDeployer);
    }

    function deployOpSuckerL2() external returns (address) {
        JBOptimismSuckerDeployer opDeployer = new JBOptimismSuckerDeployer({
            directory: _directory,
            permissions: _permissions,
            tokens: _tokens,
            configurator: _deployer,
            trustedForwarder: _trustedForwarder
        });
        opDeployer.setChainSpecificConstants(
            IOPMessenger(0x4200000000000000000000000000000000000007),
            IOPStandardBridge(0x4200000000000000000000000000000000000010)
        );
        JBOptimismSucker singleton = new JBOptimismSucker(
            opDeployer, _directory, _permissions, _prices, _tokens, FEE_PROJECT_ID, _suckerRegistry, _trustedForwarder
        );
        opDeployer.configureSingleton(singleton);
        return address(opDeployer);
    }

    function deployBaseSuckerL1(ChainConfig memory cfg) external returns (address) {
        JBBaseSuckerDeployer baseDeployer = new JBBaseSuckerDeployer({
            directory: _directory,
            permissions: _permissions,
            tokens: _tokens,
            configurator: _deployer,
            trustedForwarder: _trustedForwarder
        });
        baseDeployer.setChainSpecificConstants(IOPMessenger(cfg.baseMessenger), IOPStandardBridge(cfg.baseBridge));
        JBBaseSucker singleton = new JBBaseSucker(
            baseDeployer, _directory, _permissions, _prices, _tokens, FEE_PROJECT_ID, _suckerRegistry, _trustedForwarder
        );
        baseDeployer.configureSingleton(singleton);
        return address(baseDeployer);
    }

    function deployBaseSuckerL2() external returns (address) {
        JBBaseSuckerDeployer baseDeployer = new JBBaseSuckerDeployer({
            directory: _directory,
            permissions: _permissions,
            tokens: _tokens,
            configurator: _deployer,
            trustedForwarder: _trustedForwarder
        });
        baseDeployer.setChainSpecificConstants(
            IOPMessenger(0x4200000000000000000000000000000000000007),
            IOPStandardBridge(0x4200000000000000000000000000000000000010)
        );
        JBBaseSucker singleton = new JBBaseSucker(
            baseDeployer, _directory, _permissions, _prices, _tokens, FEE_PROJECT_ID, _suckerRegistry, _trustedForwarder
        );
        baseDeployer.configureSingleton(singleton);
        return address(baseDeployer);
    }

    function deployArbSuckerL1() external returns (address) {
        JBArbitrumSuckerDeployer arbDeployer = new JBArbitrumSuckerDeployer({
            directory: _directory,
            permissions: _permissions,
            tokens: _tokens,
            configurator: _deployer,
            trustedForwarder: _trustedForwarder
        });
        arbDeployer.setChainSpecificConstants({
            layer: JBLayer.L1,
            inbox: IInbox(ARBAddresses.L1_ETH_INBOX),
            gatewayRouter: IArbGatewayRouter(ARBAddresses.L1_GATEWAY_ROUTER)
        });
        JBArbitrumSucker singleton = new JBArbitrumSucker(
            arbDeployer, _directory, _permissions, _prices, _tokens, FEE_PROJECT_ID, _suckerRegistry, _trustedForwarder
        );
        arbDeployer.configureSingleton(singleton);
        return address(arbDeployer);
    }

    function deployArbSuckerL2() external returns (address) {
        JBArbitrumSuckerDeployer arbDeployer = new JBArbitrumSuckerDeployer({
            directory: _directory,
            permissions: _permissions,
            tokens: _tokens,
            configurator: _deployer,
            trustedForwarder: _trustedForwarder
        });
        arbDeployer.setChainSpecificConstants({
            layer: JBLayer.L2,
            inbox: IInbox(address(0)),
            gatewayRouter: IArbGatewayRouter(ARBAddresses.L2_GATEWAY_ROUTER)
        });
        JBArbitrumSucker singleton = new JBArbitrumSucker(
            arbDeployer, _directory, _permissions, _prices, _tokens, FEE_PROJECT_ID, _suckerRegistry, _trustedForwarder
        );
        arbDeployer.configureSingleton(singleton);
        return address(arbDeployer);
    }

    /// @dev Deploy CCIP suckers for a given chain. Returns array of deployer addresses.
    function deployCCIPSuckers(ChainConfig memory cfg) external returns (address[] memory deployers) {
        if (cfg.chainId == 1) {
            deployers = new address[](3);
            deployers[0] = address(_deployCCIPSucker(CCIPHelper.OP_ID));
            deployers[1] = address(_deployCCIPSucker(CCIPHelper.BASE_ID));
            deployers[2] = address(_deployCCIPSucker(CCIPHelper.ARB_ID));
        } else if (cfg.chainId == 10) {
            deployers = new address[](3);
            deployers[0] = address(_deployCCIPSucker(CCIPHelper.ETH_ID));
            deployers[1] = address(_deployCCIPSucker(CCIPHelper.ARB_ID));
            deployers[2] = address(_deployCCIPSucker(CCIPHelper.BASE_ID));
        } else if (cfg.chainId == 8453) {
            deployers = new address[](3);
            deployers[0] = address(_deployCCIPSucker(CCIPHelper.ETH_ID));
            deployers[1] = address(_deployCCIPSucker(CCIPHelper.OP_ID));
            deployers[2] = address(_deployCCIPSucker(CCIPHelper.ARB_ID));
        } else if (cfg.chainId == 42_161) {
            deployers = new address[](3);
            deployers[0] = address(_deployCCIPSucker(CCIPHelper.ETH_ID));
            deployers[1] = address(_deployCCIPSucker(CCIPHelper.OP_ID));
            deployers[2] = address(_deployCCIPSucker(CCIPHelper.BASE_ID));
        } else {
            deployers = new address[](0);
        }
    }

    function _deployCCIPSucker(uint256 remoteChainId) internal returns (JBCCIPSuckerDeployer deployer) {
        deployer = new JBCCIPSuckerDeployer(_directory, _permissions, _tokens, _deployer, _trustedForwarder);
        deployer.setChainSpecificConstants(
            remoteChainId,
            CCIPHelper.selectorOfChain(remoteChainId),
            ICCIPRouter(CCIPHelper.routerOfChain(block.chainid))
        );
        JBCCIPSucker singleton = new JBCCIPSucker(
            deployer, _directory, _permissions, _prices, _tokens, FEE_PROJECT_ID, _suckerRegistry, _trustedForwarder
        );
        deployer.configureSingleton(singleton);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Full deployment runner
    // ════════════════════════════════════════════════════════════════════

    /// @dev Runs the full infrastructure deployment (Phases 01-05) for a given chain config.
    function _runFullDeployment(ChainConfig memory cfg) internal {
        _deployer = makeAddr("deployer");
        vm.deal(_deployer, 100 ether);
        vm.startPrank(_deployer);

        // Phase 01: Core Protocol
        _deployCore();

        // Phase 02: Address Registry
        _deployAddressRegistry();

        // Phase 03a: 721 Hook
        _deploy721Hook();

        // Phase 03b: Uniswap V4 Hook
        // Stop prank: CREATE2 deployer must be address(this) to match HookMiner.find(address(this), ...).
        vm.stopPrank();
        _deployUniswapV4Hook(cfg);
        vm.startPrank(_deployer);

        // Phase 03c: Buyback Hook
        _deployBuybackHook(cfg);

        // Phase 03d: Router Terminal
        _deployRouterTerminal(cfg);

        // Phase 03e: LP Split Hook
        _deployLpSplitHook(cfg);

        // Phase 03f: Cross-Chain Suckers
        _deploySuckers(cfg);

        // Phase 04: Omnichain Deployer
        _deployOmnichainDeployer();

        // Phase 05: Periphery (Controller + Price Feeds + Deadlines)
        _deployPeriphery(cfg);

        vm.stopPrank();
    }

    // ════════════════════════════════════════════════════════════════════
    //  Assertions
    // ════════════════════════════════════════════════════════════════════

    function _assertCoreDeployment(string memory chainName) internal view {
        // All core contracts deployed at non-zero addresses with code.
        assertTrue(address(_permissions) != address(0), string.concat(chainName, ": Permissions not deployed"));
        assertTrue(address(_projects) != address(0), string.concat(chainName, ": Projects not deployed"));
        assertTrue(address(_directory) != address(0), string.concat(chainName, ": Directory not deployed"));
        assertTrue(address(_splits) != address(0), string.concat(chainName, ": Splits not deployed"));
        assertTrue(address(_rulesets) != address(0), string.concat(chainName, ": Rulesets not deployed"));
        assertTrue(address(_prices) != address(0), string.concat(chainName, ": Prices not deployed"));
        assertTrue(address(_tokens) != address(0), string.concat(chainName, ": Tokens not deployed"));
        assertTrue(address(_fundAccess) != address(0), string.concat(chainName, ": FundAccessLimits not deployed"));
        assertTrue(address(_feeless) != address(0), string.concat(chainName, ": FeelessAddresses not deployed"));
        assertTrue(address(_terminalStore) != address(0), string.concat(chainName, ": TerminalStore not deployed"));
        assertTrue(address(_terminal) != address(0), string.concat(chainName, ": Terminal not deployed"));
        assertTrue(_trustedForwarder != address(0), string.concat(chainName, ": TrustedForwarder not deployed"));

        // Bytecode verification.
        assertTrue(address(_permissions).code.length > 0, string.concat(chainName, ": Permissions has no code"));
        assertTrue(address(_terminal).code.length > 0, string.concat(chainName, ": Terminal has no code"));
    }

    function _assertCoreWiring(string memory chainName) internal view {
        // TerminalStore wiring.
        assertEq(
            address(_terminalStore.DIRECTORY()),
            address(_directory),
            string.concat(chainName, ": TerminalStore.DIRECTORY mismatch")
        );
        assertEq(
            address(_terminalStore.PRICES()),
            address(_prices),
            string.concat(chainName, ": TerminalStore.PRICES mismatch")
        );
        assertEq(
            address(_terminalStore.RULESETS()),
            address(_rulesets),
            string.concat(chainName, ": TerminalStore.RULESETS mismatch")
        );
    }

    function _assertControllerDeployment(string memory chainName) internal view {
        assertTrue(address(_controller) != address(0), string.concat(chainName, ": Controller not deployed"));
        assertTrue(address(_controller).code.length > 0, string.concat(chainName, ": Controller has no code"));

        // Controller wiring.
        assertEq(
            address(_controller.DIRECTORY()),
            address(_directory),
            string.concat(chainName, ": Controller.DIRECTORY mismatch")
        );
        assertEq(
            address(_controller.FUND_ACCESS_LIMITS()),
            address(_fundAccess),
            string.concat(chainName, ": Controller.FUND_ACCESS_LIMITS mismatch")
        );
        assertEq(
            address(_controller.PRICES()), address(_prices), string.concat(chainName, ": Controller.PRICES mismatch")
        );
        assertEq(
            address(_controller.RULESETS()),
            address(_rulesets),
            string.concat(chainName, ": Controller.RULESETS mismatch")
        );
        assertEq(
            address(_controller.SPLITS()), address(_splits), string.concat(chainName, ": Controller.SPLITS mismatch")
        );
        assertEq(
            address(_controller.TOKENS()), address(_tokens), string.concat(chainName, ": Controller.TOKENS mismatch")
        );

        // Controller is allowed to set first controller.
        assertTrue(
            _directory.isAllowedToSetFirstController(address(_controller)),
            string.concat(chainName, ": Controller not allowed to set first controller")
        );
    }

    function _assertProjectOneExists(string memory chainName) internal view {
        // Project #1 is minted to the deployer during JBProjects construction.
        address projectOneOwner = _projects.ownerOf(1);
        assertEq(
            projectOneOwner, _deployer, string.concat(chainName, ": Project #1 owner mismatch (expected deployer)")
        );
    }

    function _assertPeripheryDeployment(string memory chainName) internal view {
        // 721 Hook.
        assertTrue(address(_hookStore) != address(0), string.concat(chainName, ": HookStore not deployed"));
        assertTrue(address(_hookDeployer) != address(0), string.concat(chainName, ": HookDeployer not deployed"));
        assertTrue(
            address(_hookProjectDeployer) != address(0), string.concat(chainName, ": HookProjectDeployer not deployed")
        );

        // Buyback Hook.
        assertEq(
            address(_buybackRegistry.defaultHook()),
            address(_buybackHook),
            string.concat(chainName, ": Buyback default hook mismatch")
        );
        assertEq(
            address(_buybackHook.ORACLE_HOOK()),
            address(_uniswapV4Hook),
            string.concat(chainName, ": Buyback oracle hook mismatch")
        );

        // Router Terminal.
        assertEq(
            address(_routerTerminalRegistry.defaultTerminal()),
            address(_routerTerminal),
            string.concat(chainName, ": Router default terminal mismatch")
        );
        assertTrue(
            _feeless.isFeeless(address(_routerTerminal)), string.concat(chainName, ": Router terminal not feeless")
        );

        // LP split hook deployer.
        assertEq(
            address(_lpSplitHookDeployer.HOOK()),
            address(_lpSplitHook),
            string.concat(chainName, ": LP split hook implementation mismatch")
        );
        assertEq(
            address(_lpSplitHookDeployer.ADDRESS_REGISTRY()),
            address(_addressRegistry),
            string.concat(chainName, ": LP split hook registry mismatch")
        );
        assertEq(
            address(_lpSplitHook.ORACLE_HOOK()),
            address(_uniswapV4Hook),
            string.concat(chainName, ": LP split oracle hook mismatch")
        );

        // Sucker Registry.
        assertTrue(address(_suckerRegistry) != address(0), string.concat(chainName, ": SuckerRegistry not deployed"));

        // Omnichain Deployer.
        assertTrue(
            address(_omnichainDeployer) != address(0), string.concat(chainName, ": OmnichainDeployer not deployed")
        );

        // Address Registry.
        assertTrue(address(_addressRegistry) != address(0), string.concat(chainName, ": AddressRegistry not deployed"));
    }

    function _assertPriceFeeds(string memory chainName) internal view {
        // ETH/USD price should be between $100 and $100,000.
        uint256 pricePerUnit = _prices.pricePerUnitOf({
            projectId: 0,
            pricingCurrency: JBCurrencyIds.USD,
            unitCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            decimals: 18
        });
        assertTrue(pricePerUnit > 100e18, string.concat(chainName, ": ETH price too low"));
        assertTrue(pricePerUnit < 100_000e18, string.concat(chainName, ": ETH price too high"));
    }

    // ════════════════════════════════════════════════════════════════════
    //  Tests — one per chain
    // ════════════════════════════════════════════════════════════════════

    /// @notice Full-stack deployment on Ethereum mainnet fork.
    function test_fullStack_ethereum() public {
        ChainConfig memory cfg = _ethereumConfig();
        if (!_tryCreateFork(cfg)) {
            vm.skip(true);
            return;
        }

        _runFullDeployment(cfg);

        _assertCoreDeployment(cfg.name);
        _assertCoreWiring(cfg.name);
        _assertControllerDeployment(cfg.name);
        _assertProjectOneExists(cfg.name);
        _assertPeripheryDeployment(cfg.name);
        _assertPriceFeeds(cfg.name);
    }

    /// @notice Full-stack deployment on Optimism mainnet fork.
    function test_fullStack_optimism() public {
        ChainConfig memory cfg = _optimismConfig();
        if (!_tryCreateFork(cfg)) {
            vm.skip(true);
            return;
        }

        _runFullDeployment(cfg);

        _assertCoreDeployment(cfg.name);
        _assertCoreWiring(cfg.name);
        _assertControllerDeployment(cfg.name);
        _assertProjectOneExists(cfg.name);
        _assertPeripheryDeployment(cfg.name);
        _assertPriceFeeds(cfg.name);
    }

    /// @notice Full-stack deployment on Base mainnet fork.
    function test_fullStack_base() public {
        ChainConfig memory cfg = _baseConfig();
        if (!_tryCreateFork(cfg)) {
            vm.skip(true);
            return;
        }

        _runFullDeployment(cfg);

        _assertCoreDeployment(cfg.name);
        _assertCoreWiring(cfg.name);
        _assertControllerDeployment(cfg.name);
        _assertProjectOneExists(cfg.name);
        _assertPeripheryDeployment(cfg.name);
        _assertPriceFeeds(cfg.name);
    }

    /// @notice Full-stack deployment on Arbitrum mainnet fork.
    function test_fullStack_arbitrum() public {
        ChainConfig memory cfg = _arbitrumConfig();
        if (!_tryCreateFork(cfg)) {
            vm.skip(true);
            return;
        }

        _runFullDeployment(cfg);

        _assertCoreDeployment(cfg.name);
        _assertCoreWiring(cfg.name);
        _assertControllerDeployment(cfg.name);
        _assertProjectOneExists(cfg.name);
        _assertPeripheryDeployment(cfg.name);
        _assertPriceFeeds(cfg.name);
    }
}
