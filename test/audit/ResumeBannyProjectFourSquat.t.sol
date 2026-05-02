// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
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
    VerifyBannyShapeHarness internal verifyHarness;

    function setUp() public {
        projects = new MockProjects();
        directory = new MockDirectory();
        resumeHarness = new ResumeBannyHarness(IJBProjects(address(projects)), IJBDirectory(address(directory)));
        verifyHarness = new VerifyBannyShapeHarness(
            IJBProjects(address(projects)), IJBDirectory(address(directory)), IJBTerminal(jbMultiTerminal)
        );

        projects.setCount(BAN_PROJECT_ID);
        projects.setOwner(BAN_PROJECT_ID, attacker);
        directory.setController(BAN_PROJECT_ID, controller);
        directory.setPrimaryTerminal(BAN_PROJECT_ID, jbMultiTerminal);

        address[] memory terminals = new address[](1);
        terminals[0] = jbMultiTerminal;
        directory.setTerminals(BAN_PROJECT_ID, terminals);
    }

    function test_resumeTreatsConfiguredAttackerProjectFourAsCanonicalBanny() public {
        bool skipped = resumeHarness.resumeBanny();

        assertTrue(skipped, "resume should skip the Banny phase");
        assertEq(projects.ownerOf(BAN_PROJECT_ID), attacker, "attacker keeps project four");
        assertEq(resumeHarness.bannyResolver(), address(0), "no canonical Banny resolver is deployed");

        // These are the BAN-specific checks Verify.s.sol currently performs: existence plus generic JB wiring.
        verifyHarness.verify();
    }
}

contract ResumeBannyHarness {
    IJBProjects internal immutable PROJECTS;
    IJBDirectory internal immutable DIRECTORY;

    address public bannyResolver;

    constructor(IJBProjects projects, IJBDirectory directory) {
        PROJECTS = projects;
        DIRECTORY = directory;
    }

    function resumeBanny() external returns (bool skipped) {
        if (PROJECTS.count() >= BAN_PROJECT_ID() && address(DIRECTORY.controllerOf(BAN_PROJECT_ID())) != address(0)) {
            return true;
        }

        bannyResolver = address(new MockBannyResolver());
        return false;
    }

    function BAN_PROJECT_ID() public pure returns (uint256) {
        return 4;
    }
}

contract VerifyBannyShapeHarness {
    IJBProjects internal immutable PROJECTS;
    IJBDirectory internal immutable DIRECTORY;
    IJBTerminal internal immutable TERMINAL;

    constructor(IJBProjects projects, IJBDirectory directory, IJBTerminal terminal) {
        PROJECTS = projects;
        DIRECTORY = directory;
        TERMINAL = terminal;
    }

    function verify() external view {
        require(PROJECTS.ownerOf(4) != address(0), "owner missing");
        require(address(DIRECTORY.controllerOf(4)) != address(0), "controller missing");
        require(address(DIRECTORY.primaryTerminalOf(4, JBConstants.NATIVE_TOKEN)) != address(0), "primary missing");

        IJBTerminal[] memory terminals = DIRECTORY.terminalsOf(4);
        bool terminalFound;

        for (uint256 i; i < terminals.length; i++) {
            if (address(terminals[i]) == address(TERMINAL)) {
                terminalFound = true;
                break;
            }
        }

        require(terminalFound, "jbmultiterminal missing");
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
