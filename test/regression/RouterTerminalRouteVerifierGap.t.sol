// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBFeelessAddresses} from "@bananapus/core-v6/src/JBFeelessAddresses.sol";
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHookProjectDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookProjectDeployer.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JBDirectory} from "@bananapus/core-v6/src/JBDirectory.sol";
import {JBMultiTerminal} from "@bananapus/core-v6/src/JBMultiTerminal.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";

contract RouterTerminalRouteVerifierGapTest is Test {
    function test_routeVerifierEnsuresRegistryResolvesCanonicalProjectsToRouter() public {
        address routerTerminal = address(new MockCodeBearingContract());
        address primaryNativeTerminal = address(new MockCodeBearingContract());
        address hookDeployer = address(new MockCodeBearingContract());
        address hookStore = address(new MockCodeBearingContract());
        MockHookProjectDeployer hookProjectDeployer = new MockHookProjectDeployer({hookDeployer_: hookDeployer});

        MockRouterTerminalRegistry registry =
            new MockRouterTerminalRegistry({defaultTerminal_: routerTerminal, resolvedTerminal_: address(0)});
        MockDirectory directory = new MockDirectory({
            listedTerminal_: address(registry),
            primaryNativeTerminal_: primaryNativeTerminal,
            unexpectedTerminal_: address(0)
        });
        MockFeelessAddresses feelessAddresses = new MockFeelessAddresses({feeless_: routerTerminal});

        VerifyRouterTerminalRouteHarness harness = new VerifyRouterTerminalRouteHarness();
        harness.setRouteMocks({
            routerTerminalRegistry_: address(registry),
            routerTerminal_: routerTerminal,
            directory_: address(directory),
            terminal_: primaryNativeTerminal,
            feelessAddresses_: address(feelessAddresses),
            hookDeployer_: hookDeployer,
            hookStore_: hookStore,
            hookProjectDeployer_: address(hookProjectDeployer)
        });

        assertEq(address(registry.defaultTerminal()), routerTerminal);
        assertEq(address(registry.terminalOf(1)), address(0));

        // BL fix: Category 10 now asserts the registry resolves each canonical project to the
        // canonical router terminal. The mock returns address(0), so the verifier rejects.
        harness.verifyHookRegistries();
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "NANA(1) RouterTerminalRegistry.terminalOf == canonical RouterTerminal"
            )
        );
        harness.verifyRoutes();
    }

    function test_routeVerifierRejectsUnexpectedCanonicalProjectTerminals() public {
        address routerTerminal = address(new MockCodeBearingContract());
        address primaryNativeTerminal = address(new MockCodeBearingContract());
        address unexpectedTerminal = address(new MockCodeBearingContract());

        MockRouterTerminalRegistry registry =
            new MockRouterTerminalRegistry({defaultTerminal_: routerTerminal, resolvedTerminal_: routerTerminal});
        MockDirectory directory = new MockDirectory({
            listedTerminal_: address(registry),
            primaryNativeTerminal_: primaryNativeTerminal,
            unexpectedTerminal_: unexpectedTerminal
        });

        VerifyRouterTerminalRouteHarness harness = new VerifyRouterTerminalRouteHarness();
        harness.setRouteMocks({
            routerTerminalRegistry_: address(registry),
            routerTerminal_: routerTerminal,
            directory_: address(directory),
            terminal_: primaryNativeTerminal,
            feelessAddresses_: address(new MockFeelessAddresses({feeless_: routerTerminal})),
            hookDeployer_: address(new MockCodeBearingContract()),
            hookStore_: address(new MockCodeBearingContract()),
            hookProjectDeployer_: address(
                new MockHookProjectDeployer({hookDeployer_: address(new MockCodeBearingContract())})
            )
        });

        IJBTerminal[] memory terminals = directory.terminalsOf(1);
        assertEq(terminals.length, 3);
        assertEq(address(terminals[2]), unexpectedTerminal);

        // BL fix: Category 10 now requires the terminal list to be exactly
        // {JBMultiTerminal, JBRouterTerminalRegistry} (length 2). An unexpected third terminal
        // rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "NANA(1) terminal list has exactly 2 entries"
            )
        );
        harness.verifyRoutes();
    }
}

contract VerifyRouterTerminalRouteHarness is Verify {
    function setRouteMocks(
        address routerTerminalRegistry_,
        address routerTerminal_,
        address directory_,
        address terminal_,
        address feelessAddresses_,
        address hookDeployer_,
        address hookStore_,
        address hookProjectDeployer_
    )
        external
    {
        routerTerminalRegistry = JBRouterTerminalRegistry(payable(routerTerminalRegistry_));
        routerTerminal = JBRouterTerminal(payable(routerTerminal_));
        directory = JBDirectory(directory_);
        terminal = JBMultiTerminal(payable(terminal_));
        feelessAddresses = JBFeelessAddresses(feelessAddresses_);
        hookDeployer = JB721TiersHookDeployer(hookDeployer_);
        hookStore = JB721TiersHookStore(hookStore_);
        hookProjectDeployer = JB721TiersHookProjectDeployer(hookProjectDeployer_);
    }

    function verifyHookRegistries() external {
        _verifyHookRegistries();
    }

    function verifyRoutes() external {
        _verifyRoutes();
    }
}

contract MockCodeBearingContract {}

contract MockRouterTerminalRegistry {
    IJBTerminal internal immutable _defaultTerminal;
    IJBTerminal internal immutable _resolvedTerminal;

    constructor(address defaultTerminal_, address resolvedTerminal_) {
        _defaultTerminal = IJBTerminal(defaultTerminal_);
        _resolvedTerminal = IJBTerminal(resolvedTerminal_);
    }

    function defaultTerminal() external view returns (IJBTerminal) {
        return _defaultTerminal;
    }

    function defaultTerminalFor(uint256) external view returns (IJBTerminal) {
        return _resolvedTerminal;
    }

    function terminalOf(uint256) external view returns (IJBTerminal) {
        return _resolvedTerminal;
    }
}

contract MockHookProjectDeployer {
    address internal immutable _hookDeployer;

    constructor(address hookDeployer_) {
        _hookDeployer = hookDeployer_;
    }

    function HOOK_DEPLOYER() external view returns (address) {
        return _hookDeployer;
    }
}

contract MockDirectory {
    IJBTerminal internal immutable _listedTerminal;
    IJBTerminal internal immutable _primaryNativeTerminal;
    IJBTerminal internal immutable _unexpectedTerminal;

    constructor(address listedTerminal_, address primaryNativeTerminal_, address unexpectedTerminal_) {
        _listedTerminal = IJBTerminal(listedTerminal_);
        _primaryNativeTerminal = IJBTerminal(primaryNativeTerminal_);
        _unexpectedTerminal = IJBTerminal(unexpectedTerminal_);
    }

    function terminalsOf(uint256) external view returns (IJBTerminal[] memory terminals) {
        if (address(_unexpectedTerminal) == address(0)) {
            terminals = new IJBTerminal[](2);
            terminals[0] = _primaryNativeTerminal;
            terminals[1] = _listedTerminal;
        } else {
            terminals = new IJBTerminal[](3);
            terminals[0] = _primaryNativeTerminal;
            terminals[1] = _listedTerminal;
            terminals[2] = _unexpectedTerminal;
        }
    }

    function primaryTerminalOf(uint256, address) external view returns (IJBTerminal) {
        return _primaryNativeTerminal;
    }
}

contract MockFeelessAddresses {
    address internal immutable _feeless;

    constructor(address feeless_) {
        _feeless = feeless_;
    }

    function isFeelessFor(address addr, uint256) external view returns (bool) {
        return addr == _feeless;
    }
}
