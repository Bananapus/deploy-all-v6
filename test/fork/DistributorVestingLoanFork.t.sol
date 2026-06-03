// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../helpers/RevnetForkBase.sol";

import {JBTokenDistributor} from "@bananapus/distributor-v6/src/JBTokenDistributor.sol";
import {JBDistributor} from "@bananapus/distributor-v6/src/JBDistributor.sol";
import {JBVestingLoan} from "@bananapus/distributor-v6/src/structs/JBVestingLoan.sol";
import {IREVOwner} from "@rev-net/core-v6/src/interfaces/IREVOwner.sol";
import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Runtime coverage for the `JBTokenDistributor` vesting-loan path, which has ZERO existing fork coverage and
/// drives never-otherwise-exercised REVLoans code (`liquidateExpiredLoansFrom`) plus the distributor's
/// `borrowAgainstVesting` / `repayVestingLoan` / `writeOffLiquidatedVestingLoan`.
///
/// A staker's vesting revnet rewards are used as collateral for a Revnet loan held by the distributor. Two terminal
/// outcomes are pinned:
///   1. Liquidation: after the 10-year liquidation window the loan is liquidated (collateral destroyed), and the
///      distributor's `writeOffLiquidatedVestingLoan` reconciles its local state and forfeits the collateral.
///   2. Repay: the loan is repaid within its prepaid window (no extra source fee), restoring the collateral to the
///      distributor and re-enabling normal vesting collection.
///
/// Run with: forge test --match-contract DistributorVestingLoanForkTest -vvv
contract DistributorVestingLoanForkTest is RevnetForkBase {
    uint256 internal constant ROUND_DURATION = 7 days;
    uint256 internal constant VESTING_ROUNDS = 4;
    uint48 internal constant CLAIM_DURATION = 420 days;
    uint256 internal constant FUND_AMOUNT = 1000e18; // reward tokens funded into the round

    JBTokenDistributor internal distributor;
    address internal ALICE = makeAddr("alice");

    uint256 internal stakeRevnetId;
    uint256 internal rewardRevnetId;
    address internal stakeToken;
    IERC20 internal rewardToken;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "DistributorVestLoan";
    }

    function setUp() public override {
        super.setUp();
        distributor = new JBTokenDistributor(
            jbDirectory(),
            jbController(),
            LOANS_CONTRACT,
            IREVOwner(address(REV_OWNER)),
            ROUND_DURATION,
            VESTING_ROUNDS,
            CLAIM_DURATION
        );

        vm.deal(ALICE, 100 ether);
        vm.deal(address(this), 100 ether);
        // Pays read a TWAP via the buyback hook; mock 1:1 so every pay takes the mint path (mints nothing itself).
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Two revnets: one supplies the staked IVotes token, the other supplies the reward token (which must be a real
        // revnet project token owned by REV_OWNER so REVLoans can borrow against it).
        stakeRevnetId = _deployRevnet(0);
        rewardRevnetId = _deployRewardRevnet();
        stakeToken = address(jbTokens().tokenOf(stakeRevnetId));
        rewardToken = IERC20(address(jbTokens().tokenOf(rewardRevnetId)));

        // Fund the reward revnet treasury (ETH surplus to borrow against) and obtain reward tokens to fund the round.
        _payRevnet(rewardRevnetId, address(this), 10 ether);

        // Stake + delegate Alice into the stake revnet so the round snapshot records her votes.
        _payRevnet(stakeRevnetId, ALICE, 3 ether);
        vm.prank(ALICE);
        IVotes(stakeToken).delegate(ALICE);
        vm.roll(block.number + 1); // checkpoint must be strictly before the fund snapshot block

        // Fund round 0 with reward tokens (the distributor now holds the collateralizable reward inventory).
        rewardToken.approve(address(distributor), type(uint256).max);
        distributor.fund(stakeToken, rewardToken, FUND_AMOUNT);

        // Advance into round 1 so round 0's vesting is materializable / borrowable.
        vm.warp(block.timestamp + ROUND_DURATION);
        vm.roll(block.number + 1);
    }

    /// @dev A second native revnet with a DISTINCT salt (so it does not collide on CREATE2 with `_deployRevnet`'s
    /// "REV_SALT" project token), used as the reward-token revnet.
    function _deployRewardRevnet() internal returns (uint256 id) {
        (REVConfig memory cfg, JBAccountingContext[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildNativeConfig(0);
        cfg.description = REVDescription("Reward", "RWD", "ipfs://rwd", "RWD_SALT");
        sdc.salt = keccak256(abi.encodePacked("RWD"));
        (id,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, accountingContextsToAccept: tc, suckerDeploymentConfiguration: sdc
        });
    }

    function _ids(address staker) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = uint256(uint160(staker));
    }

    function _toks(IERC20 token) internal pure returns (IERC20[] memory toks) {
        toks = new IERC20[](1);
        toks[0] = token;
    }

    /// @dev Alice borrows ETH from the reward revnet against her vesting reward tokens; the distributor holds the loan.
    function _borrow() internal returns (uint256 loanId, uint256 collateralCount) {
        // Resolve the external read BEFORE pranking — otherwise this staticcall consumes the prank and
        // `borrowAgainstVesting` would be called by the test contract, failing the token-id access check.
        uint256 prepaidFeePercent = LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT();
        vm.prank(ALICE);
        (loanId, collateralCount) = distributor.borrowAgainstVesting({
            hook: stakeToken,
            tokenIds: _ids(ALICE),
            tokens: _toks(rewardToken),
            sourceToken: JBConstants.NATIVE_TOKEN,
            minBorrowAmount: 0,
            prepaidFeePercent: prepaidFeePercent,
            beneficiary: payable(ALICE)
        });
    }

    /// @notice A vesting loan that runs past the 10-year liquidation window is liquidated by REVLoans (collateral
    /// destroyed), and the distributor's permissionless `writeOffLiquidatedVestingLoan` reconciles its local state.
    function test_distributor_vestingLoan_liquidateAndWriteOff() public {
        uint256 aliceEthBefore = ALICE.balance;
        (uint256 loanId, uint256 collateralCount) = _borrow();

        // Loan opened: Alice received borrowed ETH; the distributor holds the loan; its local lock is set.
        assertGt(loanId, 0, "loan id assigned");
        assertGt(collateralCount, 0, "collateral (vesting rewards) locked");
        assertGt(ALICE.balance, aliceEthBefore, "alice received borrowed ETH");
        JBVestingLoan memory vl = distributor.vestingLoanOf(loanId);
        assertEq(vl.hook, stakeToken, "vesting loan tracks the stake hook");
        assertEq(vl.tokenId, uint256(uint160(ALICE)), "vesting loan tracks Alice's token id");
        assertEq(address(vl.token), address(rewardToken), "vesting loan tracks the reward token");
        assertEq(vl.collateralCount, collateralCount, "vesting loan records the collateral");
        assertEq(
            distributor.activeVestingLoanIdOf(stakeToken, 0, uint256(uint160(ALICE)), rewardToken),
            loanId,
            "active vesting-loan lock set"
        );
        assertEq(distributor.totalLoanedVestingAmountOf(stakeToken, rewardToken), collateralCount, "loaned inventory");
        assertGt(LOANS_CONTRACT.loanOf(loanId).createdAt, 0, "REVLoans loan is live");

        // Collecting vested rewards is blocked while the position is collateralized by an active loan.
        vm.expectPartialRevert(JBDistributor.JBDistributor_VestingLoanOutstanding.selector);
        vm.prank(ALICE);
        distributor.collectVestedRewards(stakeToken, _ids(ALICE), _toks(rewardToken), ALICE);

        // Warp past the 10-year liquidation window and liquidate (permissionless).
        REVLoan memory loan = LOANS_CONTRACT.loanOf(loanId);
        vm.warp(uint256(loan.createdAt) + LOANS_CONTRACT.LOAN_LIQUIDATION_DURATION() + 1);
        vm.roll(block.number + 1);
        LOANS_CONTRACT.liquidateExpiredLoansFrom(rewardRevnetId, 1, 1);
        assertEq(LOANS_CONTRACT.loanOf(loanId).createdAt, 0, "REVLoans loan deleted by liquidation");

        // Write off the now-liquidated loan: distributor forfeits the collateral and clears its local state.
        uint256 writtenOff = distributor.writeOffLiquidatedVestingLoan(loanId);
        assertEq(writtenOff, collateralCount, "write-off forfeits exactly the collateralized amount");
        assertEq(distributor.vestingLoanOf(loanId).hook, address(0), "distributor vesting-loan record cleared");
        assertEq(
            distributor.activeVestingLoanIdOf(stakeToken, 0, uint256(uint160(ALICE)), rewardToken),
            0,
            "active vesting-loan lock cleared"
        );
        assertEq(distributor.totalLoanedVestingAmountOf(stakeToken, rewardToken), 0, "loaned inventory zeroed");
        assertEq(distributor.totalVestingAmountOf(stakeToken, rewardToken), 0, "vesting inventory forfeited");

        // The collateral is gone: collecting now yields nothing (no revert, but no payout either).
        uint256 aliceRewardBefore = rewardToken.balanceOf(ALICE);
        vm.prank(ALICE);
        distributor.collectVestedRewards(stakeToken, _ids(ALICE), _toks(rewardToken), ALICE);
        assertEq(rewardToken.balanceOf(ALICE), aliceRewardBefore, "nothing collectable after write-off");

        // The loan cannot be written off twice.
        vm.expectRevert(abi.encodeWithSelector(JBDistributor.JBDistributor_NoVestingLoan.selector, loanId));
        distributor.writeOffLiquidatedVestingLoan(loanId);
    }

    /// @notice A vesting loan repaid within its prepaid window incurs no extra source fee, restores the collateral to
    /// the distributor, and re-enables normal vesting collection.
    function test_distributor_vestingLoan_borrowAndRepay() public {
        (uint256 loanId, uint256 collateralCount) = _borrow();
        assertGt(loanId, 0, "loan id assigned");

        // Within the prepaid window, no additional source fee is owed; repay exactly the principal.
        REVLoan memory loan = LOANS_CONTRACT.loanOf(loanId);
        uint256 sourceFee = LOANS_CONTRACT.determineSourceFeeAmount(loan, loan.amount);
        assertEq(sourceFee, 0, "no extra source fee inside the prepaid window");
        uint256 repayAmount = uint256(loan.amount) + sourceFee;

        uint256 distributorRewardBefore = rewardToken.balanceOf(address(distributor));

        vm.deal(ALICE, repayAmount + 1 ether);
        vm.prank(ALICE);
        distributor.repayVestingLoan{value: repayAmount}(loanId, repayAmount);

        // Loan settled both sides: distributor record cleared, REVLoans loan burned, collateral restored.
        assertEq(distributor.vestingLoanOf(loanId).hook, address(0), "distributor vesting-loan record cleared on repay");
        assertEq(
            distributor.activeVestingLoanIdOf(stakeToken, 0, uint256(uint160(ALICE)), rewardToken),
            0,
            "active vesting-loan lock cleared on repay"
        );
        assertEq(distributor.totalLoanedVestingAmountOf(stakeToken, rewardToken), 0, "loaned inventory restored");
        assertEq(LOANS_CONTRACT.loanOf(loanId).createdAt, 0, "REVLoans loan burned on full repay");
        assertGe(
            rewardToken.balanceOf(address(distributor)),
            distributorRewardBefore + collateralCount,
            "collateral returned to the distributor"
        );

        // Vesting collection works again now that the position is no longer collateralized. Fully vest then collect.
        for (uint256 i; i < VESTING_ROUNDS; ++i) {
            vm.warp(block.timestamp + ROUND_DURATION);
            vm.roll(block.number + 1);
        }
        uint256 aliceRewardBefore = rewardToken.balanceOf(ALICE);
        vm.prank(ALICE);
        distributor.collectVestedRewards(stakeToken, _ids(ALICE), _toks(rewardToken), ALICE);
        assertGt(rewardToken.balanceOf(ALICE), aliceRewardBefore, "alice collects her vested rewards after repay");

        // Cannot repay a settled loan again.
        vm.expectRevert(abi.encodeWithSelector(JBDistributor.JBDistributor_NoVestingLoan.selector, loanId));
        distributor.repayVestingLoan(loanId, 0);
    }
}
