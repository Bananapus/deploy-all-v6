// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

/// @notice Flash loan invariant tests on mainnet fork.
///
/// Ports the 3 most critical attack vectors from `FlashLoanAttacks_Local` (nana-core-v6/test/)
/// to a mainnet fork with real Permit2, real PoolManager, and fresh JB core deployment.
/// This validates that the bonding curve invariants hold in a realistic deployment environment,
/// not just in unit-test mocks.
///
/// Vectors tested:
///   1. Atomic pay+cashOut — reclaim ≤ paid
///   2. Sandwich around payout — no profit from payout timing
///   3. Reserved token inflation — cashOut reflects inflated supply
contract FlashLoanInvariantsForkTest is TestBaseWorkflow {
    uint256 public projectId;
    address public projectOwner;

    // Accept ETH for cashout returns.
    receive() external payable {}

    function setUp() public override {
        vm.createSelectFork("ethereum", 21_700_000);

        // Deploy fresh JB core on the fork (TestBaseWorkflow.setUp).
        super.setUp();

        projectOwner = multisig();

        // Launch fee collector project (#1).
        _launchFeeProject();

        // Launch test project (#2): 0% reserved, 30% cashOutTax.
        JBRulesetConfig[] memory rulesetConfig = new JBRulesetConfig[](1);
        rulesetConfig[0].mustStartAtOrAfter = 0;
        rulesetConfig[0].duration = 0;
        rulesetConfig[0].weight = 1000e18;
        rulesetConfig[0].weightCutPercent = 0;
        rulesetConfig[0].approvalHook = IJBRulesetApprovalHook(address(0));
        rulesetConfig[0].metadata = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 3000, // 30%
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: true,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            ownerMustSendPayouts: false,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: false,
            holdFees: false,
            useTotalSurplusForCashOuts: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });
        rulesetConfig[0].splitGroups = new JBSplitGroup[](0);
        rulesetConfig[0].fundAccessLimitGroups = new JBFundAccessLimitGroup[](0);

        projectId = jbController()
            .launchProjectFor({
                owner: projectOwner,
                projectUri: "flashLoanForkTest",
                rulesetConfigurations: rulesetConfig,
                terminalConfigurations: _defaultTerminalConfig(),
                memo: ""
            });

        vm.prank(projectOwner);
        jbController().deployERC20For(projectId, "FlashToken", "FT", bytes32(0));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _launchFeeProject() internal {
        JBRulesetConfig[] memory feeRulesetConfig = new JBRulesetConfig[](1);
        feeRulesetConfig[0].mustStartAtOrAfter = 0;
        feeRulesetConfig[0].duration = 0;
        feeRulesetConfig[0].weight = 1000e18;
        feeRulesetConfig[0].weightCutPercent = 0;
        feeRulesetConfig[0].approvalHook = IJBRulesetApprovalHook(address(0));
        feeRulesetConfig[0].metadata = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: false,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            ownerMustSendPayouts: false,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: false,
            holdFees: false,
            useTotalSurplusForCashOuts: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });
        feeRulesetConfig[0].splitGroups = new JBSplitGroup[](0);
        feeRulesetConfig[0].fundAccessLimitGroups = new JBFundAccessLimitGroup[](0);

        jbController()
            .launchProjectFor({
                owner: address(420),
                projectUri: "feeCollector",
                rulesetConfigurations: feeRulesetConfig,
                terminalConfigurations: _defaultTerminalConfig(),
                memo: ""
            });
    }

    function _defaultTerminalConfig() internal view returns (JBTerminalConfig[] memory) {
        JBTerminalConfig[] memory configs = new JBTerminalConfig[](1);
        JBAccountingContext[] memory tokensToAccept = new JBAccountingContext[](1);
        tokensToAccept[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        configs[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: tokensToAccept});
        return configs;
    }

    function _payProject(address payer, uint256 amount) internal returns (uint256 tokenCount) {
        vm.deal(payer, amount);
        vm.prank(payer);
        tokenCount = jbMultiTerminal().pay{value: amount}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: amount,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });
    }

    function _cashOut(address holder, uint256 count) internal returns (uint256 reclaimAmount) {
        vm.prank(holder);
        reclaimAmount = jbMultiTerminal()
            .cashOutTokensOf({
                holder: holder,
                projectId: projectId,
                cashOutCount: count,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(holder),
                metadata: new bytes(0)
            });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 1: Atomic pay+cashOut — no profit (fork)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Atomic pay+cashOut on mainnet fork: reclaim must not exceed payment.
    /// @dev Validates the bonding curve invariant holds with real Permit2 and deployment.
    function test_fork_flashLoan_payAndCashOut_noProfit() public {
        address attacker = address(0xA77AC0);
        uint256 payAmount = 10 ether;

        // Seed the project with existing funds (creates bonding curve baseline).
        _payProject(address(0x5EED), 10 ether);

        // Attacker pays and immediately cashes out.
        uint256 tokensReceived = _payProject(attacker, payAmount);
        uint256 reclaimAmount = _cashOut(attacker, tokensReceived);

        // Key invariant: reclaim ≤ payment.
        assertLe(reclaimAmount, payAmount, "FORK: Flash loan must not return more than paid");
    }

    /// @notice Multiple payers: total reclaimed must not exceed total paid.
    function test_fork_flashLoan_multiplePayers_totalConservation() public {
        address alice = address(0xA11CE);
        address bob = address(0xB0B);

        // Both pay in the same block.
        uint256 aliceTokens = _payProject(alice, 5 ether);
        uint256 bobTokens = _payProject(bob, 5 ether);

        assertEq(aliceTokens, bobTokens, "Equal payments should mint equal tokens");

        uint256 aliceReclaim = _cashOut(alice, aliceTokens);
        uint256 bobReclaim = _cashOut(bob, bobTokens);

        // Total reclaimed must not exceed total paid in (conservation).
        assertLe(aliceReclaim + bobReclaim, 10 ether, "FORK: Total reclaimed must not exceed total paid in");
        assertLt(aliceReclaim, 5 ether, "First casher pays the tax penalty");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 2: Sandwich around payout — no profit (fork)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Front-run a payout, then back-run with cashOut — attacker must not profit.
    /// @dev Real Permit2 + real deployment on fork validates the payout-limit bookkeeping
    ///      prevents value extraction from payout-induced surplus reduction.
    function test_fork_sandwichAttack_payBeforeAndAfterPayout() public {
        // Launch a project with a 5 ETH payout limit.
        JBRulesetConfig[] memory rulesetConfig = new JBRulesetConfig[](1);
        rulesetConfig[0].mustStartAtOrAfter = 0;
        rulesetConfig[0].duration = 0;
        rulesetConfig[0].weight = 1000e18;
        rulesetConfig[0].weightCutPercent = 0;
        rulesetConfig[0].approvalHook = IJBRulesetApprovalHook(address(0));
        rulesetConfig[0].metadata = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 3000,
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: true,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            ownerMustSendPayouts: false,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: false,
            holdFees: false,
            useTotalSurplusForCashOuts: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });
        rulesetConfig[0].splitGroups = new JBSplitGroup[](0);

        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1);
        payoutLimits[0] = JBCurrencyAmount({amount: 5 ether, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))});

        JBFundAccessLimitGroup[] memory fundAccessLimitGroups = new JBFundAccessLimitGroup[](1);
        fundAccessLimitGroups[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: payoutLimits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });
        rulesetConfig[0].fundAccessLimitGroups = fundAccessLimitGroups;

        uint256 sandwichProjectId = jbController()
            .launchProjectFor({
                owner: projectOwner,
                projectUri: "sandwichForkTest",
                rulesetConfigurations: rulesetConfig,
                terminalConfigurations: _defaultTerminalConfig(),
                memo: ""
            });

        // Seed the project.
        address seeder = address(0x5EED);
        vm.deal(seeder, 20 ether);
        vm.prank(seeder);
        jbMultiTerminal().pay{value: 20 ether}({
            projectId: sandwichProjectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 20 ether,
            beneficiary: seeder,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Attacker front-runs: pays right before payout.
        address attacker = address(0xA77AC0);
        uint256 attackerInitialETH = 10 ether;
        vm.deal(attacker, attackerInitialETH);
        vm.prank(attacker);
        uint256 attackerTokens = jbMultiTerminal().pay{value: attackerInitialETH}({
            projectId: sandwichProjectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: attackerInitialETH,
            beneficiary: attacker,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Payout happens.
        vm.prank(projectOwner);
        jbMultiTerminal()
            .sendPayoutsOf({
                projectId: sandwichProjectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: 5 ether,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                minTokensPaidOut: 0
            });

        // Attacker back-runs: cashes out.
        vm.prank(attacker);
        uint256 reclaimAmount = jbMultiTerminal()
            .cashOutTokensOf({
                holder: attacker,
                projectId: sandwichProjectId,
                cashOutCount: attackerTokens,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(attacker),
                metadata: new bytes(0)
            });

        assertLe(reclaimAmount, attackerInitialETH, "FORK: Sandwich attacker must not profit from payout timing");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 3: Reserved token inflation — cashOut timing (fork)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Reserved tokens inflate totalSupply, reducing per-token cashout value.
    /// @dev Validates that pending reserved tokens correctly reduce cashOut reclaim on fork.
    ///      Uses 30% cashOutTaxRate (not 0%) because the bonding curve penalty amplifies the
    ///      dilution effect — with 0% tax, dilution merely reduces the pro-rata share, but with
    ///      a tax curve the attacker's reclaim drops even further.
    function test_fork_reservedTokenInflation_cashOutTiming() public {
        // Launch project with 20% reserved and 30% cashOutTax.
        JBRulesetConfig[] memory rulesetConfig = new JBRulesetConfig[](1);
        rulesetConfig[0].mustStartAtOrAfter = 0;
        rulesetConfig[0].duration = 0;
        rulesetConfig[0].weight = 1000e18;
        rulesetConfig[0].weightCutPercent = 0;
        rulesetConfig[0].approvalHook = IJBRulesetApprovalHook(address(0));
        rulesetConfig[0].metadata = JBRulesetMetadata({
            reservedPercent: 2000, // 20%
            cashOutTaxRate: 3000, // 30%
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: true,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            ownerMustSendPayouts: false,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: false,
            holdFees: false,
            useTotalSurplusForCashOuts: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });
        rulesetConfig[0].splitGroups = new JBSplitGroup[](0);
        rulesetConfig[0].fundAccessLimitGroups = new JBFundAccessLimitGroup[](0);

        uint256 reservedProjectId = jbController()
            .launchProjectFor({
                owner: projectOwner,
                projectUri: "reservedForkTest",
                rulesetConfigurations: rulesetConfig,
                terminalConfigurations: _defaultTerminalConfig(),
                memo: ""
            });

        vm.prank(projectOwner);
        jbController().deployERC20For(reservedProjectId, "ResToken", "RT", bytes32(0));

        // Pay in.
        address alice = address(0xA11CE);
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        uint256 aliceTokens = jbMultiTerminal().pay{value: 10 ether}({
            projectId: reservedProjectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 10 ether,
            beneficiary: alice,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Verify pending reserved tokens exist.
        uint256 pendingBefore = jbController().pendingReservedTokenBalanceOf(reservedProjectId);
        assertTrue(pendingBefore > 0, "Should have pending reserved tokens");

        // Snapshot Alice's share before distributing reserves.
        uint256 totalSupplyBefore = jbTokens().totalSupplyOf(reservedProjectId);
        uint256 aliceShareBefore = (aliceTokens * 1e18) / totalSupplyBefore;

        // Distribute reserved tokens — inflates totalSupply.
        jbController().sendReservedTokensToSplitsOf(reservedProjectId);

        // Total supply increased.
        uint256 totalSupplyAfter = jbTokens().totalSupplyOf(reservedProjectId);
        assertGt(totalSupplyAfter, totalSupplyBefore, "FORK: Supply should increase after distributing reserves");

        // Alice's share decreased.
        uint256 aliceShareAfter = (aliceTokens * 1e18) / totalSupplyAfter;
        assertLt(aliceShareAfter, aliceShareBefore, "FORK: Alice's share should decrease after reserve distribution");

        // Core invariant: Alice's cashOut reclaim must not exceed her original payment.
        vm.prank(alice);
        uint256 reclaimAmount = jbMultiTerminal()
            .cashOutTokensOf({
                holder: alice,
                projectId: reservedProjectId,
                cashOutCount: aliceTokens,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(alice),
                metadata: new bytes(0)
            });

        assertLe(reclaimAmount, 10 ether, "FORK: Reclaim after reserve inflation must not exceed original payment");
        // With 20% reserved + 30% tax, reclaim should be meaningfully less than paid.
        assertLt(reclaimAmount, 9 ether, "FORK: Reclaim should reflect both reserve dilution and cashOut tax");
    }
}
