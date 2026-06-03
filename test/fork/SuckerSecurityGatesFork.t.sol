// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../helpers/SuckerConservationBase.sol";

/// @notice Negative coverage for the sucker's two security GATES — the merkle-proof check and the peer-authentication
/// check. The conservation suite drives the happy path (which, on one fork, necessarily constructs the inbox root it
/// later proves); these tests prove the complementary, non-tautological property: the gates REJECT input the harness
/// did NOT authorize. A forged leaf, a `fromRemote` not delivered by the bridge messenger, a spoofed cross-domain
/// sender, and a `ccipReceive` from a non-router must all revert.
///
/// Run with: forge test --match-contract SuckerSecurityGatesForkTest -vvv
contract SuckerSecurityGatesForkTest is SuckerConservationBase {
    address internal constant NATIVE = JBConstants.NATIVE_TOKEN;

    uint256 internal revnetId;
    address internal opSucker;
    address internal ccipSucker;
    address internal HOLDER = makeAddr("sgHolder");

    function _deployerSalt() internal pure override returns (bytes32) {
        return "SuckerSecGates";
    }

    function setUp() public override {
        super.setUp();
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
        _deployFeeProject(0);
        _deployOpInfra();
        _deployCcipInfra();

        revnetId = _deployRevnet(0);
        opSucker = _deployOpSuckerNative(revnetId, bytes32("SG_OP"));
        ccipSucker = _deployCcipSuckerNative(revnetId, bytes32("SG_CCIP"));

        vm.deal(HOLDER, 100 ether);
        _payRevnet(revnetId, HOLDER, 10 ether);
    }

    function _ben() internal view returns (bytes32) {
        return bytes32(uint256(uint160(HOLDER)));
    }

    function _root(uint256 nonce) internal pure returns (JBMessageRoot memory) {
        return JBMessageRoot({
            version: 1,
            token: bytes32(uint256(uint160(NATIVE))),
            amount: 0,
            remoteRoot: JBInboxTreeRoot({nonce: uint64(nonce), root: bytes32(uint256(1))}),
            sourceTotalSupply: 7000e18,
            sourceContexts: new JBSourceContext[](0),
            sourceTimestamp: 100
        });
    }

    // ── Merkle-proof gate
    // ────────────────────────────────────────────

    /// @notice A claim whose leaf does NOT match the relayed root (a forged amount) is rejected by the proof check —
    /// the merkle verification is load-bearing, not a rubber stamp.
    function test_gate_op_forgedLeafRejected() public {
        // Relay a real leaf committing to terminalTokenAmount = 1 ether.
        uint256 idx = _opRelay(opSucker, NATIVE, 1000e18, 1 ether, _ben(), 0, 1);

        // Claim the same index/beneficiary but with a FORGED terminalTokenAmount (5 ETH): the leaf hash no longer
        // matches the committed root, so the proof must fail.
        vm.expectPartialRevert(JBSucker.JBSucker_InvalidProof.selector);
        _claim(opSucker, NATIVE, 1000e18, 5 ether, _ben(), idx);
    }

    /// @notice Same gate over the CCIP lane.
    function test_gate_ccip_forgedLeafRejected() public {
        uint256 idx = _ccipRelay(ccipSucker, NATIVE, 1000e18, 1 ether, _ben(), 0, 1);
        vm.expectPartialRevert(JBSucker.JBSucker_InvalidProof.selector);
        _claim(ccipSucker, NATIVE, 1000e18, 5 ether, _ben(), idx);
    }

    /// @notice A forged projectTokenCount is likewise rejected (covers the other committed leaf field).
    function test_gate_op_forgedTokenCountRejected() public {
        uint256 idx = _opRelay(opSucker, NATIVE, 1000e18, 1 ether, _ben(), 0, 1);
        vm.expectPartialRevert(JBSucker.JBSucker_InvalidProof.selector);
        _claim(opSucker, NATIVE, 9999e18, 1 ether, _ben(), idx);
    }

    // ── OP peer-authentication gate
    // ──────────────────────────────────

    /// @notice `fromRemote` not delivered by the OP messenger is rejected (a direct caller cannot inject inbox roots).
    function test_gate_op_nonMessengerFromRemoteRejected() public {
        vm.expectPartialRevert(JBSucker.JBSucker_NotPeer.selector);
        JBSucker(payable(opSucker)).fromRemote(_root(1));
    }

    /// @notice `fromRemote` from the messenger but with a spoofed `xDomainMessageSender` (not the peer) is rejected.
    function test_gate_op_spoofedXDomainSenderRejected() public {
        opMessenger.setXDomainMessageSender(makeAddr("notThePeer"));
        vm.prank(address(opMessenger));
        vm.expectPartialRevert(JBSucker.JBSucker_NotPeer.selector);
        JBSucker(payable(opSucker)).fromRemote(_root(1));
    }

    // ── CCIP peer-authentication gate
    // ────────────────────────────────

    /// @notice `ccipReceive` from a non-router is rejected (only the configured CCIP router may deliver).
    function test_gate_ccip_nonRouterRejected() public {
        Client.Any2EVMMessage memory inbound = Client.Any2EVMMessage({
            messageId: bytes32("x"),
            sourceChainSelector: CCIPHelper.OP_SEL,
            sender: abi.encode(ccipSucker),
            data: abi.encode(uint8(0), abi.encode(_root(1))),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
        vm.expectPartialRevert(JBSucker.JBSucker_NotPeer.selector);
        JBCCIPSucker(payable(ccipSucker)).ccipReceive(inbound);
    }

    /// @notice `ccipReceive` from the router but with a spoofed source sender (not the peer) is rejected.
    function test_gate_ccip_spoofedSenderRejected() public {
        Client.Any2EVMMessage memory inbound = Client.Any2EVMMessage({
            messageId: bytes32("x"),
            sourceChainSelector: CCIPHelper.OP_SEL,
            sender: abi.encode(makeAddr("notThePeer")),
            data: abi.encode(uint8(0), abi.encode(_root(1))),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
        vm.prank(address(ccipRouter));
        vm.expectPartialRevert(JBSucker.JBSucker_NotPeer.selector);
        JBCCIPSucker(payable(ccipSucker)).ccipReceive(inbound);
    }

    /// @notice `ccipReceive` from the router with the WRONG source chain selector is rejected.
    function test_gate_ccip_wrongSourceChainRejected() public {
        Client.Any2EVMMessage memory inbound = Client.Any2EVMMessage({
            messageId: bytes32("x"),
            sourceChainSelector: CCIPHelper.ARB_SEL, // not the configured OP selector
            sender: abi.encode(ccipSucker),
            data: abi.encode(uint8(0), abi.encode(_root(1))),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
        vm.prank(address(ccipRouter));
        vm.expectPartialRevert(JBSucker.JBSucker_NotPeer.selector);
        JBCCIPSucker(payable(ccipSucker)).ccipReceive(inbound);
    }
}
