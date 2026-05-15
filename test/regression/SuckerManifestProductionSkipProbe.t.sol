// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {JBSuckersPair} from "@bananapus/suckers-v6/src/structs/JBSuckersPair.sol";

contract SuckerManifestProductionSkipProbeTest is Test {
    /// @dev Coverage: on production chains, the sucker manifest verifier must fail
    /// closed when ALL `VERIFY_SUCKER_PAIRS_{1..4}` env vars are unset — otherwise a deployment
    /// can ship without ever exercising the per-pair manifest gate. Operators declare zero-pair
    /// projects by setting the env var to "0".
    function test_suckerManifestFailsClosedOnProductionWhenPairCountEnvsUnset() public {
        vm.chainId(1);

        vm.setEnv("VERIFY_SUCKER_PAIRS_1", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_2", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_3", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_4", "");

        MockSuckerManifestRegistryProbe registry = new MockSuckerManifestRegistryProbe();
        // Set an obviously-malformed pair so a regression that silently skips the manifest
        // wouldn't catch it via the existing nonzero/liveness predicates either.
        registry.setPairs(
            1,
            _singlePair({
                local: address(0), remote: bytes32(uint256(uint160(makeAddr("wrong remote")))), remoteChainId: 0
            })
        );

        VerifySuckerManifestProductionSkipHarness harness = new VerifySuckerManifestProductionSkipHarness();
        harness.setSuckerRegistry(address(registry));

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "VERIFY_SUCKER_PAIRS_{1..4} MUST be set on production (use \"0\" for projects with no suckers)"
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

contract VerifySuckerManifestProductionSkipHarness is Verify {
    function setSuckerRegistry(address registry) external {
        suckerRegistry = JBSuckerRegistry(registry);
    }

    function verifySuckerManifest() external {
        _verifySuckerManifest();
    }
}

contract MockSuckerManifestRegistryProbe {
    mapping(uint256 projectId => JBSuckersPair[] pairs) internal _pairs;

    function setPairs(uint256 projectId, JBSuckersPair[] memory pairs) external {
        delete _pairs[projectId];
        for (uint256 i; i < pairs.length; i++) {
            _pairs[projectId].push(pairs[i]);
        }
    }

    function suckerPairsOf(uint256 projectId) external view returns (JBSuckersPair[] memory) {
        return _pairs[projectId];
    }

    function isSuckerOf(uint256, address) external pure returns (bool) {
        return true;
    }

    function remoteTokenFor(address) external pure returns (bool, bool, uint32, bytes32) {
        return (true, false, 0, bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN))));
    }
}
