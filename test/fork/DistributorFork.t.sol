// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../helpers/RevnetForkBase.sol";

import {MockERC20Token} from "../helpers/MockTokens.sol";
import {JBTokenDistributor} from "@bananapus/distributor-v6/src/JBTokenDistributor.sol";
import {IREVOwner} from "@rev-net/core-v6/src/interfaces/IREVOwner.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Runtime coverage for `JBTokenDistributor` (an IVotes-token reward distributor, deployed by Deploy.s.sol).
/// Pins two behaviors:
///   1. Happy path: stakers who hold + delegate the revnet token before a round's snapshot receive rewards
///      proportional to their stake once the reward vests.
///   2. A round funded when the stake token has ZERO total supply at the round's snapshot block pins `totalStake = 0`,
///      so stakers who appear later can never claim that round's rewards; the pot is only recoverable through the
///      permissionless `recycleExpiredRewards` recycle after `CLAIM_DURATION`.
///
/// Run with: forge test --match-contract DistributorForkTest -vvv
contract DistributorForkTest is RevnetForkBase {
    uint256 internal constant ROUND_DURATION = 7 days;
    uint256 internal constant VESTING_ROUNDS = 4;
    uint48 internal constant CLAIM_DURATION = 420 days;

    JBTokenDistributor internal distributor;
    address internal ALICE = makeAddr("alice");
    address internal BOB = makeAddr("bob");

    function _deployerSalt() internal pure override returns (bytes32) {
        return "DistributorFork";
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
        vm.deal(BOB, 100 ether);
        // The revnet's data hook composes the buyback hook, which reads a TWAP on every pay. Mock the oracle at a
        // 1:1 tick (liquidity 1) so the swap quote (~1 token/ETH) stays far below the mint amount (1000 tokens/ETH):
        // every pay takes the MINT path. This mints nothing itself, so the zero-supply lock test below stays valid.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
    }

    function _id(address staker) internal pure returns (uint256) {
        return uint256(uint160(staker));
    }

    function _ids(address staker) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = _id(staker);
    }

    function _toks(IERC20 token) internal pure returns (IERC20[] memory toks) {
        toks = new IERC20[](1);
        toks[0] = token;
    }

    /// @dev Pay the revnet (mints the project token to `staker`), then delegate so `getPastVotes` is non-zero.
    function _stakeAndDelegate(
        uint256 revnetId,
        address staker,
        uint256 amountEth
    )
        internal
        returns (address stakeToken)
    {
        _payRevnet(revnetId, staker, amountEth);
        stakeToken = address(jbTokens().tokenOf(revnetId));
        vm.prank(staker);
        IVotes(stakeToken).delegate(staker);
    }

    /// @dev Advance one full round and mine a block so the ERC20Votes (block-number clock) checkpoints are queryable.
    function _advanceRound() internal {
        vm.warp(block.timestamp + ROUND_DURATION);
        vm.roll(block.number + 1);
    }

    function _collect(address staker, address stakeToken, IERC20 reward) internal {
        vm.prank(staker);
        distributor.collectVestedRewards(stakeToken, _ids(staker), _toks(reward), staker);
    }

    function _newReward() internal returns (MockERC20Token reward) {
        reward = new MockERC20Token("Reward", "RWD", 18);
        reward.mint(address(this), 1_000_000e18);
        reward.approve(address(distributor), type(uint256).max);
    }

    /// @notice Stakers receive rewards proportional to their snapshot stake once fully vested.
    function test_distributor_proportionalReward() public {
        uint256 revnetId = _deployRevnet(0);
        address stakeToken = _stakeAndDelegate(revnetId, ALICE, 3 ether);
        _stakeAndDelegate(revnetId, BOB, 1 ether);
        // Checkpoints must be strictly before the fund snapshot block.
        vm.roll(block.number + 1);

        MockERC20Token reward = _newReward();
        uint256 fundAmount = 100e18;
        distributor.fund(stakeToken, IERC20(address(reward)), fundAmount);

        uint256 snap = distributor.roundSnapshotBlock(0);
        uint256 total = IVotes(stakeToken).getPastTotalSupply(snap);
        uint256 aliceVotes = IVotes(stakeToken).getPastVotes(ALICE, snap);
        uint256 bobVotes = IVotes(stakeToken).getPastVotes(BOB, snap);
        assertGt(total, 0, "snapshot total stake should be non-zero");
        assertGt(aliceVotes, 0, "alice should have delegated votes at snapshot");
        assertGt(bobVotes, 0, "bob should have delegated votes at snapshot");

        // Round 0 funded; advance into round 1 so it is claimable, materialize the vest, then fully vest it.
        _advanceRound(); // round 1 — materialize round-0 reward into a vest
        _collect(ALICE, stakeToken, IERC20(address(reward)));
        _collect(BOB, stakeToken, IERC20(address(reward)));
        for (uint256 i; i < VESTING_ROUNDS; ++i) {
            _advanceRound();
        }
        _collect(ALICE, stakeToken, IERC20(address(reward)));
        _collect(BOB, stakeToken, IERC20(address(reward)));

        uint256 aliceGot = reward.balanceOf(ALICE);
        uint256 bobGot = reward.balanceOf(BOB);
        uint256 aliceShare = fundAmount * aliceVotes / total;
        uint256 bobShare = fundAmount * bobVotes / total;

        assertApproxEqAbs(aliceGot, aliceShare, 2, "alice receives her full proportional share once vested");
        assertApproxEqAbs(bobGot, bobShare, 2, "bob receives his full proportional share once vested");
        // Proportionality (cross-multiply, tolerate rounding).
        assertApproxEqAbs(aliceGot * bobVotes, bobGot * aliceVotes, aliceVotes + bobVotes, "rewards are proportional");
        // Nothing left vesting; pot fully distributed (minus rounding dust retained in the distributor).
        assertEq(distributor.claimedFor(stakeToken, _id(ALICE), IERC20(address(reward))), 0, "alice fully vested");
        assertLe(reward.balanceOf(address(distributor)), 2, "pot distributed (<= dust remains)");
    }

    /// @notice A round funded with zero snapshot stake locks its rewards; only recoverable via expiry recycle.
    function test_distributor_zeroTotalStake_locksUntilExpiry() public {
        uint256 revnetId = _deployRevnet(0);
        address stakeToken = address(jbTokens().tokenOf(revnetId));
        // No pay yet -> zero supply. Mine a clean strictly-past block with zero supply.
        vm.roll(block.number + 1);

        MockERC20Token reward = _newReward();
        uint256 fundAmount = 100e18;
        distributor.fund(stakeToken, IERC20(address(reward)), fundAmount);

        // The round-0 snapshot froze totalStake at 0 (no supply existed).
        uint256 snap = distributor.roundSnapshotBlock(0);
        assertEq(IVotes(stakeToken).getPastTotalSupply(snap), 0, "snapshot total stake is zero (no supply existed)");

        // NOW stake — supply appears at later blocks, but round 0's snapshot is already frozen at zero.
        _stakeAndDelegate(revnetId, ALICE, 5 ether);
        vm.roll(block.number + 1);

        _advanceRound(); // round 1 (round 0 completed)
        _advanceRound(); // round 2 (would-be unlock window)

        uint256 before = reward.balanceOf(ALICE);
        _collect(ALICE, stakeToken, IERC20(address(reward)));
        assertEq(reward.balanceOf(ALICE), before, "round 0 rewards are LOCKED (zero totalStake -> round skipped)");
        assertEq(distributor.collectableFor(stakeToken, _id(ALICE), IERC20(address(reward))), 0, "nothing collectable");
        assertEq(distributor.claimedFor(stakeToken, _id(ALICE), IERC20(address(reward))), 0, "nothing entered vesting");
        assertEq(reward.balanceOf(address(distributor)), fundAmount, "full pot stranded in the distributor");

        // Recovery ONLY via expiry recycle. Before the deadline, recycleExpiredRewards is a no-op.
        uint256[] memory r = new uint256[](1);
        r[0] = 0;
        assertEq(distributor.recycleExpiredRewards(stakeToken, IERC20(address(reward)), r), 0, "not yet expired");

        // Warp past the claim deadline (round-1 start + CLAIM_DURATION) and recycle.
        vm.warp(distributor.roundStartTimestamp(1) + CLAIM_DURATION + 1);
        vm.roll(block.number + 1);
        assertEq(
            distributor.recycleExpiredRewards(stakeToken, IERC20(address(reward)), r),
            fundAmount,
            "the only recovery is the expiry recycle of the full unclaimed pot"
        );
    }
}
