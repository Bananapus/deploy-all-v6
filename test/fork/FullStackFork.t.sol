// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {IJB721TiersHook} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHook.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVDeploy721TiersHookConfig} from "@rev-net/core-v6/src/structs/REVDeploy721TiersHookConfig.sol";
import {REVCroptopAllowedPost} from "@rev-net/core-v6/src/structs/REVCroptopAllowedPost.sol";
import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";
import {REVLoanSource} from "@rev-net/core-v6/src/structs/REVLoanSource.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {JBSingleAllowance} from "@bananapus/core-v6/src/structs/JBSingleAllowance.sol";

import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";

/// @notice Full-stack integration fork test exercising all major Juicebox V6 component interactions.
///
/// Deploys the entire ecosystem on forked Ethereum mainnet and verifies:
/// - Payment -> token issuance (mint and swap paths)
/// - 721 NFT tier splits
/// - Cash-out with bonding curve + tax + fee
/// - Loan borrow and repay
/// - Sucker exemption (0% tax/fee)
/// - Reserved token distribution
/// - Stage transitions
///
/// Run with: forge test --match-contract FullStackForkTest -vvv
contract FullStackForkTest is RevnetForkBase {
    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_FullStack";
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Tests
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Pay ETH -> receive project tokens via mint path (pool at 1:1, mint wins).
    function test_fullStack_payAndMintTokens() public {
        _deployFeeProject(5000);
        uint256 revnetId = _deployRevnet(5000);
        _setupNativePool(revnetId, 10_000 ether);

        uint256 tokens = _payRevnet(revnetId, PAYER, 1 ether);

        assertGt(tokens, 0, "should receive tokens");
        assertEq(tokens, 1000e18, "should receive 1000 tokens per ETH");
        assertGt(_terminalBalance(revnetId, JBConstants.NATIVE_TOKEN), 0, "terminal should have balance");
    }

    /// @notice Pay with 721 tier metadata -> NFT minted + 30% split to beneficiary.
    function test_fullStack_payWith721TierSplits() public {
        _deployFeeProject(5000);
        (uint256 revnetId, IJB721TiersHook hook) = _deployRevnetWith721(5000);
        _setupNativePool(revnetId, 10_000 ether);

        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataNoQuote(metadataTarget);

        vm.prank(PAYER);
        uint256 tokens = jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        assertEq(tokens, 700e18, "should get 700 tokens after 30% split");
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should own 1 NFT");
    }

    /// @notice Cash out tokens -> bonding curve reclaim with tax + fee.
    function test_fullStack_cashOutWithBondingCurve() public {
        _deployFeeProject(5000);
        uint256 revnetId = _deployRevnet(5000);
        _setupNativePool(revnetId, 10_000 ether);

        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: payerTokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        uint256 ethReceived = PAYER.balance - payerEthBefore;
        assertGt(ethReceived, 0, "should receive some ETH from pool sell or bonding curve");
        assertEq(jbTokens().totalBalanceOf(PAYER, revnetId), 0, "tokens should be burned");
    }

    /// @notice Borrow against tokens -> repay -> get collateral back.
    function test_fullStack_loanBorrowAndRepay() public {
        _deployFeeProject(5000);
        uint256 revnetId = _deployRevnet(5000);
        _setupNativePool(revnetId, 10_000 ether);

        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        uint256 borrowerTokens = jbTokens().totalBalanceOf(BORROWER, revnetId);

        uint256 borrowable = LOANS_CONTRACT.borrowableAmountFrom(
            revnetId, borrowerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))
        );
        assertGt(borrowable, 0, "should have borrowable amount");

        _grantBurnPermission(BORROWER, revnetId);
        REVLoanSource memory source = _nativeLoanSource();

        uint256 borrowerEthBefore = BORROWER.balance;

        vm.startPrank(BORROWER);
        (uint256 loanId, REVLoan memory loan) = LOANS_CONTRACT.borrowFrom({
            revnetId: revnetId,
            source: source,
            minBorrowAmount: 0,
            collateralCount: borrowerTokens,
            beneficiary: payable(BORROWER),
            prepaidFeePercent: LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT(),
            holder: BORROWER
        });
        vm.stopPrank();

        assertGt(loanId, 0, "loan should be created");
        assertGt(BORROWER.balance, borrowerEthBefore, "borrower should receive ETH");

        uint256 postBorrowBalance = jbTokens().totalBalanceOf(BORROWER, revnetId);
        assertLt(postBorrowBalance, borrowerTokens / 100, "most tokens should be burned as collateral");
        assertEq(REVLoans(payable(address(LOANS_CONTRACT))).ownerOf(loanId), BORROWER, "loan NFT owned by borrower");

        // Repay the loan.
        vm.deal(BORROWER, 100 ether);
        JBSingleAllowance memory allowance;

        vm.startPrank(BORROWER);
        LOANS_CONTRACT.repayLoan{value: loan.amount * 2}({
            loanId: loanId,
            maxRepayBorrowAmount: loan.amount * 2,
            collateralCountToReturn: loan.collateral,
            beneficiary: payable(BORROWER),
            allowance: allowance
        });
        vm.stopPrank();

        assertGe(
            jbTokens().totalBalanceOf(BORROWER, revnetId), borrowerTokens, "collateral should be returned after repay"
        );

        vm.expectRevert();
        REVLoans(payable(address(LOANS_CONTRACT))).ownerOf(loanId);
    }

    /// @notice Mock sucker -> 0% tax + 0% fee exemption on cash-out.
    function test_fullStack_suckerExemptCashOut() public {
        _deployFeeProject(5000);
        uint256 revnetId = _deployRevnet(5000);
        _setupNativePool(revnetId, 10_000 ether);

        _payRevnet(revnetId, PAYER, 10 ether);

        address sucker = makeAddr("sucker");
        vm.deal(sucker, 5 ether);
        _payRevnet(revnetId, sucker, 5 ether);

        uint256 suckerTokens = jbTokens().totalBalanceOf(sucker, revnetId);
        uint256 surplus = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);

        vm.mockCall(
            address(SUCKER_REGISTRY),
            abi.encodeWithSelector(IJBSuckerRegistry.isSuckerOf.selector, revnetId, sucker),
            abi.encode(true)
        );

        uint256 suckerEthBefore = sucker.balance;

        vm.prank(sucker);
        jbMultiTerminal()
            .cashOutTokensOf({
            holder: sucker,
            projectId: revnetId,
            cashOutCount: suckerTokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(sucker),
            metadata: ""
        });

        uint256 ethReceived = sucker.balance - suckerEthBefore;
        uint256 totalSupply = jbTokens().totalSupplyOf(revnetId) + suckerTokens;
        uint256 expectedProRata = surplus * suckerTokens / totalSupply;

        assertApproxEqAbs(ethReceived, expectedProRata, 10, "sucker should get full pro-rata share");
        assertGt(ethReceived, 0, "sucker should receive ETH");
    }

    /// @notice Reserved token distribution to splits.
    function test_fullStack_reservedTokenDistribution() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildNativeConfig(5000);
        cfg.stageConfigurations[0].splitPercent = 2000;

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupNativePool(revnetId, 10_000 ether);
        _payRevnet(revnetId, PAYER, 10 ether);

        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);

        if (pending > 0) {
            jbController().sendReservedTokensToSplitsOf(revnetId);
            uint256 multisigTokens = jbTokens().totalBalanceOf(multisig(), revnetId);
            assertGt(multisigTokens, 0, "multisig should receive reserved tokens");
        }
    }

    /// @notice Warp to stage 2 -> verify new cashOutTaxRate applies.
    function test_fullStack_crossStageTransition() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageNativeConfig(7000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupNativePool(revnetId, 10_000 ether);

        _payRevnet(revnetId, PAYER, 10 ether);
        address payer2 = makeAddr("payer2");
        vm.deal(payer2, 10 ether);
        _payRevnet(revnetId, payer2, 5 ether);

        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);

        uint256 borrowableStage1 =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN)));

        vm.warp(block.timestamp + 31 days);

        uint256 borrowableStage2 =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN)));
        assertGt(borrowableStage2, borrowableStage1, "borrowable should increase with lower tax in stage 2");

        uint256 payerEthBefore = PAYER.balance;
        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: payerTokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        uint256 ethReceived = PAYER.balance - payerEthBefore;
        assertGt(ethReceived, 0, "should receive ETH in stage 2 cashout");
    }

    /// @notice Full lifecycle: deploy -> pay -> borrow -> warp -> repay -> cash out remainder.
    function test_fullStack_fullLifecycle() public {
        _deployFeeProject(5000);
        (uint256 revnetId, IJB721TiersHook hook) = _deployRevnetWith721(5000);
        _setupNativePool(revnetId, 10_000 ether);

        // 1. Pay with 721 tier selection.
        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataNoQuote(metadataTarget);

        vm.prank(BORROWER);
        uint256 borrowerTokens = jbMultiTerminal().pay{value: 5 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            beneficiary: BORROWER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        assertGt(borrowerTokens, 0, "should receive tokens");
        assertEq(IERC721(address(hook)).balanceOf(BORROWER), 1, "should own 1 NFT");

        _payRevnet(revnetId, PAYER, 10 ether);

        // 2. Borrow against tokens.
        _grantBurnPermission(BORROWER, revnetId);
        REVLoanSource memory source = _nativeLoanSource();

        vm.startPrank(BORROWER);
        (uint256 loanId, REVLoan memory loan) = LOANS_CONTRACT.borrowFrom({
            revnetId: revnetId,
            source: source,
            minBorrowAmount: 0,
            collateralCount: borrowerTokens,
            beneficiary: payable(BORROWER),
            prepaidFeePercent: LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT(),
            holder: BORROWER
        });
        vm.stopPrank();

        assertGt(loanId, 0, "loan should be created");

        // 3. Repay the loan.
        vm.deal(BORROWER, 100 ether);
        JBSingleAllowance memory allowance;

        vm.startPrank(BORROWER);
        LOANS_CONTRACT.repayLoan{value: loan.amount * 2}({
            loanId: loanId,
            maxRepayBorrowAmount: loan.amount * 2,
            collateralCountToReturn: loan.collateral,
            beneficiary: payable(BORROWER),
            allowance: allowance
        });
        vm.stopPrank();

        uint256 tokensAfterRepay = jbTokens().totalBalanceOf(BORROWER, revnetId);
        assertGe(tokensAfterRepay, borrowerTokens, "full collateral returned (may include fee-rebate tokens)");

        // 4. Cash out half the tokens.
        uint256 cashOutCount = tokensAfterRepay / 2;
        uint256 borrowerEthBefore = BORROWER.balance;

        vm.prank(BORROWER);
        jbMultiTerminal()
            .cashOutTokensOf({
            holder: BORROWER,
            projectId: revnetId,
            cashOutCount: cashOutCount,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(BORROWER),
            metadata: ""
        });

        assertGt(BORROWER.balance, borrowerEthBefore, "should receive ETH from cashout");
        assertEq(
            jbTokens().totalBalanceOf(BORROWER, revnetId), tokensAfterRepay - cashOutCount, "remaining tokens correct"
        );
    }
}
