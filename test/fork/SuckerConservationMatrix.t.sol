// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../helpers/SuckerConservationBase.sol";

/// @notice Cross-chain conservation matrix for suckers: every cell of {OP sucker, CCIP sucker} × {NATIVE, USDC}
/// terminal token runs the SAME assertions, proving balance/surplus AND project-token supply are conveyed and used
/// consistently across chains, regardless of bridge or token.
///
/// The shared body pins, per cell:
///   - **Round-trip conservation**: a real `prepare` (burn n project tokens + cash out `reclaimed` terminal tokens to
///     the outbox) relayed back through `fromRemote`/`ccipReceive` + `claim` (mint n + deposit `reclaimed`) returns
///     supply and terminal balance EXACTLY to their starting values — no value created or destroyed in conveyance.
///   - **totalSupply conveyance + staleness**: the conveyed source supply lands in `peerChainTotalSupplyOf(remote)`,
/// and a stale snapshot never overwrites a fresher one.
///   - **Stress edges**: duplicate-claim reverts, zero-project-token prepare reverts, claim front-run mints to the
///     leaf's beneficiary (not the caller).
abstract contract SuckerConservationMatrixTest is SuckerConservationBase {
    uint256 internal revnetId;
    address internal sucker;
    address internal token; // terminal token: NATIVE_TOKEN or a mock USDC address
    address internal HOLDER = makeAddr("scHolder");

    // ── Per-cell hooks
    // ───────────────────────────────────────────────
    /// @dev Deploy the cell's bridge infra + revnet + sucker, set {revnetId, sucker, token}, and fund HOLDER with
    /// project tokens.
    function _setupCell() internal virtual;

    /// @dev Relay one leaf into the sucker's inbox over this cell's bridge (OP `fromRemote` or CCIP `ccipReceive`).
    function _relay(
        address sucker_,
        address token_,
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        bytes32 beneficiary,
        uint256 sourceTotalSupply,
        uint256 sourceTimestamp
    )
        internal
        virtual
        returns (uint256 index);

    /// @dev A representative terminal-token amount in this cell's decimals (1 ether native, 1 USDC).
    function _sampleAmount() internal pure virtual returns (uint256);

    function setUp() public virtual override {
        super.setUp();
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
        _deployFeeProject(0);
        vm.deal(HOLDER, 100 ether);
        _setupCell();
    }

    function test_roundTripConservesAndConveys() public {
        uint256 holderTokens = jbTokens().totalBalanceOf(HOLDER, revnetId);
        assertGt(holderTokens, 0, "holder has project tokens");
        uint256 n = holderTokens / 2;

        uint256 supplyBefore = jbTokens().totalSupplyOf(revnetId);
        uint256 balBefore = _terminalBalance(revnetId, token);

        // SOURCE side: prepare burns n project tokens and cashes out `reclaimed` terminal tokens to the outbox.
        uint256 reclaimed = _prepare(revnetId, sucker, HOLDER, token, n);
        assertGt(reclaimed, 0, "cash-out reclaimed terminal tokens");
        assertEq(jbTokens().totalSupplyOf(revnetId), supplyBefore - n, "prepare burns exactly n");
        assertEq(_terminalBalance(revnetId, token), balBefore - reclaimed, "prepare drains exactly reclaimed");
        assertEq(IJBSucker(sucker).outboxOf(token).balance, reclaimed, "outbox holds reclaimed");

        // REMOTE side: relay the SAME leaf back (conveying the source supply) and claim it.
        uint256 sourceSupply = jbTokens().totalSupplyOf(revnetId);
        uint256 idx = _relay(sucker, token, n, reclaimed, _b32(HOLDER), sourceSupply, 1000);
        _claim(sucker, token, n, reclaimed, _b32(HOLDER), idx);

        // Conservation: supply and terminal balance return exactly to their pre-prepare values.
        assertEq(jbTokens().totalSupplyOf(revnetId), supplyBefore, "round trip conserves supply (burn n == mint n)");
        assertEq(_terminalBalance(revnetId, token), balBefore, "round trip conserves terminal balance");
        // Conveyance of the cross-chain effective supply used for remote cash-out pricing.
        assertEq(
            IJBSucker(sucker).peerChainTotalSupplyOf(REMOTE_CHAIN_ID),
            sourceSupply,
            "sourceTotalSupply conveyed to peer"
        );
        assertEq(IJBSucker(sucker).snapshotTimestampOf(REMOTE_CHAIN_ID), 1000, "snapshot timestamp recorded");
    }

    function test_totalSupplyConveyanceAndStaleness() public {
        assertEq(IJBSucker(sucker).peerChainTotalSupplyOf(REMOTE_CHAIN_ID), 0, "no conveyed supply at start");

        _relay(sucker, token, 1, 0, _b32(HOLDER), 7000e18, 100);
        assertEq(IJBSucker(sucker).peerChainTotalSupplyOf(REMOTE_CHAIN_ID), 7000e18, "fresh snapshot conveyed");
        assertEq(IJBSucker(sucker).snapshotTimestampOf(REMOTE_CHAIN_ID), 100, "timestamp advanced");

        _relay(sucker, token, 1, 0, _b32(HOLDER), 1, 50);
        assertEq(IJBSucker(sucker).peerChainTotalSupplyOf(REMOTE_CHAIN_ID), 7000e18, "stale snapshot ignored");
        assertEq(IJBSucker(sucker).snapshotTimestampOf(REMOTE_CHAIN_ID), 100, "timestamp not rolled back");

        _relay(sucker, token, 1, 0, _b32(HOLDER), 9999e18, 200);
        assertEq(IJBSucker(sucker).peerChainTotalSupplyOf(REMOTE_CHAIN_ID), 9999e18, "fresher snapshot conveyed");
        assertEq(IJBSucker(sucker).snapshotTimestampOf(REMOTE_CHAIN_ID), 200, "timestamp advanced again");
    }

    function test_duplicateClaimReverts() public {
        uint256 amt = _sampleAmount();
        uint256 idx = _relay(sucker, token, 1000e18, amt, _b32(HOLDER), 0, 1);
        _claim(sucker, token, 1000e18, amt, _b32(HOLDER), idx);

        vm.expectRevert(abi.encodeWithSelector(JBSucker.JBSucker_LeafAlreadyExecuted.selector, token, idx));
        _claim(sucker, token, 1000e18, amt, _b32(HOLDER), idx);
    }

    function test_zeroProjectTokenPrepareReverts() public {
        vm.startPrank(HOLDER);
        vm.expectRevert(JBSucker.JBSucker_ZeroProjectTokenCount.selector);
        IJBSucker(sucker).prepare(0, _b32(HOLDER), 0, token, bytes32(0));
        vm.stopPrank();
    }

    function test_claimFrontRunMintsToBeneficiary() public {
        address attacker = makeAddr("scAttacker");
        uint256 amt = _sampleAmount();
        uint256 idx = _relay(sucker, token, 1000e18, amt, _b32(HOLDER), 0, 1);

        uint256 holderBefore = jbTokens().totalBalanceOf(HOLDER, revnetId);
        uint256 attackerBefore = jbTokens().totalBalanceOf(attacker, revnetId);

        vm.prank(attacker);
        _claim(sucker, token, 1000e18, amt, _b32(HOLDER), idx);

        assertEq(jbTokens().totalBalanceOf(HOLDER, revnetId), holderBefore + 1000e18, "minted to beneficiary");
        assertEq(jbTokens().totalBalanceOf(attacker, revnetId), attackerBefore, "front-runner gains nothing");
    }

    function _b32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Concrete cells
// ═══════════════════════════════════════════════════════════════════════════

/// @notice OP sucker × native ETH.
contract SuckerConservationOpNativeTest is SuckerConservationMatrixTest {
    function _deployerSalt() internal pure override returns (bytes32) {
        return "SuckerCons_OpNative";
    }

    function _setupCell() internal override {
        _deployOpInfra();
        token = JBConstants.NATIVE_TOKEN;
        revnetId = _deployRevnet(0);
        sucker = _deployOpSuckerNative(revnetId, bytes32("OPN"));
        _payRevnet(revnetId, HOLDER, 10 ether);
    }

    function _relay(
        address s,
        address t,
        uint256 p,
        uint256 a,
        bytes32 b,
        uint256 sts,
        uint256 ts
    )
        internal
        override
        returns (uint256)
    {
        return _opRelay(s, t, p, a, b, sts, ts);
    }

    function _sampleAmount() internal pure override returns (uint256) {
        return 1 ether;
    }
}

/// @notice CCIP sucker × native ETH (wrapped to WETH on the wire, unwrapped on receive).
contract SuckerConservationCcipNativeTest is SuckerConservationMatrixTest {
    function _deployerSalt() internal pure override returns (bytes32) {
        return "SuckerCons_CcipNative";
    }

    function _setupCell() internal override {
        _deployCcipInfra();
        token = JBConstants.NATIVE_TOKEN;
        revnetId = _deployRevnet(0);
        sucker = _deployCcipSuckerNative(revnetId, bytes32("CCIPN"));
        _payRevnet(revnetId, HOLDER, 10 ether);
    }

    function _relay(
        address s,
        address t,
        uint256 p,
        uint256 a,
        bytes32 b,
        uint256 sts,
        uint256 ts
    )
        internal
        override
        returns (uint256)
    {
        return _ccipRelay(s, t, p, a, b, sts, ts);
    }

    function _sampleAmount() internal pure override returns (uint256) {
        return 1 ether;
    }
}

/// @notice OP sucker × 6-decimal USDC.
contract SuckerConservationOpUsdcTest is SuckerConservationMatrixTest {
    MockERC20Token internal usdc;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "SuckerCons_OpUsdc";
    }

    function _setupCell() internal override {
        _deployOpInfra();
        (revnetId, usdc) = _deployUsdcRevnet(0, bytes32("OPU"));
        token = address(usdc);
        sucker = _deploySucker(
            address(opDeployer), revnetId, bytes32("OPU_SUCK"), address(usdc), bytes32(uint256(uint160(address(usdc))))
        );
        _payRevnetUsdc(revnetId, usdc, HOLDER, 10_000e6);
    }

    function _relay(
        address s,
        address t,
        uint256 p,
        uint256 a,
        bytes32 b,
        uint256 sts,
        uint256 ts
    )
        internal
        override
        returns (uint256)
    {
        return _opRelay(s, t, p, a, b, sts, ts);
    }

    function _sampleAmount() internal pure override returns (uint256) {
        return 1e6;
    }
}

/// @notice CCIP sucker × 6-decimal USDC (rides the lane as a standard CCIP-bridged ERC20).
contract SuckerConservationCcipUsdcTest is SuckerConservationMatrixTest {
    MockERC20Token internal usdc;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "SuckerCons_CcipUsdc";
    }

    function _setupCell() internal override {
        _deployCcipInfra();
        (revnetId, usdc) = _deployUsdcRevnet(0, bytes32("CCIPU"));
        token = address(usdc);
        sucker = _deploySucker(
            address(ccipDeployer),
            revnetId,
            bytes32("CCIPU_SUCK"),
            address(usdc),
            bytes32(uint256(uint160(address(usdc))))
        );
        _payRevnetUsdc(revnetId, usdc, HOLDER, 10_000e6);
    }

    function _relay(
        address s,
        address t,
        uint256 p,
        uint256 a,
        bytes32 b,
        uint256 sts,
        uint256 ts
    )
        internal
        override
        returns (uint256)
    {
        return _ccipRelay(s, t, p, a, b, sts, ts);
    }

    function _sampleAmount() internal pure override returns (uint256) {
        return 1e6;
    }
}
