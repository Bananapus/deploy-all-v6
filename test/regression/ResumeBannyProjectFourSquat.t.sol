// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";

contract ResumeBannyProjectFourSquatTest is Test {
    uint256 internal constant BAN_PROJECT_ID = 4;

    address internal attacker = makeAddr("attacker");
    address internal controller = makeAddr("controller");
    address internal jbMultiTerminal = makeAddr("jbMultiTerminal");

    MockProjects internal projects;
    MockDirectory internal directory;
    ResumeBannyHarness internal resumeHarness;

    function setUp() public {
        projects = new MockProjects();
        directory = new MockDirectory();
        resumeHarness = new ResumeBannyHarness(IJBProjects(address(projects)), IJBDirectory(address(directory)));

        projects.setCount(BAN_PROJECT_ID);
        projects.setOwner(BAN_PROJECT_ID, attacker);
        directory.setController(BAN_PROJECT_ID, controller);
        directory.setPrimaryTerminal(BAN_PROJECT_ID, jbMultiTerminal);

        address[] memory terminals = new address[](1);
        terminals[0] = jbMultiTerminal;
        directory.setTerminals(BAN_PROJECT_ID, terminals);
    }

    function test_resumeRejectsConfiguredAttackerProjectFour() public {
        vm.expectRevert(abi.encodeWithSelector(ResumeBannyHarness.Resume_ProjectNotCanonical.selector, BAN_PROJECT_ID));
        resumeHarness.resumeBanny();

        assertEq(projects.ownerOf(BAN_PROJECT_ID), attacker, "attacker keeps project four");
        assertEq(resumeHarness.bannyResolver(), address(0), "no canonical Banny resolver is deployed");
    }
}

contract ResumeBannyHarness {
    error Resume_ProjectNotCanonical(uint256 projectId);

    IJBProjects internal immutable PROJECTS;
    IJBDirectory internal immutable DIRECTORY;

    address public bannyResolver;

    constructor(IJBProjects projects, IJBDirectory directory) {
        PROJECTS = projects;
        DIRECTORY = directory;
    }

    function resumeBanny() external returns (bool skipped) {
        if (PROJECTS.count() >= BAN_PROJECT_ID() && address(DIRECTORY.controllerOf(BAN_PROJECT_ID())) != address(0)) {
            if (!_isCanonicalConfiguredProject(BAN_PROJECT_ID())) revert Resume_ProjectNotCanonical(BAN_PROJECT_ID());
            return true;
        }

        bannyResolver = address(new MockBannyResolver());
        return false;
    }

    function BAN_PROJECT_ID() public pure returns (uint256) {
        return 4;
    }

    function _isCanonicalConfiguredProject(uint256 projectId) internal pure returns (bool) {
        projectId;
        return false;
    }
}

contract MockBannyResolver {}

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
}

contract MockDirectory {
    mapping(uint256 => address) internal _controllerOf;
    mapping(uint256 => address) internal _primaryTerminalOf;
    mapping(uint256 => address[]) internal _terminalsOf;

    function setController(uint256 projectId, address controller) external {
        _controllerOf[projectId] = controller;
    }

    function setPrimaryTerminal(uint256 projectId, address terminal) external {
        _primaryTerminalOf[projectId] = terminal;
    }

    function setTerminals(uint256 projectId, address[] memory terminals) external {
        _terminalsOf[projectId] = terminals;
    }

    function controllerOf(uint256 projectId) external view returns (address) {
        return _controllerOf[projectId];
    }

    function primaryTerminalOf(uint256 projectId, address) external view returns (IJBTerminal) {
        return IJBTerminal(_primaryTerminalOf[projectId]);
    }

    function terminalsOf(uint256 projectId) external view returns (IJBTerminal[] memory terminals) {
        address[] storage stored = _terminalsOf[projectId];
        terminals = new IJBTerminal[](stored.length);

        for (uint256 i; i < stored.length; i++) {
            terminals[i] = IJBTerminal(stored[i]);
        }
    }
}
