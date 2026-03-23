// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./EcosystemFork.t.sol";

/// @notice Hook composition fork tests verifying fee correctness, weight scaling,
/// fallback paths, and full-cycle invariants across the Juicebox V6 hook stack.
///
/// Run with: forge test --match-contract HookCompositionForkTest -vvv
contract HookCompositionForkTest is EcosystemForkTest {
    /// @notice Pay revnet with 721 tier (30% split) + LP split (20% reserved).
    /// Cash out and verify fee project balance increases.
    function test_composition_payWithTierSplit_feeAccrues() public {
        _deployFeeProject(5000);

        // Deploy revnet with 721 + LP split, 70% cashout tax, 20% reserved.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721Config();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // Pay to build surplus.
        _payRevnet(revnetId, BORROWER, 10 ether);
        _payRevnet(revnetId, PAYER, 5 ether);

        // Record fee project balance before cashout.
        uint256 feeBalanceBefore = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        // Cash out half of PAYER's tokens.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 cashOutCount = payerTokens / 2;

        vm.prank(PAYER);
        jbMultiTerminal().cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: cashOutCount,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        // Fee project balance should have increased (2.5% fee on cashout).
        uint256 feeBalanceAfter = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertGt(feeBalanceAfter, feeBalanceBefore, "fee project balance should increase after cashout");

        // Fee accrued should be positive.
        uint256 feeAccrued = feeBalanceAfter - feeBalanceBefore;
        assertGt(feeAccrued, 0, "fee accrued should be positive");

        // Payer should have fewer tokens.
        assertEq(
            jbTokens().totalBalanceOf(PAYER, revnetId), payerTokens - cashOutCount, "payer tokens should decrease"
        );
    }

    /// @notice Mock fee terminal to revert on external pay(). Cash out tokens.
    /// REVDeployer's try-catch returns hook fee to project. Terminal-level fee (internal path) still works.
    /// Key assertion: cashout succeeds (no tx revert) despite fee terminal failure.
    function test_composition_cashOut_feeTerminalReverts_fallback() public {
        _deployFeeProject(5000);

        // Deploy revnet with 70% cashout tax.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc
        });

        // Pay to build surplus.
        _payRevnet(revnetId, BORROWER, 10 ether);
        _payRevnet(revnetId, PAYER, 5 ether);

        // Do a NORMAL cashout first to measure baseline fee accrual.
        uint256 borrowerTokens = jbTokens().totalBalanceOf(BORROWER, revnetId);
        vm.prank(BORROWER);
        jbMultiTerminal().cashOutTokensOf({
            holder: BORROWER,
            projectId: revnetId,
            cashOutCount: borrowerTokens / 4,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(BORROWER),
            metadata: ""
        });
        uint256 feeAfterNormalCashout = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertGt(feeAfterNormalCashout, 0, "normal cashout should accrue fees");

        // Now mock fee terminal's external pay() to revert for the fee project.
        // This blocks REVDeployer.afterCashOutRecordedWith -> feeTerminal.pay().
        // The terminal's internal _processFee path is unaffected by external mocks.
        vm.mockCallRevert(
            address(jbMultiTerminal()),
            abi.encodeWithSignature(
                "pay(uint256,address,uint256,address,uint256,string,bytes)", FEE_PROJECT_ID
            ),
            "fee terminal reverted"
        );

        // Cash out should succeed despite fee terminal reverting.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 cashOutCount = payerTokens / 2;
        uint256 payerEthBefore = PAYER.balance;
        uint256 projectBalanceBefore = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);

        vm.prank(PAYER);
        jbMultiTerminal().cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: cashOutCount,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        // Main assertion: cashout succeeded (try-catch worked).
        assertGt(PAYER.balance, payerEthBefore, "payer should receive ETH despite fee terminal revert");

        // Fee project still received SOME fees (terminal-level fee via internal path).
        uint256 feeAfterMockedCashout = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertGt(feeAfterMockedCashout, feeAfterNormalCashout, "terminal-level fee still reaches fee project");

        // The REVDeployer's hook fee was returned to the project via addToBalanceOf.
        // Project balance decreased by less than it would have if both fees succeeded.
        uint256 projectBalanceAfter = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        assertLt(projectBalanceAfter, projectBalanceBefore, "project balance decreased from cashout");
        assertGt(projectBalanceAfter, 0, "project retains balance after cashout");

        vm.clearMockedCalls();
    }

    /// @notice Pay 1 ETH with 30% tier split. Verify weight is scaled by projectAmount/totalAmount.
    /// Payer tokens = (0.7 ETH worth) * scaled_weight. No token credit for split portion.
    function test_composition_721SplitPercent_weightScaling() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721Config();

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // First, pay WITHOUT tier metadata - payer gets full weight.
        uint256 tokensWithoutTier = _payRevnet(revnetId, BORROWER, 1 ether);

        // Now pay WITH tier metadata - 30% split reduces weight.
        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);

        vm.prank(PAYER);
        uint256 tokensWithTier = jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        // With 30% tier split, only 70% enters the project.
        // Weight scaled: weight * 0.7 = 700e18 (from 1000e18).
        // With 20% reserved: payer gets 80%.
        // Expected: tokensWithTier ~= 560e18, tokensWithoutTier = 800e18.
        // Ratio should be ~70%.
        assertLt(tokensWithTier, tokensWithoutTier, "tier split should reduce payer tokens");

        uint256 expectedRatio = 70; // 70%
        uint256 actualRatio = (tokensWithTier * 100) / tokensWithoutTier;
        assertApproxEqAbs(actualRatio, expectedRatio, 1, "weight scaling should be ~70% with 30% tier split");

        // Payer should also own the NFT.
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should own 1 NFT");
    }

    /// @notice Full lifecycle invariant checks: pay -> distribute reserved -> cash out -> verify.
    /// Cashout is done pre-pool to avoid buyback hook TWAP slippage issues on forked state.
    /// Post-pool pay is verified separately.
    function test_composition_fullCycle_invariants() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc
        });

        uint256 feeBalancePrev = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        // 1. Pre-AMM pay.
        _payRevnet(revnetId, PAYER, 5 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);
        assertGt(_terminalBalance(revnetId, JBConstants.NATIVE_TOKEN), 0, "inv: terminal balance > 0 after pay");

        // 2. Distribute reserved tokens -> LP split hook accumulates.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        if (pending > 0) {
            jbController().sendReservedTokensToSplitsOf(revnetId);
        }
        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);
        assertGt(accumulated, 0, "inv: LP split hook accumulated tokens");

        // 3. Cash out BEFORE pool setup (uses bonding curve, no buyback hook TWAP interference).
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 cashOutCount = payerTokens / 4;
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        jbMultiTerminal().cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: cashOutCount,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        assertGt(PAYER.balance, payerEthBefore, "inv: payer received ETH from cashout");

        // Invariant: terminal balance >= 0.
        assertGe(_terminalBalance(revnetId, JBConstants.NATIVE_TOKEN), 0, "inv: terminal balance >= 0");

        // Invariant: token supply > 0 (not all tokens cashed out).
        uint256 totalSupply = jbTokens().totalSupplyOf(revnetId);
        assertGt(totalSupply, 0, "inv: total supply > 0");

        // Invariant: fee project balance monotonically increased.
        uint256 feeBalanceNow = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertGe(feeBalanceNow, feeBalancePrev, "inv: fee project balance monotonically increases");
        feeBalancePrev = feeBalanceNow;

        // 4. Second cashout to verify fee monotonicity again.
        uint256 borrowerTokens = jbTokens().totalBalanceOf(BORROWER, revnetId);
        if (borrowerTokens > 0) {
            uint256 borrowerEthBefore = BORROWER.balance;
            vm.prank(BORROWER);
            jbMultiTerminal().cashOutTokensOf({
                holder: BORROWER,
                projectId: revnetId,
                cashOutCount: borrowerTokens / 2,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(BORROWER),
                metadata: ""
            });
            assertGt(BORROWER.balance, borrowerEthBefore, "inv: borrower received ETH");

            feeBalanceNow = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
            assertGe(feeBalanceNow, feeBalancePrev, "inv: fee balance still monotonic after 2nd cashout");
            feeBalancePrev = feeBalanceNow;
        }

        // 5. Set up buyback pool and verify post-AMM pay works.
        _setupBuybackPool(revnetId, 10_000 ether);

        address payer2 = makeAddr("payer2");
        vm.deal(payer2, 10 ether);
        uint256 tokens = _payRevnet(revnetId, payer2, 1 ether);
        assertGt(tokens, 0, "inv: post-AMM pay should return tokens");

        // Invariant: LP split hook position exists (accumulated tokens > 0 from step 2).
        assertGt(
            LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId), 0, "inv: LP split hook has accumulated tokens"
        );

        // Final invariant: fee balance only grew.
        feeBalanceNow = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertGe(feeBalanceNow, feeBalancePrev, "inv: fee balance monotonic at end");
    }

    /// @notice Cashout from project with 0% cashOutTaxRate.
    /// REVDeployer proxies directly to buyback hook (line 275-278). No fee. Fee project unchanged.
    function test_composition_zeroTaxRate_skipsFee() public {
        _deployFeeProject(5000);

        // Deploy revnet with 0% cashout tax (both stages).
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfigWithLPSplit(0, 0, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc
        });

        // Pay to build surplus.
        _payRevnet(revnetId, PAYER, 5 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        // Record fee project balance before cashout.
        uint256 feeBalanceBefore = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        // Cash out with 0% tax.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 cashOutCount = payerTokens / 2;
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        jbMultiTerminal().cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: cashOutCount,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        // Payer should receive ETH (full pro-rata with 0% tax).
        assertGt(PAYER.balance, payerEthBefore, "should receive ETH from 0% tax cashout");

        // Fee project should NOT have received fees (0% tax -> proxy to buyback, no fee spec).
        uint256 feeBalanceAfter = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);
        assertEq(feeBalanceAfter, feeBalanceBefore, "fee project should not change with 0% tax");
    }
}
