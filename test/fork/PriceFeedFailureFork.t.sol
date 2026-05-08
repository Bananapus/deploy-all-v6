// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBFixedPointNumber} from "@bananapus/core-v6/src/libraries/JBFixedPointNumber.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {JBCurrencyAmount} from "@bananapus/core-v6/src/structs/JBCurrencyAmount.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";

/// @notice Controllable price feed mock — can toggle between returning a price and reverting.
contract ControllablePriceFeed is IJBPriceFeed {
    uint256 public price;
    uint8 public feedDecimals;
    bool public shouldRevert;

    constructor(uint256 _price, uint8 _feedDecimals) {
        price = _price;
        feedDecimals = _feedDecimals;
    }

    function setRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function currentUnitPrice(uint256 decimals) external view override returns (uint256) {
        if (shouldRevert) revert("STALE_FEED");
        return JBFixedPointNumber.adjustDecimals(price, feedDecimals, decimals);
    }
}

/// @notice Tests that price feed failures correctly block cross-currency operations
/// and that recovery restores functionality.
///
/// Run with: forge test --match-contract PriceFeedFailureForkTest -vvv
contract PriceFeedFailureForkTest is TestBaseWorkflow {
    uint32 constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));
    uint32 constant USD = 2; // JBCurrencyIds.USD

    uint112 constant WEIGHT = 1000e18; // 1000 tokens per ETH

    address PAYER = makeAddr("payer");
    address PROJECT_OWNER = makeAddr("projectOwner");

    ControllablePriceFeed feed;

    uint256 projectId;

    receive() external payable {}

    function setUp() public override {
        super.setUp();

        // Deploy controllable ETH/USD feed: 1 ETH = 2000 USD.
        feed = new ControllablePriceFeed(2000e18, 18);

        // Register as default feed: USD → NATIVE_TOKEN (inverse auto-calculated).
        vm.prank(multisig());
        jbPrices()
            .addPriceFeedFor({
            projectId: 0, pricingCurrency: USD, unitCurrency: NATIVE_CURRENCY, feed: IJBPriceFeed(address(feed))
        });

        vm.deal(PAYER, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Build metadata with USD base currency.
    function _usdMetadata() internal pure returns (JBRulesetMetadata memory) {
        return JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
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

    /// @notice Build metadata with native ETH base currency.
    function _ethMetadata() internal pure returns (JBRulesetMetadata memory) {
        return JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 5000, // 50% tax for cashout tests
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
            scopeCashOutsToLocalBalances: true,
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

    /// @notice Launch a project with USD base currency, ETH terminal, and USD-denominated payout limits.
    function _launchCrossCurrencyProject(uint224 payoutLimitUSD) internal returns (uint256) {
        JBCurrencyAmount[] memory limits = new JBCurrencyAmount[](1);
        limits[0] = JBCurrencyAmount({amount: payoutLimitUSD, currency: USD});

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
            duration: 0,
            weight: WEIGHT,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: _usdMetadata(),
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: groups
        });

        return jbController()
            .launchProjectFor({
            owner: PROJECT_OWNER,
            projectUri: "test://price-feed-failure",
            rulesetConfigurations: rulesets,
            terminalConfigurations: _terminalConfigs(),
            memo: ""
        });
    }

    /// @notice Launch a same-currency project (ETH base, ETH terminal, ETH payout limits).
    function _launchSameCurrencyProject(uint224 payoutLimit) internal returns (uint256) {
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
            duration: 0,
            weight: WEIGHT,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: _ethMetadata(),
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: groups
        });

        return jbController()
            .launchProjectFor({
            owner: PROJECT_OWNER,
            projectUri: "test://same-currency",
            rulesetConfigurations: rulesets,
            terminalConfigurations: _terminalConfigs(),
            memo: ""
        });
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

    /// @notice Cross-currency payouts revert when the price feed fails (DoS, not fund loss).
    function test_priceFeedFailure_staleFeedBlocksPayout() public {
        // Launch project: USD base, 1000 USD payout limit, ETH terminal.
        projectId = _launchCrossCurrencyProject(1000e18);

        // Fund it.
        _pay(projectId, 5 ether);

        // Break the feed.
        feed.setRevert(true);

        // Attempt payout — should revert because price conversion fails.
        vm.prank(PROJECT_OWNER);
        vm.expectRevert();
        jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 500e18, // 500 USD worth
            currency: USD,
            minTokensPaidOut: 0
        });
    }

    /// @notice Same-currency payouts succeed even when the price feed is broken (no conversion needed).
    function test_priceFeedFailure_sameCurrencyPayoutSucceeds() public {
        // Launch project with ETH base + ETH limits (no cross-currency).
        uint256 sameCurrencyProject = _launchSameCurrencyProject(2 ether);

        // Fund it.
        _pay(sameCurrencyProject, 5 ether);

        // Break the feed.
        feed.setRevert(true);

        // Same-currency payout should succeed — no price conversion needed.
        vm.prank(PROJECT_OWNER);
        uint256 paid = jbMultiTerminal()
            .sendPayoutsOf({
            projectId: sameCurrencyProject,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            currency: NATIVE_CURRENCY,
            minTokensPaidOut: 0
        });
        assertGt(paid, 0, "Same-currency payout should work with broken feed");
    }

    /// @notice Cashouts on cross-currency projects revert when the feed fails.
    function test_priceFeedFailure_cashOutWithStaleFeedReverts() public {
        // Launch cross-currency project (USD base, ETH terminal).
        projectId = _launchCrossCurrencyProject(1000e18);

        // Pay to get tokens.
        uint256 tokens = _pay(projectId, 5 ether);
        assertGt(tokens, 0, "Should receive tokens");

        // Break the feed.
        feed.setRevert(true);

        // Cashout should revert — surplus calculation requires price conversion.
        vm.prank(PAYER);
        vm.expectRevert();
        jbMultiTerminal()
            .cashOutTokensOf({
            holder: PAYER,
            projectId: projectId,
            cashOutCount: tokens / 2,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });
    }

    /// @notice Once a broken feed recovers, payouts resume — DoS not fund loss.
    function test_priceFeedFailure_feedRecovery_payoutSucceeds() public {
        // Launch cross-currency project.
        projectId = _launchCrossCurrencyProject(1000e18);

        // Fund it.
        _pay(projectId, 5 ether);

        // Break → payout fails.
        feed.setRevert(true);

        vm.prank(PROJECT_OWNER);
        vm.expectRevert();
        jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId, token: JBConstants.NATIVE_TOKEN, amount: 500e18, currency: USD, minTokensPaidOut: 0
        });

        // Recover feed.
        feed.setRevert(false);

        // Now payout should succeed.
        vm.prank(PROJECT_OWNER);
        uint256 paid = jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId, token: JBConstants.NATIVE_TOKEN, amount: 500e18, currency: USD, minTokensPaidOut: 0
        });
        assertGt(paid, 0, "Payout should succeed after feed recovery");
    }
}
