// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBController} from "@bananapus/core-v6/src/JBController.sol";
import {JBDirectory} from "@bananapus/core-v6/src/JBDirectory.sol";
import {JBMultiTerminal} from "@bananapus/core-v6/src/JBMultiTerminal.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract CanonicalControllerVerifierGapTest is Test {
    function test_directoryVerifierRejectsNoncanonicalProjectControllers() public {
        address canonicalController = address(new MockCodeBearingContract());
        address fakeController = address(new MockCodeBearingContract());
        address projects = address(new MockCodeBearingContract());
        address terminal = address(new MockCodeBearingContract());

        MockDirectoryWrongController directory = new MockDirectoryWrongController({
            projects_: projects,
            allowedFirstController_: canonicalController,
            projectController_: fakeController,
            primaryTerminal_: terminal
        });

        VerifyCanonicalControllerHarness harness = new VerifyCanonicalControllerHarness();
        harness.setDirectoryMocks({
            projects_: projects, directory_: address(directory), controller_: canonicalController, terminal_: terminal
        });

        assertTrue(fakeController != canonicalController, "setup must use wrong controller");
        assertEq(address(directory.controllerOf(1)), fakeController, "project resolves to fake controller");

        // Coverage: Category 2 now asserts directory.controllerOf(projectId) == canonical
        // controller. A noncanonical controller pointer rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "NANA(1) controller == canonical JBController"
            )
        );
        harness.verifyDirectoryWiring();
    }
}

contract VerifyCanonicalControllerHarness is Verify {
    function setDirectoryMocks(address projects_, address directory_, address controller_, address terminal_) external {
        projects = JBProjects(projects_);
        directory = JBDirectory(directory_);
        controller = JBController(controller_);
        terminal = JBMultiTerminal(payable(terminal_));
    }

    function verifyDirectoryWiring() external {
        _verifyDirectoryWiring();
    }
}

contract MockCodeBearingContract {}

contract MockDirectoryWrongController {
    JBProjects internal immutable _projects;
    IERC165 internal immutable _allowedFirstController;
    IERC165 internal immutable _projectController;
    IJBTerminal internal immutable _primaryTerminal;

    constructor(
        address projects_,
        address allowedFirstController_,
        address projectController_,
        address primaryTerminal_
    ) {
        _projects = JBProjects(projects_);
        _allowedFirstController = IERC165(allowedFirstController_);
        _projectController = IERC165(projectController_);
        _primaryTerminal = IJBTerminal(primaryTerminal_);
    }

    function PROJECTS() external view returns (JBProjects) {
        return _projects;
    }

    function isAllowedToSetFirstController(address controller) external view returns (bool) {
        return controller == address(_allowedFirstController);
    }

    function controllerOf(uint256) external view returns (IERC165) {
        return _projectController;
    }

    function primaryTerminalOf(uint256, address) external view returns (IJBTerminal) {
        return _primaryTerminal;
    }

    function terminalsOf(uint256) external view returns (IJBTerminal[] memory terminals) {
        terminals = new IJBTerminal[](1);
        terminals[0] = _primaryTerminal;
    }
}
