// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBPayHook} from "@bananapus/core-v6/src/interfaces/IJBPayHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";

// 721 Hook
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721CheckpointsDeployer} from "@bananapus/721-hook-v6/src/JB721CheckpointsDeployer.sol";
import {IJB721TiersHook} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHookStore} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "@bananapus/721-hook-v6/src/interfaces/IJB721TokenUriResolver.sol";
import {JB721TierConfig} from "@bananapus/721-hook-v6/src/structs/JB721TierConfig.sol";
import {JB721InitTiersConfig} from "@bananapus/721-hook-v6/src/structs/JB721InitTiersConfig.sol";
import {JB721TierConfigFlags} from "@bananapus/721-hook-v6/src/structs/JB721TierConfigFlags.sol";

// Address Registry
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// Buyback Hook
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";
import {IJBBuybackHook} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHook.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {IGeomeanOracle} from "@bananapus/buyback-hook-v6/src/interfaces/IGeomeanOracle.sol";

// Suckers
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// Croptop
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";

// LP Split Hook
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";
import {IJBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/interfaces/IJBUniswapV4LPSplitHook.sol";

// Uniswap V4 Router Hook
import {JBUniswapV4Hook} from "@bananapus/univ4-router-v6/src/JBUniswapV4Hook.sol";
import {JuiceboxSwapRouter} from "@bananapus/univ4-router-v6/test/utils/JuiceboxSwapRouter.sol";

// Revnet
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {REVHiddenTokens} from "@rev-net/core-v6/src/REVHiddenTokens.sol";
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";
import {IREVLoans} from "@rev-net/core-v6/src/interfaces/IREVLoans.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVDeploy721TiersHookConfig} from "@rev-net/core-v6/src/structs/REVDeploy721TiersHookConfig.sol";
import {REVBaseline721HookConfig} from "@rev-net/core-v6/src/structs/REVBaseline721HookConfig.sol";
import {REV721TiersHookFlags} from "@rev-net/core-v6/src/structs/REV721TiersHookFlags.sol";
import {REVCroptopAllowedPost} from "@rev-net/core-v6/src/structs/REVCroptopAllowedPost.sol";
import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";
import {REVLoanSource} from "@rev-net/core-v6/src/structs/REVLoanSource.sol";

// Uniswap V4
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";

/// @notice Adds liquidity to a hookless V4 pool via unlock/callback pattern.
/// Supports both native ETH (address(0)) and ERC-20 settlement.
contract EcosystemLiquidityHelper is IUnlockCallback {
    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    receive() external payable {}

    function addLiquidity(
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta
    )
        external
        payable
    {
        poolManager.unlock(abi.encode(key, tickLower, tickUpper, liquidityDelta));
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        (PoolKey memory key, int24 tickLower, int24 tickUpper, int256 liquidityDelta) =
            abi.decode(data, (PoolKey, int24, int24, int256));

        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: 0
            }),
            ""
        );

        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        if (amount0 < 0) {
            _settle(key.currency0, uint128(-amount0));
        }
        if (amount1 < 0) {
            _settle(key.currency1, uint128(-amount1));
        }

        if (amount0 > 0) poolManager.take(key.currency0, address(this), uint128(amount0));
        if (amount1 > 0) poolManager.take(key.currency1, address(this), uint128(amount1));

        return "";
    }

    function _settle(Currency currency, uint256 amount) internal {
        if (Currency.unwrap(currency) == address(0)) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).transfer(address(poolManager), amount);
            poolManager.settle();
        }
    }
}

/// @notice Ecosystem integration fork test: multi-stage revnet with buyback hook, 721 tier splits,
/// LP-split hook feeding the buyback AMM, and payments via terminal + V4 router.
///
/// Verifies all major component interactions in the full Juicebox V6 stack on forked Ethereum mainnet.
///
/// Run with: forge test --match-contract EcosystemForkTest -vvv
contract EcosystemForkTest is TestBaseWorkflow {
    using PoolIdLibrary for PoolKey;

    // ── Mainnet addresses
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant WETH_ADDR = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant V4_POSITION_MANAGER_ADDR = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;

    // ── Tick range for full-range liquidity (hookless pool)
    int24 constant TICK_LOWER = -887_200;
    int24 constant TICK_UPPER = 887_200;

    // ── Test parameters
    uint112 constant INITIAL_ISSUANCE = uint112(1000e18); // 1000 tokens per ETH
    uint32 constant STAGE_DURATION = 30 days;
    uint104 constant TIER_PRICE = 1 ether;

    // ── Actors
    address PAYER = makeAddr("payer");
    address BORROWER = makeAddr("borrower");
    address SPLIT_BENEFICIARY = makeAddr("splitBeneficiary");

    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // ── Ecosystem contracts
    IPoolManager poolManager;
    IPositionManager positionManager;
    IWETH9 weth;
    EcosystemLiquidityHelper liqHelper;

    uint256 FEE_PROJECT_ID;
    JBSuckerRegistry SUCKER_REGISTRY;
    IJB721TiersHookStore HOOK_STORE;
    JB721TiersHook EXAMPLE_HOOK;
    IJBAddressRegistry ADDRESS_REGISTRY;
    IJB721TiersHookDeployer HOOK_DEPLOYER;
    CTPublisher PUBLISHER;
    JBBuybackHook BUYBACK_HOOK;
    JBBuybackHookRegistry BUYBACK_REGISTRY;
    IREVLoans LOANS_CONTRACT;
    REVOwner REV_OWNER;
    REVDeployer REV_DEPLOYER;

    // LP-split hook
    JBUniswapV4LPSplitHook LP_SPLIT_HOOK;

    receive() external payable {}

    function setUp() public override {
        // Fork mainnet at a stable block — deterministic and post-V4 deployment.
        vm.createSelectFork("ethereum", 21_700_000);
        require(POOL_MANAGER_ADDR.code.length > 0, "PoolManager not deployed");
        require(V4_POSITION_MANAGER_ADDR.code.length > 0, "PositionManager not deployed");

        // Deploy fresh JB core on the forked mainnet.
        super.setUp();

        poolManager = IPoolManager(POOL_MANAGER_ADDR);
        positionManager = IPositionManager(V4_POSITION_MANAGER_ADDR);
        weth = IWETH9(WETH_ADDR);
        liqHelper = new EcosystemLiquidityHelper(poolManager);

        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        SUCKER_REGISTRY = new JBSuckerRegistry(jbDirectory(), jbPermissions(), multisig(), address(0));
        HOOK_STORE = new JB721TiersHookStore();
        JB721CheckpointsDeployer checkpointsDeployer = new JB721CheckpointsDeployer();
        EXAMPLE_HOOK = new JB721TiersHook(
            jbDirectory(),
            jbPermissions(),
            jbPrices(),
            jbRulesets(),
            HOOK_STORE,
            jbSplits(),
            checkpointsDeployer,
            multisig()
        );
        ADDRESS_REGISTRY = new JBAddressRegistry();
        HOOK_DEPLOYER = new JB721TiersHookDeployer(EXAMPLE_HOOK, HOOK_STORE, ADDRESS_REGISTRY, multisig());
        PUBLISHER = new CTPublisher(jbDirectory(), jbPermissions(), FEE_PROJECT_ID, multisig());

        // Deploy buyback hook with real PoolManager.
        BUYBACK_HOOK = new JBBuybackHook(
            jbDirectory(),
            jbPermissions(),
            jbPrices(),
            jbProjects(),
            jbTokens(),
            poolManager,
            IHooks(address(0)),
            address(0)
        );

        BUYBACK_REGISTRY = new JBBuybackHookRegistry(jbPermissions(), jbProjects(), address(this), address(0));
        BUYBACK_REGISTRY.setDefaultHook(IJBRulesetDataHook(address(BUYBACK_HOOK)));

        LOANS_CONTRACT = new REVLoans({
            controller: jbController(),
            suckerRegistry: IJBSuckerRegistry(address(SUCKER_REGISTRY)),
            revId: FEE_PROJECT_ID,
            owner: address(this),
            permit2: permit2(),
            trustedForwarder: TRUSTED_FORWARDER
        });

        // Deploy REVHiddenTokens.
        REVHiddenTokens revHiddenTokens = new REVHiddenTokens(jbController(), TRUSTED_FORWARDER);

        // Deploy the REVOwner — the runtime data hook for pay and cash out callbacks.
        REV_OWNER = new REVOwner(
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            jbDirectory(),
            FEE_PROJECT_ID,
            SUCKER_REGISTRY,
            address(LOANS_CONTRACT),
            address(revHiddenTokens)
        );

        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_Eco"}(
            jbController(),
            SUCKER_REGISTRY,
            FEE_PROJECT_ID,
            HOOK_DEPLOYER,
            PUBLISHER,
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            address(LOANS_CONTRACT),
            TRUSTED_FORWARDER,
            address(REV_OWNER)
        );

        vm.prank(multisig());
        jbProjects().approve(address(REV_DEPLOYER), FEE_PROJECT_ID);

        // Deploy LP-split hook (clone pattern).
        JBUniswapV4LPSplitHook lpSplitImpl = new JBUniswapV4LPSplitHook(
            address(jbDirectory()),
            jbPermissions(),
            address(jbTokens()),
            poolManager,
            positionManager,
            permit2(),
            IHooks(address(0))
        );
        LP_SPLIT_HOOK = JBUniswapV4LPSplitHook(payable(LibClone.clone(address(lpSplitImpl))));
        LP_SPLIT_HOOK.initialize(0, 0); // No fee project for simplicity.

        // Mock geomean oracle at address(0) so payments work before buyback pool is set up.
        // The buyback hook queries IGeomeanOracle.observe() on the pool's hooks address (address(0)
        // for hookless pools). Without this mock, any pay() call would revert.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Fund actors.
        vm.deal(PAYER, 200 ether);
        vm.deal(BORROWER, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Config Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Build a two-stage config: high tax → low tax. Includes LP-split hook as a reserved token split.
    function _buildTwoStageConfigWithLPSplit(
        uint16 stage1Tax,
        uint16 stage2Tax,
        uint16 splitPercent
    )
        internal
        view
        returns (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc)
    {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Splits: 50% to LP-split hook, 50% to multisig.
        JBSplit[] memory splits = new JBSplit[](2);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2),
            projectId: 0,
            beneficiary: payable(address(0)),
            lockedUntil: 0,
            hook: IJBSplitHook(address(LP_SPLIT_HOOK))
        });
        splits[1] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2),
            projectId: 0,
            beneficiary: payable(multisig()),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        REVStageConfig[] memory stages = new REVStageConfig[](2);

        // Stage 1: high tax, starts immediately.
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: splitPercent,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: stage1Tax,
            extraMetadata: 0
        });

        // Stage 2: low tax, starts after STAGE_DURATION.
        stages[1] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp + STAGE_DURATION),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: splitPercent,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: stage2Tax,
            extraMetadata: 0
        });

        cfg = REVConfig({
            description: REVDescription("Ecosystem", "ECO", "ipfs://eco", "ECO_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("ECO"))
        });
    }

    function _build721Config() internal view returns (REVDeploy721TiersHookConfig memory) {
        JB721TierConfig[] memory tiers = new JB721TierConfig[](1);
        JBSplit[] memory tierSplits = new JBSplit[](1);
        tierSplits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(SPLIT_BENEFICIARY),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        tiers[0] = JB721TierConfig({
            price: TIER_PRICE,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32("tier1"),
            category: 1,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: false,
                cantIncreaseDiscountPercent: false,
                cantBuyWithCredits: false
            }),
            splitPercent: 300_000_000, // 30% of tier payment → split beneficiary
            splits: tierSplits
        });

        return REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "Ecosystem NFT",
                symbol: "ECONFT",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: "ipfs://contract",
                tiersConfig: JB721InitTiersConfig({
                    tiers: tiers, currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18
                }),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            salt: bytes32("ECO_721"),
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Pool / Buyback Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Add liquidity to the buyback pool. Pool is already initialized and registered by REVDeployer.
    /// The buyback pool uses native ETH (address(0)), not WETH.
    function _setupBuybackPool(uint256 revnetId, uint256 liquidityTokenAmount) internal returns (PoolKey memory key) {
        address projectToken = address(jbTokens().tokenOf(revnetId));
        require(projectToken != address(0), "project token not deployed");

        // Native ETH is address(0) — always sorts before any ERC-20.
        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(projectToken),
            fee: REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(),
            tickSpacing: REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(),
            hooks: IHooks(address(0))
        });

        // Pool is already initialized and registered by REVDeployer during deployment.
        // This helper only adds liquidity to the existing pool.

        // Fund LiquidityHelper with project tokens and native ETH.
        // At high tick (~69078 for 1000 tokens/ETH), full-range liquidity needs ~32x more project tokens than ETH.
        // Mint 50x project tokens and use a smaller liquidity delta to stay within budget.
        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, liquidityTokenAmount * 50);
        vm.deal(address(liqHelper), liquidityTokenAmount);

        vm.prank(address(liqHelper));
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);

        int256 liquidityDelta = int256(liquidityTokenAmount / 50);
        vm.prank(address(liqHelper));
        liqHelper.addLiquidity{value: liquidityTokenAmount}(key, TICK_LOWER, TICK_UPPER, liquidityDelta);

        // Mock geomean oracle at tick 69078 (~1000 tokens/ETH, matching INITIAL_ISSUANCE).
        _mockOracle(liquidityDelta, 69_078, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
    }

    function _mockOracle(int256 liquidity, int24 tick, uint32 twapWindow) internal {
        vm.etch(address(0), hex"00");

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = 0;
        tickCumulatives[1] = int56(tick) * int56(int32(twapWindow));

        uint136[] memory secondsPerLiquidityCumulativeX128s = new uint136[](2);
        secondsPerLiquidityCumulativeX128s[0] = 0;
        uint256 liq = uint256(liquidity > 0 ? liquidity : -liquidity);
        if (liq == 0) liq = 1;
        secondsPerLiquidityCumulativeX128s[1] = uint136((uint256(twapWindow) << 128) / liq);

        vm.mockCall(
            address(0),
            abi.encodeWithSelector(IGeomeanOracle.observe.selector),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Payment / Metadata Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _deployFeeProject(uint16 cashOutTaxRate) internal {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0].beneficiary = payable(multisig());
        splits[0].percent = 10_000;

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 0,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: cashOutTaxRate,
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("Fee", "FEE", "ipfs://fee", "FEE_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("FEE"))
        });

        vm.prank(multisig());
        REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

    function _payRevnet(uint256 revnetId, address payer, uint256 amount) internal returns (uint256 tokensReceived) {
        vm.prank(payer);
        tokensReceived = jbMultiTerminal().pay{value: amount}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: amount,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
    }

    function _terminalBalance(uint256 projectId, address token) internal view returns (uint256) {
        return jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, token);
    }

    function _buildPayMetadataWithTier(address hookMetadataTarget) internal pure returns (bytes memory) {
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        bytes memory tierData = abi.encode(true, tierIds);
        bytes4 tierMetadataId = JBMetadataResolver.getId("pay", hookMetadataTarget);

        bytes4[] memory ids = new bytes4[](1);
        ids[0] = tierMetadataId;
        bytes[] memory datas = new bytes[](1);
        datas[0] = tierData;

        return JBMetadataResolver.createMetadata(ids, datas);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Tests
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Pre-AMM: Pay from the terminal before any pool is set up. Mint path must work.
    function test_eco_preAMM_payFromTerminal() public {
        _deployFeeProject(5000);

        // Deploy revnet with two stages (70%→20% tax), 20% reserved split.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721Config();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // No pool set up yet → payment should mint directly.
        uint256 tokens = _payRevnet(revnetId, PAYER, 1 ether);

        // With 1000 tokens/ETH issuance and 20% reserved, payer gets 80% = 800 tokens.
        assertGt(tokens, 0, "should receive tokens pre-AMM");
        assertEq(tokens, 800e18, "should receive 800 tokens (80% of 1000 after 20% reserved)");

        // Terminal should have balance.
        assertGt(_terminalBalance(revnetId, JBConstants.NATIVE_TOKEN), 0, "terminal should have balance");
    }

    /// @notice Pre-AMM: Pay with 721 tier metadata → NFT minted + 30% tier split.
    function test_eco_preAMM_payWith721TierSplit() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721Config();

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);

        vm.prank(PAYER);
        uint256 tokens = jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        // NFT should be minted to PAYER.
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should own 1 NFT");

        // 30% tier split → payer gets 70% of mint. With 20% reserved:
        // Total mint = 1000 tokens. Reserved takes 20% = 200. Remaining 800.
        // Of 800, 30% (240) goes to tier split, payer gets 70% (560).
        assertGt(tokens, 0, "should receive tokens");
        // The exact amount depends on split ordering. Just verify it's less than the no-tier case.
        assertLt(tokens, 800e18, "should be less than 800 due to tier split");
    }

    /// @notice Distribute reserved tokens → LP-split hook accumulates them.
    function test_eco_lpSplitHookAccumulates() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay to generate reserved tokens.
        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        // Check pending reserved tokens.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        assertGt(pending, 0, "should have pending reserved tokens");

        // Distribute reserved tokens.
        jbController().sendReservedTokensToSplitsOf(revnetId);

        // LP-split hook should have accumulated tokens (50% of reserved).
        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);
        assertGt(accumulated, 0, "LP split hook should have accumulated tokens");

        // Multisig should also have received the other 50%.
        uint256 multisigTokens = jbTokens().totalBalanceOf(multisig(), revnetId);
        assertGt(multisigTokens, 0, "multisig should receive reserved tokens");
    }

    /// @notice Post-AMM: Pay from terminal after pool is set up → buyback hook compares swap vs mint.
    function test_eco_postAMM_payFromTerminal() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Set up buyback pool with real liquidity.
        _setupBuybackPool(revnetId, 10_000 ether);

        // Pay some surplus so bonding curve has visible effect.
        _payRevnet(revnetId, BORROWER, 5 ether);

        // Pay again — buyback hook is now active.
        uint256 tokens = _payRevnet(revnetId, PAYER, 1 ether);

        // Should receive tokens (either via mint or swap, whichever wins).
        assertGt(tokens, 0, "should receive tokens post-AMM");

        // Terminal balance should increase.
        assertGt(_terminalBalance(revnetId, JBConstants.NATIVE_TOKEN), 0, "terminal balance should increase");
    }

    /// @notice Post-AMM: Pay with 721 tier metadata while buyback hook is active.
    function test_eco_postAMM_payWith721TierSplitAndBuyback() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721Config();

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // Set up buyback pool.
        _setupBuybackPool(revnetId, 10_000 ether);

        // Another payer so bonding curve tax matters.
        _payRevnet(revnetId, BORROWER, 5 ether);

        // Pay with 721 tier metadata.
        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);

        vm.prank(PAYER);
        uint256 tokens = jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        // Payer gets NFT.
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should own 1 NFT");

        // Payer gets tokens (via swap or mint, whichever the buyback hook chose).
        assertGt(tokens, 0, "should receive tokens with 721 tier + buyback");

        // Note: when the buyback hook swaps (pool gives better price than mint), tier splits
        // aren't applied because no new tokens are minted. The split beneficiary only receives
        // tokens when the mint path is taken.
    }

    /// @notice Warp to stage 2, verify new cashOutTaxRate applies and buyback hook still works.
    function test_eco_crossStageWithBuyback() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupBuybackPool(revnetId, 10_000 ether);

        // Pay in stage 1 (70% tax).
        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);

        // Record borrowable in stage 1.
        uint256 borrowableStage1 =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN)));

        // Warp to stage 2 (20% tax).
        vm.warp(block.timestamp + STAGE_DURATION + 1);

        // Borrowable should increase with lower tax.
        uint256 borrowableStage2 =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN)));
        assertGt(borrowableStage2, borrowableStage1, "borrowable should increase in stage 2");

        // Payment in stage 2 should still work with buyback hook.
        address payer2 = makeAddr("payer2");
        vm.deal(payer2, 10 ether);
        uint256 tokens = _payRevnet(revnetId, payer2, 1 ether);
        assertGt(tokens, 0, "payment should work in stage 2 with buyback");
    }

    /// @notice Pay via the Uniswap V4 router hook (JBUniswapV4Hook) — routes to best path.
    function test_eco_payViaRouter() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Set up buyback pool.
        _setupBuybackPool(revnetId, 10_000 ether);

        // Pay some surplus.
        _payRevnet(revnetId, BORROWER, 5 ether);

        // Deploy the V4 router hook at a valid hook address.
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(poolManager, jbTokens(), jbDirectory(), jbPrices());

        (, bytes32 salt) = HookMiner.find(address(this), flags, type(JBUniswapV4Hook).creationCode, constructorArgs);

        JBUniswapV4Hook routerHook = new JBUniswapV4Hook{salt: salt}(poolManager, jbTokens(), jbDirectory(), jbPrices());

        // Create a V4 pool with the router hook.
        address projectToken = address(jbTokens().tokenOf(revnetId));
        address token0 = projectToken < WETH_ADDR ? projectToken : WETH_ADDR;
        address token1 = projectToken < WETH_ADDR ? WETH_ADDR : projectToken;

        PoolKey memory routerKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(routerHook))
        });

        uint160 sqrtPrice = TickMath.getSqrtPriceAtTick(0);
        poolManager.initialize(routerKey, sqrtPrice);

        // Add liquidity to the router pool.
        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, 1000 ether);
        vm.deal(address(liqHelper), 1000 ether);
        vm.prank(address(liqHelper));
        weth.deposit{value: 1000 ether}();

        vm.startPrank(address(liqHelper));
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);
        IERC20(WETH_ADDR).approve(address(poolManager), type(uint256).max);
        vm.stopPrank();

        vm.prank(address(liqHelper));
        liqHelper.addLiquidity(routerKey, -60, 60, 100 ether);

        // Deploy JuiceboxSwapRouter utility.
        JuiceboxSwapRouter jbSwapRouter = new JuiceboxSwapRouter(poolManager);

        // PAYER swaps WETH → project token via the router.
        vm.prank(PAYER);
        weth.deposit{value: 1 ether}();

        vm.startPrank(PAYER);
        IERC20(WETH_ADDR).approve(address(jbSwapRouter), 1 ether);

        bool wethIs0 = WETH_ADDR < projectToken;
        SwapParams memory params = SwapParams({
            zeroForOne: wethIs0,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: wethIs0 ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        jbSwapRouter.swap(routerKey, params, 0);
        vm.stopPrank();

        // PAYER should have received project tokens.
        uint256 payerTokens = IERC20(projectToken).balanceOf(PAYER);
        assertGt(payerTokens, 0, "payer should receive project tokens via router");
    }

    /// @notice Full lifecycle: deploy → pre-AMM pay → distribute reserved → set up pool → post-AMM pay →
    /// cashout.
    function test_eco_fullLifecycle() public {
        _deployFeeProject(5000);

        // 1. Deploy revnet with 721 + LP-split.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721Config();

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // 2. Pre-AMM payment (mint path only, no pool).
        uint256 tokensPreAMM = _payRevnet(revnetId, PAYER, 5 ether);
        assertGt(tokensPreAMM, 0, "pre-AMM payment should mint tokens");

        // Another payer for bonding curve effects.
        _payRevnet(revnetId, BORROWER, 5 ether);

        // 3. Distribute reserved tokens → LP-split hook accumulates.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        if (pending > 0) {
            jbController().sendReservedTokensToSplitsOf(revnetId);
        }
        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);
        assertGt(accumulated, 0, "LP split hook should accumulate from reserved distribution");

        // 4. Set up buyback pool (separate from LP-split hook's pool).
        _setupBuybackPool(revnetId, 10_000 ether);

        // 5. Post-AMM payment with 721 tier.
        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);

        vm.prank(PAYER);
        uint256 tokensPostAMM = jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });
        assertGt(tokensPostAMM, 0, "post-AMM payment should return tokens");
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "should own NFT from post-AMM payment");

        // 6. Cash out some tokens.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 cashOutCount = payerTokens / 2;
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
                holder: PAYER,
                projectId: revnetId,
                cashOutCount: cashOutCount,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(PAYER),
                metadata: ""
            });

        assertGt(PAYER.balance, payerEthBefore, "should receive ETH from cashout");
        assertEq(
            jbTokens().totalBalanceOf(PAYER, revnetId), payerTokens - cashOutCount, "remaining tokens should be correct"
        );
    }
}
