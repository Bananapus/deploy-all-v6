// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {JBCurrencyAmount} from "@bananapus/core-v6/src/structs/JBCurrencyAmount.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

// Revnet
import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";
import {REVLoanSource} from "@rev-net/core-v6/src/structs/REVLoanSource.sol";

// Base
import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";

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
contract TestTerminalMigration is RevnetForkBase {
    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_Migration";
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setUp() public override {
        super.setUp();

        // Mock geomean oracle.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
    }

    // ===================================================================
    //  Helpers
    // ===================================================================

    /// @notice Launch a plain JB project with migration-friendly flags and both terminals pre-configured.
    /// Uses allowTerminalMigration, allowSetTerminals, allowOwnerMinting, and scopeCashOutsToLocalBalances.
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
            scopeCashOutsToLocalBalances: false,
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
                // forge-lint: disable-next-line(unsafe-typecast)
                operator: address(LOANS_CONTRACT),
                // forge-lint: disable-next-line(unsafe-typecast)
                projectId: uint64(projectId),
                permissionIds: loanPermissionIds
            })
            );
    }

    /// @notice Query balance for a specific terminal (migration tests need to check both terminals).
    function _terminalBalanceOf(address terminal, uint256 projectId, address token) internal view returns (uint256) {
        return jbTerminalStore().balanceOf(terminal, projectId, token);
    }

    // ===================================================================
    //  Tests
    // ===================================================================

    /// @notice Migrate terminal with balance: verify full balance transfer.
    function test_mig_balanceTransferOnMigration() public {
        _deployFeeProject(5000);
        uint256 projectId = _launchMigrationProject();

        // Pay into the project via terminal 1.
        _payRevnet(projectId, PAYER, 10 ether);
        _payRevnet(projectId, BORROWER, 5 ether);

        uint256 balanceBefore = _terminalBalanceOf(address(jbMultiTerminal()), projectId, JBConstants.NATIVE_TOKEN);
        assertEq(balanceBefore, 15 ether, "terminal 1 should have 15 ETH");

        // Migrate balance from terminal 1 to terminal 2.
        // address(this) is the project owner.
        uint256 migrated = jbMultiTerminal().migrateBalanceOf(projectId, JBConstants.NATIVE_TOKEN, jbMultiTerminal2());

        // Verify migration transferred the full balance.
        assertEq(migrated, balanceBefore, "migrated amount should equal original balance");
        assertEq(
            _terminalBalanceOf(address(jbMultiTerminal()), projectId, JBConstants.NATIVE_TOKEN),
            0,
            "terminal 1 should have 0 balance after migration"
        );
        // Migration to a non-feeless terminal incurs a 2.5% fee.
        uint256 feeAmount = balanceBefore * 25 / 1000;
        assertEq(
            _terminalBalanceOf(address(jbMultiTerminal2()), projectId, JBConstants.NATIVE_TOKEN),
            balanceBefore - feeAmount,
            "terminal 2 should have balance minus 2.5% migration fee"
        );
    }

    /// @notice Migrate terminal during active loan: verify borrowable amount consistency.
    function test_mig_loanConsistencyAfterMigration() public {
        _deployFeeProject(5000);
        uint256 projectId = _launchMigrationProject();

        // Pay and create a loan.
        _payRevnet(projectId, PAYER, 10 ether);
        _payRevnet(projectId, BORROWER, 5 ether);

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
        // Since the project uses scopeCashOutsToLocalBalances, borrowable should be consistent.
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
        _payRevnet(projectId, PAYER, 10 ether);

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
        uint256 t2Balance = _terminalBalanceOf(address(jbMultiTerminal2()), projectId, JBConstants.NATIVE_TOKEN);
        assertEq(
            t2Balance,
            10 ether - feeOnMigration + 5 ether,
            "terminal 2 should have 14.75 ETH (10 migrated minus fee + 5 new)"
        );
    }
}
