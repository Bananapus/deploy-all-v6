// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBController} from "@bananapus/core-v6/src/JBController.sol";
import {JBDirectory} from "@bananapus/core-v6/src/JBDirectory.sol";
import {JBMultiTerminal} from "@bananapus/core-v6/src/JBMultiTerminal.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract TerminalAccountingContextVerifierGapTest is Test {
    function test_routeVerifierRejectsPrimaryNativeTerminalWithoutNativeAccountingContext() public {
        address projects = address(new MockCodeBearingContract());
        address controller = address(new MockCodeBearingContract());
        MockTerminalWithoutNativeContext terminal = new MockTerminalWithoutNativeContext();
        address routerRegistry = address(new MockCodeBearingContract());

        MockDirectoryWithTerminalNoContext directory = new MockDirectoryWithTerminalNoContext({
            projects_: projects,
            controller_: controller,
            primaryNativeTerminal_: address(terminal),
            routerRegistry_: routerRegistry
        });

        VerifyTerminalAccountingContextHarness harness = new VerifyTerminalAccountingContextHarness();
        harness.setMocks({
            projects_: projects,
            directory_: address(directory),
            controller_: controller,
            terminal_: address(terminal),
            routerRegistry_: routerRegistry
        });

        JBAccountingContext memory context =
            terminal.accountingContextForTokenOf({projectId: 1, token: JBConstants.NATIVE_TOKEN});
        assertEq(context.token, address(0), "setup intentionally omits native accounting context");

        // CQ fix: Category 2 now also reads the live accounting context for the native token on
        // each canonical project. The mock omits the native context (zero token field), so the
        // verifier rejects on the token-sentinel check.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "NANA(1) native accounting context token == NATIVE_TOKEN"
            )
        );
        harness.verifyDirectoryAndRoutes();
    }
}

contract VerifyTerminalAccountingContextHarness is Verify {
    function setMocks(
        address projects_,
        address directory_,
        address controller_,
        address terminal_,
        address routerRegistry_
    )
        external
    {
        projects = JBProjects(projects_);
        directory = JBDirectory(directory_);
        controller = JBController(controller_);
        terminal = JBMultiTerminal(payable(terminal_));
        routerTerminalRegistry = JBRouterTerminalRegistry(payable(routerRegistry_));
    }

    function verifyDirectoryAndRoutes() external {
        _verifyDirectoryWiring();
        _verifyRoutes();
    }
}

contract MockCodeBearingContract {}

contract MockDirectoryWithTerminalNoContext {
    JBProjects internal immutable _projects;
    IERC165 internal immutable _controller;
    IJBTerminal internal immutable _primaryNativeTerminal;
    IJBTerminal internal immutable _routerRegistry;

    constructor(address projects_, address controller_, address primaryNativeTerminal_, address routerRegistry_) {
        _projects = JBProjects(projects_);
        _controller = IERC165(controller_);
        _primaryNativeTerminal = IJBTerminal(primaryNativeTerminal_);
        _routerRegistry = IJBTerminal(routerRegistry_);
    }

    function PROJECTS() external view returns (JBProjects) {
        return _projects;
    }

    function isAllowedToSetFirstController(address controller) external view returns (bool) {
        return controller == address(_controller);
    }

    function controllerOf(uint256) external view returns (IERC165) {
        return _controller;
    }

    function primaryTerminalOf(uint256, address) external view returns (IJBTerminal) {
        return _primaryNativeTerminal;
    }

    function terminalsOf(uint256) external view returns (IJBTerminal[] memory terminals) {
        terminals = new IJBTerminal[](2);
        terminals[0] = _primaryNativeTerminal;
        terminals[1] = _routerRegistry;
    }
}

contract MockTerminalWithoutNativeContext {
    function accountingContextForTokenOf(
        uint256 projectId,
        address token
    )
        external
        pure
        returns (JBAccountingContext memory context)
    {
        projectId;
        token;
        return context;
    }
}
