// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EcosystemForkTest} from "./EcosystemFork.t.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {JBCurrencyAmount} from "@bananapus/core-v6/src/structs/JBCurrencyAmount.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IJBMultiTerminal} from "@bananapus/core-v6/src/interfaces/IJBMultiTerminal.sol";

/// @notice Split hook that re-enters `sendPayoutsOf` to attempt a double-payout.
/// The payout limit should already be consumed by `recordPayoutFor`, so the re-entry
/// must revert with `JBTerminalStore_InadequateControllerPayoutLimit`.
/// Because `executePayout` wraps the hook call in try-catch, the revert is caught and
/// the split's funds are returned to the project balance. The hook records whether re-entry
/// was attempted and whether it succeeded.
contract MaliciousSplitHook is IJBSplitHook {
    IJBMultiTerminal public terminal;
    uint256 public targetProjectId;
    address public token;
    uint256 public amount;
    uint256 public currency;

    bool public reentering;
    bool public reentryCalled;
    bool public reentrySucceeded;

    constructor(IJBMultiTerminal _terminal, uint256 _projectId, address _token, uint256 _amount, uint256 _currency) {
        terminal = _terminal;
        targetProjectId = _projectId;
        token = _token;
        amount = _amount;
        currency = _currency;
    }

    receive() external payable {}

    function processSplitWith(JBSplitHookContext calldata) external payable override {
        if (!reentering) {
            reentering = true;
            reentryCalled = true;
            // Attempt re-entry into sendPayoutsOf. This should fail because the payout limit
            // was already consumed by recordPayoutFor before splits execute.
            try terminal.sendPayoutsOf({
                projectId: targetProjectId, token: token, amount: amount, currency: currency, minTokensPaidOut: 0
            }) {
                // If we get here, re-entry succeeded (should NOT happen).
                reentrySucceeded = true;
            } catch {
                // Expected: re-entry reverts due to payout limit already consumed.
                reentrySucceeded = false;
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IJBSplitHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

/// @notice Split hook that re-enters via `addToBalanceOf` during payout processing.
/// Unlike `sendPayoutsOf`, `addToBalanceOf` only increases the project's recorded balance
/// and should succeed without issues. This tests that benign re-entry paths remain functional.
contract AddToBalanceSplitHook is IJBSplitHook {
    IJBMultiTerminal public terminal;
    uint256 public targetProjectId;
    address public token;

    bool public addToBalanceCalled;
    bool public addToBalanceSucceeded;

    constructor(IJBMultiTerminal _terminal, uint256 _projectId, address _token) {
        terminal = _terminal;
        targetProjectId = _projectId;
        token = _token;
    }

    receive() external payable {}

    function processSplitWith(
        JBSplitHookContext calldata /* context */
    )
        external
        payable
        override
    {
        if (!addToBalanceCalled && msg.value > 0) {
            addToBalanceCalled = true;
            // Re-enter via addToBalanceOf, forwarding all received ETH back to the project.
            try terminal.addToBalanceOf{value: msg.value}({
                projectId: targetProjectId,
                token: token,
                amount: msg.value,
                shouldReturnHeldFees: false,
                memo: "re-entry via addToBalanceOf",
                metadata: ""
            }) {
                addToBalanceSucceeded = true;
            } catch {
                addToBalanceSucceeded = false;
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IJBSplitHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

/// @notice Tests that payout split hooks cannot exploit re-entry to double-spend payouts.
///
/// The `sendPayoutsOf()` flow is:
///   1. `JBTerminalStore.recordPayoutFor()` — records payout limit usage and decreases balance BEFORE any external
/// calls 2. `JBPayoutSplitGroupLib.sendPayoutsToSplitGroupOf()` — iterates splits, calling `executePayout()` for each
///   3. `executePayout()` — transfers funds to split hook and calls `processSplitWith()`
///
/// Since step 1 consumes the payout limit before step 3 executes, a re-entrant call to `sendPayoutsOf()`
/// from inside a split hook should fail because `usedPayoutLimitOf` already equals the limit.
///
/// Run with: forge test --match-contract PayoutReentrancyForkTest -vvv
contract PayoutReentrancyForkTest is EcosystemForkTest {
    uint32 constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));
    uint112 constant WEIGHT = 1000e18; // 1000 tokens per ETH
    uint224 constant PAYOUT_LIMIT = 1 ether;

    address PROJECT_OWNER = makeAddr("projectOwner");

    // ═══════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Deploy a JB project with a single payout split pointing to `splitHook`.
    /// The project has a payout limit of `PAYOUT_LIMIT` (1 ETH) in native token.
    function _deployProjectWithSplitHook(IJBSplitHook splitHook) internal returns (uint256 projectId) {
        // Build accounting context.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});

        // Terminal config.
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Build split: 100% to the split hook.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: splitHook
        });

        // Split group: keyed by token address (native token) for payouts.
        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](1);
        splitGroups[0] = JBSplitGroup({groupId: uint256(uint160(JBConstants.NATIVE_TOKEN)), splits: splits});

        // Payout limit: 1 ETH in native currency.
        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1);
        payoutLimits[0] = JBCurrencyAmount({amount: PAYOUT_LIMIT, currency: NATIVE_CURRENCY});

        JBFundAccessLimitGroup[] memory fundAccessLimitGroups = new JBFundAccessLimitGroup[](1);
        fundAccessLimitGroups[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: payoutLimits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });

        // Ruleset config: no duration (permanent), standard weight, no approval hook.
        JBRulesetConfig[] memory rulesetConfigs = new JBRulesetConfig[](1);
        rulesetConfigs[0] = JBRulesetConfig({
            mustStartAtOrAfter: uint48(block.timestamp),
            duration: 0,
            weight: WEIGHT,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: JBRulesetMetadata({
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
            }),
            splitGroups: splitGroups,
            fundAccessLimitGroups: fundAccessLimitGroups
        });

        // Launch the project.
        projectId = jbController()
            .launchProjectFor({
                owner: PROJECT_OWNER,
                projectUri: "",
                rulesetConfigurations: rulesetConfigs,
                terminalConfigurations: tc,
                memo: ""
            });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Tests
    // ═══════════════════════════════════════════════════════════════════

    /// @notice A malicious split hook attempts to re-enter `sendPayoutsOf()` during payout processing.
    /// The re-entry should fail because `recordPayoutFor()` already consumed the payout limit.
    /// The try-catch in `executePayout` catches the failure and returns the split's funds to the project balance.
    /// Only one payout's worth of funds should leave the terminal.
    function test_payoutReentrancy_splitHookCannotDoubleSpend() public {
        // We need a project first to know the ID, then deploy the hook with that ID.
        // Use a two-step approach: predict the next project ID, deploy the hook, then deploy the project.

        // Step 1: Predict the next project ID.
        uint256 nextProjectId = jbProjects().count() + 1;

        // Step 2: Deploy the malicious split hook targeting this project.
        MaliciousSplitHook maliciousHook = new MaliciousSplitHook(
            jbMultiTerminal(),
            nextProjectId,
            JBConstants.NATIVE_TOKEN,
            PAYOUT_LIMIT, // Try to re-enter with the same payout amount.
            NATIVE_CURRENCY
        );

        // Step 3: Deploy the project with the malicious hook as the split recipient.
        uint256 projectId = _deployProjectWithSplitHook(IJBSplitHook(address(maliciousHook)));
        assertEq(projectId, nextProjectId, "project ID should match prediction");

        // Step 4: Fund the project with 5 ETH (well above the 1 ETH payout limit).
        vm.prank(PAYER);
        jbMultiTerminal().pay{value: 5 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        uint256 balanceBefore = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        assertEq(balanceBefore, 5 ether, "terminal should hold 5 ETH");

        // Step 5: Trigger payouts. This should:
        //   1. recordPayoutFor consumes the 1 ETH payout limit
        //   2. executePayout sends ETH to malicious hook and calls processSplitWith
        //   3. Hook tries to re-enter sendPayoutsOf -> recordPayoutFor reverts (limit consumed)
        //   4. try-catch in the hook catches the revert
        //   5. The first payout still completes (hook received the funds via try-catch in executePayout)
        jbMultiTerminal()
            .sendPayoutsOf({
                projectId: projectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: PAYOUT_LIMIT,
                currency: NATIVE_CURRENCY,
                minTokensPaidOut: 0
            });

        // Verify the hook attempted re-entry.
        assertTrue(maliciousHook.reentryCalled(), "hook should have attempted re-entry");

        // Verify re-entry did NOT succeed.
        assertFalse(maliciousHook.reentrySucceeded(), "re-entry into sendPayoutsOf should have failed");

        // Verify only one payout's worth of funds left the terminal.
        uint256 balanceAfter = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);

        // The hook received PAYOUT_LIMIT minus the 2.5% fee = 0.975 ETH.
        // The fee (0.025 ETH) was attempted to be processed but the fee project (ID 1) has no
        // terminal set up in this test, so the fee processing reverts. The terminal catches this
        // and returns the fee amount back to the project balance via recordAddedBalanceFor.
        // Net balance decrease = PAYOUT_LIMIT - fee = 0.975 ETH.
        uint256 feeAmount = (PAYOUT_LIMIT * 25) / 1000; // 2.5% fee
        uint256 expectedDecrease = PAYOUT_LIMIT - feeAmount;
        assertEq(
            balanceBefore - balanceAfter,
            expectedDecrease,
            "terminal balance should decrease by payout minus returned fee"
        );

        // A second sendPayoutsOf should also fail since payout limit is consumed for this cycle.
        // Since duration=0, same ruleset stays active, so payout limit persists.
        vm.expectRevert();
        jbMultiTerminal()
            .sendPayoutsOf({
                projectId: projectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: PAYOUT_LIMIT,
                currency: NATIVE_CURRENCY,
                minTokensPaidOut: 0
            });
    }

    /// @notice A split hook re-enters via `addToBalanceOf()` during payout processing.
    /// Unlike `sendPayoutsOf()`, `addToBalanceOf()` simply records additional balance for the project.
    /// This should succeed and the terminal balance should reflect both the payout and the re-added funds.
    function test_payoutReentrancy_addToBalance_succeeds() public {
        // Step 1: Predict the next project ID.
        uint256 nextProjectId = jbProjects().count() + 1;

        // Step 2: Deploy the addToBalance split hook.
        AddToBalanceSplitHook addHook =
            new AddToBalanceSplitHook(jbMultiTerminal(), nextProjectId, JBConstants.NATIVE_TOKEN);

        // Step 3: Deploy the project.
        uint256 projectId = _deployProjectWithSplitHook(IJBSplitHook(address(addHook)));
        assertEq(projectId, nextProjectId, "project ID should match prediction");

        // Step 4: Fund the project.
        vm.prank(PAYER);
        jbMultiTerminal().pay{value: 5 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        uint256 balanceBefore = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        assertEq(balanceBefore, 5 ether, "terminal should hold 5 ETH");

        // Step 5: Trigger payouts.
        // The hook will receive its split amount (after fee), then re-enter via addToBalanceOf
        // to send the ETH back to the project.
        jbMultiTerminal()
            .sendPayoutsOf({
                projectId: projectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: PAYOUT_LIMIT,
                currency: NATIVE_CURRENCY,
                minTokensPaidOut: 0
            });

        // Verify the hook called addToBalanceOf.
        assertTrue(addHook.addToBalanceCalled(), "hook should have called addToBalanceOf");
        assertTrue(addHook.addToBalanceSucceeded(), "addToBalanceOf re-entry should have succeeded");

        // Verify balance consistency.
        // The payout flow:
        //   1. recordPayoutFor deducts PAYOUT_LIMIT from terminal balance -> 4 ETH
        //   2. The split hook receives (PAYOUT_LIMIT - fee). Fee = 2.5% of 1 ETH = 0.025 ETH. Net = 0.975 ETH.
        //   3. The hook sends that 0.975 ETH back via addToBalanceOf, increasing balance.
        //   4. The fee (0.025 ETH) is paid to the fee project.
        // Final balance: 4 ETH + 0.975 ETH = 4.975 ETH
        // But there's also the leftover (0% goes to owner since 100% went to hook) and fee accounting.
        uint256 balanceAfter = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);

        // The key invariant: balance should be greater than (balanceBefore - PAYOUT_LIMIT),
        // because the hook returned the funds via addToBalanceOf.
        assertGt(
            balanceAfter,
            balanceBefore - PAYOUT_LIMIT,
            "balance should be higher than simple payout since hook returned funds"
        );

        // No double-payout occurred: we can verify the payout limit is consumed by trying again.
        vm.expectRevert();
        jbMultiTerminal()
            .sendPayoutsOf({
                projectId: projectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: PAYOUT_LIMIT,
                currency: NATIVE_CURRENCY,
                minTokensPaidOut: 0
            });
    }
}
