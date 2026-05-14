// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Regression for BY: build-artifacts.sh must `forge clean` source repos before building
/// (so stale out/*.json can't be picked up), validate that the source file exists in the source
/// repo, and validate that the copied artifact's metadata.settings.compilationTarget binds the
/// expected (sourcePath, contractName) pair.
contract PostDeployStaleSourceArtifactGapTest is Test {
    function test_buildArtifactsClearsStaleOutAndValidatesArtifactProvenance() public view {
        string memory buildSource = vm.readFile("script/build-artifacts.sh");
        string memory deploySource = vm.readFile("script/Deploy.s.sol");

        // build_repo() runs `forge clean` before `forge build` so no out/*.json from a previous
        // compilation can survive into this run.
        string memory buildRepoBlock =
            _section({haystack: buildSource, startNeedle: "build_repo() {", endNeedle: "# Capture git commit"});
        assertTrue(_contains(buildRepoBlock, "forge clean"), "source repo build runs forge clean first");
        assertTrue(_contains(buildRepoBlock, "forge build"), "source repos are built after the clean step");

        // The artifact-copy block validates source-file existence AND artifact compilation target
        // before the copy.
        string memory copyBlock = _section({
            haystack: buildSource,
            startNeedle: "src_filename=\"$(basename \"$src_path\")\"",
            endNeedle: "# Compose manifest entry"
        });
        assertTrue(
            _contains(copyBlock, "artifact=\"$repo_dir/out/$src_filename/$contract.json\""),
            "artifact is loaded from the source repo out directory"
        );
        assertTrue(_contains(copyBlock, "if [[ ! -f \"$artifact\" ]]"), "artifact existence is checked");
        assertTrue(_contains(copyBlock, "cp \"$artifact\" \"$ARTIFACTS_DIR/$contract.json\""), "out JSON is copied");

        // The new validation checks: source file present + metadata target matches expectation.
        // These live just above the copy block, so check them in the surrounding region.
        string memory validationRegion = _section({
            haystack: buildSource, startNeedle: "if [[ ! -d \"$repo_dir\" ]]", endNeedle: "# Compose manifest entry"
        });
        assertTrue(
            _contains(validationRegion, "if [[ ! -f \"$repo_dir/$src_path\" ]]"),
            "source-file existence is verified before artifact copy"
        );
        assertTrue(
            _contains(validationRegion, "settings.compilationTarget[$path]"),
            "artifact metadata compilationTarget is verified before copy"
        );
        assertTrue(
            _contains(validationRegion, "compilation_target=$(jq -r"),
            "compilationTarget is extracted via jq for validation"
        );
        assertTrue(
            _contains(validationRegion, "compilationTarget=\\\"$compilation_target\\\", expected \\\"$contract\\\""),
            "compilationTarget mismatch produces a clear error"
        );

        // Deploy.s.sol still consumes copied artifacts (no change to that path).
        assertTrue(
            _contains(
                deploySource, "return _loadCreationCode(string.concat(\"artifacts/\", artifactName, \".json\"));"
            ),
            "Deploy.s.sol consumes copied artifact JSON"
        );
        assertTrue(
            _contains(deploySource, "bytes memory code = _loadArtifact(artifactName);"),
            "deployment bytecode comes from copied artifacts"
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
