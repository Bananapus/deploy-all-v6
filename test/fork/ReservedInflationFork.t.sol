// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EcosystemForkTest} from "./EcosystemFork.t.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCashOuts} from "@bananapus/core-v6/src/libraries/JBCashOuts.sol";
import {JBFees} from "@bananapus/core-v6/src/libraries/JBFees.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDeploy721TiersHookConfig} from "@rev-net/core-v6/src/structs/REVDeploy721TiersHookConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVCroptopAllowedPost} from "@rev-net/core-v6/src/structs/REVCroptopAllowedPost.sol";
import {IJB721TiersHook} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHook.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

/// @notice Tests for H-4 CONFIRMED: Pending reserved tokens inflate `totalSupply`, reducing cashout value.
/// Verifies behavior in the context of REVDeployer's data hook composition chain (REVDeployer -> BuybackHook).
///
/// Run with: forge test --match-contract ReservedInflationForkTest -vvv
contract ReservedInflationForkTest is EcosystemForkTest {
    /// @notice Cash out with undistributed reserved tokens.
    /// Demonstrates that pending reserved tokens inflate totalSupply in the bonding curve,
    /// giving the payer less ETH than they would receive with 0% reserved.
    function test_reservedInflation_cashOutWithUndistributed() public {
        _deployFeeProject(5000);

        // Deploy revnet with 80% reserved (splitPercent = 8000).
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 8000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 100 ETH. Do NOT distribute reserved tokens.
        uint256 payerTokens = _payRevnet(revnetId, PAYER, 100 ether);

        // Verify payer received 20% of issuance (80% reserved).
        // 1000 tokens/ETH * 100 ETH = 100,000 tokens total. Payer gets 20% = 20,000 tokens.
        assertEq(payerTokens, 20_000e18, "payer should receive 20% of issuance (80% reserved)");

        // Check pending reserved tokens exist.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        assertGt(pending, 0, "should have pending reserved tokens");

        // Verify totalSupply includes pending reserved tokens.
        uint256 tokenSupply = jbTokens().totalSupplyOf(revnetId);
        uint256 totalSupplyWithReserved = jbController().totalTokenSupplyWithReservedTokensOf(revnetId);
        assertEq(totalSupplyWithReserved, tokenSupply + pending, "totalSupplyWithReserved = minted + pending");
        assertGt(totalSupplyWithReserved, tokenSupply, "totalSupplyWithReserved > minted supply");

        // Cash out half the payer's tokens.
        uint256 cashOutCount = payerTokens / 2;
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        uint256 reclaimAmount = jbMultiTerminal()
            .cashOutTokensOf({
                holder: PAYER,
                projectId: revnetId,
                cashOutCount: cashOutCount,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(PAYER),
                metadata: ""
            });

        uint256 ethReceived = PAYER.balance - payerEthBefore;
        assertGt(ethReceived, 0, "should receive ETH from cashout");

        // Calculate what payer WOULD get if reserved were 0% (totalSupply = payerTokens only).
        // With 0% reserved: totalSupply = 100,000 tokens, payer has 100,000 tokens, cashOutCount = 50,000.
        // But since we have 80% reserved, totalSupply is inflated by pending reserved tokens.
        // The bonding curve: base = surplus * cashOutCount / totalSupply
        // With pending reserved tokens inflating totalSupply, base is smaller.
        uint256 surplus = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN) + reclaimAmount; // pre-cashout surplus

        // Hypothetical reclaim with 0% reserved (totalSupply = payerTokens).
        uint256 hypotheticalReclaimNoReserved = JBCashOuts.cashOutFrom({
            surplus: surplus,
            cashOutCount: cashOutCount,
            totalSupply: payerTokens, // no reserved inflation
            cashOutTaxRate: 7000 // 70% tax
        });

        // Actual reclaim uses inflated totalSupply (includes pending reserved).
        // The payer gets LESS because their share of totalSupply is diluted by pending reserved tokens.
        assertLt(
            reclaimAmount,
            hypotheticalReclaimNoReserved,
            "H-4: payer gets LESS due to pending reserved token inflation in totalSupply"
        );

        // Document the magnitude of the reduction.
        uint256 reductionBps =
            ((hypotheticalReclaimNoReserved - reclaimAmount) * 10_000) / hypotheticalReclaimNoReserved;
        assertGt(reductionBps, 0, "reclaim reduction should be measurable");

        // With 80% reserved and 70% cashOutTaxRate, the inflation effect should be very significant.
        // The payer holds only 20% of totalSupplyWithReserved, so dilution is severe.
        emit log_named_uint("Reclaim with reserved inflation (wei)", reclaimAmount);
        emit log_named_uint("Hypothetical reclaim without reserved (wei)", hypotheticalReclaimNoReserved);
        emit log_named_uint("Reduction (basis points)", reductionBps);
    }

    /// @notice Distribute reserved tokens first, then cash out. Compare with undistributed case.
    /// The cashout value should be THE SAME whether or not reserved tokens are distributed first,
    /// because `totalTokenSupplyWithReservedTokensOf` includes pending reserved tokens either way.
    function test_reservedInflation_distributeFirst_comparesCashOut() public {
        _deployFeeProject(5000);

        // Deploy two identical revnets to compare behavior.
        // Revnet A: cash out WITHOUT distributing reserved tokens first.
        (REVConfig memory cfgA, JBTerminalConfig[] memory tcA, REVSuckerDeploymentConfig memory sdcA) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 8000);

        (uint256 revnetA,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfgA, terminalConfigurations: tcA, suckerDeploymentConfiguration: sdcA
        });

        // Revnet B: cash out AFTER distributing reserved tokens.
        (REVConfig memory cfgB, JBTerminalConfig[] memory tcB, REVSuckerDeploymentConfig memory sdcB) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 8000);
        // Use a different salt for revnet B to avoid collision.
        cfgB.description.salt = "ECO_SALT_B";

        (uint256 revnetB,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfgB, terminalConfigurations: tcB, suckerDeploymentConfiguration: sdcB
        });

        // Pay 100 ETH to both revnets.
        address payerA = makeAddr("payerA");
        address payerB = makeAddr("payerB");
        vm.deal(payerA, 200 ether);
        vm.deal(payerB, 200 ether);

        uint256 tokensA = _payRevnet(revnetA, payerA, 100 ether);
        uint256 tokensB = _payRevnet(revnetB, payerB, 100 ether);

        // Tokens received should be equal for identical configs.
        assertEq(tokensA, tokensB, "tokens received should match for identical configs");

        // Revnet B: distribute reserved tokens first.
        uint256 pendingB = jbController().pendingReservedTokenBalanceOf(revnetB);
        assertGt(pendingB, 0, "revnet B should have pending reserved");
        jbController().sendReservedTokensToSplitsOf(revnetB);
        assertEq(jbController().pendingReservedTokenBalanceOf(revnetB), 0, "pending should be zero after distribution");

        // Revnet A: do NOT distribute.
        uint256 pendingA = jbController().pendingReservedTokenBalanceOf(revnetA);
        assertGt(pendingA, 0, "revnet A should still have pending reserved");

        // Verify totalSupplyWithReserved is the same for both revnets.
        uint256 totalWithReservedA = jbController().totalTokenSupplyWithReservedTokensOf(revnetA);
        uint256 totalWithReservedB = jbController().totalTokenSupplyWithReservedTokensOf(revnetB);
        assertEq(
            totalWithReservedA, totalWithReservedB, "totalSupplyWithReserved should be equal regardless of distribution"
        );

        // Cash out half tokens from both revnets.
        uint256 cashOutCount = tokensA / 2;

        // Preview cashout for revnet A (undistributed).
        (, uint256 reclaimA,,) = jbMultiTerminal()
            .previewCashOutFrom({
                holder: payerA,
                projectId: revnetA,
                cashOutCount: cashOutCount,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                beneficiary: payable(payerA),
                metadata: ""
            });

        // Preview cashout for revnet B (distributed).
        (, uint256 reclaimB,,) = jbMultiTerminal()
            .previewCashOutFrom({
                holder: payerB,
                projectId: revnetB,
                cashOutCount: cashOutCount,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                beneficiary: payable(payerB),
                metadata: ""
            });

        // The reclaim amounts should be equal: distributing reserved tokens does not change the totalSupply
        // used in the bonding curve because `totalTokenSupplyWithReservedTokensOf` includes pending regardless.
        assertEq(reclaimA, reclaimB, "reclaim should be equal whether or not reserved tokens are distributed first");

        // Document the values.
        emit log_named_uint("Reclaim A (undistributed reserved)", reclaimA);
        emit log_named_uint("Reclaim B (distributed reserved)", reclaimB);
        emit log_named_uint("Pending reserved A", pendingA);
        emit log_named_uint("Total supply with reserved A", totalWithReservedA);
        emit log_named_uint("Total supply with reserved B", totalWithReservedB);
    }

    /// @notice Verify totalSupply consistency through the REVDeployer -> BuybackHook data hook chain.
    /// When no buyback pool is set, the buyback hook passes through context.totalSupply unchanged.
    /// Verify that this totalSupply matches jbTokens().totalSupplyOf() + pending reserved.
    function test_reservedInflation_hookComposition_totalSupplyConsistency() public {
        _deployFeeProject(5000);

        // Deploy revnet with 721 + buyback (no pool) + 50% reserved.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 5000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721Config();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // Pay a large amount to create significant pending reserved balance.
        uint256 payerTokens = _payRevnet(revnetId, PAYER, 100 ether);

        // Verify 50% reserved: payer gets 50% of issuance.
        assertEq(payerTokens, 50_000e18, "payer should receive 50% of issuance (50% reserved)");

        // Check pending reserved tokens.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        assertGt(pending, 0, "should have pending reserved tokens");

        // The totalSupply used in bonding curve = jbTokens().totalSupplyOf() + pending.
        uint256 mintedSupply = jbTokens().totalSupplyOf(revnetId);
        uint256 totalSupplyWithReserved = jbController().totalTokenSupplyWithReservedTokensOf(revnetId);
        assertEq(totalSupplyWithReserved, mintedSupply + pending, "totalSupplyWithReserved = minted + pending");

        // Preview cash out to capture the totalSupply used in the bonding curve calculation.
        uint256 cashOutCount = payerTokens / 2;

        (, uint256 reclaimAmount,,) = jbMultiTerminal()
            .previewCashOutFrom({
                holder: PAYER,
                projectId: revnetId,
                cashOutCount: cashOutCount,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                beneficiary: payable(PAYER),
                metadata: ""
            });

        // Manually compute what the bonding curve should return using totalSupplyWithReserved.
        uint256 surplus = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);

        // The REVDeployer splits the cashOutCount into fee and non-fee portions.
        // feeCashOutCount = cashOutCount * FEE / MAX_FEE = cashOutCount * 25 / 1000
        uint256 feeCashOutCount = (cashOutCount * 25) / 1000;
        uint256 nonFeeCashOutCount = cashOutCount - feeCashOutCount;

        // The REVDeployer computes postFeeReclaimedAmount using the bonding curve on the non-fee portion.
        uint256 expectedPostFeeReclaim = JBCashOuts.cashOutFrom({
            surplus: surplus,
            cashOutCount: nonFeeCashOutCount,
            totalSupply: totalSupplyWithReserved,
            cashOutTaxRate: 7000
        });

        // Then the fee portion is computed from the remaining surplus.
        uint256 expectedFeeAmount = JBCashOuts.cashOutFrom({
            surplus: surplus - expectedPostFeeReclaim,
            cashOutCount: feeCashOutCount,
            totalSupply: totalSupplyWithReserved - nonFeeCashOutCount,
            cashOutTaxRate: 7000
        });

        // The reclaimAmount returned by previewCashOutFrom is the bonding curve output
        // computed by JBTerminalStore after the data hook chain returns.
        // The data hook chain (REVDeployer -> BuybackHook) sets the values that the terminal store
        // then uses for the final bonding curve computation.
        // When no pool is set, the buyback hook returns context values unchanged.
        // REVDeployer overrides cashOutCount to nonFeeCashOutCount and sets totalSupply.
        // The terminal store then computes: reclaimAmount = cashOutFrom(surplus, nonFeeCashOutCount, totalSupply,
        // taxRate)
        assertEq(
            reclaimAmount,
            expectedPostFeeReclaim,
            "reclaimAmount should match bonding curve using totalSupplyWithReserved"
        );

        // Now actually cash out and verify the ETH received accounts for the terminal's 2.5% fee.
        // cashOutTokensOf returns reclaimAmount AFTER the terminal's built-in fee deduction.
        // previewCashOutFrom returns the bonding curve output BEFORE the terminal fee.
        // So: actualReclaim = previewReclaim - feeAmountFrom(previewReclaim, FEE)
        uint256 payerEthBefore = PAYER.balance;
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

        // The terminal applies a 2.5% fee on the reclaimAmount when cashOutTaxRate != 0.
        uint256 terminalFee = JBFees.feeAmountFrom({amountBeforeFee: reclaimAmount, feePercent: 25});
        uint256 expectedActualReclaim = reclaimAmount - terminalFee;
        assertEq(actualReclaim, expectedActualReclaim, "actual cashout = preview minus terminal 2.5% fee");

        uint256 ethReceived = PAYER.balance - payerEthBefore;
        assertGt(ethReceived, 0, "payer should receive ETH");

        // Verify the totalSupply used was consistent: if it used only mintedSupply (without pending),
        // the reclaim would be higher. Compute and assert.
        uint256 hypotheticalReclaimNoPending = JBCashOuts.cashOutFrom({
            surplus: surplus,
            cashOutCount: nonFeeCashOutCount,
            totalSupply: mintedSupply, // without pending reserved tokens
            cashOutTaxRate: 7000
        });

        assertLt(
            reclaimAmount,
            hypotheticalReclaimNoPending,
            "reclaim with pending reserved should be less than without (inflation reduces cashout value)"
        );

        // Document the consistency check.
        emit log_named_uint("Minted supply (no pending)", mintedSupply);
        emit log_named_uint("Pending reserved tokens", pending);
        emit log_named_uint("Total supply with reserved", totalSupplyWithReserved);
        emit log_named_uint("Reclaim amount (with reserved inflation)", reclaimAmount);
        emit log_named_uint("Hypothetical reclaim (no inflation)", hypotheticalReclaimNoPending);
        emit log_named_uint("Fee amount", expectedFeeAmount);
    }
}
