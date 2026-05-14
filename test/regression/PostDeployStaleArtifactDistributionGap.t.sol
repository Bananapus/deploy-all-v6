// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

contract PostDeployStaleArtifactDistributionGapTest is Test {
    function test_distributionCopiesStaleCachedArtifactsNotCurrentAddressDump() public view {
        string memory artifactSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");
        string memory distributeSource = vm.readFile("script/post-deploy/lib/distribute.mjs");
        string memory postDeploySource = vm.readFile("script/post-deploy.sh");

        assertTrue(
            _contains(artifactSource, "path.join(CACHE_DIR, `artifacts-${CHAIN_ID}`)"),
            "artifact emission writes into a persistent per-chain cache directory"
        );
        assertTrue(
            _contains(artifactSource, "fs.mkdirSync(outDir, { recursive: true });"),
            "artifact emission creates the cache directory without clearing it"
        );
        assertFalse(_contains(artifactSource, "rmSync(outDir"), "artifact emission does not remove stale cache files");
        assertFalse(
            _contains(artifactSource, "readdirSync(outDir"), "artifact emission does not prune stale cache files"
        );

        assertTrue(
            _contains(distributeSource, "path.join(CACHE_DIR, `artifacts-${CHAIN_ID}`)"),
            "distribution reads from the same persistent cache directory"
        );
        assertTrue(
            _contains(distributeSource, "const files = fs.readdirSync(inDir).filter((f) => f.endsWith('.json'));"),
            "distribution copies every cached artifact JSON file"
        );
        assertTrue(
            _contains(distributeSource, "fs.copyFileSync(sourcePath, dest);"),
            "distribution copies cached files directly"
        );
        assertFalse(_contains(distributeSource, "addresses-"), "distribution does not load the current address dump");
        assertFalse(
            _contains(distributeSource, "readJson({path: sourcePath})"),
            "distribution does not inspect artifact addresses before copying"
        );

        string memory artifactFailureBlock = _section({
            haystack: postDeploySource,
            startNeedle: "node \"$POST_DEPLOY_DIR/lib/artifacts.mjs\" --chain \"$chain_id\" $rehearsal_flag || {",
            endNeedle: "Step 4: fan out"
        });
        assertTrue(_contains(artifactFailureBlock, "GLOBAL_FAIL=1"), "artifact failures mark the global run failed");
        assertFalse(_contains(artifactFailureBlock, "continue"), "artifact failures do not skip distribution");
        assertFalse(_contains(artifactFailureBlock, "exit"), "artifact failures do not stop distribution immediately");

        assertTrue(
            _contains(postDeploySource, "--skip-artifacts                     # verify only"),
            "script usage documents skip-artifacts as verify-only"
        );
        string memory skipArtifactsBlock = _section({
            haystack: postDeploySource,
            startNeedle: "if [[ \"$SKIP_ARTIFACTS\" -eq 0 ]]; then",
            endNeedle: "node \"$POST_DEPLOY_DIR/lib/distribute.mjs\" --chain \"$chain_id\" $extra"
        });
        assertTrue(_contains(skipArtifactsBlock, "echo \"  [3/4] (skip-artifacts)\""), "artifact emission is skipped");
        assertTrue(
            _contains(skipArtifactsBlock, "Step 4: fan out to per-repo deployments"),
            "distribution still follows the skipped artifact step"
        );
        assertFalse(
            _contains(skipArtifactsBlock, "SKIP_DISTRIBUTE=1"),
            "skipping artifacts does not automatically disable distribution"
        );
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
