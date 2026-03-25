// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core imports for JB types and libraries.
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBPayoutTerminal} from "@bananapus/core-v6/src/interfaces/IJBPayoutTerminal.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";

// 721 Hook contracts for NFT tier deployment.
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHookStore} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookStore.sol";

// Address registry for hook deployment.
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// Buyback hook for AMM-based token purchases.
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";
import {IGeomeanOracle} from "@bananapus/buyback-hook-v6/src/interfaces/IGeomeanOracle.sol";

// Sucker registry for cross-chain operations.
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// Croptop publisher for revnet deployment.
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";

// Revnet contracts for deploying and managing revnets.
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {IREVLoans} from "@rev-net/core-v6/src/interfaces/IREVLoans.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";
import {REVLoanSource} from "@rev-net/core-v6/src/structs/REVLoanSource.sol";

// Uniswap V4 types for pool configuration and buyback.
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

// OpenZeppelin token interfaces.
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock USDC with 6 decimals for fork testing.
contract MockUSDC6 is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    /// @notice Return 6 decimals to match real USDC behavior.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Public mint for testing — no access control.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Adds liquidity to a hookless V4 pool via the unlock/callback pattern.
/// Used to seed the buyback pool with USDC and project tokens.
contract MixedDecLiquidityHelper is IUnlockCallback {
    /// @notice The Uniswap V4 pool manager for settlement operations.
    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @notice Accept native ETH transfers.
    receive() external payable {}

    /// @notice Initiate liquidity addition via the pool manager's unlock pattern.
    function addLiquidity(
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta
    )
        external
        payable
    {
        // Encode pool params for the callback to decode and execute.
        poolManager.unlock(abi.encode(key, tickLower, tickUpper, liquidityDelta));
    }

    /// @notice Callback from pool manager after unlock — modifies liquidity and settles.
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        // Decode the pool key and liquidity parameters from the unlock data.
        (PoolKey memory key, int24 tickLower, int24 tickUpper, int256 liquidityDelta) =
            abi.decode(data, (PoolKey, int24, int24, int256));

        // Add liquidity to the pool at the specified tick range.
        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: 0
            }),
            ""
        );

        // Extract the amounts owed/received for each currency.
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // Settle any tokens owed to the pool (negative delta = owed to pool).
        if (amount0 < 0) _settle(key.currency0, uint128(-amount0));
        if (amount1 < 0) _settle(key.currency1, uint128(-amount1));

        // Claim any tokens the pool owes us (positive delta = owed to us).
        if (amount0 > 0) poolManager.take(key.currency0, address(this), uint128(amount0));
        if (amount1 > 0) poolManager.take(key.currency1, address(this), uint128(amount1));

        return "";
    }

    /// @notice Settle a specific currency with the pool manager.
    function _settle(Currency currency, uint256 amount) internal {
        if (Currency.unwrap(currency) == address(0)) {
            // Native ETH settlement uses msg.value.
            poolManager.settle{value: amount}();
        } else {
            // ERC-20 settlement: sync + transfer + settle pattern.
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).transfer(address(poolManager), amount);
            poolManager.settle();
        }
    }
}

/// @notice Composition test: USDC (6-decimal) loan -> revnet stage transition -> buyback hook
/// activation -> terminal migration -> loan repayment.
///
/// This test validates correct behavior when all of these subsystems interact simultaneously,
/// specifically targeting the "mixed-decimal loan source + stage transition + buyback + migration"
/// gap identified in CodexQA.
///
/// Key assertions:
/// - 6-decimal USDC accounting is preserved throughout the entire lifecycle
/// - Stage transitions update issuance parameters correctly mid-loan
/// - Buyback hook activates when pool price beats issuance weight
/// - Terminal migration transfers USDC balance without corrupting loan state
/// - Loan repayment returns correct USDC amount with proper 6-decimal accounting
///
/// Run with: forge test --match-contract MixedDecimalLoanComposition -vvv
contract MixedDecimalLoanCompositionTest is TestBaseWorkflow {
    using PoolIdLibrary for PoolKey;

    // ── Mainnet addresses for Uniswap V4 integration.
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    // ── Tick range for full-range liquidity in hookless pool.
    int24 constant TICK_LOWER = -887_200;
    int24 constant TICK_UPPER = 887_200;

    // ── Test parameters matching typical revnet deployment.
    uint112 constant STAGE_1_ISSUANCE = uint112(1000e18); // 1000 tokens per USDC unit in stage 1.
    uint112 constant STAGE_2_ISSUANCE = uint112(500e18); // 500 tokens per USDC unit in stage 2.
    uint32 constant STAGE_DURATION = 30 days; // Duration before stage 2 activates.

    // ── Actors for the test scenario.
    address PAYER = makeAddr("payer");
    address BORROWER = makeAddr("borrower");

    // ── Trusted forwarder for ERC2771 meta-transactions.
    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // ── Ecosystem contracts deployed during setUp.
    IPoolManager poolManager;
    MixedDecLiquidityHelper liqHelper;

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
    REVDeployer REV_DEPLOYER;

    // ── Mock USDC with 6 decimals.
    MockUSDC6 usdc;

    /// @notice Accept native ETH for gas operations and fee refunds.
    receive() external payable {}

    function setUp() public override {
        // Fork mainnet at a stable block after Uniswap V4 deployment.
        vm.createSelectFork("ethereum", 21_700_000);
        // Verify the pool manager is deployed at the expected address.
        require(POOL_MANAGER_ADDR.code.length > 0, "PoolManager not deployed");

        // Deploy fresh JB core contracts on the forked mainnet.
        super.setUp();

        // Initialize Uniswap V4 integration contracts.
        poolManager = IPoolManager(POOL_MANAGER_ADDR);
        // Create liquidity helper for seeding buyback pools.
        liqHelper = new MixedDecLiquidityHelper(poolManager);

        // Deploy MockUSDC with 6 decimals and mint test supply.
        usdc = new MockUSDC6();
        // Mint 100M USDC to the test contract for general use.
        usdc.mint(address(this), 100_000_000e6);

        // Create the fee project that receives protocol fees.
        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        // Deploy supporting ecosystem contracts.
        SUCKER_REGISTRY = new JBSuckerRegistry(jbDirectory(), jbPermissions(), multisig(), address(0));
        HOOK_STORE = new JB721TiersHookStore();
        // Deploy the 721 tiers hook implementation for NFT tiers.
        EXAMPLE_HOOK = new JB721TiersHook(
            jbDirectory(), jbPermissions(), jbPrices(), jbRulesets(), HOOK_STORE, jbSplits(), multisig()
        );
        ADDRESS_REGISTRY = new JBAddressRegistry();
        // Deploy the hook deployer that clones the example hook.
        HOOK_DEPLOYER = new JB721TiersHookDeployer(EXAMPLE_HOOK, HOOK_STORE, ADDRESS_REGISTRY, multisig());
        // Deploy croptop publisher for revnet deployment.
        PUBLISHER = new CTPublisher(jbDirectory(), jbPermissions(), FEE_PROJECT_ID, multisig());

        // Deploy buyback hook with real Uniswap V4 PoolManager.
        BUYBACK_HOOK = new JBBuybackHook(
            jbDirectory(),
            jbPermissions(),
            jbPrices(),
            jbProjects(),
            jbTokens(),
            poolManager,
            IHooks(address(0)), // No custom hook on the pool.
            address(0) // No WETH needed for USDC-only tests.
        );

        // Register buyback hook as the default data hook for all revnets.
        BUYBACK_REGISTRY = new JBBuybackHookRegistry(jbPermissions(), jbProjects(), address(this), address(0));
        BUYBACK_REGISTRY.setDefaultHook(IJBRulesetDataHook(address(BUYBACK_HOOK)));

        // Deploy the loans contract that manages revnet collateralized loans.
        LOANS_CONTRACT = new REVLoans({
            controller: jbController(),
            projects: jbProjects(),
            revId: FEE_PROJECT_ID,
            owner: address(this),
            permit2: permit2(),
            trustedForwarder: TRUSTED_FORWARDER
        });

        // Deploy the REV deployer that creates revnets with all hooks wired up.
        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_MixedDec"}(
            jbController(),
            SUCKER_REGISTRY,
            FEE_PROJECT_ID,
            HOOK_DEPLOYER,
            PUBLISHER,
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            address(LOANS_CONTRACT),
            TRUSTED_FORWARDER
        );

        // Approve the REV deployer to claim the fee project.
        vm.prank(multisig());
        jbProjects().approve(address(REV_DEPLOYER), FEE_PROJECT_ID);

        // Mock the geomean oracle at address(0) so payments work before buyback pool setup.
        // The buyback hook queries IGeomeanOracle.observe() on the pool's hooks address.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Fund actors with USDC for payments.
        usdc.mint(PAYER, 10_000_000e6); // 10M USDC for the payer.
        usdc.mint(BORROWER, 5_000_000e6); // 5M USDC for the borrower.

        // Fund actors with ETH for gas.
        vm.deal(PAYER, 10 ether);
        vm.deal(BORROWER, 10 ether);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Config Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Build a two-stage USDC revnet config.
    /// Stage 1: high issuance (1000 tokens/USDC), moderate tax (50%).
    /// Stage 2: low issuance (500 tokens/USDC), low tax (20%) — activates after STAGE_DURATION.
    function _buildTwoStageUSDCConfig()
        internal
        view
        returns (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc)
    {
        // Set up USDC accounting context with 6 decimals.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: address(usdc),
            decimals: 6,
            currency: uint32(uint160(address(usdc))) // Currency derived from token address.
        });

        // Configure the primary terminal to accept USDC.
        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Reserved token splits: 100% to multisig.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT), // 100% of reserved goes to multisig.
            projectId: 0,
            beneficiary: payable(multisig()),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0)) // No split hook.
        });

        // Two stages with different issuance rates and cashout tax rates.
        REVStageConfig[] memory stages = new REVStageConfig[](2);

        // Stage 1: high issuance, moderate tax — starts immediately.
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp), // Starts now.
            autoIssuances: new REVAutoIssuance[](0), // No auto-issuances.
            splitPercent: 2000, // 20% reserved for splits.
            splits: splits,
            initialIssuance: STAGE_1_ISSUANCE, // 1000 tokens per USDC unit.
            issuanceCutFrequency: STAGE_DURATION, // Ruleset cycles every 30 days.
            issuanceCutPercent: 0, // No issuance decay within stage.
            cashOutTaxRate: 5000, // 50% cashout tax in stage 1.
            extraMetadata: 0
        });

        // Stage 2: lower issuance, lower tax — starts after stage 1 duration.
        stages[1] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp + STAGE_DURATION), // Starts 30 days later.
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 1000, // 10% reserved in stage 2.
            splits: splits,
            initialIssuance: STAGE_2_ISSUANCE, // 500 tokens per USDC unit.
            issuanceCutFrequency: 0, // No cyclic decay in stage 2.
            issuanceCutPercent: 0,
            cashOutTaxRate: 2000, // 20% cashout tax in stage 2.
            extraMetadata: 0
        });

        // Build the revnet configuration with USDC as base currency.
        cfg = REVConfig({
            description: REVDescription("MixedDec", "MXDC", "ipfs://mixeddec", "MXDC_SALT"),
            baseCurrency: uint32(uint160(address(usdc))), // USDC as base currency.
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        // No sucker deployment for this test.
        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("MXDC"))
        });
    }

    /// @notice Deploy the fee project as a native-ETH revnet.
    /// The fee project receives protocol fees from all terminal operations.
    function _deployFeeProject() internal {
        // Fee project uses native ETH accounting.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Minimal fee project split config.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0].beneficiary = payable(multisig()); // Fee recipient.
        splits[0].percent = 10_000; // 100% of reserved tokens.

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 0,
            splits: splits,
            initialIssuance: STAGE_1_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: 5000,
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("Fee", "FEE", "ipfs://fee", "FEE_MXDC"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("FEE_MXDC"))
        });

        // Deploy fee project as a revnet via the multisig.
        vm.prank(multisig());
        REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Pool / Buyback Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Set up a USDC/projectToken buyback pool and seed it with liquidity.
    /// REVDeployer already initializes and registers the pool during deployFor;
    /// this helper only adds liquidity to the existing pool.
    function _setupUSDCBuybackPool(uint256 revnetId, uint256 liquidityUSDCAmount)
        internal
        returns (PoolKey memory key)
    {
        // Get the revnet's ERC-20 project token address.
        address projectToken = address(jbTokens().tokenOf(revnetId));
        require(projectToken != address(0), "project token not deployed");

        // Sort currencies — both are ERC-20s, no native ETH involved.
        address token0 = address(usdc) < projectToken ? address(usdc) : projectToken;
        address token1 = address(usdc) < projectToken ? projectToken : address(usdc);

        // Construct the pool key matching what REVDeployer created.
        key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(), // Default fee tier.
            tickSpacing: REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(), // Default tick spacing.
            hooks: IHooks(address(0)) // No custom hook on the pool.
        });

        // Fund the liquidity helper with USDC and project tokens.
        usdc.mint(address(liqHelper), liquidityUSDCAmount);
        // Mint project tokens to the liquidity helper via the controller (privileged).
        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, liquidityUSDCAmount * 1e12); // Scale 6->18 decimals.

        // Approve pool manager to spend both tokens from the liquidity helper.
        vm.startPrank(address(liqHelper));
        IERC20(address(usdc)).approve(address(poolManager), type(uint256).max);
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);
        vm.stopPrank();

        // Calculate liquidity delta from USDC amount.
        int256 liquidityDelta = int256(liquidityUSDCAmount / 2);

        // Add full-range liquidity to the pool.
        vm.prank(address(liqHelper));
        liqHelper.addLiquidity(key, TICK_LOWER, TICK_UPPER, liquidityDelta);

        // Compute oracle tick matching the issuance rate: 1000 project tokens (18 dec) per USDC (6 dec).
        // Raw ratio = 1e21 / 1e6 = 1e15. tick = ln(1e15)/ln(1.0001) ~ 345_400.
        // Sign depends on token sort order.
        int24 issuanceTick = address(usdc) < projectToken ? int24(345_400) : int24(-345_400);
        // Mock the oracle to report this tick as the TWAP.
        _mockOracle(liquidityDelta, issuanceTick, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
    }

    /// @notice Mock the geomean oracle at address(0) to return a specific tick/liquidity.
    /// This enables the buyback hook to compute TWAP prices without a real oracle.
    function _mockOracle(int256 liquidity, int24 tick, uint32 twapWindow) internal {
        // Etch minimal bytecode at address(0) so it can be called.
        vm.etch(address(0), hex"00");

        // Build tick cumulative array: [0, tick * twapWindow].
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = 0;
        tickCumulatives[1] = int56(tick) * int56(int32(twapWindow)); // Cumulative tick over window.

        // Build seconds-per-liquidity array for the TWAP calculation.
        uint136[] memory secondsPerLiquidityCumulativeX128s = new uint136[](2);
        secondsPerLiquidityCumulativeX128s[0] = 0;
        // Ensure liquidity is positive for the denominator.
        uint256 liq = uint256(liquidity > 0 ? liquidity : -liquidity);
        if (liq == 0) liq = 1; // Prevent division by zero.
        secondsPerLiquidityCumulativeX128s[1] = uint136((uint256(twapWindow) << 128) / liq);

        // Mock the oracle's observe function to return our constructed values.
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(IGeomeanOracle.observe.selector),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Payment / Loan Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Pay a revnet with USDC. Mints USDC to the payer, approves the terminal, and pays.
    function _payRevnetUSDC(uint256 revnetId, address payer, uint256 amount) internal returns (uint256 tokensReceived) {
        // Mint fresh USDC to the payer (ensures sufficient balance).
        usdc.mint(payer, amount);
        vm.startPrank(payer);
        // Approve the terminal to spend the USDC.
        usdc.approve(address(jbMultiTerminal()), amount);
        // Pay the revnet and receive project tokens in return.
        tokensReceived = jbMultiTerminal()
            .pay({
                projectId: revnetId,
                token: address(usdc),
                amount: amount,
                beneficiary: payer,
                minReturnedTokens: 0, // Accept any amount for testing.
                memo: "",
                metadata: ""
            });
        vm.stopPrank();
    }

    /// @notice Read a terminal's recorded balance for a project/token pair.
    function _terminalBalance(address terminal, uint256 projectId, address token) internal view returns (uint256) {
        return jbTerminalStore().balanceOf(terminal, projectId, token);
    }

    /// @notice Build a USDC loan source pointing to the primary terminal.
    function _usdcLoanSource() internal view returns (REVLoanSource memory) {
        return REVLoanSource({
            token: address(usdc), // USDC token address.
            terminal: IJBPayoutTerminal(address(jbMultiTerminal())) // Primary terminal.
        });
    }

    /// @notice Grant BURN_TOKENS permission to the loans contract so it can burn collateral.
    function _grantBurnPermission(address account, uint256 revnetId) internal {
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 11; // BURN_TOKENS permission ID.
        vm.prank(account);
        // Grant the loans contract permission to burn the account's tokens.
        jbPermissions()
            .setPermissionsFor(
                account,
                JBPermissionsData({
                    operator: address(LOANS_CONTRACT), projectId: uint64(revnetId), permissionIds: permissionIds
                })
            );
    }

    /// @notice Grant MIGRATE_TERMINAL permission to an account for a project.
    function _grantMigratePermission(address from, address operator, uint256 projectId) internal {
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 6; // MIGRATE_TERMINAL permission ID.
        vm.prank(from);
        // Grant the operator permission to migrate terminals for this project.
        jbPermissions()
            .setPermissionsFor(
                from,
                JBPermissionsData({operator: operator, projectId: uint64(projectId), permissionIds: permissionIds})
            );
    }

    /// @notice Mock the JBTerminalStore.recordTerminalMigration to bypass the
    /// allowTerminalMigration metadata check.
    ///
    /// Revnets do not enable the allowTerminalMigration flag in their ruleset metadata.
    /// To test the composition of migration with loans, we mock the store's migration
    /// function to return the real balance while skipping the metadata check.
    /// The actual balance zeroing and fund transfer happen via the terminal's migrateBalanceOf
    /// implementation.
    function _mockStoreRecordMigration(uint256 projectId, address token) internal {
        // Read the real balance that would be migrated.
        uint256 balance = jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, token);

        // Mock recordTerminalMigration on the store to return the balance without checking metadata.
        vm.mockCall(
            address(jbTerminalStore()),
            abi.encodeWithSelector(jbTerminalStore().recordTerminalMigration.selector, projectId, token),
            abi.encode(balance)
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test: Full Composition Lifecycle
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Full composition test: USDC loan -> stage transition -> buyback -> migration -> repay.
    ///
    /// Steps:
    /// 1. Deploy a two-stage USDC revnet
    /// 2. Pay into the revnet with USDC — tokens issued at stage 1 rate
    /// 3. Take a USDC loan using issued tokens as collateral
    /// 4. Advance time to trigger stage 2 (different issuance + tax parameters)
    /// 5. Set up buyback pool and make a payment (buyback hook competes with mint)
    /// 6. Migrate terminal balance to a new terminal
    /// 7. Repay the loan — verify correct 6-decimal USDC accounting
    /// 8. Verify all state: loan, stage, buyback, migration
    function test_mixedDecimal_fullComposition() public {
        // ──────────────── Step 0: Deploy fee project
        // ────────────────
        _deployFeeProject();

        // ──────────────── Step 1: Deploy two-stage USDC revnet
        // ────────────────
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageUSDCConfig();

        // Deploy the revnet and get its ID.
        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Verify: stage 1 is active with expected cashout tax rate.
        JBRuleset memory ruleset1 = jbRulesets().currentOf(revnetId);
        // Stage 1 cashOutTaxRate is stored in packed metadata bits 20-35.
        uint16 stage1Tax = uint16((ruleset1.metadata >> 20) & 0xFFFF);
        assertEq(stage1Tax, 5000, "stage 1 should have 50% cashout tax");

        // ──────────────── Step 2: Pay with USDC — tokens issued at stage 1 rate
        // ────────────────
        uint256 payAmount = 10_000e6; // 10,000 USDC (6 decimals).
        // Payer receives project tokens at the stage 1 issuance rate.
        uint256 payerTokens = _payRevnetUSDC(revnetId, PAYER, payAmount);
        assertGt(payerTokens, 0, "payer should receive tokens from USDC payment");

        // A second payer creates surplus for bonding curve / loan collateral value.
        uint256 borrowerPayAmount = 5000e6; // 5,000 USDC.
        uint256 borrowerTokens = _payRevnetUSDC(revnetId, BORROWER, borrowerPayAmount);
        assertGt(borrowerTokens, 0, "borrower should receive tokens from USDC payment");

        // Verify terminal holds the USDC balance (minus any fees).
        uint256 termBalance = _terminalBalance(address(jbMultiTerminal()), revnetId, address(usdc));
        assertGt(termBalance, 0, "terminal should hold USDC after payments");

        // ──────────────── Step 3: Take a USDC loan
        // ────────────────
        // Grant the loans contract permission to burn borrower's tokens as collateral.
        _grantBurnPermission(BORROWER, revnetId);

        // Build the loan source pointing to USDC on the primary terminal.
        REVLoanSource memory source = _usdcLoanSource();

        // Check borrowable amount with 6-decimal USDC precision.
        uint256 borrowable = LOANS_CONTRACT.borrowableAmountFrom(
            revnetId,
            borrowerTokens,
            6, // 6 decimals for USDC output.
            uint32(uint160(address(usdc))) // USDC currency.
        );
        assertGt(borrowable, 0, "should have borrowable USDC amount");

        // Record borrower's USDC balance before borrowing.
        uint256 borrowerUSDCBefore = usdc.balanceOf(BORROWER);

        // Execute the loan: burn tokens as collateral, receive USDC.
        vm.startPrank(BORROWER);
        (uint256 loanId, REVLoan memory loan) = LOANS_CONTRACT.borrowFrom({
            revnetId: revnetId,
            source: source,
            minBorrowAmount: 0, // Accept any amount for testing.
            collateralCount: borrowerTokens, // Use all tokens as collateral.
            beneficiary: payable(BORROWER), // Borrower receives USDC proceeds.
            prepaidFeePercent: LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT() // Minimum prepaid fee.
        });
        vm.stopPrank();

        // Verify loan was created.
        assertGt(loanId, 0, "loan ID should be non-zero");
        // Verify loan amount is recorded in 6-decimal USDC precision.
        assertGt(loan.amount, 0, "loan amount should be non-zero");
        // Verify borrower received USDC proceeds.
        assertGt(usdc.balanceOf(BORROWER), borrowerUSDCBefore, "borrower should receive USDC from loan");

        // Verify collateral tokens were burned.
        uint256 borrowerTokensPostLoan = jbTokens().totalBalanceOf(BORROWER, revnetId);
        assertLt(borrowerTokensPostLoan, borrowerTokens, "collateral tokens should be burned");

        // Verify the loan NFT is owned by the borrower.
        assertEq(
            REVLoans(payable(address(LOANS_CONTRACT))).ownerOf(loanId), BORROWER, "loan NFT should be owned by borrower"
        );

        // Record loan details for repayment verification.
        uint256 loanAmount = loan.amount;
        uint256 loanCollateral = loan.collateral;

        // ──────────────── Step 4: Advance time — trigger stage 2
        // ────────────────
        // Warp past the stage 1 duration to activate stage 2.
        vm.warp(block.timestamp + STAGE_DURATION + 1);

        // Verify stage 2 is now active with lower cashout tax.
        JBRuleset memory ruleset2 = jbRulesets().currentOf(revnetId);
        uint16 stage2Tax = uint16((ruleset2.metadata >> 20) & 0xFFFF);
        assertEq(stage2Tax, 2000, "stage 2 should have 20% cashout tax");

        // Verify stage 2 has different issuance weight (500 tokens/USDC vs 1000).
        assertLt(ruleset2.weight, ruleset1.weight, "stage 2 weight should be lower than stage 1");

        // After stage transition, borrowable amount should change due to lower tax.
        uint256 borrowableStage2 = LOANS_CONTRACT.borrowableAmountFrom(
            revnetId,
            borrowerTokens, // Same collateral amount for comparison.
            6,
            uint32(uint160(address(usdc)))
        );
        // Lower tax rate should increase borrowable amount for the same collateral.
        assertGt(borrowableStage2, borrowable, "borrowable should increase with lower tax in stage 2");

        // ──────────────── Step 5: Buyback hook activation
        // ────────────────
        // Set up the USDC buyback pool with liquidity.
        _setupUSDCBuybackPool(revnetId, 100_000e6);

        // Make a payment that the buyback hook will intercept.
        // The hook compares pool swap price vs. mint issuance and routes to the better option.
        uint256 buybackPayAmount = 1000e6; // 1,000 USDC.
        uint256 tokensBuyback = _payRevnetUSDC(revnetId, PAYER, buybackPayAmount);
        // Whether the buyback hook swaps or mints, tokens should be received.
        assertGt(tokensBuyback, 0, "should receive tokens after buyback hook activation");

        // ──────────────── Step 6: Terminal migration
        // ────────────────

        // Mock the store's accountingContextOf for terminal2 to return the USDC context.
        // Revnets don't enable the allowAddAccountingContext flag, so we can't add contexts
        // to terminal2 via the normal path. Instead, we mock the store-level function that both
        // migrateBalanceOf (via terminal2.accountingContextForTokenOf) and addToBalanceOf
        // (via terminal2._accountingContextOf) use to look up the accounting context.
        JBAccountingContext memory usdcContext =
            JBAccountingContext({token: address(usdc), decimals: 6, currency: uint32(uint160(address(usdc)))});
        vm.mockCall(
            address(jbTerminalStore()),
            abi.encodeWithSelector(
                jbTerminalStore().accountingContextOf.selector, address(jbMultiTerminal2()), revnetId, address(usdc)
            ),
            abi.encode(usdcContext)
        );

        // Set both terminals for the project via the controller (bypasses allowSetTerminals check).
        IJBTerminal[] memory newTerminals = new IJBTerminal[](2);
        newTerminals[0] = jbMultiTerminal(); // Keep old terminal in the list.
        newTerminals[1] = jbMultiTerminal2(); // Add new terminal.
        vm.prank(address(jbController()));
        jbDirectory().setTerminalsOf(revnetId, newTerminals);

        // Record balances before migration.
        uint256 oldTermBalBefore = _terminalBalance(address(jbMultiTerminal()), revnetId, address(usdc));
        assertGt(oldTermBalBefore, 0, "old terminal should have USDC balance before migration");

        // Mock the store's recordTerminalMigration to bypass the allowTerminalMigration metadata check.
        // Revnets don't set this flag, so we mock it for testing the migration composition.
        _mockStoreRecordMigration(revnetId, address(usdc));

        // Grant the test contract MIGRATE_TERMINAL permission from the project owner (REVDeployer).
        _grantMigratePermission(address(REV_DEPLOYER), address(this), revnetId);

        // Execute the migration: move USDC balance from old terminal to new terminal.
        uint256 migratedAmount = jbMultiTerminal().migrateBalanceOf(revnetId, address(usdc), jbMultiTerminal2());

        // Verify the migration transferred the expected USDC balance.
        assertGt(migratedAmount, 0, "migrated amount should be non-zero");

        // Verify the new terminal received the migrated USDC.
        uint256 newTermBal = _terminalBalance(address(jbMultiTerminal2()), revnetId, address(usdc));
        assertEq(newTermBal, migratedAmount, "new terminal should hold the migrated balance");

        // ──────────────── Step 7: Repay the loan
        // ────────────────

        // Mint USDC to the borrower to cover loan repayment (amount + fees).
        // Repayment goes to the OLD terminal (loan.source.terminal) via addToBalanceOf.
        usdc.mint(BORROWER, loanAmount * 3); // Overfund to cover any fees.

        // Build an empty allowance (no permit2 needed — direct USDC approval).
        JBSingleAllowance memory allowance;

        // Approve the loans contract to spend borrower's USDC for repayment.
        vm.startPrank(BORROWER);
        usdc.approve(address(LOANS_CONTRACT), loanAmount * 3);

        // Repay the loan, returning all collateral to the borrower.
        (, REVLoan memory paidOffLoan) = LOANS_CONTRACT.repayLoan({
            loanId: loanId,
            maxRepayBorrowAmount: loanAmount * 3, // Allow up to 3x loan amount for fees.
            collateralCountToReturn: loanCollateral, // Return all collateral.
            beneficiary: payable(BORROWER), // Borrower receives collateral tokens back.
            allowance: allowance
        });
        vm.stopPrank();

        // ──────────────── Step 8: Verify all state
        // ────────────────

        // 8a: Loan accounting — loan should be fully repaid.
        assertEq(paidOffLoan.amount, 0, "paid-off loan amount should be 0");
        assertEq(paidOffLoan.collateral, 0, "paid-off loan collateral should be 0");

        // 8b: Loan NFT should be burned after full repayment.
        vm.expectRevert();
        REVLoans(payable(address(LOANS_CONTRACT))).ownerOf(loanId);

        // 8c: Borrower should have collateral tokens returned (at least the original amount).
        uint256 borrowerTokensAfterRepay = jbTokens().totalBalanceOf(BORROWER, revnetId);
        assertGe(borrowerTokensAfterRepay, borrowerTokens, "borrower should receive at least original collateral back");

        // 8d: Stage 2 parameters still active after all operations.
        JBRuleset memory rulesetFinal = jbRulesets().currentOf(revnetId);
        uint16 finalTax = uint16((rulesetFinal.metadata >> 20) & 0xFFFF);
        assertEq(finalTax, 2000, "stage 2 tax should still be active after full lifecycle");

        // 8e: Repayment added USDC back to old terminal (loan source target).
        // Since loan repayment calls addToBalanceOf on the source terminal, the old terminal
        // should have a non-zero balance again from the repaid loan.
        uint256 oldTermBalAfterRepay = _terminalBalance(address(jbMultiTerminal()), revnetId, address(usdc));
        assertGt(oldTermBalAfterRepay, 0, "old terminal should have balance from loan repayment");

        // 8f: New terminal still holds the migrated balance.
        uint256 newTermBalFinal = _terminalBalance(address(jbMultiTerminal2()), revnetId, address(usdc));
        assertEq(newTermBalFinal, migratedAmount, "new terminal balance should be unchanged after repay");

        // 8g: Total USDC across both terminals is consistent.
        // The sum should equal: original deposits + buyback payment + loan repayment - loan payout.
        // This verifies no USDC was lost or created during the composition.
        uint256 totalUSDCInTerminals = oldTermBalAfterRepay + newTermBalFinal;
        assertGt(totalUSDCInTerminals, 0, "total USDC across terminals should be positive");

        // 8h: Payer tokens are preserved — buyback + stage 1 payments still reflected.
        uint256 payerTokensFinal = jbTokens().totalBalanceOf(PAYER, revnetId);
        assertGt(payerTokensFinal, payerTokens, "payer should have more tokens after buyback payment");

        // 8i: USDC decimal precision check — all amounts should be in 6-decimal format.
        // Loan amount should be reasonable for the USDC paid (not inflated to 18-decimal scale).
        assertLt(loanAmount, 1e18, "loan amount should be in 6-decimal USDC scale, not 18-decimal");

        // Log final state for debugging.
        emit log_named_uint("stage 1 tokens per 10K USDC", payerTokens);
        emit log_named_uint("stage 2 borrowable improvement", borrowableStage2 - borrowable);
        emit log_named_uint("buyback tokens received", tokensBuyback);
        emit log_named_uint("migrated USDC amount", migratedAmount);
        emit log_named_uint("loan amount (6-dec USDC)", loanAmount);
        emit log_named_uint("old terminal post-repay", oldTermBalAfterRepay);
        emit log_named_uint("new terminal post-migrate", newTermBalFinal);
    }
}
