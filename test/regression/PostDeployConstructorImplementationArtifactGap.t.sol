// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Regression for BZ: build-artifacts.sh must include the constructor-created clone
/// implementations (JBProjectPayer, JB721Checkpoints) in its CONTRACTS list, and _dumpAddresses
/// must emit each implementation alongside its deployer.
contract PostDeployConstructorImplementationArtifactGapTest is Test {
    function test_constructorCreatedCloneImplementationsAreEmitted() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory dumpSource = _section({
            haystack: deploySource, startNeedle: "function _dumpAddresses()", endNeedle: "function _serializeIfSet"
        });
        string memory buildSource = vm.readFile("script/build-artifacts.sh");
        string memory artifactsSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");
        string memory verifySource = vm.readFile("script/Verify.s.sol");
        string memory checkpointsDeployer =
            vm.readFile("node_modules/@bananapus/721-hook-v6/src/JB721CheckpointsDeployer.sol");
        string memory projectPayerDeployer =
            vm.readFile("node_modules/@bananapus/project-payer-v6/src/JBProjectPayerDeployer.sol");

        // Sanity: deployers really do create implementations in their constructors.
        assertTrue(
            _contains(projectPayerDeployer, "IMPLEMENTATION = address(new JBProjectPayer(directory));"),
            "ProjectPayer deployer creates a live implementation in its constructor"
        );
        assertTrue(
            _contains(projectPayerDeployer, "Clones.clone(IMPLEMENTATION)"),
            "ProjectPayer clones delegate to the constructor-created implementation"
        );
        assertTrue(
            _contains(checkpointsDeployer, "IMPLEMENTATION = address(new JB721Checkpoints(store));"),
            "Checkpoints deployer creates a live implementation in its constructor"
        );
        assertTrue(
            _contains(checkpointsDeployer, "LibClone.cloneDeterministic({implementation: IMPLEMENTATION"),
            "checkpoint modules clone the constructor-created implementation"
        );

        // Deploy script still deploys the deployers + Verify.s.sol still checks IMPLEMENTATION code.
        assertTrue(
            _contains(deploySource, 'artifactName: "JBProjectPayerDeployer"'),
            "deploy-all deploys the ProjectPayer deployer"
        );
        assertTrue(
            _contains(deploySource, 'artifactName: "JB721CheckpointsDeployer"'),
            "deploy-all deploys the checkpoints deployer"
        );
        assertTrue(
            _contains(verifySource, "address implementation = projectPayerDeployer.IMPLEMENTATION();"),
            "Verify.s.sol recognizes the ProjectPayer implementation as a live contract"
        );
        assertTrue(
            _contains(verifySource, "ProjectPayer implementation has code"), "Verify.s.sol checks implementation code"
        );

        // build-artifacts.sh now compiles + copies the implementation artifacts.
        assertTrue(
            _contains(buildSource, "nana-project-payer-v6:JBProjectPayerDeployer:src/JBProjectPayerDeployer.sol"),
            "artifact build includes the ProjectPayer deployer"
        );
        assertTrue(
            _contains(buildSource, "nana-721-hook-v6:JB721CheckpointsDeployer:src/JB721CheckpointsDeployer.sol"),
            "artifact build includes the checkpoints deployer"
        );
        assertTrue(
            _contains(buildSource, "nana-project-payer-v6:JBProjectPayer:src/JBProjectPayer.sol"),
            "artifact build now includes the ProjectPayer implementation"
        );
        assertTrue(
            _contains(buildSource, "nana-721-hook-v6:JB721Checkpoints:src/JB721Checkpoints.sol"),
            "artifact build now includes the checkpoints implementation"
        );

        // _dumpAddresses emits the deployer AND its IMPLEMENTATION() target.
        assertTrue(_contains(dumpSource, 'name: "JBProjectPayerDeployer"'), "ProjectPayer deployer is emitted");
        assertTrue(_contains(dumpSource, 'name: "JB721CheckpointsDeployer"'), "checkpoints deployer is emitted");
        assertTrue(
            _contains(dumpSource, 'name: "JBProjectPayer"'),
            "ProjectPayer implementation is now emitted via IMPLEMENTATION()"
        );
        assertTrue(
            _contains(dumpSource, 'name: "JB721Checkpoints"'),
            "checkpoints implementation is now emitted via IMPLEMENTATION()"
        );
        assertTrue(
            _contains(deploySource, "function _serializeImplementationFromDeployer"),
            "_serializeImplementationFromDeployer helper exists"
        );

        // Post-deploy emits artifacts based on address dump (no change).
        assertTrue(
            _contains(artifactsSource, "const targets = Object.entries(addresses)"),
            "post-deploy artifacts are emitted only for address-dump targets"
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
