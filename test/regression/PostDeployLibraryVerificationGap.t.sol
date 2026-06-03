// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Regression: verify.mjs must pass `--libraries <path>:<LibName>:<addr>` only for each
/// artifact's actual pre-linked libraries. Passing every manifest library to every verification
/// mutates metadata.settings.libraries for otherwise-unlinked contracts and makes Etherscan reject
/// bytecode that was otherwise correct. The library addresses live in the manifest (top-level
/// `libraries` map) populated by build-artifacts.sh's Phase 3.
contract PostDeployLibraryVerificationGapTest is Test {
    function test_verifierPassesDeferredLibraryLinks() public view {
        string memory buildSource = vm.readFile("script/build-artifacts.sh");
        string memory verifySource = vm.readFile("script/post-deploy/lib/verify.mjs");
        string memory artifactsSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");
        string memory distributeSource = vm.readFile("script/post-deploy/lib/distribute.mjs");
        string memory foundrySource = vm.readFile("foundry.toml");
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

        // verify.mjs reads manifest.libraries, parses artifact linkReferences, and passes only
        // artifact-specific --libraries flags to forge.
        assertTrue(
            _contains(verifySource, "if (!manifest.libraries || typeof manifest.libraries !== 'object') return [];"),
            "verifier reads the manifest's libraries map"
        );
        assertTrue(
            _contains(verifySource, "function linkedLibraryNames(artifact)"),
            "verifier derives library names from artifact linkReferences"
        );
        assertTrue(
            _contains(verifySource, "artifact?.bytecode?.linkReferences"),
            "verifier checks creation bytecode link references"
        );
        assertTrue(
            _contains(verifySource, "artifact?.deployedBytecode?.linkReferences"),
            "verifier checks runtime bytecode link references"
        );
        assertTrue(
            _contains(verifySource, "forgeArgs.push('--libraries'"),
            "verifier appends --libraries flags to forge verify-contract"
        );
        assertTrue(
            _contains(verifySource, "${libEntry.sourcePath}:${libName}:${libEntry.address}"),
            "library spec format matches forge's expected <path>:<name>:<address>"
        );
        assertFalse(
            _contains(verifySource, "for (const [libName, libEntry] of Object.entries(manifest.libraries))"),
            "verifier must not pass every manifest library to every contract"
        );
        assertTrue(
            _contains(verifySource, "const repoDir = resolveSourceRoot(entry);"),
            "verification runs from the manifest source root, not the patched artifact directory"
        );
        assertTrue(
            _contains(verifySource, "if (entry.sourceRoot) return path.resolve(DEPLOY_ROOT, entry.sourceRoot);"),
            "manifest sourceRoot can point verification at npm package roots"
        );
        assertTrue(
            _contains(verifySource, "function verificationFoundryProfile(entry, repoDir)"),
            "verifier chooses a compile profile for deploy-all package artifacts"
        );
        assertTrue(
            _contains(verifySource, "FOUNDRY_PROFILE: foundryProfile || process.env.FOUNDRY_PROFILE || 'default'"),
            "verifier passes the selected Foundry profile through the forge environment"
        );
        assertTrue(
            _contains(verifySource, "FOUNDRY_CACHE_PATH: path.join(forgeScratch, 'cache')"),
            "verifier isolates forge cache so stale default-profile builds cannot leak in"
        );
        assertTrue(
            _contains(verifySource, "FOUNDRY_OUT: path.join(forgeScratch, 'out')"),
            "verifier isolates forge output for each verification compile"
        );
        assertTrue(
            _contains(verifySource, "'--use', entry.solcVersion"),
            "verifier pins the local solc selector from the manifest"
        );
        assertTrue(_contains(verifySource, "'--no-auto-detect'"), "verifier disables solc auto-detection");
        assertTrue(
            _contains(verifySource, "return entry.viaIr ? 'default' : 'verify_non_via_ir';"),
            "non-viaIR package artifacts must not verify with deploy-all's default viaIR profile"
        );
        assertTrue(
            _contains(foundrySource, "[profile.verify_non_via_ir]"),
            "deploy-all exposes an explicit non-viaIR verification profile"
        );
        assertTrue(_contains(foundrySource, "via_ir = false"), "non-viaIR verification profile disables viaIR");

        // Artifact emit unchanged.
        assertTrue(
            _contains(artifactsSource, "solcInputHash = crypto.createHash('md5').update(metadataString)"),
            "artifact emitter hashes metadata"
        );
        assertTrue(
            _contains(distributeSource, "['BannyLPSplitHook', 'JBUniswapV4LPSplitHook']"),
            "artifact distributor resolves Banny LP hook through the LP split hook manifest entry"
        );
        assertTrue(
            _contains(distributeSource, "const baseName = artifactNameFor({name: target.name});"),
            "artifact distributor must apply aliases before manifest lookup"
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
