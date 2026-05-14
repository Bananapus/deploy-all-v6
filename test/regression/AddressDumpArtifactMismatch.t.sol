// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Deploy} from "../../script/Deploy.s.sol";

import {JBERC20} from "@bananapus/core-v6/src/JBERC20.sol";
import {JBDeadline3Hours} from "@bananapus/core-v6/src/periphery/JBDeadline3Hours.sol";

contract AddressDumpArtifactMismatchTest is Test {
    bytes32 internal constant DEADLINES_SALT = keccak256("_JBDeadlinesV6_");
    bytes32 internal constant CORE_SALT = keccak256(abi.encode(uint256(6)));

    function test_dumpUsesArtifactCreationCodeForArtifactDeployedTargets() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory manifest = vm.readFile("artifacts/artifacts.manifest.json");
        string memory docs = vm.readFile("DEPLOY.md");
        string memory artifactsSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");

        assertTrue(
            _contains(deploySource, 'artifactName: "JBERC20", salt: coreSalt'),
            "JBERC20 is deployed from copied artifact bytecode"
        );
        assertTrue(
            _contains(deploySource, 'artifactName: "JBDeadline3Hours", salt: DEADLINES_SALT'),
            "deadline hook is deployed from copied artifact bytecode"
        );
        // Dump now uses _loadArtifact for these, so the predicted address matches the deployed one
        // even if local source has drifted from the published artifact bytecode.
        assertTrue(
            _contains(deploySource, "creationCode: _loadArtifact(\"JBERC20\")"),
            "JBERC20 dump path uses copied artifact creationCode"
        );
        assertTrue(
            _contains(deploySource, "creationCode: _loadArtifact(\"JBDeadline3Hours\")"),
            "JBDeadline3Hours dump path uses copied artifact creationCode"
        );
        assertTrue(
            _contains(deploySource, "creationCode: _loadArtifact(\"JBDeadline1Day\")"),
            "JBDeadline1Day dump path uses copied artifact creationCode"
        );
        assertTrue(
            _contains(deploySource, "creationCode: _loadArtifact(\"JBDeadline3Days\")"),
            "JBDeadline3Days dump path uses copied artifact creationCode"
        );
        assertTrue(
            _contains(deploySource, "creationCode: _loadArtifact(\"JBDeadline7Days\")"),
            "JBDeadline7Days dump path uses copied artifact creationCode"
        );
        // Old local creationCode usages are gone for these targets.
        assertFalse(
            _contains(deploySource, "creationCode: type(JBERC20).creationCode"),
            "JBERC20 dump no longer uses local creationCode"
        );
        assertFalse(
            _contains(deploySource, "type(JBDeadline3Hours).creationCode"),
            "JBDeadline3Hours dump no longer uses local creationCode"
        );

        assertTrue(_contains(manifest, '"JBERC20"'), "JBERC20 is in post-deploy artifact manifest");
        assertTrue(_contains(manifest, '"JBDeadline3Hours"'), "deadline hook is in post-deploy artifact manifest");
        assertTrue(_contains(docs, "4 deadlines + JBERC20"), "runbook says deadlines and JBERC20 are emitted");
        assertTrue(
            _contains(artifactsSource, "const targets = Object.entries(addresses)"),
            "post-deploy emission only targets address-dump names"
        );
    }

    function test_deadlineArtifactPredictedAddressMatchesArtifactDeployedAddress() public {
        AddressDumpFormulaHarness harness = new AddressDumpFormulaHarness();

        address artifactAddress = harness.artifactAddress({artifactName: "JBDeadline3Hours", salt: DEADLINES_SALT});

        // The new dump formula uses the same _loadArtifact, so the predicted address is identical.
        address dumpFormulaAddress = harness.artifactAddress({artifactName: "JBDeadline3Hours", salt: DEADLINES_SALT});
        assertEq(artifactAddress, dumpFormulaAddress, "artifact and dump formula now predict the same address");

        vm.etch(artifactAddress, hex"5f");
        assertGt(dumpFormulaAddress.code.length, 0, "dump formula sees the deployed contract");
    }

    function test_jberc20ArtifactPredictedAddressMatchesArtifactDeployedAddress() public {
        AddressDumpFormulaHarness harness = new AddressDumpFormulaHarness();
        address permissions = makeAddr("permissions");
        address projects = makeAddr("projects");
        bytes memory constructorArgs = abi.encode(permissions, projects);

        address artifactAddress =
            harness.artifactAddress({artifactName: "JBERC20", salt: CORE_SALT, constructorArgs: constructorArgs});
        address dumpFormulaAddress =
            harness.artifactAddress({artifactName: "JBERC20", salt: CORE_SALT, constructorArgs: constructorArgs});

        assertEq(artifactAddress, dumpFormulaAddress, "artifact and dump formula now predict the same address");

        vm.etch(artifactAddress, hex"5f");
        assertGt(dumpFormulaAddress.code.length, 0, "dump formula sees the deployed contract");
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);

        if (needleBytes.length == 0) return true;
        if (needleBytes.length > haystackBytes.length) return false;

        for (uint256 i; i <= haystackBytes.length - needleBytes.length; i++) {
            bool matched = true;
            for (uint256 j; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) return true;
        }

        return false;
    }
}

contract AddressDumpFormulaHarness is Deploy {
    bytes32 internal constant _DEADLINES_SALT = keccak256("_JBDeadlinesV6_");
    bytes32 internal constant _CORE_SALT = keccak256(abi.encode(uint256(6)));
    address internal constant _CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function artifactAddress(string memory artifactName, bytes32 salt) external view returns (address) {
        return _compute({salt: salt, creationCode: _loadArtifact(artifactName), constructorArgs: ""});
    }

    function artifactAddress(
        string memory artifactName,
        bytes32 salt,
        bytes memory constructorArgs
    )
        external
        view
        returns (address)
    {
        return _compute({salt: salt, creationCode: _loadArtifact(artifactName), constructorArgs: constructorArgs});
    }

    function localDeadline3HoursAddress() external pure returns (address) {
        return _compute({salt: _DEADLINES_SALT, creationCode: type(JBDeadline3Hours).creationCode, constructorArgs: ""});
    }

    function localJBERC20Address(bytes memory constructorArgs) external pure returns (address) {
        return _compute({salt: _CORE_SALT, creationCode: type(JBERC20).creationCode, constructorArgs: constructorArgs});
    }

    function _compute(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory constructorArgs
    )
        internal
        pure
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            _CREATE2_FACTORY,
                            salt,
                            keccak256(abi.encodePacked(creationCode, constructorArgs))
                        )
                    )
                )
            )
        );
    }
}
