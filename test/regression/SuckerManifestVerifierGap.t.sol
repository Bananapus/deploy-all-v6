// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBRemoteToken} from "@bananapus/suckers-v6/src/structs/JBRemoteToken.sol";
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {JBSuckersPair} from "@bananapus/suckers-v6/src/structs/JBSuckersPair.sol";

contract SuckerManifestVerifierGapTest is Test {
    function test_suckerManifestVerifierRejectsMalformedPairWithNoLocalSucker() public {
        MockSuckerRegistry registry = new MockSuckerRegistry();
        registry.setPairs(
            1,
            _singlePair({
                local: address(0), remote: bytes32(uint256(uint160(makeAddr("wrong remote sucker")))), remoteChainId: 0
            })
        );

        VerifySuckerManifestHarness harness = new VerifySuckerManifestHarness();
        harness.setSuckerRegistry(address(registry));

        vm.setEnv("VERIFY_SUCKER_PAIRS_1", "1");

        // Coverage: Category 19 now asserts the local sucker has code. The mock pair sets local to
        // address(0), so the verifier rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "NANA(1) sucker pair 0 local sucker has code"
            )
        );
        harness.verifySuckerManifest();
    }

    function test_suckerManifestVerifierRejectsPairWithDisabledNativeTokenMapping() public {
        MockSucker local = new MockSucker({
            peer_: bytes32(uint256(uint160(makeAddr("remote sucker")))),
            peerChainId_: 10,
            remoteToken_: JBRemoteToken({
                enabled: false,
                emergencyHatch: false,
                minGas: 0,
                addr: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
            })
        });

        MockSuckerRegistry registry = new MockSuckerRegistry();
        registry.setPairs(1, _singlePair({local: address(local), remote: local.peer(), remoteChainId: 10}));

        VerifySuckerManifestHarness harness = new VerifySuckerManifestHarness();
        harness.setSuckerRegistry(address(registry));

        vm.setEnv("VERIFY_SUCKER_PAIRS_1", "1");

        JBRemoteToken memory remoteToken = local.remoteTokenFor(JBConstants.NATIVE_TOKEN);
        assertFalse(remoteToken.enabled, "native-token mapping is disabled");

        // Coverage: Category 19 now reads remoteTokenFor(NATIVE_TOKEN).enabled and
        // rejects when the mapping is disabled.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "NANA(1) sucker pair 0 native-token remote mapping is enabled"
            )
        );
        harness.verifySuckerManifest();
    }

    /// @dev Coverage: when the operator declares the exact per-pair manifest via
    /// `VERIFY_SUCKER_PAIR_<projectId>_<idx>`, the verifier asserts each field matches. A wrong
    /// peer bytes32 must trip the new check. Uses project ID 2 to keep the env var key
    /// disjoint from the test below — Foundry runs tests in this contract concurrently and
    /// `vm.setEnv` is process-wide.
    function test_suckerManifestVerifierRejectsWrongPeerInExactManifest() public {
        bytes32 actualPeer = bytes32(uint256(uint160(makeAddr("actual remote sucker"))));
        bytes32 expectedPeerInManifest = bytes32(uint256(uint160(makeAddr("expected canonical remote"))));
        assertTrue(actualPeer != expectedPeerInManifest, "test must use a peer different from the manifest");

        MockSucker local = new MockSucker({
            peer_: actualPeer,
            peerChainId_: 10,
            remoteToken_: JBRemoteToken({
                enabled: true,
                emergencyHatch: false,
                minGas: 0,
                addr: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
            })
        });

        MockSuckerRegistry registry = new MockSuckerRegistry();
        registry.setPairs(2, _singlePair({local: address(local), remote: actualPeer, remoteChainId: 10}));

        VerifySuckerManifestHarness harness = new VerifySuckerManifestHarness();
        harness.setSuckerRegistry(address(registry));

        // Sibling tests in this contract also set `VERIFY_SUCKER_PAIRS_1`. The verifier loops
        // through all four canonical projects, so leftover env from a sibling would trip the
        // count check for project 1 first. Clear it explicitly to keep this test focused on
        // project 2 only.
        vm.setEnv("VERIFY_SUCKER_PAIRS_1", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_3", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_4", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_2", "1");
        // Manifest format: <peer>:<remoteChainId>:<remoteNativeToken>:<emergencyHatch>
        vm.setEnv(
            "VERIFY_SUCKER_PAIR_2_0",
            string.concat(
                vm.toString(expectedPeerInManifest),
                ":10:",
                vm.toString(bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))),
                ":0"
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "CPN(2) sucker pair 0 peer() == expected"
            )
        );
        harness.verifySuckerManifest();
    }

    /// @dev Coverage: a wrong remote-chain-id in the manifest must trip the registry-
    /// side remoteChainId check first. Uses project ID 3 to avoid env collision with sibling tests.
    function test_suckerManifestVerifierRejectsWrongRemoteChainIdInExactManifest() public {
        bytes32 peer = bytes32(uint256(uint160(makeAddr("remote sucker"))));

        MockSucker local = new MockSucker({
            peer_: peer,
            peerChainId_: 10, // local says 10
            remoteToken_: JBRemoteToken({
                enabled: true,
                emergencyHatch: false,
                minGas: 0,
                addr: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
            })
        });

        MockSuckerRegistry registry = new MockSuckerRegistry();
        registry.setPairs(3, _singlePair({local: address(local), remote: peer, remoteChainId: 10}));

        VerifySuckerManifestHarness harness = new VerifySuckerManifestHarness();
        harness.setSuckerRegistry(address(registry));

        vm.setEnv("VERIFY_SUCKER_PAIRS_1", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_2", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_4", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_3", "1");
        // Operator-declared remoteChainId = 8453 (Base) — disagrees with the pair's actual 10 (OP).
        vm.setEnv(
            "VERIFY_SUCKER_PAIR_3_0",
            string.concat(
                vm.toString(peer), ":8453:", vm.toString(bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))), ":0"
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "REV(3) sucker pair 0 registry-side remoteChainId == expected"
            )
        );
        harness.verifySuckerManifest();
    }

    function _singlePair(
        address local,
        bytes32 remote,
        uint256 remoteChainId
    )
        internal
        pure
        returns (JBSuckersPair[] memory pairs)
    {
        pairs = new JBSuckersPair[](1);
        pairs[0] = JBSuckersPair({local: local, remote: remote, remoteChainId: remoteChainId});
    }
}

contract VerifySuckerManifestHarness is Verify {
    function setSuckerRegistry(address suckerRegistry_) external {
        suckerRegistry = JBSuckerRegistry(suckerRegistry_);
    }

    function verifySuckerManifest() external {
        _verifySuckerManifest();
    }
}

contract MockSuckerRegistry {
    mapping(uint256 projectId => JBSuckersPair[] pairs) internal _pairsOf;

    function setPairs(uint256 projectId, JBSuckersPair[] memory pairs) external {
        delete _pairsOf[projectId];
        for (uint256 i; i < pairs.length; i++) {
            _pairsOf[projectId].push(pairs[i]);
        }
    }

    function suckerPairsOf(uint256 projectId) external view returns (JBSuckersPair[] memory) {
        return _pairsOf[projectId];
    }
}

contract MockSucker {
    bytes32 internal immutable _peer;
    uint256 internal immutable _peerChainId;
    JBRemoteToken internal _remoteToken;

    constructor(bytes32 peer_, uint256 peerChainId_, JBRemoteToken memory remoteToken_) {
        _peer = peer_;
        _peerChainId = peerChainId_;
        _remoteToken = remoteToken_;
    }

    function peer() external view returns (bytes32) {
        return _peer;
    }

    function peerChainId() external view returns (uint256) {
        return _peerChainId;
    }

    function remoteTokenFor(address) external view returns (JBRemoteToken memory) {
        return _remoteToken;
    }
}
