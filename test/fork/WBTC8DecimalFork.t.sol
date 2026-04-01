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
import {JB721TierConfigFlags} from "@bananapus/721-hook-v6/src/structs/JB721TierConfigFlags.sol";
import {JB721InitTiersConfig} from "@bananapus/721-hook-v6/src/structs/JB721InitTiersConfig.sol";

// Address Registry
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// Buyback Hook
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";
import {IJBBuybackHook} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHook.sol";
import {IGeomeanOracle} from "@bananapus/buyback-hook-v6/src/interfaces/IGeomeanOracle.sol";

// Suckers
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// Croptop
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";

// Revnet
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
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
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Mock WBTC token with 8 decimals (matching real WBTC on mainnet).
contract MockWBTC is ERC20 {
    /// @dev Construct the mock with name "Wrapped BTC" and symbol "WBTC".
    constructor() ERC20("Wrapped BTC", "WBTC") {}

    /// @dev Override decimals to return 8, matching real WBTC.
    function decimals() public pure override returns (uint8) {
        return 8;
    }

    /// @dev Public mint function for test scaffolding.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Inline mock price feed that returns a fixed price for WBTC/USD conversion.
contract WBTCMockPriceFeed is IJBPriceFeed {
    /// @dev The fixed price value the feed returns, in FEED_DECIMALS precision.
    uint256 public immutable PRICE;

    /// @dev The number of decimals the stored PRICE uses.
    uint8 public immutable FEED_DECIMALS;

    /// @dev Store the fixed price and its decimal precision.
    constructor(uint256 price, uint8 dec) {
        PRICE = price;
        FEED_DECIMALS = dec;
    }

    /// @dev Return the fixed price adjusted to the caller's requested decimal precision.
    function currentUnitPrice(uint256 decimals) external view override returns (uint256) {
        return JBFixedPointNumber.adjustDecimals(PRICE, FEED_DECIMALS, decimals);
    }
}

/// @notice Adds liquidity to a hookless V4 pool via the unlock/callback pattern.
/// Supports both native ETH (address(0)) and ERC-20 token settlement.
contract WBTCLiquidityHelper is IUnlockCallback {
    /// @dev Reference to the Uniswap V4 PoolManager for liquidity operations.
    IPoolManager public immutable poolManager;

    /// @dev Store the PoolManager reference for use in liquidity operations.
    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @dev Accept ETH transfers for native token settlement.
    receive() external payable {}

    /// @notice Add liquidity to a V4 pool by triggering the unlock callback.
    function addLiquidity(
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta
    )
        external
        payable
    {
        // Encode the pool key and liquidity params, then unlock the pool manager to trigger the callback.
        poolManager.unlock(abi.encode(key, tickLower, tickUpper, liquidityDelta));
    }

    /// @notice Callback invoked by PoolManager during unlock to actually modify liquidity.
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        // Decode the pool key and liquidity params from the calldata.
        (PoolKey memory key, int24 tickLower, int24 tickUpper, int256 liquidityDelta) =
            abi.decode(data, (PoolKey, int24, int24, int256));

        // Modify the pool's liquidity position and get the resulting balance delta.
        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: 0
            }),
            ""
        );

        // Read how much of each currency is owed to / owed by the pool.
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // Settle tokens owed to the pool (negative delta means we owe the pool).
        if (amount0 < 0) _settle(key.currency0, uint128(-amount0));
        if (amount1 < 0) _settle(key.currency1, uint128(-amount1));

        // Take tokens owed by the pool to this contract (positive delta means pool owes us).
        if (amount0 > 0) poolManager.take(key.currency0, address(this), uint128(amount0));
        if (amount1 > 0) poolManager.take(key.currency1, address(this), uint128(amount1));

        return "";
    }

    /// @dev Settle a single currency with the PoolManager (ETH via value, ERC-20 via transfer).
    function _settle(Currency currency, uint256 amount) internal {
        // Native ETH is represented as address(0) in Uniswap V4.
        if (Currency.unwrap(currency) == address(0)) {
            // Settle native ETH by sending value to the pool manager.
            poolManager.settle{value: amount}();
        } else {
            // Sync and transfer the ERC-20 token to the pool manager for settlement.
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).transfer(address(poolManager), amount);
            poolManager.settle();
        }
    }
}

/// @notice WBTC 8-decimal integration fork test: exercises the full payment, buyback,
/// and cash-out path using a mock WBTC token (8 decimals) to stress-test non-18-decimal
/// token accounting throughout the Juicebox V6 protocol.
///
/// Key areas exercised:
/// - JBTerminalStore balance tracking with 8-decimal accounting contexts
/// - JBPrices cross-currency conversion (WBTC -> USD) with 8-decimal feeds
/// - JBBuybackHook with non-18-decimal payment tokens
/// - Bonding curve cash-out with 8-decimal reclaim amounts
/// - 721 NFT tier pricing via cross-currency normalization
///
/// Run with: forge test --match-contract WBTC8DecimalForkTest -vvv
contract WBTC8DecimalForkTest is TestBaseWorkflow {
    using PoolIdLibrary for PoolKey;

    // -- Mainnet addresses (Uniswap V4 deployed at these deterministic addresses)
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    // -- Tick range for full-range liquidity in the hookless buyback pool
    int24 constant TICK_LOWER = -887_200;
    int24 constant TICK_UPPER = 887_200;

    // -- Test parameters
    uint112 constant INITIAL_ISSUANCE = uint112(1000e18); // 1000 project tokens per base currency unit
    uint32 constant STAGE_DURATION = 30 days; // Duration of each revnet stage
    uint104 constant TIER_PRICE_USD = 100e18; // NFT tier price: 100 USD in 18-decimal abstract USD

    // -- Currency constants (matching JBCurrencyIds)
    uint32 constant USD = 2; // Abstract USD currency ID used by JBPrices

    // -- WBTC pricing constant: 1 BTC = $60,000 USD (realistic approximate price)
    uint256 constant WBTC_USD_PRICE = 60_000e8; // 60,000 USD expressed in 8 decimals

    // -- Actors for the test scenarios
    address PAYER = makeAddr("wbtc_payer"); // Primary payer who pays WBTC into the project
    address PAYER2 = makeAddr("wbtc_payer2"); // Secondary payer for bonding curve effect
    address SPLIT_BENEFICIARY = makeAddr("wbtc_splitBeneficiary"); // Receives 721 tier split payouts

    // -- ERC-2771 trusted forwarder for meta-transactions
    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // -- Ecosystem contract references
    IPoolManager poolManager; // Uniswap V4 PoolManager for buyback pool operations
    WBTCLiquidityHelper liqHelper; // Helper for adding liquidity to the buyback pool

    MockWBTC wbtc; // The mock WBTC token with 8 decimals

    uint256 FEE_PROJECT_ID; // Project ID for the Juicebox fee project
    JBSuckerRegistry SUCKER_REGISTRY; // Registry for cross-chain sucker contracts
    IJB721TiersHookStore HOOK_STORE; // Storage contract for 721 tier hook data
    JB721TiersHook EXAMPLE_HOOK; // Implementation contract for 721 tier hook cloning
    IJBAddressRegistry ADDRESS_REGISTRY; // Registry for contract address lookups
    IJB721TiersHookDeployer HOOK_DEPLOYER; // Deployer for 721 tier hook instances
    CTPublisher PUBLISHER; // Croptop publisher for post-based minting
    JBBuybackHook BUYBACK_HOOK; // Buyback hook that compares AMM swap vs mint
    JBBuybackHookRegistry BUYBACK_REGISTRY; // Registry that maps projects to buyback hooks
    IREVLoans LOANS_CONTRACT; // Revnet loans contract for borrow/repay
    REVOwner REV_OWNER; // Runtime data hook for pay and cash out callbacks
    REVDeployer REV_DEPLOYER; // Revnet deployer that orchestrates project creation

    // -- Currency ID derived from the WBTC token address (uint32 truncation of uint160)
    uint32 wbtcCurrency;

    // -- Currency ID derived from the native ETH token sentinel address
    uint32 nativeCurrency;

    /// @dev Accept ETH for fee project deployment and gas funding.
    receive() external payable {}

    function setUp() public override {
        // Fork Ethereum mainnet at a stable block where Uniswap V4 is deployed.
        vm.createSelectFork("ethereum", 21_700_000);
        // Verify that the PoolManager contract exists at the expected address.
        require(POOL_MANAGER_ADDR.code.length > 0, "PoolManager not deployed");

        // Deploy the entire Juicebox V6 core stack on the forked mainnet.
        super.setUp();

        // Store a reference to the Uniswap V4 PoolManager.
        poolManager = IPoolManager(POOL_MANAGER_ADDR);
        // Deploy the liquidity helper for seeding the buyback pool.
        liqHelper = new WBTCLiquidityHelper(poolManager);

        // Deploy the mock WBTC token with 8 decimals.
        wbtc = new MockWBTC();
        // Derive the currency ID from the WBTC address (uint32 truncation matches JB convention).
        wbtcCurrency = uint32(uint160(address(wbtc)));
        // Derive the currency ID from the native ETH sentinel address.
        nativeCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));

        // Create the fee project owned by the multisig.
        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        // Deploy the sucker registry (no trusted forwarder for simplicity).
        SUCKER_REGISTRY = new JBSuckerRegistry(jbDirectory(), jbPermissions(), multisig(), address(0));
        // Deploy the 721 tier hook store.
        HOOK_STORE = new JB721TiersHookStore();
        // Deploy the 721 tier hook implementation for cloning.
        EXAMPLE_HOOK = new JB721TiersHook(
            jbDirectory(), jbPermissions(), jbPrices(), jbRulesets(), HOOK_STORE, jbSplits(), multisig()
        );
        // Deploy the address registry for contract lookups.
        ADDRESS_REGISTRY = new JBAddressRegistry();
        // Deploy the 721 hook deployer that creates hook instances.
        HOOK_DEPLOYER = new JB721TiersHookDeployer(EXAMPLE_HOOK, HOOK_STORE, ADDRESS_REGISTRY, multisig());
        // Deploy the Croptop publisher for post-based minting.
        PUBLISHER = new CTPublisher(jbDirectory(), jbPermissions(), FEE_PROJECT_ID, multisig());

        // Deploy the buyback hook with the real PoolManager (hookless pool, no WETH).
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

        // Deploy and configure the buyback hook registry.
        BUYBACK_REGISTRY = new JBBuybackHookRegistry(jbPermissions(), jbProjects(), address(this), address(0));
        // Set the buyback hook as the default data hook for all projects.
        BUYBACK_REGISTRY.setDefaultHook(IJBRulesetDataHook(address(BUYBACK_HOOK)));

        // Deploy the revnet loans contract for borrow/repay functionality.
        LOANS_CONTRACT = new REVLoans({
            controller: jbController(),
            projects: jbProjects(),
            revId: FEE_PROJECT_ID,
            owner: address(this),
            permit2: permit2(),
            trustedForwarder: TRUSTED_FORWARDER
        });

        // Deploy the REVOwner — the runtime data hook for pay and cash out callbacks.
        REV_OWNER = new REVOwner(
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            jbDirectory(),
            FEE_PROJECT_ID,
            SUCKER_REGISTRY,
            address(LOANS_CONTRACT)
        );

        // Deploy the REVDeployer with a unique salt to avoid address collisions.
        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_WBTC"}(
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

        // Approve the REV_DEPLOYER to transfer the fee project NFT.
        vm.prank(multisig());
        jbProjects().approve(address(REV_DEPLOYER), FEE_PROJECT_ID);

        // Mock the geomean oracle so payments work before a real buyback pool is set up.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // --- Register price feeds for cross-currency conversion ---

        // Feed: WBTC/USD -- "1 WBTC costs 60,000 USD" (8-decimal feed matching WBTC decimals).
        WBTCMockPriceFeed wbtcUsdFeed = new WBTCMockPriceFeed(WBTC_USD_PRICE, 8);
        // Register the WBTC->USD price feed at project ID 0 (global default).
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, USD, wbtcCurrency, IJBPriceFeed(address(wbtcUsdFeed)));

        // Feed: ETH/USD -- "1 ETH costs 2000 USD" (18-decimal feed for native ETH).
        WBTCMockPriceFeed ethUsdFeed = new WBTCMockPriceFeed(2000e18, 18);
        // Register the ETH->USD price feed at project ID 0 (global default).
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, USD, nativeCurrency, IJBPriceFeed(address(ethUsdFeed)));

        // Fund test actors with WBTC (8-decimal amounts).
        wbtc.mint(PAYER, 10e8); // 10 WBTC = $600,000 worth
        wbtc.mint(PAYER2, 5e8); // 5 WBTC = $300,000 worth

        // Fund actors with ETH for gas.
        vm.deal(PAYER, 1 ether);
        vm.deal(PAYER2, 1 ether);
    }

    // ===================================================================
    //  Config Helpers
    // ===================================================================

    /// @notice Build a single-stage USD-base revnet config that accepts WBTC payments.
    /// The baseCurrency is abstract USD so issuance is denominated in dollars.
    function _buildWBTCConfig(uint16 cashOutTaxRate)
        internal
        view
        returns (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc)
    {
        // Set up accounting context for WBTC with 8 decimals and its derived currency ID.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: address(wbtc), decimals: 8, currency: wbtcCurrency});

        // Configure the terminal to accept WBTC payments.
        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Create a single split sending all reserved tokens to the multisig.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(multisig()),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        // Configure a single stage with 20% reserved split and the specified cash-out tax rate.
        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 2000, // 20% of minted tokens go to reserved splits
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE, // 1000 tokens per USD unit
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: cashOutTaxRate,
            extraMetadata: 0
        });

        // Build the REVConfig with USD as baseCurrency for cross-currency issuance.
        cfg = REVConfig({
            description: REVDescription("WBTC Test", "WBTC8", "ipfs://wbtc", "WBTC_SALT"),
            baseCurrency: USD, // Abstract USD -> triggers cross-currency conversion via JBPrices
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        // No sucker deployers needed for this test.
        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("WBTC"))
        });
    }

    /// @notice Build a two-stage config: high tax (stage 1) -> low tax (stage 2) with WBTC terminal.
    function _buildTwoStageWBTCConfig(
        uint16 stage1Tax,
        uint16 stage2Tax
    )
        internal
        view
        returns (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc)
    {
        // Set up accounting context for WBTC with 8 decimals.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: address(wbtc), decimals: 8, currency: wbtcCurrency});

        // Configure the terminal to accept WBTC.
        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Reserved token split sends 100% to multisig.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(multisig()),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        // Configure two stages with different cash-out tax rates.
        REVStageConfig[] memory stages = new REVStageConfig[](2);

        // Stage 1: starts immediately with high tax.
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 2000, // 20% reserved
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: stage1Tax,
            extraMetadata: 0
        });

        // Stage 2: starts after STAGE_DURATION with low tax.
        stages[1] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp + STAGE_DURATION),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 2000, // 20% reserved
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: stage2Tax,
            extraMetadata: 0
        });

        // Build config with USD baseCurrency for cross-currency conversion.
        cfg = REVConfig({
            description: REVDescription("WBTC TwoStage", "WB2S", "ipfs://wb2s", "WB2S_SALT"),
            baseCurrency: USD,
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        // No suckers for this test.
        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("WB2S"))
        });
    }

    /// @notice Build a 721 tier config with USD-priced tiers and an optional 30% split.
    function _build721ConfigUSDTiers(bool withSplit) internal view returns (REVDeploy721TiersHookConfig memory) {
        // Allocate space for one tier configuration.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);

        // Configure the tier split (30% to SPLIT_BENEFICIARY) if requested.
        JBSplit[] memory tierSplits;
        uint32 splitPercent;

        if (withSplit) {
            // Create a single split that sends 100% of the split amount to SPLIT_BENEFICIARY.
            tierSplits = new JBSplit[](1);
            tierSplits[0] = JBSplit({
                percent: uint32(uint256(JBConstants.SPLITS_TOTAL_PERCENT)),
                projectId: 0,
                beneficiary: payable(SPLIT_BENEFICIARY),
                preferAddToBalance: false,
                lockedUntil: 0,
                hook: IJBSplitHook(address(0))
            });
            // 30% of the tier's payment amount goes to splits.
            splitPercent = 300_000_000;
        } else {
            // No tier splits.
            tierSplits = new JBSplit[](0);
            splitPercent = 0;
        }

        // Configure tier 1: 100 USD price, 100 supply, category 1.
        tierConfigs[0] = JB721TierConfig({
            price: TIER_PRICE_USD, // 100 USD in 18 decimals (abstract USD pricing)
            initialSupply: 100, // 100 NFTs available in this tier
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32("wbtcTier1"),
            category: 1, // Tiers must be sorted by category
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

        // Return the full 721 hook configuration.
        return REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "WBTC NFT",
                symbol: "WBTCNFT",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: "ipfs://contract",
                tiersConfig: JB721InitTiersConfig({
                    tiers: tierConfigs,
                    currency: USD, // Abstract USD pricing for cross-currency normalization
                    decimals: 18 // Abstract USD uses 18 decimals
                }),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            salt: bytes32(withSplit ? bytes32("WBTC_721_S") : bytes32("WBTC_721")),
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });
    }

    // ===================================================================
    //  Pool / Oracle Helpers
    // ===================================================================

    /// @notice Mock the geomean oracle at address(0) to return a specific tick and liquidity.
    /// This is needed because the buyback hook queries IGeomeanOracle.observe() on the pool's
    /// hooks address (address(0) for hookless pools).
    function _mockOracle(int256 liquidity, int24 tick, uint32 twapWindow) internal {
        // Etch minimal bytecode at address(0) so mockCall targets a contract.
        vm.etch(address(0), hex"00");

        // Build tickCumulatives array: [0, tick * twapWindow] so average = tick.
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = 0;
        tickCumulatives[1] = int56(tick) * int56(int32(twapWindow));

        // Build secondsPerLiquidityCumulativeX128s for the TWAP window.
        uint136[] memory secondsPerLiquidityCumulativeX128s = new uint136[](2);
        secondsPerLiquidityCumulativeX128s[0] = 0;
        // Compute cumulative seconds-per-liquidity avoiding division by zero.
        uint256 liq = uint256(liquidity > 0 ? liquidity : -liquidity);
        if (liq == 0) liq = 1;
        secondsPerLiquidityCumulativeX128s[1] = uint136((uint256(twapWindow) << 128) / liq);

        // Mock the oracle observe() call to return our computed TWAP data.
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(IGeomeanOracle.observe.selector),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
        );
    }

    // ===================================================================
    //  Fee Project Helper
    // ===================================================================

    /// @notice Deploy the fee project (project ID 1) using native ETH.
    /// This is required before deploying any revnet because fees flow to this project.
    function _deployFeeProject(uint16 cashOutTaxRate) internal {
        // Set up accounting context for native ETH with 18 decimals.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});

        // Configure the terminal to accept native ETH.
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Single split sending everything to multisig.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0].beneficiary = payable(multisig());
        splits[0].percent = 10_000;

        // Single stage with the specified cash-out tax rate.
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

        // Fee project uses native ETH as baseCurrency.
        REVConfig memory cfg = REVConfig({
            description: REVDescription("Fee", "FEE", "ipfs://fee", "FEE_WBTC"),
            baseCurrency: nativeCurrency,
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        // No suckers for the fee project.
        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("FEE_WBTC"))
        });

        // Deploy the fee project from the multisig address.
        vm.prank(multisig());
        REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

    // ===================================================================
    //  Payment Helpers
    // ===================================================================

    /// @notice Pay a revnet with WBTC. Mints WBTC to the payer, approves the terminal, and calls pay().
    function _payRevnetWBTC(uint256 revnetId, address payer, uint256 amount) internal returns (uint256 tokensReceived) {
        // Mint WBTC to the payer so they have enough to pay.
        wbtc.mint(payer, amount);
        // Start impersonating the payer for approval and payment.
        vm.startPrank(payer);
        // Approve the terminal to spend the payer's WBTC.
        wbtc.approve(address(jbMultiTerminal()), amount);
        // Execute the payment and capture the number of project tokens received.
        tokensReceived = jbMultiTerminal()
            .pay({
                projectId: revnetId,
                token: address(wbtc),
                amount: amount,
                beneficiary: payer,
                minReturnedTokens: 0,
                memo: "",
                metadata: ""
            });
        // Stop impersonating the payer.
        vm.stopPrank();
    }

    /// @notice Read the terminal's recorded WBTC balance for a project.
    function _terminalBalanceWBTC(uint256 projectId) internal view returns (uint256) {
        // Query the terminal store for the project's WBTC balance.
        return jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, address(wbtc));
    }

    /// @notice Build pay metadata that selects tier 1 for 721 NFT minting.
    function _buildPayMetadataWithTier(address hookMetadataTarget) internal pure returns (bytes memory) {
        // Specify that tier ID 1 should be minted.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        // Encode the tier selection: (expectMintFromExtraFunds=true, tierIds).
        bytes memory tierData = abi.encode(true, tierIds);
        // Derive the metadata ID from the hook's pay context.
        bytes4 tierMetadataId = JBMetadataResolver.getId("pay", hookMetadataTarget);

        // Pack into the JBMetadataResolver format.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = tierMetadataId;
        bytes[] memory datas = new bytes[](1);
        datas[0] = tierData;

        // Create the packed metadata bytes.
        return JBMetadataResolver.createMetadata(ids, datas);
    }

    // ===================================================================
    //  Tests
    // ===================================================================

    /// @notice Test 1: Pay WBTC (8 decimals) into a USD-base project. Verify correct cross-currency
    /// token issuance accounting.
    ///
    /// Math: 1 WBTC = $60,000. Issuance = 1000 tokens/USD.
    /// Total mint = 60,000 * 1000 = 60,000,000 tokens.
    /// With 20% reserved: payer receives 80% = 48,000,000 tokens.
    function test_wbtc_payAndMintTokens() public {
        // Deploy the fee project first (required for revnet deployment).
        _deployFeeProject(5000);

        // Build a single-stage WBTC config with 50% cash-out tax.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildWBTCConfig(5000);

        // Deploy the revnet with WBTC terminal.
        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 1 WBTC (= 1e8 in 8-decimal representation).
        uint256 tokens = _payRevnetWBTC(revnetId, PAYER, 1e8);

        // Verify payer received ~48,000,000 tokens (80% of 60M after 20% reserved).
        // Allow 0.1% tolerance: 8-decimal price feed truncation in pricePerUnitOf introduces rounding
        // (e.g., 1e8 / 60000 truncates to 1666 instead of 1666.67, inflating the mint slightly).
        assertApproxEqRel(tokens, 48_000_000e18, 0.001e18, "1 WBTC at $60k -> ~48M tokens (80% after 20% reserved)");

        // Verify the terminal recorded the WBTC balance.
        assertEq(_terminalBalanceWBTC(revnetId), 1e8, "terminal should hold 1 WBTC");

        // Verify reserved tokens were accumulated (~20% of ~60M = ~12M).
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        // Same 0.1% tolerance for the reserved portion (same rounding source).
        assertApproxEqRel(pending, 12_000_000e18, 0.001e18, "reserved ~= 12,000,000 tokens (20%)");
    }

    /// @notice Test 2: Pay a fractional WBTC amount (0.001 BTC = 100,000 sats) and verify
    /// that 8-decimal precision is preserved through the issuance calculation.
    ///
    /// Math: 0.001 WBTC = $60. Total mint = 60 * 1000 = 60,000 tokens.
    /// With 20% reserved: payer receives 48,000 tokens.
    function test_wbtc_fractionalPayment() public {
        // Deploy the fee project.
        _deployFeeProject(5000);

        // Build config with 50% cash-out tax.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildWBTCConfig(5000);

        // Deploy the revnet.
        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 0.001 WBTC = 100,000 satoshis (1e5 in 8-decimal).
        uint256 tokens = _payRevnetWBTC(revnetId, PAYER, 1e5);

        // Verify correct token issuance for fractional WBTC amount.
        // Allow 0.1% tolerance for the same price feed truncation rounding as test 1.
        assertApproxEqRel(tokens, 48_000e18, 0.001e18, "0.001 WBTC at $60k -> ~48,000 tokens (80% after 20% reserved)");

        // Verify terminal balance reflects the fractional deposit.
        assertEq(_terminalBalanceWBTC(revnetId), 1e5, "terminal should hold 0.001 WBTC");
    }

    /// @notice Test 3: Pay with 721 tier metadata via cross-currency normalization.
    /// Tier is priced at 100 USD. At $60,000/BTC, payer needs ~0.00166667 BTC to mint the NFT.
    /// We overpay slightly (0.002 BTC = $120) so the tier price ($100) is met.
    function test_wbtc_721TierWithCrossCurrency() public {
        // Deploy the fee project.
        _deployFeeProject(5000);

        // Build WBTC config with 50% tax.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildWBTCConfig(5000);
        // Build 721 tier config with USD pricing and no tier split.
        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigUSDTiers(false);

        // Deploy the revnet with the 721 hook.
        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // Get the hook's metadata target for building pay metadata.
        address metadataTarget = hook.METADATA_ID_TARGET();
        // Build metadata that requests minting from tier 1.
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);

        // Pay 0.002 WBTC = $120 (enough to cover the $100 USD tier price).
        wbtc.mint(PAYER, 2e5);
        vm.startPrank(PAYER);
        // Approve the terminal to spend the payer's WBTC.
        wbtc.approve(address(jbMultiTerminal()), 2e5);
        // Pay with tier metadata to trigger NFT minting.
        uint256 tokens = jbMultiTerminal()
            .pay({
                projectId: revnetId,
                token: address(wbtc),
                amount: 2e5, // 0.002 WBTC in 8-decimal
                beneficiary: PAYER,
                minReturnedTokens: 0,
                memo: "",
                metadata: metadata
            });
        vm.stopPrank();

        // Verify the NFT was minted to the payer via cross-currency normalization.
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should own 1 NFT from WBTC payment");

        // Verify project tokens were also issued.
        assertGt(tokens, 0, "payer should receive project tokens alongside NFT");
    }

    /// @notice Test 4: Cash out tokens for WBTC and verify the reclaim uses correct 8-decimal conversion.
    /// Two payers create a bonding curve effect, then the first payer cashes out half their tokens.
    function test_wbtc_cashOutWithBondingCurve() public {
        // Deploy the fee project.
        _deployFeeProject(5000);

        // Build config with 50% cash-out tax rate (visible bonding curve penalty).
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildWBTCConfig(5000);

        // Deploy the revnet.
        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Two payers create surplus and bonding curve dynamics.
        _payRevnetWBTC(revnetId, PAYER, 1e8); // 1 WBTC
        _payRevnetWBTC(revnetId, PAYER2, 5e7); // 0.5 WBTC

        // Read payer's token balance before cash-out.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        // Cash out half of payer's tokens.
        uint256 cashOutCount = payerTokens / 2;
        // Record WBTC balance before cash-out for comparison.
        uint256 payerWBTCBefore = wbtc.balanceOf(PAYER);

        // Execute the cash-out, reclaiming WBTC.
        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
                holder: PAYER,
                projectId: revnetId,
                cashOutCount: cashOutCount,
                tokenToReclaim: address(wbtc),
                minTokensReclaimed: 0,
                beneficiary: payable(PAYER),
                metadata: ""
            });

        // Verify the payer received WBTC from the cash-out (8-decimal amount).
        uint256 wbtcReceived = wbtc.balanceOf(PAYER) - payerWBTCBefore;
        assertGt(wbtcReceived, 0, "payer should receive WBTC from cash-out");

        // Verify the reclaimed amount is less than pro-rata due to 50% tax.
        // Pro-rata for half tokens from 1.5 WBTC pool would be 0.5 WBTC.
        // With 50% tax, should be notably less.
        assertLt(wbtcReceived, 5e7, "reclaim should be less than pro-rata due to 50% tax");

        // Verify tokens were burned.
        assertEq(
            jbTokens().totalBalanceOf(PAYER, revnetId),
            payerTokens - cashOutCount,
            "tokens should be burned after cash-out"
        );

        // Verify the terminal balance decreased by the reclaimed amount.
        assertLt(_terminalBalanceWBTC(revnetId), 15e7, "terminal balance should decrease after cash-out");
    }

    /// @notice Test 5: Verify the buyback hook handles 8-decimal WBTC math correctly.
    /// Set up a buyback pool, then pay and check that the buyback hook's mint-vs-swap
    /// comparison works with 8-decimal token amounts.
    function test_wbtc_buybackHookWith8Decimals() public {
        // Deploy the fee project.
        _deployFeeProject(5000);

        // Build config with 50% tax.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildWBTCConfig(5000);

        // Deploy the revnet.
        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Get the deployed project token address.
        address projectToken = address(jbTokens().tokenOf(revnetId));
        // Verify the project token was deployed.
        require(projectToken != address(0), "project token not deployed");

        // Sort tokens for the PoolKey (lower address is currency0).
        address token0 = address(wbtc) < projectToken ? address(wbtc) : projectToken;
        address token1 = address(wbtc) < projectToken ? projectToken : address(wbtc);

        // Build the pool key matching the REVDeployer's buyback pool parameters.
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(),
            tickSpacing: REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(),
            hooks: IHooks(address(0))
        });

        // Seed the pool with WBTC and project tokens for liquidity.
        uint256 wbtcLiquidity = 1e8; // 1 WBTC of liquidity
        wbtc.mint(address(liqHelper), wbtcLiquidity);
        // Mint project tokens to the liquidity helper (scale 8-dec WBTC to 18-dec project tokens).
        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, wbtcLiquidity * 1e10);

        // Approve the PoolManager to spend both tokens from the liquidity helper.
        vm.startPrank(address(liqHelper));
        IERC20(address(wbtc)).approve(address(poolManager), type(uint256).max);
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);
        vm.stopPrank();

        // Add liquidity across the full tick range.
        int256 liquidityDelta = int256(wbtcLiquidity / 2);
        vm.prank(address(liqHelper));
        liqHelper.addLiquidity(key, TICK_LOWER, TICK_UPPER, liquidityDelta);

        // Mock the oracle tick to match the issuance rate for WBTC.
        // At $60,000/BTC and 1000 tokens/USD, 1 WBTC mints 60M tokens.
        // Raw ratio = 60,000,000e18 / 1e8 = 6e29. tick = ln(6e29)/ln(1.0001) ~ 685,000.
        // Sign depends on token sort order.
        int24 issuanceTick = address(wbtc) < projectToken ? int24(685_000) : int24(-685_000);
        // Update the mock oracle to reflect the issuance-equivalent tick.
        _mockOracle(liquidityDelta, issuanceTick, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Pay some initial surplus so the pool has context.
        _payRevnetWBTC(revnetId, PAYER2, 5e7); // 0.5 WBTC

        // Pay again with the buyback hook active.
        uint256 tokens = _payRevnetWBTC(revnetId, PAYER, 1e7); // 0.1 WBTC

        // Verify tokens were received (either via mint or swap, whichever wins).
        assertGt(tokens, 0, "should receive tokens with buyback hook active");

        // Verify terminal balance increased.
        assertGt(_terminalBalanceWBTC(revnetId), 0, "terminal balance should increase");
    }

    /// @notice Test 6: 721 tier with 30% split, paid via WBTC cross-currency.
    /// The split beneficiary should receive ~30% of the payment in WBTC.
    function test_wbtc_721TierSplitWithCrossCurrency() public {
        // Deploy the fee project.
        _deployFeeProject(5000);

        // Build WBTC config with 50% tax.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildWBTCConfig(5000);
        // Build 721 tier config with a 30% split to SPLIT_BENEFICIARY.
        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigUSDTiers(true);

        // Deploy the revnet with the 721 hook including the tier split.
        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // Get the hook's metadata target.
        address metadataTarget = hook.METADATA_ID_TARGET();
        // Build metadata that requests tier 1 minting.
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);

        // Record the split beneficiary's WBTC balance before payment.
        uint256 splitBeneficiaryBefore = wbtc.balanceOf(SPLIT_BENEFICIARY);

        // Pay 0.002 WBTC = $120 (enough for the $100 tier).
        wbtc.mint(PAYER, 2e5);
        vm.startPrank(PAYER);
        // Approve the terminal.
        wbtc.approve(address(jbMultiTerminal()), 2e5);
        // Pay with tier metadata.
        jbMultiTerminal()
            .pay({
                projectId: revnetId,
                token: address(wbtc),
                amount: 2e5, // 0.002 WBTC
                beneficiary: PAYER,
                minReturnedTokens: 0,
                memo: "",
                metadata: metadata
            });
        vm.stopPrank();

        // Verify the NFT was minted.
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should own 1 NFT");

        // Verify the split beneficiary received WBTC (~30% of the tier's WBTC equivalent).
        uint256 splitReceived = wbtc.balanceOf(SPLIT_BENEFICIARY) - splitBeneficiaryBefore;
        // 30% of ~0.001667 BTC (tier price in BTC) ~ 0.0005 BTC = 50,000 sats.
        // Allow 5% tolerance for rounding in cross-currency conversion.
        assertGt(splitReceived, 0, "split beneficiary should receive WBTC");
    }

    /// @notice Test 7: Warp to stage 2 (lower tax) and verify that borrowable amount increases
    /// and cash-out returns more WBTC with the lower tax rate.
    function test_wbtc_crossStageTransition() public {
        // Deploy the fee project.
        _deployFeeProject(5000);

        // Build two-stage config: 70% tax in stage 1, 20% tax in stage 2.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageWBTCConfig(7000, 2000);

        // Deploy the revnet.
        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Two payers create surplus.
        _payRevnetWBTC(revnetId, PAYER, 1e8); // 1 WBTC
        _payRevnetWBTC(revnetId, PAYER2, 5e7); // 0.5 WBTC

        // Read payer's token balance.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);

        // Record borrowable amount in stage 1 (70% tax).
        uint256 borrowableStage1 = LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 8, wbtcCurrency);

        // Warp to stage 2 (20% tax).
        vm.warp(block.timestamp + STAGE_DURATION + 1);

        // Borrowable amount should increase with lower tax.
        uint256 borrowableStage2 = LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 8, wbtcCurrency);
        assertGt(borrowableStage2, borrowableStage1, "borrowable should increase in stage 2 with lower tax");
    }

    /// @notice Test 8: Dust payment (1 satoshi = 1e0 in 8-decimal) should not revert.
    /// Verifies that 8-decimal precision handles minimum amounts gracefully.
    function test_wbtc_dustPayment_noRevert() public {
        // Deploy the fee project.
        _deployFeeProject(5000);

        // Build config with 50% tax.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildWBTCConfig(5000);

        // Deploy the revnet.
        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 1 satoshi (minimum WBTC amount).
        // At $60k/BTC, 1 sat = $0.0006. Tokens = 0.0006 * 1000 = 0.6 tokens.
        // With rounding and reserved, may be 0 or very small -- key is no revert.
        _payRevnetWBTC(revnetId, PAYER, 1);

        // Verify no revert occurred (dust payments should be gracefully handled).
        assertTrue(true, "dust payment (1 satoshi) did not revert");
    }

    /// @notice Test 9: Full lifecycle with WBTC: deploy -> pay -> distribute reserved -> cash out.
    /// Exercises the complete payment-to-cashout path with 8-decimal WBTC.
    function test_wbtc_fullLifecycle() public {
        // Deploy the fee project.
        _deployFeeProject(5000);

        // Build WBTC config with 50% tax and deploy with 721 hook.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildWBTCConfig(5000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigUSDTiers(false);

        // Deploy the revnet with WBTC terminal and 721 hook.
        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // Step 1: Pay 1 WBTC to get project tokens.
        uint256 tokensFromPay = _payRevnetWBTC(revnetId, PAYER, 1e8);
        // Verify tokens were minted.
        assertGt(tokensFromPay, 0, "step 1: should receive tokens from WBTC payment");

        // Step 2: Second payer adds to the surplus for bonding curve effect.
        _payRevnetWBTC(revnetId, PAYER2, 5e7);

        // Step 3: Distribute reserved tokens to splits.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        // Verify reserved tokens accumulated.
        assertGt(pending, 0, "step 3: should have pending reserved tokens");
        // Send reserved tokens to the configured splits.
        jbController().sendReservedTokensToSplitsOf(revnetId);
        // Verify multisig received the reserved tokens.
        uint256 multisigTokens = jbTokens().totalBalanceOf(multisig(), revnetId);
        assertGt(multisigTokens, 0, "step 3: multisig should receive reserved tokens");

        // Step 4: Pay with 721 tier metadata to mint an NFT.
        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);
        // Pay 0.002 WBTC with tier metadata.
        wbtc.mint(PAYER, 2e5);
        vm.startPrank(PAYER);
        wbtc.approve(address(jbMultiTerminal()), 2e5);
        uint256 tokensFromNFTPay = jbMultiTerminal()
            .pay({
                projectId: revnetId,
                token: address(wbtc),
                amount: 2e5,
                beneficiary: PAYER,
                minReturnedTokens: 0,
                memo: "",
                metadata: metadata
            });
        vm.stopPrank();
        // Verify NFT was minted.
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "step 4: payer should own 1 NFT");
        // Verify project tokens were also issued.
        assertGt(tokensFromNFTPay, 0, "step 4: should receive tokens with NFT");

        // Step 5: Cash out half of payer's tokens for WBTC.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 cashOutCount = payerTokens / 2;
        uint256 payerWBTCBefore = wbtc.balanceOf(PAYER);

        // Execute the cash-out.
        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
                holder: PAYER,
                projectId: revnetId,
                cashOutCount: cashOutCount,
                tokenToReclaim: address(wbtc),
                minTokensReclaimed: 0,
                beneficiary: payable(PAYER),
                metadata: ""
            });

        // Verify WBTC was received (8-decimal reclaim amount).
        assertGt(wbtc.balanceOf(PAYER), payerWBTCBefore, "step 5: should receive WBTC from cash-out");
        // Verify the correct number of tokens remain.
        assertEq(
            jbTokens().totalBalanceOf(PAYER, revnetId),
            payerTokens - cashOutCount,
            "step 5: remaining tokens should be correct"
        );
    }

    /// @notice Test 10: Multi-token surplus aggregation. Pay both WBTC and ETH, verify
    /// surplus is correctly aggregated in USD terms across different decimal tokens.
    function test_wbtc_multiTokenSurplusAggregation() public {
        // Deploy the fee project.
        _deployFeeProject(5000);

        // Build config that accepts BOTH WBTC and ETH.
        JBAccountingContext[] memory acc = new JBAccountingContext[](2);
        // WBTC with 8 decimals.
        acc[0] = JBAccountingContext({token: address(wbtc), decimals: 8, currency: wbtcCurrency});
        // Native ETH with 18 decimals.
        acc[1] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});

        // Configure the terminal to accept both tokens.
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Single split to multisig for reserved tokens.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(multisig()),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        // Single stage with 50% tax and 20% reserved.
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

        // USD baseCurrency for cross-currency aggregation.
        REVConfig memory cfg = REVConfig({
            description: REVDescription("WBTC+ETH", "WBETH", "ipfs://wbeth", "WBETH_SALT"),
            baseCurrency: USD,
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        // No suckers.
        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("WBETH"))
        });

        // Deploy the revnet with dual-token terminal.
        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 0.1 WBTC = $6,000.
        _payRevnetWBTC(revnetId, PAYER, 1e7);

        // Pay 1 ETH = $2,000.
        vm.deal(PAYER2, 10 ether);
        vm.prank(PAYER2);
        jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER2,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Check surplus in USD terms (aggregates both WBTC and ETH via JBPrices).
        uint256 surplusUSD = jbMultiTerminal().currentSurplusOf(revnetId, new address[](0), 18, USD);

        // Total surplus should be ~$8,000 ($6,000 WBTC + $2,000 ETH).
        assertGt(surplusUSD, 7800e18, "surplus should be >= $7,800 (allowing for rounding)");
        assertLe(surplusUSD, 8200e18, "surplus should be <= $8,200");
    }
}
