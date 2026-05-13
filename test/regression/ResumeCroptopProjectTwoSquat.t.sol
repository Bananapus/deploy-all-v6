// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";

contract ResumeCroptopProjectTwoSquatTest is Test {
    uint256 internal constant CPN_PROJECT_ID = 2;

    address internal deployer = makeAddr("deployer");
    address internal attacker = makeAddr("attacker");
    address internal controller = makeAddr("controller");

    MockProjects internal projects;
    MockDirectory internal directory;
    ResumeCroptopHarness internal harness;

    function setUp() public {
        projects = new MockProjects();
        directory = new MockDirectory();
        harness = new ResumeCroptopHarness(IJBProjects(address(projects)), IJBDirectory(address(directory)), deployer);

        projects.setCount(CPN_PROJECT_ID);
        projects.setOwner(CPN_PROJECT_ID, attacker);
        directory.setController(CPN_PROJECT_ID, controller);
    }

    function test_resumeRejectsConfiguredAttackerProjectTwoAsCroptopFeeSink() public {
        vm.expectRevert(
            abi.encodeWithSelector(ResumeCroptopHarness.Resume_ProjectNotCanonical.selector, CPN_PROJECT_ID)
        );
        harness.resumeCroptop();

        assertEq(projects.ownerOf(CPN_PROJECT_ID), attacker, "attacker keeps project two");
    }
}

contract ResumeCroptopHarness {
    error Resume_ProjectNotCanonical(uint256 projectId);

    IJBProjects internal immutable PROJECTS;
    IJBDirectory internal immutable DIRECTORY;
    address internal immutable DEPLOYER;

    constructor(IJBProjects projects, IJBDirectory directory, address deployer) {
        PROJECTS = projects;
        DIRECTORY = directory;
        DEPLOYER = deployer;
    }

    function resumeCroptop() external returns (CTPublisher publisher) {
        uint256 cpnProjectId = _ensureProjectExists(CPN_PROJECT_ID());
        publisher = new CTPublisher(DIRECTORY, IJBPermissions(address(0)), cpnProjectId, address(0));
    }

    function CPN_PROJECT_ID() public pure returns (uint256) {
        return 2;
    }

    function _ensureProjectExists(uint256 expectedProjectId) internal returns (uint256) {
        uint256 count = PROJECTS.count();
        if (count >= expectedProjectId) {
            if (address(DIRECTORY.controllerOf(expectedProjectId)) != address(0)) {
                if (!_isCanonicalConfiguredProject(expectedProjectId)) {
                    revert Resume_ProjectNotCanonical(expectedProjectId);
                }
                return expectedProjectId;
            }
            if (PROJECTS.ownerOf(expectedProjectId) != DEPLOYER) revert("Resume_ProjectNotOwned");
            return expectedProjectId;
        }

        uint256 created = PROJECTS.createFor(DEPLOYER);
        if (created != expectedProjectId) revert("Resume_ProjectIdMismatch");
        return created;
    }

    function _isCanonicalConfiguredProject(uint256 projectId) internal pure returns (bool) {
        projectId;
        return false;
    }
}

contract MockProjects {
    mapping(uint256 => address) internal _ownerOf;
    uint256 internal _count;

    function setCount(uint256 newCount) external {
        _count = newCount;
    }

    function setOwner(uint256 projectId, address owner) external {
        _ownerOf[projectId] = owner;
    }

    function count() external view returns (uint256) {
        return _count;
    }

    function ownerOf(uint256 projectId) external view returns (address) {
        return _ownerOf[projectId];
    }

    function createFor(address owner) external returns (uint256) {
        unchecked {
            ++_count;
        }
        _ownerOf[_count] = owner;
        return _count;
    }
}

contract MockDirectory {
    mapping(uint256 => address) internal _controllerOf;

    function setController(uint256 projectId, address controller) external {
        _controllerOf[projectId] = controller;
    }

    function controllerOf(uint256 projectId) external view returns (address) {
        return _controllerOf[projectId];
    }
}
