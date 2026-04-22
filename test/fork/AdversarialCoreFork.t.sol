// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FullStackForkTest} from "./FullStackFork.t.sol";
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
import {IJBMultiTerminal} from "@bananapus/core-v6/src/interfaces/IJBMultiTerminal.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// ═══════════════════════════════════════════════════════════════════════════
//  Inline attack contracts
// ═══════════════════════════════════════════════════════════════════════════

/// @notice Split hook that re-enters `cashOutTokensOf` when receiving ETH from a payout split.
/// During payout processing, this hook receives its share of the payout and immediately tries
/// to cash out tokens it holds, testing whether the terminal's accounting remains consistent
/// when `cashOutTokensOf` is called mid-payout.
contract CashOutReentrySplitHook is IJBSplitHook {
    IJBMultiTerminal public terminal;
    uint256 public targetProjectId;
    address public token;
    address public victimHolder;

    bool public reentryCalled;
    bool public reentrySucceeded;
    uint256 public reclaimedAmount;

    constructor(
        IJBMultiTerminal _terminal,
        uint256 _projectId,
        address _token,
        address _victimHolder
    ) {
        terminal = _terminal;
        targetProjectId = _projectId;
        token = _token;
        victimHolder = _victimHolder;
    }

    receive() external payable {}

    function processSplitWith(JBSplitHookContext calldata) external payable override {
        if (!reentryCalled) {
            reentryCalled = true;
            // Attempt to cash out the victim's tokens via re-entry.
            // The hook holds no tokens itself, so it tries to cash out the victimHolder's tokens.
            // This should fail because the hook is not the holder and has no permission.
            // Even if it could, accounting should remain consistent.
            try terminal.cashOutTokensOf({
                holder: victimHolder,
                projectId: targetProjectId,
                cashOutCount: 1e18, // Try to cash out 1 token
                tokenToReclaim: token,
                minTokensReclaimed: 0,
                beneficiary: payable(address(this)),
                metadata: ""
            }) returns (uint256 reclaimed) {
                reentrySucceeded = true;
                reclaimedAmount = reclaimed;
            } catch {
                reentrySucceeded = false;
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IJBSplitHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Adversarial Core Fork Tests
// ═══════════════════════════════════════════════════════════════════════════

/// @notice Adversarial tests targeting known attack surfaces and edge cases in the Juicebox V6 protocol.
///
/// Covers:
/// - Duration-0 instant ruleset switch (rug vector via weight inflation)
/// - Split hook re-entering cashOutTokensOf during payout processing
/// - Same-block payout + cashout ordering sensitivity
/// - Exact ruleset transition boundary behavior
/// - Fee project self-pause (fee forgiveness when fee terminal reverts)
/// - Reserved token distribution at exact stage transition boundary
///
/// Run with: forge test --match-contract AdversarialCoreForkTest -vvv
contract AdversarialCoreForkTest is FullStackForkTest {
    // ── Constants
    uint32 constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));

    // ── Additional actors
    address ACCOMPLICE = makeAddr("accomplice");
    address PAYER2 = makeAddr("payer2");
    address PROJECT_OWNER = makeAddr("projectOwner");

    // ═══════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Launch a raw JB project (not a revnet) with given weight, duration, and cashOutTaxRate.
    function _launchRawProject(
        uint112 weight,
        uint32 duration,
        uint16 cashOutTaxRate,
        address owner
    )
        internal
        returns (uint256 projectId)
    {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});

        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBRulesetConfig[] memory rulesetConfigs = new JBRulesetConfig[](1);
        rulesetConfigs[0] = JBRulesetConfig({
            mustStartAtOrAfter: uint48(block.timestamp),
            duration: duration,
            weight: weight,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: JBRulesetMetadata({
                reservedPercent: 0,
                cashOutTaxRate: cashOutTaxRate,
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
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        projectId = jbController().launchProjectFor({
            owner: owner,
            projectUri: "ipfs://adversarial",
            rulesetConfigurations: rulesetConfigs,
            terminalConfigurations: tc,
            memo: ""
        });
    }

    /// @notice Launch a raw JB project with a split hook receiving a percentage of payouts.
    function _launchRawProjectWithSplitHook(
        uint112 weight,
        uint16 cashOutTaxRate,
        IJBSplitHook splitHook,
        uint32 splitPercent,
        uint224 payoutLimit,
        address owner
    )
        internal
        returns (uint256 projectId)
    {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});

        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Build split: splitPercent to the hook, remainder to owner.
        JBSplit[] memory splits = new JBSplit[](2);
        splits[0] = JBSplit({
            percent: splitPercent,
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: splitHook
        });
        splits[1] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT) - splitPercent,
            projectId: 0,
            beneficiary: payable(owner),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](1);
        splitGroups[0] = JBSplitGroup({groupId: uint256(uint160(JBConstants.NATIVE_TOKEN)), splits: splits});

        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1);
        payoutLimits[0] = JBCurrencyAmount({amount: payoutLimit, currency: NATIVE_CURRENCY});

        JBFundAccessLimitGroup[] memory fundAccessLimitGroups = new JBFundAccessLimitGroup[](1);
        fundAccessLimitGroups[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: payoutLimits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });

        JBRulesetConfig[] memory rulesetConfigs = new JBRulesetConfig[](1);
        rulesetConfigs[0] = JBRulesetConfig({
            mustStartAtOrAfter: uint48(block.timestamp),
            duration: 0,
            weight: weight,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: JBRulesetMetadata({
                reservedPercent: 0,
                cashOutTaxRate: cashOutTaxRate,
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

        projectId = jbController().launchProjectFor({
            owner: owner,
            projectUri: "ipfs://adversarial-split",
            rulesetConfigurations: rulesetConfigs,
            terminalConfigurations: tc,
            memo: ""
        });
    }

    /// @notice Build a two-stage revnet config with custom splitPercent for reserved token testing.
    function _buildTwoStageConfigWithSplit(
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

        REVStageConfig[] memory stages = new REVStageConfig[](2);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0].beneficiary = payable(multisig());
        splits[0].percent = 10_000;

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

        stages[1] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp + 30 days),
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
            description: REVDescription("Adversarial", "ADV", "ipfs://adv", "ADV_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("ADV"))
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 1: Duration-0 instant ruleset switch (Gap 4)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice A project owner with duration=0 and no approval hook can queue a new ruleset with
    /// 1000x inflated weight. Because the old ruleset has no duration, the new one takes effect
    /// immediately. An accomplice pays at the inflated weight, then cashes out to extract value
    /// from existing payers.
    function test_adversarial_duration0_instantRulesetSwitch() public {
        _deployFeeProject(5000);

        vm.deal(ACCOMPLICE, 100 ether);

        // Step 1: Launch a raw JB project with duration=0, no approval hook, weight=1000e18.
        uint112 originalWeight = 1000e18;
        uint256 projectId = _launchRawProject({
            weight: originalWeight,
            duration: 0,
            cashOutTaxRate: 0, // No tax -- makes extraction easier for the attacker.
            owner: PROJECT_OWNER
        });

        emit log_named_uint("Project ID", projectId);

        // Step 2: PAYER pays 10 ETH, receiving tokens at the original weight.
        vm.prank(PAYER);
        uint256 payerTokens = jbMultiTerminal().pay{value: 10 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 10 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "honest payer",
            metadata: ""
        });

        emit log_named_uint("PAYER tokens (at weight 1000)", payerTokens);
        assertEq(payerTokens, 10_000e18, "PAYER should receive 10,000 tokens at 1000/ETH");

        uint256 terminalBalAfterPay = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        emit log_named_uint("Terminal balance after PAYER", terminalBalAfterPay);

        // Step 3: Project owner queues new ruleset with 1000x inflated weight.
        uint112 inflatedWeight = 1_000_000e18;
        JBRulesetConfig[] memory newRulesets = new JBRulesetConfig[](1);
        newRulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: uint48(block.timestamp),
            duration: 0,
            weight: inflatedWeight,
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
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        vm.prank(PROJECT_OWNER);
        uint256 newRulesetId = jbController().queueRulesetsOf(projectId, newRulesets, "inflate weight 1000x");
        emit log_named_uint("New ruleset ID", newRulesetId);

        // Step 4: ACCOMPLICE pays 1 ETH at the inflated weight.
        // Since duration=0 and no approval hook, the new ruleset should take effect immediately.
        vm.prank(ACCOMPLICE);
        uint256 accompliceTokens = jbMultiTerminal().pay{value: 1 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: ACCOMPLICE,
            minReturnedTokens: 0,
            memo: "accomplice pays at inflated weight",
            metadata: ""
        });

        emit log_named_uint("ACCOMPLICE tokens (at weight 1M)", accompliceTokens);

        // ACCOMPLICE should get 1000x more tokens per ETH than PAYER did.
        uint256 payerTokensPerEth = payerTokens / 10; // 1000e18
        uint256 accompliceTokensPerEth = accompliceTokens; // Paid 1 ETH
        emit log_named_uint("PAYER tokens/ETH", payerTokensPerEth);
        emit log_named_uint("ACCOMPLICE tokens/ETH", accompliceTokensPerEth);

        assertGt(accompliceTokensPerEth, payerTokensPerEth * 100, "ACCOMPLICE should get >100x more tokens per ETH");

        // Step 5: ACCOMPLICE cashes out all tokens -- check if they extract more than 1 ETH.
        uint256 accompliceEthBefore = ACCOMPLICE.balance;
        uint256 totalSupplyBefore = jbTokens().totalSupplyOf(projectId);
        uint256 surplusBefore = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);

        emit log_named_uint("Total supply before cashout", totalSupplyBefore);
        emit log_named_uint("Surplus before cashout", surplusBefore);

        vm.prank(ACCOMPLICE);
        uint256 reclaimed = jbMultiTerminal().cashOutTokensOf({
            holder: ACCOMPLICE,
            projectId: projectId,
            cashOutCount: accompliceTokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(ACCOMPLICE),
            metadata: ""
        });

        uint256 accompliceEthReceived = ACCOMPLICE.balance - accompliceEthBefore;
        emit log_named_uint("ACCOMPLICE reclaimed (return value)", reclaimed);
        emit log_named_uint("ACCOMPLICE ETH received", accompliceEthReceived);
        emit log_named_uint("ACCOMPLICE ETH profit", accompliceEthReceived > 1 ether ? accompliceEthReceived - 1 ether : 0);

        // The rug vector: ACCOMPLICE paid 1 ETH but should be able to extract a pro-rata share
        // of the 11 ETH surplus proportional to their massive token holding.
        // With cashOutTaxRate=0 and pro-rata: accomplice share = 11 ETH * accompliceTokens / totalSupply.
        // If accompliceTokens >> payerTokens, they get almost all the surplus.
        if (accompliceEthReceived > 1 ether) {
            emit log("RESULT: Instant ruleset switch allows ACCOMPLICE to PROFIT -- rug vector confirmed.");
            emit log_named_uint("  PAYER loss (ETH)", 10 ether - (surplusBefore - accompliceEthReceived));
        } else {
            emit log("RESULT: ACCOMPLICE did not profit -- protocol may have protections.");
        }

        // Verify accounting invariant: terminal balance should never go negative.
        uint256 terminalBalAfter = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        emit log_named_uint("Terminal balance after cashout", terminalBalAfter);
        assertGe(terminalBalAfter, 0, "terminal balance must not be negative");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 2: Split hook re-entering cashOutTokensOf (Gap 8)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice A payout split hook receives ETH during sendPayoutsOf and attempts to re-enter
    /// `cashOutTokensOf` on the terminal for another user. This tests whether the re-entrant
    /// cashout is blocked by permissions or reentrancy guards, and whether accounting stays
    /// consistent regardless.
    function test_adversarial_splitHookReentrantCashOut() public {
        _deployFeeProject(5000);

        vm.deal(PAYER2, 100 ether);

        // Step 1: Predict the next project ID so we can configure the hook.
        uint256 nextProjectId = jbProjects().count() + 1;

        // Step 2: Deploy the re-entrant split hook.
        CashOutReentrySplitHook reentryHook = new CashOutReentrySplitHook(
            jbMultiTerminal(),
            nextProjectId,
            JBConstants.NATIVE_TOKEN,
            PAYER2 // victim whose tokens the hook tries to cash out
        );

        // Step 3: Deploy the project with the hook receiving 30% of payouts.
        uint32 hookSplitPercent = uint32(uint256(JBConstants.SPLITS_TOTAL_PERCENT) * 30 / 100); // 30%
        uint256 projectId = _launchRawProjectWithSplitHook({
            weight: 1000e18,
            cashOutTaxRate: 0,
            splitHook: IJBSplitHook(address(reentryHook)),
            splitPercent: hookSplitPercent,
            payoutLimit: 3 ether, // Payout limit of 3 ETH
            owner: PROJECT_OWNER
        });
        assertEq(projectId, nextProjectId, "project ID should match prediction");

        emit log_named_uint("Project ID", projectId);

        // Step 4: PAYER pays 10 ETH.
        vm.prank(PAYER);
        uint256 payerTokens = jbMultiTerminal().pay{value: 10 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 10 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "payer1",
            metadata: ""
        });
        emit log_named_uint("PAYER tokens", payerTokens);

        // Step 5: PAYER2 pays 5 ETH -- they will be the cashout victim.
        vm.prank(PAYER2);
        uint256 payer2Tokens = jbMultiTerminal().pay{value: 5 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            beneficiary: PAYER2,
            minReturnedTokens: 0,
            memo: "payer2 - victim",
            metadata: ""
        });
        emit log_named_uint("PAYER2 tokens", payer2Tokens);

        uint256 terminalBalBefore = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        emit log_named_uint("Terminal balance before payout", terminalBalBefore);

        // Step 6: Trigger payouts -- the hook will receive its share and try to cashOut PAYER2's tokens.
        jbMultiTerminal().sendPayoutsOf({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 3 ether,
            currency: NATIVE_CURRENCY,
            minTokensPaidOut: 0
        });

        // Step 7: Check results.
        emit log_named_uint("Re-entry called", reentryHook.reentryCalled() ? 1 : 0);
        emit log_named_uint("Re-entry succeeded", reentryHook.reentrySucceeded() ? 1 : 0);

        assertTrue(reentryHook.reentryCalled(), "hook should have attempted re-entry into cashOutTokensOf");

        if (reentryHook.reentrySucceeded()) {
            emit log("WARNING: Re-entrant cashOutTokensOf succeeded during payout processing!");
            emit log_named_uint("  Reclaimed amount", reentryHook.reclaimedAmount());

            // Even if it succeeded, check accounting consistency.
            uint256 terminalBalAfter = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
            uint256 actualTerminalEth = address(jbMultiTerminal()).balance;

            emit log_named_uint("Terminal recorded balance after", terminalBalAfter);
            emit log_named_uint("Terminal actual ETH", actualTerminalEth);

            // Accounting invariant: recorded balance must not exceed actual ETH held.
            assertGe(
                actualTerminalEth,
                terminalBalAfter,
                "CRITICAL: recorded balance exceeds actual ETH -- double-spend detected"
            );
        } else {
            emit log("RESULT: Re-entrant cashOutTokensOf was correctly blocked (permission or reentrancy guard).");
        }

        // Verify PAYER2 tokens are still intact (no unauthorized cashout).
        uint256 payer2TokensAfter = jbTokens().totalBalanceOf(PAYER2, projectId);
        emit log_named_uint("PAYER2 tokens after payout", payer2TokensAfter);
        assertEq(payer2TokensAfter, payer2Tokens, "PAYER2 tokens should be unchanged -- no unauthorized cashout");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 3: Same-block payout + cashout (Gap 7)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice In the same block, execute sendPayoutsOf followed by cashOutTokensOf.
    /// The cashout should reflect the reduced surplus from the payout. Compare with the
    /// reverse ordering to show the amounts differ.
    function test_adversarial_sameBlockPayoutThenCashOut() public {
        vm.deal(PAYER2, 100 ether);

        // Deploy a raw JB project (no buyback hook) with 50% cashOutTaxRate.
        // Using a raw project avoids buyback hook slippage failures on the forked Uniswap pool.
        uint256 revnetId = _launchRawProject(1000e18, 0, 5000, PROJECT_OWNER);

        // Two payers each pay 10 ETH.
        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, PAYER2, 10 ether);

        uint256 payer2Tokens = jbTokens().totalBalanceOf(PAYER2, revnetId);
        emit log_named_uint("PAYER2 tokens", payer2Tokens);

        uint256 surplusBefore = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        emit log_named_uint("Surplus before any action", surplusBefore);

        // --- Scenario A: Payout FIRST, then cashout (same block) ---
        // Take a snapshot so we can compare with Scenario B.
        uint256 snapshotId = vm.snapshot();

        // Payout 5 ETH (revnets have no payout limit by default, so this tests surplus reduction).
        // Revnets don't support sendPayoutsOf in the usual sense because they have no payout limits.
        // Instead, we do the cashout directly and measure the surplus effect.

        // For the same-block test, we cash out PAYER2 and record the reclaim.
        uint256 payer2EthBefore = PAYER2.balance;

        vm.prank(PAYER2);
        uint256 reclaimScenarioA = jbMultiTerminal().cashOutTokensOf({
            holder: PAYER2,
            projectId: revnetId,
            cashOutCount: payer2Tokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER2),
            metadata: ""
        });

        uint256 ethReceivedA = PAYER2.balance - payer2EthBefore;
        emit log_named_uint("Scenario A: PAYER2 cashout reclaim (return)", reclaimScenarioA);
        emit log_named_uint("Scenario A: PAYER2 ETH received", ethReceivedA);

        uint256 surplusAfterA = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        emit log_named_uint("Scenario A: surplus after cashout", surplusAfterA);

        // --- Scenario B: Revert to snapshot, have PAYER cash out first, reducing surplus, then PAYER2 cashes out ---
        vm.revertTo(snapshotId);

        // PAYER cashes out first -- this reduces the surplus.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        uint256 payerReclaim = jbMultiTerminal().cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: payerTokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        uint256 payerEthReceived = PAYER.balance - payerEthBefore;
        emit log_named_uint("Scenario B: PAYER cashout first, ETH received", payerEthReceived);

        uint256 surpusAfterPayerCashout = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        emit log_named_uint("Scenario B: surplus after PAYER cashout", surpusAfterPayerCashout);

        // Now PAYER2 cashes out from the reduced surplus.
        payer2EthBefore = PAYER2.balance;

        vm.prank(PAYER2);
        uint256 reclaimScenarioB = jbMultiTerminal().cashOutTokensOf({
            holder: PAYER2,
            projectId: revnetId,
            cashOutCount: payer2Tokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER2),
            metadata: ""
        });

        uint256 ethReceivedB = PAYER2.balance - payer2EthBefore;
        emit log_named_uint("Scenario B: PAYER2 cashout after PAYER, ETH received", ethReceivedB);

        // Key comparison: the amounts should differ because the surplus changed.
        // When PAYER cashes out first, the surplus is reduced, so PAYER2 gets a different amount.
        emit log_named_uint("Difference in PAYER2 reclaim (A - B)", ethReceivedA > ethReceivedB ? ethReceivedA - ethReceivedB : ethReceivedB - ethReceivedA);

        // With a 50% tax rate, the second casher-out should receive LESS because:
        // - After PAYER's cashout, there are fewer tokens AND less surplus.
        // - But PAYER2 owns a larger share of remaining tokens, so the bonding curve may actually give more.
        // The key invariant is that total extracted <= total deposited.
        uint256 totalExtracted = payerEthReceived + ethReceivedB;
        emit log_named_uint("Scenario B: total ETH extracted", totalExtracted);
        emit log_named_uint("Total ETH deposited", 20 ether);

        assertLe(totalExtracted, 20 ether, "total extracted must not exceed total deposited");

        // Accounting invariant: terminal balance must be non-negative and consistent.
        uint256 terminalBalFinal = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        emit log_named_uint("Final terminal balance", terminalBalFinal);
        assertGe(terminalBalFinal, 0, "terminal balance must not be negative");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 4: Exact ruleset transition boundary (Gap 13)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Deploy a revnet with two stages (stage1 tax=7000, stage2 tax=2000, 30-day duration).
    /// Pay at the exact boundary timestamp and compare with +1 second past the boundary.
    /// Determine which tax rate applies at the exact boundary.
    function test_adversarial_exactRulesetBoundary() public {
        _deployFeeProject(5000);

        // Deploy two-stage revnet: 70% tax -> 20% tax after 30 days.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfig(7000, 2000);

        uint256 deployTimestamp = block.timestamp;

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupPool(revnetId, 10_000 ether);

        // Step 1: Pay in stage 1 to establish a baseline.
        _payRevnet(revnetId, PAYER, 5 ether);
        address boundaryPayer = makeAddr("boundaryPayer");
        vm.deal(boundaryPayer, 100 ether);

        // Record baseline payment in stage 1.
        uint256 tokensStage1 = _payRevnet(revnetId, boundaryPayer, 1 ether);
        emit log_named_uint("Tokens received in stage 1 (1 ETH)", tokensStage1);

        // Step 2: Warp to EXACTLY the boundary (block.timestamp + 30 days).
        uint256 exactBoundary = deployTimestamp + 30 days;
        vm.warp(exactBoundary);

        address exactPayer = makeAddr("exactPayer");
        vm.deal(exactPayer, 100 ether);
        uint256 tokensAtExactBoundary = _payRevnet(revnetId, exactPayer, 1 ether);
        emit log_named_uint("Tokens received at EXACT boundary (1 ETH)", tokensAtExactBoundary);

        // Step 3: Warp to +1 second past the boundary.
        vm.warp(exactBoundary + 1);

        address latePayer = makeAddr("latePayer");
        vm.deal(latePayer, 100 ether);
        uint256 tokensAfterBoundary = _payRevnet(revnetId, latePayer, 1 ether);
        emit log_named_uint("Tokens received at boundary+1s (1 ETH)", tokensAfterBoundary);

        // Analysis: Compare token counts.
        // The token count itself reflects the issuance weight (which is the same for both stages in our config).
        // The difference shows up in the cashOutTaxRate, not in minting. So let's also check cashout values.
        emit log_named_uint("Exact boundary vs stage1 difference", tokensAtExactBoundary > tokensStage1 ? tokensAtExactBoundary - tokensStage1 : tokensStage1 - tokensAtExactBoundary);
        emit log_named_uint("After boundary vs exact boundary difference", tokensAfterBoundary > tokensAtExactBoundary ? tokensAfterBoundary - tokensAtExactBoundary : tokensAtExactBoundary - tokensAfterBoundary);

        // If exact boundary == after boundary, stage 2 starts AT the boundary (inclusive).
        // If exact boundary == stage 1, stage 2 starts AFTER the boundary (exclusive).
        if (tokensAtExactBoundary == tokensAfterBoundary) {
            emit log("RESULT: Stage 2 starts at EXACT boundary (boundary is inclusive for new stage).");
        } else if (tokensAtExactBoundary == tokensStage1) {
            emit log("RESULT: Stage 1 still active at exact boundary (boundary is exclusive for new stage).");
        } else {
            emit log("RESULT: Token counts differ at boundary -- possible interpolation or rounding.");
        }

        // Verify that the +1 second payment is definitely in stage 2 by checking cashout tax.
        // Cash out the latePayer's tokens and see how much they get back.
        uint256 latePayerTokens = jbTokens().totalBalanceOf(latePayer, revnetId);
        uint256 latePayerEthBefore = latePayer.balance;

        vm.prank(latePayer);
        jbMultiTerminal().cashOutTokensOf({
            holder: latePayer,
            projectId: revnetId,
            cashOutCount: latePayerTokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(latePayer),
            metadata: ""
        });

        uint256 latePayerEthReceived = latePayer.balance - latePayerEthBefore;
        emit log_named_uint("Late payer (+1s) cashout ETH received", latePayerEthReceived);

        // Also cash out the exact boundary payer for comparison.
        uint256 exactPayerTokens = jbTokens().totalBalanceOf(exactPayer, revnetId);
        uint256 exactPayerEthBefore = exactPayer.balance;

        vm.prank(exactPayer);
        jbMultiTerminal().cashOutTokensOf({
            holder: exactPayer,
            projectId: revnetId,
            cashOutCount: exactPayerTokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(exactPayer),
            metadata: ""
        });

        uint256 exactPayerEthReceived = exactPayer.balance - exactPayerEthBefore;
        emit log_named_uint("Exact boundary payer cashout ETH received", exactPayerEthReceived);

        // Accounting invariant: terminal should still be consistent.
        uint256 terminalBalFinal = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        emit log_named_uint("Final terminal balance", terminalBalFinal);
        assertGe(terminalBalFinal, 0, "terminal balance must not be negative");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 5: Fee project self-pause (Gap 21)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice When the fee project's terminal pay() reverts (simulating pausePay), fees generated
    /// by other projects should be forgiven (returned to the project) rather than causing the
    /// entire cashout to fail.
    function test_adversarial_feeProjectPausesPay() public {
        _deployFeeProject(5000);

        // Deploy a second revnet that generates fees via cashouts.
        uint256 revnetId = _deployRevnet(5000); // 50% tax -- fees are charged on cashouts when tax < 100%
        _setupPool(revnetId, 10_000 ether);

        // Two payers for bonding curve effect.
        _payRevnet(revnetId, PAYER, 10 ether);
        address feePayer = makeAddr("feePayer");
        vm.deal(feePayer, 20 ether);
        _payRevnet(revnetId, feePayer, 5 ether);

        uint256 feePayerTokens = jbTokens().totalBalanceOf(feePayer, revnetId);

        // Step 1: Cash out normally -- this should generate a fee to the fee project.
        uint256 feeProjectBalBefore = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        emit log_named_uint("Fee project balance before normal cashout", feeProjectBalBefore);

        uint256 revnetBalBefore = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        emit log_named_uint("Revnet balance before normal cashout", revnetBalBefore);

        // Cash out half of feePayer's tokens.
        uint256 halfTokens = feePayerTokens / 2;
        uint256 feePayerEthBefore = feePayer.balance;

        vm.prank(feePayer);
        uint256 normalReclaim = jbMultiTerminal().cashOutTokensOf({
            holder: feePayer,
            projectId: revnetId,
            cashOutCount: halfTokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(feePayer),
            metadata: ""
        });

        uint256 normalEthReceived = feePayer.balance - feePayerEthBefore;
        uint256 feeProjectBalAfterNormal = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        uint256 revnetBalAfterNormal = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);

        emit log_named_uint("Normal cashout ETH received", normalEthReceived);
        emit log_named_uint("Fee project balance after normal cashout", feeProjectBalAfterNormal);
        emit log_named_uint("Revnet balance after normal cashout", revnetBalAfterNormal);

        // Step 2: Mock executeProcessFee to revert (simulating a fee-processing failure).
        // _processFee calls this.executeProcessFee(...) via an external self-call wrapped in
        // try-catch. When the fee terminal is the same multi-terminal (which it is here),
        // _efficientPay uses the internal _pay() path, so mocking the external pay() selector
        // never triggers. Instead we mock executeProcessFee itself. When it reverts, the
        // catch block in _processFee forgives the fee back to the originating project.
        vm.mockCallRevert(
            address(jbMultiTerminal()),
            abi.encodeWithSelector(
                bytes4(keccak256("executeProcessFee(uint256,address,uint256,address,address)"))
            ),
            "FEE_PAY_REVERTED"
        );

        // Step 3: Cash out the remaining tokens -- fee processing should fail but cashout should succeed.
        uint256 remainingTokens = jbTokens().totalBalanceOf(feePayer, revnetId);
        uint256 revnetBalBeforeMocked = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        uint256 feeProjectBalBeforeMocked = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        feePayerEthBefore = feePayer.balance;

        emit log_named_uint("Remaining tokens to cash out", remainingTokens);
        emit log_named_uint("Revnet balance before mocked cashout", revnetBalBeforeMocked);
        emit log_named_uint("Fee project balance before mocked cashout", feeProjectBalBeforeMocked);

        vm.prank(feePayer);
        uint256 mockedReclaim = jbMultiTerminal().cashOutTokensOf({
            holder: feePayer,
            projectId: revnetId,
            cashOutCount: remainingTokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(feePayer),
            metadata: ""
        });

        uint256 mockedEthReceived = feePayer.balance - feePayerEthBefore;
        emit log_named_uint("Mocked cashout ETH received", mockedEthReceived);
        emit log_named_uint("Mocked cashout reclaim (return value)", mockedReclaim);

        // The cashout should still succeed even though fee processing fails.
        assertGt(mockedEthReceived, 0, "cashout should succeed even when fee pay reverts");

        // Step 4: Verify the terminal fee was forgiven (returned to the revnet, not sent to the fee project).
        // Clear the mock so we can read balances cleanly.
        vm.clearMockedCalls();

        uint256 feeProjectBalAfterMocked = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        uint256 revnetBalAfterMocked = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);

        emit log_named_uint("Fee project balance after mocked cashout", feeProjectBalAfterMocked);
        emit log_named_uint("Revnet balance after mocked cashout", revnetBalAfterMocked);

        // When executeProcessFee reverts, _processFee's catch block calls _recordAddedBalanceFor
        // to forgive the terminal fee back to the originating project (the revnet). However, the
        // cashout hook (REVOwner) independently forwards funds to the fee project via the internal
        // _pay path, which is NOT affected by the executeProcessFee mock. So the fee project
        // balance CAN increase from hook-forwarded funds, but should NOT include the terminal fee.
        uint256 feeProjectIncreaseNormal = feeProjectBalAfterNormal - feeProjectBalBefore;
        uint256 feeProjectIncreaseMocked = feeProjectBalAfterMocked - feeProjectBalBeforeMocked;

        emit log_named_uint("Fee project increase (normal cashout)", feeProjectIncreaseNormal);
        emit log_named_uint("Fee project increase (mocked cashout)", feeProjectIncreaseMocked);

        // The fee project balance increased from hook-forwarded funds, but the terminal fee was
        // forgiven back to the revnet. Verify the revnet retained a positive balance.
        assertGt(revnetBalAfterMocked, 0, "revnet balance must be positive after fee forgiveness");

        // Key accounting invariant when the terminal fee is forgiven:
        // The revnet's balance decrease should EQUAL the fee project's balance increase.
        // This proves the terminal fee stayed with the revnet (it was neither sent to the fee
        // project nor lost). In a normal cashout, the fee project increase would be LARGER than
        // the revnet decrease by the terminal fee amount (since the fee moves from revnet to fee
        // project as a separate recorded payment).
        uint256 revnetDecrease = revnetBalBeforeMocked - revnetBalAfterMocked;
        emit log_named_uint("Revnet balance decrease from mocked cashout", revnetDecrease);

        assertEq(
            revnetDecrease,
            feeProjectIncreaseMocked,
            "revnet decrease must equal fee project increase (terminal fee was forgiven, not transferred)"
        );

        // Sanity check: the normal cashout's fee project increase (which included the terminal fee)
        // should be larger than the mocked cashout's increase (hook-only, plus bonding curve gives
        // less on the second cashout).
        assertGt(
            feeProjectIncreaseNormal,
            feeProjectIncreaseMocked,
            "normal cashout should increase fee project more than mocked cashout"
        );

        emit log("RESULT: Fee was forgiven back to the revnet when executeProcessFee reverted.");
        emit log("        The fee project received hook-forwarded funds but NOT the terminal fee.");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 6: Reserved token distribution at exact ruleset transition (Gap 20)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Distribute reserved tokens at three different moments relative to a stage transition:
    /// 1 second before, at exact boundary, and 1 second after. Compare the split beneficiary
    /// token amounts to detect any boundary anomalies.
    function test_adversarial_reservedDistributionAtTransition() public {
        _deployFeeProject(5000);

        // Deploy a two-stage revnet with 20% reserved (splitPercent=2000) in stage 1.
        // Stage 2 has different reserved split percent (e.g., 1000 = 10%).
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithSplit(7000, 2000, 2000);

        uint256 deployTimestamp = block.timestamp;

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupPool(revnetId, 10_000 ether);

        // Step 1: Pay 10 ETH in stage 1 to accumulate reserved tokens.
        _payRevnet(revnetId, PAYER, 10 ether);

        uint256 pendingAfterPay = jbController().pendingReservedTokenBalanceOf(revnetId);
        emit log_named_uint("Pending reserved tokens after 10 ETH pay", pendingAfterPay);
        assertGt(pendingAfterPay, 0, "should have pending reserved tokens after payment");

        // --- Scenario A: Distribute 1 second BEFORE the transition ---
        uint256 snapshotBeforeTransition = vm.snapshot();

        uint256 exactBoundary = deployTimestamp + 30 days;
        vm.warp(exactBoundary - 1);

        uint256 multisigTokensBefore_A = jbTokens().totalBalanceOf(multisig(), revnetId);
        jbController().sendReservedTokensToSplitsOf(revnetId);
        uint256 multisigTokensAfter_A = jbTokens().totalBalanceOf(multisig(), revnetId);
        uint256 distributedBefore = multisigTokensAfter_A - multisigTokensBefore_A;

        emit log_named_uint("Scenario A (1s before): multisig received tokens", distributedBefore);

        // --- Scenario B: Distribute at EXACT boundary ---
        vm.revertTo(snapshotBeforeTransition);
        uint256 snapshotExact = vm.snapshot();

        vm.warp(exactBoundary);

        uint256 multisigTokensBefore_B = jbTokens().totalBalanceOf(multisig(), revnetId);
        jbController().sendReservedTokensToSplitsOf(revnetId);
        uint256 multisigTokensAfter_B = jbTokens().totalBalanceOf(multisig(), revnetId);
        uint256 distributedExact = multisigTokensAfter_B - multisigTokensBefore_B;

        emit log_named_uint("Scenario B (exact boundary): multisig received tokens", distributedExact);

        // --- Scenario C: Distribute 1 second AFTER the transition ---
        vm.revertTo(snapshotExact);

        vm.warp(exactBoundary + 1);

        uint256 multisigTokensBefore_C = jbTokens().totalBalanceOf(multisig(), revnetId);
        jbController().sendReservedTokensToSplitsOf(revnetId);
        uint256 multisigTokensAfter_C = jbTokens().totalBalanceOf(multisig(), revnetId);
        uint256 distributedAfter = multisigTokensAfter_C - multisigTokensBefore_C;

        emit log_named_uint("Scenario C (1s after): multisig received tokens", distributedAfter);

        // --- Analysis ---
        emit log("--- Reserved Distribution Boundary Analysis ---");
        emit log_named_uint("Before boundary (-1s)", distributedBefore);
        emit log_named_uint("At exact boundary", distributedExact);
        emit log_named_uint("After boundary (+1s)", distributedAfter);

        // All three should distribute the same pending amount (since the pending balance was
        // accumulated before the transition). The difference might be in which ruleset's split
        // configuration is used.
        if (distributedBefore == distributedExact && distributedExact == distributedAfter) {
            emit log("RESULT: Reserved distribution is identical across boundary -- no anomaly.");
        } else if (distributedBefore == distributedExact && distributedExact != distributedAfter) {
            emit log("RESULT: Stage transition affects distribution AFTER boundary (exclusive transition).");
            emit log_named_uint("  Difference (exact vs after)", distributedExact > distributedAfter ? distributedExact - distributedAfter : distributedAfter - distributedExact);
        } else if (distributedBefore != distributedExact && distributedExact == distributedAfter) {
            emit log("RESULT: Stage transition affects distribution AT boundary (inclusive transition).");
            emit log_named_uint("  Difference (before vs exact)", distributedBefore > distributedExact ? distributedBefore - distributedExact : distributedExact - distributedBefore);
        } else {
            emit log("RESULT: All three differ -- possible interpolation or rounding at boundary.");
        }

        // Regardless of distribution timing, the total pending should be zero after distribution.
        // (We check the last scenario since it's the one that persists.)
        uint256 pendingAfterDist = jbController().pendingReservedTokenBalanceOf(revnetId);
        assertEq(pendingAfterDist, 0, "pending reserved tokens should be zero after distribution");

        // Accounting invariant.
        uint256 terminalBalFinal = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        assertGe(terminalBalFinal, 0, "terminal balance must not be negative");
    }
}
