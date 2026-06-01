// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Proves that every precompiled artifact the deploy loads at runtime is produced by the artifact build.
/// @dev The deploy resolves each contract's creation code from `artifacts/<name>.json` through `vm.readFile`
/// (`_loadArtifact` / `_deployPrecompiledIfNeeded`). A contract that the deploy references but the artifact build
/// (`script/build-artifacts.sh`) does not emit therefore reverts at deploy time on every chain — the deploy script
/// itself compiles fine and the fork tests, which re-build the protocol with direct `new` calls, never exercise the
/// artifact-loading path, so nothing else catches it. This test derives the required set straight from the deploy
/// source (so it can never drift from the code) and asserts each artifact exists after the canonical build.
contract DeployArtifactCompletenessGapTest is Test {
    /// @notice The two ways the deploy names a precompiled artifact: the `_deployPrecompiledIfNeeded` struct field
    /// (`artifactName: "X"`) and the direct loader (`_loadArtifact("X")`). Every artifact load funnels through one of
    /// these, so scanning for both yields the complete set the build must cover.
    bytes private constant _STRUCT_FIELD_MARKER = bytes('artifactName: "');
    bytes private constant _DIRECT_LOAD_MARKER = bytes('_loadArtifact("');

    function test_everyLoadedArtifactIsBuilt() public {
        // The canonical artifacts are produced by `npm run artifacts` ahead of the suite in CI. When they are absent
        // (a bare `forge test` with no prior build) there is nothing to verify, so skip rather than report a false gap.
        if (!vm.exists("artifacts/artifacts.manifest.json")) {
            vm.skip(true);
            return;
        }

        // Read the deploy source and pull out every artifact name it loads.
        string memory source = vm.readFile("script/Deploy.s.sol");
        string[] memory names = _loadedArtifactNames(source);

        // A deploy that loads nothing means the markers changed and this guard silently stopped covering anything.
        assertGt(names.length, 0, "expected the deploy to load at least one precompiled artifact");

        // Each loaded artifact must exist on disk; a missing one is the exact deploy-time revert this guards against.
        for (uint256 i; i < names.length; i++) {
            assertTrue(
                vm.exists(string.concat("artifacts/", names[i], ".json")),
                string.concat(
                    "Deploy.s.sol loads '",
                    names[i],
                    "' but artifacts/",
                    names[i],
                    ".json was not built. Add it to script/build-artifacts.sh."
                )
            );
        }
    }

    /// @notice Collects every artifact name referenced through either marker in `source`.
    /// @dev Two passes: count matches to size the array (memory arrays cannot grow), then fill it.
    function _loadedArtifactNames(string memory source) internal pure returns (string[] memory names) {
        bytes memory s = bytes(source);
        uint256 total = _countMarker(s, _STRUCT_FIELD_MARKER) + _countMarker(s, _DIRECT_LOAD_MARKER);
        names = new string[](total);
        uint256 idx = _fillNames(s, _STRUCT_FIELD_MARKER, names, 0);
        _fillNames(s, _DIRECT_LOAD_MARKER, names, idx);
    }

    /// @notice Counts how many times `marker` (immediately followed by the artifact name and a closing quote) appears.
    function _countMarker(bytes memory s, bytes memory marker) internal pure returns (uint256 count) {
        uint256 from;
        while (true) {
            int256 at = _indexOf(s, marker, from);
            if (at < 0) break;
            count++;
            from = uint256(at) + marker.length;
        }
    }

    /// @notice Writes the artifact name following each `marker` occurrence into `names`, starting at `start`, and
    /// returns the next free index.
    function _fillNames(
        bytes memory s,
        bytes memory marker,
        string[] memory names,
        uint256 start
    )
        internal
        pure
        returns (uint256 next)
    {
        next = start;
        uint256 from;
        while (true) {
            int256 at = _indexOf(s, marker, from);
            if (at < 0) break;
            // The name runs from just past the marker up to the closing double-quote.
            uint256 nameStart = uint256(at) + marker.length;
            uint256 nameEnd = nameStart;
            while (nameEnd < s.length && s[nameEnd] != '"') nameEnd++;
            bytes memory name = new bytes(nameEnd - nameStart);
            for (uint256 i; i < name.length; i++) {
                name[i] = s[nameStart + i];
            }
            names[next++] = string(name);
            from = nameEnd;
        }
    }

    /// @notice Returns the first index of `needle` in `haystack` at or after `from`, or -1 if absent.
    function _indexOf(bytes memory haystack, bytes memory needle, uint256 from) internal pure returns (int256) {
        if (needle.length == 0 || haystack.length < needle.length) return -1;
        for (uint256 i = from; i + needle.length <= haystack.length; i++) {
            bool matched = true;
            for (uint256 j; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) return int256(i);
        }
        return -1;
    }
}
