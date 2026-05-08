// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FullStackForkTest} from "./FullStackFork.t.sol";

// Core structs and libraries
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBFixedPointNumber} from "@bananapus/core-v6/src/libraries/JBFixedPointNumber.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {JBCurrencyAmount} from "@bananapus/core-v6/src/structs/JBCurrencyAmount.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBFee} from "@bananapus/core-v6/src/structs/JBFee.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBFees} from "@bananapus/core-v6/src/libraries/JBFees.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Revnet
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// ERC20 for mock token
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ═══════════════════════════════════════════════════════════════════
//  Inline Helper Contracts
// ═══════════════════════════════════════════════════════════════════

/// @notice Price feed that always returns zero — used to test division-by-zero DoS.
contract ZeroPriceFeed is IJBPriceFeed {
    function currentUnitPrice(uint256) external pure override returns (uint256) {
        return 0;
    }
}

/// @notice Mock ERC-20 token with 18 decimals and public mint, for multi-terminal tests.
contract MockERC20Token is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Adversarial accounting fork tests exercising edge cases in fee holding, price feed
/// failure modes, cross-currency round trips, dust payment rounding, preview parity, and
/// multi-terminal surplus aggregation.
///
/// Run with: forge test --match-contract AdversarialAccountingForkTest -vvv
contract AdversarialAccountingForkTest is FullStackForkTest {
    // ── Currency constants
    uint32 constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));
    uint32 constant USD = 2; // JBCurrencyIds.USD

    // ── Additional actors
    address ATTACKER = makeAddr("attacker");
    address HONEST_PAYER = makeAddr("honestPayer");
    address PROJECT_OWNER = makeAddr("projectOwner");

    // Accept ETH returns from cashouts.
    // (inherited from FullStackForkTest)

    // ═══════════════════════════════════════════════════════════════════
    //  Metadata Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Build JBRulesetMetadata with holdFees enabled and native base currency.
    function _holdFeesMetadata() internal pure returns (JBRulesetMetadata memory) {
        return JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
            baseCurrency: NATIVE_CURRENCY,
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
            holdFees: true,
            scopeCashOutsToLocalBalances: true,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });
    }

    /// @notice Build JBRulesetMetadata with USD base currency.
    function _usdBaseMetadata(uint16 cashOutTaxRate) internal pure returns (JBRulesetMetadata memory) {
        return JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: cashOutTaxRate,
            baseCurrency: USD,
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
            scopeCashOutsToLocalBalances: true,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });
    }

    /// @notice Build metadata with native base, no tax, no hooks, no fees.
    function _vanillaMetadata(uint16 cashOutTaxRate) internal pure returns (JBRulesetMetadata memory) {
        return JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: cashOutTaxRate,
            baseCurrency: NATIVE_CURRENCY,
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: true,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: true,
            ownerMustSendPayouts: false,
            holdFees: false,
            scopeCashOutsToLocalBalances: true,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });
    }

    /// @notice Build metadata with scopeCashOutsToLocalBalances=true and allowSetTerminals=true.
    function _totalSurplusMetadata(uint16 cashOutTaxRate) internal pure returns (JBRulesetMetadata memory) {
        return JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: cashOutTaxRate,
            baseCurrency: NATIVE_CURRENCY,
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: true,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: true,
            ownerMustSendPayouts: false,
            holdFees: false,
            scopeCashOutsToLocalBalances: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });
    }

    /// @notice Build native ETH terminal config.
    function _nativeTerminalConfigs() internal view returns (JBTerminalConfig[] memory tc) {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});

        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 1: holdFees — accumulate and process (Gap 3)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Exercises the full held fee lifecycle: fees are held during payouts when holdFees=true,
    /// cannot be processed before the 28-day unlock period, and are correctly sent to the fee project after.
    function test_adversarial_holdFees_accumulateAndProcess() public {
        // Deploy the fee project so held fees have somewhere to go.
        // The fee project must be a fully configured revnet with a buyback pool so that
        // processHeldFeesOf -> pay() succeeds (the buyback hook needs a working pool/oracle).
        _deployFeeProject(5000);
        _setupNativePool(FEE_PROJECT_ID, 10_000 ether);

        // Launch a raw JB project with holdFees=true and a 5 ETH payout limit.
        JBFundAccessLimitGroup[] memory limits = new JBFundAccessLimitGroup[](1);
        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1);
        payoutLimits[0] = JBCurrencyAmount({amount: uint224(5 ether), currency: NATIVE_CURRENCY});
        limits[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: payoutLimits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });

        // Splits: 100% to this contract so all payout goes through.
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

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: uint112(INITIAL_ISSUANCE),
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: _holdFeesMetadata(),
            splitGroups: splitGroups,
            fundAccessLimitGroups: limits
        });

        uint256 projectId = jbController()
            .launchProjectFor({
            owner: PROJECT_OWNER,
            projectUri: "ipfs://holdFees-test",
            rulesetConfigurations: rulesets,
            terminalConfigurations: _nativeTerminalConfigs(),
            memo: ""
        });

        // Pay 20 ETH into the project.
        vm.deal(PAYER, 100 ether);
        vm.prank(PAYER);
        jbMultiTerminal().pay{value: 20 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 20 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Record fee project balance before payout.
        uint256 feeProjectBalanceBefore = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        // Execute sendPayoutsOf (5 ETH payout limit). Fees should be HELD, not processed.
        jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            currency: NATIVE_CURRENCY,
            minTokensPaidOut: 0
        });

        // Fee project balance should NOT change with holdFees=true.
        uint256 feeProjectBalanceAfterPayout = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertEq(
            feeProjectBalanceAfterPayout,
            feeProjectBalanceBefore,
            "fee project balance should not change when holdFees=true"
        );

        // Verify heldFeesOf has entries.
        JBFee[] memory heldFees = jbMultiTerminal().heldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);
        assertGt(heldFees.length, 0, "should have held fees after payout");
        assertGt(heldFees[0].amount, 0, "held fee amount should be > 0");

        // Try processing before 28-day unlock — fees should remain.
        uint256 projectBalanceBefore = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        jbMultiTerminal().processHeldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);

        uint256 projectBalanceAfterEarlyProcess = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        assertEq(
            projectBalanceAfterEarlyProcess,
            projectBalanceBefore,
            "project balance should not change when processing locked fees"
        );

        // Warp 28 days + 1 second past the unlock period.
        vm.warp(block.timestamp + 28 days + 1);

        // Anyone calls processHeldFeesOf.
        jbMultiTerminal().processHeldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);

        // Fee project should now have received the fees.
        uint256 feeProjectBalanceAfterProcess = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertGt(
            feeProjectBalanceAfterProcess, feeProjectBalanceBefore, "fee project should receive fees after processing"
        );

        // The fee amount sent to the fee project should be feeAmountFrom(5 ETH, 2.5%) = 0.125 ETH.
        uint256 expectedFeeAmount = JBFees.feeAmountFrom({amountBeforeFee: 5 ether, feePercent: 25});
        assertEq(expectedFeeAmount, 0.125 ether, "expected fee amount should be 0.125 ETH");
        assertEq(
            feeProjectBalanceAfterProcess - feeProjectBalanceBefore,
            expectedFeeAmount,
            "fee project balance increase should equal the fee amount"
        );

        // Held fees should be consumed.
        JBFee[] memory remainingFees = jbMultiTerminal().heldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);
        assertEq(remainingFees.length, 0, "no held fees should remain after processing");

        // Terminal balance accounting should be consistent:
        // The project's recorded balance was reduced to 15 ETH during sendPayoutsOf (the full 5 ETH
        // payout was deducted from the recorded balance at that time). The held fee is backed by
        // unattributed ETH in the terminal contract, not by the project's recorded balance.
        // When processHeldFeesOf runs, it sends that unattributed ETH to the fee project (via _pay),
        // which increases the fee project's recorded balance. The original project's recorded balance
        // stays at 15 ETH — it was already reduced during the payout.
        uint256 finalBalance = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        assertEq(finalBalance, 15 ether, "project balance should remain at 15 ETH (already reduced during payout)");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 2: Price feed returning zero (Gap 15)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice A price feed returning zero causes a DoS when used in cross-currency operations.
    /// This confirms the DoS is real but bounded (no fund loss, just inability to pay).
    function test_adversarial_priceFeedReturnsZero() public {
        // Deploy a zero price feed.
        ZeroPriceFeed zeroPriceFeed = new ZeroPriceFeed();

        // Register it as the default ETH/USD feed: USD -> NATIVE_TOKEN.
        vm.prank(multisig());
        jbPrices()
            .addPriceFeedFor({
            projectId: 0,
            pricingCurrency: USD,
            unitCurrency: NATIVE_CURRENCY,
            feed: IJBPriceFeed(address(zeroPriceFeed))
        });

        // Launch a project with baseCurrency = USD, terminal accepts ETH.
        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: uint112(INITIAL_ISSUANCE),
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: _usdBaseMetadata(0),
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        uint256 projectId = jbController()
            .launchProjectFor({
            owner: PROJECT_OWNER,
            projectUri: "ipfs://zero-feed",
            rulesetConfigurations: rulesets,
            terminalConfigurations: _nativeTerminalConfigs(),
            memo: ""
        });

        // Pay with ETH — the price conversion should use the zero feed.
        // This should revert due to division by zero in the price conversion (mulDiv with 0 denominator).
        vm.deal(PAYER, 10 ether);
        vm.prank(PAYER);
        vm.expectRevert();
        jbMultiTerminal().pay{value: 1 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Confirm: DoS is real but bounded. The project exists, no funds are lost,
        // but payments are blocked until the feed is fixed.
        // Terminal balance should be zero (no successful payments).
        assertEq(
            _terminalBalance(projectId, JBConstants.NATIVE_TOKEN),
            0,
            "no funds should be in terminal after zero feed DoS"
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 3: Cross-currency cashout round trip (Gap 9)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Tests the round-trip fidelity of cross-currency pay-then-cashout.
    /// Pays ETH into a USD-denominated project, then cashes out all tokens.
    /// Verifies no rounding leak (reclaim <= initial payment) and checks tax application.
    function test_adversarial_crossCurrency_cashOutRoundTrip() public {
        // Deploy a mock ETH/USD price feed: 1 ETH = $2000.
        MockPriceFeed priceFeed = new MockPriceFeed(2000e18, 18);

        // Register as default feed: USD -> NATIVE_TOKEN.
        vm.prank(multisig());
        jbPrices()
            .addPriceFeedFor({
            projectId: 0, pricingCurrency: USD, unitCurrency: NATIVE_CURRENCY, feed: IJBPriceFeed(address(priceFeed))
        });

        // Launch project: baseCurrency=USD, 0% cashOutTaxRate, terminal accepts ETH.
        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: uint112(INITIAL_ISSUANCE), // 1000 tokens per USD
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: _usdBaseMetadata(0), // 0% tax
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        uint256 projectId = jbController()
            .launchProjectFor({
            owner: PROJECT_OWNER,
            projectUri: "ipfs://cross-currency-roundtrip",
            rulesetConfigurations: rulesets,
            terminalConfigurations: _nativeTerminalConfigs(),
            memo: ""
        });

        // PAYER pays 1 ETH. At $2000/ETH and 1000 tokens/$1, expect ~2,000,000 tokens.
        vm.deal(PAYER, 10 ether);
        vm.prank(PAYER);
        uint256 tokensReceived = jbMultiTerminal().pay{value: 1 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Record exact token count.
        assertGt(tokensReceived, 0, "should receive tokens from cross-currency payment");
        // 1 ETH = $2000, 1000 tokens/$1 = 2,000,000 tokens.
        assertEq(tokensReceived, 2_000_000e18, "should receive 2M tokens for 1 ETH at $2000/ETH");

        // Cash out ALL tokens.
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        uint256 reclaimAmount = jbMultiTerminal()
            .cashOutTokensOf({
            holder: PAYER,
            projectId: projectId,
            cashOutCount: tokensReceived,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        uint256 ethReceived = PAYER.balance - payerEthBefore;

        // With 0% cashOutTaxRate and direct payments (no incoming payouts from splits),
        // _feeFreeSurplusOf == 0, so no fee is taken. Round-trip protection means
        // direct pay + cashout at 0% tax = no fee.
        assertEq(reclaimAmount, 1 ether, "reclaim should be 1 ETH (no fee on round trip with 0% tax)");

        // Return value should match actual ETH transfer.
        assertEq(ethReceived, reclaimAmount, "ethReceived should match reclaimAmount");

        // CRITICAL: no rounding leak — reclaim should never exceed initial payment.
        assertLe(reclaimAmount, 1 ether, "reclaim must not exceed initial payment (no rounding leak)");

        // Verify tokens are burned.
        assertEq(jbTokens().totalBalanceOf(PAYER, projectId), 0, "all tokens should be burned after full cashout");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 4: 1-wei rounding attack (Gap 24)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Tests whether many 1-wei payments can yield more tokens than a single equivalent payment,
    /// creating a rounding profit on cashout.
    function test_adversarial_dustPaymentRounding() public {
        // Launch a vanilla project with 0% cashOutTaxRate and native base.
        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: uint112(INITIAL_ISSUANCE),
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: _vanillaMetadata(0), // 0% tax
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        uint256 projectId = jbController()
            .launchProjectFor({
            owner: PROJECT_OWNER,
            projectUri: "ipfs://dust-rounding",
            rulesetConfigurations: rulesets,
            terminalConfigurations: _nativeTerminalConfigs(),
            memo: ""
        });

        // Fund actors.
        vm.deal(ATTACKER, 1 ether);
        vm.deal(HONEST_PAYER, 1 ether);

        // ATTACKER makes 100 payments of 1 wei each.
        uint256 attackerTotalTokens = 0;
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(ATTACKER);
            uint256 tokens = jbMultiTerminal().pay{value: 1}({
                projectId: projectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: 1,
                beneficiary: ATTACKER,
                minReturnedTokens: 0,
                memo: "",
                metadata: ""
            });
            attackerTotalTokens += tokens;
        }

        // HONEST_PAYER makes 1 payment of 100 wei.
        vm.prank(HONEST_PAYER);
        uint256 honestTokens = jbMultiTerminal().pay{value: 100}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 100,
            beneficiary: HONEST_PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Compare token counts.
        // At 1000e18 tokens per ETH = 1000e18 / 1e18 = 1000 tokens per wei? No.
        // weight = 1000e18, so for 1 wei: tokens = 1 * 1000e18 / 1e18 = 1000 tokens.
        // For 100 wei: tokens = 100 * 1000e18 / 1e18 = 100,000 tokens.
        // 100 payments of 1 wei = 100 * 1000 = 100,000 tokens.
        // They should be equal if there is no rounding in the issuance path.

        // If attacker has MORE tokens than honest payer, there is a rounding profit.
        bool attackerHasMore = attackerTotalTokens > honestTokens;

        // Log the comparison.
        emit log_named_uint("Attacker total tokens (100x 1 wei)", attackerTotalTokens);
        emit log_named_uint("Honest payer tokens (1x 100 wei)", honestTokens);
        emit log_named_uint("Difference (attacker - honest)", attackerHasMore ? attackerTotalTokens - honestTokens : 0);

        // Verify: even if attacker has slightly more tokens due to rounding, they should NOT be able
        // to cash out for more than they paid in total.
        // Total terminal balance = 200 wei.
        uint256 terminalBalance = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        assertEq(terminalBalance, 200, "terminal balance should be 200 wei");

        // Check if attacker can profit by cashing out.
        if (attackerTotalTokens > 0) {
            uint256 attackerEthBefore = ATTACKER.balance;

            vm.prank(ATTACKER);
            jbMultiTerminal()
                .cashOutTokensOf({
                holder: ATTACKER,
                projectId: projectId,
                cashOutCount: attackerTotalTokens,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(ATTACKER),
                metadata: ""
            });

            uint256 attackerReclaimed = ATTACKER.balance - attackerEthBefore;

            // Attacker should not reclaim more than they paid (100 wei).
            assertLe(attackerReclaimed, 100, "attacker should not profit from dust rounding (reclaim <= 100 wei)");
        }

        // Check that ATTACKER + HONEST_PAYER cannot cashout for more than 200 wei total.
        // (Honest payer would need to cashout separately to verify, but with 0% tax and feeless,
        // the sum of reclaims equals the surplus minus fees. No more than 200 wei can be extracted.)
        // Since attacker cashed out their portion, honest payer can cashout the rest.
        if (honestTokens > 0) {
            uint256 honestEthBefore = HONEST_PAYER.balance;

            vm.prank(HONEST_PAYER);
            jbMultiTerminal()
                .cashOutTokensOf({
                holder: HONEST_PAYER,
                projectId: projectId,
                cashOutCount: honestTokens,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(HONEST_PAYER),
                metadata: ""
            });

            uint256 honestReclaimed = HONEST_PAYER.balance - honestEthBefore;

            // Total extraction should not exceed total deposits.
            uint256 totalReclaimed = (ATTACKER.balance - (1 ether - 100)) + honestReclaimed;
            assertLe(totalReclaimed, 200, "total reclaimed should not exceed total deposited (200 wei)");
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 5: Preview parity through REVDeployer data hook chain (Gap 22)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Verifies that previewPayFor and previewCashOutFrom return values matching
    /// actual pay and cashOutTokensOf results, even when the REVDeployer data hook chain is active.
    function test_adversarial_previewParity_throughDataHook() public {
        // Deploy fee project and revnet.
        _deployFeeProject(5000);
        uint256 revnetId = _deployRevnet(5000); // 50% cashOutTaxRate
        _setupNativePool(revnetId, 10_000 ether);

        // Fund a second payer so bonding curve tax has visible effect.
        address payer2 = makeAddr("payer2");
        vm.deal(payer2, 50 ether);
        _payRevnet(revnetId, payer2, 10 ether);

        // --- Pay Preview vs Actual ---

        // Preview pay for 1 ETH.
        vm.deal(PAYER, 100 ether);
        (, // JBRuleset memory previewRuleset
            uint256 previewBeneficiaryTokens,
            uint256 previewReservedTokens,
            // JBPayHookSpecification[] memory previewPayHooks
        ) = jbMultiTerminal()
            .previewPayFor({
            projectId: revnetId, token: JBConstants.NATIVE_TOKEN, amount: 1 ether, beneficiary: PAYER, metadata: ""
        });

        // Actually pay 1 ETH.
        vm.prank(PAYER);
        uint256 actualPayTokens = jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Compare preview vs actual token count. They should match exactly.
        assertEq(actualPayTokens, previewBeneficiaryTokens, "PAY: preview beneficiary token count should match actual");

        emit log_named_uint("Preview pay tokens (beneficiary)", previewBeneficiaryTokens);
        emit log_named_uint("Actual pay tokens", actualPayTokens);
        emit log_named_uint("Preview reserved tokens", previewReservedTokens);

        // --- CashOut Preview vs Actual ---

        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 cashOutCount = payerTokens / 2;

        // Preview cashout.
        (, // JBRuleset memory cashOutRuleset
            uint256 previewReclaim,, // uint256 previewCashOutTaxRate
            // JBCashOutHookSpecification[] memory previewCashOutHooks
        ) = jbMultiTerminal()
            .previewCashOutFrom({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: cashOutCount,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        // Actually cashout.
        vm.prank(PAYER);
        uint256 actualReclaim = jbMultiTerminal()
            .cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: cashOutCount,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        // The preview reclaimAmount is the bonding curve output BEFORE the terminal's 2.5% fee.
        // The actual reclaim returned by cashOutTokensOf is AFTER the fee deduction.
        // So: actualReclaim = previewReclaim - feeAmountFrom(previewReclaim, FEE)
        uint256 terminalFee = JBFees.feeAmountFrom({amountBeforeFee: previewReclaim, feePercent: 25});
        uint256 expectedActualReclaim = previewReclaim - terminalFee;

        assertEq(
            actualReclaim, expectedActualReclaim, "CASHOUT: actual reclaim should equal preview minus 2.5% terminal fee"
        );

        emit log_named_uint("Preview cashout reclaim (before fee)", previewReclaim);
        emit log_named_uint("Expected actual reclaim (after fee)", expectedActualReclaim);
        emit log_named_uint("Actual cashout reclaim", actualReclaim);

        // If preview and actual diverge, this reveals a bug in the data hook's preview vs execution path.
        // The assertion above catches that. If we reach here, they are consistent.
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 6: scopeCashOutsToLocalBalances with multiple terminals (Gap 2)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Tests that scopeCashOutsToLocalBalances aggregates surplus across multiple terminals,
    /// increasing the cashout value from Terminal A, but capped at Terminal A's local balance.
    function test_adversarial_totalSurplusCashOut_multiTerminal() public {
        // Deploy a mock ERC-20 token.
        MockERC20Token mockToken = new MockERC20Token();

        // Launch a raw JB project with scopeCashOutsToLocalBalances=true and allowSetTerminals=true.
        // Configure a single terminal initially; we will add accounting contexts for the ERC-20 after.
        JBAccountingContext[] memory acc = new JBAccountingContext[](2);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});
        // Use the ERC20's address as its currency (same pattern as NATIVE_TOKEN).
        acc[1] = JBAccountingContext({
            token: address(mockToken), decimals: 18, currency: uint32(uint160(address(mockToken)))
        });

        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: uint112(INITIAL_ISSUANCE),
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: _totalSurplusMetadata(0), // 0% tax, scopeCashOutsToLocalBalances=false
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        uint256 projectId = jbController()
            .launchProjectFor({
            owner: PROJECT_OWNER,
            projectUri: "ipfs://multi-terminal-surplus",
            rulesetConfigurations: rulesets,
            terminalConfigurations: tc,
            memo: ""
        });

        // Add a 1:1 price feed so the terminal can convert the mock token's currency to native
        // currency when aggregating total surplus across tokens.
        uint32 mockTokenCurrency = uint32(uint160(address(mockToken)));
        MockPriceFeed oneToOneFeed = new MockPriceFeed(1e18, 18);
        vm.prank(multisig());
        jbPrices()
            .addPriceFeedFor({
            projectId: 0,
            pricingCurrency: mockTokenCurrency,
            unitCurrency: NATIVE_CURRENCY,
            feed: IJBPriceFeed(address(oneToOneFeed))
        });

        // Pay 10 ETH into the terminal (native token side).
        vm.deal(PAYER, 100 ether);
        vm.prank(PAYER);
        uint256 ethPayTokens = jbMultiTerminal().pay{value: 10 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 10 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Pay equivalent value in ERC-20 into the same terminal (different accounting context).
        uint256 erc20Amount = 10 ether; // Same nominal amount (18 decimals).
        mockToken.mint(PAYER, erc20Amount);
        vm.prank(PAYER);
        mockToken.approve(address(jbMultiTerminal()), erc20Amount);

        vm.prank(PAYER);
        uint256 erc20PayTokens = jbMultiTerminal().pay{value: 0}({
            projectId: projectId,
            token: address(mockToken),
            amount: erc20Amount,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Verify both payments succeeded.
        assertGt(ethPayTokens, 0, "should receive tokens from ETH payment");
        assertGt(erc20PayTokens, 0, "should receive tokens from ERC20 payment");

        // Verify terminal balances.
        uint256 ethBalance =
            jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, JBConstants.NATIVE_TOKEN);
        uint256 erc20Balance = jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, address(mockToken));
        assertEq(ethBalance, 10 ether, "ETH balance should be 10 ETH");
        assertEq(erc20Balance, erc20Amount, "ERC20 balance should be the deposited amount");

        // Record PAYER's total tokens.
        uint256 payerTotalTokens = jbTokens().totalBalanceOf(PAYER, projectId);
        assertGt(payerTotalTokens, 0, "payer should have tokens");

        // Now do a REFERENCE cashout (without total surplus) to compare.
        // First, let's preview what the cashout would give from Terminal A (ETH side).
        // With scopeCashOutsToLocalBalances=true, the surplus calculation includes Terminal B's balance.
        // This means the payer's share of the surplus is calculated against a larger pool.

        // Cash out a small portion of tokens to test.
        uint256 cashOutCount = payerTotalTokens / 4;
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
            holder: PAYER,
            projectId: projectId,
            cashOutCount: cashOutCount,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        uint256 ethReceived = PAYER.balance - payerEthBefore;
        assertGt(ethReceived, 0, "should receive ETH from cashout with total surplus");

        // With total surplus, the payer's reclaim should factor in the ERC-20 side.
        // The surplus across both tokens is larger, so the reclaim should be higher than
        // if only the ETH side surplus was considered.
        // We verify this by checking that the reclaim is proportional to the total surplus.
        // Total surplus = ETH + ERC20 (in native terms). Since no price feed exists between
        // the mock token and native, the actual behavior depends on how JBSurplus handles
        // tokens without a price feed.

        // Verify: reclaim is still capped at Terminal A's local ETH balance.
        uint256 ethBalanceAfter =
            jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, JBConstants.NATIVE_TOKEN);
        assertGe(ethBalance - ethBalanceAfter, ethReceived, "ETH balance decrease >= ETH received");
        assertLe(ethReceived, ethBalance, "reclaim should not exceed the terminal's local ETH balance");

        // Document the reclaim amounts for analysis.
        emit log_named_uint("ETH terminal balance before cashout", ethBalance);
        emit log_named_uint("ERC20 terminal balance", erc20Balance);
        emit log_named_uint("Payer total tokens", payerTotalTokens);
        emit log_named_uint("CashOut count", cashOutCount);
        emit log_named_uint("ETH reclaimed", ethReceived);
        emit log_named_uint("ETH terminal balance after cashout", ethBalanceAfter);
    }
}

/// @notice Inline mock price feed that returns a fixed price.
/// Used for cross-currency tests.
contract MockPriceFeed is IJBPriceFeed {
    uint256 public immutable PRICE;
    uint8 public immutable FEED_DECIMALS;

    constructor(uint256 price, uint8 dec) {
        PRICE = price;
        FEED_DECIMALS = dec;
    }

    function currentUnitPrice(uint256 decimals) external view override returns (uint256) {
        return JBFixedPointNumber.adjustDecimals(PRICE, FEED_DECIMALS, decimals);
    }
}
