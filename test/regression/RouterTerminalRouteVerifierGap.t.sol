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
import {JBRouterTerminalGateway} from "@bananapus/router-terminal-v6/src/JBRouterTerminalGateway.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";

contract RouterTerminalRouteVerifierGapTest is Test {
    function test_routeVerifierEnsuresRegistryResolvesCanonicalProjectsToRouter() public {
        address routerTerminal = address(new MockCodeBearingContract());
        address primaryNativeTerminal = address(new MockCodeBearingContract());
        address hookDeployer = address(new MockCodeBearingContract());
        address hookStore = address(new MockCodeBearingContract());
        MockHookProjectDeployer hookProjectDeployer = new MockHookProjectDeployer({hookDeployer_: hookDeployer});

        address gateway = address(new MockRouterTerminalGateway(routerTerminal));
        MockRouterTerminalRegistry registry =
            new MockRouterTerminalRegistry({defaultTerminal_: gateway, resolvedTerminal_: address(0)});
        MockDirectory directory = new MockDirectory({
            listedTerminal_: address(registry),
            primaryNativeTerminal_: primaryNativeTerminal,
            unexpectedTerminal_: address(0)
        });
        // Router must NOT be globally feeless (the global grant was dropped) — feed an unrelated
        // feeless address so isFeelessFor(router) returns false.
        MockFeelessAddresses feelessAddresses = new MockFeelessAddresses({feeless_: address(0)});

        VerifyRouterTerminalRouteHarness harness = new VerifyRouterTerminalRouteHarness();
        harness.setRouteMocks({
            routerTerminalRegistry_: address(registry),
            routerTerminal_: routerTerminal,
            routerTerminalGateway_: gateway,
            directory_: address(directory),
            terminal_: primaryNativeTerminal,
            feelessAddresses_: address(feelessAddresses),
            hookDeployer_: hookDeployer,
            hookStore_: hookStore,
            hookProjectDeployer_: address(hookProjectDeployer)
        });

        assertEq(address(registry.defaultTerminal()), gateway);
        assertEq(address(registry.terminalOf(1)), address(0));

        // Coverage: Category 10 asserts the registry resolves each canonical project to the
        // canonical gateway. The mock returns address(0), so the verifier rejects.
        harness.verifyHookRegistries();
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "NANA(1) RouterTerminalRegistry.terminalOf == canonical RouterTerminalGateway"
            )
        );
        harness.verifyRoutes();
    }

    function test_hookRegistriesVerifierRejectsGloballyFeelessRouterTerminal() public {
        address routerTerminal = address(new MockCodeBearingContract());
        address primaryNativeTerminal = address(new MockCodeBearingContract());
        address hookDeployer = address(new MockCodeBearingContract());
        address hookStore = address(new MockCodeBearingContract());
        MockHookProjectDeployer hookProjectDeployer = new MockHookProjectDeployer({hookDeployer_: hookDeployer});

        address gateway = address(new MockRouterTerminalGateway(routerTerminal));
        MockRouterTerminalRegistry registry =
            new MockRouterTerminalRegistry({defaultTerminal_: gateway, resolvedTerminal_: gateway});
        MockDirectory directory = new MockDirectory({
            listedTerminal_: address(registry),
            primaryNativeTerminal_: primaryNativeTerminal,
            unexpectedTerminal_: address(0)
        });
        // Mock the router terminal as still globally feeless — the verifier must reject this
        // because the global grant was dropped in deploy.
        MockFeelessAddresses feelessAddresses = new MockFeelessAddresses({feeless_: routerTerminal});

        VerifyRouterTerminalRouteHarness harness = new VerifyRouterTerminalRouteHarness();
        harness.setRouteMocks({
            routerTerminalRegistry_: address(registry),
            routerTerminal_: routerTerminal,
            routerTerminalGateway_: gateway,
            directory_: address(directory),
            terminal_: primaryNativeTerminal,
            feelessAddresses_: address(feelessAddresses),
            hookDeployer_: hookDeployer,
            hookStore_: hookStore,
            hookProjectDeployer_: address(hookProjectDeployer)
        });

        vm.expectRevert(
            abi.encodeWithSelector(Verify.Verify_CriticalCheckFailed.selector, "RouterTerminal is NOT globally feeless")
        );
        harness.verifyHookRegistries();
    }

    function test_hookRegistriesVerifierAllowsUnsetDefaultWhenRouterTerminalAbsent() public {
        address primaryNativeTerminal = address(new MockCodeBearingContract());
        address hookDeployer = address(new MockCodeBearingContract());
        address hookStore = address(new MockCodeBearingContract());
        MockHookProjectDeployer hookProjectDeployer = new MockHookProjectDeployer({hookDeployer_: hookDeployer});

        MockRouterTerminalRegistry registry =
            new MockRouterTerminalRegistry({defaultTerminal_: address(0), resolvedTerminal_: address(0)});
        MockDirectory directory = new MockDirectory({
            listedTerminal_: address(registry),
            primaryNativeTerminal_: primaryNativeTerminal,
            unexpectedTerminal_: address(0)
        });

        VerifyRouterTerminalRouteHarness harness = new VerifyRouterTerminalRouteHarness();
        harness.setRouteMocks({
            routerTerminalRegistry_: address(registry),
            routerTerminal_: address(0),
            routerTerminalGateway_: address(0),
            directory_: address(directory),
            terminal_: primaryNativeTerminal,
            feelessAddresses_: address(new MockFeelessAddresses({feeless_: address(0)})),
            hookDeployer_: hookDeployer,
            hookStore_: hookStore,
            hookProjectDeployer_: address(hookProjectDeployer)
        });

        assertEq(address(registry.defaultTerminal()), address(0));

        // Coverage: chains that skip the Uniswap stack still deploy the registry for deterministic
        // constructor args, but intentionally leave the router terminal/default unset.
        harness.verifyHookRegistries();
    }

    function test_routeVerifierRejectsUnexpectedCanonicalProjectTerminals() public {
        address routerTerminal = address(new MockCodeBearingContract());
        address primaryNativeTerminal = address(new MockCodeBearingContract());
        address unexpectedTerminal = address(new MockCodeBearingContract());

        address gateway = address(new MockRouterTerminalGateway(routerTerminal));
        MockRouterTerminalRegistry registry =
            new MockRouterTerminalRegistry({defaultTerminal_: gateway, resolvedTerminal_: gateway});
        MockDirectory directory = new MockDirectory({
            listedTerminal_: address(registry),
            primaryNativeTerminal_: primaryNativeTerminal,
            unexpectedTerminal_: unexpectedTerminal
        });

        VerifyRouterTerminalRouteHarness harness = new VerifyRouterTerminalRouteHarness();
        harness.setRouteMocks({
            routerTerminalRegistry_: address(registry),
            routerTerminal_: routerTerminal,
            routerTerminalGateway_: gateway,
            directory_: address(directory),
            terminal_: primaryNativeTerminal,
            feelessAddresses_: address(new MockFeelessAddresses({feeless_: address(0)})),
            hookDeployer_: address(new MockCodeBearingContract()),
            hookStore_: address(new MockCodeBearingContract()),
            hookProjectDeployer_: address(
                new MockHookProjectDeployer({hookDeployer_: address(new MockCodeBearingContract())})
            )
        });

        IJBTerminal[] memory terminals = directory.terminalsOf(1);
        assertEq(terminals.length, 3);
        assertEq(address(terminals[2]), unexpectedTerminal);

        // Coverage: Category 10 now requires the terminal list to be exactly
        // {JBMultiTerminal, JBRouterTerminalRegistry} (length 2). An unexpected third terminal
        // rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "NANA(1) terminal list has exactly 2 entries"
            )
        );
        harness.verifyRoutes();
    }

    function test_hookRegistriesVerifierRejectsRawRouterAsDefault() public {
        address routerTerminal = address(new MockCodeBearingContract());
        address gateway = address(new MockRouterTerminalGateway(routerTerminal));
        address primaryNativeTerminal = address(new MockCodeBearingContract());

        // The registry still serves the raw router: a custody-less rollout the verifier must refuse.
        MockRouterTerminalRegistry registry =
            new MockRouterTerminalRegistry({defaultTerminal_: routerTerminal, resolvedTerminal_: routerTerminal});
        MockDirectory directory = new MockDirectory({
            listedTerminal_: address(registry),
            primaryNativeTerminal_: primaryNativeTerminal,
            unexpectedTerminal_: address(0)
        });

        VerifyRouterTerminalRouteHarness harness =
            _harnessFor({registry: registry, routerTerminal: routerTerminal, gateway: gateway, directory: directory});

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "RouterTerminalRegistry.defaultTerminal == JBRouterTerminalGateway"
            )
        );
        harness.verifyHookRegistries();
    }

    function test_hookRegistriesVerifierRejectsSelectableRawRouter() public {
        address routerTerminal = address(new MockCodeBearingContract());
        address gateway = address(new MockRouterTerminalGateway(routerTerminal));
        address primaryNativeTerminal = address(new MockCodeBearingContract());

        MockRouterTerminalRegistry registry =
            new MockRouterTerminalRegistry({defaultTerminal_: gateway, resolvedTerminal_: gateway});
        // A project could pick the raw router and skip custody.
        registry.setAllowedTerminal(routerTerminal);
        MockDirectory directory = new MockDirectory({
            listedTerminal_: address(registry),
            primaryNativeTerminal_: primaryNativeTerminal,
            unexpectedTerminal_: address(0)
        });

        VerifyRouterTerminalRouteHarness harness =
            _harnessFor({registry: registry, routerTerminal: routerTerminal, gateway: gateway, directory: directory});

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "raw JBRouterTerminal is NOT selectable in RouterTerminalRegistry"
            )
        );
        harness.verifyHookRegistries();
    }

    function test_routeVerifierAcceptsPreviousRouterForUnmigratedProjectsOnlyWhenDeclared() public {
        address routerTerminal = address(new MockCodeBearingContract());
        address previousRouter = address(new MockCodeBearingContract());
        address gateway = address(new MockRouterTerminalGateway(routerTerminal));
        address primaryNativeTerminal = address(new MockCodeBearingContract());

        // The fee project is migrated by the infra proposal; the other canonical projects still resolve to the
        // retired router until their operators move them.
        MockRouterTerminalRegistry registry =
            new MockRouterTerminalRegistry({defaultTerminal_: gateway, resolvedTerminal_: previousRouter});
        registry.setFeeProjectTerminal(gateway);
        MockDirectory directory = new MockDirectory({
            listedTerminal_: address(registry),
            primaryNativeTerminal_: primaryNativeTerminal,
            unexpectedTerminal_: address(0)
        });

        VerifyRouterTerminalRouteHarness harness =
            _harnessFor({registry: registry, routerTerminal: routerTerminal, gateway: gateway, directory: directory});

        // Undeclared, an unmigrated project is a routing fault.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "CPN(2) RouterTerminalRegistry.terminalOf == canonical RouterTerminalGateway"
            )
        );
        harness.verifyRoutes();

        // Declared, the retired router is accepted for projects other than the fee project.
        harness.setPreviousRouterTerminal(previousRouter);
        harness.verifyRoutes();
    }

    function test_routeVerifierNeverAcceptsPreviousRouterForFeeProject() public {
        address routerTerminal = address(new MockCodeBearingContract());
        address previousRouter = address(new MockCodeBearingContract());
        address gateway = address(new MockRouterTerminalGateway(routerTerminal));
        address primaryNativeTerminal = address(new MockCodeBearingContract());

        MockRouterTerminalRegistry registry =
            new MockRouterTerminalRegistry({defaultTerminal_: gateway, resolvedTerminal_: previousRouter});
        MockDirectory directory = new MockDirectory({
            listedTerminal_: address(registry),
            primaryNativeTerminal_: primaryNativeTerminal,
            unexpectedTerminal_: address(0)
        });

        VerifyRouterTerminalRouteHarness harness =
            _harnessFor({registry: registry, routerTerminal: routerTerminal, gateway: gateway, directory: directory});
        harness.setPreviousRouterTerminal(previousRouter);

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "NANA(1) RouterTerminalRegistry.terminalOf == canonical RouterTerminalGateway"
            )
        );
        harness.verifyRoutes();
    }

    function _harnessFor(
        MockRouterTerminalRegistry registry,
        address routerTerminal,
        address gateway,
        MockDirectory directory
    )
        internal
        returns (VerifyRouterTerminalRouteHarness harness)
    {
        address hookDeployer = address(new MockCodeBearingContract());
        harness = new VerifyRouterTerminalRouteHarness();
        harness.setRouteMocks({
            routerTerminalRegistry_: address(registry),
            routerTerminal_: routerTerminal,
            routerTerminalGateway_: gateway,
            directory_: address(directory),
            terminal_: address(directory.primaryTerminalOf(1, address(0))),
            feelessAddresses_: address(new MockFeelessAddresses({feeless_: address(0)})),
            hookDeployer_: hookDeployer,
            hookStore_: address(new MockCodeBearingContract()),
            hookProjectDeployer_: address(new MockHookProjectDeployer({hookDeployer_: hookDeployer}))
        });
    }
}

contract VerifyRouterTerminalRouteHarness is Verify {
    function setRouteMocks(
        address routerTerminalRegistry_,
        address routerTerminal_,
        address routerTerminalGateway_,
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
        routerTerminalGateway = JBRouterTerminalGateway(payable(routerTerminalGateway_));
        directory = JBDirectory(directory_);
        terminal = JBMultiTerminal(payable(terminal_));
        feelessAddresses = JBFeelessAddresses(feelessAddresses_);
        hookDeployer = JB721TiersHookDeployer(hookDeployer_);
        hookStore = JB721TiersHookStore(hookStore_);
        hookProjectDeployer = JB721TiersHookProjectDeployer(hookProjectDeployer_);
    }

    function setPreviousRouterTerminal(address previous) external {
        previousRouterTerminal = previous;
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
    IJBTerminal internal _feeProjectTerminal;
    bool internal _hasFeeProjectTerminal;
    IJBTerminal internal _allowedTerminal;

    constructor(address defaultTerminal_, address resolvedTerminal_) {
        _defaultTerminal = IJBTerminal(defaultTerminal_);
        _resolvedTerminal = IJBTerminal(resolvedTerminal_);
    }

    /// @notice Resolve the fee project (1) differently from every other project.
    function setFeeProjectTerminal(address terminal) external {
        _feeProjectTerminal = IJBTerminal(terminal);
        _hasFeeProjectTerminal = true;
    }

    /// @notice Mark one terminal as selectable, on top of the default (which the real registry auto-allows).
    function setAllowedTerminal(address terminal) external {
        _allowedTerminal = IJBTerminal(terminal);
    }

    function defaultTerminal() external view returns (IJBTerminal) {
        return _defaultTerminal;
    }

    function defaultTerminalFor(uint256) external view returns (IJBTerminal) {
        return _resolvedTerminal;
    }

    function isTerminalAllowed(IJBTerminal terminal) external view returns (bool) {
        return terminal == _defaultTerminal || terminal == _allowedTerminal;
    }

    function terminalOf(uint256 projectId) external view returns (IJBTerminal) {
        if (projectId == 1 && _hasFeeProjectTerminal) return _feeProjectTerminal;
        return _resolvedTerminal;
    }
}

contract MockRouterTerminalGateway {
    address public immutable ROUTER;

    constructor(address router) {
        ROUTER = router;
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

    function isFeelessFor(address addr, uint256, address) external view returns (bool) {
        return addr == _feeless;
    }
}
