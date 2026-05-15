// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Regression: verify.mjs must treat missing manifest entries (and identity-
/// mismatched cache hits) as fail-closed, and the process exit must reflect both critical
/// failure categories.
contract PostDeployVerifyStatusGapTest is Test {
    function test_verifyScriptFailsClosedOnMissingManifestEntries() public view {
        string memory verifySource = vm.readFile("script/post-deploy/lib/verify.mjs");
        string memory artifactSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");

        assertTrue(
            _contains(verifySource, "const allContractsOnChain = Object.entries(addresses)"),
            "verification targets are sourced from the address dump"
        );
        assertTrue(
            _contains(verifySource, "const entry = manifest.contracts[baseName];"),
            "verification relies on the base-name manifest entry"
        );

        // Missing manifest entries fail closed unless explicitly allowlisted.
        assertTrue(_contains(verifySource, "VERIFY_SKIP_ALLOWLIST"), "missing-manifest skip allowlist is declared");
        assertTrue(
            _contains(verifySource, "VERIFY_SKIP_ALLOWLIST.has(target.name)"),
            "missing manifest entries check the allowlist"
        );
        assertTrue(
            _contains(verifySource, "skipFailures += 1"),
            "missing manifest entries increment a critical failure counter"
        );
        assertTrue(
            _contains(verifySource, "process.exit(permanentFailures + skipFailures > 0 ? 1 : 0);"),
            "process exit reflects both permanent failures and skip failures"
        );

        assertTrue(
            _contains(artifactSource, "if (!manifestEntry) throw new Error(`not in manifest`);"),
            "artifact emission also treats missing manifest entries as an error"
        );
    }

    function test_cachedVerifiedStatusIsBoundToCurrentTargetIdentity() public view {
        string memory verifySource = vm.readFile("script/post-deploy/lib/verify.mjs");

        string memory cachedStatusBlock = _section({
            haystack: verifySource, startNeedle: "const cur = status.contracts[target.name] || {};", endNeedle: "try {"
        });

        // The cache hit must check address, chainId, sourcePath, and gitCommit alignment.
        assertTrue(
            _contains(cachedStatusBlock, "cur.status === 'verified'"),
            "verified cache status is checked before verification"
        );
        assertTrue(_contains(cachedStatusBlock, "cur.address"), "cached address is now part of the cache key");
        assertTrue(_contains(cachedStatusBlock, "cur.chainId"), "cached chainId is now part of the cache key");
        assertTrue(_contains(cachedStatusBlock, "cur.sourcePath"), "cached sourcePath is now part of the cache key");
        assertTrue(_contains(cachedStatusBlock, "cur.gitCommit"), "cached gitCommit is now part of the cache key");
        assertTrue(_contains(cachedStatusBlock, "cache-busted"), "identity mismatches log a cache bust and re-verify");

        // On successful verify, the status entry now stores the full identity tuple.
        assertTrue(_contains(verifySource, "chainId: CHAIN_ID,"), "status records chainId");
        assertTrue(_contains(verifySource, "sourcePath: entry.sourcePath,"), "status records sourcePath");
        assertTrue(_contains(verifySource, "gitCommit: entry.gitCommit,"), "status records gitCommit");
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
