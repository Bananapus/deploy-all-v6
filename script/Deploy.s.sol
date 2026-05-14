// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Sphinx} from "@sphinx-labs/contracts/contracts/foundry/SphinxPlugin.sol";
import {Script, stdJson, VmSafe} from "forge-std/Script.sol";
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
import {IJB721TiersHookStore} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookStore.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {IJB721TokenUriResolver} from "@bananapus/721-hook-v6/src/interfaces/IJB721TokenUriResolver.sol";
import {JB721InitTiersConfig} from "@bananapus/721-hook-v6/src/structs/JB721InitTiersConfig.sol";
import {JB721TierConfig} from "@bananapus/721-hook-v6/src/structs/JB721TierConfig.sol";
import {JB721TierConfigFlags} from "@bananapus/721-hook-v6/src/structs/JB721TierConfigFlags.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHook} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHook.sol";
import {JB721CheckpointsDeployer} from "@bananapus/721-hook-v6/src/JB721CheckpointsDeployer.sol";
import {IJB721CheckpointsDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721CheckpointsDeployer.sol";

// ── Buyback Hook ──
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";
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
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {JBArbitrumSucker} from "@bananapus/suckers-v6/src/JBArbitrumSucker.sol";
import {JBBaseSucker} from "@bananapus/suckers-v6/src/JBBaseSucker.sol";
import {JBCCIPSucker} from "@bananapus/suckers-v6/src/JBCCIPSucker.sol";
import {JBOptimismSucker} from "@bananapus/suckers-v6/src/JBOptimismSucker.sol";
import {JBSwapCCIPSucker} from "@bananapus/suckers-v6/src/JBSwapCCIPSucker.sol";
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {JBArbitrumSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBArbitrumSuckerDeployer.sol";
import {JBBaseSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBBaseSuckerDeployer.sol";
import {JBCCIPSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBCCIPSuckerDeployer.sol";
import {JBOptimismSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBOptimismSuckerDeployer.sol";
import {JBSwapCCIPSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBSwapCCIPSuckerDeployer.sol";
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
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";

// ── Omnichain Deployer ──
import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";

// ── Croptop ──
import {CTDeployer} from "@croptop/core-v6/src/CTDeployer.sol";
import {CTProjectOwner} from "@croptop/core-v6/src/CTProjectOwner.sol";
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";

// ── Revnet ──
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";
import {IREVDeployer} from "@rev-net/core-v6/src/interfaces/IREVDeployer.sol";
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

// ── Defifa ──
import {ITypeface} from "lib/typeface/contracts/interfaces/ITypeface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DefifaHook} from "@ballkidz/defifa/src/DefifaHook.sol";
import {DefifaDeployer} from "@ballkidz/defifa/src/DefifaDeployer.sol";
import {DefifaGovernor} from "@ballkidz/defifa/src/DefifaGovernor.sol";
import {DefifaTokenUriResolver} from "@ballkidz/defifa/src/DefifaTokenUriResolver.sol";

// ── Project Handles ──
import {JBProjectHandles} from "@bananapus/project-handles-v6/src/JBProjectHandles.sol";

// ── Distributor ──
import {JB721Distributor} from "@bananapus/distributor-v6/src/JB721Distributor.sol";
import {JBTokenDistributor} from "@bananapus/distributor-v6/src/JBTokenDistributor.sol";

// ── Project Payer ──
import {JBProjectPayerDeployer} from "@bananapus/project-payer-v6/src/JBProjectPayerDeployer.sol";

/// @title Deploy — Juicebox V6 Ecosystem
/// @notice One-shot deployment of the entire Juicebox V6 ecosystem.
/// @dev Based on each source repo's Deploy.s.sol. Deploys everything in dependency order within a single Sphinx
/// proposal.
contract Deploy is Script, Sphinx {
    error Deploy_ExistingAddressMismatch(address expected, address actual);
    error Deploy_ProjectIdMismatch(uint256 expected, uint256 actual);
    error Deploy_ProjectNotOwned(uint256 projectId);
    error Deploy_ProjectNotCanonical(uint256 projectId);
    error Deploy_PriceFeedMismatch(uint256 projectId, uint256 pricingCurrency, uint256 unitCurrency);
    error Deploy_BannyProjectIdMismatch(uint256 actual, uint256 expected);
    error Deploy_UnexpectedSafe(address expected, address actual);

    // ════════════════════════════════════════════════════════════════════
    //  Constants
    // ════════════════════════════════════════════════════════════════════

    IPermit2 private constant _PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    /// @dev Deterministic deployment proxy (https://github.com/Arachnid/deterministic-deployment-proxy).
    address private constant _CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    string private constant TRUSTED_FORWARDER_NAME = "Juicebox";
    uint256 private constant CORE_DEPLOYMENT_NONCE = 6;

    /// @dev Canonical Sphinx Safe for the Juicebox V6 deployment. Derived from the Safe's owners +
    /// threshold + saltNonce 6 (see sphinx.lock). This is the address that:
    ///   (a) `safeAddress()` must resolve to during every deploy run, and
    ///   (b) will own NANA project #1 immediately after `_deployRevFeeProject` creates it.
    /// Any deploy run with a different Sphinx config produces a different `safeAddress()`, which
    /// would silently fork the deployment to attacker-controlled state. The assertion at the top
    /// of `run()` catches that misconfiguration before any side effects.
    address private constant _EXPECTED_SAFE = 0x80a8F7a4bD75b539CE26937016Df607fdC9ABeb5;

    // ── Tempo chain constants (until CCIPHelper is published with these) ──
    uint256 private constant TEMPO_CHAIN_ID = 4217;
    uint256 private constant TEMPO_MOD_CHAIN_ID = 42_431;
    uint64 private constant TEMPO_CCIP_SEL = 7_281_642_695_469_137_430;
    uint64 private constant TEMPO_MOD_CCIP_SEL = 8_457_817_439_310_187_923;
    address private constant TEMPO_CCIP_ROUTER = 0xa132F089492CcE5f1D79483a9e4552f37266ed01;
    address private constant TEMPO_MOD_CCIP_ROUTER = 0xD3e53cCEE3688aAEE5C9118ef5Fe24EB423aa56F;

    // ── Core salts ──
    bytes32 private constant DEADLINES_SALT = keccak256("_JBDeadlinesV6_");
    bytes32 private constant USD_NATIVE_FEED_SALT = keccak256("USD_FEEDV6");
    bytes32 private constant USDC_FEED_SALT = keccak256("USDC_FEEDV6");
    bytes32 private constant MATCHING_FEED_SALT = keccak256("_JBMatchingPriceFeedV6_");
    /// @dev Salts for external libraries pre-linked at compile time. The deterministic CREATE2
    ///      address derived from each (factory, salt, creationCode) MUST match the
    ///      `libraries = [...]` entry in the corresponding source repo's foundry.toml — otherwise
    ///      DELEGATECALLs from contracts that depend on these libraries hit dead code.
    ///      All libraries are deployed by `_deployLibraries()` (Phase 00, before _deployCore).
    bytes32 private constant PAYOUT_SPLIT_GROUP_LIB_SALT = keccak256("_JBPayoutSplitGroupLibV6_");
    bytes32 private constant TIERS_HOOK_LIB_SALT = keccak256("_JB721TiersHookLibV6_");
    bytes32 private constant SUCKER_LIB_SALT = keccak256("_JBSuckerLibV6_");
    bytes32 private constant CCIP_LIB_SALT = keccak256("_JBCCIPLibV6_");
    bytes32 private constant CCIP_HELPER_SALT = keccak256("_CCIPHelperV6_");
    bytes32 private constant SWAP_POOL_LIB_SALT = keccak256("_JBSwapPoolLibV6_");
    bytes32 private constant DEFIFA_HOOK_LIB_SALT = keccak256("_DefifaHookLibV6_");

    // ── Address Registry salt ──
    bytes32 private constant ADDRESS_REGISTRY_SALT = "_JBAddressRegistryV6_";

    // ── 721 Hook salts ──
    bytes32 private constant HOOK_721_STORE_SALT = "JB721TiersHookStoreV6_";
    bytes32 private constant HOOK_721_SALT = "JB721TiersHookV6_";
    bytes32 private constant HOOK_721_DEPLOYER_SALT = "JB721TiersHookDeployerV6_";
    bytes32 private constant HOOK_721_PROJECT_DEPLOYER_SALT = "JB721TiersHookProjectDeployerV6";
    bytes32 private constant HOOK_721_CHECKPOINTS_DEPLOYER_SALT = "JB721CheckpointsDeployerV6";

    // ── Uniswap V4 Hook + Buyback Hook salts ──
    bytes32 private constant BUYBACK_HOOK_SALT = "JBBuybackHookV6";
    bytes32 private constant LP_SPLIT_HOOK_SALT = "JBUniswapV4LPSplitHookV6";
    bytes32 private constant LP_SPLIT_HOOK_DEPLOYER_SALT = "JBUniswapV4LPSplitHookDeployerV6";

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
    bytes32 private constant TEMPO_SALT = "_SUCKER_ETH_TEMPO_V6_";
    bytes32 private constant SUCKER_REGISTRY_SALT = "REGISTRYV6";
    bytes32 private constant SWAP_OP_SALT = "_SWAP_SUCKER_ETH_OP_V6_";
    bytes32 private constant SWAP_BASE_SALT = "_SWAP_SUCKER_ETH_BASE_V6";
    bytes32 private constant SWAP_ARB_SALT = "_SWAP_SUCKER_ETH_ARB_V6_";
    bytes32 private constant SWAP_ARB_BASE_SALT = "_SWAP_SUCKER_ARB_BASEV6";
    bytes32 private constant SWAP_ARB_OP_SALT = "_SWAP_SUCKER_ARB_OP_V6_";
    bytes32 private constant SWAP_OP_BASE_SALT = "_SWAP_SUCKER_OP_BASE_V6_";

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
    bytes32 private constant REV_OWNER_SALT = "_REV_OWNER_SALT_V6_";
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
    bytes32 private constant DEFIFA_SALT = "_DEFIFA_SALTV6_";

    // ── Defifa Revnet salts ──
    bytes32 private constant DEFIFA_REV_ERC20_SALT = "_DEFIFA_ERC20V6_";
    bytes32 private constant DEFIFA_REV_SUCKER_SALT = "_DEFIFA_SUCKERV6_";

    // ── Project Handles salt ──
    bytes32 private constant PROJECT_HANDLES_SALT = "JBProjectHandlesV6";

    // ── Distributor salts ──
    bytes32 private constant DISTRIBUTOR_721_SALT = "JB721DistributorV6";
    bytes32 private constant DISTRIBUTOR_TOKEN_SALT = "JBTokenDistributorV6";

    // ── Project Payer salt ──
    bytes32 private constant PROJECT_PAYER_DEPLOYER_SALT = "JBProjectPayerDeployerV6";

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

    // ── Distributor constants ──
    uint256 private constant VESTING_ROUNDS = 52;

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
    JB721CheckpointsDeployer private _checkpointsDeployer;
    JB721TiersHook private _hook721;
    JB721TiersHookDeployer private _hookDeployer;
    JB721TiersHookProjectDeployer private _hookProjectDeployer;

    // Buyback Hook
    JBUniswapV4Hook private _uniswapV4Hook;
    JBBuybackHookRegistry private _buybackRegistry;
    JBBuybackHook private _buybackHook;
    JBUniswapV4LPSplitHook private _lpSplitHook;
    JBUniswapV4LPSplitHookDeployer private _lpSplitHookDeployer;

    // Router Terminal
    JBRouterTerminalRegistry private _routerTerminalRegistry;
    JBRouterTerminal private _routerTerminal;

    // Suckers
    JBSuckerRegistry private _suckerRegistry;
    address[] private _preApprovedSuckerDeployers;
    IJBSuckerDeployer private _optimismSuckerDeployer;
    IJBSuckerDeployer private _baseSuckerDeployer;
    IJBSuckerDeployer private _arbitrumSuckerDeployer;
    IJBSuckerDeployer private _tempoCcipDeployer;

    // Omnichain Deployer
    JBOmnichainDeployer private _omnichainDeployer;

    // Croptop
    CTPublisher private _ctPublisher;
    CTDeployer private _ctDeployer;
    CTProjectOwner private _ctProjectOwner;

    // Revnet
    REVLoans private _revLoans;
    REVOwner private _revOwner;
    REVDeployer private _revDeployer;

    // Banny
    Banny721TokenUriResolver private _bannyResolver;

    // Defifa
    DefifaHook private _defifaHook;
    DefifaTokenUriResolver private _defifaTokenUriResolver;
    DefifaGovernor private _defifaGovernor;
    JB721TiersHookStore private _defifaHookStore;
    DefifaDeployer private _defifaDeployer;

    // Project Handles
    JBProjectHandles private _projectHandles;

    // Distributor
    JB721Distributor private _721Distributor;
    JBTokenDistributor private _tokenDistributor;
    uint256 private _roundDuration;

    // Project Payer
    JBProjectPayerDeployer private _projectPayerDeployer;

    // Project IDs (determined by deploy order)
    uint256 private _cpnProjectId; // project 2
    uint256 private _revProjectId; // project 3
    uint256 private constant _FEE_PROJECT_ID = 1;
    uint256 private constant _CPN_PROJECT_ID = 2;
    uint256 private constant _REV_PROJECT_ID = 3;
    uint256 private constant _BAN_PROJECT_ID = 4;

    /// @notice Canonical Banny ops EOA. Used as the auto-issuance beneficiary in all stages and inherits
    /// the BAN split-operator role + resolver ownership from the Sphinx Safe via `_finalizeBannyOwnership`
    /// after all Banny drops have been registered.
    address private constant _BAN_OPS_OPERATOR = 0x9E2a10aB3BD22831f19d02C648Bc2Cb49B127450;

    // Chain-specific addresses (set in run())
    address private _wrappedNativeToken;
    address private _usdcToken;
    address private _v3Factory;
    address private _poolManager;
    address private _positionManager;
    address private _typeface;

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
        // Sanity-gate the entire deploy: refuse to proceed unless the Sphinx Safe resolves to the
        // canonical address. Catches misconfigured sphinx.lock or stale Safe-factory state before
        // anything is deployed or any project ownership is granted.
        if (safeAddress() != _EXPECTED_SAFE) {
            revert Deploy_UnexpectedSafe({expected: _EXPECTED_SAFE, actual: safeAddress()});
        }

        _setupChainAddresses();
        deploy();
        _dumpAddresses();
    }

    function deploy() public sphinx {
        // Phase 00: External libraries (must come BEFORE any contract that DELEGATECALLs into them).
        _deployLibraries();

        // Phase 01: Core Protocol
        _deployCore();

        // Phase 02: Address Registry
        _deployAddressRegistry();

        // Phase 03a: 721 Tier Hook
        _deploy721Hook();

        // Phase 03c (registry only): Buyback Hook Registry — deployed unconditionally so revnets work on
        // chains without Uniswap V4. The registry passes through gracefully when no hook is configured.
        _deployBuybackRegistry();

        if (_shouldDeployUniswapStack()) {
            // Phase 03b: Uniswap V4 Router Hook
            _deployUniswapV4Hook();

            // Phase 03c (hook): Buyback Hook — requires Uniswap V4 PoolManager
            _deployBuybackHook();

            // Phase 03d: Router Terminal
            _deployRouterTerminal();
        }

        // Phase 03e: Cross-Chain Suckers (before LP Split Hook — LP hook needs the registry)
        _deploySuckers();

        if (_positionManager != address(0)) {
            // Phase 03f: Uniswap V4 LP Split Hook (requires PositionManager + SuckerRegistry)
            _deployLpSplitHook();
        }

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

        // Phase 09b: Banny Drop 1 — registers the 47 retail items on the BAN project's 721 hook + resolver.
        // Idempotent: skipped when the hook already has the drop tiers.
        _registerBannyDrop1();

        // Phase 09c: Banny Drop 2 — registers the 17 outfit items on top of Drop 1.
        // Idempotent: skipped when the hook already has the drop tiers. Must run before
        // `_finalizeBannyOwnership` so the Sphinx Safe still holds split-operator + resolver ownership.
        _registerBannyDrop2();

        // Phase 09d: Finalize Banny ownership — transfers resolver ownership + BAN split-operator role
        // from the Sphinx Safe to `_BAN_OPS_OPERATOR`. Idempotent: skipped when the resolver is already
        // owned by `_BAN_OPS_OPERATOR`.
        _finalizeBannyOwnership();

        // Phase 10: Defifa — deploys the Defifa game infrastructure (hook, resolver, governor, deployer).
        _deployDefifa();

        // Phase 11: Periphery Extensions (Project Handles, Distributor, Project Payer)
        _deployProjectHandles();
        _deployDistributors();
        _deployProjectPayerDeployer();
    }

    // ════════════════════════════════════════════════════════════════════
    //  Chain-Specific Address Setup
    // ════════════════════════════════════════════════════════════════════

    function _setupChainAddresses() internal {
        // Ethereum Mainnet
        if (block.chainid == 1) {
            _wrappedNativeToken = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
            _usdcToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
            _v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            _poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            _positionManager = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
            _typeface = 0xA77b7D93E79f1E6B4f77FaB29d9ef85733A3D44A;
            _roundDuration = 604_800; // 7 days
        }
        // Ethereum Sepolia
        else if (block.chainid == 11_155_111) {
            _wrappedNativeToken = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9; // WETH
            _usdcToken = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // USDC
            _v3Factory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
            _poolManager = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
            _positionManager = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
            _typeface = 0x8C420d3388C882F40d263714d7A6e2c8DB93905F;
            _roundDuration = 604_800; // 7 days
        }
        // Optimism
        else if (block.chainid == 10) {
            _wrappedNativeToken = 0x4200000000000000000000000000000000000006; // WETH
            _usdcToken = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // USDC
            _v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            _poolManager = 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
            _positionManager = 0x3C3Ea4B57a46241e54610e5f022E5c45859A1017;
            _typeface = 0xe160e47928907894F97a0DC025c61D64E862fEAa;
            _roundDuration = 604_800; // 7 days
        }
        // Optimism Sepolia
        // Keep deploy-all supported here, but skip the Uniswap-dependent stack since no PositionManager is published.
        else if (block.chainid == 11_155_420) {
            _wrappedNativeToken = 0x4200000000000000000000000000000000000006; // WETH
            _usdcToken = 0x5fd84259d66Cd46123540766Be93DFE6D43130D7; // USDC
            _v3Factory = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
            _poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            _positionManager = address(0);
            _typeface = 0xe160e47928907894F97a0DC025c61D64E862fEAa;
            _roundDuration = 604_800; // 7 days
        }
        // Base
        else if (block.chainid == 8453) {
            _wrappedNativeToken = 0x4200000000000000000000000000000000000006; // WETH
            _usdcToken = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC
            _v3Factory = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
            _poolManager = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
            _positionManager = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
            _typeface = 0x3DE45A14ea0fe24037D6363Ae71Ef18F336D1C27;
            _roundDuration = 604_800; // 7 days
        }
        // Base Sepolia
        else if (block.chainid == 84_532) {
            _wrappedNativeToken = 0x4200000000000000000000000000000000000006; // WETH
            _usdcToken = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // USDC
            _v3Factory = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
            _poolManager = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
            _positionManager = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
            _typeface = 0xEb269d9F0850CEf5e3aB0F9718fb79c466720784;
            _roundDuration = 604_800; // 7 days
        }
        // Arbitrum
        else if (block.chainid == 42_161) {
            _wrappedNativeToken = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
            _usdcToken = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
            _v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            _poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
            _positionManager = 0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869;
            _typeface = 0x431C35e9fA5152A906A38390910d0Cfcba0Fb43b;
            _roundDuration = 604_800; // 7 days
        }
        // Arbitrum Sepolia
        else if (block.chainid == 421_614) {
            _wrappedNativeToken = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73; // WETH
            _usdcToken = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d; // USDC
            _v3Factory = 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e;
            _poolManager = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
            _positionManager = 0xAc631556d3d4019C95769033B5E719dD77124BAc;
            _typeface = 0x431C35e9fA5152A906A38390910d0Cfcba0Fb43b;
            _roundDuration = 604_800; // 7 days
        }
        // TODO: Tempo support commented out until chain is ready.
        // else if (block.chainid == 4217) { ... }
        // else if (block.chainid == 42_431) { ... }
        else {
            revert("Unsupported chain");
        }
    }

    function _shouldDeployUniswapStack() internal view returns (bool) {
        // Skip on chains without Uniswap V4: OP Sepolia (no PositionManager).
        return block.chainid != 11_155_420;
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 01: Core Protocol
    // ════════════════════════════════════════════════════════════════════

    // ════════════════════════════════════════════════════════════════════
    //  Phase 00: External Libraries
    //  Deployed first because downstream contracts have their bytecode
    //  pre-linked to these libraries' deterministic CREATE2 addresses
    //  (see each source repo's `foundry.toml` `libraries = [...]`). A
    //  DELEGATECALL into a not-yet-deployed library is a silent revert.
    // ════════════════════════════════════════════════════════════════════

    function _deployLibraries() internal {
        // JBPayoutSplitGroupLib — DELEGATECALL'd by JBMultiTerminal.
        _deployPrecompiledIfNeeded({
            artifactName: "JBPayoutSplitGroupLib", salt: PAYOUT_SPLIT_GROUP_LIB_SALT, ctorArgs: ""
        });
        // JB721TiersHookLib — DELEGATECALL'd by JB721TiersHook.
        _deployPrecompiledIfNeeded({artifactName: "JB721TiersHookLib", salt: TIERS_HOOK_LIB_SALT, ctorArgs: ""});
        // JBSuckerLib — DELEGATECALL'd by JBOptimismSucker / JBBaseSucker / JBArbitrumSucker /
        // JBCCIPSucker / JBSwapCCIPSucker.
        _deployPrecompiledIfNeeded({artifactName: "JBSuckerLib", salt: SUCKER_LIB_SALT, ctorArgs: ""});
        // JBCCIPLib — DELEGATECALL'd by JBCCIPSucker / JBSwapCCIPSucker.
        _deployPrecompiledIfNeeded({artifactName: "JBCCIPLib", salt: CCIP_LIB_SALT, ctorArgs: ""});
        // CCIPHelper — DELEGATECALL'd by JBCCIPSucker (chain selector / router lookups).
        _deployPrecompiledIfNeeded({artifactName: "CCIPHelper", salt: CCIP_HELPER_SALT, ctorArgs: ""});
        // JBSwapPoolLib — DELEGATECALL'd by JBSwapCCIPSucker.
        _deployPrecompiledIfNeeded({artifactName: "JBSwapPoolLib", salt: SWAP_POOL_LIB_SALT, ctorArgs: ""});
        // DefifaHookLib — DELEGATECALL'd by DefifaHook + DefifaGovernor.
        _deployPrecompiledIfNeeded({artifactName: "DefifaHookLib", salt: DEFIFA_HOOK_LIB_SALT, ctorArgs: ""});
    }

    function _deployCore() internal {
        bytes32 coreSalt = keccak256(abi.encode(CORE_DEPLOYMENT_NONCE));

        _trustedForwarder = _deployPrecompiledIfNeeded({
            artifactName: "ERC2771Forwarder", salt: coreSalt, ctorArgs: abi.encode(TRUSTED_FORWARDER_NAME)
        });

        _permissions = JBPermissions(
            _deployPrecompiledIfNeeded({
                artifactName: "JBPermissions", salt: coreSalt, ctorArgs: abi.encode(_trustedForwarder)
            })
        );

        _projects = JBProjects(
            _deployPrecompiledIfNeeded({
                artifactName: "JBProjects",
                salt: coreSalt,
                ctorArgs: abi.encode(safeAddress(), safeAddress(), _trustedForwarder)
            })
        );

        _directory = JBDirectory(
            _deployPrecompiledIfNeeded({
                artifactName: "JBDirectory",
                salt: coreSalt,
                ctorArgs: abi.encode(_permissions, _projects, safeAddress())
            })
        );

        _splits = JBSplits(
            _deployPrecompiledIfNeeded({artifactName: "JBSplits", salt: coreSalt, ctorArgs: abi.encode(_directory)})
        );

        _rulesets = JBRulesets(
            _deployPrecompiledIfNeeded({artifactName: "JBRulesets", salt: coreSalt, ctorArgs: abi.encode(_directory)})
        );

        _prices = JBPrices(
            _deployPrecompiledIfNeeded({
                artifactName: "JBPrices",
                salt: coreSalt,
                ctorArgs: abi.encode(_directory, _permissions, _projects, safeAddress(), _trustedForwarder)
            })
        );

        JBERC20 token = JBERC20(
            _deployPrecompiledIfNeeded({
                artifactName: "JBERC20", salt: coreSalt, ctorArgs: abi.encode(_permissions, _projects)
            })
        );

        _tokens = JBTokens(
            _deployPrecompiledIfNeeded({
                artifactName: "JBTokens", salt: coreSalt, ctorArgs: abi.encode(_directory, token)
            })
        );

        _fundAccess = JBFundAccessLimits(
            _deployPrecompiledIfNeeded({
                artifactName: "JBFundAccessLimits", salt: coreSalt, ctorArgs: abi.encode(_directory)
            })
        );

        _feeless = JBFeelessAddresses(
            _deployPrecompiledIfNeeded({
                artifactName: "JBFeelessAddresses", salt: coreSalt, ctorArgs: abi.encode(safeAddress())
            })
        );

        _terminalStore = JBTerminalStore(
            _deployPrecompiledIfNeeded({
                artifactName: "JBTerminalStore", salt: coreSalt, ctorArgs: abi.encode(_directory, _prices, _rulesets)
            })
        );

        _terminal = JBMultiTerminal(
            _deployPrecompiledIfNeeded({
                artifactName: "JBMultiTerminal",
                salt: coreSalt,
                ctorArgs: abi.encode(
                    _feeless, _permissions, _projects, _splits, _terminalStore, _tokens, _PERMIT2, _trustedForwarder
                )
            })
        );
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 02: Address Registry
    // ════════════════════════════════════════════════════════════════════

    function _deployAddressRegistry() internal {
        _addressRegistry = JBAddressRegistry(
            _deployPrecompiledIfNeeded({artifactName: "JBAddressRegistry", salt: ADDRESS_REGISTRY_SALT, ctorArgs: ""})
        );
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 03a: 721 Tier Hook
    // ════════════════════════════════════════════════════════════════════

    function _deploy721Hook() internal {
        _hookStore = JB721TiersHookStore(
            _deployPrecompiledIfNeeded({artifactName: "JB721TiersHookStore", salt: HOOK_721_STORE_SALT, ctorArgs: ""})
        );

        _checkpointsDeployer = JB721CheckpointsDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "JB721CheckpointsDeployer",
                salt: HOOK_721_CHECKPOINTS_DEPLOYER_SALT,
                ctorArgs: abi.encode(_hookStore)
            })
        );

        _hook721 = JB721TiersHook(
            _deployPrecompiledIfNeeded({
                artifactName: "JB721TiersHook",
                salt: HOOK_721_SALT,
                ctorArgs: abi.encode(
                    _directory,
                    _permissions,
                    _prices,
                    _rulesets,
                    _hookStore,
                    _splits,
                    _checkpointsDeployer,
                    _trustedForwarder
                )
            })
        );

        _hookDeployer = JB721TiersHookDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "JB721TiersHookDeployer",
                salt: HOOK_721_DEPLOYER_SALT,
                ctorArgs: abi.encode(
                    _hook721, _hookStore, IJBAddressRegistry(address(_addressRegistry)), _trustedForwarder
                )
            })
        );

        _hookProjectDeployer = JB721TiersHookProjectDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "JB721TiersHookProjectDeployer",
                salt: HOOK_721_PROJECT_DEPLOYER_SALT,
                ctorArgs: abi.encode(_directory, _permissions, _hookDeployer, _trustedForwarder)
            })
        );
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 03b: Uniswap V4 Router Hook
    // ════════════════════════════════════════════════════════════════════

    function _deployUniswapV4Hook() internal {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory v4HookCode = _loadArtifact("JBUniswapV4Hook");
        bytes memory ctorArgs = abi.encode(IPoolManager(_poolManager), _tokens, _directory, _prices);

        // V4 hook salt must be mined so the resulting address has the right flag bits.
        bytes32 salt = _findHookSalt({
            deployer: _CREATE2_FACTORY, flags: flags, creationCode: v4HookCode, constructorArgs: ctorArgs
        });

        (address hook, bool already) = _isDeployed({salt: salt, creationCode: v4HookCode, arguments: ctorArgs});

        if (!already) {
            hook = _deployViaFactory({
                factory: _CREATE2_FACTORY, salt: salt, creationCode: v4HookCode, constructorArgs: ctorArgs
            });
        }
        _uniswapV4Hook = JBUniswapV4Hook(payable(hook));
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 03c (registry): Buyback Hook Registry
    //  Deployed unconditionally — the registry passes through gracefully
    //  when no hook is configured, so projects work without buyback.
    // ════════════════════════════════════════════════════════════════════

    function _deployBuybackRegistry() internal {
        _buybackRegistry = JBBuybackHookRegistry(
            _deployPrecompiledIfNeeded({
                artifactName: "JBBuybackHookRegistry",
                salt: BUYBACK_HOOK_SALT,
                ctorArgs: abi.encode(_permissions, _projects, safeAddress(), _trustedForwarder)
            })
        );
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 03c (hook): Buyback Hook — requires Uniswap V4 PoolManager
    // ════════════════════════════════════════════════════════════════════

    function _deployBuybackHook() internal {
        // Chain-same CREATE2: constructor inputs are byte-identical across chains. The chain-specific
        // PoolManager + ORACLE_HOOK are wired in afterwards via the DEPLOYER-gated one-shot
        // setChainSpecificConstants setter on the hook (mirrors JBOptimismSuckerDeployer).
        _buybackHook = JBBuybackHook(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBBuybackHook",
                    salt: BUYBACK_HOOK_SALT,
                    ctorArgs: abi.encode(
                        _directory, _permissions, _prices, _projects, _tokens, safeAddress(), _trustedForwarder
                    )
                }))
        );

        if (address(_buybackHook.POOL_MANAGER()) == address(0)) {
            _buybackHook.setChainSpecificConstants({
                poolManager: IPoolManager(_poolManager), oracleHook: IHooks(address(_uniswapV4Hook))
            });
        }

        if (address(_buybackRegistry.defaultHook()) == address(0)) {
            _buybackRegistry.setDefaultHook({hook: _buybackHook});
        } else if (address(_buybackRegistry.defaultHook()) != address(_buybackHook)) {
            revert Deploy_ExistingAddressMismatch(address(_buybackHook), address(_buybackRegistry.defaultHook()));
        }

        // Pin the buyback hook for project 1 (NANA) so it persists even if the default changes.
        _buybackRegistry.setHookFor({projectId: _FEE_PROJECT_ID, hook: _buybackHook});
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 03d: Router Terminal
    // ════════════════════════════════════════════════════════════════════

    function _deployRouterTerminal() internal {
        _routerTerminalRegistry = JBRouterTerminalRegistry(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBRouterTerminalRegistry",
                    salt: ROUTER_TERMINAL_REGISTRY_SALT,
                    ctorArgs: abi.encode(_permissions, _projects, _PERMIT2, safeAddress(), _trustedForwarder)
                }))
        );

        // Chain-same CREATE2: constructor inputs are byte-identical across chains. The chain-specific
        // wrapped-native-token, V3 factory, V4 PoolManager, and V4 hook are wired in afterwards via the
        // DEPLOYER-gated one-shot setChainSpecificConstants setter on the terminal (mirrors JBBuybackHook).
        _routerTerminal = JBRouterTerminal(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBRouterTerminal",
                    salt: ROUTER_TERMINAL_SALT,
                    ctorArgs: abi.encode(
                        _directory, _tokens, _PERMIT2, address(_buybackHook), _trustedForwarder, safeAddress()
                    )
                }))
        );

        if (address(_routerTerminal.WRAPPED_NATIVE_TOKEN()) == address(0)) {
            _routerTerminal.setChainSpecificConstants({
                wrappedNativeToken: IWETH9(_wrappedNativeToken),
                factory: IUniswapV3Factory(_v3Factory),
                poolManager: IPoolManager(_poolManager),
                univ4Hook: address(_uniswapV4Hook)
            });
        }

        if (address(_routerTerminalRegistry.defaultTerminal()) == address(0)) {
            _routerTerminalRegistry.setDefaultTerminal({terminal: _routerTerminal});
        } else if (address(_routerTerminalRegistry.defaultTerminal()) != address(_routerTerminal)) {
            revert Deploy_ExistingAddressMismatch(
                address(_routerTerminal), address(_routerTerminalRegistry.defaultTerminal())
            );
        }

        if (!_feeless.isFeelessFor({addr: address(_routerTerminal), projectId: 0})) {
            _feeless.setFeelessAddress({addr: address(_routerTerminal), flag: true});
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 03f: Uniswap V4 LP Split Hook
    // ════════════════════════════════════════════════════════════════════

    function _deployLpSplitHook() internal {
        // Chain-same CREATE2 for the implementation: the chain-specific Uniswap V4 addresses (PoolManager,
        // PositionManager, oracle hook) are no longer ctor args — each clone receives them through the deployer
        // factory's `deployHookFor`, which passes them into `initialize` from the factory's storage.
        _lpSplitHook = JBUniswapV4LPSplitHook(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBUniswapV4LPSplitHook",
                    salt: LP_SPLIT_HOOK_SALT,
                    ctorArgs: abi.encode(
                        address(_directory),
                        _permissions,
                        address(_tokens),
                        IAllowanceTransfer(address(_PERMIT2)),
                        IJBSuckerRegistry(address(_suckerRegistry))
                    )
                }))
        );

        // Chain-same CREATE2 for the deployer factory: ctor takes only chain-same inputs. The implementation +
        // chain-specific V4 addresses are wired afterwards via the DEPLOYER-gated one-shot setChainSpecificConstants
        // setter; the factory uses these stored values when initializing each freshly cloned hook.
        _lpSplitHookDeployer = JBUniswapV4LPSplitHookDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "JBUniswapV4LPSplitHookDeployer",
                salt: LP_SPLIT_HOOK_DEPLOYER_SALT,
                ctorArgs: abi.encode(IJBAddressRegistry(address(_addressRegistry)), safeAddress())
            })
        );

        if (address(_lpSplitHookDeployer.HOOK()) == address(0)) {
            _lpSplitHookDeployer.setChainSpecificConstants({
                hook: _lpSplitHook,
                poolManager: IPoolManager(_poolManager),
                positionManager: IPositionManager(_positionManager),
                oracleHook: IHooks(address(_uniswapV4Hook))
            });
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 03e: Cross-Chain Suckers
    // ════════════════════════════════════════════════════════════════════

    function _deploySuckers() internal {
        // Deploy the registry FIRST — singleton sucker constructors consume it as an immutable.
        _suckerRegistry = JBSuckerRegistry(
            _deployPrecompiledIfNeeded({
                artifactName: "JBSuckerRegistry",
                salt: SUCKER_REGISTRY_SALT,
                ctorArgs: abi.encode(_directory, _permissions, safeAddress(), _trustedForwarder)
            })
        );

        // Deploy singleton implementations and deployers (they reference _suckerRegistry).
        _deploySuckersOptimism();
        _deploySuckersBase();
        _deploySuckersArbitrum();
        _deploySuckersCCIP();

        // Pre-approve deployers in the registry.
        if (_preApprovedSuckerDeployers.length != 0) {
            for (uint256 i; i < _preApprovedSuckerDeployers.length; i++) {
                if (!_suckerRegistry.suckerDeployerIsAllowed(_preApprovedSuckerDeployers[i])) {
                    _suckerRegistry.allowSuckerDeployer(_preApprovedSuckerDeployers[i]);
                }
            }
        }
    }

    function _deploySuckersOptimism() internal {
        // L1: Ethereum Mainnet / Sepolia
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            JBOptimismSuckerDeployer opDeployer = JBOptimismSuckerDeployer(
                _deployPrecompiledIfNeeded({
                    artifactName: "JBOptimismSuckerDeployer",
                    salt: OP_SALT,
                    ctorArgs: abi.encode(_directory, _permissions, _tokens, safeAddress(), _trustedForwarder)
                })
            );

            IOPMessenger messenger = IOPMessenger(
                block.chainid == 1
                    ? address(0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1)
                    : address(0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef)
            );
            IOPStandardBridge bridge = IOPStandardBridge(
                block.chainid == 1
                    ? address(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1)
                    : address(0xFBb0621E0B23b5478B630BD55a5f21f67730B0F1)
            );
            if (address(opDeployer.opMessenger()) == address(0)) {
                opDeployer.setChainSpecificConstants(messenger, bridge);
            }

            JBOptimismSucker singleton = JBOptimismSucker(
                payable(_deployPrecompiledIfNeeded({
                        artifactName: "JBOptimismSucker",
                        salt: OP_SALT,
                        ctorArgs: abi.encode(
                            opDeployer,
                            _directory,
                            _permissions,
                            _prices,
                            _tokens,
                            1,
                            _suckerRegistry,
                            _trustedForwarder
                        )
                    }))
            );
            if (address(opDeployer.singleton()) == address(0)) opDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(opDeployer));
            _optimismSuckerDeployer = IJBSuckerDeployer(address(opDeployer));
        }

        // L2: Optimism / Optimism Sepolia
        if (block.chainid == 10 || block.chainid == 11_155_420) {
            JBOptimismSuckerDeployer opDeployer = JBOptimismSuckerDeployer(
                _deployPrecompiledIfNeeded({
                    artifactName: "JBOptimismSuckerDeployer",
                    salt: OP_SALT,
                    ctorArgs: abi.encode(_directory, _permissions, _tokens, safeAddress(), _trustedForwarder)
                })
            );

            if (address(opDeployer.opMessenger()) == address(0)) {
                opDeployer.setChainSpecificConstants(
                    IOPMessenger(0x4200000000000000000000000000000000000007),
                    IOPStandardBridge(0x4200000000000000000000000000000000000010)
                );
            }

            JBOptimismSucker singleton = JBOptimismSucker(
                payable(_deployPrecompiledIfNeeded({
                        artifactName: "JBOptimismSucker",
                        salt: OP_SALT,
                        ctorArgs: abi.encode(
                            opDeployer,
                            _directory,
                            _permissions,
                            _prices,
                            _tokens,
                            1,
                            _suckerRegistry,
                            _trustedForwarder
                        )
                    }))
            );
            if (address(opDeployer.singleton()) == address(0)) opDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(opDeployer));
            _optimismSuckerDeployer = IJBSuckerDeployer(address(opDeployer));
        }
    }

    function _deploySuckersBase() internal {
        // L1
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            JBBaseSuckerDeployer baseDeployer = JBBaseSuckerDeployer(
                _deployPrecompiledIfNeeded({
                    artifactName: "JBBaseSuckerDeployer",
                    salt: BASE_SALT,
                    ctorArgs: abi.encode(_directory, _permissions, _tokens, safeAddress(), _trustedForwarder)
                })
            );

            IOPMessenger messenger = IOPMessenger(
                block.chainid == 1
                    ? address(0x866E82a600A1414e583f7F13623F1aC5d58b0Afa)
                    : address(0xC34855F4De64F1840e5686e64278da901e261f20)
            );
            IOPStandardBridge bridge = IOPStandardBridge(
                block.chainid == 1
                    ? address(0x3154Cf16ccdb4C6d922629664174b904d80F2C35)
                    : address(0xfd0Bf71F60660E2f608ed56e1659C450eB113120)
            );
            if (address(baseDeployer.opMessenger()) == address(0)) {
                baseDeployer.setChainSpecificConstants(messenger, bridge);
            }

            JBBaseSucker singleton = JBBaseSucker(
                payable(_deployPrecompiledIfNeeded({
                        artifactName: "JBBaseSucker",
                        salt: BASE_SALT,
                        ctorArgs: abi.encode(
                            baseDeployer,
                            _directory,
                            _permissions,
                            _prices,
                            _tokens,
                            1,
                            _suckerRegistry,
                            _trustedForwarder
                        )
                    }))
            );
            if (address(baseDeployer.singleton()) == address(0)) baseDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(baseDeployer));
            _baseSuckerDeployer = IJBSuckerDeployer(address(baseDeployer));
        }

        // L2: Base / Base Sepolia
        if (block.chainid == 8453 || block.chainid == 84_532) {
            JBBaseSuckerDeployer baseDeployer = JBBaseSuckerDeployer(
                _deployPrecompiledIfNeeded({
                    artifactName: "JBBaseSuckerDeployer",
                    salt: BASE_SALT,
                    ctorArgs: abi.encode(_directory, _permissions, _tokens, safeAddress(), _trustedForwarder)
                })
            );

            if (address(baseDeployer.opMessenger()) == address(0)) {
                baseDeployer.setChainSpecificConstants(
                    IOPMessenger(0x4200000000000000000000000000000000000007),
                    IOPStandardBridge(0x4200000000000000000000000000000000000010)
                );
            }

            JBBaseSucker singleton = JBBaseSucker(
                payable(_deployPrecompiledIfNeeded({
                        artifactName: "JBBaseSucker",
                        salt: BASE_SALT,
                        ctorArgs: abi.encode(
                            baseDeployer,
                            _directory,
                            _permissions,
                            _prices,
                            _tokens,
                            1,
                            _suckerRegistry,
                            _trustedForwarder
                        )
                    }))
            );
            if (address(baseDeployer.singleton()) == address(0)) baseDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(baseDeployer));
            _baseSuckerDeployer = IJBSuckerDeployer(address(baseDeployer));
        }
    }

    function _deploySuckersArbitrum() internal {
        // L1
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            JBArbitrumSuckerDeployer arbDeployer = JBArbitrumSuckerDeployer(
                _deployPrecompiledIfNeeded({
                    artifactName: "JBArbitrumSuckerDeployer",
                    salt: ARB_SALT,
                    ctorArgs: abi.encode(_directory, _permissions, _tokens, safeAddress(), _trustedForwarder)
                })
            );

            if (address(arbDeployer.arbGatewayRouter()) == address(0)) {
                arbDeployer.setChainSpecificConstants({
                    layer: JBLayer.L1,
                    inbox: IInbox(block.chainid == 1 ? ARBAddresses.L1_ETH_INBOX : ARBAddresses.L1_SEP_INBOX),
                    gatewayRouter: IArbGatewayRouter(
                        block.chainid == 1 ? ARBAddresses.L1_GATEWAY_ROUTER : ARBAddresses.L1_SEP_GATEWAY_ROUTER
                    )
                });
            }

            JBArbitrumSucker singleton = JBArbitrumSucker(
                payable(_deployPrecompiledIfNeeded({
                        artifactName: "JBArbitrumSucker",
                        salt: ARB_SALT,
                        ctorArgs: abi.encode(
                            arbDeployer,
                            _directory,
                            _permissions,
                            _prices,
                            _tokens,
                            1,
                            _suckerRegistry,
                            _trustedForwarder
                        )
                    }))
            );
            if (address(arbDeployer.singleton()) == address(0)) arbDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(arbDeployer));
            _arbitrumSuckerDeployer = IJBSuckerDeployer(address(arbDeployer));
        }

        // L2: Arbitrum / Arbitrum Sepolia
        if (block.chainid == 42_161 || block.chainid == 421_614) {
            JBArbitrumSuckerDeployer arbDeployer = JBArbitrumSuckerDeployer(
                _deployPrecompiledIfNeeded({
                    artifactName: "JBArbitrumSuckerDeployer",
                    salt: ARB_SALT,
                    ctorArgs: abi.encode(_directory, _permissions, _tokens, safeAddress(), _trustedForwarder)
                })
            );

            // inbox=address(0) is correct on L2. The Arbitrum inbox is only used on L1 to send
            // retryable tickets. The deployer's validation in nana-suckers-v6 is layer-aware and
            // accepts address(0) when layer == JBLayer.L2.
            if (address(arbDeployer.arbGatewayRouter()) == address(0)) {
                arbDeployer.setChainSpecificConstants({
                    layer: JBLayer.L2,
                    inbox: IInbox(address(0)),
                    gatewayRouter: IArbGatewayRouter(
                        block.chainid == 42_161 ? ARBAddresses.L2_GATEWAY_ROUTER : ARBAddresses.L2_SEP_GATEWAY_ROUTER
                    )
                });
            }

            JBArbitrumSucker singleton = JBArbitrumSucker(
                payable(_deployPrecompiledIfNeeded({
                        artifactName: "JBArbitrumSucker",
                        salt: ARB_SALT,
                        ctorArgs: abi.encode(
                            arbDeployer,
                            _directory,
                            _permissions,
                            _prices,
                            _tokens,
                            1,
                            _suckerRegistry,
                            _trustedForwarder
                        )
                    }))
            );
            if (address(arbDeployer.singleton()) == address(0)) arbDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(arbDeployer));
            _arbitrumSuckerDeployer = IJBSuckerDeployer(address(arbDeployer));
        }
    }

    function _deploySuckersCCIP() internal {
        // L1: Deploy CCIP suckers for OP, Base, Arb
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            _deployCCIPRoute({
                standardSalt: OP_SALT,
                swapSalt: SWAP_OP_SALT,
                remoteChainId: block.chainid == 1 ? CCIPHelper.OP_ID : CCIPHelper.OP_SEP_ID
            });
            _deployCCIPRoute({
                standardSalt: BASE_SALT,
                swapSalt: SWAP_BASE_SALT,
                remoteChainId: block.chainid == 1 ? CCIPHelper.BASE_ID : CCIPHelper.BASE_SEP_ID
            });
            _deployCCIPRoute({
                standardSalt: ARB_SALT,
                swapSalt: SWAP_ARB_SALT,
                remoteChainId: block.chainid == 1 ? CCIPHelper.ARB_ID : CCIPHelper.ARB_SEP_ID
            });
            // TODO: Tempo CCIP sucker commented out until chain is ready.
        }

        // Arbitrum / Arbitrum Sepolia
        if (block.chainid == 42_161 || block.chainid == 421_614) {
            _deployCCIPRoute({
                standardSalt: ARB_SALT,
                swapSalt: SWAP_ARB_SALT,
                remoteChainId: block.chainid == 42_161 ? CCIPHelper.ETH_ID : CCIPHelper.ETH_SEP_ID
            });
            _deployCCIPRoute({
                standardSalt: ARB_OP_SALT,
                swapSalt: SWAP_ARB_OP_SALT,
                remoteChainId: block.chainid == 42_161 ? CCIPHelper.OP_ID : CCIPHelper.OP_SEP_ID
            });
            _deployCCIPRoute({
                standardSalt: ARB_BASE_SALT,
                swapSalt: SWAP_ARB_BASE_SALT,
                remoteChainId: block.chainid == 42_161 ? CCIPHelper.BASE_ID : CCIPHelper.BASE_SEP_ID
            });
        }
        // Optimism / Optimism Sepolia
        else if (block.chainid == 10 || block.chainid == 11_155_420) {
            _deployCCIPRoute({
                standardSalt: OP_SALT,
                swapSalt: SWAP_OP_SALT,
                remoteChainId: block.chainid == 10 ? CCIPHelper.ETH_ID : CCIPHelper.ETH_SEP_ID
            });
            _deployCCIPRoute({
                standardSalt: ARB_OP_SALT,
                swapSalt: SWAP_ARB_OP_SALT,
                remoteChainId: block.chainid == 10 ? CCIPHelper.ARB_ID : CCIPHelper.ARB_SEP_ID
            });
            _deployCCIPRoute({
                standardSalt: OP_BASE_SALT,
                swapSalt: SWAP_OP_BASE_SALT,
                remoteChainId: block.chainid == 10 ? CCIPHelper.BASE_ID : CCIPHelper.BASE_SEP_ID
            });
        }
        // Base / Base Sepolia
        else if (block.chainid == 8453 || block.chainid == 84_532) {
            _deployCCIPRoute({
                standardSalt: BASE_SALT,
                swapSalt: SWAP_BASE_SALT,
                remoteChainId: block.chainid == 8453 ? CCIPHelper.ETH_ID : CCIPHelper.ETH_SEP_ID
            });
            _deployCCIPRoute({
                standardSalt: OP_BASE_SALT,
                swapSalt: SWAP_OP_BASE_SALT,
                remoteChainId: block.chainid == 8453 ? CCIPHelper.OP_ID : CCIPHelper.OP_SEP_ID
            });
            _deployCCIPRoute({
                standardSalt: ARB_BASE_SALT,
                swapSalt: SWAP_ARB_BASE_SALT,
                remoteChainId: block.chainid == 8453 ? CCIPHelper.ARB_ID : CCIPHelper.ARB_SEP_ID
            });
        }

        // TODO: Tempo / Tempo Moderato CCIP sucker commented out until chain is ready.
    }

    function _deployCCIPRoute(bytes32 standardSalt, bytes32 swapSalt, uint256 remoteChainId) internal {
        _preApprovedSuckerDeployers.push(
            address(_deployCCIPSuckerFor({salt: standardSalt, remoteChainId: remoteChainId}))
        );
        _preApprovedSuckerDeployers.push(
            address(_deploySwapCCIPSuckerFor({salt: swapSalt, remoteChainId: remoteChainId}))
        );
    }

    function _deployCCIPSuckerFor(bytes32 salt, uint256 remoteChainId)
        internal
        returns (JBCCIPSuckerDeployer deployer)
    {
        deployer = JBCCIPSuckerDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "JBCCIPSuckerDeployer",
                salt: salt,
                ctorArgs: abi.encode(_directory, _permissions, _tokens, safeAddress(), _trustedForwarder)
            })
        );

        if (address(deployer.ccipRouter()) == address(0)) {
            deployer.setChainSpecificConstants(
                remoteChainId,
                CCIPHelper.selectorOfChain(remoteChainId),
                ICCIPRouter(CCIPHelper.routerOfChain(block.chainid))
            );
        }

        JBCCIPSucker singleton = JBCCIPSucker(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBCCIPSucker",
                    salt: salt,
                    ctorArgs: abi.encode(
                        deployer, _directory, _permissions, _prices, _tokens, 1, _suckerRegistry, _trustedForwarder
                    )
                }))
        );
        if (address(deployer.singleton()) == address(0)) deployer.configureSingleton(singleton);
    }

    function _deploySwapCCIPSuckerFor(
        bytes32 salt,
        uint256 remoteChainId
    )
        internal
        returns (JBSwapCCIPSuckerDeployer deployer)
    {
        deployer = JBSwapCCIPSuckerDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "JBSwapCCIPSuckerDeployer",
                salt: salt,
                ctorArgs: abi.encode(_directory, _permissions, _tokens, safeAddress(), _trustedForwarder)
            })
        );

        if (address(deployer.ccipRouter()) == address(0)) {
            deployer.setChainSpecificConstants(
                remoteChainId,
                CCIPHelper.selectorOfChain(remoteChainId),
                ICCIPRouter(CCIPHelper.routerOfChain(block.chainid))
            );
        }

        if (address(deployer.bridgeToken()) == address(0)) {
            deployer.setSwapConstants({
                _bridgeToken: IERC20(_usdcToken),
                _poolManager: IPoolManager(_poolManager),
                _v3Factory: IUniswapV3Factory(_v3Factory),
                _univ4Hook: address(_uniswapV4Hook),
                _wrappedNativeToken: _wrappedNativeToken
            });
        }

        JBSwapCCIPSucker singleton = JBSwapCCIPSucker(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBSwapCCIPSucker",
                    salt: salt,
                    ctorArgs: abi.encode(
                        deployer, _directory, _permissions, _prices, _tokens, 1, _suckerRegistry, _trustedForwarder
                    )
                }))
        );
        if (address(deployer.singleton()) == address(0)) deployer.configureSingleton(singleton);
    }

    /// @notice Deploy a CCIP sucker for Tempo, using explicit chain constants instead of CCIPHelper lookups
    /// (since the CCIPHelper npm package doesn't include Tempo yet).
    function _deployCCIPSuckerForTempo(
        bytes32 salt,
        uint256 remoteChainId,
        uint64 remoteChainSelector,
        ICCIPRouter router
    )
        internal
        returns (JBCCIPSuckerDeployer deployer)
    {
        deployer = JBCCIPSuckerDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "JBCCIPSuckerDeployer",
                salt: salt,
                ctorArgs: abi.encode(_directory, _permissions, _tokens, safeAddress(), _trustedForwarder)
            })
        );

        if (address(deployer.ccipRouter()) == address(0)) {
            deployer.setChainSpecificConstants(remoteChainId, remoteChainSelector, router);
        }

        JBCCIPSucker singleton = JBCCIPSucker(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBCCIPSucker",
                    salt: salt,
                    ctorArgs: abi.encode(
                        deployer, _directory, _permissions, _prices, _tokens, 1, _suckerRegistry, _trustedForwarder
                    )
                }))
        );
        if (address(deployer.singleton()) == address(0)) deployer.configureSingleton(singleton);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 04: Omnichain Deployer
    // ════════════════════════════════════════════════════════════════════

    function _deployOmnichainDeployer() internal {
        _omnichainDeployer = JBOmnichainDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "JBOmnichainDeployer",
                salt: OMNICHAIN_DEPLOYER_SALT,
                ctorArgs: abi.encode(
                    _suckerRegistry,
                    IJB721TiersHookDeployer(address(_hookDeployer)),
                    _permissions,
                    _projects,
                    _directory,
                    _trustedForwarder
                )
            })
        );
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 05: Periphery (Controller + Price Feeds + Deadlines)
    // ════════════════════════════════════════════════════════════════════

    function _deployPeriphery() internal {
        // Deploy ETH/USD price feed.
        IJBPriceFeed ethUsdFeed = _deployEthUsdFeed();
        IJBPriceFeed matchingFeed =
            _prices.priceFeedFor(0, JBCurrencyIds.ETH, uint32(uint160(JBConstants.NATIVE_TOKEN)));
        if (address(matchingFeed) == address(0)) {
            // CREATE2 via the precompile pipeline (no constructor args) so the matching feed lands at the
            // same address on every chain. Previously this used plain `new`, which depended on the safe's
            // per-chain nonce and produced a different address each time.
            matchingFeed = IJBPriceFeed(
                _deployPrecompiledIfNeeded({
                    artifactName: "JBMatchingPriceFeed", salt: MATCHING_FEED_SALT, ctorArgs: ""
                })
            );
        }

        // All chains: native = ETH.
        _ensureDefaultPriceFeed({
            projectId: 0,
            pricingCurrency: JBCurrencyIds.USD,
            unitCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            expectedFeed: ethUsdFeed
        });
        _ensureDefaultPriceFeed({
            projectId: 0, pricingCurrency: JBCurrencyIds.USD, unitCurrency: JBCurrencyIds.ETH, expectedFeed: ethUsdFeed
        });
        _ensureDefaultPriceFeed({
            projectId: 0,
            pricingCurrency: JBCurrencyIds.ETH,
            unitCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            expectedFeed: matchingFeed
        });

        // Deploy USDC/USD feed.
        _deployUsdcFeed();

        // Deploy deadlines (no constructor args).
        _deployPrecompiledIfNeeded({artifactName: "JBDeadline3Hours", salt: DEADLINES_SALT, ctorArgs: ""});
        _deployPrecompiledIfNeeded({artifactName: "JBDeadline1Day", salt: DEADLINES_SALT, ctorArgs: ""});
        _deployPrecompiledIfNeeded({artifactName: "JBDeadline3Days", salt: DEADLINES_SALT, ctorArgs: ""});
        _deployPrecompiledIfNeeded({artifactName: "JBDeadline7Days", salt: DEADLINES_SALT, ctorArgs: ""});

        // Deploy the Controller — uses the omnichain deployer address.
        bytes32 coreSalt = keccak256(abi.encode(CORE_DEPLOYMENT_NONCE));
        _controller = JBController(
            _deployPrecompiledIfNeeded({
                artifactName: "JBController",
                salt: coreSalt,
                ctorArgs: abi.encode(
                    _directory,
                    _fundAccess,
                    _permissions,
                    _prices,
                    _projects,
                    _rulesets,
                    _splits,
                    _tokens,
                    address(_omnichainDeployer),
                    _trustedForwarder
                )
            })
        );

        if (!_directory.isAllowedToSetFirstController(address(_controller))) {
            _directory.setIsAllowedToSetFirstController(address(_controller), true);
        }
    }

    function _deployEthUsdFeed() internal returns (IJBPriceFeed feed) {
        uint256 L2GracePeriod = 3600 seconds;

        // Ethereum Mainnet
        if (block.chainid == 1) {
            feed = _deployChainlinkFeed({
                salt: USD_NATIVE_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419),
                threshold: 3600 seconds
            });
        }
        // Ethereum Sepolia
        else if (block.chainid == 11_155_111) {
            feed = _deployChainlinkFeed({
                salt: USD_NATIVE_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306),
                threshold: 3600 seconds
            });
        }
        // Optimism
        else if (block.chainid == 10) {
            feed = _deployChainlinkSequencerFeed({
                salt: USD_NATIVE_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5),
                threshold: 3600 seconds,
                sequencerFeed: AggregatorV2V3Interface(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389),
                gracePeriod: L2GracePeriod
            });
        }
        // Optimism Sepolia
        else if (block.chainid == 11_155_420) {
            feed = _deployChainlinkFeed({
                salt: USD_NATIVE_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x61Ec26aA57019C486B10502285c5A3D4A4750AD7),
                threshold: 3600 seconds
            });
        }
        // Base
        else if (block.chainid == 8453) {
            feed = _deployChainlinkSequencerFeed({
                salt: USD_NATIVE_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70),
                threshold: 3600 seconds,
                sequencerFeed: AggregatorV2V3Interface(0xBCF85224fc0756B9Fa45aA7892530B47e10b6433),
                gracePeriod: L2GracePeriod
            });
        }
        // Base Sepolia
        // Verified: 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1 is the Chainlink ETH/USD feed on Base Sepolia
        // (description() returns "ETH / USD", 8 decimals, actively updated).
        else if (block.chainid == 84_532) {
            feed = _deployChainlinkFeed({
                salt: USD_NATIVE_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1),
                threshold: 3600 seconds
            });
        }
        // Arbitrum
        else if (block.chainid == 42_161) {
            feed = _deployChainlinkSequencerFeed({
                salt: USD_NATIVE_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
                threshold: 3600 seconds,
                sequencerFeed: AggregatorV2V3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D),
                gracePeriod: L2GracePeriod
            });
        }
        // Arbitrum Sepolia
        else if (block.chainid == 421_614) {
            feed = _deployChainlinkFeed({
                salt: USD_NATIVE_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165),
                threshold: 3600 seconds
            });
        }
        // TODO: Tempo ETH/USD feed commented out until chain is ready.
        else {
            revert("Unsupported chain for ETH/USD feed");
        }
    }

    function _deployUsdcFeed() internal {
        uint256 L2GracePeriod = 3600 seconds;
        IJBPriceFeed usdcFeed;
        address usdc;

        if (block.chainid == 1) {
            usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            usdcFeed = _deployChainlinkFeed({
                salt: USDC_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6),
                threshold: 86_400 seconds
            });
        } else if (block.chainid == 11_155_111) {
            usdc = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
            usdcFeed = _deployChainlinkFeed({
                salt: USDC_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E),
                threshold: 86_400 seconds
            });
        } else if (block.chainid == 10) {
            usdc = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
            usdcFeed = _deployChainlinkSequencerFeed({
                salt: USDC_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3),
                threshold: 86_400 seconds,
                sequencerFeed: AggregatorV2V3Interface(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389),
                gracePeriod: L2GracePeriod
            });
        } else if (block.chainid == 11_155_420) {
            usdc = 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;
            usdcFeed = _deployChainlinkFeed({
                salt: USDC_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x6e44e50E3cc14DD16e01C590DC1d7020cb36eD4C),
                threshold: 86_400 seconds
            });
        } else if (block.chainid == 8453) {
            usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
            usdcFeed = _deployChainlinkSequencerFeed({
                salt: USDC_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B),
                threshold: 86_400 seconds,
                sequencerFeed: AggregatorV2V3Interface(0xBCF85224fc0756B9Fa45aA7892530B47e10b6433),
                gracePeriod: L2GracePeriod
            });
        } else if (block.chainid == 84_532) {
            usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
            // Base Sepolia USDC/USD Chainlink feed.
            // Verified at https://docs.chain.link/data-feeds/price-feeds/addresses?network=base&networkType=testnet
            usdcFeed = _deployChainlinkFeed({
                salt: USDC_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165),
                threshold: 86_400 seconds
            });
        } else if (block.chainid == 42_161) {
            usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
            usdcFeed = _deployChainlinkSequencerFeed({
                salt: USDC_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3),
                threshold: 86_400 seconds,
                sequencerFeed: AggregatorV2V3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D),
                gracePeriod: L2GracePeriod
            });
        } else if (block.chainid == 421_614) {
            usdc = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
            usdcFeed = _deployChainlinkFeed({
                salt: USDC_FEED_SALT,
                chainlinkFeed: AggregatorV3Interface(0x0153002d20B96532C639313c2d54c3dA09109309),
                threshold: 86_400 seconds
            });
        }
        // TODO: Tempo USDC feed commented out until chain is ready.
        else {
            revert("Unsupported chain for USDC feed");
        }

        _ensureDefaultPriceFeed({
            projectId: 0,
            pricingCurrency: JBCurrencyIds.USD,
            // forge-lint: disable-next-line(unsafe-typecast)
            unitCurrency: uint32(uint160(usdc)),
            expectedFeed: usdcFeed
        });
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 06: Croptop
    // ════════════════════════════════════════════════════════════════════

    function _deployCroptop() internal {
        _cpnProjectId = _ensureProjectExists(_CPN_PROJECT_ID);

        _ctPublisher = CTPublisher(
            _deployPrecompiledIfNeeded({
                artifactName: "CTPublisher",
                salt: CT_PUBLISHER_SALT,
                ctorArgs: abi.encode(_directory, _permissions, _cpnProjectId, _trustedForwarder)
            })
        );

        _ctDeployer = CTDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "CTDeployer",
                salt: CT_DEPLOYER_SALT,
                ctorArgs: abi.encode(
                    _permissions,
                    _projects,
                    IJB721TiersHookDeployer(address(_hookDeployer)),
                    _ctPublisher,
                    _suckerRegistry,
                    _trustedForwarder
                )
            })
        );

        _ctProjectOwner = CTProjectOwner(
            _deployPrecompiledIfNeeded({
                artifactName: "CTProjectOwner",
                salt: CT_PROJECT_OWNER_SALT,
                ctorArgs: abi.encode(_permissions, _projects, _ctPublisher)
            })
        );
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 07: Revnet (REVLoans + REVDeployer + $REV)
    // ════════════════════════════════════════════════════════════════════

    function _deployRevnet() internal {
        _revProjectId = _ensureProjectExists(_REV_PROJECT_ID);

        // Deploy REVLoans.
        _revLoans = REVLoans(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "REVLoans",
                    salt: REV_LOANS_SALT,
                    ctorArgs: abi.encode(
                        _controller,
                        IJBSuckerRegistry(address(_suckerRegistry)),
                        _revProjectId,
                        safeAddress(),
                        _PERMIT2,
                        _trustedForwarder
                    )
                }))
        );

        // Deploy REVOwner — the runtime data hook that handles pay and cash out callbacks.
        _revOwner = REVOwner(
            _deployPrecompiledIfNeeded({
                artifactName: "REVOwner",
                salt: REV_OWNER_SALT,
                ctorArgs: abi.encode(
                    IJBBuybackHookRegistry(address(_buybackRegistry)),
                    _directory,
                    _revProjectId,
                    _suckerRegistry,
                    _revLoans,
                    msg.sender
                )
            })
        );

        // Predict REVDeployer's CREATE2 address so we can bind REVOwner BEFORE deploying it
        // (REVDeployer's constructor reads REVOwner.DEPLOYER() during initialization on some paths).
        bytes memory revDeployerArgs = abi.encode(
            _controller,
            _suckerRegistry,
            _revProjectId,
            IJB721TiersHookDeployer(address(_hookDeployer)),
            _ctPublisher,
            IJBBuybackHookRegistry(address(_buybackRegistry)),
            address(_revLoans),
            _trustedForwarder,
            address(_revOwner)
        );
        (address predictedRevDeployer,) = _isDeployed({
            salt: REV_DEPLOYER_SALT, creationCode: _loadArtifact("REVDeployer"), arguments: revDeployerArgs
        });
        if (address(_revOwner.DEPLOYER()) == address(0)) {
            _revOwner.setDeployer(IREVDeployer(predictedRevDeployer));
        }
        _revDeployer = REVDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "REVDeployer", salt: REV_DEPLOYER_SALT, ctorArgs: revDeployerArgs
            })
        );

        // Approve the deployer to configure the $REV project.
        _projects.approve({to: address(_revDeployer), tokenId: _revProjectId});

        // Configure the $REV revnet.
        if (address(_directory.controllerOf(_revProjectId)) == address(0)) _deployRevFeeProject();
    }

    function _deployRevFeeProject() internal {
        address operator = 0x6b92c73682f0e1fac35A18ab17efa5e77DDE9fE1;

        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] =
            JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: DECIMALS, currency: NATIVE_CURRENCY});

        bool hasRouter = address(_routerTerminalRegistry) != address(0);
        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](hasRouter ? 2 : 1);
        terminalConfigs[0] = JBTerminalConfig({terminal: _terminal, accountingContextsToAccept: accountingContexts});
        if (hasRouter) {
            terminalConfigs[1] = JBTerminalConfig({
                terminal: IJBTerminal(address(_routerTerminalRegistry)),
                accountingContextsToAccept: new JBAccountingContext[](0)
            });
        }

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
                // forge-lint: disable-next-line(unsafe-typecast)
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
                // forge-lint: disable-next-line(unsafe-typecast)
                chainId: PREMINT_CHAIN_ID,
                // forge-lint: disable-next-line(unsafe-typecast)
                count: uint104(1_550_000 * DECIMAL_MULTIPLIER),
                beneficiary: operator
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
            scopeCashOutsToLocalBalances: false,
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

        bool hasRouter = address(_routerTerminalRegistry) != address(0);
        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](hasRouter ? 2 : 1);
        terminalConfigs[0] = JBTerminalConfig({terminal: _terminal, accountingContextsToAccept: accountingContexts});
        if (hasRouter) {
            terminalConfigs[1] = JBTerminalConfig({
                terminal: IJBTerminal(address(_routerTerminalRegistry)),
                accountingContextsToAccept: new JBAccountingContext[](0)
            });
        }

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
                // forge-lint: disable-next-line(unsafe-typecast)
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
            scopeCashOutsToLocalBalances: false,
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
        if (address(_directory.controllerOf(_cpnProjectId)) == address(0)) {
            _projects.approve({to: address(_revDeployer), tokenId: _cpnProjectId});

            _revDeployer.deployFor({
                revnetId: _cpnProjectId,
                configuration: cpnConfig,
                terminalConfigurations: terminalConfigs,
                suckerDeploymentConfiguration: suckerConfig,
                tiered721HookConfiguration: hookConfig,
                allowedPosts: allowedPosts
            });
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 08b: NANA Revnet (project ID 1)
    // ════════════════════════════════════════════════════════════════════

    function _deployNanaRevnet() internal {
        uint256 feeProjectId = _FEE_PROJECT_ID;
        address operator = 0x80a8F7a4bD75b539CE26937016Df607fdC9ABeb5;

        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] =
            JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});

        bool hasRouter = address(_routerTerminalRegistry) != address(0);
        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](hasRouter ? 2 : 1);
        terminalConfigs[0] = JBTerminalConfig({terminal: _terminal, accountingContextsToAccept: accountingContexts});
        if (hasRouter) {
            terminalConfigs[1] = JBTerminalConfig({
                terminal: IJBTerminal(address(_routerTerminalRegistry)),
                accountingContextsToAccept: new JBAccountingContext[](0)
            });
        }

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
            // forge-lint: disable-next-line(unsafe-typecast)
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
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory suckerConfig = _buildSuckerConfig(NANA_SUCKER_SALT);

        // Configure project ID 1 only if it has not already become the canonical NANA revnet.
        if (address(_directory.controllerOf(feeProjectId)) != address(0)) {
            if (!_isCanonicalRevnetProject({projectId: feeProjectId, expectedSymbol: "NANA"})) {
                revert Deploy_ProjectNotCanonical(feeProjectId);
            }
            return;
        }

        if (_projects.ownerOf(feeProjectId) != safeAddress()) revert Deploy_ProjectNotOwned(feeProjectId);

        // Approve the deployer to configure project ID 1.
        _projects.approve({to: address(_revDeployer), tokenId: feeProjectId});

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
        // Use canonical identity gates instead of generic ownership check.
        if (_projects.count() >= _BAN_PROJECT_ID && address(_directory.controllerOf(_BAN_PROJECT_ID)) != address(0)) {
            if (!_isCanonicalBannyProject()) {
                revert Deploy_ProjectNotCanonical(_BAN_PROJECT_ID);
            }
            return;
        }

        address operator = _BAN_OPS_OPERATOR;

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

        Banny721TokenUriResolver resolver;
        {
            bytes memory resolverArgs = abi.encode(
                bannyBody,
                defaultNecklace,
                defaultMouth,
                defaultStandardEyes,
                defaultAlienEyes,
                safeAddress(),
                _trustedForwarder
            );
            // Detect first-time deploy so we can run the one-shot initialization
            // (setMetadata + transferOwnership) only when fresh.
            (, bool resolverExisted) = _isDeployed({
                salt: BAN_RESOLVER_SALT,
                creationCode: _loadArtifact("Banny721TokenUriResolver"),
                arguments: resolverArgs
            });
            resolver = Banny721TokenUriResolver(
                _deployPrecompiledIfNeeded({
                    artifactName: "Banny721TokenUriResolver", salt: BAN_RESOLVER_SALT, ctorArgs: resolverArgs
                })
            );
            _bannyResolver = resolver;
            if (!resolverExisted) {
                resolver.setMetadata({
                    description: "A piece of Banny Retail.",
                    url: "https://retail.banny.eth.shop",
                    baseUri: "https://bannyverse.infura-ipfs.io/ipfs/"
                });
                // Ownership transfer to `_BAN_OPS_OPERATOR` happens in `_finalizeBannyOwnership` after
                // every drop registration, so this script retains owner-only authority for
                // `setSvgHashesOf` + `setProductNames` across all drops.
            }
        }

        // Build the Banny revnet config.
        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] =
            JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: DECIMALS, currency: NATIVE_CURRENCY});

        bool hasRouter = address(_routerTerminalRegistry) != address(0);
        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](hasRouter ? 2 : 1);
        terminalConfigs[0] = JBTerminalConfig({terminal: _terminal, accountingContextsToAccept: accountingContexts});
        if (hasRouter) {
            terminalConfigs[1] = JBTerminalConfig({
                terminal: IJBTerminal(address(_routerTerminalRegistry)),
                accountingContextsToAccept: new JBAccountingContext[](0)
            });
        }

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
                // forge-lint: disable-next-line(unsafe-typecast)
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
                // forge-lint: disable-next-line(unsafe-typecast)
                chainId: PREMINT_CHAIN_ID,
                // forge-lint: disable-next-line(unsafe-typecast)
                count: uint104(1_000_000 * DECIMAL_MULTIPLIER),
                beneficiary: operator
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

        // Initial split operator is the Sphinx Safe so this script can call `hook.adjustTiers` when
        // registering every Banny drop (Phases 09b, 09c, …). Operator is transferred to `operator`
        // (the canonical Banny ops EOA) by `_finalizeBannyOwnership` after the last drop. Auto-issuance
        // beneficiaries below still flow to `operator`, so the initial launch mints land correctly
        // regardless of who holds the operator role.
        REVConfig memory banConfig = REVConfig({
            description: REVDescription(
                "Banny Network", "BAN", "ipfs://Qme34ww9HuwnsWF6sYDpDfpSdYHpPCGsEyJULk1BikCVYp", BAN_ERC20_SALT
            ),
            baseCurrency: ETH_CURRENCY,
            splitOperator: safeAddress(),
            scopeCashOutsToLocalBalances: false,
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
            // forge-lint: disable-next-line(unsafe-typecast)
            encodedIPFSUri: bytes32(""),
            category: bannyBodyCategory,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: true,
                cantIncreaseDiscountPercent: true,
                cantBuyWithCredits: false
            }),
            splitPercent: 0,
            splits: new JBSplit[](0)
        });
        tiers[1] = JB721TierConfig({
            price: uint104(1 * (10 ** (DECIMALS - 1))),
            initialSupply: 1000,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            // forge-lint: disable-next-line(unsafe-typecast)
            encodedIPFSUri: bytes32(""),
            category: bannyBodyCategory,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: true,
                cantIncreaseDiscountPercent: true,
                cantBuyWithCredits: false
            }),
            splitPercent: 0,
            splits: new JBSplit[](0)
        });
        tiers[2] = JB721TierConfig({
            price: uint104(1 * (10 ** (DECIMALS - 2))),
            initialSupply: 10_000,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            // forge-lint: disable-next-line(unsafe-typecast)
            encodedIPFSUri: bytes32(""),
            category: bannyBodyCategory,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: true,
                cantIncreaseDiscountPercent: true,
                cantBuyWithCredits: false
            }),
            splitPercent: 0,
            splits: new JBSplit[](0)
        });
        tiers[3] = JB721TierConfig({
            price: uint104(1 * (10 ** (DECIMALS - 4))),
            initialSupply: 999_999_999,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            // forge-lint: disable-next-line(unsafe-typecast)
            encodedIPFSUri: bytes32(""),
            category: bannyBodyCategory,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: true,
                cantIncreaseDiscountPercent: true,
                cantBuyWithCredits: false
            }),
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
        (uint256 banProjectId,) = _revDeployer.deployFor({
            revnetId: 0,
            configuration: banConfig,
            terminalConfigurations: terminalConfigs,
            suckerDeploymentConfiguration: suckerConfig,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });
        if (banProjectId != _BAN_PROJECT_ID) revert Deploy_BannyProjectIdMismatch(banProjectId, _BAN_PROJECT_ID);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 09b: Banny Drop 1 (47 retail items)
    // ════════════════════════════════════════════════════════════════════

    /// @notice Adds the Drop 1 product set (47 tiered NFT items, categories 1-16) to the BAN project's
    /// JB721TiersHook and registers their names + SVG hashes on the Banny URI resolver.
    /// @dev Mirrors `banny-retail-v6/script/Drop1.s.sol` so the entire BAN launch (project creation +
    /// drop registration) lands in a single Sphinx proposal. Idempotent: if the hook already has the drop
    /// tiers (maxTierId >= 4 + 47 = 51), skips. The 4-tier baseline is what `_deployBanny` sets up via
    /// `REVDeployer.deployFor(tiered721HookConfiguration: ...)`. Ownership transfers (resolver + split
    /// operator) are deferred to `_finalizeBannyOwnership` so subsequent drops can still write.
    function _registerBannyDrop1() internal {
        IJB721TiersHook hook = _revOwner.tiered721HookOf(_BAN_PROJECT_ID);
        IJB721TiersHookStore store = hook.STORE();
        Banny721TokenUriResolver resolver = Banny721TokenUriResolver(address(store.tokenUriResolverOf(address(hook))));

        // Idempotency: 4 baseline tiers + 47 drop tiers = 51. Skip if already populated.
        uint256 maxBefore = store.maxTierIdOf(address(hook));
        if (maxBefore >= 51) return;

        // Sanity gate: the baseline must be exactly 4 (no other drops have landed). If something else
        // shifted the tier count, abort rather than mis-target the metadata writes.
        if (maxBefore != 4) revert Deploy_BannyProjectIdMismatch(maxBefore, 4);

        uint256 decimals = DECIMALS;
        string[] memory names = new string[](47);
        bytes32[] memory svgHashes = new bytes32[](47);
        JB721TierConfig[] memory products = new JB721TierConfig[](47);

        // Desk
        names[0] = "Work Station";
        svgHashes[0] = bytes32(0xab22e30cb6daaac109ea557a14af9b65f680d46cc563a0b25dd42483f9286bf7);
        products[0] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 50,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x5665b0c125d1bccccb78cc0ffc429e66ce41ed3bccebba51209d04636cadbd2c),
            category: 1
        });
        // Hay field
        names[1] = "Hay Field";
        svgHashes[1] = bytes32(0x62f97f668e227ab9d6eaf5bd35504974f3df175ee2d952c39add59b7d141c0de);
        products[1] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 250,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x233dd4173ef4ed0f60822a469277bb328b5ae056d8980301f7bd7ad9df780099),
            category: 1
        });
        // Pew pew
        names[2] = "Pew Pew";
        svgHashes[2] = bytes32(0x71f6918188cd0bc9eb1d5baed9340491efb41af1d358bbeb10912a02e95323f8);
        products[2] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 150,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x6cb06872575a04a0c4527157eb4719be10b6474d08aa2ce2a4ac5bcb0da996ea),
            category: 2
        });
        // Bandolph staff
        names[3] = "Bandolph Staff";
        svgHashes[3] = bytes32(0x790e607150e343fd457bb0cefe5fd12cd216b722dabfa19adbee1f1e537fd1c7);
        products[3] = _drop1Tier({
            price: uint104(125 * (10 ** (decimals - 3))),
            initialSupply: 250,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x7206771942e806053d6ed8aa90040e53a07319e4fd1f938fc4a10879b7bd2da9),
            category: 2
        });
        // Block chain — the first reserves-bearing tier in Drop 1. Sets the hook's
        // `defaultReserveBeneficiaryOf` to `_BAN_OPS_OPERATOR` so that every later tier in the array which
        // has `reserveFrequency > 0 && reserveBeneficiary == address(0)` (e.g. Nerd Glasses, Investor
        // Shades, all of Drop 2) can inherit a non-zero beneficiary. Without this, `recordAddTiers`
        // reverts with `MissingReserveBeneficiary` at tier 4 because the default has not been set yet —
        // Banny Vision Pro (the intended default-setter at index 7) only runs later in the sort order.
        names[4] = "Block Chain";
        svgHashes[4] = bytes32(0x5e609d387ea091bc8884a753ddd28dd43b8ed1243b29de6e9354ef1ab109a0b9);
        products[4] = _drop1Tier({
            price: uint104(125 * (10 ** (decimals - 2))),
            initialSupply: 12,
            reserveFrequency: 12,
            reserveBeneficiary: _BAN_OPS_OPERATOR,
            useReserveBeneficiaryAsDefault: true,
            encodedIPFSUri: bytes32(0xef6478be50575bade53e7ce4c9fb5b399643bcabed94f2111afb63e97fb9fd44),
            category: 3
        });
        // Astronaut Head
        names[5] = "Astronaut Head";
        svgHashes[5] = bytes32(0x7054504d4eef582f2e3411df719fba9d90e94c2054bf48e2efa175b4f37cc1e9);
        products[5] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 1000,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xe26d20762024435aedd91058ac9bc9900d719e1f7a04cace501d83a4c1f40941),
            category: 4
        });
        // Nerd
        names[6] = "Nerd Glasses";
        svgHashes[6] = bytes32(0x964356f8cbc40b81653a219d94da9d49d0bd5b745aa6bf4db16a14aa81c129ac);
        products[6] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 100,
            reserveFrequency: 25,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x9f76cb495fd79397cba4fe3d377a5aa2fdd63df218f3b3022c6cc8e32478b494),
            category: 6
        });
        // Banny vision pro — inherits the default reserve beneficiary already set by Block Chain
        // (index 4). No need to re-set the default.
        names[7] = "Banny Vision Pro";
        svgHashes[7] = bytes32(0x12702d5d843aff058610a01286446401be4175c27abaaec144d8970f99db34e2);
        products[7] = _drop1Tier({
            price: uint104(1 * (10 ** decimals)),
            initialSupply: 100,
            reserveFrequency: 25,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xf01423f9dae3de4adc7e372e6902a351e2c6193a385dde90f5baf37165914831),
            category: 6
        });
        // Cyberpunk glasses
        names[8] = "Cyberpunk Glasses";
        svgHashes[8] = bytes32(0x5930f0bb8cb34d82b88a13391bcccf936e09be535f2848ba7911b2a98615585d);
        products[8] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 150,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x325c138f1f38e5b5f90a57a248a2f5afe6af738b2adfc825cf9f413bbcf50fa1),
            category: 6
        });
        // Investor shades
        names[9] = "Investor Shades";
        svgHashes[9] = bytes32(0x4410654936785cff70498421a8805ad2f9d5101a8c18168264ef94df671db10e);
        products[9] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 250,
            reserveFrequency: 50,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x7dc7e556a7ac39c473da85165df3d094c6ed9258003fb7dc3d9a8582bcb0dc7f),
            category: 6
        });
        // Proff glasses
        names[10] = "Proff Glasses";
        svgHashes[10] = bytes32(0x54004065d83ca03befdf72236331f5b532c00920613d8774ebd8edbf277c345a);
        products[10] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 200,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xb06dbd64696994798dee9e00d406a649191524a95e715532f1bdebc92f00aebd),
            category: 6
        });
        // Gap tooth
        names[11] = "Gap Teeth";
        svgHashes[11] = bytes32(0x5b5a29873435b40784f64c5d9bb5d95ecebd433c57493e38f3eb816a0dd9fd7f);
        products[11] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 1))),
            initialSupply: 50,
            reserveFrequency: 10,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x52815d712399165b921df61795581a8c20ad9acf3502e777e20a782b7bc11d54),
            category: 7
        });
        // Dorthy shoes
        names[12] = "Dorthy Shoes";
        svgHashes[12] = bytes32(0x67a973e1023d2a9a37270e4345f9e93b30828ec64bc81c0d1d56028f8e976491);
        products[12] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 250,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x8a1b694033a47ad08b648d2608fa1b86dccdb0f431795c470605a819988f55ad),
            category: 8
        });
        // Astronaut boots
        names[13] = "Astronaut Boots";
        svgHashes[13] = bytes32(0x539f9417dd22ba8aacd4029753f6058b5f905eef2a3b07acb519c964fc57ce50);
        products[13] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 250,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x39cd82854f76c22afccaf4ad6f055d4e225c2e225f322154f1c3d327cbaccb5a),
            category: 8
        });
        // Flops
        names[14] = "Flops";
        svgHashes[14] = bytes32(0x0a322735b4b89b7a593a86615ccc03e14867ce1cfd57c1aa9a61a841d9498103);
        products[14] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 500,
            reserveFrequency: 10,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x4e87f483ea20c1537f24c2a586acd14819ca2a6cba1bab68365361e45374f9f9),
            category: 8
        });
        // Astronaut Body
        names[15] = "Astronaut Suit";
        svgHashes[15] = bytes32(0xdbcfc1891ab9d56cb964f3432f867a77293352e38edca3b59b34061e46a31b83);
        products[15] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 250,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x5fbc1c58d608acd436c18e11edc72d3ae436e1a4c15d127b28a9a24879013d3c),
            category: 9
        });
        // Sweatsuit
        names[16] = "Sweatsuit";
        svgHashes[16] = bytes32(0xfbb3a6dde059e3e3115c3e83fd675d1739ec29afa62999fa759ed878f48e9aa2);
        products[16] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 1))),
            initialSupply: 24,
            reserveFrequency: 6,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x823466de69eaf605d3a62366e5e9dbd6649a71da146f791f94628d4749a2da55),
            category: 9
        });
        // Dorthy dress
        names[17] = "Dorthy Dress";
        svgHashes[17] = bytes32(0xfc0eda6d0165d339239bfda3cf68d630949b03c588e3b6d45175c6fc8f00e289);
        products[17] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 250,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x017db86219678b824995b8556e7073d65af87212671312212365497708675c41),
            category: 9
        });
        // Geisha body
        names[18] = "Geisha Gown";
        svgHashes[18] = bytes32(0x5f8c77bc896a90a35580078ee7ea51460b5694aec68db3d749fd1dc0e9b05c6c);
        products[18] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 100,
            reserveFrequency: 50,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xdf7d4084b087b22cc172e1df3a2b465b5386a950e9bcd53ed424014a0a86ee57),
            category: 9
        });
        // Baggies
        names[19] = "Baggies";
        svgHashes[19] = bytes32(0x2f0cab70c7d07048ccc7b6855bba39cdd95be15a109c8eaa401d9be6d503ca2a);
        products[19] = _drop1Tier({
            price: uint104(15 * (10 ** (decimals - 2))),
            initialSupply: 30,
            reserveFrequency: 15,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x745b3b4f18aab6ad0d8465d34751ca8eb5b9c267dee6ec8bf63686b508afacf3),
            category: 10
        });
        // Jonny utah shirt
        names[20] = "Jonny Utah Shirt";
        svgHashes[20] = bytes32(0xf62770cf77965461df8528baec000228c713e749b4dcc12e278b1025507dc0ff);
        products[20] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 250,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x815c7dfb119da1e3802754f8ce364caf7a8069e331e35c3f20446800579d8df8),
            category: 11
        });
        // Doc coat
        names[21] = "Doc Coat";
        svgHashes[21] = bytes32(0x6650b989b4ad53d12fd306bf4a12f5afbca2072c3241fdcb96e434443039d1f7);
        products[21] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 250,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xc77fe2f93a5a48ad7f59a3c6c40dd76317e47605fcb74b85a4c5bea160fdab6e),
            category: 11
        });
        // Goat jersey
        names[22] = "Goat Jersey";
        svgHashes[22] = bytes32(0xcca8b9f46f75822d78e7f3125ba4832e24ffe1711f6f01d00cdccb6669f752f2);
        products[22] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 1))),
            initialSupply: 50,
            reserveFrequency: 10,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x2b62afa12feb307f005902e6bec09f15f8f5d7ba09d937f1162e5d2f00c21e12),
            category: 11
        });
        // Irie tshirt
        names[23] = "Irie Shirt";
        svgHashes[23] = bytes32(0xd26b2eaad19396b85f4ae09c702717969b72b8c63021821e0d35addd85e7bbd1);
        products[23] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 250,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x4d4b149bded92db977ac35a77bcfff72270eaee404db8751b27ec18030511d3b),
            category: 11
        });
        // Punk jacket
        names[24] = "Punk Jacket";
        svgHashes[24] = bytes32(0x44cb972aab236c8c01afef7addb0f19a0fab02cfdc7b5065d662b53ab970f310);
        products[24] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 1))),
            initialSupply: 50,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x5ec40dc2aad2a009266337a198d4b9098cd968d08c06cdc328efd4789f974aa4),
            category: 11
        });
        // Zipper jacket
        names[25] = "Zipper Jacket";
        svgHashes[25] = bytes32(0x7177dfec617d77cf78e8393fe373b68c7bc755edd1541c0decc952e99ec80304);
        products[25] = _drop1Tier({
            price: uint104(15 * (10 ** (decimals - 2))),
            initialSupply: 25,
            reserveFrequency: 25,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xb8658c65907f280bfbd228ec384f0dfdfe55401505dc0f303d7d3d6a68a6414b),
            category: 11
        });
        // Zucco tshirt
        names[26] = "Zucco Tshirt";
        svgHashes[26] = bytes32(0x2a69ce643e565cb4fe648dc9b03020b0749ec780748d43153ee4c6770c76adbf);
        products[26] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 1000,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x04e22ea49d80f346b7a5a9013169470824f71faa7d9e0155a71f4afc3fa63f89),
            category: 11
        });
        // Ice Cube
        names[27] = "Ice Cube";
        svgHashes[27] = bytes32(0x032b50792f9929066168187acd5eeb101f8528f538ef850913c81dc4b6452842);
        products[27] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 250,
            reserveFrequency: 50,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xf7c17eff468f5dd227b991d773b7a36b93cd997751547f9908a4bf33e31ba701),
            category: 11
        });
        // Club beanie
        names[28] = "Club Beanie";
        svgHashes[28] = bytes32(0x0a8d7c8ff075db0e66638bb51eea732a53641b09b39de68d1cbeafe9099f9b6e);
        products[28] = _drop1Tier({
            price: uint104(15 * (10 ** (decimals - 3))),
            initialSupply: 300,
            reserveFrequency: 50,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x9a29e975b191f800744d74b11c580fdd74b2db73c95426af36e28cf00d66da97),
            category: 12
        });
        // Dorthy hair
        names[29] = "Dorthy Hair";
        svgHashes[29] = bytes32(0x5f2bec3082d7039474f6cba827a3fbd4d4f8e21f22d304edfbc6de77a8b529cf);
        products[29] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 250,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x52a03dc3e983121f275cadc2d86626e0fca8a9901f3dc7d0bbee826e5d3d409d),
            category: 12
        });
        // Farmer hat
        names[30] = "Farmer Hat";
        svgHashes[30] = bytes32(0xcf90bc8459345bcfae00796c4641c0bc8868c01d6339a54ef4d3c4fa1737cfd8);
        products[30] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 250,
            reserveFrequency: 25,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xc583623dc7a3e61bfc04813f8c975eba8a22aeafe3d741edff1e2c97ac520737),
            category: 12
        });
        // Geisha hair
        names[31] = "Geisha Hair";
        svgHashes[31] = bytes32(0x17b939b04709c357480bdfa54cf2007d7898f4bf048bf12efa6cd8e3af4d711c);
        products[31] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 1))),
            initialSupply: 100,
            reserveFrequency: 25,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x58f8e217cfafd0a6feff40f4822790cdc19aba5dd4d4948f4c1bd5e313c90e8d),
            category: 12
        });
        // Headphones
        names[32] = "Headphones";
        svgHashes[32] = bytes32(0xf1850876ede53102140881e04a4a0e532ba6a08bc0fb64dee279d11c98d64dbf);
        products[32] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 500,
            reserveFrequency: 10,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x3e67840649fabab6d62f92bad701a6248b77f86ea8fcd66dc88dfbcba1134d85),
            category: 12
        });
        // Natty dread
        names[33] = "Natty Dred";
        svgHashes[33] = bytes32(0x04ae3342ce08da16f61d32e4ce7034dff0223e462afa48019b90c94afc19b939);
        products[33] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 100,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xd4724e692969066fc0b3587b8e18d1589205d1e1f133d7f9f8d63d14b6d1862f),
            category: 12
        });
        // Peachhair
        names[34] = "Peach Hair";
        svgHashes[34] = bytes32(0xdf7b9e74c552908290a05388f905a503978a289c44ffb61e510df43f2955d435);
        products[34] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 100,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xde4c6e589f4e99cda7205236a99db750638236007b2dd03d79de1146102d7f81),
            category: 12
        });
        // Proff hair
        names[35] = "Proff Hair";
        svgHashes[35] = bytes32(0x501769b2b47a8aedf4b328f6cf0076200df07ce2087f5e082f49e815f54595b9);
        products[35] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 200,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x766001db70e4a18e76dbbd9e4b0f9e47b5a9c4daa1a7c3727190a154daabfa1c),
            category: 12
        });
        // Catana
        names[36] = "Catana";
        svgHashes[36] = bytes32(0xbe7e7bb20da87fffa92e867bf0cd3267df180e24ba6eae7a1d434c56856ef2f5);
        products[36] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 250,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xa4d2eb02df6eb99cbbdc3603a116b3b9dcd45f865a8c8396611ea5f879deee59),
            category: 13
        });
        // Chefs knife
        names[37] = "Chefs Knife";
        svgHashes[37] = bytes32(0x705180b5aee8e57d0a0783d22fc30dc95e3e84fac36e9d96fef96fabfa58d1f9);
        products[37] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 500,
            reserveFrequency: 100,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x18abc38e7f1c5c014398f705131aac80196dcd0da2b5f02c103e1a549433e8b3),
            category: 13
        });
        // Cheap beer
        names[38] = "Cheap Beer";
        svgHashes[38] = bytes32(0x993a2c657f43e19820f3e23677e650705d0c8c6a0ccd88a381aa54d2da7ba047);
        products[38] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 2000,
            reserveFrequency: 100,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xc498a98bea66a8b44297631f136a7326f7a28b882058829588979b186d06baff),
            category: 13
        });
        // Constitution
        names[39] = "Constitution";
        svgHashes[39] = bytes32(0xaf0826d8eac1e57789077f43e6f979488da6f619f72f9f0ff50a52ebcca3bfa3);
        products[39] = _drop1Tier({
            price: uint104(1787 * (10 ** (decimals - 6))),
            initialSupply: 1000,
            reserveFrequency: 100,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x3bd1186293e2d3e4def734a669c348976e1ba0cdc628a19cd5a3b38e0bee28f9),
            category: 13
        });
        // DJ booth
        names[40] = "DJ Deck";
        svgHashes[40] = bytes32(0x2c9538556986d134ddec2831e768233f587b242e887df9bb359b3aefffa3c5a6);
        products[40] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 1))),
            initialSupply: 10,
            reserveFrequency: 10,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x6b8bfbf33e574747b69039adfc6788101047a4593db7ea7ff4f6fa5a890e9ecf),
            category: 13
        });
        // Gas can
        names[41] = "Gas Can";
        svgHashes[41] = bytes32(0x89808b70d019077e4f986b4a60af4ec15fc72ed022bc5e5476441d98f8ce1d1d);
        products[41] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 1))),
            initialSupply: 25,
            reserveFrequency: 25,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xf11d1cea4163e0dfa2be8d60b0cd82d075fb37d969e40439df4e91db53bf7f3e),
            category: 13
        });
        // Lightsaber
        names[42] = "Lightsaber";
        svgHashes[42] = bytes32(0xf7017a80e9fa4c3fc052a701c04374176620a8e5befa39b708a51293c4d8f406);
        products[42] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 250,
            reserveFrequency: 50,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xedf8136f97347d1fee1fc14b1b9cbdb6d170a75c3860a92664c56060712567f3),
            category: 13
        });
        // Potion
        names[43] = "Potion";
        svgHashes[43] = bytes32(0xefdbac65db3868ead1c1093ea20f0b2d77e9095567f6358e246ba160ec545e09);
        products[43] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 1))),
            initialSupply: 100,
            reserveFrequency: 25,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xbcc0c314f94ccb0f8f2717aff0b2096a28ace5b70465b5b4e106981fdbceb238),
            category: 13
        });
        // Dagger
        names[44] = "Dagger";
        svgHashes[44] = bytes32(0xaf60de81f2609b847b7d6e97ef6c09c9e3d91cabe6f955bd8828f342f1558738);
        products[44] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 150,
            reserveFrequency: 30,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x867d8d8b9da0b5d8a00024d548e5f6e33562d521dff8c245764b6206003d1970),
            category: 13
        });
        // Duct Tape
        names[45] = "Duct Tape";
        svgHashes[45] = bytes32(0x962ce657908ee4fb58b3e2d1f77109b36428e7a4446d6127bcb6c06aa2360637);
        products[45] = _drop1Tier({
            price: uint104((10 ** (decimals + 2))),
            initialSupply: 1,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x876078bdfb8cdcc4359bb946274a9964e84877beac0ecd59fbf293c3bc2457c9),
            category: 14
        });
        // Mouthstraw
        names[46] = "Wheat Straw";
        svgHashes[46] = bytes32(0x112b8217bb82aebc91e80c935244dce8aa30d4d8df5f98382054b97037dc0c94);
        products[46] = _drop1Tier({
            price: uint104(1 * (10 ** decimals)),
            initialSupply: 15,
            reserveFrequency: 15,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x1d1484b4b37a882e59ab5a01c1a32528e703e15156b9bb9b5372b61fec84c0df),
            category: 16
        });

        // Add the tiers. Capture the new maxTierId to derive the UPC range that received our writes.
        hook.adjustTiers({tiersToAdd: products, tierIdsToRemove: new uint256[](0)});
        uint256 maxAfter = store.maxTierIdOf(address(hook));
        // Drift guard: our 47 tiers must occupy exactly (maxBefore, maxAfter]. Anything else means another
        // ADJUST_721_TIERS call landed between proposal and execution and the metadata writes below would
        // target the wrong UPC range.
        if (maxAfter != maxBefore + 47) revert Deploy_BannyProjectIdMismatch(maxAfter, maxBefore + 47);

        uint256[] memory productIds = new uint256[](47);
        for (uint256 i; i < 47; i++) {
            productIds[i] = maxAfter - 46 + i;
        }
        resolver.setSvgHashesOf({upcs: productIds, svgHashes: svgHashes});
        resolver.setProductNames({upcs: productIds, names: names});
    }

    /// @dev Builds a JB721TierConfig with the fixed Drop-1 boilerplate (zero voting units, no discounts,
    /// no splits, all `cantBeRemoved`-style flags false). Only the per-tier fields the products actually
    /// vary on are taken as parameters; everything else is filled in here to keep the call sites readable.
    function _drop1Tier(
        uint104 price,
        uint32 initialSupply,
        uint16 reserveFrequency,
        address reserveBeneficiary,
        bool useReserveBeneficiaryAsDefault,
        bytes32 encodedIPFSUri,
        uint24 category
    )
        private
        pure
        returns (JB721TierConfig memory)
    {
        return JB721TierConfig({
            price: price,
            initialSupply: initialSupply,
            votingUnits: 0,
            reserveFrequency: reserveFrequency,
            reserveBeneficiary: reserveBeneficiary,
            encodedIPFSUri: encodedIPFSUri,
            category: category,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: useReserveBeneficiaryAsDefault,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: false,
                cantIncreaseDiscountPercent: false,
                cantBuyWithCredits: false
            }),
            splitPercent: 0,
            splits: new JBSplit[](0)
        });
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 09c: Banny Drop 2 (17 outfit items)
    // ════════════════════════════════════════════════════════════════════

    /// @notice Adds the Drop 2 product set (17 tiered NFT items) to the BAN project's
    /// JB721TiersHook and registers their names + SVG hashes on the Banny URI resolver.
    /// @dev Runs after `_registerBannyDrop1` so the default reserve beneficiary set by the Block Chain
    /// tier in Drop 1 is already in place. Idempotent: if the hook already has the drop tiers
    /// (maxTierId >= 51 + 17 = 68), skips. Reuses the `_drop1Tier` helper since the tier-config
    /// boilerplate is shared across drops.
    ///
    /// Tiers are pre-sorted by Banny resolver category number (backside=2, eyes=5, mouth=7, suit=9,
    /// headTop=12, hand=13) so `recordAddTiers` does not revert with `InvalidCategorySortOrder`.
    /// `reserveFrequency` encodes "1 reserved per N mints", so 5% = 20 and 10% = 10.
    function _registerBannyDrop2() internal {
        IJB721TiersHook hook = _revOwner.tiered721HookOf(_BAN_PROJECT_ID);
        IJB721TiersHookStore store = hook.STORE();
        Banny721TokenUriResolver resolver = Banny721TokenUriResolver(address(store.tokenUriResolverOf(address(hook))));

        // Idempotency: 4 baseline + 47 Drop 1 + 17 Drop 2 = 68. Skip if already populated.
        uint256 maxBefore = store.maxTierIdOf(address(hook));
        if (maxBefore >= 68) return;

        // Sanity gate: Drop 2 may only land directly on top of Drop 1 (maxTierId == 51). If something
        // else shifted the tier count, abort rather than mis-target the metadata writes.
        if (maxBefore != 51) revert Deploy_BannyProjectIdMismatch(maxBefore, 51);

        uint256 decimals = DECIMALS;
        string[] memory names = new string[](17);
        bytes32[] memory svgHashes = new bytes32[](17);
        JB721TierConfig[] memory products = new JB721TierConfig[](17);

        // Nunchucks — backside
        names[0] = "Nunchucks";
        svgHashes[0] = bytes32(0x3a56edaedaf6d8dfb3747251e550e071865acd2ec33c3a3f668f7bb7e1cdf58f);
        products[0] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 10,
            reserveFrequency: 10,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x623d9c0b2fd488ca8b6d93a9f20f89290989366a548e6ec7354bbd61311f0e12),
            category: 2
        });
        // Fierce Eyes — eyes
        names[1] = "Fierce Eyes";
        svgHashes[1] = bytes32(0xc2e8e326e98529041db4f4ce89c913a5099e83fbc59e3bd00b8544a5c9ea98b2);
        products[1] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 50,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xb5fd509939ccd462fbec901c3b33cda4a146fba01aec716a64f1a343d3a705a9),
            category: 5
        });
        // Glassy Eyes — eyes
        names[2] = "Glassy Eyes";
        svgHashes[2] = bytes32(0x426213d05aeb01485f42d580000ac3cbe4ba9023f0bd477109dab85b5b361299);
        products[2] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 50,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xf03b5e0420b2203a11f02f44c8ee76b9d2651fb1c0d7c756e11268abdb7f6a8c),
            category: 5
        });
        // Introspective Eyes — eyes
        names[3] = "Introspective Eyes";
        svgHashes[3] = bytes32(0xbcc073616c70da197d643ee582afa87041b4e486ab8e69f75c82d54a7ad77faa);
        products[3] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 1))),
            initialSupply: 10,
            reserveFrequency: 10,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x5f614933b94a7f16a5fe3385a1108be31cedfabccceeadc0aa8fa1936130a44c),
            category: 5
        });
        // Lashed Eyes — eyes
        names[4] = "Lashed Eyes";
        svgHashes[4] = bytes32(0x287e1e9929e99b96f71ac6f3b22906500c66eb9ee6774f88247bada62ad551d0);
        products[4] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 200,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xe02ba7e22c248ffff774aa351c92dcf8c15d4d6d903e70474cb5524df9ade79b),
            category: 5
        });
        // Surprised Eyes — eyes
        names[5] = "Surprised Eyes";
        svgHashes[5] = bytes32(0x7a6cc5372e20e217e427e451393cdb0541c94e56f9739be3b0737db5453e67c6);
        products[5] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 50,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x48968871dd045671e3e79ccee2330afaf4b7aa5ef213324132bbba823a961276),
            category: 5
        });
        // Lipstick — mouth
        names[6] = "Lipstick";
        svgHashes[6] = bytes32(0x0f509b77bc24068e593e2fa79efc80c507cec9ee2892791057e1dfeb6e3db4d6);
        products[6] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 50,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xc42aacdb29e89590b65d7a53c9942725eff2eafb2571cb96dc2dd23346617ebe),
            category: 7
        });
        // Open Mouth — mouth
        names[7] = "Open Mouth";
        svgHashes[7] = bytes32(0xec19f58288959a9f587ec0d6026d92d395c9b7f8f63e96312e97f91fecf7fdbc);
        products[7] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 50,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xf41dd39e89039f84af3e014cc5bf35017d864233be9f7ea0972b635c28686009),
            category: 7
        });
        // Kasaya — suit
        names[8] = "Kasaya";
        svgHashes[8] = bytes32(0xa5508a3488596ad6dfe03aca408c175781b27b640eecf80da8eadbcc33eb53e8);
        products[8] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 1))),
            initialSupply: 20,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xc0b84558f47050ca7a297179497161ab6dc64cc984f41a23fc918a151c4890e1),
            category: 9
        });
        // Overalls — suit
        names[9] = "Overalls";
        svgHashes[9] = bytes32(0xc909807ec6a464eee6ebf9154c81208f07ed161c780d954da6f839143fe664b9);
        products[9] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 2))),
            initialSupply: 50,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x83b0fde0e64c98aa58e2699f49b883ebcd49461dd2ddee6e6d26f454966a70e1),
            category: 9
        });
        // Chef Hat — headTop
        names[10] = "Chef Hat";
        svgHashes[10] = bytes32(0xb704274125c42913a61c577957981b7479be2096d0625b68bb34c96678be2323);
        products[10] = _drop1Tier({
            price: uint104(5 * (10 ** (decimals - 2))),
            initialSupply: 20,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xed52af40eca5f3d2543049a62b0c40581f9037234cd35de2e49dab0aa4767a65),
            category: 12
        });
        // Green Hat — headTop
        names[11] = "Green Hat";
        svgHashes[11] = bytes32(0xcbc6cac1188f0026880313c476a3e0da19194ed37d77b2ee9eef177115728a27);
        products[11] = _drop1Tier({
            price: uint104(2 * (10 ** (decimals - 3))),
            initialSupply: 200,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x7c618fc124661012a9c85356faeac8aae728b7738a0b3b676b058e39931c55b9),
            category: 12
        });
        // Ribbon — headTop
        names[12] = "Ribbon";
        svgHashes[12] = bytes32(0x12e705dd471bac110031f1c9598436eabd49908369f5ca2da0989eac73c45278);
        products[12] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 20,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x52b67b4b3d1553c7f0222155bf671be6ca000c08ef162368b40f9c2509f76d0d),
            category: 12
        });
        // Rick Astley Hair — headTop
        names[13] = "Rick Astley Hair";
        svgHashes[13] = bytes32(0x175979053cb15a342061b66c72a192bd89d9671db2f2832d79ef0864e84609ec);
        products[13] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 1))),
            initialSupply: 10,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x340b99eec7b723b6d13e66af7f62e15106df3b2330c805317b8e7cb0b9369822),
            category: 12
        });
        // Baguette — hand
        names[14] = "Baguette";
        svgHashes[14] = bytes32(0x8c4055d1b39c2cffa5ba90558908c4841dc96f5ed422a7e093d17724ae8ffaff);
        products[14] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 3))),
            initialSupply: 100,
            reserveFrequency: 20,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xbd05bdd17415f8d89764a89e0d3ef94f1feb2eafafb6583e18c2fed281303feb),
            category: 13
        });
        // Fishing Pole — hand
        names[15] = "Fishing Pole";
        svgHashes[15] = bytes32(0x64859db152943cc966ade9053c4a7d75767fe8a179d553e8eabd863574e5ad9c);
        products[15] = _drop1Tier({
            price: uint104(5 * (10 ** (decimals - 2))),
            initialSupply: 10,
            reserveFrequency: 10,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0x56960c3eb618f4605ba50139bfa9c44a54e8884c547a1d03bc94010a03eea914),
            category: 13
        });
        // Rhoads — hand
        names[16] = "Rhoads";
        svgHashes[16] = bytes32(0xd05fc36799ca0b7e50be8d90dd4e2e83b1ebc63876d617803beea7e7b4f8d77b);
        products[16] = _drop1Tier({
            price: uint104(1 * (10 ** (decimals - 1))),
            initialSupply: 10,
            reserveFrequency: 10,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            encodedIPFSUri: bytes32(0xf2ed45e54a2c42994dddfa5e581c898f435afb5d5b9240b84a258f0c90d43bf9),
            category: 13
        });

        // Add the tiers. Capture the new maxTierId to derive the UPC range that received our writes.
        hook.adjustTiers({tiersToAdd: products, tierIdsToRemove: new uint256[](0)});
        uint256 maxAfter = store.maxTierIdOf(address(hook));
        // Drift guard: our 17 tiers must occupy exactly (maxBefore, maxAfter].
        if (maxAfter != maxBefore + 17) revert Deploy_BannyProjectIdMismatch(maxAfter, maxBefore + 17);

        uint256[] memory productIds = new uint256[](17);
        for (uint256 i; i < 17; i++) {
            productIds[i] = maxAfter - 16 + i;
        }
        resolver.setSvgHashesOf({upcs: productIds, svgHashes: svgHashes});
        resolver.setProductNames({upcs: productIds, names: names});
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 09d: Finalize Banny Ownership
    // ════════════════════════════════════════════════════════════════════

    /// @notice Hands the Banny URI resolver and the BAN split-operator role from the Sphinx Safe to
    /// `_BAN_OPS_OPERATOR`. Must run after every drop registration that needs owner-only writes.
    /// @dev Idempotent: skipped when the resolver is already owned by `_BAN_OPS_OPERATOR`. Because both
    /// transfers happen atomically in a single Sphinx proposal, the resolver owner serves as a witness
    /// for the split-operator state too — if the resolver is no longer the safe's, both transfers
    /// have already landed.
    function _finalizeBannyOwnership() internal {
        IJB721TiersHook hook = _revOwner.tiered721HookOf(_BAN_PROJECT_ID);
        IJB721TiersHookStore store = hook.STORE();
        Banny721TokenUriResolver resolver = Banny721TokenUriResolver(address(store.tokenUriResolverOf(address(hook))));

        // Idempotency witness: if the safe no longer owns the resolver, both transfers have run.
        if (resolver.owner() != safeAddress()) return;

        // Hand the resolver off to the canonical Banny ops EOA. This deliberately happens AFTER all
        // drop registrations, which call owner-gated `setSvgHashesOf` + `setProductNames`. After this
        // point, future drops + metadata edits must be authorized by `_BAN_OPS_OPERATOR`.
        resolver.transferOwnership(_BAN_OPS_OPERATOR);

        // Transfer the BAN split operator role from the Sphinx Safe to the canonical Banny ops EOA.
        // After this, the safe no longer has ADJUST_721_TIERS / MINT_721 etc. on project 4; the Banny
        // ops account does.
        _revDeployer.setSplitOperatorOf({revnetId: _BAN_PROJECT_ID, newSplitOperator: _BAN_OPS_OPERATOR});
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 10: Defifa
    // ════════════════════════════════════════════════════════════════════

    /// @notice Deploys the Defifa game infrastructure: hook code origin, token URI resolver, governor, and deployer.
    /// @dev Uses the REV project (ID 3) as the Defifa fee project and the NANA fee project (ID 1) as the base
    /// protocol project. These will be updated when a dedicated Defifa revnet is created.
    function _deployDefifa() internal {
        // Skip deployment on chains without a typeface (e.g. Tempo) — DefifaTokenUriResolver
        // requires a valid ITypeface and would cause tokenURI() to revert if deployed with address(0).
        if (_typeface == address(0)) return;

        // Resolve the ERC-20 token for the Defifa fee project (REV, project 3).
        IERC20 defifaToken = IERC20(address(_tokens.tokenOf(_REV_PROJECT_ID)));

        // Resolve the ERC-20 token for the base protocol fee project (NANA, project 1).
        IERC20 baseProtocolToken = IERC20(address(_tokens.tokenOf(_FEE_PROJECT_ID)));

        // Skip deployment if either project token is not yet deployed on this chain.
        if (address(defifaToken) == address(0) || address(baseProtocolToken) == address(0)) return;

        // ── DefifaHook (code origin for clone-based game deployment) ──
        _defifaHook = DefifaHook(
            _deployPrecompiledIfNeeded({
                artifactName: "DefifaHook",
                salt: DEFIFA_SALT,
                ctorArgs: abi.encode(_directory, defifaToken, baseProtocolToken)
            })
        );

        // ── DefifaTokenUriResolver (on-chain SVG renderer for game NFTs) ──
        _defifaTokenUriResolver = DefifaTokenUriResolver(
            _deployPrecompiledIfNeeded({
                artifactName: "DefifaTokenUriResolver", salt: DEFIFA_SALT, ctorArgs: abi.encode(_typeface)
            })
        );

        // ── DefifaGovernor (scorecard attestation and ratification) ──
        _defifaGovernor = DefifaGovernor(
            _deployPrecompiledIfNeeded({
                artifactName: "DefifaGovernor", salt: DEFIFA_SALT, ctorArgs: abi.encode(_controller, safeAddress())
            })
        );

        // ── DefifaHookStore (dedicated store for Defifa game NFT tiers — same artifact as the
        // protocol-level hook store but a different salt produces a separate instance) ──
        _defifaHookStore = JB721TiersHookStore(
            _deployPrecompiledIfNeeded({artifactName: "JB721TiersHookStore", salt: DEFIFA_SALT, ctorArgs: ""})
        );

        // ── DefifaDeployer (factory that creates new Defifa games) ──
        // We need to detect first-time deploy so we know whether to transfer governor ownership.
        bytes memory deployerArgs = abi.encode(
            address(_defifaHook),
            _defifaTokenUriResolver,
            _defifaGovernor,
            _controller,
            _addressRegistry,
            _REV_PROJECT_ID,
            _FEE_PROJECT_ID,
            _defifaHookStore
        );
        (, bool deployerExisted) =
            _isDeployed({salt: DEFIFA_SALT, creationCode: _loadArtifact("DefifaDeployer"), arguments: deployerArgs});
        _defifaDeployer = DefifaDeployer(
            _deployPrecompiledIfNeeded({artifactName: "DefifaDeployer", salt: DEFIFA_SALT, ctorArgs: deployerArgs})
        );
        if (!deployerExisted) {
            // First-time deploy: transfer governor ownership to the new deployer so it can initialize games.
            _defifaGovernor.transferOwnership(address(_defifaDeployer));
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  Phase 11: Periphery Extensions
    // ════════════════════════════════════════════════════════════════════

    function _deployProjectHandles() internal {
        _projectHandles = JBProjectHandles(
            _deployPrecompiledIfNeeded({
                artifactName: "JBProjectHandles", salt: PROJECT_HANDLES_SALT, ctorArgs: abi.encode(_trustedForwarder)
            })
        );
    }

    function _deployDistributors() internal {
        _721Distributor = JB721Distributor(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JB721Distributor",
                    salt: DISTRIBUTOR_721_SALT,
                    ctorArgs: abi.encode(_directory, _roundDuration, VESTING_ROUNDS)
                }))
        );

        _tokenDistributor = JBTokenDistributor(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBTokenDistributor",
                    salt: DISTRIBUTOR_TOKEN_SALT,
                    ctorArgs: abi.encode(_directory, _roundDuration, VESTING_ROUNDS)
                }))
        );
    }

    function _deployProjectPayerDeployer() internal {
        _projectPayerDeployer = JBProjectPayerDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "JBProjectPayerDeployer",
                salt: PROJECT_PAYER_DEPLOYER_SALT,
                ctorArgs: abi.encode(_directory)
            })
        );
    }

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
            // L1: initial canonical project pairs use standard native OP, Base, and Arb suckers.
            // Tempo remains inactive until that chain is ready.
            suckerDeployerConfigs = new JBSuckerDeployerConfig[](3);
            suckerDeployerConfigs[0] =
                JBSuckerDeployerConfig({deployer: _optimismSuckerDeployer, peer: bytes32(0), mappings: tokenMappings});
            suckerDeployerConfigs[1] =
                JBSuckerDeployerConfig({deployer: _baseSuckerDeployer, peer: bytes32(0), mappings: tokenMappings});
            suckerDeployerConfigs[2] =
                JBSuckerDeployerConfig({deployer: _arbitrumSuckerDeployer, peer: bytes32(0), mappings: tokenMappings});
            // TODO: Tempo sucker config commented out until chain is ready.
        } else {
            suckerDeployerConfigs = new JBSuckerDeployerConfig[](1);
            // L2 -> L1: pick whichever deployer is non-zero for this chain.
            suckerDeployerConfigs[0] = JBSuckerDeployerConfig({
                deployer: address(_optimismSuckerDeployer) != address(0)
                    ? _optimismSuckerDeployer
                    : address(_baseSuckerDeployer) != address(0) ? _baseSuckerDeployer : _arbitrumSuckerDeployer,
                peer: bytes32(0),
                mappings: tokenMappings
            });
        }

        return REVSuckerDeploymentConfig({deployerConfigurations: suckerDeployerConfigs, salt: salt});
    }

    function _ensureDefaultPriceFeed(
        uint256 projectId,
        uint256 pricingCurrency,
        uint256 unitCurrency,
        IJBPriceFeed expectedFeed
    )
        internal
    {
        IJBPriceFeed existing =
            _prices.priceFeedFor({projectId: projectId, pricingCurrency: pricingCurrency, unitCurrency: unitCurrency});
        if (address(existing) == address(0)) {
            _prices.addPriceFeedFor({
                projectId: projectId, pricingCurrency: pricingCurrency, unitCurrency: unitCurrency, feed: expectedFeed
            });
        } else if (address(existing) != address(expectedFeed)) {
            revert Deploy_PriceFeedMismatch({
                projectId: projectId, pricingCurrency: pricingCurrency, unitCurrency: unitCurrency
            });
        }
    }

    /// @dev Canonical identity gate for the Banny project (ID 4).
    function _isCanonicalBannyProject() internal view returns (bool) {
        if (!_isCanonicalRevnetProject(_BAN_PROJECT_ID, "BAN")) return false;
        if (address(_revOwner) == address(0)) return false;

        IJB721TiersHook hook = _revOwner.tiered721HookOf(_BAN_PROJECT_ID);
        if (address(hook) == address(0)) return false;
        if (hook.PROJECT_ID() != _BAN_PROJECT_ID) return false;
        if (address(hook.STORE()) != address(_hookStore)) return false;

        // Verify the BANNY symbol on the 721 hook.
        (bool success, bytes memory data) = address(hook).staticcall(abi.encodeWithSignature("symbol()"));
        if (!success || data.length < 32) return false;
        if (keccak256(bytes(abi.decode(data, (string)))) != keccak256(bytes("BANNY"))) return false;

        return true;
    }

    function _isCanonicalRevnetProject(uint256 projectId, string memory expectedSymbol) internal view returns (bool) {
        if (_projects.ownerOf(projectId) != address(_revDeployer)) return false;
        if (address(_directory.controllerOf(projectId)) != address(_controller)) return false;
        if (_revDeployer.hashedEncodedConfigurationOf(projectId) == bytes32(0)) return false;
        if (!_projectTokenSymbolIs({projectId: projectId, expectedSymbol: expectedSymbol})) return false;
        return true;
    }

    function _projectTokenSymbolIs(uint256 projectId, string memory expectedSymbol) internal view returns (bool) {
        address token = address(_tokens.tokenOf(projectId));
        if (token == address(0)) return false;

        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("symbol()"));
        if (!success || data.length < 32) return false;

        return keccak256(bytes(abi.decode(data, (string)))) == keccak256(bytes(expectedSymbol));
    }

    function _ensureProjectExists(uint256 expectedProjectId) internal returns (uint256) {
        uint256 count = _projects.count();
        if (count >= expectedProjectId) {
            if (_projects.ownerOf(expectedProjectId) != safeAddress()) {
                revert Deploy_ProjectNotOwned(expectedProjectId);
            }
            return expectedProjectId;
        }

        uint256 created = _projects.createFor(safeAddress());
        if (created != expectedProjectId) revert Deploy_ProjectIdMismatch(expectedProjectId, created);
        return created;
    }

    /// @dev Compute the CREATE2 address for a (salt, code, args) tuple deployed via the canonical
    ///      CREATE2 factory (0x4e59…). Returns the address and whether code already exists there.
    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (address deployedTo, bool isDeployed)
    {
        deployedTo = vm.computeCreate2Address({
            salt: salt, initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)), deployer: _CREATE2_FACTORY
        });
        isDeployed = deployedTo.code.length != 0;
    }

    /// @dev Overload for callers that explicitly want a non-default deployer (kept for
    ///      backwards-compatibility with code that already passes `_CREATE2_FACTORY`).
    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments,
        address deployer
    )
        internal
        view
        returns (address deployedTo, bool isDeployed)
    {
        deployedTo = vm.computeCreate2Address({
            salt: salt, initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)), deployer: deployer
        });
        isDeployed = deployedTo.code.length != 0;
    }

    /// @dev Load creation bytecode from a pre-compiled artifact JSON file
    ///      (produced by `script/build-artifacts.sh`).
    function _loadCreationCode(string memory artifactPath) internal view returns (bytes memory) {
        string memory json = vm.readFile(artifactPath);
        return vm.parseJsonBytes({json: json, key: ".bytecode.object"});
    }

    /// @dev Convenience accessor: load artifact creation bytecode by short name (no path or extension).
    ///      `artifactName = "JBController"` → reads `artifacts/JBController.json`.
    function _loadArtifact(string memory artifactName) internal view returns (bytes memory) {
        return _loadCreationCode(string.concat("artifacts/", artifactName, ".json"));
    }

    /// @dev Deploy via an external CREATE2 factory (e.g. the canonical 0x4e59… factory).
    ///      Used for the uniform precompile path AND for Uniswap V4 hooks whose addresses
    ///      must satisfy bit-flag constraints.
    function _deployViaFactory(
        address factory,
        bytes32 salt,
        bytes memory creationCode,
        bytes memory constructorArgs
    )
        internal
        returns (address addr)
    {
        bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);
        (bool success,) = factory.call(abi.encodePacked(salt, initCode));
        require(success, "Factory CREATE2 failed");
        addr = vm.computeCreate2Address({salt: salt, initCodeHash: keccak256(initCode), deployer: factory});
        require(addr.code.length != 0, "Factory CREATE2 produced no code");
    }

    /// @dev Deploy a standard L1 Chainlink price feed (pre-compiled in nana-core-v6).
    function _deployChainlinkFeed(
        bytes32 salt,
        AggregatorV3Interface chainlinkFeed,
        uint256 threshold
    )
        internal
        returns (IJBPriceFeed)
    {
        return IJBPriceFeed(
            _deployPrecompiledIfNeeded({
                artifactName: "JBChainlinkV3PriceFeed", salt: salt, ctorArgs: abi.encode(chainlinkFeed, threshold)
            })
        );
    }

    /// @dev Deploy an L2 sequencer-aware Chainlink price feed (pre-compiled in nana-core-v6).
    function _deployChainlinkSequencerFeed(
        bytes32 salt,
        AggregatorV3Interface chainlinkFeed,
        uint256 threshold,
        AggregatorV2V3Interface sequencerFeed,
        uint256 gracePeriod
    )
        internal
        returns (IJBPriceFeed)
    {
        return IJBPriceFeed(
            _deployPrecompiledIfNeeded({
                artifactName: "JBChainlinkV3SequencerPriceFeed",
                salt: salt,
                ctorArgs: abi.encode(chainlinkFeed, threshold, sequencerFeed, gracePeriod)
            })
        );
    }

    /// @dev Idempotent precompile deploy via the canonical CREATE2 factory.
    ///      If a contract already exists at the deterministic address, returns it; otherwise
    ///      reads bytecode from `artifacts/<artifactName>.json`, deploys via the factory,
    ///      and returns the new address. This is the uniform happy-path helper used by every
    ///      deployment site in the all-precompile design.
    function _deployPrecompiledIfNeeded(
        string memory artifactName,
        bytes32 salt,
        bytes memory ctorArgs
    )
        internal
        returns (address addr)
    {
        bytes memory code = _loadArtifact(artifactName);
        bool already;
        (addr, already) = _isDeployed({salt: salt, creationCode: code, arguments: ctorArgs});
        if (!already) {
            addr = _deployViaFactory({
                factory: _CREATE2_FACTORY, salt: salt, creationCode: code, constructorArgs: ctorArgs
            });
        }
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
        flags = flags & HookMiner.FLAG_MASK;
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);

        for (uint256 i; i < HookMiner.MAX_LOOP; i++) {
            address hookAddress = HookMiner.computeAddress(deployer, i, creationCodeWithArgs);
            if (uint160(hookAddress) & HookMiner.FLAG_MASK == flags) {
                return bytes32(i);
            }
        }

        revert("HookMiner: could not find salt");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Address Dump — for post-deploy verify + artifact pipeline
    // ════════════════════════════════════════════════════════════════════

    /// @notice Emit `script/post-deploy/.cache/addresses-<chainId>.json` mapping every
    /// deployed contract to its on-chain address. Read by post-deploy.sh to
    /// drive Etherscan verification + sphinx-format artifact emission.
    /// @dev Only emits non-zero addresses, so chains that skip phases (e.g.
    /// non-Uniswap chains) produce a partial map naturally.
    function _dumpAddresses() internal {
        string memory j = "_jbV6Addresses";
        bytes32 coreSalt = keccak256(abi.encode(CORE_DEPLOYMENT_NONCE));

        // ── State-var-tracked contracts ──
        _serializeIfSet({key: j, name: "ERC2771Forwarder", addr: _trustedForwarder});
        _serializeIfSet({key: j, name: "JBPermissions", addr: address(_permissions)});
        _serializeIfSet({key: j, name: "JBProjects", addr: address(_projects)});
        _serializeIfSet({key: j, name: "JBDirectory", addr: address(_directory)});
        _serializeIfSet({key: j, name: "JBSplits", addr: address(_splits)});
        _serializeIfSet({key: j, name: "JBRulesets", addr: address(_rulesets)});
        _serializeIfSet({key: j, name: "JBPrices", addr: address(_prices)});
        _serializeIfSet({key: j, name: "JBTokens", addr: address(_tokens)});
        _serializeIfSet({key: j, name: "JBFundAccessLimits", addr: address(_fundAccess)});
        _serializeIfSet({key: j, name: "JBFeelessAddresses", addr: address(_feeless)});
        _serializeIfSet({key: j, name: "JBTerminalStore", addr: address(_terminalStore)});
        _serializeIfSet({key: j, name: "JBMultiTerminal", addr: address(_terminal)});
        _serializeIfSet({key: j, name: "JBController", addr: address(_controller)});
        _serializeIfSet({key: j, name: "JBAddressRegistry", addr: address(_addressRegistry)});
        _serializeIfSet({key: j, name: "JB721TiersHookStore", addr: address(_hookStore)});
        _serializeIfSet({key: j, name: "JB721CheckpointsDeployer", addr: address(_checkpointsDeployer)});
        _serializeIfSet({key: j, name: "JB721TiersHook", addr: address(_hook721)});
        _serializeIfSet({key: j, name: "JB721TiersHookDeployer", addr: address(_hookDeployer)});
        _serializeIfSet({key: j, name: "JB721TiersHookProjectDeployer", addr: address(_hookProjectDeployer)});
        _serializeIfSet({key: j, name: "JBUniswapV4Hook", addr: address(_uniswapV4Hook)});
        _serializeIfSet({key: j, name: "JBBuybackHookRegistry", addr: address(_buybackRegistry)});
        _serializeIfSet({key: j, name: "JBBuybackHook", addr: address(_buybackHook)});
        _serializeIfSet({key: j, name: "JBUniswapV4LPSplitHook", addr: address(_lpSplitHook)});
        _serializeIfSet({key: j, name: "JBUniswapV4LPSplitHookDeployer", addr: address(_lpSplitHookDeployer)});
        _serializeIfSet({key: j, name: "JBRouterTerminalRegistry", addr: address(_routerTerminalRegistry)});
        _serializeIfSet({key: j, name: "JBRouterTerminal", addr: address(_routerTerminal)});
        _serializeIfSet({key: j, name: "JBSuckerRegistry", addr: address(_suckerRegistry)});
        _serializeIfSet({key: j, name: "JBOptimismSuckerDeployer", addr: address(_optimismSuckerDeployer)});
        _serializeIfSet({key: j, name: "JBBaseSuckerDeployer", addr: address(_baseSuckerDeployer)});
        _serializeIfSet({key: j, name: "JBArbitrumSuckerDeployer", addr: address(_arbitrumSuckerDeployer)});
        _serializeIfSet({key: j, name: "JBOmnichainDeployer", addr: address(_omnichainDeployer)});
        _serializeIfSet({key: j, name: "CTPublisher", addr: address(_ctPublisher)});
        _serializeIfSet({key: j, name: "CTDeployer", addr: address(_ctDeployer)});
        _serializeIfSet({key: j, name: "CTProjectOwner", addr: address(_ctProjectOwner)});
        _serializeIfSet({key: j, name: "REVLoans", addr: address(_revLoans)});
        _serializeIfSet({key: j, name: "REVOwner", addr: address(_revOwner)});
        _serializeIfSet({key: j, name: "REVDeployer", addr: address(_revDeployer)});
        _serializeIfSet({key: j, name: "Banny721TokenUriResolver", addr: address(_bannyResolver)});
        _serializeIfSet({key: j, name: "DefifaHook", addr: address(_defifaHook)});
        _serializeIfSet({key: j, name: "DefifaTokenUriResolver", addr: address(_defifaTokenUriResolver)});
        _serializeIfSet({key: j, name: "DefifaGovernor", addr: address(_defifaGovernor)});
        _serializeIfSet({key: j, name: "DefifaDeployer", addr: address(_defifaDeployer)});
        _serializeIfSet({key: j, name: "JBProjectHandles", addr: address(_projectHandles)});
        _serializeIfSet({key: j, name: "JB721Distributor", addr: address(_721Distributor)});
        _serializeIfSet({key: j, name: "JBTokenDistributor", addr: address(_tokenDistributor)});
        _serializeIfSet({key: j, name: "JBProjectPayerDeployer", addr: address(_projectPayerDeployer)});

        // ── Single-instance contracts not held in state vars ──
        // Computed via _isDeployed against the canonical CREATE2 factory (since the
        // all-precompile design routes every deploy through `_deployPrecompiledIfNeeded`).

        // External libraries — no constructor args, fixed salts.
        _serializeLibrary({key: j, name: "JBPayoutSplitGroupLib", salt: PAYOUT_SPLIT_GROUP_LIB_SALT});
        _serializeLibrary({key: j, name: "JB721TiersHookLib", salt: TIERS_HOOK_LIB_SALT});
        _serializeLibrary({key: j, name: "JBSuckerLib", salt: SUCKER_LIB_SALT});
        _serializeLibrary({key: j, name: "JBCCIPLib", salt: CCIP_LIB_SALT});
        _serializeLibrary({key: j, name: "CCIPHelper", salt: CCIP_HELPER_SALT});
        _serializeLibrary({key: j, name: "JBSwapPoolLib", salt: SWAP_POOL_LIB_SALT});
        _serializeLibrary({key: j, name: "DefifaHookLib", salt: DEFIFA_HOOK_LIB_SALT});

        // JBERC20 — constructor (permissions, projects), shared with tokens.
        if (address(_permissions) != address(0) && address(_projects) != address(0)) {
            (address erc20Addr, bool erc20Deployed) = _isDeployed({
                salt: coreSalt, creationCode: type(JBERC20).creationCode, arguments: abi.encode(_permissions, _projects)
            });
            if (erc20Deployed) _serializeIfSet({key: j, name: "JBERC20", addr: erc20Addr});
        }

        // Deadlines — no constructor args, salt = DEADLINES_SALT.
        _serializeDeadline({key: j, name: "JBDeadline3Hours", creationCode: type(JBDeadline3Hours).creationCode});
        _serializeDeadline({key: j, name: "JBDeadline1Day", creationCode: type(JBDeadline1Day).creationCode});
        _serializeDeadline({key: j, name: "JBDeadline3Days", creationCode: type(JBDeadline3Days).creationCode});
        _serializeDeadline({key: j, name: "JBDeadline7Days", creationCode: type(JBDeadline7Days).creationCode});

        // Price feeds — query the prices registry directly.
        if (address(_prices) != address(0)) {
            address ethUsd = address(
                _prices.priceFeedFor({
                    projectId: 0,
                    pricingCurrency: JBCurrencyIds.USD,
                    unitCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                })
            );
            _serializeIfSet({key: j, name: "JBChainlinkV3PriceFeed__ETH_USD", addr: ethUsd});

            if (_usdcToken != address(0)) {
                // forge-lint: disable-next-line(unsafe-typecast)
                address usdcUsd = address(
                    _prices.priceFeedFor({
                        projectId: 0, pricingCurrency: JBCurrencyIds.USD, unitCurrency: uint32(uint160(_usdcToken))
                    })
                );
                _serializeIfSet({key: j, name: "JBChainlinkV3PriceFeed__USDC_USD", addr: usdcUsd});
            }

            address ethMatching = address(
                _prices.priceFeedFor({
                    projectId: 0,
                    pricingCurrency: JBCurrencyIds.ETH,
                    unitCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                })
            );
            _serializeIfSet({key: j, name: "JBMatchingPriceFeed", addr: ethMatching});
        }

        // ── Metadata ──
        vm.serializeString({objectKey: j, valueKey: "format", value: "jb-v6-addresses-1"});
        string memory out = vm.serializeUint({objectKey: j, valueKey: "chainId", value: block.chainid});

        string memory outPath =
            string.concat("script/post-deploy/.cache/addresses-", vm.toString(block.chainid), ".json");
        // Ensure the .cache directory exists. vm.writeJson does not auto-create.
        vm.createDir({path: "script/post-deploy/.cache", recursive: true});
        vm.writeJson({json: out, path: outPath});
    }

    function _serializeIfSet(string memory key, string memory name, address addr) internal {
        if (addr != address(0)) {
            vm.serializeAddress({objectKey: key, valueKey: name, value: addr});
        }
    }

    function _serializeDeadline(string memory key, string memory name, bytes memory creationCode) internal {
        (address deadlineAddr, bool isDeployed) =
            _isDeployed({salt: DEADLINES_SALT, creationCode: creationCode, arguments: ""});
        if (isDeployed) _serializeIfSet({key: key, name: name, addr: deadlineAddr});
    }

    function _serializeLibrary(string memory key, string memory name, bytes32 salt) internal {
        (address libAddr, bool isDeployed) = _isDeployed({salt: salt, creationCode: _loadArtifact(name), arguments: ""});
        if (isDeployed) _serializeIfSet({key: key, name: name, addr: libAddr});
    }
}
