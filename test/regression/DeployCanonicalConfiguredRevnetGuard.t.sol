// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

contract DeployCanonicalConfiguredRevnetGuardTest is Test {
    function test_configuredRevnetReplayGuardsRequireExactCanonicalShape() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");

        string memory defifaSource = _section({
            haystack: deploySource, startNeedle: "function _deployDefifaRevnet()", endNeedle: "function _deployArt()"
        });
        string memory artSource = _section({
            haystack: deploySource, startNeedle: "function _deployArt()", endNeedle: "function _deployMarkee()"
        });
        string memory markeeSource = _section({
            haystack: deploySource,
            startNeedle: "function _deployMarkee()",
            endNeedle: "function _deployProjectHandles()"
        });
        string memory bannySource = _section({
            haystack: deploySource, startNeedle: "function _deployBanny()", endNeedle: "function _registerBannyDrop1()"
        });

        _assertStrictConfiguredRevnetGuard(defifaSource, "_DEFIFA_REV_PROJECT_ID", "DEFIFA");
        _assertStrictConfiguredRevnetGuard(artSource, "_ART_PROJECT_ID", "ART");
        _assertStrictConfiguredRevnetGuard(markeeSource, "_MARKEE_PROJECT_ID", "MARKEE");

        assertTrue(_contains(bannySource, "_encodedConfigurationHashOf"), "Banny computes expected config hash");
        assertTrue(_contains(bannySource, "_isCanonicalBannyProject"), "Banny uses strict canonical guard");

        string memory genericGuard = _section({
            haystack: deploySource,
            startNeedle: "function _isCanonicalRevnetProject(",
            endNeedle: "function _isCanonicalNanaRevnetProject("
        });
        assertTrue(
            _contains(genericGuard, "hashedEncodedConfigurationOf(projectId) != expectedConfigurationHash"),
            "generic guard checks exact config hash"
        );
        assertTrue(_contains(genericGuard, "isOperatorOf"), "generic guard checks expected operator");
        assertTrue(_contains(genericGuard, "uriOf(projectId)"), "generic guard checks project URI");
        assertTrue(_contains(genericGuard, "_reservedSplitIsCanonical"), "generic guard checks reserved split");
        assertTrue(_contains(genericGuard, "_nativeTerminalConfigIsCanonical"), "generic guard checks terminal setup");

        string memory bannyGuard = _section({
            haystack: deploySource,
            startNeedle: "function _isCanonicalBannyProject(",
            endNeedle: "function _isCanonicalRevnetProject("
        });
        assertTrue(_contains(bannyGuard, "_isCanonicalRevnetProjectShape"), "Banny checks exact revnet shape");
        assertTrue(_contains(bannyGuard, "_BAN_OPS_OPERATOR"), "Banny accepts finalized ops operator");
        assertTrue(
            _contains(bannySource, "partialResumeOperator: safeAddress()"), "Banny passes the deployment safe operator"
        );
        assertTrue(_contains(bannyGuard, "partialResumeOperator"), "Banny accepts partial-resume safe operator");
        assertTrue(_contains(bannyGuard, "BANNY"), "Banny checks tiered hook identity");
    }

    function _assertStrictConfiguredRevnetGuard(
        string memory deployFunctionSource,
        string memory projectIdName,
        string memory expectedSymbol
    )
        internal
        pure
    {
        assertTrue(_contains(deployFunctionSource, "_encodedConfigurationHashOf"), "expected config hash is computed");
        assertTrue(_contains(deployFunctionSource, "_isCanonicalRevnetProject"), "strict guard is used");
        assertTrue(
            _contains(deployFunctionSource, string.concat("projectId: ", projectIdName)),
            "guard checks the intended project"
        );
        assertTrue(
            _contains(deployFunctionSource, string.concat('expectedSymbol: "', expectedSymbol, '"')),
            "guard checks token symbol"
        );
        assertTrue(
            _contains(deployFunctionSource, "expectedConfigurationHash: expectedConfigurationHash"),
            "guard passes exact config hash"
        );
        assertTrue(_contains(deployFunctionSource, "expectedOperator: operator"), "guard passes expected operator");
        assertTrue(_contains(deployFunctionSource, 'expectedUri: ""'), "guard passes expected URI");
        assertTrue(
            _contains(deployFunctionSource, "expectedReservedSplitBeneficiary: payable(operator)"),
            "guard passes expected reserved split beneficiary"
        );
        assertTrue(_contains(deployFunctionSource, "expectRouterTerminal: hasRouter"), "guard checks router terminal");
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
