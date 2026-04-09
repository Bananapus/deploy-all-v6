// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

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
import {REVHiddenTokens} from "@rev-net/core-v6/src/REVHiddenTokens.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";
import {IREVLoans} from "@rev-net/core-v6/src/interfaces/IREVLoans.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";
import {REVLoanSource} from "@rev-net/core-v6/src/structs/REVLoanSource.sol";

// Uniswap V4
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @notice Terminal migration fork test during active REVLoans.
///
/// Verifies that migrating a project's balance from one terminal to another
/// properly transfers balances, that loan collateral values remain consistent,
/// and that loan repayment still works after migration.
///
/// Uses a plain JB project (not a revnet) for the migrated project because revnets
/// do not enable the allowTerminalMigration / allowAddAccountingContext / allowSetTerminals
/// flags. The fee project is still deployed as a revnet via REVDeployer.
///
/// Run with: forge test --match-contract TestTerminalMigration -vvv
contract TestTerminalMigration is TestBaseWorkflow {
    // -- Mainnet addresses
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    // -- Test parameters
    uint112 constant INITIAL_ISSUANCE = uint112(1000e18);

    // -- Actors
    address PAYER = makeAddr("mig_payer");
    address BORROWER = makeAddr("mig_borrower");

    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // -- Ecosystem contracts
    IPoolManager poolManager;

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

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setUp() public override {
        vm.createSelectFork("ethereum", 21_700_000);
        require(POOL_MANAGER_ADDR.code.length > 0, "PoolManager not deployed");

        super.setUp();

        poolManager = IPoolManager(POOL_MANAGER_ADDR);

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

        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_Mig"}(
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

    /// @notice Launch a plain JB project with migration-friendly flags and both terminals pre-configured.
    /// Uses allowTerminalMigration, allowSetTerminals, allowOwnerMinting, and useTotalSurplusForCashOuts.
    function _launchMigrationProject() internal returns (uint256 projectId) {
        // Accounting context for ETH on both terminals.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });

        // Include both terminals from the start so accounting contexts are set before rulesets.
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](2);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});
        tc[1] = JBTerminalConfig({terminal: jbMultiTerminal2(), accountingContextsToAccept: acc});

        // Splits: 100% to multisig.
        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](1);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(multisig()),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });
        splitGroups[0] = JBSplitGroup({groupId: uint256(uint160(JBConstants.NATIVE_TOKEN)), splits: splits});

        // Surplus allowances: unlimited for loan operations (REVLoans uses useAllowanceOf).
        JBFundAccessLimitGroup[] memory limits = new JBFundAccessLimitGroup[](2);
        JBCurrencyAmount[] memory surplusAllowances = new JBCurrencyAmount[](1);
        surplusAllowances[0] =
            JBCurrencyAmount({amount: type(uint224).max, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))});
        limits[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: new JBCurrencyAmount[](0),
            surplusAllowances: surplusAllowances
        });
        limits[1] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal2()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: new JBCurrencyAmount[](0),
            surplusAllowances: surplusAllowances
        });

        JBRulesetMetadata memory metadata = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 5000,
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: true,
            allowSetTerminals: true,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: false,
            useTotalSurplusForCashOuts: true,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: INITIAL_ISSUANCE,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: metadata,
            splitGroups: splitGroups,
            fundAccessLimitGroups: limits
        });

        projectId = jbController()
            .launchProjectFor({
                owner: address(this),
                projectUri: "ipfs://mig-test",
                rulesetConfigurations: rulesets,
                terminalConfigurations: tc,
                memo: ""
            });

        // Deploy an ERC-20 token for this project so REVLoans can burn/mint.
        jbController().deployERC20For({projectId: projectId, name: "MigTest", symbol: "MIG", salt: bytes32(0)});

        // Grant MINT_TOKENS and USE_ALLOWANCE permissions to LOANS_CONTRACT.
        // MINT_TOKENS: so it can re-mint collateral on repay.
        // USE_ALLOWANCE: so it can pull loan funds from the terminal's surplus.
        uint8[] memory loanPermissionIds = new uint8[](2);
        loanPermissionIds[0] = 10; // MINT_TOKENS
        loanPermissionIds[1] = 18; // USE_ALLOWANCE
        jbPermissions()
            .setPermissionsFor(
                address(this),
                JBPermissionsData({
                    operator: address(LOANS_CONTRACT), projectId: uint64(projectId), permissionIds: loanPermissionIds
                })
            );
    }

    function _payProject(uint256 projectId, address payer, uint256 amount) internal returns (uint256 tokensReceived) {
        vm.prank(payer);
        tokensReceived = jbMultiTerminal().pay{value: amount}({
            projectId: projectId,
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

    function _grantBurnPermission(address account, uint256 projectId) internal {
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 11; // BURN_TOKENS
        vm.prank(account);
        jbPermissions()
            .setPermissionsFor(
                account,
                JBPermissionsData({
                    operator: address(LOANS_CONTRACT), projectId: uint64(projectId), permissionIds: permissionIds
                })
            );
    }

    // ===================================================================
    //  Tests
    // ===================================================================

    /// @notice Migrate terminal with balance: verify full balance transfer.
    function test_mig_balanceTransferOnMigration() public {
        _deployFeeProject(5000);
        uint256 projectId = _launchMigrationProject();

        // Pay into the project via terminal 1.
        _payProject(projectId, PAYER, 10 ether);
        _payProject(projectId, BORROWER, 5 ether);

        uint256 balanceBefore = _terminalBalance(address(jbMultiTerminal()), projectId, JBConstants.NATIVE_TOKEN);
        assertEq(balanceBefore, 15 ether, "terminal 1 should have 15 ETH");

        // Migrate balance from terminal 1 to terminal 2.
        // address(this) is the project owner.
        uint256 migrated = jbMultiTerminal().migrateBalanceOf(projectId, JBConstants.NATIVE_TOKEN, jbMultiTerminal2());

        // Verify migration transferred the full balance.
        assertEq(migrated, balanceBefore, "migrated amount should equal original balance");
        assertEq(
            _terminalBalance(address(jbMultiTerminal()), projectId, JBConstants.NATIVE_TOKEN),
            0,
            "terminal 1 should have 0 balance after migration"
        );
        // Migration to a non-feeless terminal incurs a 2.5% fee.
        uint256 feeAmount = balanceBefore * 25 / 1000;
        assertEq(
            _terminalBalance(address(jbMultiTerminal2()), projectId, JBConstants.NATIVE_TOKEN),
            balanceBefore - feeAmount,
            "terminal 2 should have balance minus 2.5% migration fee"
        );
    }

    /// @notice Migrate terminal during active loan: verify borrowable amount consistency.
    function test_mig_loanConsistencyAfterMigration() public {
        _deployFeeProject(5000);
        uint256 projectId = _launchMigrationProject();

        // Pay and create a loan.
        _payProject(projectId, PAYER, 10 ether);
        _payProject(projectId, BORROWER, 5 ether);

        uint256 borrowerTokens = jbTokens().totalBalanceOf(BORROWER, projectId);
        _grantBurnPermission(BORROWER, projectId);

        REVLoanSource memory source = REVLoanSource({token: JBConstants.NATIVE_TOKEN, terminal: jbMultiTerminal()});

        // Check borrowable amount before migration.
        uint256 borrowableBefore = LOANS_CONTRACT.borrowableAmountFrom(
            projectId, borrowerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))
        );
        assertGt(borrowableBefore, 0, "should have borrowable amount before migration");

        // Create loan.
        vm.startPrank(BORROWER);
        (uint256 loanId, REVLoan memory loan) = LOANS_CONTRACT.borrowFrom({
            revnetId: projectId,
            source: source,
            minBorrowAmount: 0,
            collateralCount: borrowerTokens,
            beneficiary: payable(BORROWER),
            prepaidFeePercent: LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT(),
            holder: BORROWER
        });
        vm.stopPrank();

        assertGt(loanId, 0, "loan should be created");

        // Migrate the terminal. Both terminals were configured at launch.
        uint256 migrated = jbMultiTerminal().migrateBalanceOf(projectId, JBConstants.NATIVE_TOKEN, jbMultiTerminal2());
        assertGt(migrated, 0, "should migrate non-zero balance");

        // After migration, the surplus is now in terminal 2.
        // Since the project uses useTotalSurplusForCashOuts, borrowable should be consistent.
        uint256 borrowableAfter = LOANS_CONTRACT.borrowableAmountFrom(
            projectId, borrowerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))
        );

        // The key invariant: borrowable should still be > 0 even after migration.
        assertGt(borrowableAfter, 0, "borrowable should remain > 0 after terminal migration");

        // Repay the loan using ETH.
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
            jbTokens().totalBalanceOf(BORROWER, projectId),
            borrowerTokens,
            "collateral should be returned after repay post-migration"
        );
    }

    /// @notice Verify that payments into the new terminal work after migration.
    function test_mig_paymentToNewTerminalAfterMigration() public {
        _deployFeeProject(5000);
        uint256 projectId = _launchMigrationProject();

        // Initial payment to terminal 1.
        _payProject(projectId, PAYER, 10 ether);

        // Migrate balance from terminal 1 to terminal 2.
        jbMultiTerminal().migrateBalanceOf(projectId, JBConstants.NATIVE_TOKEN, jbMultiTerminal2());

        // Set terminal 2 as primary.
        jbDirectory().setPrimaryTerminalOf(projectId, JBConstants.NATIVE_TOKEN, jbMultiTerminal2());

        // Pay into terminal 2.
        uint256 payerTokensBefore = jbTokens().totalBalanceOf(PAYER, projectId);
        vm.prank(PAYER);
        uint256 newTokens = jbMultiTerminal2().pay{value: 5 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        assertGt(newTokens, 0, "should receive tokens when paying into new terminal");
        assertGt(jbTokens().totalBalanceOf(PAYER, projectId), payerTokensBefore, "payer token balance should increase");

        // Terminal 2 balance should reflect migration (minus 2.5% fee) and new payment.
        uint256 feeOnMigration = 10 ether * 25 / 1000;
        uint256 t2Balance = _terminalBalance(address(jbMultiTerminal2()), projectId, JBConstants.NATIVE_TOKEN);
        assertEq(
            t2Balance,
            10 ether - feeOnMigration + 5 ether,
            "terminal 2 should have 14.75 ETH (10 migrated minus fee + 5 new)"
        );
    }
}
