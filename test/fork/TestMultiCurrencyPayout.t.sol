// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {JBCurrencyAmount} from "@bananapus/core-v6/src/structs/JBCurrencyAmount.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

// Revnet
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Base and shared helpers.
import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";
import {MockERC20Token} from "../helpers/MockTokens.sol";
import {MockPriceFeed} from "../helpers/MockPriceFeed.sol";

/// @notice Multi-currency payout fork test with Chainlink price conversion.
///
/// Exercises USD-denominated payout limits paid from an ETH terminal, and USDC terminal
/// payouts with USD limits. Verifies price conversion consistency across JBPrices.
///
/// Run with: forge test --match-contract TestMultiCurrencyPayout -vvv
contract TestMultiCurrencyPayout is RevnetForkBase {
    // -- Currency constants
    uint32 constant USD = 2; // JBCurrencyIds.USD

    // -- Actors
    address SPLIT_RECIPIENT = makeAddr("mcp_splitRecipient");

    // -- Ecosystem contracts
    MockERC20Token usdc;

    // Currency helpers
    uint32 nativeCurrency;
    uint32 usdcCurrency;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_MultiPayout";
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setUp() public override {
        super.setUp();

        usdc = new MockERC20Token("Mock USDC", "USDC", 6);
        nativeCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));
        usdcCurrency = uint32(uint160(address(usdc)));

        // Mock geomean oracle so payments work.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Register price feeds: ETH/USD = 2000, USDC/USD = 1.
        MockPriceFeed ethUsdFeed = new MockPriceFeed(2000e18, 18);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, USD, nativeCurrency, IJBPriceFeed(address(ethUsdFeed)));

        MockPriceFeed usdcUsdFeed = new MockPriceFeed(1e6, 6);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, USD, usdcCurrency, IJBPriceFeed(address(usdcUsdFeed)));

        // Fund actors with extra ETH and USDC for multi-currency tests.
        vm.deal(PAYER, 200 ether);
        usdc.mint(PAYER, 500_000e6);
        vm.deal(SPLIT_RECIPIENT, 1 ether);
    }

    // ===================================================================
    //  Helpers
    // ===================================================================

    /// @notice Launch a plain JB project (not via REVDeployer) with explicit payout limits.
    function _launchProjectWithPayoutLimits(
        JBFundAccessLimitGroup[] memory limitGroups,
        JBTerminalConfig[] memory terminalConfigs,
        JBRulesetMetadata memory metadata
    )
        internal
        returns (uint256 projectId)
    {
        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](1);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(SPLIT_RECIPIENT),
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
            metadata: metadata,
            splitGroups: splitGroups,
            fundAccessLimitGroups: limitGroups
        });

        projectId = jbController()
            .launchProjectFor({
            owner: address(this),
            projectUri: "ipfs://mcp-test",
            rulesetConfigurations: rulesets,
            terminalConfigurations: terminalConfigs,
            memo: ""
        });
    }

    // ===================================================================
    //  Tests
    // ===================================================================

    /// @notice USD-denominated payout limit paid from ETH terminal.
    /// Pay 10 ETH, set a $5000 USD payout limit, send payouts in ETH.
    /// At $2000/ETH, 2.5 ETH should be distributed.
    function test_mcp_usdPayoutLimitPaidInETH() public {
        _deployFeeProject(5000);

        // Terminal accepts ETH.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Payout limit: $5000 USD, paid from the ETH terminal.
        JBFundAccessLimitGroup[] memory limits = new JBFundAccessLimitGroup[](1);
        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1);
        payoutLimits[0] = JBCurrencyAmount({amount: 5000e18, currency: USD}); // $5000 in 18-decimal USD
        limits[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: payoutLimits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });

        JBRulesetMetadata memory metadata = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 5000,
            baseCurrency: USD,
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
            holdFees: false,
            scopeCashOutsToLocalBalances: true,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        uint256 projectId = _launchProjectWithPayoutLimits(limits, tc, metadata);

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

        assertEq(_terminalBalance(projectId, JBConstants.NATIVE_TOKEN), 10 ether, "balance should be 10 ETH");

        // Send payouts: $5000 USD limit at $2000/ETH = 2.5 ETH.
        uint256 recipientBefore = SPLIT_RECIPIENT.balance;
        jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId, token: JBConstants.NATIVE_TOKEN, amount: 5000e18, currency: USD, minTokensPaidOut: 0
        });

        uint256 recipientReceived = SPLIT_RECIPIENT.balance - recipientBefore;

        // 2.5 ETH minus 2.5% fee. Fee = 2.5 ETH * 25 / 1000 = 0.0625 ETH.
        // Expected: ~2.4375 ETH. Allow some rounding tolerance.
        uint256 expectedPayout = 2.5 ether;
        uint256 expectedFee = expectedPayout * 25 / 1000;
        uint256 expectedNet = expectedPayout - expectedFee;

        assertApproxEqAbs(recipientReceived, expectedNet, 100, "recipient should receive ~2.4375 ETH after fee");

        // Remaining balance should be ~7.5 ETH.
        uint256 remaining = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        assertApproxEqAbs(remaining, 7.5 ether, 100, "remaining balance should be ~7.5 ETH");
    }

    /// @notice USDC terminal with USDC-denominated payout limit.
    /// Pay 10,000 USDC, set 5000 USDC payout limit, send payouts in USDC.
    /// 5000 USDC should be distributed.
    ///
    /// NOTE: Payout limits use the token's own currency (usdcCurrency) and the token's native
    /// decimal precision (6 for USDC). When currency == accountingContext.currency, the
    /// JBTerminalStore takes the fast path (amountPaidOut = amount) with no price conversion,
    /// so amounts must match the token's stored balance precision.
    function test_mcp_usdPayoutLimitPaidInUSDC() public {
        _deployFeeProject(5000);

        // Terminal accepts USDC.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: address(usdc), decimals: 6, currency: usdcCurrency});
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Payout limit: 5000 USDC in the token's native 6-decimal format.
        JBFundAccessLimitGroup[] memory limits = new JBFundAccessLimitGroup[](1);
        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1);
        payoutLimits[0] = JBCurrencyAmount({amount: 5000e6, currency: usdcCurrency});

        limits[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: address(usdc),
            payoutLimits: payoutLimits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });

        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](1);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(SPLIT_RECIPIENT),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });
        splitGroups[0] = JBSplitGroup({groupId: uint256(uint160(address(usdc))), splits: splits});

        JBRulesetMetadata memory metadata = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 5000,
            baseCurrency: usdcCurrency,
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
            holdFees: false,
            scopeCashOutsToLocalBalances: true,
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
            projectUri: "ipfs://mcp-usdc",
            rulesetConfigurations: rulesets,
            terminalConfigurations: tc,
            memo: ""
        });

        // Pay 10,000 USDC.
        vm.startPrank(PAYER);
        usdc.approve(address(jbMultiTerminal()), 10_000e6);
        jbMultiTerminal()
            .pay({
            projectId: projectId,
            token: address(usdc),
            amount: 10_000e6,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
        vm.stopPrank();

        uint256 balance = jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, address(usdc));
        assertEq(balance, 10_000e6, "balance should be 10,000 USDC");

        // Send payouts: 5000 USDC payout limit, same currency as accounting context.
        uint256 recipientBefore = usdc.balanceOf(SPLIT_RECIPIENT);
        jbMultiTerminal()
            .sendPayoutsOf({
            projectId: projectId, token: address(usdc), amount: 5000e6, currency: usdcCurrency, minTokensPaidOut: 0
        });

        uint256 recipientReceived = usdc.balanceOf(SPLIT_RECIPIENT) - recipientBefore;

        // 5000 USDC minus 2.5% fee = 4875 USDC.
        uint256 expectedNet = 5000e6 - (5000e6 * 25 / 1000);
        assertApproxEqAbs(recipientReceived, expectedNet, 100, "recipient should receive ~4875 USDC after fee");
    }

    /// @notice Verify price conversion consistency: paying equivalent USD amounts via ETH vs USDC
    /// should produce the same token count.
    function test_mcp_priceConversionConsistency() public {
        _deployFeeProject(5000);

        // Deploy a USD-base revnet accepting both ETH and USDC.
        JBAccountingContext[] memory acc = new JBAccountingContext[](2);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});
        acc[1] = JBAccountingContext({token: address(usdc), decimals: 6, currency: usdcCurrency});
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
            description: REVDescription("CC Parity", "CCP", "ipfs://ccp", "CCP_SALT"),
            baseCurrency: USD,
            operator: multisig(),
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("CCP"))
        });

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 1 ETH (= $2000 at mock price).
        vm.prank(PAYER);
        uint256 tokensFromETH = jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Pay 2000 USDC (= $2000 at mock price).
        address payer2 = makeAddr("mcp_payer2");
        usdc.mint(payer2, 2000e6);
        vm.startPrank(payer2);
        usdc.approve(address(jbMultiTerminal()), 2000e6);
        uint256 tokensFromUSDC = jbMultiTerminal()
            .pay({
            projectId: revnetId,
            token: address(usdc),
            amount: 2000e6,
            beneficiary: payer2,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
        vm.stopPrank();

        // Both should receive the same number of tokens (equivalent $2000 payments).
        assertEq(tokensFromETH, tokensFromUSDC, "1 ETH and 2000 USDC should mint the same tokens at $2000/ETH");
        assertGt(tokensFromETH, 0, "should receive tokens");
    }
}
