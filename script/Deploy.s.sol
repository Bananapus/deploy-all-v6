// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@sphinx-labs/contracts/contracts/foundry/SphinxPlugin.sol";
import {Script, stdJson, VmSafe} from "forge-std/Script.sol";

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

// ── Core Structs ──
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

// ── Core Interfaces ──
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";

// ── Core Periphery ──
import {JBDeadline3Hours} from "@bananapus/core-v6/src/periphery/JBDeadline3Hours.sol";
import {JBDeadline1Day} from "@bananapus/core-v6/src/periphery/JBDeadline1Day.sol";
import {JBDeadline3Days} from "@bananapus/core-v6/src/periphery/JBDeadline3Days.sol";
import {JBDeadline7Days} from "@bananapus/core-v6/src/periphery/JBDeadline7Days.sol";
import {JBMatchingPriceFeed} from "@bananapus/core-v6/src/periphery/JBMatchingPriceFeed.sol";

// ── Price Feeds ──
import {JBChainlinkV3PriceFeed, AggregatorV3Interface} from "@bananapus/core-v6/src/JBChainlinkV3PriceFeed.sol";
import {AggregatorV2V3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";
import {JBChainlinkV3SequencerPriceFeed} from "@bananapus/core-v6/src/JBChainlinkV3SequencerPriceFeed.sol";

// ── Address Registry ──
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// ── 721 Hook ──
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHookProjectDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookProjectDeployer.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {IJB721TokenUriResolver} from "@bananapus/721-hook-v6/src/interfaces/IJB721TokenUriResolver.sol";
import {JB721InitTiersConfig} from "@bananapus/721-hook-v6/src/structs/JB721InitTiersConfig.sol";
import {JB721TierConfig} from "@bananapus/721-hook-v6/src/structs/JB721TierConfig.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";

// ── Buyback Hook ──
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

// ── Router Terminal ──
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";
import {IWETH9 as IRouterWETH9} from "@bananapus/router-terminal-v6/src/interfaces/IWETH9.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

// ── Suckers ──
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {JBArbitrumSucker} from "@bananapus/suckers-v6/src/JBArbitrumSucker.sol";
import {JBBaseSucker} from "@bananapus/suckers-v6/src/JBBaseSucker.sol";
import {JBCCIPSucker} from "@bananapus/suckers-v6/src/JBCCIPSucker.sol";
import {JBOptimismSucker} from "@bananapus/suckers-v6/src/JBOptimismSucker.sol";
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {JBArbitrumSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBArbitrumSuckerDeployer.sol";
import {JBBaseSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBBaseSuckerDeployer.sol";
import {JBCCIPSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBCCIPSuckerDeployer.sol";
import {JBOptimismSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBOptimismSuckerDeployer.sol";
import {JBLayer} from "@bananapus/suckers-v6/src/enums/JBLayer.sol";
import {IArbGatewayRouter} from "@bananapus/suckers-v6/src/interfaces/IArbGatewayRouter.sol";
import {ICCIPRouter} from "@bananapus/suckers-v6/src/interfaces/ICCIPRouter.sol";
import {IOPMessenger} from "@bananapus/suckers-v6/src/interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "@bananapus/suckers-v6/src/interfaces/IOPStandardBridge.sol";
import {ARBAddresses} from "@bananapus/suckers-v6/src/libraries/ARBAddresses.sol";
import {ARBChains} from "@bananapus/suckers-v6/src/libraries/ARBChains.sol";
import {CCIPHelper} from "@bananapus/suckers-v6/src/libraries/CCIPHelper.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";
import {JBTokenMapping} from "@bananapus/suckers-v6/src/structs/JBTokenMapping.sol";
import {IJBSuckerDeployer} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerDeployer.sol";

// ── Omnichain Deployer ──
import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";

// ── Croptop ──
import {CTDeployer} from "@croptop/core-v6/src/CTDeployer.sol";
import {CTProjectOwner} from "@croptop/core-v6/src/CTProjectOwner.sol";
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";

// ── Revnet ──
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans, IREVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVAutoIssuance.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVCroptopAllowedPost} from "@rev-net/core-v6/src/structs/REVCroptopAllowedPost.sol";
import {REVDeploy721TiersHookConfig} from "@rev-net/core-v6/src/structs/REVDeploy721TiersHookConfig.sol";
import {REVBaseline721HookConfig} from "@rev-net/core-v6/src/structs/REVBaseline721HookConfig.sol";
import {REV721TiersHookFlags} from "@rev-net/core-v6/src/structs/REV721TiersHookFlags.sol";

// ── Banny ──
import {Banny721TokenUriResolver} from "@bannynet/core-v6/src/Banny721TokenUriResolver.sol";

// ── Defifa ── (TODO: uncomment when Defifa source is updated)
// import {ITypeface} from "lib/typeface/contracts/interfaces/ITypeface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import {DefifaHook} from "@ballkidz/defifa/src/DefifaHook.sol";
// import {DefifaDeployer} from "@ballkidz/defifa/src/DefifaDeployer.sol";
// import {DefifaGovernor} from "@ballkidz/defifa/src/DefifaGovernor.sol";
// import {DefifaTokenUriResolver} from "@ballkidz/defifa/src/DefifaTokenUriResolver.sol";

/// @title Deploy — Juicebox V6 Ecosystem
/// @notice One-shot deployment of the entire Juicebox V6 ecosystem.
/// @dev Based on each source repo's Deploy.s.sol. Deploys everything in dependency order within a single Sphinx
/// proposal.
contract Deploy is Script, Sphinx {
    // ════════════════════════════════════════════════════════════════════
    //  Constants
    // ════════════════════════════════════════════════════════════════════

    IPermit2 private constant _PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    string private constant TRUSTED_FORWARDER_NAME = "Juicebox";
    uint256 private constant CORE_DEPLOYMENT_NONCE = 6;

    // ── Core salts ──
    bytes32 private constant DEADLINES_SALT = keccak256("_JBDeadlinesV6_");
    bytes32 private constant USD_NATIVE_FEED_SALT = keccak256("USD_FEEDV6");

    // ── Address Registry salt ──
    bytes32 private constant ADDRESS_REGISTRY_SALT = "_JBAddressRegistryV6_";

    // ── 721 Hook salts ──
    bytes32 private constant HOOK_721_STORE_SALT = "JB721TiersHookStoreV6_";
    bytes32 private constant HOOK_721_SALT = "JB721TiersHookV6_";
    bytes32 private constant HOOK_721_DEPLOYER_SALT = "JB721TiersHookDeployerV6_";
    bytes32 private constant HOOK_721_PROJECT_DEPLOYER_SALT = "JB721TiersHookProjectDeployerV6";

    // ── Buyback Hook salt ──
    bytes32 private constant BUYBACK_HOOK_SALT = "JBBuybackHookV6";

    // ── Router Terminal salts ──
    bytes32 private constant ROUTER_TERMINAL_SALT = "JBRouterTerminalV6";
    bytes32 private constant ROUTER_TERMINAL_REGISTRY_SALT = "JBRouterTerminalRegistryV6";

    // ── Sucker salts ──
    bytes32 private constant OP_SALT = "_SUCKER_ETH_OP_V6_";
    bytes32 private constant BASE_SALT = "_SUCKER_ETH_BASE_V6_";
    bytes32 private constant ARB_SALT = "_SUCKER_ETH_ARB_V6_";
    bytes32 private constant ARB_BASE_SALT = "_SUCKER_ARB_BASE_V6_";
    bytes32 private constant ARB_OP_SALT = "_SUCKER_ARB_OP_V6_";
    bytes32 private constant OP_BASE_SALT = "_SUCKER_OP_BASE_V6_";
    bytes32 private constant SUCKER_REGISTRY_SALT = "REGISTRYV6";

    // ── Omnichain Deployer salt ──
    bytes32 private constant OMNICHAIN_DEPLOYER_SALT = "JBOmnichainDeployerV6_";

    // ── Croptop salts ──
    bytes32 private constant CT_PUBLISHER_SALT = "_PUBLISHER_SALTV6_";
    bytes32 private constant CT_DEPLOYER_SALT = "_DEPLOYER_SALTV6_";
    bytes32 private constant CT_PROJECT_OWNER_SALT = "_PROJECT_OWNER_SALTV6_";

    // ── Revnet salts ──
    bytes32 private constant REV_ERC20_SALT = "_REV_ERC20_SALT_V6_";
    bytes32 private constant REV_SUCKER_SALT = "_REV_SUCKER_SALT_V6_";
    bytes32 private constant REV_DEPLOYER_SALT = "_REV_DEPLOYER_SALT_V6_";
    bytes32 private constant REV_LOANS_SALT = "_REV_LOANS_SALT_V6_";

    // ── NANA Fee Project salts ──
    bytes32 private constant NANA_ERC20_SALT = "_NANA_ERC20_SALTV6__";
    bytes32 private constant NANA_SUCKER_SALT = "_NANA_SUCKER_SALTV6__";

    // ── CPN salts ──
    bytes32 private constant CPN_ERC20_SALT = "_CPN_ERC20_SALTV6__";
    bytes32 private constant CPN_SUCKER_SALT = "_CPN_SUCKERV6__";
    bytes32 private constant CPN_HOOK_SALT = "_CPN_HOOK_SALTV6__";

    // ── Banny salts ──
    bytes32 private constant BAN_ERC20_SALT = "_BAN_ERC20V6_";
    bytes32 private constant BAN_SUCKER_SALT = "_BAN_SUCKERV6_";
    bytes32 private constant BAN_HOOK_SALT = "_BAN_HOOKV6_";
    bytes32 private constant BAN_RESOLVER_SALT = "_BAN_RESOLVERV6_";

    // ── Defifa salt ──
    bytes32 private constant DEFIFA_SALT = bytes32(keccak256("0.0.2"));

    // ── Defifa Revnet salts ──
    bytes32 private constant DEFIFA_REV_ERC20_SALT = "_DEFIFA_ERC20V6_";
    bytes32 private constant DEFIFA_REV_SUCKER_SALT = "_DEFIFA_SUCKERV6_";

    // ── REV constants ──
    uint48 private constant REV_START_TIME = 1_740_089_444;
    uint104 private constant REV_MAINNET_AUTO_ISSUANCE = 1_050_482_341_387_116_262_330_122;
    uint104 private constant REV_BASE_AUTO_ISSUANCE = 38_544_322_230_437_559_731_228;
    uint104 private constant REV_OP_AUTO_ISSUANCE = 32_069_388_242_375_817_844;
    uint104 private constant REV_ARB_AUTO_ISSUANCE = 3_479_431_776_906_850_000_000;

    // ── NANA constants ──
    uint48 private constant NANA_START_TIME = 1_740_089_444;
    uint104 private constant NANA_MAINNET_AUTO_ISSUANCE = 34_614_774_622_547_324_824_200;
    uint104 private constant NANA_BASE_AUTO_ISSUANCE = 1_604_412_323_715_200_204_800;
    uint104 private constant NANA_OP_AUTO_ISSUANCE = 6_266_215_368_602_910_600;
    uint104 private constant NANA_ARB_AUTO_ISSUANCE = 105_160_496_145_000_000;

    // ── CPN constants ──
    uint48 private constant CPN_START_TIME = 1_740_089_444;
    uint104 private constant CPN_MAINNET_AUTO_ISSUANCE = 250_003_875_000_000_000_000_000;
    uint104 private constant CPN_BASE_AUTO_ISSUANCE = 844_894_881_600_000_000_000;
    uint104 private constant CPN_OP_AUTO_ISSUANCE = 844_894_881_600_000_000_000;
    uint104 private constant CPN_ARB_AUTO_ISSUANCE = 3_844_000_000_000_000_000;

    // ── Banny constants ──
    uint48 private constant BAN_START_TIME = 1_740_435_044;
    uint104 private constant BAN_MAINNET_AUTO_ISSUANCE = 545_296_034_092_246_678_345_976;
    uint104 private constant BAN_BASE_AUTO_ISSUANCE = 10_097_684_379_816_492_953_872;
    uint104 private constant BAN_OP_AUTO_ISSUANCE = 328_366_065_858_064_488_000;
    uint104 private constant BAN_ARB_AUTO_ISSUANCE = 2_825_980_000_000_000_000_000;

    // ── Common ──
    uint32 private constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));
    uint32 private constant ETH_CURRENCY = uint32(JBCurrencyIds.ETH);
    uint8 private constant DECIMALS = 18;
    uint256 private constant DECIMAL_MULTIPLIER = 10 ** DECIMALS;
    uint32 private constant PREMINT_CHAIN_ID = 1;

    // ════════════════════════════════════════════════════════════════════
    //  Deployed contract references (set during deployment)
    // ════════════════════════════════════════════════════════════════════

    // Core
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

    // Address Registry
    JBAddressRegistry private _addressRegistry;

    // 721 Hook
    JB721TiersHookStore private _hookStore;
    JB721TiersHook private _hook721;
    JB721TiersHookDeployer private _hookDeployer;
    JB721TiersHookProjectDeployer private _hookProjectDeployer;

    // Buyback Hook
    JBBuybackHookRegistry private _buybackRegistry;
    JBBuybackHook private _buybackHook;

    // Router Terminal
    JBRouterTerminalRegistry private _routerTerminalRegistry;
    JBRouterTerminal private _routerTerminal;

    // Suckers
    JBSuckerRegistry private _suckerRegistry;
    address[] private _preApprovedSuckerDeployers;
    IJBSuckerDeployer private _optimismSuckerDeployer;
    IJBSuckerDeployer private _baseSuckerDeployer;
    IJBSuckerDeployer private _arbitrumSuckerDeployer;

    // Omnichain Deployer
    JBOmnichainDeployer private _omnichainDeployer;

    // Croptop
    CTPublisher private _ctPublisher;
    CTDeployer private _ctDeployer;
    CTProjectOwner private _ctProjectOwner;

    // Revnet
    REVLoans private _revLoans;
    REVDeployer private _revDeployer;

    // Project IDs (determined by deploy order)
    uint256 private _cpnProjectId; // project 2
    uint256 private _revProjectId; // project 3

    // Chain-specific addresses (set in run())
    address private _weth;
    address private _v3Factory;
    address private _poolManager;

    // ════════════════════════════════════════════════════════════════════
    //  Sphinx Configuration
    // ════════════════════════════════════════════════════════════════════

    function configureSphinx() public override {
        sphinxConfig.projectName = "juicebox-v6";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    // ════════════════════════════════════════════════════════════════════
    //  Entry Point
    // ════════════════════════════════════════════════════════════════════

    function run() public {
        _setupChainAddresses();
        deploy();
    }

    function deploy() public sphinx {
        // Phase 01: Core Protocol
        _deployCore();

        // Phase 02: Address Registry
        _deployAddressRegistry();

        // Phase 03a: 721 Tier Hook
        _deploy721Hook();

        // Phase 03b: Buyback Hook
        _deployBuybackHook();

        // Phase 03c: Router Terminal
        _deployRouterTerminal();

        // Phase 03d: Cross-Chain Suckers
        _deploySuckers();

        // Phase 04: Omnichain Deployer
        _deployOmnichainDeployer();

        // Phase 05: Periphery (Controller + Price Feeds + Deadlines)
        // NOTE: Must come AFTER omnichain deployer — Controller needs its address.
        _deployPeriphery();

        // Phase 06: Croptop — creates CPN project (ID 2), deploys CT contracts
        _deployCroptop();

        // Phase 07: Revnet — creates REV project (ID 3), deploys REVLoans + REVDeployer, configures $REV
        _deployRevnet();

        // Phase 08: Configure CPN (project 2) and NANA (project 1) as revnets
        _deployCpnRevnet();
        _deployNanaRevnet();

        // Phase 09: Banny — creates BAN project (ID 4)
        _deployBanny();

        // TODO: Defifa — uncomment when ready.
        // _deployDefifaRevnet();
        // _deployDefifa();
    }

    // ════════════════════════════════════════════════════════════════════
    //  Chain-Specific Address Setup
    // ════════════════════════════════════════════════════════════════════

    function _setupChainAddresses() internal {
        // Ethereum Mainnet
        if (block.chainid == 1) {
            _weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            _v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            _poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        }
        // Ethereum Sepolia
        else if (block.chainid == 11_155_111) {
            _weth = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
            _v3Factory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
            _poolManager = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
        }
        // Optimism
        else if (block.chainid == 10) {
            _weth = 0x4200000000000000000000000000000000000006;
            _v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            _poolManager = 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
        }
        // Optimism Sepolia
        // TODO: Uniswap V4 PoolManager is not yet deployed on OP Sepolia. Verify and update once available.
        else if (block.chainid == 11_155_420) {
            _weth = 0x4200000000000000000000000000000000000006;
            _v3Factory = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
            _poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        }
        // Base
        else if (block.chainid == 8453) {
            _weth = 0x4200000000000000000000000000000000000006;
            _v3Factory = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
            _poolManager = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
        }
        // Base Sepolia
        else if (block.chainid == 84_532) {
            _weth = 0x4200000000000000000000000000000000000006;
            _v3Factory = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
            _poolManager = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
        }
        // Arbitrum
        else if (block.chainid == 42_161) {
            _weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
            _v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            _poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
        }
        // Arbitrum Sepolia
        else if (block.chainid == 421_614) {
            _weth = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
            _v3Factory = 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e;
            _poolManager = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
        } else {
            revert("Unsupported chain");
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 01: Core Protocol
    // ════════════════════════════════════════════════════════════════════

    function _deployCore() internal {
        _trustedForwarder =
            address(new ERC2771Forwarder{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}(TRUSTED_FORWARDER_NAME));

        _permissions = new JBPermissions{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}(_trustedForwarder);

        _projects = new JBProjects{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}(
            safeAddress(), safeAddress(), _trustedForwarder
        );

        _directory =
            new JBDirectory{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}(_permissions, _projects, safeAddress());

        _splits = new JBSplits{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}(_directory);

        _rulesets = new JBRulesets{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}(_directory);

        _prices = new JBPrices{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}(
            _directory, _permissions, _projects, safeAddress(), _trustedForwarder
        );

        _tokens = new JBTokens{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}(
            _directory, new JBERC20{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}()
        );

        _fundAccess = new JBFundAccessLimits{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}(_directory);

        _feeless = new JBFeelessAddresses{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}(safeAddress());

        _terminalStore = new JBTerminalStore{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}({
            directory: _directory, rulesets: _rulesets, prices: _prices
        });

        _terminal = new JBMultiTerminal{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}({
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

    // ════════════════════════════════════════════════════════════════════
    //  Phase 02: Address Registry
    // ════════════════════════════════════════════════════════════════════

    function _deployAddressRegistry() internal {
        _addressRegistry = new JBAddressRegistry{salt: ADDRESS_REGISTRY_SALT}();
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 03a: 721 Tier Hook
    // ════════════════════════════════════════════════════════════════════

    function _deploy721Hook() internal {
        _hookStore = new JB721TiersHookStore{salt: HOOK_721_STORE_SALT}();

        _hook721 = new JB721TiersHook{salt: HOOK_721_SALT}(
            _directory, _permissions, _prices, _rulesets, _hookStore, _splits, _trustedForwarder
        );

        _hookDeployer = new JB721TiersHookDeployer{salt: HOOK_721_DEPLOYER_SALT}(
            _hook721, _hookStore, IJBAddressRegistry(address(_addressRegistry)), _trustedForwarder
        );

        _hookProjectDeployer = new JB721TiersHookProjectDeployer{salt: HOOK_721_PROJECT_DEPLOYER_SALT}(
            _directory, _permissions, _hookDeployer, _trustedForwarder
        );
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 03b: Buyback Hook
    // ════════════════════════════════════════════════════════════════════

    function _deployBuybackHook() internal {
        _buybackRegistry = new JBBuybackHookRegistry{salt: BUYBACK_HOOK_SALT}(
            _permissions, _projects, safeAddress(), _trustedForwarder
        );

        _buybackHook = new JBBuybackHook{salt: BUYBACK_HOOK_SALT}(
            _directory,
            _permissions,
            _prices,
            _projects,
            _tokens,
            IPoolManager(_poolManager),
            IHooks(address(0)),
            _trustedForwarder
        );

        _buybackRegistry.setDefaultHook(_buybackHook);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 03c: Router Terminal
    // ════════════════════════════════════════════════════════════════════

    function _deployRouterTerminal() internal {
        _routerTerminalRegistry = new JBRouterTerminalRegistry{salt: ROUTER_TERMINAL_REGISTRY_SALT}(
            _permissions, _projects, _PERMIT2, safeAddress(), _trustedForwarder
        );

        _routerTerminal = new JBRouterTerminal{salt: ROUTER_TERMINAL_SALT}(
            _directory,
            _permissions,
            _projects,
            _tokens,
            _PERMIT2,
            safeAddress(),
            IRouterWETH9(_weth),
            IUniswapV3Factory(_v3Factory),
            IPoolManager(_poolManager),
            _trustedForwarder
        );

        _routerTerminalRegistry.setDefaultTerminal(_routerTerminal);

        // Mark the router terminal as feeless so that project-to-project token routing
        // (cashout → pay) doesn't incur the 2.5% protocol fee. Value stays in the protocol.
        _feeless.setFeelessAddress(address(_routerTerminal), true);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 03d: Cross-Chain Suckers
    // ════════════════════════════════════════════════════════════════════

    function _deploySuckers() internal {
        _deploySuckersOptimism();
        _deploySuckersBase();
        _deploySuckersArbitrum();
        _deploySuckersCCIP();

        // Deploy the registry and pre-approve deployers.
        _suckerRegistry = new JBSuckerRegistry{salt: SUCKER_REGISTRY_SALT}({
            directory: _directory,
            permissions: _permissions,
            initialOwner: safeAddress(),
            trustedForwarder: _trustedForwarder
        });

        if (_preApprovedSuckerDeployers.length != 0) {
            _suckerRegistry.allowSuckerDeployers(_preApprovedSuckerDeployers);
        }
    }

    function _deploySuckersOptimism() internal {
        // L1: Ethereum Mainnet / Sepolia
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            JBOptimismSuckerDeployer opDeployer = new JBOptimismSuckerDeployer{salt: OP_SALT}({
                directory: _directory,
                permissions: _permissions,
                tokens: _tokens,
                configurator: safeAddress(),
                trustedForwarder: _trustedForwarder
            });

            opDeployer.setChainSpecificConstants(
                IOPMessenger(
                    block.chainid == 1
                        ? address(0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1)
                        : address(0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef)
                ),
                IOPStandardBridge(
                    block.chainid == 1
                        ? address(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1)
                        : address(0xFBb0621E0B23b5478B630BD55a5f21f67730B0F1)
                )
            );

            JBOptimismSucker singleton = new JBOptimismSucker{salt: OP_SALT}({
                deployer: opDeployer,
                directory: _directory,
                permissions: _permissions,
                tokens: _tokens,
                feeProjectId: 1,
                registry: _suckerRegistry,
                trustedForwarder: _trustedForwarder
            });
            opDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(opDeployer));
            _optimismSuckerDeployer = IJBSuckerDeployer(address(opDeployer));
        }

        // L2: Optimism / Optimism Sepolia
        if (block.chainid == 10 || block.chainid == 11_155_420) {
            JBOptimismSuckerDeployer opDeployer = new JBOptimismSuckerDeployer{salt: OP_SALT}({
                directory: _directory,
                permissions: _permissions,
                tokens: _tokens,
                configurator: safeAddress(),
                trustedForwarder: _trustedForwarder
            });

            opDeployer.setChainSpecificConstants(
                IOPMessenger(0x4200000000000000000000000000000000000007),
                IOPStandardBridge(0x4200000000000000000000000000000000000010)
            );

            JBOptimismSucker singleton = new JBOptimismSucker{salt: OP_SALT}({
                deployer: opDeployer,
                directory: _directory,
                permissions: _permissions,
                tokens: _tokens,
                feeProjectId: 1,
                registry: _suckerRegistry,
                trustedForwarder: _trustedForwarder
            });
            opDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(opDeployer));
            _optimismSuckerDeployer = IJBSuckerDeployer(address(opDeployer));
        }
    }

    function _deploySuckersBase() internal {
        // L1
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            JBBaseSuckerDeployer baseDeployer = new JBBaseSuckerDeployer{salt: BASE_SALT}({
                directory: _directory,
                permissions: _permissions,
                tokens: _tokens,
                configurator: safeAddress(),
                trustedForwarder: _trustedForwarder
            });

            baseDeployer.setChainSpecificConstants(
                IOPMessenger(
                    block.chainid == 1
                        ? address(0x866E82a600A1414e583f7F13623F1aC5d58b0Afa)
                        : address(0xC34855F4De64F1840e5686e64278da901e261f20)
                ),
                IOPStandardBridge(
                    block.chainid == 1
                        ? address(0x3154Cf16ccdb4C6d922629664174b904d80F2C35)
                        : address(0xfd0Bf71F60660E2f608ed56e1659C450eB113120)
                )
            );

            JBBaseSucker singleton = new JBBaseSucker{salt: BASE_SALT}({
                deployer: baseDeployer,
                directory: _directory,
                permissions: _permissions,
                tokens: _tokens,
                feeProjectId: 1,
                registry: _suckerRegistry,
                trustedForwarder: _trustedForwarder
            });
            baseDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(baseDeployer));
            _baseSuckerDeployer = IJBSuckerDeployer(address(baseDeployer));
        }

        // L2: Base / Base Sepolia
        if (block.chainid == 8453 || block.chainid == 84_532) {
            JBBaseSuckerDeployer baseDeployer = new JBBaseSuckerDeployer{salt: BASE_SALT}({
                directory: _directory,
                permissions: _permissions,
                tokens: _tokens,
                configurator: safeAddress(),
                trustedForwarder: _trustedForwarder
            });

            baseDeployer.setChainSpecificConstants(
                IOPMessenger(0x4200000000000000000000000000000000000007),
                IOPStandardBridge(0x4200000000000000000000000000000000000010)
            );

            JBBaseSucker singleton = new JBBaseSucker{salt: BASE_SALT}({
                deployer: baseDeployer,
                directory: _directory,
                permissions: _permissions,
                tokens: _tokens,
                feeProjectId: 1,
                registry: _suckerRegistry,
                trustedForwarder: _trustedForwarder
            });
            baseDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(baseDeployer));
            _baseSuckerDeployer = IJBSuckerDeployer(address(baseDeployer));
        }
    }

    function _deploySuckersArbitrum() internal {
        // L1
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            JBArbitrumSuckerDeployer arbDeployer = new JBArbitrumSuckerDeployer{salt: ARB_SALT}({
                directory: _directory,
                permissions: _permissions,
                tokens: _tokens,
                configurator: safeAddress(),
                trustedForwarder: _trustedForwarder
            });

            arbDeployer.setChainSpecificConstants({
                layer: JBLayer.L1,
                inbox: IInbox(block.chainid == 1 ? ARBAddresses.L1_ETH_INBOX : ARBAddresses.L1_SEP_INBOX),
                gatewayRouter: IArbGatewayRouter(
                    block.chainid == 1 ? ARBAddresses.L1_GATEWAY_ROUTER : ARBAddresses.L1_SEP_GATEWAY_ROUTER
                )
            });

            JBArbitrumSucker singleton = new JBArbitrumSucker{salt: ARB_SALT}({
                deployer: arbDeployer,
                directory: _directory,
                permissions: _permissions,
                tokens: _tokens,
                feeProjectId: 1,
                registry: _suckerRegistry,
                trustedForwarder: _trustedForwarder
            });
            arbDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(arbDeployer));
            _arbitrumSuckerDeployer = IJBSuckerDeployer(address(arbDeployer));
        }

        // L2: Arbitrum / Arbitrum Sepolia
        if (block.chainid == 42_161 || block.chainid == 421_614) {
            JBArbitrumSuckerDeployer arbDeployer = new JBArbitrumSuckerDeployer{salt: ARB_SALT}({
                directory: _directory,
                permissions: _permissions,
                tokens: _tokens,
                configurator: safeAddress(),
                trustedForwarder: _trustedForwarder
            });

            // inbox=address(0) is correct on L2. The Arbitrum inbox is only used on L1 to send
            // retryable tickets. The deployer's validation in nana-suckers-v6 is layer-aware and
            // accepts address(0) when layer == JBLayer.L2.
            arbDeployer.setChainSpecificConstants({
                layer: JBLayer.L2,
                inbox: IInbox(address(0)),
                gatewayRouter: IArbGatewayRouter(
                    block.chainid == 42_161 ? ARBAddresses.L2_GATEWAY_ROUTER : ARBAddresses.L2_SEP_GATEWAY_ROUTER
                )
            });

            JBArbitrumSucker singleton = new JBArbitrumSucker{salt: ARB_SALT}({
                deployer: arbDeployer,
                directory: _directory,
                permissions: _permissions,
                tokens: _tokens,
                feeProjectId: 1,
                registry: _suckerRegistry,
                trustedForwarder: _trustedForwarder
            });
            arbDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(arbDeployer));
            _arbitrumSuckerDeployer = IJBSuckerDeployer(address(arbDeployer));
        }
    }

    function _deploySuckersCCIP() internal {
        // L1: Deploy CCIP suckers for OP, Base, Arb
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            _preApprovedSuckerDeployers.push(
                address(_deployCCIPSuckerFor(OP_SALT, block.chainid == 1 ? CCIPHelper.OP_ID : CCIPHelper.OP_SEP_ID))
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _deployCCIPSuckerFor(BASE_SALT, block.chainid == 1 ? CCIPHelper.BASE_ID : CCIPHelper.BASE_SEP_ID)
                )
            );
            _preApprovedSuckerDeployers.push(
                address(_deployCCIPSuckerFor(ARB_SALT, block.chainid == 1 ? CCIPHelper.ARB_ID : CCIPHelper.ARB_SEP_ID))
            );
        }

        // Arbitrum / Arbitrum Sepolia
        if (block.chainid == 42_161 || block.chainid == 421_614) {
            _preApprovedSuckerDeployers.push(
                address(
                    _deployCCIPSuckerFor(ARB_SALT, block.chainid == 42_161 ? CCIPHelper.ETH_ID : CCIPHelper.ETH_SEP_ID)
                )
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _deployCCIPSuckerFor(ARB_OP_SALT, block.chainid == 42_161 ? CCIPHelper.OP_ID : CCIPHelper.OP_SEP_ID)
                )
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _deployCCIPSuckerFor(
                        ARB_BASE_SALT, block.chainid == 42_161 ? CCIPHelper.BASE_ID : CCIPHelper.BASE_SEP_ID
                    )
                )
            );
        }
        // Optimism / Optimism Sepolia
        else if (block.chainid == 10 || block.chainid == 11_155_420) {
            _preApprovedSuckerDeployers.push(
                address(_deployCCIPSuckerFor(OP_SALT, block.chainid == 10 ? CCIPHelper.ETH_ID : CCIPHelper.ETH_SEP_ID))
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _deployCCIPSuckerFor(ARB_OP_SALT, block.chainid == 10 ? CCIPHelper.ARB_ID : CCIPHelper.ARB_SEP_ID)
                )
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _deployCCIPSuckerFor(
                        OP_BASE_SALT, block.chainid == 10 ? CCIPHelper.BASE_ID : CCIPHelper.BASE_SEP_ID
                    )
                )
            );
        }
        // Base / Base Sepolia
        else if (block.chainid == 8453 || block.chainid == 84_532) {
            _preApprovedSuckerDeployers.push(
                address(
                    _deployCCIPSuckerFor(BASE_SALT, block.chainid == 8453 ? CCIPHelper.ETH_ID : CCIPHelper.ETH_SEP_ID)
                )
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _deployCCIPSuckerFor(OP_BASE_SALT, block.chainid == 8453 ? CCIPHelper.OP_ID : CCIPHelper.OP_SEP_ID)
                )
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _deployCCIPSuckerFor(
                        ARB_BASE_SALT, block.chainid == 8453 ? CCIPHelper.ARB_ID : CCIPHelper.ARB_SEP_ID
                    )
                )
            );
        }
    }

    function _deployCCIPSuckerFor(bytes32 salt, uint256 remoteChainId)
        internal
        returns (JBCCIPSuckerDeployer deployer)
    {
        deployer = new JBCCIPSuckerDeployer{salt: salt}(
            _directory, _permissions, _tokens, safeAddress(), _trustedForwarder
        );

        deployer.setChainSpecificConstants(
            remoteChainId,
            CCIPHelper.selectorOfChain(remoteChainId),
            ICCIPRouter(CCIPHelper.routerOfChain(block.chainid))
        );

        JBCCIPSucker singleton = new JBCCIPSucker{salt: salt}({
            deployer: deployer,
            directory: _directory,
            tokens: _tokens,
            permissions: _permissions,
            feeProjectId: 1,
            registry: _suckerRegistry,
            trustedForwarder: _trustedForwarder
        });
        deployer.configureSingleton(singleton);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 04: Omnichain Deployer
    // ════════════════════════════════════════════════════════════════════

    function _deployOmnichainDeployer() internal {
        _omnichainDeployer = new JBOmnichainDeployer{salt: OMNICHAIN_DEPLOYER_SALT}(
            _suckerRegistry, IJB721TiersHookDeployer(address(_hookDeployer)), _permissions, _projects, _trustedForwarder
        );
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 05: Periphery (Controller + Price Feeds + Deadlines)
    // ════════════════════════════════════════════════════════════════════

    function _deployPeriphery() internal {
        // Deploy ETH/USD price feed.
        IJBPriceFeed ethUsdFeed = _deployEthUsdFeed();
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
        _deployUsdcFeed();

        // Deploy deadlines.
        new JBDeadline3Hours{salt: DEADLINES_SALT}();
        new JBDeadline1Day{salt: DEADLINES_SALT}();
        new JBDeadline3Days{salt: DEADLINES_SALT}();
        new JBDeadline7Days{salt: DEADLINES_SALT}();

        // Deploy the Controller — uses the omnichain deployer address.
        _controller = new JBController{salt: keccak256(abi.encode(CORE_DEPLOYMENT_NONCE))}({
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

    function _deployEthUsdFeed() internal returns (IJBPriceFeed feed) {
        uint256 L2GracePeriod = 3600 seconds;

        // Ethereum Mainnet
        if (block.chainid == 1) {
            feed = new JBChainlinkV3PriceFeed{salt: USD_NATIVE_FEED_SALT}(
                AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419), 3600 seconds
            );
        }
        // Ethereum Sepolia
        else if (block.chainid == 11_155_111) {
            feed = new JBChainlinkV3PriceFeed{salt: USD_NATIVE_FEED_SALT}(
                AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306), 3600 seconds
            );
        }
        // Optimism
        else if (block.chainid == 10) {
            feed = new JBChainlinkV3SequencerPriceFeed{salt: USD_NATIVE_FEED_SALT}(
                AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5),
                3600 seconds,
                AggregatorV2V3Interface(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389),
                L2GracePeriod
            );
        }
        // Optimism Sepolia
        else if (block.chainid == 11_155_420) {
            feed = new JBChainlinkV3PriceFeed{salt: USD_NATIVE_FEED_SALT}(
                AggregatorV3Interface(0x61Ec26aA57019C486B10502285c5A3D4A4750AD7), 3600 seconds
            );
        }
        // Base
        else if (block.chainid == 8453) {
            feed = new JBChainlinkV3SequencerPriceFeed{salt: USD_NATIVE_FEED_SALT}(
                AggregatorV3Interface(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70),
                3600 seconds,
                AggregatorV2V3Interface(0xBCF85224fc0756B9Fa45aA7892530B47e10b6433),
                L2GracePeriod
            );
        }
        // Base Sepolia
        // Verified: 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1 is the Chainlink ETH/USD feed on Base Sepolia
        // (description() returns "ETH / USD", 8 decimals, actively updated).
        else if (block.chainid == 84_532) {
            feed = new JBChainlinkV3PriceFeed{salt: USD_NATIVE_FEED_SALT}(
                AggregatorV3Interface(0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1), 3600 seconds
            );
        }
        // Arbitrum
        else if (block.chainid == 42_161) {
            feed = new JBChainlinkV3SequencerPriceFeed{salt: USD_NATIVE_FEED_SALT}(
                AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
                3600 seconds,
                AggregatorV2V3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D),
                L2GracePeriod
            );
        }
        // Arbitrum Sepolia
        else if (block.chainid == 421_614) {
            feed = new JBChainlinkV3PriceFeed{salt: USD_NATIVE_FEED_SALT}(
                AggregatorV3Interface(0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165), 3600 seconds
            );
        } else {
            revert("Unsupported chain for ETH/USD feed");
        }
    }

    function _deployUsdcFeed() internal {
        uint256 L2GracePeriod = 3600 seconds;
        IJBPriceFeed usdcFeed;
        address usdc;

        if (block.chainid == 1) {
            usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            usdcFeed = new JBChainlinkV3PriceFeed(
                AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6), 86_400 seconds
            );
        } else if (block.chainid == 11_155_111) {
            usdc = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
            usdcFeed = new JBChainlinkV3PriceFeed(
                AggregatorV3Interface(0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E), 86_400 seconds
            );
        } else if (block.chainid == 10) {
            usdc = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
            usdcFeed = new JBChainlinkV3SequencerPriceFeed({
                feed: AggregatorV3Interface(0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3),
                threshold: 86_400 seconds,
                sequencerFeed: AggregatorV2V3Interface(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389),
                gracePeriod: L2GracePeriod
            });
        } else if (block.chainid == 11_155_420) {
            usdc = 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;
            usdcFeed = new JBChainlinkV3PriceFeed(
                AggregatorV3Interface(0x6e44e50E3cc14DD16e01C590DC1d7020cb36eD4C), 86_400 seconds
            );
        } else if (block.chainid == 8453) {
            usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
            usdcFeed = new JBChainlinkV3SequencerPriceFeed({
                feed: AggregatorV3Interface(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B),
                threshold: 86_400 seconds,
                sequencerFeed: AggregatorV2V3Interface(0xBCF85224fc0756B9Fa45aA7892530B47e10b6433),
                gracePeriod: L2GracePeriod
            });
        } else if (block.chainid == 84_532) {
            usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
            // Base Sepolia USDC/USD Chainlink feed.
            // Verified at https://docs.chain.link/data-feeds/price-feeds/addresses?network=base&networkType=testnet
            usdcFeed = new JBChainlinkV3PriceFeed(
                AggregatorV3Interface(0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165), 86_400 seconds
            );
        } else if (block.chainid == 42_161) {
            usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
            usdcFeed = new JBChainlinkV3SequencerPriceFeed({
                feed: AggregatorV3Interface(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3),
                threshold: 86_400 seconds,
                sequencerFeed: AggregatorV2V3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D),
                gracePeriod: L2GracePeriod
            });
        } else if (block.chainid == 421_614) {
            usdc = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
            usdcFeed = new JBChainlinkV3PriceFeed(
                AggregatorV3Interface(0x0153002d20B96532C639313c2d54c3dA09109309), 86_400 seconds
            );
        } else {
            revert("Unsupported chain for USDC feed");
        }

        _prices.addPriceFeedFor({
            projectId: 0, pricingCurrency: JBCurrencyIds.USD, unitCurrency: uint32(uint160(usdc)), feed: usdcFeed
        });
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 06: Croptop
    // ════════════════════════════════════════════════════════════════════

    function _deployCroptop() internal {
        // Create CPN project (project 2).
        _cpnProjectId = _projects.createFor(safeAddress());

        _ctPublisher =
            new CTPublisher{salt: CT_PUBLISHER_SALT}(_directory, _permissions, _cpnProjectId, _trustedForwarder);

        _ctDeployer = new CTDeployer{salt: CT_DEPLOYER_SALT}(
            _permissions,
            _projects,
            IJB721TiersHookDeployer(address(_hookDeployer)),
            _ctPublisher,
            _suckerRegistry,
            _trustedForwarder
        );

        _ctProjectOwner = new CTProjectOwner{salt: CT_PROJECT_OWNER_SALT}(_permissions, _projects, _ctPublisher);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 07: Revnet (REVLoans + REVDeployer + $REV)
    // ════════════════════════════════════════════════════════════════════

    function _deployRevnet() internal {
        // Create the $REV project.
        _revProjectId = _projects.createFor(safeAddress());

        // Deploy REVLoans.
        _revLoans = new REVLoans{salt: REV_LOANS_SALT}({
            controller: _controller,
            projects: _projects,
            revId: _revProjectId,
            owner: safeAddress(),
            permit2: _PERMIT2,
            trustedForwarder: _trustedForwarder
        });

        // Deploy REVDeployer.
        _revDeployer = new REVDeployer{salt: REV_DEPLOYER_SALT}(
            _controller,
            _suckerRegistry,
            _revProjectId,
            IJB721TiersHookDeployer(address(_hookDeployer)),
            _ctPublisher,
            IJBBuybackHookRegistry(address(_buybackRegistry)),
            address(_revLoans),
            _trustedForwarder
        );

        // Approve the deployer to configure the $REV project.
        _projects.approve(address(_revDeployer), _revProjectId);

        // Configure the $REV revnet.
        _deployRevFeeProject();
    }

    function _deployRevFeeProject() internal {
        address operator = 0x6b92c73682f0e1fac35A18ab17efa5e77DDE9fE1;

        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] =
            JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: DECIMALS, currency: NATIVE_CURRENCY});

        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](2);
        terminalConfigs[0] = JBTerminalConfig({terminal: _terminal, accountingContextsToAccept: accountingContexts});
        terminalConfigs[1] = JBTerminalConfig({
            terminal: IJBTerminal(address(_routerTerminalRegistry)),
            accountingContextsToAccept: new JBAccountingContext[](0)
        });

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(operator),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        REVStageConfig[] memory stages = new REVStageConfig[](3);

        {
            REVAutoIssuance[] memory autoIssuances = new REVAutoIssuance[](4);
            autoIssuances[0] = REVAutoIssuance({chainId: 1, count: REV_MAINNET_AUTO_ISSUANCE, beneficiary: operator});
            autoIssuances[1] = REVAutoIssuance({chainId: 8453, count: REV_BASE_AUTO_ISSUANCE, beneficiary: operator});
            autoIssuances[2] = REVAutoIssuance({chainId: 10, count: REV_OP_AUTO_ISSUANCE, beneficiary: operator});
            autoIssuances[3] = REVAutoIssuance({chainId: 42_161, count: REV_ARB_AUTO_ISSUANCE, beneficiary: operator});

            stages[0] = REVStageConfig({
                startsAtOrAfter: REV_START_TIME,
                autoIssuances: autoIssuances,
                splitPercent: 3800,
                splits: splits,
                initialIssuance: uint112(10_000 * DECIMAL_MULTIPLIER),
                issuanceCutFrequency: 90 days,
                issuanceCutPercent: 380_000_000,
                cashOutTaxRate: 1000,
                extraMetadata: 4
            });
        }

        {
            REVAutoIssuance[] memory autoIssuances = new REVAutoIssuance[](1);
            autoIssuances[0] = REVAutoIssuance({
                chainId: PREMINT_CHAIN_ID, count: uint104(1_550_000 * DECIMAL_MULTIPLIER), beneficiary: operator
            });

            stages[1] = REVStageConfig({
                startsAtOrAfter: uint40(stages[0].startsAtOrAfter + 720 days),
                autoIssuances: autoIssuances,
                splitPercent: 3800,
                splits: splits,
                initialIssuance: 1,
                issuanceCutFrequency: 30 days,
                issuanceCutPercent: 70_000_000,
                cashOutTaxRate: 1000,
                extraMetadata: 4
            });
        }

        stages[2] = REVStageConfig({
            startsAtOrAfter: uint40(stages[1].startsAtOrAfter + 3600 days),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 3800,
            splits: splits,
            initialIssuance: 0,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: 1000,
            extraMetadata: 4
        });

        REVConfig memory revConfig = REVConfig({
            description: REVDescription(
                "Revnet", "REV", "ipfs://QmcCBD5fM927LjkLDSJWtNEU9FohcbiPSfqtGRHXFHzJ4W", REV_ERC20_SALT
            ),
            baseCurrency: ETH_CURRENCY,
            splitOperator: operator,
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory suckerConfig = _buildSuckerConfig(REV_SUCKER_SALT);

        _revDeployer.deployFor({
            revnetId: _revProjectId,
            configuration: revConfig,
            terminalConfigurations: terminalConfigs,
            suckerDeploymentConfiguration: suckerConfig
        });
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 08a: CPN Revnet (project ID 2)
    // ════════════════════════════════════════════════════════════════════

    function _deployCpnRevnet() internal {
        address operator = 0x240dc2085caEF779F428dcd103CFD2fB510EdE82;

        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] =
            JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: DECIMALS, currency: NATIVE_CURRENCY});

        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](2);
        terminalConfigs[0] = JBTerminalConfig({terminal: _terminal, accountingContextsToAccept: accountingContexts});
        terminalConfigs[1] = JBTerminalConfig({
            terminal: IJBTerminal(address(_routerTerminalRegistry)),
            accountingContextsToAccept: new JBAccountingContext[](0)
        });

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(operator),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        REVStageConfig[] memory stages = new REVStageConfig[](3);

        {
            REVAutoIssuance[] memory autoIssuances = new REVAutoIssuance[](4);
            autoIssuances[0] = REVAutoIssuance({chainId: 1, count: CPN_MAINNET_AUTO_ISSUANCE, beneficiary: operator});
            autoIssuances[1] = REVAutoIssuance({chainId: 10, count: CPN_OP_AUTO_ISSUANCE, beneficiary: operator});
            autoIssuances[2] = REVAutoIssuance({chainId: 8453, count: CPN_BASE_AUTO_ISSUANCE, beneficiary: operator});
            autoIssuances[3] = REVAutoIssuance({chainId: 42_161, count: CPN_ARB_AUTO_ISSUANCE, beneficiary: operator});

            stages[0] = REVStageConfig({
                startsAtOrAfter: CPN_START_TIME,
                autoIssuances: autoIssuances,
                splitPercent: 3800,
                splits: splits,
                initialIssuance: uint112(10_000 * DECIMAL_MULTIPLIER),
                issuanceCutFrequency: 120 days,
                issuanceCutPercent: 380_000_000,
                cashOutTaxRate: 1000,
                extraMetadata: 4
            });
        }

        stages[1] = REVStageConfig({
            startsAtOrAfter: uint40(stages[0].startsAtOrAfter + 720 days),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 3800,
            splits: splits,
            initialIssuance: 1,
            issuanceCutFrequency: 30 days,
            issuanceCutPercent: 70_000_000,
            cashOutTaxRate: 1000,
            extraMetadata: 4
        });

        stages[2] = REVStageConfig({
            startsAtOrAfter: uint40(stages[1].startsAtOrAfter + 3800 days),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 3800,
            splits: splits,
            initialIssuance: 0,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: 1000,
            extraMetadata: 4
        });

        REVConfig memory cpnConfig = REVConfig({
            description: REVDescription({
                name: "Croptop Publishing Network",
                ticker: "CPN",
                uri: "ipfs://QmUAFevoMn1iqSEQR8LogQYRxm39TNxQTPYnuLuq5BmfEi",
                salt: CPN_ERC20_SALT
            }),
            baseCurrency: ETH_CURRENCY,
            splitOperator: operator,
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory suckerConfig = _buildSuckerConfig(CPN_SUCKER_SALT);

        REVDeploy721TiersHookConfig memory hookConfig = REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "Croptop Publishing Network",
                symbol: "CPN",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: "",
                tiersConfig: JB721InitTiersConfig({
                    tiers: new JB721TierConfig[](0), currency: ETH_CURRENCY, decimals: DECIMALS
                }),
                reserveBeneficiary: address(0),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: true,
                    noNewTiersWithOwnerMinting: true,
                    preventOverspending: false
                })
            }),
            salt: CPN_HOOK_SALT,
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });

        REVCroptopAllowedPost[] memory allowedPosts = new REVCroptopAllowedPost[](5);
        allowedPosts[0] = REVCroptopAllowedPost({
            category: 0,
            minimumPrice: uint104(10 ** (DECIMALS - 5)),
            minimumTotalSupply: 10_000,
            maximumTotalSupply: 999_999_999,
            maximumSplitPercent: 0,
            allowedAddresses: new address[](0)
        });
        allowedPosts[1] = REVCroptopAllowedPost({
            category: 1,
            minimumPrice: uint104(10 ** (DECIMALS - 3)),
            minimumTotalSupply: 10_000,
            maximumTotalSupply: 999_999_999,
            maximumSplitPercent: 0,
            allowedAddresses: new address[](0)
        });
        allowedPosts[2] = REVCroptopAllowedPost({
            category: 2,
            minimumPrice: uint104(10 ** (DECIMALS - 1)),
            minimumTotalSupply: 100,
            maximumTotalSupply: 999_999_999,
            maximumSplitPercent: 0,
            allowedAddresses: new address[](0)
        });
        allowedPosts[3] = REVCroptopAllowedPost({
            category: 3,
            minimumPrice: uint104(10 ** DECIMALS),
            minimumTotalSupply: 10,
            maximumTotalSupply: 999_999_999,
            maximumSplitPercent: 0,
            allowedAddresses: new address[](0)
        });
        allowedPosts[4] = REVCroptopAllowedPost({
            category: 4,
            minimumPrice: uint104(10 ** (DECIMALS + 2)),
            minimumTotalSupply: 10,
            maximumTotalSupply: 999_999_999,
            maximumSplitPercent: 0,
            allowedAddresses: new address[](0)
        });

        // Approve the deployer to configure CPN (project 2).
        _projects.approve(address(_revDeployer), _cpnProjectId);

        _revDeployer.deployFor({
            revnetId: _cpnProjectId,
            configuration: cpnConfig,
            terminalConfigurations: terminalConfigs,
            suckerDeploymentConfiguration: suckerConfig,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: allowedPosts
        });
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 08b: NANA Revnet (project ID 1)
    // ════════════════════════════════════════════════════════════════════

    function _deployNanaRevnet() internal {
        uint256 feeProjectId = 1;
        address operator = 0x80a8F7a4bD75b539CE26937016Df607fdC9ABeb5;

        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] =
            JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});

        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](2);
        terminalConfigs[0] = JBTerminalConfig({terminal: _terminal, accountingContextsToAccept: accountingContexts});
        terminalConfigs[1] = JBTerminalConfig({
            terminal: IJBTerminal(address(_routerTerminalRegistry)),
            accountingContextsToAccept: new JBAccountingContext[](0)
        });

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(operator),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        REVAutoIssuance[] memory autoIssuances = new REVAutoIssuance[](4);
        autoIssuances[0] = REVAutoIssuance({chainId: 1, count: NANA_MAINNET_AUTO_ISSUANCE, beneficiary: operator});
        autoIssuances[1] = REVAutoIssuance({chainId: 8453, count: NANA_BASE_AUTO_ISSUANCE, beneficiary: operator});
        autoIssuances[2] = REVAutoIssuance({chainId: 10, count: NANA_OP_AUTO_ISSUANCE, beneficiary: operator});
        autoIssuances[3] = REVAutoIssuance({chainId: 42_161, count: NANA_ARB_AUTO_ISSUANCE, beneficiary: operator});

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: NANA_START_TIME,
            autoIssuances: autoIssuances,
            splitPercent: 6200,
            splits: splits,
            initialIssuance: uint112(10_000 * DECIMAL_MULTIPLIER),
            issuanceCutFrequency: 360 days,
            issuanceCutPercent: 380_000_000,
            cashOutTaxRate: 1000,
            extraMetadata: 4
        });

        REVConfig memory nanaConfig = REVConfig({
            description: REVDescription({
                name: "Bananapus (Juicebox V6)",
                ticker: "NANA",
                uri: "ipfs://QmWCgCaryfsJYBu5LczFuBz3UKK5VEU3BZFYp2mHJTLeRQ",
                salt: NANA_ERC20_SALT
            }),
            baseCurrency: ETH_CURRENCY,
            splitOperator: operator,
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory suckerConfig = _buildSuckerConfig(NANA_SUCKER_SALT);

        // Approve the deployer to configure project ID 1.
        _projects.approve(address(_revDeployer), feeProjectId);

        _revDeployer.deployFor({
            revnetId: feeProjectId,
            configuration: nanaConfig,
            terminalConfigurations: terminalConfigs,
            suckerDeploymentConfiguration: suckerConfig
        });
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 09: Banny Network (project ID 4)
    // ════════════════════════════════════════════════════════════════════

    function _deployBanny() internal {
        address operator = 0x9E2a10aB3BD22831f19d02C648Bc2Cb49B127450;

        // Deploy the URI resolver.
        string memory bannyBody =
            '<g class="a1"><path d="M173 53h4v17h-4z"/></g><g class="a2"><path d="M167 57h3v10h-3z"/><path d="M169 53h4v17h-4z"/></g><g class="a3"><path d="M167 53h3v4h-3z"/><path d="M163 57h4v10h-4z"/><path d="M167 67h3v3h-3z"/></g><g class="b1"><path d="M213 253h-3v-3-3h-3v-7-3h-4v-10h-3v-7-7-3h-3v-73h-4v-10h-3v-10h-3v-7h-4v-7h-3v-3h-3v-3h-4v10h4v10h3v10h3v3h4v7 3 70 3h3v7h3v20h4v7h3v3h3v3h4v4h3v3h3v-3-4z"/><path d="M253 307v-4h-3v-3h-3v-3h-4v-4h-3v-3h-3v-3h-4v-4h-3v-3h-3v-3h-4v-4h-3v-6h-3v-7h-4v17h4v3h3v3h3 4v4h3v3h3v3h4v4h3v3h3v3h4v4h3v3h3v3h4v-6h-4z"/></g><g class="b2"><path d="M250 310v-3h-3v-4h-4v-3h-3v-3h-3v-4h-4v-3h-3v-3h-3v-4h-7v-3h-3v-3h-4v-17h-3v-3h-3v-4h-4v-3h-3v-3h-3v-7h-4v-20h-3v-7h-3v-73-3-7h-4v-3h-3v-10h-3v-10h-4V70h-3v-3l-3 100 3-100v40h-3v10h-4v6h-3v14h-3v3 13h-4v44h4v16h3v14h3v13h4v10h3v7h3v3h4v3h3v4h3v3h4v3h3v4h3v3h4v3h3v7h7v7h6v3h7v3h7v4h13v3h3v3h10v-3h-3zm-103-87v-16h3v-10h-3v6h-4v17h-3v10h3v-7h4z"/><path d="M143 230h4v7h-4zm4 10h3v3h-3zm3 7h3v3h-3zm3 6h4v4h-4z"/><path d="M163 257h-6v3h3v3h3v4h4v-4-3h-4v-3z"/></g><g class="b3"><path d="M143 197v6h4v-6h6v-44h4v-16h3v-14h3v-6h4v-10h3V97h-7v6h-3v4h-3v3h-4v3h-3v4 3h-3v3 4h-4v10h-3v16 4h-3v46h3v-6h3z"/><path d="M140 203h3v17h-3z"/><path d="M137 220h3v10h-3z"/><path d="M153 250h-3v-7h-3v-6h-4v-7h-3v10h3v7h4v6h3v4h3v-7zm-3 10h3v7h-3z"/><path d="M147 257h3v3h-3zm6 0h4v3h-4z"/><path d="M160 263v-3h-3v3 7h6v-7h-3zm-10-56v16h-3v7h3v10h3v7h4v6h6v4h7v-4-3h-3v-10h-4v-13h-3v-14h-3v-16h-4v10h-3z"/><path d="M243 313v-3h-3v-3h-10-3v-4h-7v-3h-7v-3h-6v-7h-7v-7h-3v-3h-4v-3h-3v-4h-3v-3h-4v-3h-3v-4h-3v-3h-4v-3h-3v10h-3v3h-4v3h-3v7h3v7h4v6h3v5h4v3h6v3h3v3h4 3v3h3 4v3h3 3v4h10v3h7 7 3v3h10 3v-3h10v-3h4v-4h-14z"/></g><g class="b4"><path d="M183 130h4v7h-4z"/><path d="M180 127h3v3h-3zm-27-4h4v7h-4z"/><path d="M157 117h3v6h-3z"/><path d="M160 110h3v7h-3z"/><path d="M163 107h4v3h-4zm-3 83h3v7h-3z"/><path d="M163 187h4v3h-4zm20 0h7v3h-7z"/><path d="M180 190h3v3h-3zm10-7h3v4h-3z"/><path d="M193 187h4v6h-4zm-20 53h4v7h-4z"/><path d="M177 247h3v6h-3z"/><path d="M180 253h3v7h-3z"/><path d="M183 260h7v3h-7z"/><path d="M190 263h3v4h-3zm0-20h3v4h-3z"/><path d="M187 240h3v3h-3z"/><path d="M190 237h3v3h-3zm13 23h4v3h-4z"/><path d="M207 263h3v7h-3z"/><path d="M210 270h3v3h-3zm-10 7h3v6h-3z"/><path d="M203 283h4v7h-4z"/><path d="M207 290h6v3h-6z"/></g><g class="o"><path d="M133 157h4v50h-4zm0 63h4v10h-4zm27-163h3v10h-3z"/><path d="M163 53h4v4h-4z"/><path d="M167 50h10v3h-10z"/><path d="M177 53h3v17h-3z"/><path d="M173 70h4v27h-4zm-6 0h3v27h-3z"/><path d="M163 67h4v3h-4zm0 30h4v3h-4z"/><path d="M160 100h3v3h-3z"/><path d="M157 103h3v4h-3z"/><path d="M153 107h4v3h-4z"/><path d="M150 110h3v3h-3z"/><path d="M147 113h3v7h-3z"/><path d="M143 120h4v7h-4z"/><path d="M140 127h3v10h-3z"/><path d="M137 137h3v20h-3zm56-10h4v10h-4z"/><path d="M190 117h3v10h-3z"/><path d="M187 110h3v7h-3z"/><path d="M183 103h4v7h-4z"/><path d="M180 100h3v3h-3z"/><path d="M177 97h3v3h-3zm-40 106h3v17h-3zm0 27h3v10h-3zm10 30h3v7h-3z"/><path d="M150 257v-4h-3v-6h-4v-7h-3v10h3v10h4v-3h3z"/><path d="M150 257h3v3h-3z"/><path d="M163 273v-3h-6v-10h-4v7h-3v3h3v3h4v7h3v-7h3z"/><path d="M163 267h4v3h-4z"/><path d="M170 257h-3-4v3h4v7h3v-10z"/><path d="M157 253h6v4h-6z"/><path d="M153 247h4v6h-4z"/><path d="M150 240h3v7h-3z"/><path d="M147 230h3v10h-3zm13 50h3v7h-3z"/><path d="M143 223h4v7h-4z"/><path d="M147 207h3v16h-3z"/><path d="M150 197h3v10h-3zm-10 0h3v6h-3zm50 113h7v3h-7zm23 10h17v3h-17z"/><path d="M230 323h13v4h-13z"/><path d="M243 320h10v3h-10z"/><path d="M253 317h4v3h-4z"/><path d="M257 307h3v10h-3z"/><path d="M253 303h4v4h-4z"/><path d="M250 300h3v3h-3z"/><path d="M247 297h3v3h-3z"/><path d="M243 293h4v4h-4z"/><path d="M240 290h3v3h-3z"/><path d="M237 287h3v3h-3z"/><path d="M233 283h4v4h-4z"/><path d="M230 280h3v3h-3z"/><path d="M227 277h3v3h-3z"/><path d="M223 273h4v4h-4z"/><path d="M220 267h3v6h-3z"/><path d="M217 260h3v7h-3z"/><path d="M213 253h4v7h-4z"/><path d="M210 247h3v6h-3z"/><path d="M207 237h3v10h-3z"/><path d="M203 227h4v10h-4zm-40 60h4v6h-4zm24 20h3v3h-3z"/><path d="M167 293h3v5h-3zm16 14h4v3h-4z"/><path d="M170 298h4v3h-4zm10 6h3v3h-3z"/><path d="M174 301h6v3h-6zm23 12h6v4h-6z"/><path d="M203 317h10v3h-10zm-2-107v-73h-4v73h3v17h3v-17h-2z"/></g><g class="o"><path d="M187 307v-4h3v-6h-3v-4h-4v-3h-3v-3h-7v-4h-6v4h-4v3h4v27h-4v13h-3v10h-4v7h4v3h3 10 14v-3h-4v-4h-3v-3h-3v-3h-4v-7h4v-10h3v-7h3v-3h7v-3h-3zm16 10v-4h-6v17h-4v10h-3v7h3v3h4 6 4 3 14v-3h-4v-4h-7v-3h-3v-3h-3v-10h3v-7h3v-3h-10z"/></g>';
        string memory defaultNecklace =
            '<g class="o"><path d="M190 173h-37v-3h-10v-4h-6v4h3v3h-3v4h6v3h10v4h37v-4h3v-3h-3v-4zm-40 4h-3v-4h3v4zm7 3v-3h3v3h-3zm6 0v-3h4v3h-4zm7 0v-3h3v3h-3zm7 0v-3h3v3h-3zm10 0h-4v-3h4v3z"/><path d="M190 170h3v3h-3z"/><path d="M193 166h4v4h-4zm0 7h4v4h-4z"/></g><g class="w"><path d="M137 170h3v3h-3zm10 3h3v4h-3zm10 4h3v3h-3zm6 0h4v3h-4zm7 0h3v3h-3zm7 0h3v3h-3zm6 0h4v3h-4zm7-4h3v4h-3z"/><path d="M193 170h4v3h-4z"/></g>';
        string memory defaultMouth =
            '<g class="o"><path d="M183 160v-4h-20v4h-3v3h3v4h24v-7h-4zm-13 3v-3h10v3h-10z" fill="#ad71c8"/><path d="M170 160h10v3h-10z"/></g>';
        string memory defaultStandardEyes =
            '<g class="o"><path d="M177 140v3h6v11h10v-11h4v-3h-20z"/><path d="M153 140v3h7v8 3h7 3v-11h3v-3h-20z"/></g><g class="w"><path d="M153 143h7v4h-7z"/><path d="M157 147h3v3h-3zm20-4h6v4h-6z"/><path d="M180 147h3v3h-3z"/></g>';
        string memory defaultAlienEyes =
            '<g class="o"><path d="M190 127h3v3h-3zm3 13h4v3h-4zm-42 0h6v6h-6z"/><path d="M151 133h3v7h-3zm10 0h6v4h-6z"/><path d="M157 137h17v6h-17zm3 13h14v3h-14zm17-13h7v16h-7z"/><path d="M184 137h6v6h-6zm0 10h10v6h-10z"/><path d="M187 143h10v4h-10z"/><path d="M190 140h3v3h-3zm-6-10h3v7h-3z"/><path d="M187 130h6v3h-6zm-36 0h10v3h-10zm16 13h7v7h-7zm-10 0h7v7h-7z"/><path d="M164 147h3v3h-3zm29-20h4v6h-4z"/><path d="M194 133h3v7h-3z"/></g><g class="w"><path d="M154 133h7v4h-7z"/><path d="M154 137h3v3h-3zm10 6h3v4h-3zm20 0h3v4h-3zm3-10h7v4h-7z"/><path d="M190 137h4v3h-4z"/></g>';

        Banny721TokenUriResolver resolver = new Banny721TokenUriResolver{salt: BAN_RESOLVER_SALT}(
            bannyBody, defaultNecklace, defaultMouth, defaultStandardEyes, defaultAlienEyes, operator, _trustedForwarder
        );

        resolver.setMetadata(
            "A piece of Banny Retail.", "https://retail.banny.eth.shop", "https://bannyverse.infura-ipfs.io/ipfs/"
        );

        // Build the Banny revnet config.
        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] =
            JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: DECIMALS, currency: NATIVE_CURRENCY});

        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](2);
        terminalConfigs[0] = JBTerminalConfig({terminal: _terminal, accountingContextsToAccept: accountingContexts});
        terminalConfigs[1] = JBTerminalConfig({
            terminal: IJBTerminal(address(_routerTerminalRegistry)),
            accountingContextsToAccept: new JBAccountingContext[](0)
        });

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(operator),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        REVStageConfig[] memory stages = new REVStageConfig[](3);

        {
            REVAutoIssuance[] memory autoIssuances = new REVAutoIssuance[](4);
            autoIssuances[0] = REVAutoIssuance({chainId: 1, count: BAN_MAINNET_AUTO_ISSUANCE, beneficiary: operator});
            autoIssuances[1] = REVAutoIssuance({chainId: 8453, count: BAN_BASE_AUTO_ISSUANCE, beneficiary: operator});
            autoIssuances[2] = REVAutoIssuance({chainId: 10, count: BAN_OP_AUTO_ISSUANCE, beneficiary: operator});
            autoIssuances[3] = REVAutoIssuance({chainId: 42_161, count: BAN_ARB_AUTO_ISSUANCE, beneficiary: operator});

            stages[0] = REVStageConfig({
                startsAtOrAfter: BAN_START_TIME,
                autoIssuances: autoIssuances,
                splitPercent: 3800,
                splits: splits,
                initialIssuance: uint112(10_000 * DECIMAL_MULTIPLIER),
                issuanceCutFrequency: 60 days,
                issuanceCutPercent: 380_000_000,
                cashOutTaxRate: 1000,
                extraMetadata: 4
            });
        }

        {
            REVAutoIssuance[] memory autoIssuances = new REVAutoIssuance[](1);
            autoIssuances[0] = REVAutoIssuance({
                chainId: PREMINT_CHAIN_ID, count: uint104(1_000_000 * DECIMAL_MULTIPLIER), beneficiary: operator
            });

            stages[1] = REVStageConfig({
                startsAtOrAfter: uint40(stages[0].startsAtOrAfter + 360 days),
                autoIssuances: autoIssuances,
                splitPercent: 3800,
                splits: splits,
                initialIssuance: 1,
                issuanceCutFrequency: 21 days,
                issuanceCutPercent: 70_000_000,
                cashOutTaxRate: 1000,
                extraMetadata: 4
            });
        }

        stages[2] = REVStageConfig({
            startsAtOrAfter: uint40(stages[1].startsAtOrAfter + 1200 days),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 0,
            splits: splits,
            initialIssuance: 0,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: 1000,
            extraMetadata: 4
        });

        REVConfig memory banConfig = REVConfig({
            description: REVDescription(
                "Banny Network", "BAN", "ipfs://Qme34ww9HuwnsWF6sYDpDfpSdYHpPCGsEyJULk1BikCVYp", BAN_ERC20_SALT
            ),
            baseCurrency: ETH_CURRENCY,
            splitOperator: operator,
            stageConfigurations: stages
        });

        // Build 721 tiers.
        JB721TierConfig[] memory tiers = new JB721TierConfig[](4);
        uint24 bannyBodyCategory = 0;

        tiers[0] = JB721TierConfig({
            price: uint104(1 * (10 ** DECIMALS)),
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32(""),
            category: bannyBodyCategory,
            discountPercent: 0,
            cannotIncreaseDiscountPercent: true,
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: true,
            splitPercent: 0,
            splits: new JBSplit[](0)
        });
        tiers[1] = JB721TierConfig({
            price: uint104(1 * (10 ** (DECIMALS - 1))),
            initialSupply: 1000,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32(""),
            category: bannyBodyCategory,
            discountPercent: 0,
            cannotIncreaseDiscountPercent: true,
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: true,
            splitPercent: 0,
            splits: new JBSplit[](0)
        });
        tiers[2] = JB721TierConfig({
            price: uint104(1 * (10 ** (DECIMALS - 2))),
            initialSupply: 10_000,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32(""),
            category: bannyBodyCategory,
            discountPercent: 0,
            cannotIncreaseDiscountPercent: true,
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: true,
            splitPercent: 0,
            splits: new JBSplit[](0)
        });
        tiers[3] = JB721TierConfig({
            price: uint104(1 * (10 ** (DECIMALS - 4))),
            initialSupply: 999_999_999,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32(""),
            category: bannyBodyCategory,
            discountPercent: 0,
            cannotIncreaseDiscountPercent: true,
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: true,
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        REVSuckerDeploymentConfig memory suckerConfig = _buildSuckerConfig(BAN_SUCKER_SALT);

        REVDeploy721TiersHookConfig memory hookConfig = REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "Banny Retail",
                symbol: "BANNY",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(resolver)),
                contractUri: "https://jbm.infura-ipfs.io/ipfs/Qmd2hgb1E4caEB51VvoC3GvonhwkCoVyXjJ3zqsCxHPTKK",
                tiersConfig: JB721InitTiersConfig({tiers: tiers, currency: ETH_CURRENCY, decimals: DECIMALS}),
                reserveBeneficiary: address(0),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            salt: BAN_HOOK_SALT,
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });

        // Deploy the $BAN revnet with 721 tiers (revnetId: 0 creates new project).
        _revDeployer.deployFor({
            revnetId: 0,
            configuration: banConfig,
            terminalConfigurations: terminalConfigs,
            suckerDeploymentConfiguration: suckerConfig,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });
    }

    // TODO: Defifa phases — add back when ready.

    // ════════════════════════════════════════════════════════════════════
    //  Helpers
    // ════════════════════════════════════════════════════════════════════

    /// @notice Builds a standard sucker deployment config for L1→L2 bridging.
    function _buildSuckerConfig(bytes32 salt) internal view returns (REVSuckerDeploymentConfig memory) {
        JBTokenMapping[] memory tokenMappings = new JBTokenMapping[](1);
        tokenMappings[0] = JBTokenMapping({
            localToken: JBConstants.NATIVE_TOKEN,
            minGas: 200_000,
            remoteToken: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
        });

        JBSuckerDeployerConfig[] memory suckerDeployerConfigs;
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            suckerDeployerConfigs = new JBSuckerDeployerConfig[](3);
            suckerDeployerConfigs[0] =
                JBSuckerDeployerConfig({deployer: _optimismSuckerDeployer, mappings: tokenMappings});
            suckerDeployerConfigs[1] = JBSuckerDeployerConfig({deployer: _baseSuckerDeployer, mappings: tokenMappings});
            suckerDeployerConfigs[2] =
                JBSuckerDeployerConfig({deployer: _arbitrumSuckerDeployer, mappings: tokenMappings});
        } else {
            suckerDeployerConfigs = new JBSuckerDeployerConfig[](1);
            // L2 -> L1: pick whichever deployer is non-zero for this chain.
            suckerDeployerConfigs[0] = JBSuckerDeployerConfig({
                deployer: address(_optimismSuckerDeployer) != address(0)
                    ? _optimismSuckerDeployer
                    : address(_baseSuckerDeployer) != address(0) ? _baseSuckerDeployer : _arbitrumSuckerDeployer,
                mappings: tokenMappings
            });
        }

        return REVSuckerDeploymentConfig({deployerConfigurations: suckerDeployerConfigs, salt: salt});
    }
}
