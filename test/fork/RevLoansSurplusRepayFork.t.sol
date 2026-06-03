// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../helpers/RevnetForkBase.sol";

import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";
import {JBSingleAllowance} from "@bananapus/core-v6/src/structs/JBSingleAllowance.sol";

/// @notice Pins the INTENDED REVLoans design for partial loan repayment after the collateral appreciates:
/// `repayLoan` is strictly for debt reduction. A PARTIAL collateral return that would leave the kept collateral backing
/// MORE than the loan — because the revnet's per-token borrowable value ROSE since the loan opened (surplus grew /
/// cash-out tax dropped) — reverts `REVLoans_NewBorrowAmountGreaterThanLoanAmount`. This is a deliberate separation
/// of
/// concerns between debt reduction (`repayLoan`) and excess-collateral handling (`reallocateCollateralFromLoan`).
///
/// The borrower is never stranded: to access appreciated EXCESS collateral while keeping a position they use
/// `reallocateCollateralFromLoan` (moves the excess into a new loan) — demonstrated here as the working alternative
/// —
/// or a FULL repay to recover everything.
///
/// Surplus is raised the way it would in production: an `addToBalanceOf` donation (or cross-chain bridged surplus, or a
/// stage that lowers the cash-out tax) adds terminal surplus without minting matching project tokens.
///
/// Run with: forge test --match-contract RevLoansSurplusRepayForkTest -vvv
contract RevLoansSurplusRepayForkTest is RevnetForkBase {
    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVLoans_SurplusRepay";
    }

    function test_revLoans_partialRepayReverts_fullRepayRecoversAll() public {
        _deployFeeProject(5000);
        uint256 revnetId = _deployRevnet(5000);
        _setupNativePool(revnetId, 10_000 ether);

        _payRevnet(revnetId, BORROWER, 5 ether);
        uint256 borrowerTokens = jbTokens().totalBalanceOf(BORROWER, revnetId);
        assertGt(borrowerTokens, 0, "borrower should hold revnet tokens");

        _grantBurnPermission(BORROWER, revnetId);
        address source = _nativeLoanSource();

        // Borrow against ALL of the borrower's tokens at the current (low) surplus.
        vm.startPrank(BORROWER);
        (uint256 loanId, REVLoan memory loan) = LOANS_CONTRACT.borrowFrom({
            revnetId: revnetId,
            token: source,
            minBorrowAmount: 0,
            collateralCount: borrowerTokens,
            beneficiary: payable(BORROWER),
            prepaidFeePercent: LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT(),
            holder: BORROWER
        });
        vm.stopPrank();
        assertGt(loanId, 0, "loan created");
        assertGt(loan.amount, 0, "loan has an outstanding amount");

        // Surplus rises sharply (donation, no new tokens) -> each remaining collateral token now backs more debt.
        uint256 donation = 200 ether;
        vm.deal(address(this), donation);
        jbMultiTerminal().addToBalanceOf{value: donation}({
            projectId: revnetId,
            token: source,
            amount: donation,
            shouldReturnHeldFees: false,
            memo: "surplus donation",
            metadata: ""
        });

        vm.deal(BORROWER, 1000 ether);
        JBSingleAllowance memory allowance;

        // INTENDED GUARD: a partial repay whose kept collateral now backs MORE than the loan reverts. `repayLoan`
        // reduces debt; it is deliberately NOT the path for pulling out appreciated excess collateral.
        vm.prank(BORROWER);
        vm.expectPartialRevert(REVLoans.REVLoans_NewBorrowAmountGreaterThanLoanAmount.selector);
        LOANS_CONTRACT.repayLoan{value: loan.amount * 2}({
            loanId: loanId,
            maxRepayBorrowAmount: loan.amount * 2,
            collateralCountToReturn: borrowerTokens / 2,
            beneficiary: payable(BORROWER),
            allowance: allowance
        });

        // INTENDED ESCAPE: the borrower is never stranded. A FULL repay (remaining collateral -> 0 -> treated as full
        // repay) always recovers ALL collateral. To instead access the appreciated EXCESS while keeping a position,
        // `reallocateCollateralFromLoan` is the designed path (moves the excess into a new loan; demonstrated in
        // revnet-core-v6's REVLoansEdgeCases). This separation is intended, not a bug.
        uint256 tokensBefore = jbTokens().totalBalanceOf(BORROWER, revnetId);
        vm.prank(BORROWER);
        LOANS_CONTRACT.repayLoan{value: loan.amount * 2}({
            loanId: loanId,
            maxRepayBorrowAmount: loan.amount * 2,
            collateralCountToReturn: loan.collateral,
            beneficiary: payable(BORROWER),
            allowance: allowance
        });
        assertEq(
            jbTokens().totalBalanceOf(BORROWER, revnetId) - tokensBefore,
            loan.collateral,
            "full repay recovers all collateral - borrower is never stranded"
        );
    }
}
