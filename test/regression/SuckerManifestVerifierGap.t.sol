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

        // BC fix: Category 19 now asserts the local sucker has code. The mock pair sets local to
        // address(0), so the verifier rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "NANA(1) sucker pair 0 local sucker has code"
            )
        );
        harness.verifySuckerManifest();
    }

    function test_suckerManifestVerifierAcceptsPairWithDisabledNativeTokenMapping() public {
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

        // Category 19 never checks the local sucker's token mapping, so the pair passes even
        // though the canonical native-token bridge path is disabled.
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
