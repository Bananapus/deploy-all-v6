// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Regression for BR: _dumpAddresses must emit the singleton implementation address for
/// every standard sucker deployer (JBOptimismSucker / JBBaseSucker / JBArbitrumSucker) AND the
/// per-route CCIP and SwapCCIP deployers + their singletons (with `__<remoteChainSuffix>` naming).
contract PostDeploySuckerArtifactGapTest is Test {
    function test_suckerSingletonsAndCcipRouteDeployersAreEmitted() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory dumpSource = _section({
            haystack: deploySource, startNeedle: "function _dumpAddresses()", endNeedle: "function _serializeIfSet"
        });

        // Deployment paths still exist (sanity).
        assertTrue(_contains(deploySource, 'artifactName: "JBOptimismSucker"'), "deploys Optimism sucker singleton");
        assertTrue(_contains(deploySource, 'artifactName: "JBBaseSucker"'), "deploys Base sucker singleton");
        assertTrue(_contains(deploySource, 'artifactName: "JBArbitrumSucker"'), "deploys Arbitrum sucker singleton");
        assertTrue(_contains(deploySource, 'artifactName: "JBCCIPSucker"'), "deploys CCIP sucker singleton");
        assertTrue(_contains(deploySource, 'artifactName: "JBSwapCCIPSucker"'), "deploys swap CCIP sucker singleton");
        assertTrue(
            _contains(deploySource, "configureSingleton(singleton)"),
            "deployed sucker singletons are bound to clone deployers"
        );
        assertTrue(
            _contains(deploySource, 'artifactName: "JBCCIPSuckerDeployer"'), "deploys route-specific CCIP deployers"
        );
        assertTrue(
            _contains(deploySource, 'artifactName: "JBSwapCCIPSuckerDeployer"'),
            "deploys route-specific swap CCIP deployers"
        );

        // _dumpAddresses emits the standard deployers AND their singletons.
        assertTrue(_contains(dumpSource, 'name: "JBOptimismSuckerDeployer"'), "standard Optimism deployer is emitted");
        assertTrue(_contains(dumpSource, 'name: "JBBaseSuckerDeployer"'), "standard Base deployer is emitted");
        assertTrue(_contains(dumpSource, 'name: "JBArbitrumSuckerDeployer"'), "standard Arbitrum deployer is emitted");
        assertTrue(_contains(dumpSource, 'name: "JBOptimismSucker"'), "Optimism singleton is now emitted");
        assertTrue(_contains(dumpSource, 'name: "JBBaseSucker"'), "Base singleton is now emitted");
        assertTrue(_contains(dumpSource, 'name: "JBArbitrumSucker"'), "Arbitrum singleton is now emitted");

        // _dumpAddresses emits per-route CCIP and SwapCCIP via _serializeCCIPRouteDeployers.
        assertTrue(
            _contains(dumpSource, "_serializeCCIPRouteDeployers"),
            "per-route deployer enumeration is invoked from the dump"
        );
        assertTrue(
            _contains(deploySource, "function _serializeCCIPRouteDeployers"),
            "_serializeCCIPRouteDeployers helper is defined"
        );
        assertTrue(
            _contains(deploySource, "function _serializeSingletonFromDeployer"),
            "_serializeSingletonFromDeployer helper is defined"
        );

        // The per-route helper emits both deployer and singleton names with `__<suffix>` shape.
        assertTrue(
            _contains(deploySource, '"JBSwapCCIPSuckerDeployer" : "JBCCIPSuckerDeployer"'),
            "per-route helper branches on Swap vs standard CCIP deployer"
        );
        assertTrue(
            _contains(deploySource, '"JBSwapCCIPSucker" : "JBCCIPSucker"'),
            "per-route helper branches on Swap vs standard CCIP singleton"
        );
        assertTrue(
            _contains(deploySource, "_chainIdToRouteSuffix(remoteId)"),
            "per-route helper derives suffix from ccipRemoteChainId"
        );
        assertTrue(
            _contains(deploySource, 'if (chainId == 10) return "OP";'), "chain suffix table covers Optimism mainnet"
        );
        assertTrue(
            _contains(deploySource, 'if (chainId == 8453) return "BASE";'), "chain suffix table covers Base mainnet"
        );
        assertTrue(
            _contains(deploySource, 'if (chainId == 42_161) return "ARB";'),
            "chain suffix table covers Arbitrum mainnet"
        );

        // artifacts.mjs only emits targets present in addresses-<chainId>.json (no change).
        string memory artifactsSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");
        assertTrue(
            _contains(artifactsSource, "const targets = Object.entries(addresses)"),
            "artifact emission only targets names present in addresses-<chainId>.json"
        );

        // DEPLOY.md no longer claims per-route CCIP suckers are missing from the dump.
        string memory docs = vm.readFile("DEPLOY.md");
        assertFalse(
            _contains(docs, "not yet emitted to `addresses-<chainId>.json`"),
            "docs no longer note missing sucker route emissions"
        );
        assertTrue(
            _contains(docs, "Per-route CCIP / SwapCCIP suckers"), "docs describe the new per-route emission scheme"
        );
        assertTrue(_contains(docs, "JBCCIPSucker__<RouteSuffix>"), "docs document the per-route naming suffix");
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
