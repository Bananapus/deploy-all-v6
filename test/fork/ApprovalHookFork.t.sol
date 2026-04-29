// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {JBCurrencyAmount} from "@bananapus/core-v6/src/structs/JBCurrencyAmount.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";
import {JBApprovalStatus} from "@bananapus/core-v6/src/enums/JBApprovalStatus.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {JBDeadline} from "@bananapus/core-v6/src/JBDeadline.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Approval hook that always rejects queued rulesets.
contract AlwaysRejectApprovalHook is IJBRulesetApprovalHook {
    function DURATION() external pure override returns (uint256) {
        return 0;
    }

    function approvalStatusOf(uint256, JBRuleset memory) external pure override returns (JBApprovalStatus) {
        return JBApprovalStatus.Failed;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IJBRulesetApprovalHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

/// @notice Approval hook that reverts in approvalStatusOf — should be treated as Failed.
contract RevertingApprovalHook is IJBRulesetApprovalHook {
    function DURATION() external pure override returns (uint256) {
        return 0;
    }

    function approvalStatusOf(uint256, JBRuleset memory) external pure override returns (JBApprovalStatus) {
        revert("BOOM");
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IJBRulesetApprovalHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

/// @notice Tests that approval hook rejection causes fallback to the base ruleset.
///
/// Run with: forge test --match-contract ApprovalHookForkTest -vvv
contract ApprovalHookForkTest is TestBaseWorkflow {
    uint32 constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));
    uint112 constant BASE_WEIGHT = 1000e18; // 1000 tokens per ETH
    uint112 constant QUEUED_WEIGHT = 5000e18; // 5000 tokens per ETH (should never activate)
    uint32 constant CYCLE_DURATION = 7 days;

    address PAYER = makeAddr("payer");
    address PROJECT_OWNER = makeAddr("projectOwner");

    AlwaysRejectApprovalHook rejectHook;
    RevertingApprovalHook revertHook;

    uint256 projectId;

    receive() external payable {}

    function setUp() public override {
        super.setUp();

        rejectHook = new AlwaysRejectApprovalHook();
        revertHook = new RevertingApprovalHook();

        vm.deal(PAYER, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════════

    function _defaultMetadata() internal pure returns (JBRulesetMetadata memory) {
        return JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
            baseCurrency: NATIVE_CURRENCY,
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: false,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: false,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: false,
            useTotalSurplusForCashOuts: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });
    }

    function _terminalConfigs() internal view returns (JBTerminalConfig[] memory tc) {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});

        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});
    }

    /// @notice Launch a project with a 7-day cycle, the given approval hook, and a base weight of 1000 tokens/ETH.
    function _launchWithApprovalHook(IJBRulesetApprovalHook hook) internal returns (uint256) {
        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: CYCLE_DURATION,
            weight: BASE_WEIGHT,
            weightCutPercent: 0,
            approvalHook: hook,
            metadata: _defaultMetadata(),
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        return jbController()
            .launchProjectFor({
            owner: PROJECT_OWNER,
            projectUri: "test://approval-hook",
            rulesetConfigurations: rulesets,
            terminalConfigurations: _terminalConfigs(),
            memo: ""
        });
    }

    /// @notice Launch a project with a 7-day cycle and payout limits, plus the given approval hook.
    function _launchWithPayoutLimitAndHook(IJBRulesetApprovalHook hook, uint224 payoutLimit)
        internal
        returns (uint256)
    {
        JBCurrencyAmount[] memory limits = new JBCurrencyAmount[](1);
        limits[0] = JBCurrencyAmount({amount: payoutLimit, currency: NATIVE_CURRENCY});

        JBFundAccessLimitGroup[] memory groups = new JBFundAccessLimitGroup[](1);
        groups[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: limits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: CYCLE_DURATION,
            weight: BASE_WEIGHT,
            weightCutPercent: 0,
            approvalHook: hook,
            metadata: _defaultMetadata(),
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: groups
        });

        return jbController()
            .launchProjectFor({
            owner: PROJECT_OWNER,
            projectUri: "test://approval-hook-payout",
            rulesetConfigurations: rulesets,
            terminalConfigurations: _terminalConfigs(),
            memo: ""
        });
    }

    /// @notice Queue a new ruleset with a different weight. The queued ruleset has no approval hook of its own.
    function _queueNewWeight(uint256 _projectId, uint112 weight) internal {
        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: CYCLE_DURATION,
            weight: weight,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: _defaultMetadata(),
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        vm.prank(PROJECT_OWNER);
        jbController().queueRulesetsOf({projectId: _projectId, rulesetConfigurations: rulesets, memo: ""});
    }

    /// @notice Queue a new ruleset with a different weight AND higher payout limit.
    function _queueNewWeightAndPayout(uint256 _projectId, uint112 weight, uint224 payoutLimit) internal {
        JBCurrencyAmount[] memory limits = new JBCurrencyAmount[](1);
        limits[0] = JBCurrencyAmount({amount: payoutLimit, currency: NATIVE_CURRENCY});

        JBFundAccessLimitGroup[] memory groups = new JBFundAccessLimitGroup[](1);
        groups[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: limits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: CYCLE_DURATION,
            weight: weight,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: _defaultMetadata(),
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: groups
        });

        vm.prank(PROJECT_OWNER);
        jbController().queueRulesetsOf({projectId: _projectId, rulesetConfigurations: rulesets, memo: ""});
    }

    function _pay(uint256 _projectId, uint256 amount) internal returns (uint256 tokens) {
        vm.prank(PAYER);
        tokens = jbMultiTerminal().pay{value: amount}({
            projectId: _projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: amount,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Tests
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice When a queued ruleset is rejected by the approval hook, payments should use the base weight.
    function test_approvalRejection_fallsBackToBaseRuleset() public {
        // Launch with AlwaysRejectApprovalHook and base weight 1000.
        projectId = _launchWithApprovalHook(IJBRulesetApprovalHook(address(rejectHook)));

        // Queue a new ruleset with weight 5000 (should be rejected).
        _queueNewWeight(projectId, QUEUED_WEIGHT);

        // Warp past the first cycle boundary so the queued ruleset would have started.
        vm.warp(block.timestamp + CYCLE_DURATION + 1);

        // Pay 1 ETH — should get tokens at BASE_WEIGHT (1000), not QUEUED_WEIGHT (5000).
        uint256 tokens = _pay(projectId, 1 ether);

        // With base weight 1000 tokens/ETH: 1 ETH → 1000 tokens.
        assertEq(tokens, 1000e18, "Should use base weight after rejection");

        // Verify the current ruleset's weight is the base weight (cycled).
        JBRuleset memory current = jbRulesets().currentOf(projectId);
        assertEq(current.weight, BASE_WEIGHT, "Current ruleset should have base weight");
    }

    /// @notice When a queued ruleset is rejected, payout limits from the base config apply.
    function test_approvalRejection_payoutsUseBaseConfig() public {
        // Base: 1 ETH payout limit. Queued: 10 ETH payout limit (should be rejected).
        projectId = _launchWithPayoutLimitAndHook(IJBRulesetApprovalHook(address(rejectHook)), 1 ether);
        _queueNewWeightAndPayout(projectId, QUEUED_WEIGHT, 10 ether);

        // Fund the project.
        _pay(projectId, 5 ether);

        // Warp past cycle boundary.
        vm.warp(block.timestamp + CYCLE_DURATION + 1);

        // Attempt payout of 2 ETH — should revert because base limit is 1 ETH.
        vm.prank(PROJECT_OWNER);
        vm.expectRevert();
        jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 2 ether,
            currency: NATIVE_CURRENCY,
            minTokensPaidOut: 0
        });

        // Payout of 1 ETH should succeed (within base limit).
        vm.prank(PROJECT_OWNER);
        uint256 paid = jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            currency: NATIVE_CURRENCY,
            minTokensPaidOut: 0
        });
        assertGt(paid, 0, "Payout within base limit should succeed");
    }

    /// @notice A reverting approval hook should be treated the same as an explicit rejection.
    function test_approvalRejection_hookReverts_treatedAsFailed() public {
        // Launch with RevertingApprovalHook.
        projectId = _launchWithApprovalHook(IJBRulesetApprovalHook(address(revertHook)));

        // Queue a new ruleset with weight 5000.
        _queueNewWeight(projectId, QUEUED_WEIGHT);

        // Warp past the cycle boundary.
        vm.warp(block.timestamp + CYCLE_DURATION + 1);

        // Pay 1 ETH — should get tokens at BASE_WEIGHT, not QUEUED_WEIGHT.
        uint256 tokens = _pay(projectId, 1 ether);
        assertEq(tokens, 1000e18, "Reverting hook should behave like rejection");

        // Verify fallback to base weight.
        JBRuleset memory current = jbRulesets().currentOf(projectId);
        assertEq(current.weight, BASE_WEIGHT, "Current ruleset should fall back to base");
    }

    /// @notice JBDeadline rejects rulesets queued too late (less than DURATION before cycle end).
    function test_approvalRejection_deadlineHook_tooLate() public {
        // Deploy a JBDeadline with 3-day requirement.
        JBDeadline deadline = new JBDeadline(3 days);

        // Launch with the deadline hook and a 7-day cycle.
        projectId = _launchWithApprovalHook(IJBRulesetApprovalHook(address(deadline)));

        // Warp to 2 days before cycle end (only 2 days left, but deadline requires 3).
        vm.warp(block.timestamp + CYCLE_DURATION - 2 days);

        // Queue new ruleset — queued too late (2 days left < 3 day deadline).
        _queueNewWeight(projectId, QUEUED_WEIGHT);

        // Warp past cycle boundary.
        vm.warp(block.timestamp + 2 days + 1);

        // Pay — should use base weight because deadline was missed.
        uint256 tokens = _pay(projectId, 1 ether);
        assertEq(tokens, 1000e18, "Late-queued ruleset should be rejected by deadline hook");
    }
}
