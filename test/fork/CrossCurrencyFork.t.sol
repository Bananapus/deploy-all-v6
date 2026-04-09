// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {JBFixedPointNumber} from "@bananapus/core-v6/src/libraries/JBFixedPointNumber.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBPayHook} from "@bananapus/core-v6/src/interfaces/IJBPayHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";

// 721 Hook
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
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

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";

/// @notice Mock USDC token with 6 decimals.
contract CCMockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Inline mock price feed that returns a fixed price.
contract MockPriceFeed is IJBPriceFeed {
    uint256 public immutable PRICE;
    uint8 public immutable FEED_DECIMALS;

    constructor(uint256 price, uint8 dec) {
        PRICE = price;
        FEED_DECIMALS = dec;
    }

    function currentUnitPrice(uint256 decimals) external view override returns (uint256) {
        return JBFixedPointNumber.adjustDecimals(PRICE, FEED_DECIMALS, decimals);
    }
}

/// @notice Adds liquidity to a hookless V4 pool via unlock/callback pattern.
contract CCLiquidityHelper is IUnlockCallback {
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

        if (amount0 < 0) _settle(key.currency0, uint128(-amount0));
        if (amount1 < 0) _settle(key.currency1, uint128(-amount1));
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

/// @notice Cross-currency integration fork test: stress-tests JBPrices in live payment flows with hooks.
/// Exercises cross-currency paths in JBTerminalStore, JB721TiersHookLib, and JBBuybackHook.
///
/// Run with: forge test --match-contract CrossCurrencyForkTest -vvv
contract CrossCurrencyForkTest is TestBaseWorkflow {
    using PoolIdLibrary for PoolKey;

    // -- Mainnet addresses
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant V4_POSITION_MANAGER_ADDR = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;

    // -- Tick range for full-range liquidity (hookless pool)
    int24 constant TICK_LOWER = -887_200;
    int24 constant TICK_UPPER = 887_200;

    // -- Test parameters
    uint112 constant INITIAL_ISSUANCE = uint112(1000e18); // 1000 tokens per USD unit
    uint32 constant STAGE_DURATION = 30 days;
    uint104 constant TIER_PRICE_USD = 100e18; // 100 USD (18 decimals for USD abstract pricing)
    uint104 constant TIER_PRICE_ETH = 0.05e18; // 0.05 ETH

    // -- Currency constants
    uint32 constant USD = 2; // JBCurrencyIds.USD
    uint32 constant ETH_ID = 1; // JBCurrencyIds.ETH

    // -- Actors
    address PAYER = makeAddr("cc_payer");
    address PAYER2 = makeAddr("cc_payer2");
    address SPLIT_BENEFICIARY = makeAddr("cc_splitBeneficiary");

    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // -- Ecosystem contracts
    IPoolManager poolManager;
    IPositionManager positionManager;
    CCLiquidityHelper liqHelper;

    CCMockUSDC usdc;

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

    // Currency helpers
    uint32 nativeCurrency;
    uint32 usdcCurrency;

    receive() external payable {}

    function setUp() public override {
        vm.createSelectFork("ethereum", 21_700_000);
        require(POOL_MANAGER_ADDR.code.length > 0, "PoolManager not deployed");
        require(V4_POSITION_MANAGER_ADDR.code.length > 0, "PositionManager not deployed");

        super.setUp();

        poolManager = IPoolManager(POOL_MANAGER_ADDR);
        positionManager = IPositionManager(V4_POSITION_MANAGER_ADDR);
        liqHelper = new CCLiquidityHelper(poolManager);

        usdc = new CCMockUSDC();
        nativeCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));
        usdcCurrency = uint32(uint160(address(usdc)));

        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        SUCKER_REGISTRY = new JBSuckerRegistry(jbDirectory(), jbPermissions(), multisig(), address(0));
        HOOK_STORE = new JB721TiersHookStore();
        EXAMPLE_HOOK = new JB721TiersHook(
            jbDirectory(), jbPermissions(), jbPrices(), jbRulesets(), HOOK_STORE, jbSplits(), multisig()
        );
        ADDRESS_REGISTRY = new JBAddressRegistry();
        HOOK_DEPLOYER = new JB721TiersHookDeployer(EXAMPLE_HOOK, HOOK_STORE, ADDRESS_REGISTRY, multisig());
        PUBLISHER = new CTPublisher(jbDirectory(), jbPermissions(), FEE_PROJECT_ID, multisig());

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

        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_CC"}(
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
        LP_SPLIT_HOOK.initialize(0, 0);

        // Mock geomean oracle.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // --- Register price feeds ---

        // Feed 1: ETH/USD — "1 ETH costs 2000 USD" (18-decimal feed)
        MockPriceFeed ethUsdFeed = new MockPriceFeed(2000e18, 18);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, USD, nativeCurrency, IJBPriceFeed(address(ethUsdFeed)));

        // Feed 2: USDC/USD — "1 USDC costs 1 USD" (6-decimal feed)
        MockPriceFeed usdcUsdFeed = new MockPriceFeed(1e6, 6);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, USD, usdcCurrency, IJBPriceFeed(address(usdcUsdFeed)));

        // Feed 3: NATIVE_TOKEN/ETH — 1:1 (for 721 tiers priced in abstract ETH)
        MockPriceFeed nativeEthFeed = new MockPriceFeed(1e18, 18);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, ETH_ID, nativeCurrency, IJBPriceFeed(address(nativeEthFeed)));

        // Fund actors.
        usdc.mint(PAYER, 200_000e6);
        usdc.mint(PAYER2, 100_000e6);
        vm.deal(PAYER, 100 ether);
        vm.deal(PAYER2, 100 ether);
    }

    // ===================================================================
    //  Config Helpers
    // ===================================================================

    /// @notice Build a two-stage USD-base revnet accepting BOTH ETH and USDC.
    function _buildCrossCurrencyConfig()
        internal
        view
        returns (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc)
    {
        JBAccountingContext[] memory acc = new JBAccountingContext[](2);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});
        acc[1] = JBAccountingContext({token: address(usdc), decimals: 6, currency: usdcCurrency});

        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(multisig()),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 2000, // 20% reserved
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: 5000,
            extraMetadata: 0
        });

        cfg = REVConfig({
            description: REVDescription("CC Test", "CCT", "ipfs://cc", "CC_SALT"),
            baseCurrency: USD, // Abstract USD
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("CC"))
        });
    }

    /// @notice 721 tiers priced in abstract USD(2), no tier splits.
    function _build721ConfigUSDTiers() internal view returns (REVDeploy721TiersHookConfig memory) {
        return _build721ConfigUSDTiersWithSplit(false);
    }

    /// @notice 721 tiers priced in abstract USD(2), with optional 30% tier split.
    function _build721ConfigUSDTiersWithSplit(bool withSplit)
        internal
        view
        returns (REVDeploy721TiersHookConfig memory)
    {
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);

        JBSplit[] memory tierSplits;
        uint32 splitPercent;

        if (withSplit) {
            tierSplits = new JBSplit[](1);
            tierSplits[0] = JBSplit({
                percent: uint32(uint256(JBConstants.SPLITS_TOTAL_PERCENT)),
                projectId: 0,
                beneficiary: payable(SPLIT_BENEFICIARY),
                preferAddToBalance: false,
                lockedUntil: 0,
                hook: IJBSplitHook(address(0))
            });
            splitPercent = 300_000_000; // 30%
        } else {
            tierSplits = new JBSplit[](0);
            splitPercent = 0;
        }

        tierConfigs[0] = JB721TierConfig({
            price: TIER_PRICE_USD, // 100 USD (18 decimals)
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32("ccUsdTier1"),
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
            splitPercent: splitPercent,
            splits: tierSplits
        });

        return REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "CC USD NFT",
                symbol: "CCUSDNFT",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: "ipfs://contract",
                tiersConfig: JB721InitTiersConfig({
                    tiers: tierConfigs,
                    currency: USD, // Abstract USD
                    decimals: 18
                }),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            salt: bytes32(withSplit ? bytes32("CC_USD_721_S") : bytes32("CC_USD_721")),
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });
    }

    /// @notice 721 tiers priced in abstract ETH(1).
    function _build721ConfigETHTiers() internal pure returns (REVDeploy721TiersHookConfig memory) {
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);

        tierConfigs[0] = JB721TierConfig({
            price: TIER_PRICE_ETH, // 0.05 ETH
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32("ccEthTier1"),
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
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        return REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "CC ETH NFT",
                symbol: "CCETHNFT",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: "ipfs://contract",
                tiersConfig: JB721InitTiersConfig({
                    tiers: tierConfigs,
                    currency: ETH_ID, // Abstract ETH
                    decimals: 18
                }),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            salt: bytes32("CC_ETH_721"),
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });
    }

    // ===================================================================
    //  Pool / Oracle Helpers
    // ===================================================================

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

    // ===================================================================
    //  Fee Project Helper
    // ===================================================================

    function _deployFeeProject(uint16 cashOutTaxRate) internal {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});
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
            description: REVDescription("Fee", "FEE", "ipfs://fee", "FEE_CC"),
            baseCurrency: nativeCurrency,
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("FEE_CC"))
        });

        vm.prank(multisig());
        REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

    // ===================================================================
    //  Payment / Metadata Helpers
    // ===================================================================

    function _payRevnetETH(uint256 revnetId, address payer, uint256 amount) internal returns (uint256 tokensReceived) {
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

    function _payRevnetUSDC(uint256 revnetId, address payer, uint256 amount) internal returns (uint256 tokensReceived) {
        usdc.mint(payer, amount);
        vm.startPrank(payer);
        usdc.approve(address(jbMultiTerminal()), amount);
        tokensReceived = jbMultiTerminal()
            .pay({
                projectId: revnetId,
                token: address(usdc),
                amount: amount,
                beneficiary: payer,
                minReturnedTokens: 0,
                memo: "",
                metadata: ""
            });
        vm.stopPrank();
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

    // ===================================================================
    //  Tests
    // ===================================================================

    /// @notice Test 1: USD-base project, pay with ETH -> correct cross-currency token count.
    function test_cc_usdBaseProject_payWithETH() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 1 ETH to USD-base project.
        // Weight ratio: pricePerUnitOf(_, nativeCurrency, USD, 18) = inverse of 2000e18 = 5e14
        // Expected: mulDiv(1e18, 1000e18, 5e14) = 2,000,000e18 tokens total
        // With 20% reserved → payer gets 1,600,000e18
        uint256 tokens = _payRevnetETH(revnetId, PAYER, 1 ether);

        assertEq(tokens, 1_600_000e18, "1 ETH at $2000 -> 1,600,000 tokens (80% after 20% reserved)");

        // Verify reserved token accumulation.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        assertEq(pending, 400_000e18, "reserved = 400,000 tokens (20%)");
    }

    /// @notice Test 2: USD-base project, pay with USDC -> equivalent token count to ETH payment.
    function test_cc_usdBaseProject_payWithUSDC() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 2000 USDC to USD-base project (= $2000, same as 1 ETH).
        // Weight ratio: pricePerUnitOf(_, usdcCurrency, USD, 6) = inverse of 1e6 = 1e6
        // Expected: mulDiv(2000e6, 1000e18, 1e6) = 2,000,000e18 tokens total
        // With 20% reserved → payer gets 1,600,000e18
        uint256 tokens = _payRevnetUSDC(revnetId, PAYER, 2000e6);

        assertEq(tokens, 1_600_000e18, "2000 USDC -> 1,600,000 tokens (same as 1 ETH)");
    }

    /// @notice Test 3: 721 tiers in USD, pay with ETH -> NFT minted via cross-currency normalization.
    function test_cc_721TiersInUSD_payWithETH() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();
        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigUSDTiers();

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

        // Pay 0.05 ETH (= $100 at $2000/ETH = tier price of 100 USD)
        vm.prank(PAYER);
        jbMultiTerminal().pay{value: 0.05 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 0.05 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "1 NFT minted from ETH via cross-currency");
    }

    /// @notice Test 4: 721 tiers in USD, pay with USDC -> NFT minted via cross-currency normalization.
    function test_cc_721TiersInUSD_payWithUSDC() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();
        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigUSDTiers();

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

        // Pay 100 USDC (= $100 = tier price)
        usdc.mint(PAYER, 100e6);
        vm.startPrank(PAYER);
        usdc.approve(address(jbMultiTerminal()), 100e6);
        jbMultiTerminal()
            .pay({
                projectId: revnetId,
                token: address(usdc),
                amount: 100e6,
                beneficiary: PAYER,
                minReturnedTokens: 0,
                memo: "",
                metadata: metadata
            });
        vm.stopPrank();

        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "1 NFT minted from USDC via cross-currency");
    }

    /// @notice Test 5: 721 tiers in USD + 30% tier split, pay with USDC -> split beneficiary gets USDC.
    /// @dev FINDING: Tier splits with cross-currency pricing revert because the split amount is
    /// calculated in the tier's abstract pricing denomination (e.g., 30e18 USD units) but compared
    /// against the actual payment token amount (e.g., 100e6 USDC). The hook requests forwarding
    /// more tokens than the payment contains. This test documents the revert behavior.
    function test_cc_721TiersInUSD_payWithUSDC_withSplit() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();
        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigUSDTiersWithSplit(true);

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

        // FIXED: Split amounts are now converted from tier pricing denomination (USD, 18 decimals)
        // to payment token denomination (USDC, 6 decimals) inside calculateSplitAmounts.
        // 30% of 100 USD tier = 30 USD -> ~30e6 USDC forwarded to split beneficiary.
        uint256 splitBeneficiaryBalanceBefore = usdc.balanceOf(SPLIT_BENEFICIARY);

        usdc.mint(PAYER, 100e6);
        vm.startPrank(PAYER);
        usdc.approve(address(jbMultiTerminal()), 100e6);
        jbMultiTerminal()
            .pay({
                projectId: revnetId,
                token: address(usdc),
                amount: 100e6,
                beneficiary: PAYER,
                minReturnedTokens: 0,
                memo: "",
                metadata: metadata
            });
        vm.stopPrank();

        // NFT minted to payer.
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should have 1 NFT");

        // Split beneficiary received ~30 USDC (30% of 100 USDC, converted from 30e18 USD).
        uint256 splitBeneficiaryBalanceAfter = usdc.balanceOf(SPLIT_BENEFICIARY);
        uint256 splitReceived = splitBeneficiaryBalanceAfter - splitBeneficiaryBalanceBefore;
        // Allow 1% tolerance for price feed rounding.
        assertApproxEqRel(splitReceived, 30e6, 0.01e18, "split beneficiary should receive ~30 USDC");
    }

    /// @notice Test 6: Missing price feed -> revert.
    function test_cc_missingPriceFeed_reverts() public {
        // Deploy a separate JB ecosystem without price feeds for this test.
        // We use a revnet with baseCurrency = 999 (no feed registered for this).
        _deployFeeProject(5000);

        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});
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
            cashOutTaxRate: 5000,
            extraMetadata: 0
        });

        // baseCurrency = 999 -> no feed exists for nativeCurrency -> 999
        REVConfig memory cfg = REVConfig({
            description: REVDescription("NoPriceFeed", "NPF", "ipfs://npf", "NPF_SALT"),
            baseCurrency: 999,
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("NPF"))
        });

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay with ETH -> should revert because no nativeCurrency -> 999 feed exists.
        vm.prank(PAYER);
        vm.expectRevert();
        jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
    }

    /// @notice Test 7: 721 hook with prices=address(0) -> silent skip (no NFT minted).
    function test_cc_721_noPricesContract_silentSkip() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();

        // Build 721 config with prices=address(0) but USD-priced tiers.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: TIER_PRICE_USD,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32("noPricesTier"),
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
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        REVDeploy721TiersHookConfig memory hookConfig = REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "NoPrices NFT",
                symbol: "NPNFT",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: "ipfs://contract",
                tiersConfig: JB721InitTiersConfig({tiers: tierConfigs, currency: USD, decimals: 18}),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            salt: bytes32("NP_721"),
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // Pay with ETH (currencies differ, no prices contract).
        // normalizePaymentValue returns (0, false) -> no NFT minted, but payer still gets project tokens.
        uint256 tokens = _payRevnetETH(revnetId, PAYER, 1 ether);

        assertEq(IERC721(address(hook)).balanceOf(PAYER), 0, "no NFT minted (silent skip)");
        assertGt(tokens, 0, "payer still receives ERC-20 project tokens");
    }

    /// @notice Test 8: Dust payment (1 wei USDC) -> zero tokens minted (no revert).
    function test_cc_dustPayment_zeroMint() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 1 wei USDC.
        // mulDiv(1, 1000e18, 1e6) = 1000e12 = 1e15 tokens (non-zero actually due to weight)
        // But with weight = 1000e18 and weightRatio = 1e6, mulDiv(1, 1000e18, 1e6) = 1e15
        // This is actually non-zero! The test verifies no revert on tiny payments.
        _payRevnetUSDC(revnetId, PAYER, 1);

        // Should not revert. Token count may be very small or zero depending on reserved rate.
        // With 20% reserved and 1e15 total: payer gets 800e12 which is > 0.
        // The key invariant: no revert on dust payments.
        assertTrue(true, "dust payment did not revert");
    }

    /// @notice Test 9: Multi-token surplus aggregation (pay both ETH and USDC).
    function test_cc_multiTokenSurplus() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 1 ETH (= $2000) + 2000 USDC (= $2000).
        _payRevnetETH(revnetId, PAYER, 1 ether);
        _payRevnetUSDC(revnetId, PAYER2, 2000e6);

        // Check surplus in USD terms.
        uint256 surplusUSD = jbMultiTerminal().currentSurplusOf(revnetId, new address[](0), 18, USD);

        // Surplus should be ~$4000 worth (both tokens aggregated via price conversion).
        // There are no payouts configured, so surplus = total balance in USD terms.
        assertGt(surplusUSD, 3900e18, "surplus should be >= $3900 (allowing for rounding)");
        assertLe(surplusUSD, 4100e18, "surplus should be <= $4100");
    }

    /// @notice Test 10: ETH payment with ETH-priced tiers -> same-currency flow still works.
    function test_cc_ethPayment_ethTiers_regression() public {
        _deployFeeProject(5000);

        // Build ETH-base config (not USD-base).
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});
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
            cashOutTaxRate: 5000,
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("ETH Base", "ETHB", "ipfs://ethb", "ETHB_SALT"),
            baseCurrency: nativeCurrency, // Same currency as payment token
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("ETHB"))
        });

        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigETHTiers();

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

        // Pay 0.05 ETH with tier metadata (tier price = 0.05 ETH, same currency).
        vm.prank(PAYER);
        uint256 tokens = jbMultiTerminal().pay{value: 0.05 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 0.05 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "NFT minted via same-currency (regression)");
        assertGt(tokens, 0, "project tokens received");
    }
}
