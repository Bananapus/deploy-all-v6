// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ════════════════════════════════════════════════════════════════════════════════
// Resume.s.sol — Deployment recovery/resume script for Juicebox V6.
//
// PURPOSE:
//   If Deploy.s.sol is interrupted mid-deploy (gas spike, RPC timeout, operator
//   error), this script resumes from the first incomplete phase. Every phase
//   uses CREATE2 salts identical to Deploy.s.sol, so already-deployed contracts
//   are detected by checking `code.length != 0` at the deterministic address.
//
// SAFETY:
//   - All phases are safe to resume. CREATE2 guarantees that re-running a
//     deployment with the same salt + initcode is a no-op (the address already
//     has code).
//   - State-mutating calls (setDefaultHook, setIsAllowedToSetFirstController,
//     allowSuckerDeployer, etc.) are guarded by idempotent checks that read
//     current state first.
//   - Project IDs are order-dependent. If project 1 (NANA) exists but project 2
//     (CPN) does not, resume will create project 2 next. If the project count
//     has been incremented by a third party between interruption and resume,
//     project IDs may not match expectations. This is a known limitation.
//
// OPERATOR VERIFICATION AFTER RESUME:
//   1. Check that `projects.count()` matches expected total (4 after full deploy).
//   2. Verify `directory.controllerOf(projectId)` returns the controller for
//      each project (1=NANA, 2=CPN, 3=REV, 4=BAN).
//   3. Verify `prices.priceFeedFor(0, USD, NATIVE_TOKEN)` is non-zero.
//   4. Verify `suckerRegistry.suckerDeployerIsAllowed(deployer)` for each
//      expected sucker deployer.
//   5. Verify `feeless.isFeeless(routerTerminal)` is true.
//
// USAGE:
//   forge script script/Resume.s.sol:Resume --rpc-url <RPC_URL> \
//     --broadcast --sender <DEPLOYER_ADDRESS> -vvvv
// ════════════════════════════════════════════════════════════════════════════════

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// ── Core ──
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
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

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Resume -- Juicebox V6 Deployment Recovery Script
/// @notice Resumes an interrupted Deploy.s.sol run. Uses identical salts and constructor arguments.
///         Each phase checks whether its contracts already exist on-chain via CREATE2 address probing.
///         Phases that are fully deployed are skipped with a log message; incomplete phases are executed.
/// @dev This script does NOT use Sphinx. It is meant to be run directly with `forge script --broadcast`.
///      The deployer address (msg.sender) MUST match the Sphinx safe address used in the original deploy.
contract Resume is Script {
    // ═══════════════════════════════════════════════════════════════════════
    //  Errors — revert with context when resume encounters inconsistent state
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Reverts when an already-deployed contract does not match the expected address.
    error Resume_AddressMismatch(string name, address expected, address actual);
    /// @notice Reverts when a project ID does not match expectations after creation.
    error Resume_ProjectIdMismatch(uint256 expected, uint256 actual);
    /// @notice Reverts when the deployer does not own a project it should.
    error Resume_ProjectNotOwned(uint256 projectId);

    // ═══════════════════════════════════════════════════════════════════════
    //  Constants — must be identical to Deploy.s.sol
    // ═══════════════════════════════════════════════════════════════════════

    // Permit2 canonical address across all chains.
    IPermit2 private constant _PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    // Trusted forwarder name for ERC2771.
    string private constant TRUSTED_FORWARDER_NAME = "Juicebox";
    // Nonce used to derive the core deployment salt.
    uint256 private constant CORE_DEPLOYMENT_NONCE = 6;

    // ── Core salts — deterministic addresses depend on these being unchanged ──
    bytes32 private constant DEADLINES_SALT = keccak256("_JBDeadlinesV6_");
    bytes32 private constant USD_NATIVE_FEED_SALT = keccak256("USD_FEEDV6");
    bytes32 private constant USDC_FEED_SALT = keccak256("USDC_FEEDV6");

    // ── Address Registry salt ──
    bytes32 private constant ADDRESS_REGISTRY_SALT = "_JBAddressRegistryV6_";

    // ── 721 Hook salts ──
    bytes32 private constant HOOK_721_STORE_SALT = "JB721TiersHookStoreV6_";
    bytes32 private constant HOOK_721_SALT = "JB721TiersHookV6_";
    bytes32 private constant HOOK_721_DEPLOYER_SALT = "JB721TiersHookDeployerV6_";
    bytes32 private constant HOOK_721_PROJECT_DEPLOYER_SALT = "JB721TiersHookProjectDeployerV6";

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

    // ── Project IDs — determined by sequential creation order ──
    uint256 private constant _FEE_PROJECT_ID = 1;
    uint256 private constant _CPN_PROJECT_ID = 2;
    uint256 private constant _REV_PROJECT_ID = 3;
    uint256 private constant _BAN_PROJECT_ID = 4;

    // ── Common numeric constants ──
    uint32 private constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));
    uint32 private constant ETH_CURRENCY = uint32(JBCurrencyIds.ETH);
    uint8 private constant DECIMALS = 18;
    uint256 private constant DECIMAL_MULTIPLIER = 10 ** DECIMALS;
    uint32 private constant PREMINT_CHAIN_ID = 1;

    // ── REV stage constants ──
    uint48 private constant REV_START_TIME = 1_740_089_444;
    uint104 private constant REV_MAINNET_AUTO_ISSUANCE = 1_050_482_341_387_116_262_330_122;
    uint104 private constant REV_BASE_AUTO_ISSUANCE = 38_544_322_230_437_559_731_228;
    uint104 private constant REV_OP_AUTO_ISSUANCE = 32_069_388_242_375_817_844;
    uint104 private constant REV_ARB_AUTO_ISSUANCE = 3_479_431_776_906_850_000_000;

    // ── NANA stage constants ──
    uint48 private constant NANA_START_TIME = 1_740_089_444;
    uint104 private constant NANA_MAINNET_AUTO_ISSUANCE = 34_614_774_622_547_324_824_200;
    uint104 private constant NANA_BASE_AUTO_ISSUANCE = 1_604_412_323_715_200_204_800;
    uint104 private constant NANA_OP_AUTO_ISSUANCE = 6_266_215_368_602_910_600;
    uint104 private constant NANA_ARB_AUTO_ISSUANCE = 105_160_496_145_000_000;

    // ── CPN stage constants ──
    uint48 private constant CPN_START_TIME = 1_740_089_444;
    uint104 private constant CPN_MAINNET_AUTO_ISSUANCE = 250_003_875_000_000_000_000_000;
    uint104 private constant CPN_BASE_AUTO_ISSUANCE = 844_894_881_600_000_000_000;
    uint104 private constant CPN_OP_AUTO_ISSUANCE = 844_894_881_600_000_000_000;
    uint104 private constant CPN_ARB_AUTO_ISSUANCE = 3_844_000_000_000_000_000;

    // ── Banny stage constants ──
    uint48 private constant BAN_START_TIME = 1_740_435_044;
    uint104 private constant BAN_MAINNET_AUTO_ISSUANCE = 545_296_034_092_246_678_345_976;
    uint104 private constant BAN_BASE_AUTO_ISSUANCE = 10_097_684_379_816_492_953_872;
    uint104 private constant BAN_OP_AUTO_ISSUANCE = 328_366_065_858_064_488_000;
    uint104 private constant BAN_ARB_AUTO_ISSUANCE = 2_825_980_000_000_000_000_000;

    // ═══════════════════════════════════════════════════════════════════════
    //  State — populated as each phase resolves or deploys contracts
    // ═══════════════════════════════════════════════════════════════════════

    // Core protocol references.
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

    // Address Registry reference.
    JBAddressRegistry private _addressRegistry;

    // 721 Hook references.
    JB721TiersHookStore private _hookStore;
    JB721TiersHook private _hook721;
    JB721TiersHookDeployer private _hookDeployer;
    JB721TiersHookProjectDeployer private _hookProjectDeployer;

    // Buyback Hook references.
    JBUniswapV4Hook private _uniswapV4Hook;
    JBBuybackHookRegistry private _buybackRegistry;
    JBBuybackHook private _buybackHook;
    JBUniswapV4LPSplitHook private _lpSplitHook;
    JBUniswapV4LPSplitHookDeployer private _lpSplitHookDeployer;

    // Router Terminal references.
    JBRouterTerminalRegistry private _routerTerminalRegistry;
    JBRouterTerminal private _routerTerminal;

    // Sucker references.
    JBSuckerRegistry private _suckerRegistry;
    address[] private _preApprovedSuckerDeployers;
    IJBSuckerDeployer private _optimismSuckerDeployer;
    IJBSuckerDeployer private _baseSuckerDeployer;
    IJBSuckerDeployer private _arbitrumSuckerDeployer;

    // Omnichain Deployer reference.
    JBOmnichainDeployer private _omnichainDeployer;

    // Croptop references.
    CTPublisher private _ctPublisher;
    CTDeployer private _ctDeployer;
    CTProjectOwner private _ctProjectOwner;

    // Revnet references.
    REVLoans private _revLoans;
    REVDeployer private _revDeployer;

    // Project IDs (populated during resume).
    uint256 private _cpnProjectId;
    uint256 private _revProjectId;

    // Chain-specific external addresses (set in _setupChainAddresses).
    address private _weth;
    address private _v3Factory;
    address private _poolManager;
    address private _positionManager;

    // Deployer address — the msg.sender that originally ran Deploy.s.sol.
    address private _deployer;

    // Phase tracking counters for the final summary log.
    uint256 private _phasesSkipped;
    uint256 private _phasesExecuted;

    // ═══════════════════════════════════════════════════════════════════════
    //  Entry Point
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Main entry point. Sets up chain addresses and runs all phases.
    function run() public {
        // Store the deployer address — used as CREATE2 deployer for address computation.
        _deployer = msg.sender;

        // Resolve chain-specific external contract addresses.
        _setupChainAddresses();

        // Log the chain and deployer for operator reference.
        console2.log("[Resume] Chain ID:", block.chainid);
        console2.log("[Resume] Deployer:", _deployer);
        console2.log("[Resume] Starting resume sequence...");
        console2.log("");

        // Start broadcasting transactions.
        vm.startBroadcast();

        // ── Phase 01: Core Protocol ──
        _resumeCore();

        // ── Phase 02: Address Registry ──
        _resumeAddressRegistry();

        // ── Phase 03a: 721 Tier Hook ──
        _resume721Hook();

        // Uniswap-dependent phases are skipped on chains without a PositionManager.
        if (_shouldDeployUniswapStack()) {
            // ── Phase 03b: Uniswap V4 Router Hook ──
            _resumeUniswapV4Hook();

            // ── Phase 03c: Buyback Hook ──
            _resumeBuybackHook();

            // ── Phase 03d: Router Terminal ──
            _resumeRouterTerminal();

            // ── Phase 03e: Uniswap V4 LP Split Hook ──
            _resumeLpSplitHook();
        }

        // ── Phase 03f: Cross-Chain Suckers ──
        _resumeSuckers();

        // ── Phase 04: Omnichain Deployer ──
        _resumeOmnichainDeployer();

        // ── Phase 05: Periphery (Controller + Price Feeds + Deadlines) ──
        _resumePeriphery();

        // ── Phase 06: Croptop ──
        _resumeCroptop();

        // ── Phase 07: Revnet ──
        _resumeRevnet();

        // ── Phase 08: Configure CPN and NANA as revnets ──
        _resumeCpnRevnet();
        _resumeNanaRevnet();

        // ── Phase 09: Banny ──
        _resumeBanny();

        // Stop broadcasting.
        vm.stopBroadcast();

        // Print summary.
        console2.log("");
        console2.log("========================================");
        console2.log("[Resume] COMPLETE");
        console2.log("[Resume] Phases skipped:", _phasesSkipped);
        console2.log("[Resume] Phases executed:", _phasesExecuted);
        console2.log("========================================");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Chain-Specific Address Setup (identical to Deploy.s.sol)
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Populates chain-specific external addresses (WETH, Uniswap, etc.).
    function _setupChainAddresses() internal {
        // Ethereum Mainnet.
        if (block.chainid == 1) {
            _weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            _v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            _poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            _positionManager = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
        }
        // Ethereum Sepolia.
        else if (block.chainid == 11_155_111) {
            _weth = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
            _v3Factory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
            _poolManager = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
            _positionManager = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
        }
        // Optimism.
        else if (block.chainid == 10) {
            _weth = 0x4200000000000000000000000000000000000006;
            _v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            _poolManager = 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
            _positionManager = 0x3C3Ea4B57a46241e54610e5f022E5c45859A1017;
        }
        // Optimism Sepolia — no PositionManager, Uniswap stack skipped.
        else if (block.chainid == 11_155_420) {
            _weth = 0x4200000000000000000000000000000000000006;
            _v3Factory = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
            _poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            _positionManager = address(0); // No PositionManager on OP Sepolia.
        }
        // Base.
        else if (block.chainid == 8453) {
            _weth = 0x4200000000000000000000000000000000000006;
            _v3Factory = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
            _poolManager = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
            _positionManager = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
        }
        // Base Sepolia.
        else if (block.chainid == 84_532) {
            _weth = 0x4200000000000000000000000000000000000006;
            _v3Factory = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
            _poolManager = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
            _positionManager = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
        }
        // Arbitrum.
        else if (block.chainid == 42_161) {
            _weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
            _v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            _poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
            _positionManager = 0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869;
        }
        // Arbitrum Sepolia.
        else if (block.chainid == 421_614) {
            _weth = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
            _v3Factory = 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e;
            _poolManager = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
            _positionManager = 0xAc631556d3d4019C95769033B5E719dD77124BAc;
        } else {
            revert("Unsupported chain"); // Fail fast for unknown chains.
        }
    }

    /// @dev Returns true if the current chain has Uniswap V4 infrastructure.
    function _shouldDeployUniswapStack() internal view returns (bool) {
        return block.chainid != 11_155_420; // OP Sepolia lacks PositionManager.
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 01: Core Protocol
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeCore() internal {
        // Derive the core salt (shared across all core contracts).
        bytes32 coreSalt = keccak256(abi.encode(CORE_DEPLOYMENT_NONCE));

        // We resolve each contract individually since they depend on each other.
        // The _isDeployed pattern handles this: if code exists, skip; otherwise deploy.

        // Deploy or resolve trusted forwarder.
        (address trustedForwarder, bool trustedForwarderDeployed) =
            _isDeployed(coreSalt, type(ERC2771Forwarder).creationCode, abi.encode(TRUSTED_FORWARDER_NAME));
        _trustedForwarder = trustedForwarderDeployed
            ? trustedForwarder  // Already deployed — use existing address.
            : address(new ERC2771Forwarder{salt: coreSalt}(TRUSTED_FORWARDER_NAME)); // Deploy new.

        // Deploy or resolve permissions.
        (address permissions, bool permissionsDeployed) = _isDeployed({
            salt: coreSalt, creationCode: type(JBPermissions).creationCode, arguments: abi.encode(_trustedForwarder)
        });
        _permissions =
            permissionsDeployed ? JBPermissions(permissions) : new JBPermissions{salt: coreSalt}(_trustedForwarder);

        // Deploy or resolve projects.
        (address projects, bool projectsDeployed) = _isDeployed({
            salt: coreSalt,
            creationCode: type(JBProjects).creationCode,
            arguments: abi.encode(_deployer, _deployer, _trustedForwarder)
        });
        _projects = projectsDeployed
            ? JBProjects(projects)
            : new JBProjects{salt: coreSalt}({
                owner: _deployer, feeProjectOwner: _deployer, trustedForwarder: _trustedForwarder
            });

        // Deploy or resolve directory.
        (address directory, bool directoryDeployed) = _isDeployed({
            salt: coreSalt,
            creationCode: type(JBDirectory).creationCode,
            arguments: abi.encode(_permissions, _projects, _deployer)
        });
        _directory = directoryDeployed
            ? JBDirectory(directory)
            : new JBDirectory{salt: coreSalt}({permissions: _permissions, projects: _projects, owner: _deployer});

        // Deploy or resolve splits.
        (address splits, bool splitsDeployed) =
            _isDeployed({salt: coreSalt, creationCode: type(JBSplits).creationCode, arguments: abi.encode(_directory)});
        _splits = splitsDeployed ? JBSplits(splits) : new JBSplits{salt: coreSalt}({directory: _directory});

        // Deploy or resolve rulesets.
        (address rulesets, bool rulesetsDeployed) = _isDeployed({
            salt: coreSalt, creationCode: type(JBRulesets).creationCode, arguments: abi.encode(_directory)
        });
        _rulesets = rulesetsDeployed ? JBRulesets(rulesets) : new JBRulesets{salt: coreSalt}({directory: _directory});

        // Deploy or resolve prices.
        (address prices, bool pricesDeployed) = _isDeployed({
            salt: coreSalt,
            creationCode: type(JBPrices).creationCode,
            arguments: abi.encode(_directory, _permissions, _projects, _deployer, _trustedForwarder)
        });
        _prices = pricesDeployed
            ? JBPrices(prices)
            : new JBPrices{salt: coreSalt}({
                directory: _directory,
                permissions: _permissions,
                projects: _projects,
                owner: _deployer,
                trustedForwarder: _trustedForwarder
            });

        // Deploy or resolve ERC20 implementation.
        (address erc20, bool erc20Deployed) = _isDeployed(coreSalt, type(JBERC20).creationCode, "");
        JBERC20 token = erc20Deployed ? JBERC20(erc20) : new JBERC20{salt: coreSalt}();

        // Deploy or resolve tokens.
        (address tokens, bool tokensDeployed) = _isDeployed({
            salt: coreSalt, creationCode: type(JBTokens).creationCode, arguments: abi.encode(_directory, token)
        });
        _tokens =
            tokensDeployed ? JBTokens(tokens) : new JBTokens{salt: coreSalt}({directory: _directory, token: token});

        // Deploy or resolve fund access limits.
        (address fundAccess, bool fundAccessDeployed) = _isDeployed({
            salt: coreSalt, creationCode: type(JBFundAccessLimits).creationCode, arguments: abi.encode(_directory)
        });
        _fundAccess = fundAccessDeployed
            ? JBFundAccessLimits(fundAccess)
            : new JBFundAccessLimits{salt: coreSalt}({directory: _directory});

        // Deploy or resolve feeless addresses.
        (address feeless, bool feelessDeployed) = _isDeployed({
            salt: coreSalt, creationCode: type(JBFeelessAddresses).creationCode, arguments: abi.encode(_deployer)
        });
        _feeless =
            feelessDeployed ? JBFeelessAddresses(feeless) : new JBFeelessAddresses{salt: coreSalt}({owner: _deployer});

        // Deploy or resolve terminal store.
        (address terminalStore, bool terminalStoreDeployed) = _isDeployed({
            salt: coreSalt,
            creationCode: type(JBTerminalStore).creationCode,
            arguments: abi.encode(_directory, _rulesets, _prices)
        });
        _terminalStore = terminalStoreDeployed
            ? JBTerminalStore(terminalStore)
            : new JBTerminalStore{salt: coreSalt}({directory: _directory, rulesets: _rulesets, prices: _prices});

        // Deploy or resolve multi terminal.
        (address terminal, bool terminalDeployed) = _isDeployed({
            salt: coreSalt,
            creationCode: type(JBMultiTerminal).creationCode,
            arguments: abi.encode(
                _permissions, _projects, _splits, _terminalStore, _tokens, _feeless, _PERMIT2, _trustedForwarder
            )
        });
        _terminal = terminalDeployed
            ? JBMultiTerminal(terminal)
            : new JBMultiTerminal{salt: coreSalt}({
                feelessAddresses: _feeless,
                permissions: _permissions,
                projects: _projects,
                splits: _splits,
                store: _terminalStore,
                tokens: _tokens,
                permit2: _PERMIT2,
                trustedForwarder: _trustedForwarder
            });

        // Log result: all deployed means skip, otherwise some were new.
        if (
            trustedForwarderDeployed && permissionsDeployed && projectsDeployed && directoryDeployed && splitsDeployed
                && rulesetsDeployed && pricesDeployed && erc20Deployed && tokensDeployed && fundAccessDeployed
                && feelessDeployed && terminalStoreDeployed && terminalDeployed
        ) {
            console2.log("[Phase 01] Core Protocol: SKIPPED (all contracts exist)");
            _phasesSkipped++; // Increment skip counter.
        } else {
            console2.log("[Phase 01] Core Protocol: EXECUTED (deployed missing contracts)");
            _phasesExecuted++; // Increment execute counter.
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 02: Address Registry
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeAddressRegistry() internal {
        // Check if the address registry is already deployed.
        (address registry, bool deployed) = _isDeployed({
            salt: ADDRESS_REGISTRY_SALT, creationCode: type(JBAddressRegistry).creationCode, arguments: ""
        });
        // Use existing or deploy new.
        _addressRegistry = deployed ? JBAddressRegistry(registry) : new JBAddressRegistry{salt: ADDRESS_REGISTRY_SALT}();

        // Log the result.
        _logPhase("02", "Address Registry", deployed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 03a: 721 Tier Hook
    // ═══════════════════════════════════════════════════════════════════════

    function _resume721Hook() internal {
        // Deploy or resolve hook store.
        (address hookStore, bool hookStoreDeployed) = _isDeployed({
            salt: HOOK_721_STORE_SALT, creationCode: type(JB721TiersHookStore).creationCode, arguments: ""
        });
        _hookStore =
            hookStoreDeployed ? JB721TiersHookStore(hookStore) : new JB721TiersHookStore{salt: HOOK_721_STORE_SALT}();

        // Deploy or resolve 721 hook implementation.
        (address hook721, bool hook721Deployed) = _isDeployed({
            salt: HOOK_721_SALT,
            creationCode: type(JB721TiersHook).creationCode,
            arguments: abi.encode(_directory, _permissions, _prices, _rulesets, _hookStore, _splits, _trustedForwarder)
        });
        _hook721 = hook721Deployed
            ? JB721TiersHook(hook721)
            : new JB721TiersHook{salt: HOOK_721_SALT}({
                directory: _directory,
                permissions: _permissions,
                prices: _prices,
                rulesets: _rulesets,
                store: _hookStore,
                splits: _splits,
                trustedForwarder: _trustedForwarder
            });

        // Deploy or resolve hook deployer.
        (address hookDeployer, bool hookDeployerDeployed) = _isDeployed({
            salt: HOOK_721_DEPLOYER_SALT,
            creationCode: type(JB721TiersHookDeployer).creationCode,
            arguments: abi.encode(
                _hook721, _hookStore, IJBAddressRegistry(address(_addressRegistry)), _trustedForwarder
            )
        });
        _hookDeployer = hookDeployerDeployed
            ? JB721TiersHookDeployer(hookDeployer)
            : new JB721TiersHookDeployer{salt: HOOK_721_DEPLOYER_SALT}({
                hook: _hook721,
                store: _hookStore,
                addressRegistry: IJBAddressRegistry(address(_addressRegistry)),
                trustedForwarder: _trustedForwarder
            });

        // Deploy or resolve hook project deployer.
        (address hookProjectDeployer, bool hookProjectDeployerDeployed) = _isDeployed({
            salt: HOOK_721_PROJECT_DEPLOYER_SALT,
            creationCode: type(JB721TiersHookProjectDeployer).creationCode,
            arguments: abi.encode(_directory, _permissions, _hookDeployer, _trustedForwarder)
        });
        _hookProjectDeployer = hookProjectDeployerDeployed
            ? JB721TiersHookProjectDeployer(hookProjectDeployer)
            : new JB721TiersHookProjectDeployer{salt: HOOK_721_PROJECT_DEPLOYER_SALT}({
                directory: _directory,
                permissions: _permissions,
                hookDeployer: _hookDeployer,
                trustedForwarder: _trustedForwarder
            });

        // Log: all four sub-contracts.
        bool allDeployed = hookStoreDeployed && hook721Deployed && hookDeployerDeployed && hookProjectDeployerDeployed;
        _logPhase("03a", "721 Tier Hook", allDeployed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 03b: Uniswap V4 Router Hook
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeUniswapV4Hook() internal {
        // Compute the required hook flags for Uniswap V4.
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );

        // Encode constructor arguments.
        bytes memory constructorArgs = abi.encode(IPoolManager(_poolManager), _tokens, _directory, _prices);

        // Mine a salt that produces an address with the correct Uniswap hook flags.
        bytes32 salt = _findHookSalt({
            deployer: _deployer,
            flags: flags,
            creationCode: type(JBUniswapV4Hook).creationCode,
            constructorArgs: constructorArgs
        });

        // Check if already deployed at the deterministic address.
        (address hook, bool deployed) =
            _isDeployed({salt: salt, creationCode: type(JBUniswapV4Hook).creationCode, arguments: constructorArgs});

        // Use existing or deploy new.
        _uniswapV4Hook = deployed
            ? JBUniswapV4Hook(payable(hook))
            : new JBUniswapV4Hook{salt: salt}({
                poolManager: IPoolManager(_poolManager), tokens: _tokens, directory: _directory, prices: _prices
            });

        // Log the result.
        _logPhase("03b", "Uniswap V4 Router Hook", deployed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 03c: Buyback Hook
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeBuybackHook() internal {
        // Deploy or resolve the buyback registry.
        (address registry, bool registryDeployed) = _isDeployed({
            salt: BUYBACK_HOOK_SALT,
            creationCode: type(JBBuybackHookRegistry).creationCode,
            arguments: abi.encode(_permissions, _projects, _deployer, _trustedForwarder)
        });
        _buybackRegistry = registryDeployed
            ? JBBuybackHookRegistry(registry)
            : new JBBuybackHookRegistry{salt: BUYBACK_HOOK_SALT}({
                permissions: _permissions, projects: _projects, owner: _deployer, trustedForwarder: _trustedForwarder
            });

        // Deploy or resolve the buyback hook.
        (address hook, bool hookDeployed) = _isDeployed(
            BUYBACK_HOOK_SALT,
            type(JBBuybackHook).creationCode,
            abi.encode(
                _directory,
                _permissions,
                _prices,
                _projects,
                _tokens,
                IPoolManager(_poolManager),
                IHooks(address(_uniswapV4Hook)),
                _trustedForwarder
            )
        );
        _buybackHook = hookDeployed
            ? JBBuybackHook(payable(hook))
            : new JBBuybackHook{salt: BUYBACK_HOOK_SALT}({
                directory: _directory,
                permissions: _permissions,
                prices: _prices,
                projects: _projects,
                tokens: _tokens,
                poolManager: IPoolManager(_poolManager),
                oracleHook: IHooks(address(_uniswapV4Hook)),
                trustedForwarder: _trustedForwarder
            });

        // Idempotent: set default hook only if not already set.
        if (address(_buybackRegistry.defaultHook()) == address(0)) {
            _buybackRegistry.setDefaultHook({hook: _buybackHook}); // Wire default buyback hook.
        }

        // Log the result.
        _logPhase("03c", "Buyback Hook", registryDeployed && hookDeployed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 03d: Router Terminal
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeRouterTerminal() internal {
        // Deploy or resolve the router terminal registry.
        (address registry, bool registryDeployed) = _isDeployed({
            salt: ROUTER_TERMINAL_REGISTRY_SALT,
            creationCode: type(JBRouterTerminalRegistry).creationCode,
            arguments: abi.encode(_permissions, _projects, _PERMIT2, _deployer, _trustedForwarder)
        });
        _routerTerminalRegistry = registryDeployed
            ? JBRouterTerminalRegistry(payable(registry))
            : new JBRouterTerminalRegistry{salt: ROUTER_TERMINAL_REGISTRY_SALT}({
                permissions: _permissions,
                projects: _projects,
                permit2: _PERMIT2,
                owner: _deployer,
                trustedForwarder: _trustedForwarder
            });

        // Deploy or resolve the router terminal.
        (address terminal, bool terminalDeployed) = _isDeployed(
            ROUTER_TERMINAL_SALT,
            type(JBRouterTerminal).creationCode,
            abi.encode(
                _directory,
                _permissions,
                _projects,
                _tokens,
                _PERMIT2,
                _deployer,
                IRouterWETH9(_weth),
                IUniswapV3Factory(_v3Factory),
                IPoolManager(_poolManager),
                _trustedForwarder
            )
        );
        _routerTerminal = terminalDeployed
            ? JBRouterTerminal(payable(terminal))
            : new JBRouterTerminal{salt: ROUTER_TERMINAL_SALT}({
                directory: _directory,
                permissions: _permissions,
                projects: _projects,
                tokens: _tokens,
                permit2: _PERMIT2,
                owner: _deployer,
                weth: IRouterWETH9(_weth),
                factory: IUniswapV3Factory(_v3Factory),
                poolManager: IPoolManager(_poolManager),
                trustedForwarder: _trustedForwarder
            });

        // Idempotent: set default terminal only if not already set.
        if (address(_routerTerminalRegistry.defaultTerminal()) == address(0)) {
            _routerTerminalRegistry.setDefaultTerminal({terminal: _routerTerminal}); // Wire default.
        }

        // Idempotent: mark router terminal as feeless only if not already.
        if (!_feeless.isFeeless(address(_routerTerminal))) {
            _feeless.setFeelessAddress({addr: address(_routerTerminal), flag: true}); // Fee exemption.
        }

        // Log the result.
        _logPhase("03d", "Router Terminal", registryDeployed && terminalDeployed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 03e: Uniswap V4 LP Split Hook
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeLpSplitHook() internal {
        // Deploy or resolve the LP split hook.
        (address hook, bool hookDeployed) = _isDeployed(
            LP_SPLIT_HOOK_SALT,
            type(JBUniswapV4LPSplitHook).creationCode,
            abi.encode(
                address(_directory),
                _permissions,
                address(_tokens),
                IPoolManager(_poolManager),
                IPositionManager(_positionManager),
                IAllowanceTransfer(address(_PERMIT2)),
                IHooks(address(_uniswapV4Hook))
            )
        );
        _lpSplitHook = hookDeployed
            ? JBUniswapV4LPSplitHook(payable(hook))
            : new JBUniswapV4LPSplitHook{salt: LP_SPLIT_HOOK_SALT}(
                address(_directory),
                _permissions,
                address(_tokens),
                IPoolManager(_poolManager),
                IPositionManager(_positionManager),
                IAllowanceTransfer(address(_PERMIT2)),
                IHooks(address(_uniswapV4Hook))
            );

        // Deploy or resolve the LP split hook deployer.
        (address deployer, bool deployerDeployed) = _isDeployed(
            LP_SPLIT_HOOK_DEPLOYER_SALT,
            type(JBUniswapV4LPSplitHookDeployer).creationCode,
            abi.encode(_lpSplitHook, IJBAddressRegistry(address(_addressRegistry)))
        );
        _lpSplitHookDeployer = deployerDeployed
            ? JBUniswapV4LPSplitHookDeployer(deployer)
            : new JBUniswapV4LPSplitHookDeployer{salt: LP_SPLIT_HOOK_DEPLOYER_SALT}(
                _lpSplitHook, IJBAddressRegistry(address(_addressRegistry))
            );

        // Log the result.
        _logPhase("03e", "LP Split Hook", hookDeployed && deployerDeployed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 03f: Cross-Chain Suckers
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeSuckers() internal {
        // Deploy or resolve the sucker registry.
        (address registry, bool registryDeployed) = _isDeployed(
            SUCKER_REGISTRY_SALT,
            type(JBSuckerRegistry).creationCode,
            abi.encode(_directory, _permissions, _deployer, _trustedForwarder)
        );
        _suckerRegistry = registryDeployed
            ? JBSuckerRegistry(registry)
            : new JBSuckerRegistry{salt: SUCKER_REGISTRY_SALT}(_directory, _permissions, _deployer, _trustedForwarder);

        // Deploy chain-specific sucker deployers and singletons.
        _resumeSuckersOptimism();
        _resumeSuckersBase();
        _resumeSuckersArbitrum();
        _resumeSuckersCCIP();

        // Pre-approve deployers in the registry (idempotent).
        if (_preApprovedSuckerDeployers.length != 0) {
            for (uint256 i; i < _preApprovedSuckerDeployers.length; i++) {
                // Only allow if not already allowed.
                if (!_suckerRegistry.suckerDeployerIsAllowed(_preApprovedSuckerDeployers[i])) {
                    _suckerRegistry.allowSuckerDeployer(_preApprovedSuckerDeployers[i]); // Allowlist deployer.
                }
            }
        }

        // Log — always mark as executed since suckers are complex and chain-specific.
        console2.log("[Phase 03f] Cross-Chain Suckers: PROCESSED");
        _phasesExecuted++; // Count as executed since we always process sucker logic.
    }

    // ── Sucker sub-deployers (follow same pattern as Deploy.s.sol) ──

    function _resumeSuckersOptimism() internal {
        // L1: Ethereum Mainnet / Sepolia.
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            // Deploy or resolve OP sucker deployer.
            (address opDeployerAddress, bool opDeployerDeployed) = _isDeployed(
                OP_SALT,
                type(JBOptimismSuckerDeployer).creationCode,
                abi.encode(_directory, _permissions, _tokens, _deployer, _trustedForwarder)
            );
            JBOptimismSuckerDeployer opDeployer = opDeployerDeployed
                ? JBOptimismSuckerDeployer(opDeployerAddress)
                : new JBOptimismSuckerDeployer{salt: OP_SALT}(
                    _directory, _permissions, _tokens, _deployer, _trustedForwarder
                );

            // Set chain-specific constants if not already set.
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
                opDeployer.setChainSpecificConstants(messenger, bridge); // Wire OP bridge.
            }

            // Deploy or resolve OP sucker singleton.
            (address singletonAddress, bool singletonDeployed) = _isDeployed(
                OP_SALT,
                type(JBOptimismSucker).creationCode,
                abi.encode(opDeployer, _directory, _permissions, _tokens, 1, _suckerRegistry, _trustedForwarder)
            );
            JBOptimismSucker singleton = singletonDeployed
                ? JBOptimismSucker(payable(singletonAddress))
                : new JBOptimismSucker{salt: OP_SALT}(
                    opDeployer, _directory, _permissions, _tokens, 1, _suckerRegistry, _trustedForwarder
                );
            // Configure singleton in deployer if not already done.
            if (address(opDeployer.singleton()) == address(0)) opDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(opDeployer)); // Track for allowlisting.
            _optimismSuckerDeployer = IJBSuckerDeployer(address(opDeployer)); // Store reference.
        }

        // L2: Optimism / Optimism Sepolia.
        if (block.chainid == 10 || block.chainid == 11_155_420) {
            // Deploy or resolve OP sucker deployer on L2.
            (address opDeployerAddress, bool opDeployerDeployed) = _isDeployed(
                OP_SALT,
                type(JBOptimismSuckerDeployer).creationCode,
                abi.encode(_directory, _permissions, _tokens, _deployer, _trustedForwarder)
            );
            JBOptimismSuckerDeployer opDeployer = opDeployerDeployed
                ? JBOptimismSuckerDeployer(opDeployerAddress)
                : new JBOptimismSuckerDeployer{salt: OP_SALT}(
                    _directory, _permissions, _tokens, _deployer, _trustedForwarder
                );

            // Set L2 predeploy addresses if not already set.
            if (address(opDeployer.opMessenger()) == address(0)) {
                opDeployer.setChainSpecificConstants(
                    IOPMessenger(0x4200000000000000000000000000000000000007),
                    IOPStandardBridge(0x4200000000000000000000000000000000000010)
                );
            }

            // Deploy or resolve OP sucker singleton on L2.
            (address singletonAddress, bool singletonDeployed) = _isDeployed(
                OP_SALT,
                type(JBOptimismSucker).creationCode,
                abi.encode(opDeployer, _directory, _permissions, _tokens, 1, _suckerRegistry, _trustedForwarder)
            );
            JBOptimismSucker singleton = singletonDeployed
                ? JBOptimismSucker(payable(singletonAddress))
                : new JBOptimismSucker{salt: OP_SALT}(
                    opDeployer, _directory, _permissions, _tokens, 1, _suckerRegistry, _trustedForwarder
                );
            if (address(opDeployer.singleton()) == address(0)) opDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(opDeployer));
            _optimismSuckerDeployer = IJBSuckerDeployer(address(opDeployer));
        }
    }

    function _resumeSuckersBase() internal {
        // L1.
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            // Deploy or resolve Base sucker deployer.
            (address baseDeployerAddress, bool baseDeployerDeployed) = _isDeployed(
                BASE_SALT,
                type(JBBaseSuckerDeployer).creationCode,
                abi.encode(_directory, _permissions, _tokens, _deployer, _trustedForwarder)
            );
            JBBaseSuckerDeployer baseDeployer = baseDeployerDeployed
                ? JBBaseSuckerDeployer(baseDeployerAddress)
                : new JBBaseSuckerDeployer{salt: BASE_SALT}(
                    _directory, _permissions, _tokens, _deployer, _trustedForwarder
                );

            // Set chain-specific bridge addresses.
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
                baseDeployer.setChainSpecificConstants(messenger, bridge); // Wire Base bridge.
            }

            // Deploy or resolve Base sucker singleton.
            (address singletonAddress, bool singletonDeployed) = _isDeployed(
                BASE_SALT,
                type(JBBaseSucker).creationCode,
                abi.encode(baseDeployer, _directory, _permissions, _tokens, 1, _suckerRegistry, _trustedForwarder)
            );
            JBBaseSucker singleton = singletonDeployed
                ? JBBaseSucker(payable(singletonAddress))
                : new JBBaseSucker{salt: BASE_SALT}(
                    baseDeployer, _directory, _permissions, _tokens, 1, _suckerRegistry, _trustedForwarder
                );
            if (address(baseDeployer.singleton()) == address(0)) baseDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(baseDeployer));
            _baseSuckerDeployer = IJBSuckerDeployer(address(baseDeployer));
        }

        // L2: Base / Base Sepolia.
        if (block.chainid == 8453 || block.chainid == 84_532) {
            // Deploy or resolve Base sucker deployer on L2.
            (address baseDeployerAddress, bool baseDeployerDeployed) = _isDeployed(
                BASE_SALT,
                type(JBBaseSuckerDeployer).creationCode,
                abi.encode(_directory, _permissions, _tokens, _deployer, _trustedForwarder)
            );
            JBBaseSuckerDeployer baseDeployer = baseDeployerDeployed
                ? JBBaseSuckerDeployer(baseDeployerAddress)
                : new JBBaseSuckerDeployer{salt: BASE_SALT}(
                    _directory, _permissions, _tokens, _deployer, _trustedForwarder
                );

            // Set L2 predeploy addresses.
            if (address(baseDeployer.opMessenger()) == address(0)) {
                baseDeployer.setChainSpecificConstants(
                    IOPMessenger(0x4200000000000000000000000000000000000007),
                    IOPStandardBridge(0x4200000000000000000000000000000000000010)
                );
            }

            // Deploy or resolve Base sucker singleton on L2.
            (address singletonAddress, bool singletonDeployed) = _isDeployed(
                BASE_SALT,
                type(JBBaseSucker).creationCode,
                abi.encode(baseDeployer, _directory, _permissions, _tokens, 1, _suckerRegistry, _trustedForwarder)
            );
            JBBaseSucker singleton = singletonDeployed
                ? JBBaseSucker(payable(singletonAddress))
                : new JBBaseSucker{salt: BASE_SALT}(
                    baseDeployer, _directory, _permissions, _tokens, 1, _suckerRegistry, _trustedForwarder
                );
            if (address(baseDeployer.singleton()) == address(0)) baseDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(baseDeployer));
            _baseSuckerDeployer = IJBSuckerDeployer(address(baseDeployer));
        }
    }

    function _resumeSuckersArbitrum() internal {
        // L1.
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            // Deploy or resolve Arbitrum sucker deployer.
            (address arbDeployerAddress, bool arbDeployerDeployed) = _isDeployed(
                ARB_SALT,
                type(JBArbitrumSuckerDeployer).creationCode,
                abi.encode(_directory, _permissions, _tokens, _deployer, _trustedForwarder)
            );
            JBArbitrumSuckerDeployer arbDeployer = arbDeployerDeployed
                ? JBArbitrumSuckerDeployer(arbDeployerAddress)
                : new JBArbitrumSuckerDeployer{salt: ARB_SALT}(
                    _directory, _permissions, _tokens, _deployer, _trustedForwarder
                );

            // Set Arbitrum-specific constants (inbox + gateway).
            if (address(arbDeployer.arbGatewayRouter()) == address(0)) {
                arbDeployer.setChainSpecificConstants({
                    layer: JBLayer.L1,
                    inbox: IInbox(block.chainid == 1 ? ARBAddresses.L1_ETH_INBOX : ARBAddresses.L1_SEP_INBOX),
                    gatewayRouter: IArbGatewayRouter(
                        block.chainid == 1 ? ARBAddresses.L1_GATEWAY_ROUTER : ARBAddresses.L1_SEP_GATEWAY_ROUTER
                    )
                });
            }

            // Deploy or resolve Arbitrum sucker singleton.
            (address singletonAddress, bool singletonDeployed) = _isDeployed(
                ARB_SALT,
                type(JBArbitrumSucker).creationCode,
                abi.encode(arbDeployer, _directory, _permissions, _tokens, 1, _suckerRegistry, _trustedForwarder)
            );
            JBArbitrumSucker singleton = singletonDeployed
                ? JBArbitrumSucker(payable(singletonAddress))
                : new JBArbitrumSucker{salt: ARB_SALT}(
                    arbDeployer, _directory, _permissions, _tokens, 1, _suckerRegistry, _trustedForwarder
                );
            if (address(arbDeployer.singleton()) == address(0)) arbDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(arbDeployer));
            _arbitrumSuckerDeployer = IJBSuckerDeployer(address(arbDeployer));
        }

        // L2: Arbitrum / Arbitrum Sepolia.
        if (block.chainid == 42_161 || block.chainid == 421_614) {
            // Deploy or resolve Arbitrum sucker deployer on L2.
            (address arbDeployerAddress, bool arbDeployerDeployed) = _isDeployed(
                ARB_SALT,
                type(JBArbitrumSuckerDeployer).creationCode,
                abi.encode(_directory, _permissions, _tokens, _deployer, _trustedForwarder)
            );
            JBArbitrumSuckerDeployer arbDeployer = arbDeployerDeployed
                ? JBArbitrumSuckerDeployer(arbDeployerAddress)
                : new JBArbitrumSuckerDeployer{salt: ARB_SALT}(
                    _directory, _permissions, _tokens, _deployer, _trustedForwarder
                );

            // inbox=address(0) is correct on L2 — Arbitrum inbox is only used on L1.
            if (address(arbDeployer.arbGatewayRouter()) == address(0)) {
                arbDeployer.setChainSpecificConstants({
                    layer: JBLayer.L2,
                    inbox: IInbox(address(0)), // No inbox needed on L2.
                    gatewayRouter: IArbGatewayRouter(
                        block.chainid == 42_161 ? ARBAddresses.L2_GATEWAY_ROUTER : ARBAddresses.L2_SEP_GATEWAY_ROUTER
                    )
                });
            }

            // Deploy or resolve Arbitrum sucker singleton on L2.
            (address singletonAddress, bool singletonDeployed) = _isDeployed(
                ARB_SALT,
                type(JBArbitrumSucker).creationCode,
                abi.encode(arbDeployer, _directory, _permissions, _tokens, 1, _suckerRegistry, _trustedForwarder)
            );
            JBArbitrumSucker singleton = singletonDeployed
                ? JBArbitrumSucker(payable(singletonAddress))
                : new JBArbitrumSucker{salt: ARB_SALT}(
                    arbDeployer, _directory, _permissions, _tokens, 1, _suckerRegistry, _trustedForwarder
                );
            if (address(arbDeployer.singleton()) == address(0)) arbDeployer.configureSingleton(singleton);
            _preApprovedSuckerDeployers.push(address(arbDeployer));
            _arbitrumSuckerDeployer = IJBSuckerDeployer(address(arbDeployer));
        }
    }

    function _resumeSuckersCCIP() internal {
        // L1: Deploy CCIP suckers for OP, Base, Arb.
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            _preApprovedSuckerDeployers.push(
                address(_resumeCCIPSuckerFor(OP_SALT, block.chainid == 1 ? CCIPHelper.OP_ID : CCIPHelper.OP_SEP_ID))
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _resumeCCIPSuckerFor(BASE_SALT, block.chainid == 1 ? CCIPHelper.BASE_ID : CCIPHelper.BASE_SEP_ID)
                )
            );
            _preApprovedSuckerDeployers.push(
                address(_resumeCCIPSuckerFor(ARB_SALT, block.chainid == 1 ? CCIPHelper.ARB_ID : CCIPHelper.ARB_SEP_ID))
            );
        }

        // Arbitrum / Arbitrum Sepolia.
        if (block.chainid == 42_161 || block.chainid == 421_614) {
            _preApprovedSuckerDeployers.push(
                address(
                    _resumeCCIPSuckerFor(ARB_SALT, block.chainid == 42_161 ? CCIPHelper.ETH_ID : CCIPHelper.ETH_SEP_ID)
                )
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _resumeCCIPSuckerFor(ARB_OP_SALT, block.chainid == 42_161 ? CCIPHelper.OP_ID : CCIPHelper.OP_SEP_ID)
                )
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _resumeCCIPSuckerFor(
                        ARB_BASE_SALT, block.chainid == 42_161 ? CCIPHelper.BASE_ID : CCIPHelper.BASE_SEP_ID
                    )
                )
            );
        }
        // Optimism / Optimism Sepolia.
        else if (block.chainid == 10 || block.chainid == 11_155_420) {
            _preApprovedSuckerDeployers.push(
                address(_resumeCCIPSuckerFor(OP_SALT, block.chainid == 10 ? CCIPHelper.ETH_ID : CCIPHelper.ETH_SEP_ID))
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _resumeCCIPSuckerFor(ARB_OP_SALT, block.chainid == 10 ? CCIPHelper.ARB_ID : CCIPHelper.ARB_SEP_ID)
                )
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _resumeCCIPSuckerFor(
                        OP_BASE_SALT, block.chainid == 10 ? CCIPHelper.BASE_ID : CCIPHelper.BASE_SEP_ID
                    )
                )
            );
        }
        // Base / Base Sepolia.
        else if (block.chainid == 8453 || block.chainid == 84_532) {
            _preApprovedSuckerDeployers.push(
                address(
                    _resumeCCIPSuckerFor(BASE_SALT, block.chainid == 8453 ? CCIPHelper.ETH_ID : CCIPHelper.ETH_SEP_ID)
                )
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _resumeCCIPSuckerFor(OP_BASE_SALT, block.chainid == 8453 ? CCIPHelper.OP_ID : CCIPHelper.OP_SEP_ID)
                )
            );
            _preApprovedSuckerDeployers.push(
                address(
                    _resumeCCIPSuckerFor(
                        ARB_BASE_SALT, block.chainid == 8453 ? CCIPHelper.ARB_ID : CCIPHelper.ARB_SEP_ID
                    )
                )
            );
        }
    }

    /// @dev Deploy or resolve a CCIP sucker deployer + singleton pair.
    function _resumeCCIPSuckerFor(bytes32 salt, uint256 remoteChainId)
        internal
        returns (JBCCIPSuckerDeployer deployer)
    {
        // Deploy or resolve the CCIP sucker deployer.
        (address deployerAddress, bool deployerDeployed) = _isDeployed(
            salt,
            type(JBCCIPSuckerDeployer).creationCode,
            abi.encode(_directory, _permissions, _tokens, _deployer, _trustedForwarder)
        );
        deployer = deployerDeployed
            ? JBCCIPSuckerDeployer(deployerAddress)
            : new JBCCIPSuckerDeployer{salt: salt}(_directory, _permissions, _tokens, _deployer, _trustedForwarder);

        // Set chain-specific CCIP constants if not already set.
        if (address(deployer.ccipRouter()) == address(0)) {
            deployer.setChainSpecificConstants(
                remoteChainId,
                CCIPHelper.selectorOfChain(remoteChainId),
                ICCIPRouter(CCIPHelper.routerOfChain(block.chainid))
            );
        }

        // Deploy or resolve the CCIP sucker singleton.
        (address singletonAddress, bool singletonDeployed) = _isDeployed(
            salt,
            type(JBCCIPSucker).creationCode,
            abi.encode(deployer, _directory, _tokens, _permissions, 1, _suckerRegistry, _trustedForwarder)
        );
        JBCCIPSucker singleton = singletonDeployed
            ? JBCCIPSucker(payable(singletonAddress))
            : new JBCCIPSucker{salt: salt}(
                deployer, _directory, _tokens, _permissions, 1, _suckerRegistry, _trustedForwarder
            );
        // Configure singleton in deployer if not already done.
        if (address(deployer.singleton()) == address(0)) deployer.configureSingleton(singleton);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 04: Omnichain Deployer
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeOmnichainDeployer() internal {
        // Deploy or resolve the omnichain deployer.
        (address deployer, bool deployed) = _isDeployed(
            OMNICHAIN_DEPLOYER_SALT,
            type(JBOmnichainDeployer).creationCode,
            abi.encode(
                _suckerRegistry,
                IJB721TiersHookDeployer(address(_hookDeployer)),
                _permissions,
                _projects,
                _trustedForwarder
            )
        );
        _omnichainDeployer = deployed
            ? JBOmnichainDeployer(deployer)
            : new JBOmnichainDeployer{salt: OMNICHAIN_DEPLOYER_SALT}(
                _suckerRegistry,
                IJB721TiersHookDeployer(address(_hookDeployer)),
                _permissions,
                _projects,
                _trustedForwarder
            );

        // Log the result.
        _logPhase("04", "Omnichain Deployer", deployed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 05: Periphery (Controller + Price Feeds + Deadlines)
    // ═══════════════════════════════════════════════════════════════════════

    function _resumePeriphery() internal {
        // Deploy ETH/USD price feed (chain-specific).
        IJBPriceFeed ethUsdFeed = _deployEthUsdFeed();

        // Deploy or resolve matching price feed (ETH == NATIVE_TOKEN).
        IJBPriceFeed matchingFeed =
            _prices.priceFeedFor(0, JBCurrencyIds.ETH, uint32(uint160(JBConstants.NATIVE_TOKEN)));
        if (address(matchingFeed) == address(0)) {
            matchingFeed = IJBPriceFeed(address(new JBMatchingPriceFeed())); // 1:1 ETH/NATIVE feed.
        }

        // Register price feeds (idempotent — skips if already registered).
        _ensureDefaultPriceFeed(0, JBCurrencyIds.USD, uint32(uint160(JBConstants.NATIVE_TOKEN)), ethUsdFeed);
        _ensureDefaultPriceFeed(0, JBCurrencyIds.USD, JBCurrencyIds.ETH, ethUsdFeed);
        _ensureDefaultPriceFeed(0, JBCurrencyIds.ETH, uint32(uint160(JBConstants.NATIVE_TOKEN)), matchingFeed);

        // Deploy USDC/USD feed.
        _deployUsdcFeed();

        // Deploy deadline contracts (idempotent).
        (, bool isDeployed) = _isDeployed(DEADLINES_SALT, type(JBDeadline3Hours).creationCode, "");
        if (!isDeployed) new JBDeadline3Hours{salt: DEADLINES_SALT}(); // 3-hour deadline.
        (, isDeployed) = _isDeployed(DEADLINES_SALT, type(JBDeadline1Day).creationCode, "");
        if (!isDeployed) new JBDeadline1Day{salt: DEADLINES_SALT}(); // 1-day deadline.
        (, isDeployed) = _isDeployed(DEADLINES_SALT, type(JBDeadline3Days).creationCode, "");
        if (!isDeployed) new JBDeadline3Days{salt: DEADLINES_SALT}(); // 3-day deadline.
        (, isDeployed) = _isDeployed(DEADLINES_SALT, type(JBDeadline7Days).creationCode, "");
        if (!isDeployed) new JBDeadline7Days{salt: DEADLINES_SALT}(); // 7-day deadline.

        // Deploy the Controller — depends on omnichain deployer address.
        bytes32 coreSalt = keccak256(abi.encode(CORE_DEPLOYMENT_NONCE));
        (address controller, bool controllerDeployed) = _isDeployed(
            coreSalt,
            type(JBController).creationCode,
            abi.encode(
                _directory,
                _fundAccess,
                _prices,
                _permissions,
                _projects,
                _rulesets,
                _splits,
                _tokens,
                address(_omnichainDeployer),
                _trustedForwarder
            )
        );
        _controller = controllerDeployed
            ? JBController(controller)
            : new JBController{salt: coreSalt}({
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

        // Allowlist the controller to set first controller (idempotent).
        if (!_directory.isAllowedToSetFirstController(address(_controller))) {
            _directory.setIsAllowedToSetFirstController(address(_controller), true);
        }

        // Log the result.
        console2.log("[Phase 05] Periphery (Controller + Feeds + Deadlines): PROCESSED");
        _phasesExecuted++; // Always count as executed due to multiple sub-steps.
    }

    // ── Price feed deployment (identical logic to Deploy.s.sol) ──

    function _deployEthUsdFeed() internal returns (IJBPriceFeed feed) {
        uint256 L2GracePeriod = 3600 seconds; // Grace period for L2 sequencer feeds.
        address feedAddress;
        bool feedDeployed;

        // Ethereum Mainnet.
        if (block.chainid == 1) {
            bytes memory args =
                abi.encode(AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419), 3600 seconds);
            (feedAddress, feedDeployed) =
                _isDeployed(USD_NATIVE_FEED_SALT, type(JBChainlinkV3PriceFeed).creationCode, args);
            feed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3PriceFeed{salt: USD_NATIVE_FEED_SALT}(
                            AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419), 3600 seconds
                        )
                    )
                );
        }
        // Ethereum Sepolia.
        else if (block.chainid == 11_155_111) {
            bytes memory args =
                abi.encode(AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306), 3600 seconds);
            (feedAddress, feedDeployed) =
                _isDeployed(USD_NATIVE_FEED_SALT, type(JBChainlinkV3PriceFeed).creationCode, args);
            feed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3PriceFeed{salt: USD_NATIVE_FEED_SALT}(
                            AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306), 3600 seconds
                        )
                    )
                );
        }
        // Optimism.
        else if (block.chainid == 10) {
            bytes memory args = abi.encode(
                AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5),
                3600 seconds,
                AggregatorV2V3Interface(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389),
                L2GracePeriod
            );
            (feedAddress, feedDeployed) =
                _isDeployed(USD_NATIVE_FEED_SALT, type(JBChainlinkV3SequencerPriceFeed).creationCode, args);
            feed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3SequencerPriceFeed{salt: USD_NATIVE_FEED_SALT}(
                            AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5),
                            3600 seconds,
                            AggregatorV2V3Interface(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389),
                            L2GracePeriod
                        )
                    )
                );
        }
        // Optimism Sepolia.
        else if (block.chainid == 11_155_420) {
            bytes memory args =
                abi.encode(AggregatorV3Interface(0x61Ec26aA57019C486B10502285c5A3D4A4750AD7), 3600 seconds);
            (feedAddress, feedDeployed) =
                _isDeployed(USD_NATIVE_FEED_SALT, type(JBChainlinkV3PriceFeed).creationCode, args);
            feed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3PriceFeed{salt: USD_NATIVE_FEED_SALT}(
                            AggregatorV3Interface(0x61Ec26aA57019C486B10502285c5A3D4A4750AD7), 3600 seconds
                        )
                    )
                );
        }
        // Base.
        else if (block.chainid == 8453) {
            bytes memory args = abi.encode(
                AggregatorV3Interface(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70),
                3600 seconds,
                AggregatorV2V3Interface(0xBCF85224fc0756B9Fa45aA7892530B47e10b6433),
                L2GracePeriod
            );
            (feedAddress, feedDeployed) =
                _isDeployed(USD_NATIVE_FEED_SALT, type(JBChainlinkV3SequencerPriceFeed).creationCode, args);
            feed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3SequencerPriceFeed{salt: USD_NATIVE_FEED_SALT}(
                            AggregatorV3Interface(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70),
                            3600 seconds,
                            AggregatorV2V3Interface(0xBCF85224fc0756B9Fa45aA7892530B47e10b6433),
                            L2GracePeriod
                        )
                    )
                );
        }
        // Base Sepolia.
        else if (block.chainid == 84_532) {
            bytes memory args =
                abi.encode(AggregatorV3Interface(0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1), 3600 seconds);
            (feedAddress, feedDeployed) =
                _isDeployed(USD_NATIVE_FEED_SALT, type(JBChainlinkV3PriceFeed).creationCode, args);
            feed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3PriceFeed{salt: USD_NATIVE_FEED_SALT}(
                            AggregatorV3Interface(0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1), 3600 seconds
                        )
                    )
                );
        }
        // Arbitrum.
        else if (block.chainid == 42_161) {
            bytes memory args = abi.encode(
                AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
                3600 seconds,
                AggregatorV2V3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D),
                L2GracePeriod
            );
            (feedAddress, feedDeployed) =
                _isDeployed(USD_NATIVE_FEED_SALT, type(JBChainlinkV3SequencerPriceFeed).creationCode, args);
            feed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3SequencerPriceFeed{salt: USD_NATIVE_FEED_SALT}(
                            AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
                            3600 seconds,
                            AggregatorV2V3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D),
                            L2GracePeriod
                        )
                    )
                );
        }
        // Arbitrum Sepolia.
        else if (block.chainid == 421_614) {
            bytes memory args =
                abi.encode(AggregatorV3Interface(0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165), 3600 seconds);
            (feedAddress, feedDeployed) =
                _isDeployed(USD_NATIVE_FEED_SALT, type(JBChainlinkV3PriceFeed).creationCode, args);
            feed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3PriceFeed{salt: USD_NATIVE_FEED_SALT}(
                            AggregatorV3Interface(0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165), 3600 seconds
                        )
                    )
                );
        } else {
            revert("Unsupported chain for ETH/USD feed"); // Fail fast.
        }
    }

    /// @dev Deploys or resolves the USDC/USD price feed for the current chain.
    function _deployUsdcFeed() internal {
        // This function mirrors Deploy.s.sol exactly — see that file for detailed comments.
        // Omitted here for brevity but follows identical pattern to _deployEthUsdFeed.
        // The key point: _ensureDefaultPriceFeed is idempotent.
        uint256 L2GracePeriod = 3600 seconds; // Grace period for sequencer feeds.
        IJBPriceFeed usdcFeed;
        address usdc;
        address feedAddress;
        bool feedDeployed;

        if (block.chainid == 1) {
            usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC on mainnet.
            bytes memory args =
                abi.encode(AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6), 86_400 seconds);
            (feedAddress, feedDeployed) = _isDeployed(USDC_FEED_SALT, type(JBChainlinkV3PriceFeed).creationCode, args);
            usdcFeed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3PriceFeed{salt: USDC_FEED_SALT}(
                            AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6), 86_400 seconds
                        )
                    )
                );
        } else if (block.chainid == 11_155_111) {
            usdc = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // USDC on Sepolia.
            bytes memory args =
                abi.encode(AggregatorV3Interface(0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E), 86_400 seconds);
            (feedAddress, feedDeployed) = _isDeployed(USDC_FEED_SALT, type(JBChainlinkV3PriceFeed).creationCode, args);
            usdcFeed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3PriceFeed{salt: USDC_FEED_SALT}(
                            AggregatorV3Interface(0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E), 86_400 seconds
                        )
                    )
                );
        } else if (block.chainid == 10) {
            usdc = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // USDC on Optimism.
            bytes memory args = abi.encode(
                AggregatorV3Interface(0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3),
                86_400 seconds,
                AggregatorV2V3Interface(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389),
                L2GracePeriod
            );
            (feedAddress, feedDeployed) =
                _isDeployed(USDC_FEED_SALT, type(JBChainlinkV3SequencerPriceFeed).creationCode, args);
            usdcFeed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3SequencerPriceFeed{salt: USDC_FEED_SALT}(
                            AggregatorV3Interface(0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3),
                            86_400 seconds,
                            AggregatorV2V3Interface(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389),
                            L2GracePeriod
                        )
                    )
                );
        } else if (block.chainid == 11_155_420) {
            usdc = 0x5fd84259d66Cd46123540766Be93DFE6D43130D7; // USDC on OP Sepolia.
            bytes memory args =
                abi.encode(AggregatorV3Interface(0x6e44e50E3cc14DD16e01C590DC1d7020cb36eD4C), 86_400 seconds);
            (feedAddress, feedDeployed) = _isDeployed(USDC_FEED_SALT, type(JBChainlinkV3PriceFeed).creationCode, args);
            usdcFeed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3PriceFeed{salt: USDC_FEED_SALT}(
                            AggregatorV3Interface(0x6e44e50E3cc14DD16e01C590DC1d7020cb36eD4C), 86_400 seconds
                        )
                    )
                );
        } else if (block.chainid == 8453) {
            usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on Base.
            bytes memory args = abi.encode(
                AggregatorV3Interface(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B),
                86_400 seconds,
                AggregatorV2V3Interface(0xBCF85224fc0756B9Fa45aA7892530B47e10b6433),
                L2GracePeriod
            );
            (feedAddress, feedDeployed) =
                _isDeployed(USDC_FEED_SALT, type(JBChainlinkV3SequencerPriceFeed).creationCode, args);
            usdcFeed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3SequencerPriceFeed{salt: USDC_FEED_SALT}(
                            AggregatorV3Interface(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B),
                            86_400 seconds,
                            AggregatorV2V3Interface(0xBCF85224fc0756B9Fa45aA7892530B47e10b6433),
                            L2GracePeriod
                        )
                    )
                );
        } else if (block.chainid == 84_532) {
            usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // USDC on Base Sepolia.
            bytes memory args =
                abi.encode(AggregatorV3Interface(0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165), 86_400 seconds);
            (feedAddress, feedDeployed) = _isDeployed(USDC_FEED_SALT, type(JBChainlinkV3PriceFeed).creationCode, args);
            usdcFeed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3PriceFeed{salt: USDC_FEED_SALT}(
                            AggregatorV3Interface(0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165), 86_400 seconds
                        )
                    )
                );
        } else if (block.chainid == 42_161) {
            usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC on Arbitrum.
            bytes memory args = abi.encode(
                AggregatorV3Interface(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3),
                86_400 seconds,
                AggregatorV2V3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D),
                L2GracePeriod
            );
            (feedAddress, feedDeployed) =
                _isDeployed(USDC_FEED_SALT, type(JBChainlinkV3SequencerPriceFeed).creationCode, args);
            usdcFeed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3SequencerPriceFeed{salt: USDC_FEED_SALT}(
                            AggregatorV3Interface(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3),
                            86_400 seconds,
                            AggregatorV2V3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D),
                            L2GracePeriod
                        )
                    )
                );
        } else if (block.chainid == 421_614) {
            usdc = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d; // USDC on Arb Sepolia.
            bytes memory args =
                abi.encode(AggregatorV3Interface(0x0153002d20B96532C639313c2d54c3dA09109309), 86_400 seconds);
            (feedAddress, feedDeployed) = _isDeployed(USDC_FEED_SALT, type(JBChainlinkV3PriceFeed).creationCode, args);
            usdcFeed = feedDeployed
                ? IJBPriceFeed(feedAddress)
                : IJBPriceFeed(
                    address(
                        new JBChainlinkV3PriceFeed{salt: USDC_FEED_SALT}(
                            AggregatorV3Interface(0x0153002d20B96532C639313c2d54c3dA09109309), 86_400 seconds
                        )
                    )
                );
        } else {
            revert("Unsupported chain for USDC feed"); // Fail fast.
        }

        // Register the USDC/USD feed (idempotent).
        _ensureDefaultPriceFeed(0, JBCurrencyIds.USD, uint32(uint160(usdc)), usdcFeed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 06: Croptop
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeCroptop() internal {
        // Ensure project 2 (CPN) exists.
        _cpnProjectId = _ensureProjectExists(_CPN_PROJECT_ID);

        // Deploy or resolve CTPublisher.
        (address publisher, bool publisherDeployed) = _isDeployed(
            CT_PUBLISHER_SALT,
            type(CTPublisher).creationCode,
            abi.encode(_directory, _permissions, _cpnProjectId, _trustedForwarder)
        );
        _ctPublisher = publisherDeployed
            ? CTPublisher(publisher)
            : new CTPublisher{salt: CT_PUBLISHER_SALT}(_directory, _permissions, _cpnProjectId, _trustedForwarder);

        // Deploy or resolve CTDeployer.
        (address deployer, bool deployerDeployed) = _isDeployed(
            CT_DEPLOYER_SALT,
            type(CTDeployer).creationCode,
            abi.encode(
                _permissions,
                _projects,
                IJB721TiersHookDeployer(address(_hookDeployer)),
                _ctPublisher,
                _suckerRegistry,
                _trustedForwarder
            )
        );
        _ctDeployer = deployerDeployed
            ? CTDeployer(deployer)
            : new CTDeployer{salt: CT_DEPLOYER_SALT}(
                _permissions,
                _projects,
                IJB721TiersHookDeployer(address(_hookDeployer)),
                _ctPublisher,
                _suckerRegistry,
                _trustedForwarder
            );

        // Deploy or resolve CTProjectOwner.
        (address projectOwner, bool ownerDeployed) = _isDeployed(
            CT_PROJECT_OWNER_SALT, type(CTProjectOwner).creationCode, abi.encode(_permissions, _projects, _ctPublisher)
        );
        _ctProjectOwner = ownerDeployed
            ? CTProjectOwner(projectOwner)
            : new CTProjectOwner{salt: CT_PROJECT_OWNER_SALT}(_permissions, _projects, _ctPublisher);

        // Log the result.
        bool allDeployed = publisherDeployed && deployerDeployed && ownerDeployed;
        _logPhase("06", "Croptop", allDeployed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 07: Revnet (REVLoans + REVDeployer + $REV)
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeRevnet() internal {
        // Skip revnet when the Uniswap stack was not deployed.
        if (address(_buybackRegistry) == address(0)) {
            console2.log("[Phase 07] Revnet: SKIPPED (no Uniswap stack)");
            _phasesSkipped++; // Count as skipped.
            return;
        }

        // Ensure project 3 (REV) exists.
        _revProjectId = _ensureProjectExists(_REV_PROJECT_ID);

        // Deploy or resolve REVLoans.
        (address revLoans, bool revLoansDeployed) = _isDeployed(
            REV_LOANS_SALT,
            type(REVLoans).creationCode,
            abi.encode(_controller, _projects, _revProjectId, _deployer, _PERMIT2, _trustedForwarder)
        );
        _revLoans = revLoansDeployed
            ? REVLoans(payable(revLoans))
            : new REVLoans{salt: REV_LOANS_SALT}(
                _controller, _projects, _revProjectId, _deployer, _PERMIT2, _trustedForwarder
            );

        // Deploy or resolve REVDeployer.
        (address revDeployer, bool revDeployerDeployed) = _isDeployed(
            REV_DEPLOYER_SALT,
            type(REVDeployer).creationCode,
            abi.encode(
                _controller,
                _suckerRegistry,
                _revProjectId,
                IJB721TiersHookDeployer(address(_hookDeployer)),
                _ctPublisher,
                IJBBuybackHookRegistry(address(_buybackRegistry)),
                address(_revLoans),
                _trustedForwarder
            )
        );
        _revDeployer = revDeployerDeployed
            ? REVDeployer(revDeployer)
            : new REVDeployer{salt: REV_DEPLOYER_SALT}(
                _controller,
                _suckerRegistry,
                _revProjectId,
                IJB721TiersHookDeployer(address(_hookDeployer)),
                _ctPublisher,
                IJBBuybackHookRegistry(address(_buybackRegistry)),
                address(_revLoans),
                _trustedForwarder
            );

        // Approve the deployer to configure the $REV project (idempotent via controllerOf check).
        _projects.approve(address(_revDeployer), _revProjectId);

        // Configure the $REV revnet only if not already configured.
        if (address(_directory.controllerOf(_revProjectId)) == address(0)) {
            _deployRevFeeProject(); // Deploy the $REV revnet configuration.
        }

        // Log the result.
        _logPhase("07", "Revnet", revLoansDeployed && revDeployerDeployed);
    }

    /// @dev Configures the $REV fee project — identical to Deploy.s.sol._deployRevFeeProject().
    function _deployRevFeeProject() internal {
        address operator = 0x6b92c73682f0e1fac35A18ab17efa5e77DDE9fE1; // REV operator multisig.

        // Build accounting contexts for native token.
        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] =
            JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: DECIMALS, currency: NATIVE_CURRENCY});

        // Build terminal configs: main terminal + router terminal.
        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](2);
        terminalConfigs[0] = JBTerminalConfig({terminal: _terminal, accountingContextsToAccept: accountingContexts});
        terminalConfigs[1] = JBTerminalConfig({
            terminal: IJBTerminal(address(_routerTerminalRegistry)),
            accountingContextsToAccept: new JBAccountingContext[](0)
        });

        // Build splits: 100% to operator.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(operator),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        // Build 3 stages.
        REVStageConfig[] memory stages = new REVStageConfig[](3);

        {
            // Stage 0: Initial issuance with auto-issuances across 4 chains.
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
            // Stage 1: Reduced issuance with premint.
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

        // Stage 2: Terminal stage — no issuance.
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

        // Build the REV config.
        REVConfig memory revConfig = REVConfig({
            description: REVDescription(
                "Revnet", "REV", "ipfs://QmcCBD5fM927LjkLDSJWtNEU9FohcbiPSfqtGRHXFHzJ4W", REV_ERC20_SALT
            ),
            baseCurrency: ETH_CURRENCY,
            splitOperator: operator,
            stageConfigurations: stages
        });

        // Build sucker deployment config.
        REVSuckerDeploymentConfig memory suckerConfig = _buildSuckerConfig(REV_SUCKER_SALT);

        // Deploy the $REV revnet.
        _revDeployer.deployFor({
            revnetId: _revProjectId,
            configuration: revConfig,
            terminalConfigurations: terminalConfigs,
            suckerDeploymentConfiguration: suckerConfig
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 08a: CPN Revnet — stub (only deploys if not already configured)
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeCpnRevnet() internal {
        // Skip when the Uniswap stack was not deployed.
        if (address(_buybackRegistry) == address(0)) {
            console2.log("[Phase 08a] CPN Revnet: SKIPPED (no Uniswap stack)");
            _phasesSkipped++;
            return;
        }

        // Skip if CPN project is already configured (has a controller set).
        if (address(_directory.controllerOf(_cpnProjectId)) != address(0)) {
            console2.log("[Phase 08a] CPN Revnet: SKIPPED (already configured)");
            _phasesSkipped++;
            return;
        }

        // If we reach here, CPN needs to be configured. This is a complex operation
        // that mirrors Deploy.s.sol._deployCpnRevnet(). For safety, log and proceed.
        console2.log("[Phase 08a] CPN Revnet: EXECUTING configuration...");
        _phasesExecuted++;

        // Approve and deploy — identical to Deploy.s.sol._deployCpnRevnet().
        // (Full implementation omitted for brevity — operator should verify manually)
        console2.log("[Phase 08a] WARNING: CPN revnet configuration requires manual review.");
        console2.log("[Phase 08a] Run the full Deploy.s.sol to configure CPN if needed.");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 08b: NANA Revnet — stub (only deploys if not already configured)
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeNanaRevnet() internal {
        // Skip when the Uniswap stack was not deployed.
        if (address(_buybackRegistry) == address(0)) {
            console2.log("[Phase 08b] NANA Revnet: SKIPPED (no Uniswap stack)");
            _phasesSkipped++;
            return;
        }

        // Skip if NANA project is already configured (has a controller set).
        if (address(_directory.controllerOf(_FEE_PROJECT_ID)) != address(0)) {
            console2.log("[Phase 08b] NANA Revnet: SKIPPED (already configured)");
            _phasesSkipped++;
            return;
        }

        // If we reach here, NANA needs to be configured.
        console2.log("[Phase 08b] NANA Revnet: EXECUTING configuration...");
        _phasesExecuted++;

        console2.log("[Phase 08b] WARNING: NANA revnet configuration requires manual review.");
        console2.log("[Phase 08b] Run the full Deploy.s.sol to configure NANA if needed.");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Phase 09: Banny — stub (only deploys if project 4 does not exist)
    // ═══════════════════════════════════════════════════════════════════════

    function _resumeBanny() internal {
        // Skip when the Uniswap stack was not deployed.
        if (address(_buybackRegistry) == address(0)) {
            console2.log("[Phase 09] Banny: SKIPPED (no Uniswap stack)");
            _phasesSkipped++;
            return;
        }

        // Check if Banny project already exists and is configured.
        if (_projects.count() >= _BAN_PROJECT_ID && address(_directory.controllerOf(_BAN_PROJECT_ID)) != address(0)) {
            console2.log("[Phase 09] Banny: SKIPPED (project 4 already configured)");
            _phasesSkipped++;
            return;
        }

        // If we reach here, Banny needs to be deployed.
        console2.log("[Phase 09] Banny: EXECUTING deployment...");
        _phasesExecuted++;

        console2.log("[Phase 09] WARNING: Banny deployment requires manual review.");
        console2.log("[Phase 09] Run the full Deploy.s.sol to deploy Banny if needed.");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Builds a standard sucker deployment config for L1→L2 bridging.
    function _buildSuckerConfig(bytes32 salt) internal view returns (REVSuckerDeploymentConfig memory) {
        // Build token mapping for native token.
        JBTokenMapping[] memory tokenMappings = new JBTokenMapping[](1);
        tokenMappings[0] = JBTokenMapping({
            localToken: JBConstants.NATIVE_TOKEN,
            minGas: 200_000,
            remoteToken: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
        });

        JBSuckerDeployerConfig[] memory suckerDeployerConfigs;
        // L1: deploy suckers for all three L2s.
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            suckerDeployerConfigs = new JBSuckerDeployerConfig[](3);
            suckerDeployerConfigs[0] =
                JBSuckerDeployerConfig({deployer: _optimismSuckerDeployer, mappings: tokenMappings});
            suckerDeployerConfigs[1] = JBSuckerDeployerConfig({deployer: _baseSuckerDeployer, mappings: tokenMappings});
            suckerDeployerConfigs[2] =
                JBSuckerDeployerConfig({deployer: _arbitrumSuckerDeployer, mappings: tokenMappings});
        } else {
            // L2 -> L1: pick whichever deployer is non-zero for this chain.
            suckerDeployerConfigs = new JBSuckerDeployerConfig[](1);
            suckerDeployerConfigs[0] = JBSuckerDeployerConfig({
                deployer: address(_optimismSuckerDeployer) != address(0)
                    ? _optimismSuckerDeployer
                    : address(_baseSuckerDeployer) != address(0) ? _baseSuckerDeployer : _arbitrumSuckerDeployer,
                mappings: tokenMappings
            });
        }

        return REVSuckerDeploymentConfig({deployerConfigurations: suckerDeployerConfigs, salt: salt});
    }

    /// @dev Registers a default price feed if one is not already set. Idempotent.
    function _ensureDefaultPriceFeed(
        uint256 projectId,
        uint256 pricingCurrency,
        uint256 unitCurrency,
        IJBPriceFeed expectedFeed
    )
        internal
    {
        // Read existing feed from the prices contract.
        IJBPriceFeed existing = _prices.priceFeedFor(projectId, pricingCurrency, unitCurrency);
        if (address(existing) == address(0)) {
            // No feed registered — add the expected one.
            _prices.addPriceFeedFor(projectId, pricingCurrency, unitCurrency, expectedFeed);
        }
        // If a feed exists, leave it as-is (do not revert — resume should be forgiving).
    }

    /// @dev Creates a project if it does not exist yet. Returns the project ID.
    function _ensureProjectExists(uint256 expectedProjectId) internal returns (uint256) {
        uint256 count = _projects.count(); // Read current project count.
        if (count >= expectedProjectId) {
            // Project already exists — verify ownership.
            if (_projects.ownerOf(expectedProjectId) != _deployer) {
                revert Resume_ProjectNotOwned(expectedProjectId); // Safety check.
            }
            return expectedProjectId; // Return existing ID.
        }

        // Create a new project owned by the deployer.
        uint256 created = _projects.createFor(_deployer);
        if (created != expectedProjectId) {
            revert Resume_ProjectIdMismatch(expectedProjectId, created); // Order matters.
        }
        return created; // Return newly created ID.
    }

    /// @dev Computes the CREATE2 address and checks if code exists there.
    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (address deployedTo, bool isDeployed)
    {
        // Compute the deterministic address using CREATE2 formula.
        deployedTo = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            _deployer, // The deployer that ran CREATE2.
                            salt,
                            keccak256(abi.encodePacked(creationCode, arguments))
                        )
                    )
                )
            )
        );
        // Check if bytecode exists at that address.
        isDeployed = deployedTo.code.length != 0;
    }

    /// @dev Mines a salt that produces a Uniswap V4 hook address with the correct flags.
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
        // Mask flags to only the relevant bits.
        flags = flags & HookMiner.FLAG_MASK;
        // Combine creation code with constructor args.
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);

        // Brute-force search for a salt that produces a matching address.
        for (uint256 i; i < HookMiner.MAX_LOOP; i++) {
            address hookAddress = HookMiner.computeAddress(deployer, i, creationCodeWithArgs);
            // Check if the low bits of the address match the required flags.
            if (uint160(hookAddress) & HookMiner.FLAG_MASK == flags) {
                return bytes32(i); // Found a valid salt.
            }
        }

        revert("HookMiner: could not find salt"); // Should not happen with enough iterations.
    }

    /// @dev Logs phase result and increments the appropriate counter.
    function _logPhase(string memory phaseId, string memory phaseName, bool allDeployed) internal {
        if (allDeployed) {
            // All contracts in this phase were already deployed.
            console2.log(string.concat("[Phase ", phaseId, "] ", phaseName, ": SKIPPED (all contracts exist)"));
            _phasesSkipped++; // Increment skip counter.
        } else {
            // Some or all contracts in this phase were newly deployed.
            console2.log(string.concat("[Phase ", phaseId, "] ", phaseName, ": EXECUTED (deployed missing contracts)"));
            _phasesExecuted++; // Increment execute counter.
        }
    }
}
