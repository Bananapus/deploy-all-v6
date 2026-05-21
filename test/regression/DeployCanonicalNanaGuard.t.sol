// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

contract DeployCanonicalNanaGuardTest is Test {
    function test_deployNanaReplayGuardRequiresExactCanonicalShape() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory deployNanaSource = _section({
            haystack: deploySource, startNeedle: "function _deployNanaRevnet()", endNeedle: "function _deployBanny()"
        });
        string memory guardSource = _section({
            haystack: deploySource,
            startNeedle: "function _isCanonicalNanaRevnetProject(",
            endNeedle: "function _encodedConfigurationHashOf("
        });

        assertTrue(
            _contains(deployNanaSource, "_encodedConfigurationHashOf"),
            "NANA replay path computes the expected config hash"
        );
        assertTrue(
            _contains(deployNanaSource, "_isCanonicalNanaRevnetProject"),
            "NANA replay path uses the strict canonical guard"
        );
        assertFalse(
            _contains(deployNanaSource, '_isCanonicalRevnetProject({projectId: feeProjectId, expectedSymbol: "NANA"})'),
            "NANA replay path must not use the generic nonzero-hash guard"
        );

        assertTrue(_contains(guardSource, "FEE_REVNET_ID()"), "guard checks fee-revnet dependency");
        assertTrue(
            _contains(guardSource, "hashedEncodedConfigurationOf(projectId) != expectedConfigurationHash"),
            "guard checks exact revnet hash"
        );
        assertTrue(_contains(guardSource, "isOperatorOf"), "guard checks expected operator permissions");
        assertTrue(_contains(guardSource, "uriOf(projectId)"), "guard checks project URI");
        assertTrue(_contains(guardSource, "_reservedSplitIsCanonical"), "guard checks reserved split routing");
        assertTrue(_contains(guardSource, "_nativeTerminalConfigIsCanonical"), "guard checks terminal setup");
    }

    function _section(
        string memory haystack,
        string memory startNeedle,
        string memory endNeedle
    )
        internal
        pure
        returns (string memory)
    {
        bytes memory h = bytes(haystack);
        uint256 start = _indexOf(haystack, startNeedle);
        uint256 end = _indexOfFrom(haystack, endNeedle, start);
        require(end >= start, "invalid section");

        bytes memory out = new bytes(end - start);
        for (uint256 i; i < out.length; i++) {
            out[i] = h[start + i];
        }
        return string(out);
    }

    function _indexOf(string memory haystack, string memory needle) internal pure returns (uint256) {
        return _indexOfFrom(haystack, needle, 0);
    }

    function _indexOfFrom(string memory haystack, string memory needle, uint256 start) internal pure returns (uint256) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        require(n.length != 0, "empty needle");
        require(n.length <= h.length, "needle too long");

        for (uint256 i = start; i <= h.length - n.length; i++) {
            bool matched = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) return i;
        }

        revert("needle not found");
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
