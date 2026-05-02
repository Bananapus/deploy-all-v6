// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";

contract ResumeRevProjectThreeSquatTest is Test {
    uint256 internal constant REV_PROJECT_ID = 3;

    address internal attacker = makeAddr("attacker");
    address internal controller = makeAddr("controller");
    address internal jbMultiTerminal = makeAddr("jbMultiTerminal");
    address internal suckerRegistry = makeAddr("suckerRegistry");
    address internal hookDeployer = makeAddr("hookDeployer");
    address internal ctPublisher = makeAddr("ctPublisher");

    MockProjects internal projects;
    MockDirectory internal directory;
    ResumeRevnetHarness internal harness;

    function setUp() public {
        projects = new MockProjects();
        directory = new MockDirectory();
        harness = new ResumeRevnetHarness(IJBProjects(address(projects)), IJBDirectory(address(directory)));

        projects.setCount(REV_PROJECT_ID);
        projects.setOwner(REV_PROJECT_ID, attacker);
        projects.setApprovedCaller(REV_PROJECT_ID, address(harness));

        directory.setController(REV_PROJECT_ID, controller);
        directory.setPrimaryTerminal(REV_PROJECT_ID, jbMultiTerminal);

        address[] memory terminals = new address[](1);
        terminals[0] = jbMultiTerminal;
        directory.setTerminals(REV_PROJECT_ID, terminals);
    }

    function test_resumeAcceptsConfiguredAttackerProjectThreeIfResumeCallerIsPreapproved() public {
        (MockREVDeployer revDeployer, MockREVOwner revOwner, MockREVLoans revLoans) =
            harness.resumeRevnet(controller, suckerRegistry, hookDeployer, ctPublisher);

        assertEq(projects.ownerOf(REV_PROJECT_ID), attacker, "attacker keeps project three");
        assertEq(revDeployer.FEE_REVNET_ID(), REV_PROJECT_ID, "deployer binds canonical REV fees to project three");
        assertEq(revOwner.FEE_REVNET_ID(), REV_PROJECT_ID, "owner binds canonical REV fees to project three");
        assertEq(revLoans.REV_ID(), REV_PROJECT_ID, "loan system binds canonical REV loans to project three");

        // These are the current REV-specific checks Verify.s.sol performs.
        assertEq(address(directory.controllerOf(REV_PROJECT_ID)), controller, "project three keeps generic wiring");
        assertEq(
            address(directory.primaryTerminalOf(REV_PROJECT_ID, JBConstants.NATIVE_TOKEN)),
            jbMultiTerminal,
            "project three keeps a primary terminal"
        );
        assertEq(address(directory.terminalsOf(REV_PROJECT_ID)[0]), jbMultiTerminal, "project three keeps JB wiring");
        assertEq(revDeployer.CONTROLLER(), controller, "verifier-visible controller wiring still matches");
        assertEq(revDeployer.SUCKER_REGISTRY(), suckerRegistry, "verifier-visible registry wiring still matches");
        assertEq(revDeployer.HOOK_DEPLOYER(), hookDeployer, "verifier-visible hook deployer still matches");
        assertEq(revDeployer.PUBLISHER(), ctPublisher, "verifier-visible publisher still matches");
        assertEq(revDeployer.LOANS(), address(revLoans), "verifier-visible loans wiring still matches");
        assertEq(revDeployer.OWNER(), address(revOwner), "verifier-visible owner wiring still matches");
        assertEq(address(revOwner.DEPLOYER()), address(revDeployer), "rev owner points back to rev deployer");
    }
}

contract ResumeRevnetHarness {
    IJBProjects internal immutable PROJECTS;
    IJBDirectory internal immutable DIRECTORY;

    constructor(IJBProjects projects, IJBDirectory directory) {
        PROJECTS = projects;
        DIRECTORY = directory;
    }

    function resumeRevnet(
        address controller,
        address suckerRegistry,
        address hookDeployer,
        address publisher
    )
        external
        returns (MockREVDeployer revDeployer, MockREVOwner revOwner, MockREVLoans revLoans)
    {
        uint256 revProjectId = _ensureProjectExists(REV_PROJECT_ID());

        revLoans = new MockREVLoans(revProjectId);
        revOwner = new MockREVOwner(revProjectId);
        revDeployer = new MockREVDeployer(
            controller, suckerRegistry, hookDeployer, publisher, address(revLoans), address(revOwner), revProjectId
        );
        revOwner.setDeployer(revDeployer);

        PROJECTS.approve(address(revDeployer), revProjectId);
    }

    function REV_PROJECT_ID() public pure returns (uint256) {
        return 3;
    }

    function _ensureProjectExists(uint256 expectedProjectId) internal returns (uint256) {
        uint256 count = PROJECTS.count();
        if (count >= expectedProjectId) {
            if (address(DIRECTORY.controllerOf(expectedProjectId)) != address(0)) {
                return expectedProjectId;
            }
            if (PROJECTS.ownerOf(expectedProjectId) != address(this)) revert("Resume_ProjectNotOwned");
            return expectedProjectId;
        }

        revert("Resume_ProjectIdMismatch");
    }
}

contract MockREVDeployer {
    address public immutable CONTROLLER;
    address public immutable SUCKER_REGISTRY;
    address public immutable HOOK_DEPLOYER;
    address public immutable PUBLISHER;
    address public immutable LOANS;
    address public immutable OWNER;
    uint256 public immutable FEE_REVNET_ID;

    constructor(
        address controller,
        address suckerRegistry,
        address hookDeployer,
        address publisher,
        address loans,
        address owner,
        uint256 feeRevnetId
    ) {
        CONTROLLER = controller;
        SUCKER_REGISTRY = suckerRegistry;
        HOOK_DEPLOYER = hookDeployer;
        PUBLISHER = publisher;
        LOANS = loans;
        OWNER = owner;
        FEE_REVNET_ID = feeRevnetId;
    }
}

contract MockREVOwner {
    uint256 public immutable FEE_REVNET_ID;
    MockREVDeployer public DEPLOYER;

    constructor(uint256 feeRevnetId) {
        FEE_REVNET_ID = feeRevnetId;
    }

    function setDeployer(MockREVDeployer deployer) external {
        DEPLOYER = deployer;
    }
}

contract MockREVLoans {
    uint256 public immutable REV_ID;

    constructor(uint256 revId) {
        REV_ID = revId;
    }
}

contract MockProjects {
    mapping(uint256 => address) internal _ownerOf;
    mapping(uint256 => address) internal _approvedCallerOf;
    uint256 internal _count;

    function setCount(uint256 newCount) external {
        _count = newCount;
    }

    function setOwner(uint256 projectId, address owner) external {
        _ownerOf[projectId] = owner;
    }

    function setApprovedCaller(uint256 projectId, address caller) external {
        _approvedCallerOf[projectId] = caller;
    }

    function count() external view returns (uint256) {
        return _count;
    }

    function ownerOf(uint256 projectId) external view returns (address) {
        return _ownerOf[projectId];
    }

    function approve(address, uint256 projectId) external {
        address owner = _ownerOf[projectId];
        if (msg.sender != owner && msg.sender != _approvedCallerOf[projectId]) revert("not authorized");
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
