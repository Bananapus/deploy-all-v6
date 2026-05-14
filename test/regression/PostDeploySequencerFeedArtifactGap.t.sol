// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Deploy} from "../../script/Deploy.s.sol";

contract PostDeploySequencerFeedArtifactGapTest is Test {
    function test_l2SequencerFeedsAreDumpedUnderSequencerArtifactName() public {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");

        assertTrue(
            _contains(deploySource, 'artifactName: "JBChainlinkV3SequencerPriceFeed"'),
            "deploy script deploys L2 sequencer-aware feed artifact"
        );

        // Post-fix: the dump routes ETH_USD and USDC_USD price feeds through _serializePriceFeed,
        // which detects the sequencer-aware variant via SEQUENCER_FEED() and emits under the right
        // artifact prefix. The hardcoded "JBChainlinkV3PriceFeed__ETH_USD" / "..__USDC_USD" entries
        // are gone.
        assertTrue(
            _contains(deploySource, "_serializePriceFeed({key: j, suffix: \"ETH_USD\""),
            "ETH_USD feed routed through sequencer-aware helper"
        );
        assertTrue(
            _contains(deploySource, "_serializePriceFeed({key: j, suffix: \"USDC_USD\""),
            "USDC_USD feed routed through sequencer-aware helper"
        );
        assertTrue(_contains(deploySource, "function _serializePriceFeed"), "_serializePriceFeed helper is defined");
        assertTrue(
            _contains(deploySource, "SEQUENCER_FEED()"), "helper detects sequencer variant via SEQUENCER_FEED() getter"
        );
        assertTrue(
            _contains(deploySource, '"JBChainlinkV3SequencerPriceFeed" : "JBChainlinkV3PriceFeed"'),
            "helper picks the matching artifact name based on detection"
        );

        string memory verifySource = vm.readFile("script/post-deploy/lib/verify.mjs");
        string memory artifactsSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");

        assertTrue(
            _contains(verifySource, "const baseName = target.name.split('__')[0];"),
            "verifier derives artifact name by stripping route suffix"
        );
        assertTrue(
            _contains(artifactsSource, "const baseName = target.name.split('__')[0];"),
            "artifact emitter derives artifact name by stripping route suffix"
        );
        assertTrue(_contains(verifySource, "`${baseName}.json`"), "verifier loads artifact by stripped base name");
        assertTrue(
            _contains(artifactsSource, "`${baseName}.json`"), "artifact emitter loads artifact by stripped base name"
        );

        PostDeployArtifactHarness harness = new PostDeployArtifactHarness();
        assertNotEq(
            harness.creationCodeHash("JBChainlinkV3PriceFeed"),
            harness.creationCodeHash("JBChainlinkV3SequencerPriceFeed"),
            "sequencer and non-sequencer feed artifacts have different creation bytecode"
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

contract PostDeployArtifactHarness is Deploy {
    function creationCodeHash(string memory artifactName) external view returns (bytes32) {
        return keccak256(_loadArtifact(artifactName));
    }
}
