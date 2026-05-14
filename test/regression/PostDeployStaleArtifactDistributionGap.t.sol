// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Regression for BV: artifact emission must prune its per-chain output directory before
/// writing the current run's targets, distribution must derive its target list from the current
/// addresses-<chainId>.json dump (not readdirSync on the cache), and post-deploy.sh must skip
/// distribution when artifact emission failed.
contract PostDeployStaleArtifactDistributionGapTest is Test {
    function test_distributionDerivesFromCurrentAddressDumpAndCachePrunedBeforeEmit() public view {
        string memory artifactSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");
        string memory distributeSource = vm.readFile("script/post-deploy/lib/distribute.mjs");
        string memory postDeploySource = vm.readFile("script/post-deploy.sh");

        // artifact emission prunes its per-chain output directory before writing.
        assertTrue(
            _contains(artifactSource, "path.join(CACHE_DIR, `artifacts-${CHAIN_ID}`)"),
            "artifact emission writes into a persistent per-chain cache directory"
        );
        assertTrue(
            _contains(artifactSource, "fs.rmSync(outDir, { recursive: true, force: true });"),
            "artifact emission prunes the cache directory before writing"
        );
        assertTrue(
            _contains(artifactSource, "fs.mkdirSync(outDir, { recursive: true });"),
            "artifact emission recreates the cache directory after pruning"
        );

        // distribution derives its target list from the address dump, not from readdirSync.
        assertTrue(
            _contains(distributeSource, "addresses-${CHAIN_ID}.json"),
            "distribution reads the current address dump for targets"
        );
        assertFalse(
            _contains(distributeSource, "const files = fs.readdirSync(inDir).filter"),
            "distribution does not enumerate the cache directory"
        );
        assertTrue(
            _contains(distributeSource, "Object.entries(addresses)"),
            "distribution iterates targets from the address dump"
        );
        assertTrue(
            _contains(distributeSource, "artifact.address"),
            "distribution validates artifact.address matches the current target"
        );
        assertTrue(
            _contains(distributeSource, "artifact.chainId"),
            "distribution validates artifact.chainId matches the current chain"
        );

        // post-deploy.sh skips distribution when artifact emission failed.
        assertTrue(
            _contains(postDeploySource, "artifact_failed=0"), "post-deploy declares per-chain artifact-failed flag"
        );
        assertTrue(
            _contains(postDeploySource, "artifact_failed=1"), "post-deploy sets the flag when artifact emission fails"
        );
        assertTrue(
            _contains(postDeploySource, "\"$SKIP_DISTRIBUTE\" -eq 0 && \"$artifact_failed\" -eq 0"),
            "distribution step is gated on the artifact-failed flag"
        );
        assertTrue(
            _contains(postDeploySource, "artifact emission failed"),
            "post-deploy reports the skipped distribution clearly"
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
