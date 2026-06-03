// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../helpers/SuckerConservationBase.sol";

/// @notice **Stateful stress invariant for cross-chain sucker conservation.**
///
/// A fuzzer hammers an OP-native revnet+sucker with random sequences of: pay (mint), bridge round trip (prepare burns +
/// relay/claim re-mints, atomically), and cash out (burn for ETH). Across every reachable state it asserts that the
/// bridging machinery never creates or destroys project-token supply or terminal ETH:
///   - total project-token supply always equals the sum of the tracked holders' balances (every mint/burn is
///     accounted; bridge round trips are supply-neutral);
///   - cumulative ETH cashed out never exceeds cumulative ETH paid in (no value minted from bridging);
///   - the terminal balance stays bounded by cumulative inflows.
///
/// The handler functions live on this contract and are fuzzer-targeted directly so they can reuse the relay harness.
///
/// forge-config: default.invariant.runs = 16
/// forge-config: default.invariant.depth = 50
/// forge-config: default.invariant.fail-on-revert = false
contract SuckerConservationInvariant is SuckerConservationBase {
    address internal constant NATIVE = JBConstants.NATIVE_TOKEN;

    uint256 internal revnetId;
    address internal sucker;
    address[] internal holders;

    uint256 public totalPaidIn;
    uint256 public totalCashedOut;
    uint256 public roundTrips;
    uint256 public payCalls;
    uint256 public cashOutCalls;
    uint256 internal _ts;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "SuckerConsInv";
    }

    function setUp() public override {
        super.setUp();
        require(block.chainid == 1, "fork must be on mainnet");
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
        _deployFeeProject(0);
        _deployOpInfra();

        revnetId = _deployRevnet(0);
        sucker = _deployOpSuckerNative(revnetId, bytes32("INV_OP"));

        holders.push(makeAddr("invH1"));
        holders.push(makeAddr("invH2"));
        holders.push(makeAddr("invH3"));
        for (uint256 i; i < holders.length; ++i) {
            vm.deal(holders[i], 1000 ether);
        }

        // Seed supply + surplus so bridge round trips have something to work with.
        _payRevnet(revnetId, holders[0], 10 ether);
        totalPaidIn = 10 ether;

        targetContract(address(this));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = this.handler_pay.selector;
        selectors[1] = this.handler_bridgeRoundTrip.selector;
        selectors[2] = this.handler_cashOut.selector;
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Fuzzer-targeted handlers
    // ═══════════════════════════════════════════════════════════════════

    function handler_pay(uint256 holderSeed, uint256 amount) public {
        amount = bound(amount, 0.01 ether, 5 ether);
        address h = holders[holderSeed % holders.length];
        vm.deal(h, h.balance + amount);
        _payRevnet(revnetId, h, amount);
        totalPaidIn += amount;
        payCalls++;
    }

    /// @dev Prepare a fraction of a holder's tokens (burns + drains to outbox), then relay the leaf back and claim it
    /// (re-mints + re-deposits). Supply- and terminal-neutral by construction; stresses the conveyance path.
    function handler_bridgeRoundTrip(uint256 holderSeed, uint256 fracSeed) public {
        address h = holders[holderSeed % holders.length];
        uint256 bal = jbTokens().totalBalanceOf(h, revnetId);
        if (bal == 0) return;
        uint256 n = bound(fracSeed, 1, bal);

        uint256 reclaimed = _prepare(revnetId, sucker, h, NATIVE, n);
        uint256 idx = _opRelay(
            sucker, NATIVE, n, reclaimed, bytes32(uint256(uint160(h))), jbTokens().totalSupplyOf(revnetId), ++_ts
        );
        _claim(sucker, NATIVE, n, reclaimed, bytes32(uint256(uint160(h))), idx);
        roundTrips++;
    }

    function handler_cashOut(uint256 holderSeed, uint256 fracSeed) public {
        address h = holders[holderSeed % holders.length];
        uint256 bal = jbTokens().totalBalanceOf(h, revnetId);
        if (bal == 0) return;
        uint256 n = bound(fracSeed, 1, bal);

        uint256 ethBefore = h.balance;
        vm.prank(h);
        (bool ok,) = address(jbMultiTerminal())
            .call(
                abi.encodeWithSignature(
                    "cashOutTokensOf(address,uint256,uint256,address,uint256,address,bytes)",
                    h,
                    revnetId,
                    n,
                    NATIVE,
                    0,
                    h,
                    ""
                )
            );
        if (!ok) return;
        totalCashedOut += h.balance - ethBefore;
        cashOutCalls++;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Invariants
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Every project token is held by a tracked holder — bridging never conjures or strands supply.
    function invariant_supplyEqualsTrackedBalances() public view {
        uint256 tracked;
        for (uint256 i; i < holders.length; ++i) {
            tracked += jbTokens().totalBalanceOf(holders[i], revnetId);
        }
        assertEq(jbTokens().totalSupplyOf(revnetId), tracked, "supply == sum of tracked holder balances");
    }

    /// @notice No ETH is created: cumulative cash-outs never exceed cumulative pay-ins.
    function invariant_noEthCreated() public view {
        assertLe(totalCashedOut, totalPaidIn + 1, "cumulative cash-outs cannot exceed cumulative pay-ins");
    }

    /// @notice The terminal balance is bounded above by cumulative inflows.
    function invariant_terminalBoundedByInflows() public view {
        assertLe(_terminalBalance(revnetId, NATIVE), totalPaidIn + 1, "terminal balance bounded by cumulative inflows");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Sanity: a scripted interleaving holds all invariants
    // ═══════════════════════════════════════════════════════════════════

    function test_sucker_stressSanity() public {
        handler_pay(1, 3 ether);
        handler_bridgeRoundTrip(0, type(uint256).max / 3);
        handler_bridgeRoundTrip(1, type(uint256).max / 2);
        handler_cashOut(0, type(uint256).max / 4);
        handler_pay(2, 1 ether);
        handler_bridgeRoundTrip(2, type(uint256).max);
        assertGt(roundTrips, 0, "round trips executed");

        invariant_supplyEqualsTrackedBalances();
        invariant_noEthCreated();
        invariant_terminalBoundedByInflows();
    }
}
