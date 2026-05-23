// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Regression: deployment artifacts must not compile from installed package
/// sources that predate the freeze-critical post-audit fixes.
contract PostDeployFreezeCriticalPackagePreflightTest is Test {
    function test_buildArtifactsFailsClosedOnStaleFreezeCriticalPackageSources() public view {
        string memory buildSource = vm.readFile("script/build-artifacts.sh");

        assertTrue(
            _contains(buildSource, "Freeze-critical source preflight"),
            "build script has freeze-critical source preflight"
        );
        assertTrue(
            _contains(buildSource, "require_freeze_critical_package_sources"),
            "build script runs freeze-critical package checks"
        );
        assertTrue(
            _contains(buildSource, "freeze-critical package source preflight failed"),
            "build script fails closed when a required source marker is missing"
        );

        assertTrue(
            _contains(buildSource, "safeTransfer({to: context.holder, value: unsoldProjectTokenCount})"),
            "buyback package must include unsold-remint return fix"
        );
        assertTrue(
            _contains(buildSource, "if (cashOutTaxRate == 0) return effectiveReclaim"),
            "univ4 router package must include zero-tax cash-out preview fix"
        );
        assertTrue(_contains(buildSource, "nana-omnichain-deployers-v6"), "omnichain deployer package is covered");
        assertTrue(_contains(buildSource, "croptop-core-v6"), "Croptop package is covered");
        assertTrue(
            _contains(buildSource, "_requireExplicitSuckerPeerPermissionFrom"),
            "explicit sucker peer permission wrappers are covered"
        );
        assertTrue(
            _contains(
                buildSource, "allOperatorPermissions = new uint256[](10 + customOperatorPermissionIndexes.length)"
            ),
            "revnet package must include 10-permission operator envelope"
        );
        assertTrue(
            _contains(buildSource, "allOperatorPermissions[4] = JBPermissionIds.SET_SUCKER_PEER"),
            "revnet package must grant SET_SUCKER_PEER"
        );
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0) return true;
        if (n.length > h.length) return false;

        for (uint256 i; i <= h.length - n.length; i++) {
            bool matched = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) return true;
        }

        return false;
    }
}
