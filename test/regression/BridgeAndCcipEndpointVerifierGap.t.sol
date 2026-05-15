// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

/// @notice Coverage for bridge/CCIP endpoint identity on sucker deployers. Each test
/// supplies a deployer whose endpoint immutable is one step off the canonical chain manifest
/// and asserts the verifier rejects.
contract BridgeAndCcipEndpointVerifierGapTest is Test {
    // Canonical mainnet values (mirror CCIPHelper / ARBAddresses / OP messenger constants).
    address internal constant CANONICAL_OP_L1_MESSENGER = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1;
    address internal constant CANONICAL_OP_L1_BRIDGE = 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1;
    address internal constant CANONICAL_BASE_L1_MESSENGER = 0x866E82a600A1414e583f7F13623F1aC5d58b0Afa;
    address internal constant CANONICAL_BASE_L1_BRIDGE = 0x3154Cf16ccdb4C6d922629664174b904d80F2C35;
    address internal constant CANONICAL_ARB_L1_INBOX = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;
    address internal constant CANONICAL_ARB_L1_GATEWAY = 0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef;
    address internal constant CANONICAL_ETH_CCIP_ROUTER = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
    uint64 internal constant CANONICAL_OP_SELECTOR = 3_734_403_246_176_062_136;
    uint256 internal constant CANONICAL_OP_CHAIN_ID = 10;

    function test_bridgeVerifierRejectsWrongOpMessengerOnMainnet() public {
        vm.chainId(1);

        address wrongMessenger = makeAddr("wrong op messenger");
        assertTrue(wrongMessenger != CANONICAL_OP_L1_MESSENGER, "test must use a noncanonical messenger");

        address deployer = address(new MockOpDeployer(wrongMessenger, CANONICAL_OP_L1_BRIDGE));

        VerifyBridgeEndpointHarness harness = new VerifyBridgeEndpointHarness();
        harness.setOpSuckerDeployer(deployer);

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "Optimism sucker deployer opMessenger == canonical"
            )
        );
        harness.verifyBridgeAndCcipEndpoints();
    }

    function test_bridgeVerifierRejectsWrongBaseStandardBridgeOnMainnet() public {
        vm.chainId(1);

        address wrongBridge = makeAddr("wrong base bridge");
        assertTrue(wrongBridge != CANONICAL_BASE_L1_BRIDGE, "test must use a noncanonical bridge");

        VerifyBridgeEndpointHarness harness = new VerifyBridgeEndpointHarness();
        _wireCanonicalNonFocused(harness);
        // Override Base with a bad deployer so the Base branch is the one that fails.
        harness.setBaseSuckerDeployer(address(new MockOpDeployer(CANONICAL_BASE_L1_MESSENGER, wrongBridge)));

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "Base sucker deployer opBridge == canonical"
            )
        );
        harness.verifyBridgeAndCcipEndpoints();
    }

    function test_bridgeVerifierRejectsWrongArbitrumGatewayRouterOnMainnet() public {
        vm.chainId(1);

        address wrongGateway = makeAddr("wrong arb gateway");
        assertTrue(wrongGateway != CANONICAL_ARB_L1_GATEWAY, "test must use a noncanonical gateway");

        VerifyBridgeEndpointHarness harness = new VerifyBridgeEndpointHarness();
        _wireCanonicalNonFocused(harness);
        harness.setArbSuckerDeployer(address(new MockArbDeployer(CANONICAL_ARB_L1_INBOX, wrongGateway)));

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "Arbitrum sucker deployer arbGatewayRouter == canonical"
            )
        );
        harness.verifyBridgeAndCcipEndpoints();
    }

    function test_ccipVerifierRejectsWrongRouterOnMainnet() public {
        vm.chainId(1);

        address wrongRouter = makeAddr("wrong ccip router");
        assertTrue(wrongRouter != CANONICAL_ETH_CCIP_ROUTER, "test must use a noncanonical router");

        address deployer = address(new MockCcipDeployer(wrongRouter, CANONICAL_OP_CHAIN_ID, CANONICAL_OP_SELECTOR));

        VerifyBridgeEndpointHarness harness = new VerifyBridgeEndpointHarness();
        _wireCanonicalNonFocused(harness);
        harness.setCcipDeployersCsv(string.concat(vm.toString(CANONICAL_OP_CHAIN_ID), ":", vm.toString(deployer)));

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                string.concat(
                    "CCIP sucker deployer (remote=", vm.toString(CANONICAL_OP_CHAIN_ID), ") ccipRouter == canonical"
                )
            )
        );
        harness.verifyBridgeAndCcipEndpoints();
    }

    function test_ccipVerifierRejectsWrongRemoteSelectorOnMainnet() public {
        vm.chainId(1);

        uint64 wrongSelector = CANONICAL_OP_SELECTOR + 1;

        address deployer =
            address(new MockCcipDeployer(CANONICAL_ETH_CCIP_ROUTER, CANONICAL_OP_CHAIN_ID, wrongSelector));

        VerifyBridgeEndpointHarness harness = new VerifyBridgeEndpointHarness();
        _wireCanonicalNonFocused(harness);
        harness.setCcipDeployersCsv(string.concat(vm.toString(CANONICAL_OP_CHAIN_ID), ":", vm.toString(deployer)));

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                string.concat(
                    "CCIP sucker deployer (remote=",
                    vm.toString(CANONICAL_OP_CHAIN_ID),
                    ") ccipRemoteChainSelector == canonical"
                )
            )
        );
        harness.verifyBridgeAndCcipEndpoints();
    }

    /// Wire canonical-OK deployers for OP, Base, Arb, and one CCIP route so the only failing
    /// branch in each focused test is the one the test is exercising.
    function _wireCanonicalNonFocused(VerifyBridgeEndpointHarness harness) internal {
        harness.setOpSuckerDeployer(address(new MockOpDeployer(CANONICAL_OP_L1_MESSENGER, CANONICAL_OP_L1_BRIDGE)));
        harness.setBaseSuckerDeployer(
            address(new MockOpDeployer(CANONICAL_BASE_L1_MESSENGER, CANONICAL_BASE_L1_BRIDGE))
        );
        harness.setArbSuckerDeployer(address(new MockArbDeployer(CANONICAL_ARB_L1_INBOX, CANONICAL_ARB_L1_GATEWAY)));
        // Default CCIP CSV is empty — overridden by tests that exercise the CCIP branch.
    }

    function test_bridgeVerifierFailsClosedWhenOpDeployerUnsetOnMainnet() public {
        vm.chainId(1);
        VerifyBridgeEndpointHarness harness = new VerifyBridgeEndpointHarness();
        // No deployer addresses set — production fail-closed.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "VERIFY_OP_SUCKER_DEPLOYER MUST be set on production for Optimism endpoint identity"
            )
        );
        harness.verifyBridgeAndCcipEndpoints();
    }
}

contract VerifyBridgeEndpointHarness is Verify {
    function setOpSuckerDeployer(address d) external {
        opSuckerDeployer = d;
    }

    function setBaseSuckerDeployer(address d) external {
        baseSuckerDeployer = d;
    }

    function setArbSuckerDeployer(address d) external {
        arbSuckerDeployer = d;
    }

    function setCcipDeployersCsv(string calldata csv) external {
        ccipSuckerDeployersCsv = csv;
    }

    function verifyBridgeAndCcipEndpoints() external {
        _verifyBridgeAndCcipEndpoints();
    }
}

contract MockOpDeployer {
    address internal immutable _opMessenger;
    address internal immutable _opBridge;

    constructor(address opMessenger_, address opBridge_) {
        _opMessenger = opMessenger_;
        _opBridge = opBridge_;
    }

    function opMessenger() external view returns (address) {
        return _opMessenger;
    }

    function opBridge() external view returns (address) {
        return _opBridge;
    }
}

contract MockArbDeployer {
    address internal immutable _arbInbox;
    address internal immutable _arbGatewayRouter;

    constructor(address arbInbox_, address arbGatewayRouter_) {
        _arbInbox = arbInbox_;
        _arbGatewayRouter = arbGatewayRouter_;
    }

    function arbInbox() external view returns (address) {
        return _arbInbox;
    }

    function arbGatewayRouter() external view returns (address) {
        return _arbGatewayRouter;
    }
}

contract MockCcipDeployer {
    address internal immutable _ccipRouter;
    uint256 internal immutable _ccipRemoteChainId;
    uint64 internal immutable _ccipRemoteChainSelector;

    constructor(address ccipRouter_, uint256 ccipRemoteChainId_, uint64 ccipRemoteChainSelector_) {
        _ccipRouter = ccipRouter_;
        _ccipRemoteChainId = ccipRemoteChainId_;
        _ccipRemoteChainSelector = ccipRemoteChainSelector_;
    }

    function ccipRouter() external view returns (address) {
        return _ccipRouter;
    }

    function ccipRemoteChainId() external view returns (uint256) {
        return _ccipRemoteChainId;
    }

    function ccipRemoteChainSelector() external view returns (uint64) {
        return _ccipRemoteChainSelector;
    }
}
