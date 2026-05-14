// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Regression for BT: _dumpAddresses must query the live `_tokens.tokenOf(projectId)` and
/// `_revOwner.tiered721HookOf(projectId)` for each canonical project (1-4) and emit the clone
/// addresses under `JBERC20__Project<NAME>` / `JB721TiersHook__Project<NAME>`.
contract PostDeployCanonicalProjectArtifactGapTest is Test {
    function test_canonicalProjectTokensAndHooksAreEmitted() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory dumpSource = _section({
            haystack: deploySource, startNeedle: "function _dumpAddresses()", endNeedle: "function _serializeIfSet"
        });

        // Sanity — canonical-project deployment paths still exist.
        assertTrue(_contains(deploySource, "NANA_ERC20_SALT"), "deploys NANA ERC-20 from a canonical salt");
        assertTrue(_contains(deploySource, "CPN_ERC20_SALT"), "deploys CPN ERC-20 from a canonical salt");
        assertTrue(_contains(deploySource, "REV_ERC20_SALT"), "deploys REV ERC-20 from a canonical salt");
        assertTrue(_contains(deploySource, "BAN_ERC20_SALT"), "deploys BAN ERC-20 from a canonical salt");
        assertTrue(_contains(deploySource, "CPN_HOOK_SALT"), "deploys CPN 721 hook from a canonical salt");
        assertTrue(_contains(deploySource, "BAN_HOOK_SALT"), "deploys BAN 721 hook from a canonical salt");

        // _dumpAddresses now invokes the canonical-project helpers and queries tokenOf / tiered721HookOf.
        assertTrue(_contains(dumpSource, 'name: "JBERC20"'), "shared ERC-20 implementation is still emitted");
        assertTrue(_contains(dumpSource, "_serializeProjectErc20"), "address dump invokes the canonical ERC-20 helper");
        assertTrue(
            _contains(dumpSource, "_serializeProject721Hook"), "address dump invokes the canonical 721 hook helper"
        );
        assertTrue(_contains(dumpSource, '"ProjectNANA"'), "NANA token clone is emitted with ProjectNANA suffix");
        assertTrue(_contains(dumpSource, '"ProjectCPN"'), "CPN token + hook clones are emitted with ProjectCPN suffix");
        assertTrue(_contains(dumpSource, '"ProjectREV"'), "REV token clone is emitted with ProjectREV suffix");
        assertTrue(_contains(dumpSource, '"ProjectBAN"'), "BAN token + hook clones are emitted with ProjectBAN suffix");

        // Helper bodies actually call the live registry getters.
        assertTrue(
            _contains(deploySource, "_tokens.tokenOf(projectId)"),
            "_serializeProjectErc20 queries the live token registry"
        );
        assertTrue(
            _contains(deploySource, "_revOwner.tiered721HookOf(projectId)"),
            "_serializeProject721Hook queries the live revnet hook registry"
        );

        string memory artifactsSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");
        assertTrue(
            _contains(artifactsSource, "const targets = Object.entries(addresses)"),
            "artifact emission only targets names present in addresses-<chainId>.json"
        );

        string memory docs = vm.readFile("DEPLOY.md");
        assertTrue(
            _contains(docs, "compute every deployed contract's CREATE2 address"),
            "docs claim the address dump covers every CREATE2 deployment"
        );
        assertTrue(_contains(docs, "4 deadlines + JBERC20"), "docs mention the shared ERC-20 implementation");
        assertTrue(
            _contains(docs, "JBERC20__Project") || _contains(docs, "canonical project ERC-20"),
            "docs mention the new canonical project token emissions"
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
