// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";

/// @notice Handler exposing bounded random actions over a revnet that simultaneously has a reserved (split) rate
/// accruing PENDING tokens, the buyback data hook composed into every pay, and live loans. Tracks every ETH flow so
/// the invariants can assert conservation.
///
/// Actions:
///   - pay(holderSeed, amount)            — pay the revnet (mints tokens + accrues reserved, through the buyback
/// hook).
///   - cashOut(holderSeed, amountSeed)    — cash out a holder's tokens against the reserved-inflated bonding curve.
///   - borrow(holderSeed, amountSeed)     — open a loan against a holder's tokens (collateral burned from supply).
///   - repay(loanSeed)                    — repay a tracked loan in full.
///   - distributeReserved()               — `sendReservedTokensToSplitsOf` (mints pending reserved to the split).
contract ComposedConservationHandler is Test {
    address internal constant NATIVE = JBConstants.NATIVE_TOKEN;

    address public immutable TEST_CONTRACT;
    uint256 public immutable REVNET_ID;
    address public immutable TERMINAL;
    address public immutable JB_TOKENS;
    address public immutable JB_CONTROLLER;
    address public immutable LOANS;
    address public immutable JB_PERMISSIONS;

    address[] public holders;
    uint256[] public loanIds;

    // ── ETH-flow ledgers (consumed by the invariants)
    uint256 public totalPaidIn; // ETH tendered on pay
    uint256 public totalCashedOutGross; // ETH withdrawn via cashOut
    uint256 public totalBorrowedOut; // ETH delivered to borrowers (loan principal)
    uint256 public totalRepaid; // ETH spent repaying loans

    // ── Action counters (consumed by the sanity test to prove the surfaces are live)
    uint256 public payCalls;
    uint256 public cashOutCalls;
    uint256 public borrowCalls;
    uint256 public repayCalls;
    uint256 public distributeCalls;

    constructor(
        address testContract,
        uint256 revnetId,
        address terminal,
        address jbTokens,
        address jbController,
        address loans,
        address jbPermissions
    ) {
        TEST_CONTRACT = testContract;
        REVNET_ID = revnetId;
        TERMINAL = terminal;
        JB_TOKENS = jbTokens;
        JB_CONTROLLER = jbController;
        LOANS = loans;
        JB_PERMISSIONS = jbPermissions;

        holders.push(makeAddr("ccHolder1"));
        holders.push(makeAddr("ccHolder2"));
        holders.push(makeAddr("ccHolder3"));
        for (uint256 i; i < holders.length; ++i) {
            vm.deal(holders[i], 1000 ether);
            _grantBurnPermission(holders[i]);
        }
    }

    receive() external payable {}

    // ═════════════════════════════════════════════════════════════════════
    //  Fuzzer-exposed actions
    // ═════════════════════════════════════════════════════════════════════

    function pay(uint256 holderSeed, uint256 amount) external {
        amount = bound(amount, 0.05 ether, 5 ether);
        address holder = holders[holderSeed % holders.length];
        vm.deal(holder, holder.balance + amount);

        vm.prank(holder);
        (bool ok,) = TERMINAL.call{value: amount}(
            abi.encodeWithSignature(
                "pay(uint256,address,uint256,address,uint256,string,bytes)",
                REVNET_ID,
                NATIVE,
                amount,
                holder,
                0,
                "",
                ""
            )
        );
        if (!ok) return;
        totalPaidIn += amount;
        payCalls++;
    }

    function cashOut(uint256 holderSeed, uint256 amountSeed) external {
        address holder = holders[holderSeed % holders.length];
        uint256 bal = _tokenBalanceOf(holder);
        if (bal == 0) return;
        uint256 cashAmount = bound(amountSeed, 1, bal);

        uint256 ethBefore = holder.balance;
        vm.prank(holder);
        (bool ok,) = TERMINAL.call(
            abi.encodeWithSignature(
                "cashOutTokensOf(address,uint256,uint256,address,uint256,address,bytes)",
                holder,
                REVNET_ID,
                cashAmount,
                NATIVE,
                0,
                holder,
                ""
            )
        );
        if (!ok) return;
        totalCashedOutGross += holder.balance - ethBefore;
        cashOutCalls++;
    }

    function borrow(uint256 holderSeed, uint256 amountSeed) external {
        address holder = holders[holderSeed % holders.length];
        uint256 bal = _tokenBalanceOf(holder);
        if (bal == 0) return;
        uint256 collateral = bound(amountSeed, 1, bal);

        (, bytes memory prepRes) = LOANS.staticcall(abi.encodeWithSignature("MIN_PREPAID_FEE_PERCENT()"));
        uint256 prepaidFee = abi.decode(prepRes, (uint256));

        uint256 ethBefore = holder.balance;
        vm.prank(holder);
        (bool ok, bytes memory res) = LOANS.call(
            abi.encodeWithSignature(
                "borrowFrom(uint256,address,uint256,uint256,address,uint256,address)",
                REVNET_ID,
                NATIVE,
                0,
                collateral,
                holder,
                prepaidFee,
                holder
            )
        );
        if (!ok) return;
        (uint256 loanId,) = abi.decode(res, (uint256, REVLoan));
        loanIds.push(loanId);
        totalBorrowedOut += holder.balance - ethBefore;
        borrowCalls++;
    }

    function repay(uint256 loanSeed) external {
        if (loanIds.length == 0) return;
        uint256 loanId = loanIds[loanSeed % loanIds.length];

        (, bytes memory loanRes) = LOANS.staticcall(abi.encodeWithSignature("loanOf(uint256)", loanId));
        if (loanRes.length == 0) return;
        REVLoan memory l = abi.decode(loanRes, (REVLoan));
        if (l.amount == 0) return;

        address payer = holders[0];
        uint256 repayAmount = uint256(l.amount) + 1 ether; // overpay; excess refunded.
        vm.deal(payer, payer.balance + repayAmount);
        uint256 payerBefore = payer.balance;

        vm.prank(payer);
        (bool ok,) = LOANS.call{value: repayAmount}(
            abi.encodeWithSignature(
                "repayLoan(uint256,uint256,uint256,address,bytes)", loanId, type(uint256).max, 0, payer, ""
            )
        );
        if (!ok) return;
        totalRepaid += payerBefore - payer.balance;
        repayCalls++;
    }

    function distributeReserved() external {
        (bool ok,) = JB_CONTROLLER.call(abi.encodeWithSignature("sendReservedTokensToSplitsOf(uint256)", REVNET_ID));
        if (ok) distributeCalls++;
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Views
    // ═════════════════════════════════════════════════════════════════════

    function holdersCount() external view returns (uint256) {
        return holders.length;
    }

    function holderAt(uint256 i) external view returns (address) {
        return holders[i];
    }

    function _tokenBalanceOf(address holder) internal view returns (uint256) {
        (, bytes memory res) =
            JB_TOKENS.staticcall(abi.encodeWithSignature("totalBalanceOf(address,uint256)", holder, REVNET_ID));
        return abi.decode(res, (uint256));
    }

    function _grantBurnPermission(address holder) internal {
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 11; // BURN_TOKENS
        vm.prank(holder);
        (bool ok,) = JB_PERMISSIONS.call(
            abi.encodeWithSignature(
                "setPermissionsFor(address,(address,uint64,uint8[]))",
                holder,
                JBPermissionsData({operator: LOANS, projectId: uint64(REVNET_ID), permissionIds: permissionIds})
            )
        );
        ok;
    }
}

/// @notice **Composed conservation invariant — reserved + loans + cash-out interleaved.**
///
/// The existing `CrossChainArbInvariant` exercises pay/cashout/borrow/repay conservation, but always on a revnet with
/// `splitPercent = 0` — so reserved tokens never accrue and the reserved↔minted↔loan accounting never overlaps.
/// The
/// confirmed accounting-drift risk lives where MORE surfaces overlap at once. This suite stands up a revnet that
/// simultaneously composes:
///   (1) the buyback data hook on every pay (the REVOwner → registry → buyback chain evaluates mint-vs-swap),
///   (2) a 20% reserved rate accruing PENDING tokens (seeded to a standing balance, then distributed mid-run),
///   (3) open LOANS (collateral burned out of supply on borrow, restored on repay), and
///   (4) cash-outs against the reserved-INFLATED bonding curve.
///
/// Across random action sequences it asserts that neither ETH nor token supply can be created out of thin air at that
/// intersection. (Note: the buyback hook is mocked at a 1:1 oracle so pays take the MINT path — actual on-chain swap
/// execution is a documented harness limitation, since the V4 pool's initialized price is decoupled from the mocked
/// TWAP. The hook is still composed into and consulted on every pay.)
///
/// forge-config: default.invariant.runs = 16
/// forge-config: default.invariant.depth = 40
/// forge-config: default.invariant.fail-on-revert = false
contract ComposedConservationInvariant is RevnetForkBase {
    uint16 internal constant RESERVED_PERCENT = 2000; // 20% of issuance reserved -> pending
    uint16 internal constant CASH_OUT_TAX = 1000; // 10%

    uint256 internal revnetId;
    ComposedConservationHandler internal handler;

    uint256 internal initialPaidIn; // ETH paid into the terminal during the seed
    address internal seeder = makeAddr("ccSeeder");

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_ComposedCons";
    }

    function setUp() public override {
        super.setUp();
        require(block.chainid == 1, "fork must be on mainnet");

        _deployFeeProject(1000);

        // Deploy a revnet with a 20% reserved rate routed to a single split beneficiary.
        revnetId = _deployReservedRevnet();

        // The buyback hook reads a TWAP on every pay; mock it 1:1 (tick 0) so pays take the MINT path (no real pool
        // needed). This mints nothing itself and keeps every pay on a deterministic, non-reverting path.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Seed: fund the terminal surplus (so loans have collateral value to borrow against) AND accrue a standing
        // PENDING reserved balance that will still be outstanding while loans/cash-outs run.
        uint256 seed = 20 ether;
        vm.deal(seeder, seed);
        _payRevnet(revnetId, seeder, seed);
        initialPaidIn = seed;

        assertGt(jbController().pendingReservedTokenBalanceOf(revnetId), 0, "seed must leave pending reserved");
        assertGt(_terminalBalance(revnetId, JBConstants.NATIVE_TOKEN), 0, "seed must fund terminal surplus");
        // The buyback hook is genuinely composed into the pay path (registry default hook).
        assertEq(
            address(BUYBACK_REGISTRY.defaultHook()), address(BUYBACK_HOOK), "buyback hook composed into the pay path"
        );

        handler = new ComposedConservationHandler({
            testContract: address(this),
            revnetId: revnetId,
            terminal: address(jbMultiTerminal()),
            jbTokens: address(jbTokens()),
            jbController: address(jbController()),
            loans: address(LOANS_CONTRACT),
            jbPermissions: address(jbPermissions())
        });

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = ComposedConservationHandler.pay.selector;
        selectors[1] = ComposedConservationHandler.cashOut.selector;
        selectors[2] = ComposedConservationHandler.borrow.selector;
        selectors[3] = ComposedConservationHandler.repay.selector;
        selectors[4] = ComposedConservationHandler.distributeReserved.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ═════════════════════════════════════════════════════════════════════
    //  INVARIANTS
    // ═════════════════════════════════════════════════════════════════════

    /// @notice **ETH cannot be created.** Cumulative ETH paid OUT of the terminal (cash-outs + loan principal) can
    /// never exceed cumulative ETH paid IN (seed + pays + repays), even with reserved + loans + cash-outs interleaved.
    function invariant_ethOutflowBoundedByInflow() public view {
        uint256 inflows = initialPaidIn + handler.totalPaidIn() + handler.totalRepaid();
        uint256 outflows = handler.totalCashedOutGross() + handler.totalBorrowedOut();
        assertLe(outflows, inflows + 1, "outflows cannot exceed inflows (no ETH created at the intersection)");
    }

    /// @notice **Terminal surplus is bounded above by cumulative inflows** — no path inflates the treasury beyond
    /// what
    /// was paid in.
    function invariant_terminalSurplusBounded() public view {
        uint256 surplus = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        uint256 inflows = initialPaidIn + handler.totalPaidIn() + handler.totalRepaid();
        assertLe(surplus, inflows + 1, "terminal surplus bounded by cumulative inflows");
    }

    /// @notice **Token-supply identity holds with reserved + loans interleaved.** The reserved-inclusive total is
    /// always exactly minted supply plus pending reserved — the two accounting surfaces never drift.
    function invariant_tokenSupplyIdentity() public view {
        uint256 withReserved = jbController().totalTokenSupplyWithReservedTokensOf(revnetId);
        uint256 minted = jbTokens().totalSupplyOf(revnetId);
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        assertEq(withReserved, minted + pending, "withReserved == minted + pending (no token created/lost)");
    }

    /// @notice **No token is conjured.** The tracked holders plus the split beneficiary can never collectively hold
    /// more than the minted supply (they are a subset of all holders; collateral is burned out of supply on borrow).
    function invariant_trackedBalancesWithinSupply() public view {
        uint256 minted = jbTokens().totalSupplyOf(revnetId);
        uint256 tracked = jbTokens().totalBalanceOf(SPLIT_BENEFICIARY, revnetId);
        uint256 n = handler.holdersCount();
        for (uint256 i; i < n; ++i) {
            tracked += jbTokens().totalBalanceOf(handler.holderAt(i), revnetId);
        }
        assertLe(tracked, minted, "tracked balances <= minted supply");
    }

    /// @notice Pending reserved never exceeds the reserved-inclusive supply (no negative minted supply).
    function invariant_pendingWithinWithReserved() public view {
        assertLe(
            jbController().pendingReservedTokenBalanceOf(revnetId),
            jbController().totalTokenSupplyWithReservedTokensOf(revnetId),
            "pending reserved <= reserved-inclusive supply"
        );
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Sanity test — proves the surfaces are simultaneously live and the
    //  invariants hold through a hand-driven composed sequence.
    // ═════════════════════════════════════════════════════════════════════

    function test_handlerSanity_composedConservation() public {
        // Standing pending-reserved from the seed (surface 2) is live before we touch anything.
        assertGt(jbController().pendingReservedTokenBalanceOf(revnetId), 0, "pending reserved live at start");

        // Pays through the buyback-hook-composed path (surface 1) mint tokens + accrue more reserved.
        handler.pay({holderSeed: 0, amount: 3 ether});
        handler.pay({holderSeed: 1, amount: 1 ether});
        assertGt(handler.payCalls(), 0, "pays succeed through the composed buyback path");

        // Open a loan against a holder's tokens (surface 3) while pending reserved is still outstanding.
        handler.borrow({holderSeed: 0, amountSeed: type(uint256).max});
        assertGt(handler.borrowCalls(), 0, "a loan must open (surface 3 live)");
        assertGt(jbController().pendingReservedTokenBalanceOf(revnetId), 0, "pending still outstanding alongside loan");

        // Cash out against the reserved-inflated bonding curve (surface 4).
        handler.cashOut({holderSeed: 1, amountSeed: type(uint256).max});
        assertGt(handler.cashOutCalls(), 0, "a cash-out must succeed (surface 4 live)");

        // Distribute the pending reserved (pending -> minted) with a loan still open.
        handler.distributeReserved();
        assertGt(handler.distributeCalls(), 0, "reserved distribution must succeed");

        // Repay the loan.
        handler.repay({loanSeed: 0});

        // Every conservation invariant must hold after the composed sequence.
        invariant_ethOutflowBoundedByInflow();
        invariant_terminalSurplusBounded();
        invariant_tokenSupplyIdentity();
        invariant_trackedBalancesWithinSupply();
        invariant_pendingWithinWithReserved();
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Helpers
    // ═════════════════════════════════════════════════════════════════════

    function _deployReservedRevnet() internal returns (uint256 id) {
        JBAccountingContext[] memory tc = new JBAccountingContext[](1);
        tc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(SPLIT_BENEFICIARY),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: RESERVED_PERCENT,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: CASH_OUT_TAX,
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("Composed", "CMP", "ipfs://cmp", "CMP_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            operator: multisig(),
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("CMP"))
        });

        (id,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, accountingContextsToAccept: tc, suckerDeploymentConfiguration: sdc
        });
    }
}
