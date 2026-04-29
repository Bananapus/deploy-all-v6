// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";
import "./EcosystemFork.t.sol";

/// @notice Tests the sucker exemption path in REVDeployer.beforeCashOutRecordedWith when a buyback hook is active.
///
/// Suckers get special treatment: zero tax, full pro-rata reclaim, no fees, no hook delegation.
/// These tests verify that the sucker path bypasses all of that — even when a buyback hook is deployed.
///
/// Run with: forge test --match-contract SuckerBuybackForkTest -vvv
contract SuckerBuybackForkTest is EcosystemForkTest {
    address MOCK_SUCKER = makeAddr("mockSucker");
    address NON_SUCKER = makeAddr("nonSucker");

    /// @notice Deploy a single-stage revnet with buyback hook active and a meaningful cashOutTaxRate.
    /// No pool setup — the buyback hook is registered but pre-AMM (no liquidity).
    function _deployRevnetForSuckerTest(uint16 cashOutTaxRate) internal returns (uint256 revnetId) {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(multisig()),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 0, // No reserved tokens — simplifies token accounting.
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: cashOutTaxRate,
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("SuckerTest", "SKRT", "ipfs://sucker", "SUCKER_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("SUCKER_TEST"))
        });

        (revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

    /// @notice Mock the sucker registry so that `mockSucker` is recognized as a sucker for the given project.
    function _registerMockSucker(uint256 revnetId) internal {
        vm.mockCall(
            address(SUCKER_REGISTRY),
            abi.encodeWithSignature("isSuckerOf(uint256,address)", revnetId, MOCK_SUCKER),
            abi.encode(true)
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 1: Sucker exemption — zero tax with buyback active
    // ═══════════════════════════════════════════════════════════════════

    /// @notice When a sucker cashes out, REVDeployer returns (0, cashOutCount, totalSupply, []).
    /// The buyback hook is NOT consulted. No fees are charged. Full pro-rata ETH reclaim.
    function test_suckerExemption_zeroTaxWithBuybackActive() public {
        // Deploy fee project so the fee terminal exists.
        _deployFeeProject(5000);

        // Deploy revnet with 70% cashOutTaxRate.
        uint256 revnetId = _deployRevnetForSuckerTest(7000);

        // Register the mock sucker.
        _registerMockSucker(revnetId);

        // Fund actors.
        vm.deal(MOCK_SUCKER, 100 ether);
        vm.deal(NON_SUCKER, 100 ether);

        // Pay into the revnet to create surplus and give the sucker tokens.
        // First, have someone else pay to create surplus (so sucker is not the only holder).
        _payRevnet(revnetId, NON_SUCKER, 10 ether);

        // Sucker pays to get tokens.
        uint256 suckerTokens = _payRevnet(revnetId, MOCK_SUCKER, 10 ether);
        assertGt(suckerTokens, 0, "sucker should receive tokens from payment");

        // Record fee project balance BEFORE sucker cashout.
        uint256 feeBalanceBefore = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        // Record sucker ETH balance before.
        uint256 suckerEthBefore = MOCK_SUCKER.balance;

        // Sucker cashes out all tokens.
        vm.prank(MOCK_SUCKER);
        uint256 reclaimAmount = jbMultiTerminal()
            .cashOutTokensOf({
            holder: MOCK_SUCKER,
            projectId: revnetId,
            cashOutCount: suckerTokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(MOCK_SUCKER),
            metadata: ""
        });

        // Sucker should receive ETH.
        assertGt(reclaimAmount, 0, "sucker should reclaim ETH");
        assertGt(MOCK_SUCKER.balance, suckerEthBefore, "sucker ETH balance should increase");

        // With 0% tax (sucker exemption) and sucker holding 50% of supply cashing out 50%:
        // Pro-rata reclaim from the 20 ETH surplus = 10 ETH (minus any rounding).
        // The bonding curve with 0% tax gives: surplus * cashOutCount / totalSupply = 20 * 50% = 10 ETH.
        assertEq(reclaimAmount, 10 ether, "sucker should reclaim full pro-rata share (0% tax)");

        // Fee project balance should NOT increase — sucker cashouts are fee-exempt.
        uint256 feeBalanceAfter = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertEq(feeBalanceAfter, feeBalanceBefore, "fee project should NOT receive fees from sucker cashout");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 2: Sucker vs non-sucker reclaim difference
    // ═══════════════════════════════════════════════════════════════════

    /// @notice A sucker reclaims more than a non-sucker cashing out the same token count.
    /// The fee project balance increases ONLY on the non-sucker cashout.
    function test_suckerVsNonSucker_reclaimDifference() public {
        // Deploy fee project so the fee terminal exists.
        _deployFeeProject(5000);

        // Deploy revnet with 70% cashOutTaxRate (high tax to make the difference obvious).
        uint256 revnetId = _deployRevnetForSuckerTest(7000);

        // Register the mock sucker.
        _registerMockSucker(revnetId);

        // Fund actors.
        vm.deal(MOCK_SUCKER, 100 ether);
        vm.deal(NON_SUCKER, 100 ether);

        // Both pay the same amount to get the same number of tokens.
        uint256 suckerTokens = _payRevnet(revnetId, MOCK_SUCKER, 10 ether);
        uint256 nonSuckerTokens = _payRevnet(revnetId, NON_SUCKER, 10 ether);

        // Both should have the same token count (same payment, same issuance rate).
        assertEq(suckerTokens, nonSuckerTokens, "both should receive same token count");

        // Cash out the same amount from each.
        uint256 cashOutCount = suckerTokens / 2; // Cash out half their tokens.

        // Record fee project balance before any cashouts.
        uint256 feeBalanceBefore = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        // --- Non-sucker cashes out first ---
        vm.prank(NON_SUCKER);
        uint256 nonSuckerReclaim = jbMultiTerminal()
            .cashOutTokensOf({
            holder: NON_SUCKER,
            projectId: revnetId,
            cashOutCount: cashOutCount,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(NON_SUCKER),
            metadata: ""
        });

        assertGt(nonSuckerReclaim, 0, "non-sucker should reclaim some ETH");

        // Fee project balance should increase from non-sucker cashout.
        uint256 feeBalanceAfterNonSucker = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertGt(
            feeBalanceAfterNonSucker, feeBalanceBefore, "fee project balance should increase from non-sucker cashout"
        );

        // --- Sucker cashes out second ---
        vm.prank(MOCK_SUCKER);
        uint256 suckerReclaim = jbMultiTerminal()
            .cashOutTokensOf({
            holder: MOCK_SUCKER,
            projectId: revnetId,
            cashOutCount: cashOutCount,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(MOCK_SUCKER),
            metadata: ""
        });

        assertGt(suckerReclaim, 0, "sucker should reclaim ETH");

        // Sucker should reclaim MORE than non-sucker (zero tax vs 70% tax + fees).
        assertGt(suckerReclaim, nonSuckerReclaim, "sucker reclaim should exceed non-sucker reclaim");

        // Fee project balance should NOT increase from sucker cashout.
        uint256 feeBalanceAfterSucker = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertEq(
            feeBalanceAfterSucker,
            feeBalanceAfterNonSucker,
            "fee project balance should NOT increase from sucker cashout"
        );
    }
}
