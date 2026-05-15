// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Regression: verify.mjs must pass `--libraries <path>:<LibName>:<addr>` for every
/// pre-linked library so forge verify-contract can re-link the source against the on-chain
/// bytecode. The library addresses live in the manifest (top-level `libraries` map) populated by
/// build-artifacts.sh's Phase 3.
contract PostDeployLibraryVerificationGapTest is Test {
    function test_verifierPassesDeferredLibraryLinks() public view {
        string memory buildSource = vm.readFile("script/build-artifacts.sh");
        string memory verifySource = vm.readFile("script/post-deploy/lib/verify.mjs");
        string memory artifactsSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");
        string memory defifaHookArtifact = vm.readFile("artifacts/DefifaHook.json");

        // Build script still computes + substitutes deterministic library addresses.
        assertTrue(_contains(buildSource, "Phase 2: deferred library linking"), "artifact build links libraries");
        assertTrue(_contains(buildSource, "LIB_SALTS=("), "library salts are computed during artifact build");
        assertTrue(
            _contains(buildSource, "after=\"${after//$placeholder/$libaddr_hex}\""),
            "artifact bytecode is patched with deterministic library addresses"
        );

        // Phase 3 now persists library addresses to the manifest so verify.mjs can consume them.
        assertTrue(
            _contains(buildSource, "Phase 3: persist library addresses in the manifest"),
            "library addresses are persisted to the manifest"
        );
        assertTrue(_contains(buildSource, "LIBRARIES_JSON"), "library addresses accumulated for manifest emission");
        assertTrue(_contains(buildSource, "{libraries: $libs}"), "manifest is extended with a top-level libraries map");

        assertTrue(_contains(defifaHookArtifact, "\"linkReferences\""), "DefifaHook has external library links");
        assertTrue(_contains(defifaHookArtifact, "\"DefifaHookLib\""), "DefifaHook links DefifaHookLib");
        assertFalse(_contains(defifaHookArtifact, "__$"), "copied deployment artifact has patched library placeholders");

        // verify.mjs reads manifest.libraries and passes --libraries flags to forge.
        assertTrue(
            _contains(verifySource, "manifest.libraries && typeof manifest.libraries"),
            "verifier reads the manifest's libraries map"
        );
        assertTrue(
            _contains(verifySource, "forgeArgs.push('--libraries'"),
            "verifier appends --libraries flags to forge verify-contract"
        );
        assertTrue(
            _contains(verifySource, "${libEntry.sourcePath}:${libName}:${libEntry.address}"),
            "library spec format matches forge's expected <path>:<name>:<address>"
        );
        assertTrue(
            _contains(
                verifySource,
                "const repoDir = entry.repo === 'deploy-all-v6' ? DEPLOY_ROOT : path.join(MONOREPO_ROOT, entry.repo);"
            ),
            "verification runs from the source repo, not the patched artifact directory"
        );

        // Artifact emit unchanged.
        assertTrue(
            _contains(artifactsSource, "solcInputHash = crypto.createHash('md5').update(metadataString)"),
            "artifact emitter hashes metadata"
        );
        string memory emittedArtifactObject =
            _section({haystack: artifactsSource, startNeedle: "return {", endNeedle: "history: []"});
        assertTrue(_contains(emittedArtifactObject, "metadata: metadataString"), "emitted artifacts publish metadata");
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
