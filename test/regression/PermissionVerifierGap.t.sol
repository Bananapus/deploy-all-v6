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
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";

contract PermissionVerifierGapTest is Test {
    function test_permissionsVerifierRejectsMissingRuntimeWildcardGrant() public {
        address trustedForwarder = makeAddr("trusted forwarder");
        JBPermissions permissions = new JBPermissions(trustedForwarder);

        address revDeployer = makeAddr("rev deployer");
        address revOwner = makeAddr("rev owner");
        address revLoans = makeAddr("rev loans");

        _stubAuthSurface({target: revDeployer, permissions: permissions, trustedForwarder: trustedForwarder});
        _stubAuthSurface({target: revOwner, permissions: permissions, trustedForwarder: trustedForwarder});
        _stubAuthSurface({target: revLoans, permissions: permissions, trustedForwarder: trustedForwarder});

        assertFalse(
            permissions.hasPermission({
                operator: revLoans,
                account: revOwner,
                projectId: 0,
                permissionId: JBPermissionIds.USE_ALLOWANCE,
                includeRoot: true,
                includeWildcardProjectId: true
            }),
            "setup must omit expected REVLoans wildcard grant"
        );

        VerifyPermissionHarness harness = _permissionHarness({
            permissions: permissions,
            trustedForwarder: trustedForwarder,
            projects_: address(new MockTrustedForwarder(trustedForwarder))
        });

        // P: enable the runtime-grants check by wiring the REV stack pointers.
        harness.setPermissionGrantMocks({
            revDeployer_: revDeployer, revOwner_: revOwner, revLoans_: revLoans, buybackRegistry_: address(0)
        });

        // P fix: _verifyPermissionGrants now asserts REVLoans has the wildcard USE_ALLOWANCE grant
        // from REVOwner. The harness omits this grant, so the verifier rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "Permissions: REVLoans wildcard USE_ALLOWANCE granted by REVOwner"
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
        assertNotEq(wrongPermissionsForwarder, canonicalForwarder, "forwarders must differ");

        VerifyPermissionHarness harness = _permissionHarness({
            permissions: permissions,
            trustedForwarder: canonicalForwarder,
            projects_: address(new MockTrustedForwarder(canonicalForwarder))
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
        address revOwner = makeAddr("rev owner");
        address revLoans = makeAddr("rev loans");
        address canonicalBuybackRegistry = makeAddr("canonical buyback registry");
        address unexpectedOperator = makeAddr("unexpected buyback operator");

        _stubAuthSurface({target: revDeployer, permissions: permissions, trustedForwarder: trustedForwarder});
        _stubAuthSurface({target: revOwner, permissions: permissions, trustedForwarder: trustedForwarder});
        _stubAuthSurface({target: revLoans, permissions: permissions, trustedForwarder: trustedForwarder});
        _stubAuthSurface({
            target: canonicalBuybackRegistry, permissions: permissions, trustedForwarder: trustedForwarder
        });

        // First grant REVLoans wildcard USE_ALLOWANCE so we reach the buyback-registry check.
        _grantPermissions({
            permissions: permissions,
            account: revOwner,
            operator: revLoans,
            projectId: 0,
            permissionIds: _singlePermission(JBPermissionIds.USE_ALLOWANCE)
        });

        // Grant the wildcard SET_BUYBACK_POOL to an unexpected operator. The CANONICAL buyback
        // registry is NOT granted — but P's positive check looks for the canonical operator and
        // fails when only an unexpected one has the grant.
        _grantPermissions({
            permissions: permissions,
            account: revOwner,
            operator: unexpectedOperator,
            projectId: 0,
            permissionIds: _singlePermission(JBPermissionIds.SET_BUYBACK_POOL)
        });

        assertTrue(
            permissions.hasPermission({
                operator: unexpectedOperator,
                account: revOwner,
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
                account: revOwner,
                projectId: 4,
                permissionId: JBPermissionIds.SET_BUYBACK_POOL,
                includeRoot: true,
                includeWildcardProjectId: true
            }),
            "setup must omit the canonical buyback registry wildcard grant"
        );

        VerifyPermissionHarness harness = _permissionHarness({
            permissions: permissions,
            trustedForwarder: trustedForwarder,
            projects_: address(new MockTrustedForwarder(trustedForwarder))
        });
        harness.setPermissionGrantMocks({
            revDeployer_: revDeployer,
            revOwner_: revOwner,
            revLoans_: revLoans,
            buybackRegistry_: canonicalBuybackRegistry
        });

        // P fix: the verifier asserts the CANONICAL buyback registry has the grant. Granting it
        // to an unexpected operator does not satisfy this check — the verifier rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "Permissions: BuybackRegistry wildcard SET_BUYBACK_POOL granted by REVOwner"
            )
        );
        harness.verifyPermissionsAndForwarder();
    }

    function test_permissionsVerifierDoesNotRequireOperatorSetSuckerPeerGrant() public {
        address trustedForwarder = makeAddr("trusted forwarder");
        JBPermissions permissions = new JBPermissions(trustedForwarder);

        address revDeployer = makeAddr("rev deployer");
        address revOwner = makeAddr("rev owner");
        address revLoans = makeAddr("rev loans");
        address operator = makeAddr("operator");

        _stubAuthSurface({target: revDeployer, permissions: permissions, trustedForwarder: trustedForwarder});
        _stubAuthSurface({target: revOwner, permissions: permissions, trustedForwarder: trustedForwarder});
        _stubAuthSurface({target: revLoans, permissions: permissions, trustedForwarder: trustedForwarder});

        _grantPermissions({
            permissions: permissions,
            account: revOwner,
            operator: revLoans,
            projectId: 0,
            permissionIds: _singlePermission(JBPermissionIds.USE_ALLOWANCE)
        });

        _grantPermissions({
            permissions: permissions,
            account: revOwner,
            operator: revDeployer,
            projectId: 0,
            permissionIds: _revDeployerRuntimePermissions()
        });

        _grantPermissions({
            permissions: permissions,
            account: revOwner,
            operator: operator,
            projectId: 2,
            permissionIds: _canonicalOperatorPermissions()
        });

        assertFalse(
            permissions.hasPermission({
                operator: operator,
                account: revOwner,
                projectId: 2,
                permissionId: JBPermissionIds.SET_SUCKER_PEER,
                includeRoot: true,
                includeWildcardProjectId: true
            }),
            "setup must omit the explicit sucker peer grant"
        );

        VerifyPermissionHarness harness = _permissionHarness({
            permissions: permissions,
            trustedForwarder: trustedForwarder,
            projects_: address(new MockProjectsForPermissions(trustedForwarder, revOwner))
        });
        harness.setPermissionGrantMocks({
            revDeployer_: revDeployer, revOwner_: revOwner, revLoans_: revLoans, buybackRegistry_: address(0)
        });

        vm.setEnv("VERIFY_OPERATOR_2", vm.toString(operator));

        harness.verifyPermissionsAndForwarder();

        vm.setEnv("VERIFY_OPERATOR_2", "0x0000000000000000000000000000000000000000");
    }

    function _grantPermissions(
        JBPermissions permissions,
        address account,
        address operator,
        uint64 projectId,
        uint8[] memory permissionIds
    )
        private
    {
        vm.prank(account);
        permissions.setPermissionsFor({
            account: account,
            permissionsData: JBPermissionsData({operator: operator, projectId: projectId, permissionIds: permissionIds})
        });
    }

    function _stubAuthSurface(address target, JBPermissions permissions, address trustedForwarder) private {
        vm.mockCall(target, abi.encodeWithSignature("PERMISSIONS()"), abi.encode(address(permissions)));
        vm.mockCall(target, abi.encodeWithSignature("trustedForwarder()"), abi.encode(trustedForwarder));
    }

    function _permissionHarness(
        JBPermissions permissions,
        address trustedForwarder,
        address projects_
    )
        private
        returns (VerifyPermissionHarness harness)
    {
        harness = new VerifyPermissionHarness();
        harness.setPermissionMocks({
            permissions_: address(permissions),
            controller_: address(new MockPermissioned2771(address(permissions), trustedForwarder)),
            terminal_: address(new MockPermissioned2771(address(permissions), trustedForwarder)),
            directory_: address(new MockPermissioned(address(permissions))),
            projects_: projects_,
            expectedTrustedForwarder_: trustedForwarder
        });
    }

    function _singlePermission(uint8 permissionId) private pure returns (uint8[] memory permissionIds) {
        permissionIds = new uint8[](1);
        permissionIds[0] = permissionId;
    }

    function _revDeployerRuntimePermissions() private pure returns (uint8[] memory permissionIds) {
        permissionIds = new uint8[](2);
        permissionIds[0] = JBPermissionIds.DEPLOY_SUCKERS;
        permissionIds[1] = JBPermissionIds.MAP_SUCKER_TOKEN;
    }

    function _canonicalOperatorPermissions() private pure returns (uint8[] memory permissionIds) {
        permissionIds = new uint8[](9);
        permissionIds[0] = JBPermissionIds.SET_SPLIT_GROUPS;
        permissionIds[1] = JBPermissionIds.SET_BUYBACK_POOL;
        permissionIds[2] = JBPermissionIds.SET_BUYBACK_TWAP;
        permissionIds[3] = JBPermissionIds.SET_PROJECT_URI;
        permissionIds[4] = JBPermissionIds.SUCKER_SAFETY;
        permissionIds[5] = JBPermissionIds.SET_BUYBACK_HOOK;
        permissionIds[6] = JBPermissionIds.SET_ROUTER_TERMINAL;
        permissionIds[7] = JBPermissionIds.SET_TOKEN_METADATA;
        permissionIds[8] = JBPermissionIds.SIGN_FOR_ERC20;
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
    function setPermissionGrantMocks(
        address revDeployer_,
        address revOwner_,
        address revLoans_,
        address buybackRegistry_
    )
        external
    {
        revDeployer = REVDeployer(revDeployer_);
        revOwner = REVOwner(revOwner_);
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

contract MockProjectsForPermissions is MockTrustedForwarder {
    address internal immutable _owner;

    constructor(address trustedForwarder_, address owner_) MockTrustedForwarder(trustedForwarder_) {
        _owner = owner_;
    }

    function count() external pure returns (uint256) {
        return 4;
    }

    function ownerOf(uint256 projectId) external view returns (address) {
        require(projectId == 2, "unexpected project");
        return _owner;
    }
}
