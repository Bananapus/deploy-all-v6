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

contract PermissionVerifierGapTest is Test {
    function test_permissionsVerifierAcceptsMissingRuntimeWildcardGrant() public {
        address trustedForwarder = makeAddr("trusted forwarder");
        JBPermissions permissions = new JBPermissions(trustedForwarder);

        address revDeployer = makeAddr("rev deployer");
        address revLoans = makeAddr("rev loans");

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

        // Current Category 14 only checks a few PERMISSIONS() immutables and core forwarder parity.
        // It does not inspect JBPermissions.permissionsOf(...) for runtime wildcard grants.
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

    function test_permissionsVerifierAcceptsUnexpectedWildcardBuybackOperator() public {
        address trustedForwarder = makeAddr("trusted forwarder");
        JBPermissions permissions = new JBPermissions(trustedForwarder);

        address revDeployer = makeAddr("rev deployer");
        address canonicalBuybackRegistry = makeAddr("canonical buyback registry");
        address unexpectedOperator = makeAddr("unexpected buyback operator");

        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = JBPermissionIds.SET_BUYBACK_POOL;

        vm.prank(revDeployer);
        permissions.setPermissionsFor({
            account: revDeployer,
            permissionsData: JBPermissionsData({
                operator: unexpectedOperator, projectId: 0, permissionIds: permissionIds
            })
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

        // Category 14 does not prove that the wildcard permission surface is exact, so it
        // accepts a permissions registry where an unexpected operator can configure buyback pools.
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
