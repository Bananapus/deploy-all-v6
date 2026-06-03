// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../helpers/SuckerConservationBase.sol";

/// @notice Multi-lane conservation: one revnet with BOTH an OP sucker and a CCIP sucker (two independent bridges to two
/// remote chains). Pins that each lane keeps an independent inbox / executed-leaf set (a claim on one lane neither
/// settles nor blocks the other), yet both lanes mint into the same project supply and deposit into the same terminal
/// —
/// so the project's balance/supply accounting stays correct no matter how many lanes feed it.
///
/// Run with: forge test --match-contract SuckerMultiLaneForkTest -vvv
contract SuckerMultiLaneForkTest is SuckerConservationBase {
    address internal constant NATIVE = JBConstants.NATIVE_TOKEN;

    uint256 internal revnetId;
    address internal opSucker;
    address internal ccipSucker;
    address internal HOLDER = makeAddr("mlHolder");

    function _deployerSalt() internal pure override returns (bytes32) {
        return "SuckerMultiLane";
    }

    function setUp() public override {
        super.setUp();
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
        _deployFeeProject(0);
        _deployOpInfra();
        _deployCcipInfra();

        revnetId = _deployRevnet(0);
        opSucker = _deployOpSuckerNative(revnetId, bytes32("ML_OP"));
        ccipSucker = _deployCcipSuckerNative(revnetId, bytes32("ML_CCIP"));

        vm.deal(HOLDER, 100 ether);
        _payRevnet(revnetId, HOLDER, 10 ether);
    }

    function _ben() internal view returns (bytes32) {
        return bytes32(uint256(uint160(HOLDER)));
    }

    /// @notice Distinct leaves on each lane settle independently into the SAME terminal and supply.
    function test_multiLane_independentInboxesSameTerminal() public {
        uint256 balBefore = _terminalBalance(revnetId, NATIVE);
        uint256 supplyBefore = jbTokens().totalSupplyOf(revnetId);

        uint256 opIdx = _opRelay(opSucker, NATIVE, 1000e18, 1 ether, _ben(), 0, 1);
        uint256 ccipIdx = _ccipRelay(ccipSucker, NATIVE, 2000e18, 2 ether, _ben(), 0, 1);

        // Settle the OP lane only.
        _claim(opSucker, NATIVE, 1000e18, 1 ether, _ben(), opIdx);
        assertTrue(IJBSucker(opSucker).executedLeafHashOf(NATIVE, opIdx) != bytes32(0), "op leaf executed");
        assertEq(
            IJBSucker(ccipSucker).executedLeafHashOf(NATIVE, ccipIdx),
            bytes32(0),
            "ccip inbox is independent (not settled by the op claim)"
        );
        assertEq(_terminalBalance(revnetId, NATIVE), balBefore + 1 ether, "only the op deposit landed so far");

        // Settle the CCIP lane.
        _claim(ccipSucker, NATIVE, 2000e18, 2 ether, _ben(), ccipIdx);

        // Both lanes fed the one project: terminal + supply reflect the sum.
        assertEq(_terminalBalance(revnetId, NATIVE), balBefore + 3 ether, "both lanes deposit into the one terminal");
        assertEq(jbTokens().totalSupplyOf(revnetId), supplyBefore + 3000e18, "both lanes mint into the one supply");
    }

    /// @notice The SAME leaf payload can be settled once on EACH lane (separate executed-sets), but never twice on one
    /// lane. This proves the double-spend guard is per-sucker, not global, while still preventing replay within a lane.
    function test_multiLane_sameLeafSettlesOncePerLaneNotTwice() public {
        uint256 balBefore = _terminalBalance(revnetId, NATIVE);

        // Identical payload relayed to both lanes.
        uint256 opIdx = _opRelay(opSucker, NATIVE, 500e18, 0.5 ether, _ben(), 0, 1);
        uint256 ccipIdx = _ccipRelay(ccipSucker, NATIVE, 500e18, 0.5 ether, _ben(), 0, 1);

        _claim(opSucker, NATIVE, 500e18, 0.5 ether, _ben(), opIdx);
        // Same payload still settles on the OTHER lane (independent executed-set).
        _claim(ccipSucker, NATIVE, 500e18, 0.5 ether, _ben(), ccipIdx);
        assertEq(_terminalBalance(revnetId, NATIVE), balBefore + 1 ether, "each lane deposited its own 0.5 ETH");

        // But neither lane allows a replay of its own leaf.
        vm.expectRevert(abi.encodeWithSelector(JBSucker.JBSucker_LeafAlreadyExecuted.selector, NATIVE, opIdx));
        _claim(opSucker, NATIVE, 500e18, 0.5 ether, _ben(), opIdx);

        vm.expectRevert(abi.encodeWithSelector(JBSucker.JBSucker_LeafAlreadyExecuted.selector, NATIVE, ccipIdx));
        _claim(ccipSucker, NATIVE, 500e18, 0.5 ether, _ben(), ccipIdx);
    }
}
