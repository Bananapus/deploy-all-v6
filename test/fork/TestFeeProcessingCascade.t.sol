// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";

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
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {IREVLoans} from "@rev-net/core-v6/src/interfaces/IREVLoans.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

// Uniswap V4
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Fee processing cascade fork test.
///
/// Exercises the held fee lifecycle: fees are held during cashouts, accumulate over 28 days,
/// and are then processed to the fee beneficiary project (#1). Tests what happens when
/// fee processing succeeds and when it encounters edge cases.
///
/// Run with: forge test --match-contract TestFeeProcessingCascade -vvv
contract TestFeeProcessingCascade is TestBaseWorkflow {
    // -- Mainnet addresses
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    // -- Test parameters
    uint112 constant INITIAL_ISSUANCE = uint112(1000e18);

    // -- Actors
    address PAYER = makeAddr("fee_payer");
    address PAYER2 = makeAddr("fee_payer2");

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
    REVDeployer REV_DEPLOYER;

    receive() external payable {}

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
            projects: jbProjects(),
            revId: FEE_PROJECT_ID,
            owner: address(this),
            permit2: permit2(),
            trustedForwarder: TRUSTED_FORWARDER
        });

        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_Fee"}(
            jbController(),
            SUCKER_REGISTRY,
            FEE_PROJECT_ID,
            HOOK_DEPLOYER,
            PUBLISHER,
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            address(LOANS_CONTRACT),
            TRUSTED_FORWARDER
        );

        vm.prank(multisig());
        jbProjects().approve(address(REV_DEPLOYER), FEE_PROJECT_ID);

        // Mock geomean oracle.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Fund actors.
        vm.deal(PAYER, 200 ether);
        vm.deal(PAYER2, 100 ether);
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
            description: REVDescription("Fee", "FEE", "ipfs://fee", "FEE_FPC"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("FEE_FPC"))
        });

        vm.prank(multisig());
        REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

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

        projectId = jbController().launchProjectFor({
            owner: address(this),
            projectUri: "ipfs://fee-held",
            rulesetConfigurations: rulesets,
            terminalConfigurations: tc,
            memo: ""
        });
    }

    function _terminalBalance(uint256 projectId, address token) internal view returns (uint256) {
        return jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, token);
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

        jbMultiTerminal().sendPayoutsOf({
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
            feeProjectBalanceAfterPayout,
            feeProjectBalanceBefore,
            "fee project balance should not change with holdFees"
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
            feeProjectBalanceAfterProcess,
            feeProjectBalanceBefore,
            "fee project should receive fees after processing"
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
        uint256 reclaimed = jbMultiTerminal().cashOutTokensOf({
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
        jbMultiTerminal().sendPayoutsOf({
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

        // Held fees should be reduced or eliminated.
        JBFee[] memory remainingFees = jbMultiTerminal().heldFeesOf(projectId, JBConstants.NATIVE_TOKEN, 10);
        assertLt(remainingFees.length, heldFees.length, "held fees should be reduced after return");
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

        uint256 projectId = jbController().launchProjectFor({
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
        jbMultiTerminal().sendPayoutsOf({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            minTokensPaidOut: 0
        });

        // Advance time by 1 day.
        vm.warp(block.timestamp + 1 days);

        // Send second payout of 3 ETH (creates second held fee with later unlock).
        jbMultiTerminal().sendPayoutsOf({
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
}
