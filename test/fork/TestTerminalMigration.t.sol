// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";

// 721 Hook
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHookStore} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookStore.sol";

// Address Registry
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// Buyback Hook
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";
import {IGeomeanOracle} from "@bananapus/buyback-hook-v6/src/interfaces/IGeomeanOracle.sol";

// Suckers
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// Croptop
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";

// Revnet
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {IREVLoans} from "@rev-net/core-v6/src/interfaces/IREVLoans.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";
import {REVLoanSource} from "@rev-net/core-v6/src/structs/REVLoanSource.sol";

// Uniswap V4
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Adds liquidity to a V4 pool via unlock/callback pattern.
contract MigrationLiquidityHelper is IUnlockCallback {
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

/// @notice Terminal migration fork test during active REVLoans.
///
/// Verifies that migrating a project's balance from one terminal to another
/// properly transfers balances, that loan collateral values remain consistent,
/// and that loan repayment still works after migration.
///
/// Run with: forge test --match-contract TestTerminalMigration -vvv
contract TestTerminalMigration is TestBaseWorkflow {
    // -- Mainnet addresses
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    // -- Tick range for full-range liquidity
    int24 constant TICK_LOWER = -887_200;
    int24 constant TICK_UPPER = 887_200;

    // -- Test parameters
    uint112 constant INITIAL_ISSUANCE = uint112(1000e18);

    // -- Actors
    address PAYER = makeAddr("mig_payer");
    address BORROWER = makeAddr("mig_borrower");

    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // -- Ecosystem contracts
    IPoolManager poolManager;
    MigrationLiquidityHelper liqHelper;

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

    receive() external payable {}

    function setUp() public override {
        vm.createSelectFork("ethereum", 21_700_000);
        require(POOL_MANAGER_ADDR.code.length > 0, "PoolManager not deployed");

        super.setUp();

        poolManager = IPoolManager(POOL_MANAGER_ADDR);
        liqHelper = new MigrationLiquidityHelper(poolManager);

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
            projects: jbProjects(),
            revId: FEE_PROJECT_ID,
            owner: address(this),
            permit2: permit2(),
            trustedForwarder: TRUSTED_FORWARDER
        });

        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_Mig"}(
            jbController(),
            SUCKER_REGISTRY,
            FEE_PROJECT_ID,
            HOOK_DEPLOYER,
            PUBLISHER,
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            address(LOANS_CONTRACT),
            TRUSTED_FORWARDER
        );

        vm.prank(multisig());
        jbProjects().approve(address(REV_DEPLOYER), FEE_PROJECT_ID);

        // Mock geomean oracle.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Fund actors.
        vm.deal(PAYER, 100 ether);
        vm.deal(BORROWER, 100 ether);
    }

    // ===================================================================
    //  Helpers
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
            description: REVDescription("Fee", "FEE", "ipfs://fee", "FEE_MIG"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("FEE_MIG"))
        });

        vm.prank(multisig());
        REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

    function _buildMigrationConfig()
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

        cfg = REVConfig({
            description: REVDescription("MigTest", "MIG", "ipfs://mig", "MIG_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("MIG"))
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

    function _terminalBalance(address terminal, uint256 projectId, address token) internal view returns (uint256) {
        return jbTerminalStore().balanceOf(terminal, projectId, token);
    }

    function _grantBurnPermission(address account, uint256 revnetId) internal {
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 11; // BURN_TOKENS
        vm.prank(account);
        jbPermissions()
            .setPermissionsFor(
                account,
                JBPermissionsData({
                    operator: address(LOANS_CONTRACT), projectId: uint64(revnetId), permissionIds: permissionIds
                })
            );
    }

    function _setupPool(uint256 revnetId, uint256 liquidityTokenAmount) internal {
        address projectToken = address(jbTokens().tokenOf(revnetId));
        require(projectToken != address(0), "project token not deployed");

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(projectToken),
            fee: REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(),
            tickSpacing: REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(),
            hooks: IHooks(address(0))
        });

        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, liquidityTokenAmount * 50);
        vm.deal(address(liqHelper), liquidityTokenAmount);

        vm.prank(address(liqHelper));
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);

        int256 liquidityDelta = int256(liquidityTokenAmount / 50);
        vm.prank(address(liqHelper));
        liqHelper.addLiquidity{value: liquidityTokenAmount}(key, TICK_LOWER, TICK_UPPER, liquidityDelta);

        _mockOracle(liquidityDelta, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
    }

    // ===================================================================
    //  Tests
    // ===================================================================

    /// @notice Migrate terminal with balance: verify full balance transfer.
    function test_mig_balanceTransferOnMigration() public {
        _deployFeeProject(5000);
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildMigrationConfig();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupPool(revnetId, 10_000 ether);

        // Pay into the revnet.
        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        uint256 balanceBefore = _terminalBalance(address(jbMultiTerminal()), revnetId, JBConstants.NATIVE_TOKEN);
        assertEq(balanceBefore, 15 ether, "terminal 1 should have 15 ETH");

        // Add the second terminal to the project's terminal list.
        // The REVDeployer is the project's controller, so it has control.
        // We need to add jbMultiTerminal2 as an accepted terminal with accounting context.
        JBAccountingContext[] memory acc2 = new JBAccountingContext[](1);
        acc2[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        vm.prank(address(REV_DEPLOYER));
        jbMultiTerminal2().addAccountingContextsFor(revnetId, acc2);

        // Set terminals to include both.
        IJBTerminal[] memory terminals = new IJBTerminal[](2);
        terminals[0] = jbMultiTerminal();
        terminals[1] = jbMultiTerminal2();
        vm.prank(address(REV_DEPLOYER));
        jbDirectory().setTerminalsOf(revnetId, terminals);

        // Migrate balance from terminal 1 to terminal 2.
        // The project owner (REV_DEPLOYER's generated project owner) needs MIGRATE_TERMINAL permission.
        // For revnets, REV_DEPLOYER is the owner of the project NFT in the context of the REVDeployer.
        // We use the multisig since that's who owns the project NFT indirectly.
        // Actually for revnets, the project owner is the REV_DEPLOYER itself. Let's check and prank accordingly.
        address projectOwner = jbProjects().ownerOf(revnetId);

        vm.prank(projectOwner);
        uint256 migrated = jbMultiTerminal().migrateBalanceOf(revnetId, JBConstants.NATIVE_TOKEN, jbMultiTerminal2());

        // Verify migration transferred the full balance.
        assertEq(migrated, balanceBefore, "migrated amount should equal original balance");
        assertEq(
            _terminalBalance(address(jbMultiTerminal()), revnetId, JBConstants.NATIVE_TOKEN),
            0,
            "terminal 1 should have 0 balance after migration"
        );
        assertEq(
            _terminalBalance(address(jbMultiTerminal2()), revnetId, JBConstants.NATIVE_TOKEN),
            balanceBefore,
            "terminal 2 should have full balance after migration"
        );
    }

    /// @notice Migrate terminal during active loan: verify borrowable amount consistency.
    function test_mig_loanConsistencyAfterMigration() public {
        _deployFeeProject(5000);
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildMigrationConfig();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupPool(revnetId, 10_000 ether);

        // Pay and create a loan.
        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        uint256 borrowerTokens = jbTokens().totalBalanceOf(BORROWER, revnetId);
        _grantBurnPermission(BORROWER, revnetId);

        REVLoanSource memory source = REVLoanSource({token: JBConstants.NATIVE_TOKEN, terminal: jbMultiTerminal()});

        // Check borrowable amount before migration.
        uint256 borrowableBefore = LOANS_CONTRACT.borrowableAmountFrom(
            revnetId, borrowerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))
        );
        assertGt(borrowableBefore, 0, "should have borrowable amount before migration");

        // Create loan.
        vm.startPrank(BORROWER);
        (uint256 loanId, REVLoan memory loan) = LOANS_CONTRACT.borrowFrom({
            revnetId: revnetId,
            source: source,
            minBorrowAmount: 0,
            collateralCount: borrowerTokens,
            beneficiary: payable(BORROWER),
            prepaidFeePercent: LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT()
        });
        vm.stopPrank();

        assertGt(loanId, 0, "loan should be created");

        // Now migrate the terminal.
        JBAccountingContext[] memory acc2 = new JBAccountingContext[](1);
        acc2[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        vm.prank(address(REV_DEPLOYER));
        jbMultiTerminal2().addAccountingContextsFor(revnetId, acc2);

        IJBTerminal[] memory terminals = new IJBTerminal[](2);
        terminals[0] = jbMultiTerminal();
        terminals[1] = jbMultiTerminal2();
        vm.prank(address(REV_DEPLOYER));
        jbDirectory().setTerminalsOf(revnetId, terminals);

        address projectOwner = jbProjects().ownerOf(revnetId);
        vm.prank(projectOwner);
        uint256 migrated = jbMultiTerminal().migrateBalanceOf(revnetId, JBConstants.NATIVE_TOKEN, jbMultiTerminal2());
        assertGt(migrated, 0, "should migrate non-zero balance");

        // After migration, the surplus is now in terminal 2.
        // The loan still references terminal 1 as its source.
        // Check that borrowable amount is recalculated based on the new surplus distribution.
        // Since the revnet uses total surplus across all terminals (useTotalSurplusForCashOuts),
        // the loan collateral value should be consistent.
        uint256 borrowableAfter = LOANS_CONTRACT.borrowableAmountFrom(
            revnetId, borrowerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))
        );

        // Borrowable should be approximately the same (or slightly different due to loan impact on surplus).
        // The key invariant: borrowable should still be > 0 even after migration.
        assertGt(borrowableAfter, 0, "borrowable should remain > 0 after terminal migration");

        // Repay the loan using ETH (loan source was terminal 1, but repayment goes to whatever terminal).
        vm.deal(BORROWER, 100 ether);
        JBSingleAllowance memory allowance;

        vm.startPrank(BORROWER);
        LOANS_CONTRACT.repayLoan{value: loan.amount * 2}({
            loanId: loanId,
            maxRepayBorrowAmount: loan.amount * 2,
            collateralCountToReturn: loan.collateral,
            beneficiary: payable(BORROWER),
            allowance: allowance
        });
        vm.stopPrank();

        // Collateral should be returned.
        assertGe(
            jbTokens().totalBalanceOf(BORROWER, revnetId),
            borrowerTokens,
            "collateral should be returned after repay post-migration"
        );
    }

    /// @notice Verify that payments into the new terminal work after migration.
    function test_mig_paymentToNewTerminalAfterMigration() public {
        _deployFeeProject(5000);
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildMigrationConfig();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupPool(revnetId, 10_000 ether);

        // Initial payment to terminal 1.
        _payRevnet(revnetId, PAYER, 10 ether);

        // Set up terminal 2 and migrate.
        JBAccountingContext[] memory acc2 = new JBAccountingContext[](1);
        acc2[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        vm.prank(address(REV_DEPLOYER));
        jbMultiTerminal2().addAccountingContextsFor(revnetId, acc2);

        IJBTerminal[] memory terminals = new IJBTerminal[](2);
        terminals[0] = jbMultiTerminal();
        terminals[1] = jbMultiTerminal2();
        vm.prank(address(REV_DEPLOYER));
        jbDirectory().setTerminalsOf(revnetId, terminals);

        address projectOwner = jbProjects().ownerOf(revnetId);
        vm.prank(projectOwner);
        jbMultiTerminal().migrateBalanceOf(revnetId, JBConstants.NATIVE_TOKEN, jbMultiTerminal2());

        // Set terminal 2 as primary.
        vm.prank(address(REV_DEPLOYER));
        jbDirectory().setPrimaryTerminalOf(revnetId, JBConstants.NATIVE_TOKEN, jbMultiTerminal2());

        // Pay into terminal 2.
        uint256 payerTokensBefore = jbTokens().totalBalanceOf(PAYER, revnetId);
        vm.prank(PAYER);
        uint256 newTokens = jbMultiTerminal2().pay{value: 5 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        assertGt(newTokens, 0, "should receive tokens when paying into new terminal");
        assertGt(jbTokens().totalBalanceOf(PAYER, revnetId), payerTokensBefore, "payer token balance should increase");

        // Terminal 2 balance should reflect both migration and new payment.
        uint256 t2Balance = _terminalBalance(address(jbMultiTerminal2()), revnetId, JBConstants.NATIVE_TOKEN);
        assertEq(t2Balance, 15 ether, "terminal 2 should have 15 ETH (10 migrated + 5 new)");
    }
}
