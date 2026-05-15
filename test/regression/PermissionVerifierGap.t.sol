// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBController} from "@bananapus/core-v6/src/JBController.sol";
import {JBDirectory} from "@bananapus/core-v6/src/JBDirectory.sol";
import {JBMultiTerminal} from "@bananapus/core-v6/src/JBMultiTerminal.sol";
import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";

contract PermissionVerifierGapTest is Test {
    function test_permissionsVerifierRejectsMissingRuntimeWildcardGrant() public {
        address trustedForwarder = makeAddr("trusted forwarder");
        JBPermissions permissions = new JBPermissions(trustedForwarder);

        address revDeployer = makeAddr("rev deployer");
        address revLoans = makeAddr("rev loans");

        // O's prior checks call .PERMISSIONS() on revDeployer / revLoans. Stub those to satisfy O
        // so the test reaches P's grant check rather than reverting on a missing getter.
        vm.mockCall(revDeployer, abi.encodeWithSignature("PERMISSIONS()"), abi.encode(address(permissions)));
        vm.mockCall(revLoans, abi.encodeWithSignature("PERMISSIONS()"), abi.encode(address(permissions)));
        // O's expanded ERC-2771 sweep also calls trustedForwarder() on the same surfaces. Stub
        // those so the verifier reaches P's grant check.
        vm.mockCall(revDeployer, abi.encodeWithSignature("trustedForwarder()"), abi.encode(trustedForwarder));
        vm.mockCall(revLoans, abi.encodeWithSignature("trustedForwarder()"), abi.encode(trustedForwarder));

        assertFalse(
            permissions.hasPermission({
                operator: revLoans,
                account: revDeployer,
                projectId: 0,
                permissionId: JBPermissionIds.USE_ALLOWANCE,
                includeRoot: true,
                includeWildcardProjectId: true
            }),
            "setup must omit expected REVLoans wildcard grant"
        );

        VerifyPermissionHarness harness = new VerifyPermissionHarness();
        harness.setPermissionMocks({
            permissions_: address(permissions),
            controller_: address(new MockPermissioned2771(address(permissions), trustedForwarder)),
            terminal_: address(new MockPermissioned2771(address(permissions), trustedForwarder)),
            directory_: address(new MockPermissioned(address(permissions))),
            projects_: address(new MockTrustedForwarder(trustedForwarder)),
            expectedTrustedForwarder_: trustedForwarder
        });

        // P: enable the runtime-grants check by wiring the REV stack pointers.
        harness.setPermissionGrantMocks({revDeployer_: revDeployer, revLoans_: revLoans, buybackRegistry_: address(0)});

        // P fix: _verifyPermissionGrants now asserts REVLoans has the wildcard USE_ALLOWANCE grant
        // from REVDeployer. The harness omits this grant, so the verifier rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "Permissions: REVLoans wildcard USE_ALLOWANCE granted by REVDeployer"
            )
        );
        harness.verifyPermissionsAndForwarder();
    }

    function test_permissionsVerifierRejectsWrongPermissionsTrustedForwarder() public {
        address canonicalForwarder = makeAddr("canonical forwarder");
        address wrongPermissionsForwarder = makeAddr("wrong permissions forwarder");
        JBPermissions permissions = new JBPermissions(wrongPermissionsForwarder);

        assertEq(
            permissions.trustedForwarder(),
            wrongPermissionsForwarder,
            "setup must give JBPermissions a noncanonical trusted forwarder"
        );
        assertTrue(wrongPermissionsForwarder != canonicalForwarder, "forwarders must differ");

        VerifyPermissionHarness harness = new VerifyPermissionHarness();
        harness.setPermissionMocks({
            permissions_: address(permissions),
            controller_: address(new MockPermissioned2771(address(permissions), canonicalForwarder)),
            terminal_: address(new MockPermissioned2771(address(permissions), canonicalForwarder)),
            directory_: address(new MockPermissioned(address(permissions))),
            projects_: address(new MockTrustedForwarder(canonicalForwarder)),
            expectedTrustedForwarder_: canonicalForwarder
        });

        // O fix: Category 14 now asserts `permissions.trustedForwarder() == expectedTrustedForwarder`.
        // The harness above gives JBPermissions a noncanonical forwarder, so the verifier rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "Permissions.trustedForwarder == expected"
            )
        );
        harness.verifyPermissionsAndForwarder();
    }

    function test_permissionsVerifierRejectsWhenCanonicalBuybackLacksWildcardGrant() public {
        address trustedForwarder = makeAddr("trusted forwarder");
        JBPermissions permissions = new JBPermissions(trustedForwarder);

        address revDeployer = makeAddr("rev deployer");
        address revLoans = makeAddr("rev loans");
        address canonicalBuybackRegistry = makeAddr("canonical buyback registry");
        address unexpectedOperator = makeAddr("unexpected buyback operator");

        // O's PERMISSIONS() checks on EOAs need stubs to pass through to P.
        vm.mockCall(revDeployer, abi.encodeWithSignature("PERMISSIONS()"), abi.encode(address(permissions)));
        vm.mockCall(revLoans, abi.encodeWithSignature("PERMISSIONS()"), abi.encode(address(permissions)));
        vm.mockCall(
            canonicalBuybackRegistry, abi.encodeWithSignature("PERMISSIONS()"), abi.encode(address(permissions))
        );
        // O's expanded ERC-2771 sweep also calls trustedForwarder() on each surface.
        vm.mockCall(revDeployer, abi.encodeWithSignature("trustedForwarder()"), abi.encode(trustedForwarder));
        vm.mockCall(revLoans, abi.encodeWithSignature("trustedForwarder()"), abi.encode(trustedForwarder));
        vm.mockCall(
            canonicalBuybackRegistry, abi.encodeWithSignature("trustedForwarder()"), abi.encode(trustedForwarder)
        );

        // First grant REVLoans wildcard USE_ALLOWANCE so we reach the buyback-registry check.
        uint8[] memory useAllowanceIds = new uint8[](1);
        useAllowanceIds[0] = JBPermissionIds.USE_ALLOWANCE;
        vm.prank(revDeployer);
        permissions.setPermissionsFor({
            account: revDeployer,
            permissionsData: JBPermissionsData({operator: revLoans, projectId: 0, permissionIds: useAllowanceIds})
        });

        // Grant the wildcard SET_BUYBACK_POOL to an unexpected operator. The CANONICAL buyback
        // registry is NOT granted — but P's positive check looks for the canonical operator and
        // fails when only an unexpected one has the grant.
        uint8[] memory poolIds = new uint8[](1);
        poolIds[0] = JBPermissionIds.SET_BUYBACK_POOL;
        vm.prank(revDeployer);
        permissions.setPermissionsFor({
            account: revDeployer,
            permissionsData: JBPermissionsData({operator: unexpectedOperator, projectId: 0, permissionIds: poolIds})
        });

        assertTrue(
            permissions.hasPermission({
                operator: unexpectedOperator,
                account: revDeployer,
                projectId: 4,
                permissionId: JBPermissionIds.SET_BUYBACK_POOL,
                includeRoot: true,
                includeWildcardProjectId: true
            }),
            "setup must leave an unexpected wildcard buyback-pool operator"
        );
        assertFalse(
            permissions.hasPermission({
                operator: canonicalBuybackRegistry,
                account: revDeployer,
                projectId: 4,
                permissionId: JBPermissionIds.SET_BUYBACK_POOL,
                includeRoot: true,
                includeWildcardProjectId: true
            }),
            "setup must omit the canonical buyback registry wildcard grant"
        );

        VerifyPermissionHarness harness = new VerifyPermissionHarness();
        harness.setPermissionMocks({
            permissions_: address(permissions),
            controller_: address(new MockPermissioned2771(address(permissions), trustedForwarder)),
            terminal_: address(new MockPermissioned2771(address(permissions), trustedForwarder)),
            directory_: address(new MockPermissioned(address(permissions))),
            projects_: address(new MockTrustedForwarder(trustedForwarder)),
            expectedTrustedForwarder_: trustedForwarder
        });
        harness.setPermissionGrantMocks({
            revDeployer_: revDeployer, revLoans_: revLoans, buybackRegistry_: canonicalBuybackRegistry
        });

        // P fix: the verifier asserts the CANONICAL buyback registry has the grant. Granting it
        // to an unexpected operator does not satisfy this check — the verifier rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "Permissions: BuybackRegistry wildcard SET_BUYBACK_POOL granted by REVDeployer"
            )
        );
        harness.verifyPermissionsAndForwarder();
    }
}

contract VerifyPermissionHarness is Verify {
    function setPermissionMocks(
        address permissions_,
        address controller_,
        address terminal_,
        address directory_,
        address projects_,
        address expectedTrustedForwarder_
    )
        external
    {
        permissions = JBPermissions(permissions_);
        controller = JBController(controller_);
        terminal = JBMultiTerminal(payable(terminal_));
        directory = JBDirectory(directory_);
        projects = JBProjects(projects_);
        expectedTrustedForwarder = expectedTrustedForwarder_;
    }

    /// P: set the REV stack pointers + (optional) buyback registry so _verifyPermissionGrants
    /// actually runs its checks. Without these, _verifyPermissionGrants short-circuits via the
    /// "[SKIP] REV stack not loaded" branch.
    function setPermissionGrantMocks(address revDeployer_, address revLoans_, address buybackRegistry_) external {
        revDeployer = REVDeployer(revDeployer_);
        revLoans = REVLoans(payable(revLoans_));
        buybackRegistry = JBBuybackHookRegistry(buybackRegistry_);
    }

    function verifyPermissionsAndForwarder() external {
        _verifyPermissionsAndForwarder();
    }
}

contract MockPermissioned {
    address internal immutable _permissions;

    constructor(address permissions_) {
        _permissions = permissions_;
    }

    function PERMISSIONS() external view returns (address) {
        return _permissions;
    }
}

contract MockPermissioned2771 is MockPermissioned {
    address internal immutable _trustedForwarder;

    constructor(address permissions_, address trustedForwarder_) MockPermissioned(permissions_) {
        _trustedForwarder = trustedForwarder_;
    }

    function trustedForwarder() external view returns (address) {
        return _trustedForwarder;
    }
}

contract MockTrustedForwarder {
    address internal immutable _trustedForwarder;

    constructor(address trustedForwarder_) {
        _trustedForwarder = trustedForwarder_;
    }

    function trustedForwarder() external view returns (address) {
        return _trustedForwarder;
    }
}
