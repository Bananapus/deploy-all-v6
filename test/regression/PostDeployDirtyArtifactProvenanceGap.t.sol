// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Regression for BW: artifact builds must fail closed on dirty source unless --rehearsal is
/// passed, published artifacts must expose gitDirty alongside gitCommit, and downstream verify/emit
/// scripts must refuse to publish dirty manifests on production chains without --rehearsal.
contract PostDeployDirtyArtifactProvenanceGapTest is Test {
    function test_dirtySourceGateAndProvenancePropagation() public view {
        string memory buildSource = vm.readFile("script/build-artifacts.sh");
        string memory verifySource = vm.readFile("script/post-deploy/lib/verify.mjs");
        string memory artifactSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");
        string memory postDeploySource = vm.readFile("script/post-deploy.sh");
        string memory chainsCfg = vm.readFile("script/post-deploy/chains.json");
        string memory deployDocs = vm.readFile("DEPLOY.md");

        // build-artifacts.sh — gate exists, REHEARSAL flag parsed, dirty repos fail by default.
        assertTrue(_contains(buildSource, "REHEARSAL=0"), "build script declares REHEARSAL flag default");
        assertTrue(_contains(buildSource, "--rehearsal) REHEARSAL=1"), "build script parses --rehearsal flag");
        assertTrue(_contains(buildSource, "Dirty-source gate"), "build script has explicit dirty-source gate section");
        assertTrue(
            _contains(buildSource, "source repo(s) have uncommitted changes"),
            "build script errors when dirty without --rehearsal"
        );
        assertTrue(_contains(buildSource, "ANY_DIRTY=\"true\""), "build script computes any-dirty summary");
        assertTrue(_contains(buildSource, '"gitDirty": %s'), "build script writes top-level gitDirty to manifest");
        assertTrue(_contains(buildSource, "REPO_DIRTY[$repo]=\"true\""), "build script still detects dirty repos");

        // artifacts.mjs — production-chain gate + gitDirty in emitted artifact.
        assertTrue(
            _contains(artifactSource, "Refusing to emit artifacts for production chain"),
            "artifact emitter refuses production with dirty manifest"
        );
        assertTrue(
            _contains(artifactSource, "manifest.gitDirty && chain.production && !args.rehearsal"),
            "artifact emitter gate uses manifest dirty + chain production + rehearsal flag"
        );
        string memory emittedArtifactObject =
            _section({haystack: artifactSource, startNeedle: "return {", endNeedle: "history: []"});
        assertTrue(_contains(emittedArtifactObject, "gitCommit:"), "published artifact includes gitCommit");
        assertTrue(_contains(emittedArtifactObject, "gitDirty:"), "published artifact also includes gitDirty");

        // verify.mjs — production-chain gate.
        assertTrue(
            _contains(verifySource, "Refusing to verify on production chain"),
            "verifier refuses production with dirty manifest"
        );
        assertTrue(
            _contains(verifySource, "manifest.gitDirty && chain.production && !args.rehearsal"),
            "verifier gate uses manifest dirty + chain production + rehearsal flag"
        );

        // post-deploy.sh — propagates --rehearsal + has a defense-in-depth preflight.
        assertTrue(_contains(postDeploySource, "REHEARSAL=0"), "post-deploy declares REHEARSAL flag default");
        assertTrue(_contains(postDeploySource, "--rehearsal) REHEARSAL=1"), "post-deploy parses --rehearsal");
        assertTrue(
            _contains(postDeploySource, "production chain $alias refuses dirty manifest"),
            "post-deploy preflight refuses dirty production"
        );
        assertTrue(
            _contains(postDeploySource, "rehearsal_flag"), "post-deploy propagates --rehearsal to verify/artifacts"
        );

        // chains.json — production flag explicit per chain.
        assertTrue(_contains(chainsCfg, "\"production\": true"), "chains.json marks production chains");
        assertTrue(_contains(chainsCfg, "\"production\": false"), "chains.json marks non-production chains");

        // DEPLOY.md — operators must know about the gate.
        assertTrue(_contains(deployDocs, "--rehearsal"), "docs document --rehearsal flag");
        assertTrue(_contains(deployDocs, "gitDirty"), "docs document gitDirty provenance");
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
