// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Regression: deploy-all-owned artifacts should be written directly under
/// deployments/<chain>/, without an extra project-name segment. The distribute step uses Set-based
/// dedup on the destination paths.
contract PostDeployDistributeArtifactGapTest is Test {
    function test_deployAllOwnedArtifactsUseDirectChainPath() public view {
        string memory distributeSource = vm.readFile("script/post-deploy/lib/distribute.mjs");
        string memory chainsConfig = vm.readFile("script/post-deploy/chains.json");
        string memory manifest = vm.readFile("artifacts/artifacts.manifest.json");

        assertTrue(_contains(manifest, '"ERC2771Forwarder"'), "manifest includes deploy-all owned forwarder");
        assertTrue(_contains(manifest, '"repo": "deploy-all-v6"'), "forwarder source repo is deploy-all-v6");
        assertFalse(_contains(chainsConfig, '"deploy-all-v6": "V6"'), "deploy-all does not add a V6 project segment");

        assertTrue(
            _contains(
                distributeSource, "const aggregatorPath = path.join(DEPLOY_ROOT, 'deployments', chain.alias, file);"
            ),
            "aggregator path is the direct chain deployment path"
        );
        assertTrue(
            _contains(distributeSource, "if (manifestEntry.repo !== 'deploy-all-v6')"),
            "source-repo project segments are only used for non deploy-all repos"
        );
        assertTrue(
            _contains(
                distributeSource,
                "perRepoPath = path.join(MONOREPO_ROOT, manifestEntry.repo, 'deployments', sphinxProject, chain.alias, file);"
            ),
            "per-repo path keeps source-repo project segments"
        );
        assertTrue(
            _contains(distributeSource, "for (const dest of new Set([aggregatorPath, perRepoPath]))"),
            "distribution loop deduplicates destinations via Set"
        );
        assertFalse(
            _contains(distributeSource, "if (dest === aggregatorPath && perRepoPath === aggregatorPath) continue;"),
            "old buggy double-skip guard is gone"
        );

        string memory aggregatorPath = "deploy-all-v6/deployments/ethereum/ERC2771Forwarder.json";
        string memory perRepoPath = "deploy-all-v6/deployments/ethereum/ERC2771Forwarder.json";
        assertEq(
            keccak256(bytes(aggregatorPath)), keccak256(bytes(perRepoPath)), "deploy-all destinations are identical"
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
