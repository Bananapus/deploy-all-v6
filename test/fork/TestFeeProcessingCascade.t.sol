// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBFee} from "@bananapus/core-v6/src/structs/JBFee.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {JBCurrencyAmount} from "@bananapus/core-v6/src/structs/JBCurrencyAmount.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBFeeTerminal} from "@bananapus/core-v6/src/interfaces/IJBFeeTerminal.sol";
import {JBFees} from "@bananapus/core-v6/src/libraries/JBFees.sol";

// Revnet
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// Base
import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";

/// @notice Fee processing cascade fork test.
///
/// Exercises the held fee lifecycle: fees are held during cashouts, accumulate over 28 days,
/// and are then processed to the fee beneficiary project (#1). Tests what happens when
/// fee processing succeeds and when it encounters edge cases.
///
/// Run with: forge test --match-contract TestFeeProcessingCascade -vvv
contract TestFeeProcessingCascade is RevnetForkBase {
    // -- Actors
    address PAYER2 = makeAddr("fee_payer2");

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_Fee";
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setUp() public override {
        super.setUp();

        // Mock geomean oracle.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Re-assign PAYER with fee-specific label and fund actors.
        PAYER = makeAddr("fee_payer");
        vm.deal(PAYER, 200 ether);
        vm.deal(PAYER2, 100 ether);
    }

    // ===================================================================
    //  Helpers
    // ===================================================================

    /// @notice Launch a project with holdFees enabled for testing fee lifecycle.
    function _launchHeldFeeProject() internal returns (uint256 projectId) {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Payout limit: 5 ETH (so payouts generate fees).
        JBFundAccessLimitGroup[] memory limits = new JBFundAccessLimitGroup[](1);
        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1);
        payoutLimits[0] =
            JBCurrencyAmount({amount: uint224(5 ether), currency: uint32(uint160(JBConstants.NATIVE_TOKEN))});
        limits[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: payoutLimits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });

        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](1);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(this)),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });
        splitGroups[0] = JBSplitGroup({groupId: uint256(uint160(JBConstants.NATIVE_TOKEN)), splits: splits});

        JBRulesetMetadata memory metadata = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: false,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: true, // Enable fee holding
            useTotalSurplusForCashOuts: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: uint112(INITIAL_ISSUANCE),
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: metadata,
            splitGroups: splitGroups,
            fundAccessLimitGroups: limits
        });

        projectId = jbController()
            .launchProjectFor({
            owner: address(this),
            projectUri: "ipfs://fee-held",
            rulesetConfigurations: rulesets,
            terminalConfigurations: tc,
            memo: ""
        });
    }

    // ===================================================================
    //  Tests
    // ===================================================================

    /// @notice Held fee lifecycle: create fees via payout, verify they are held, then process after 28 days.
    function test_fee_heldFeeLifecycle() public {
        _deployFeeProject(5000);
        uint256 projectId = _launchHeldFeeProject();

        // Pay 10 ETH to the project.
        vm.prank(PAYER);
        jbMultiTerminal().pay{value: 10 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 10 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Send payouts of 5 ETH. With holdFees=true, fees should be held rather than sent immediately.
        uint256 feeProjectBalanceBefore =
            jbTerminalStore().balanceOf(address(jbMultiTerminal()), FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            minTokensPaidOut: 0
        });

        // Fee = 5 ETH * 25/1000 = 0.125 ETH should be held.
        // Since holdFees is true, fee project balance should NOT increase yet.
        uint256 feeProjectBalanceAfterPayout =
            jbTerminalStore().balanceOf(address(jbMultiTerminal()), FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        // With holdFees, fees are not sent to fee project.
        assertEq(
            feeProjectBalanceAfterPayout, feeProjectBalanceBefore, "fee project balance should not change with holdFees"
        );

        // Check that held fees exist.
        JBFee[] memory heldFees = jbMultiTerminal().heldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);
        assertGt(heldFees.length, 0, "should have held fees");
        assertGt(heldFees[0].amount, 0, "held fee amount should be > 0");

        // Try to process held fees before unlock - they should remain locked.
        // The fees have a 28-day hold period.
        uint256 projectBalanceBefore = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        jbMultiTerminal().processHeldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);

        // Since fees are still locked, project balance should not change.
        uint256 projectBalanceAfterEarlyProcess = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        assertEq(
            projectBalanceAfterEarlyProcess,
            projectBalanceBefore,
            "project balance should not change when processing locked fees"
        );

        // Warp past the 28-day hold period.
        vm.warp(block.timestamp + 29 days);

        // Now process the held fees.
        jbMultiTerminal().processHeldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);

        // Fee project should now have received the fees.
        uint256 feeProjectBalanceAfterProcess =
            jbTerminalStore().balanceOf(address(jbMultiTerminal()), FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertGt(
            feeProjectBalanceAfterProcess, feeProjectBalanceBefore, "fee project should receive fees after processing"
        );

        // Held fees should be consumed.
        JBFee[] memory remainingFees = jbMultiTerminal().heldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);
        assertEq(remainingFees.length, 0, "no held fees should remain after processing");
    }

    /// @notice Cash-out fees: when a user cashes out (non-held), fees go to fee project immediately.
    function test_fee_cashOutFeesGoToFeeProject() public {
        _deployFeeProject(5000);

        // Deploy a revnet (non-held fees).
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
            cashOutTaxRate: 5000,
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("CashOutFee", "COF", "ipfs://cof", "COF_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("COF"))
        });

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay from two payers so bonding curve tax has effect.
        vm.prank(PAYER);
        jbMultiTerminal().pay{value: 10 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 10 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        vm.prank(PAYER2);
        jbMultiTerminal().pay{value: 5 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            beneficiary: PAYER2,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        uint256 feeBalanceBefore =
            jbTerminalStore().balanceOf(address(jbMultiTerminal()), FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        // Cash out PAYER's tokens.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);

        vm.prank(PAYER);
        uint256 reclaimed = jbMultiTerminal()
            .cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: payerTokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        assertGt(reclaimed, 0, "should reclaim some ETH");

        // Fee project balance should increase from the cashout fee.
        uint256 feeBalanceAfter =
            jbTerminalStore().balanceOf(address(jbMultiTerminal()), FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertGt(feeBalanceAfter, feeBalanceBefore, "fee project balance should increase from cashout fee");
    }

    /// @notice Held fee return: when addToBalance is called with shouldReturnHeldFees=true,
    /// held fees are returned to the project's balance.
    function test_fee_heldFeeReturnViaAddToBalance() public {
        _deployFeeProject(5000);
        uint256 projectId = _launchHeldFeeProject();

        // Pay 10 ETH.
        vm.prank(PAYER);
        jbMultiTerminal().pay{value: 10 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 10 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Send payouts of 5 ETH. Fees held (~0.125 ETH).
        jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            minTokensPaidOut: 0
        });

        // Verify held fees exist.
        JBFee[] memory heldFees = jbMultiTerminal().heldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);
        assertGt(heldFees.length, 0, "should have held fees");

        uint256 projectBalanceBefore = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);

        // Add to balance with shouldReturnHeldFees=true to return held fees.
        jbMultiTerminal().addToBalanceOf{value: 1 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            shouldReturnHeldFees: true,
            memo: "returning fees",
            metadata: ""
        });

        uint256 projectBalanceAfter = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);

        // Balance should increase by more than 1 ETH (the added amount plus returned held fees).
        uint256 increase = projectBalanceAfter - projectBalanceBefore;
        assertGt(increase, 1 ether, "balance increase should exceed 1 ETH due to returned held fees");

        // Held fees should have a reduced amount (partial return doesn't remove the entry,
        // it reduces its amount since only 1 ETH was returned against a 5 ETH held fee).
        JBFee[] memory remainingFees = jbMultiTerminal().heldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);
        assertEq(remainingFees.length, heldFees.length, "partial return keeps the entry");
        assertLt(remainingFees[0].amount, heldFees[0].amount, "held fee amount should decrease after partial return");
    }

    /// @notice Multiple payouts create multiple held fees; processing handles them correctly.
    function test_fee_multipleHeldFeesProcessedSequentially() public {
        _deployFeeProject(5000);

        // Launch project with a large payout limit so we can do multiple payouts.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBFundAccessLimitGroup[] memory limits = new JBFundAccessLimitGroup[](1);
        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1);
        payoutLimits[0] =
            JBCurrencyAmount({amount: uint224(50 ether), currency: uint32(uint160(JBConstants.NATIVE_TOKEN))});
        limits[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: payoutLimits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });

        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](1);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(this)),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });
        splitGroups[0] = JBSplitGroup({groupId: uint256(uint160(JBConstants.NATIVE_TOKEN)), splits: splits});

        JBRulesetMetadata memory metadata = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: false,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: true, // Enable fee holding
            useTotalSurplusForCashOuts: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 30 days, // Duration so we can cycle to a new ruleset.
            weight: uint112(INITIAL_ISSUANCE),
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: metadata,
            splitGroups: splitGroups,
            fundAccessLimitGroups: limits
        });

        uint256 projectId = jbController()
            .launchProjectFor({
            owner: address(this),
            projectUri: "ipfs://multi-fee",
            rulesetConfigurations: rulesets,
            terminalConfigurations: tc,
            memo: ""
        });

        // Pay 100 ETH.
        vm.prank(PAYER);
        jbMultiTerminal().pay{value: 100 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 100 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Send first payout of 5 ETH (creates first held fee).
        jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            minTokensPaidOut: 0
        });

        // Advance time by 1 day.
        vm.warp(block.timestamp + 1 days);

        // Send second payout of 3 ETH (creates second held fee with later unlock).
        jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 3 ether,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            minTokensPaidOut: 0
        });

        // Check we have 2 held fees.
        JBFee[] memory heldFees = jbMultiTerminal().heldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);
        assertEq(heldFees.length, 2, "should have 2 held fees from 2 payouts");

        // Different unlock timestamps.
        assertLt(heldFees[0].unlockTimestamp, heldFees[1].unlockTimestamp, "first fee should unlock before second");

        // Warp past the first fee's unlock but before the second.
        vm.warp(heldFees[0].unlockTimestamp + 1);

        uint256 feeBalanceBefore =
            jbTerminalStore().balanceOf(address(jbMultiTerminal()), FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        // Process 1 fee.
        jbMultiTerminal().processHeldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 1);

        uint256 feeBalanceAfterFirst =
            jbTerminalStore().balanceOf(address(jbMultiTerminal()), FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertGt(feeBalanceAfterFirst, feeBalanceBefore, "fee project should receive first fee");

        // Second fee should still be held.
        JBFee[] memory feesAfterFirst = jbMultiTerminal().heldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);
        assertEq(feesAfterFirst.length, 1, "should have 1 held fee remaining");

        // Warp past the second fee's unlock.
        vm.warp(heldFees[1].unlockTimestamp + 1);

        // Process remaining fee.
        jbMultiTerminal().processHeldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 1);

        uint256 feeBalanceAfterSecond =
            jbTerminalStore().balanceOf(address(jbMultiTerminal()), FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertGt(feeBalanceAfterSecond, feeBalanceAfterFirst, "fee project should receive second fee");

        // All fees processed.
        JBFee[] memory feesAfterAll = jbMultiTerminal().heldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);
        assertEq(feesAfterAll.length, 0, "all held fees should be processed");
    }

    /// @notice When the fee terminal reverts during fee processing (holdFees=false),
    /// the FeeReverted event is emitted and the fee amount is returned to the project's balance.
    function test_fee_revertingFeeTerminalReturnsFundsToProject() public {
        // 1. Deploy the fee project (project 1) with a terminal.
        _deployFeeProject(5000);

        // 2. Launch a second project (project 2) with holdFees: false so fees process immediately.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Payout limit: 5 ETH.
        JBFundAccessLimitGroup[] memory limits = new JBFundAccessLimitGroup[](1);
        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1);
        payoutLimits[0] =
            JBCurrencyAmount({amount: uint224(5 ether), currency: uint32(uint160(JBConstants.NATIVE_TOKEN))});
        limits[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: payoutLimits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });

        // Splits: 100% to this contract (so all payout goes through splits, generating fees).
        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](1);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(this)),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });
        splitGroups[0] = JBSplitGroup({groupId: uint256(uint160(JBConstants.NATIVE_TOKEN)), splits: splits});

        JBRulesetMetadata memory metadata = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: false,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: false, // Fees process immediately — no holding.
            useTotalSurplusForCashOuts: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: uint112(INITIAL_ISSUANCE),
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: metadata,
            splitGroups: splitGroups,
            fundAccessLimitGroups: limits
        });

        uint256 projectId = jbController()
            .launchProjectFor({
            owner: address(this),
            projectUri: "ipfs://fee-revert-test",
            rulesetConfigurations: rulesets,
            terminalConfigurations: tc,
            memo: ""
        });

        // 3. Fund project 2 with 10 ETH.
        vm.prank(PAYER);
        jbMultiTerminal().pay{value: 10 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 10 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Record balances before the payout.
        uint256 projectBalanceBefore = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        uint256 feeProjectBalanceBefore = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        // 4. Mock the terminal's executeProcessFee to REVERT.
        // _processFee calls this.executeProcessFee(...) via an external call wrapped in try-catch.
        // By making executeProcessFee revert, the catch block fires, emitting FeeReverted and
        // returning the fee amount to the project's balance.
        vm.mockCallRevert(
            address(jbMultiTerminal()),
            abi.encodeWithSelector(jbMultiTerminal().executeProcessFee.selector),
            "FEE_TERMINAL_BROKEN"
        );

        // 5. Send payouts of 5 ETH, which generates fees.
        // With holdFees=false, _takeFeeFrom calls _processFee immediately.
        // The fee = 5 ETH * 25 / 1000 = 0.125 ETH.
        uint256 expectedFee = JBFees.feeAmountFrom({amountBeforeFee: 5 ether, feePercent: jbMultiTerminal().FEE()});
        assertGt(expectedFee, 0, "expected fee should be non-zero");

        // 6. Expect the FeeReverted event.
        vm.expectEmit(true, true, true, false);
        emit IJBFeeTerminal.FeeReverted({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            feeProjectId: FEE_PROJECT_ID,
            amount: expectedFee,
            reason: "", // We don't check the exact reason bytes.
            caller: address(0) // We don't check the exact caller.
        });

        jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            minTokensPaidOut: 0
        });

        // Clear the mock so subsequent calls work normally.
        vm.clearMockedCalls();

        // 7. Verify: fee project balance did NOT increase (fee payment reverted).
        uint256 feeProjectBalanceAfter = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertEq(
            feeProjectBalanceAfter,
            feeProjectBalanceBefore,
            "fee project balance should not increase when fee terminal reverts"
        );

        // 8. Verify: fee amount was returned to project 2's balance.
        // After the 5 ETH payout, the project's balance should be:
        //   10 ETH (initial) - 5 ETH (payout) = 5 ETH remaining
        // But since the fee reverted, the fee amount is returned to the project balance:
        //   5 ETH + expectedFee = the project's balance
        uint256 projectBalanceAfter = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        uint256 expectedBalanceAfterPayout = projectBalanceBefore - 5 ether + expectedFee;
        assertEq(
            projectBalanceAfter,
            expectedBalanceAfterPayout,
            "fee amount should be returned to project balance when fee terminal reverts"
        );

        // Sanity: the fee amount that was returned is meaningful (not dust).
        assertGt(expectedFee, 0.1 ether, "fee should be at least 0.1 ETH for a 5 ETH payout at 2.5%");
    }
}
