// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBController} from "@bananapus/core-v6/src/JBController.sol";
import {JBDirectory} from "@bananapus/core-v6/src/JBDirectory.sol";
import {JBMultiTerminal} from "@bananapus/core-v6/src/JBMultiTerminal.sol";
import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {JBPrices} from "@bananapus/core-v6/src/JBPrices.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {CTDeployer} from "@croptop/core-v6/src/CTDeployer.sol";
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";

/// @notice Regressions for the O/P verifier extensions: noncanonical PERMISSIONS pointers,
/// noncanonical trusted forwarders, and missing canonical wildcard grants on the broader auth
/// surface (Prices, Croptop, OmnichainDeployer -> SuckerRegistry, CTDeployer -> CTPublisher).
contract PermissionAuthSurfaceVerifierGapTest is Test {
    /// @dev Source-only assertion: confirm the verifier exercises every new PERMISSIONS /
    /// trustedForwarder pair so a future refactor cannot silently drop one of them. Mirrors the
    /// source-only pattern used in `SuckerDeployerAllowlistVerifierGap.t.sol`.
    function test_verifierAuthSurfaceCoverage() public view {
        string memory verifySource = vm.readFile("script/Verify.s.sol");

        // PERMISSIONS coverage.
        assertTrue(
            _contains(verifySource, "Prices.PERMISSIONS == permissions"),
            "verifier asserts JBPrices PERMISSIONS pointer"
        );
        assertTrue(
            _contains(verifySource, "CTPublisher.PERMISSIONS == permissions"),
            "verifier asserts CTPublisher PERMISSIONS pointer"
        );
        assertTrue(
            _contains(verifySource, "CTDeployer.PERMISSIONS == permissions"),
            "verifier asserts CTDeployer PERMISSIONS pointer"
        );

        // trustedForwarder coverage across ERC-2771 surfaces.
        assertTrue(
            _contains(verifySource, "Prices.trustedForwarder == expected"), "verifier asserts JBPrices trustedForwarder"
        );
        assertTrue(
            _contains(verifySource, "BuybackRegistry.trustedForwarder == expected"),
            "verifier asserts BuybackRegistry trustedForwarder"
        );
        assertTrue(
            _contains(verifySource, "SuckerRegistry.trustedForwarder == expected"),
            "verifier asserts SuckerRegistry trustedForwarder"
        );
        assertTrue(
            _contains(verifySource, "OmnichainDeployer.trustedForwarder == expected"),
            "verifier asserts OmnichainDeployer trustedForwarder"
        );
        assertTrue(
            _contains(verifySource, "REVDeployer.trustedForwarder == expected"),
            "verifier asserts REVDeployer trustedForwarder"
        );
        assertTrue(
            _contains(verifySource, "REVLoans.trustedForwarder == expected"),
            "verifier asserts REVLoans trustedForwarder"
        );
        assertTrue(
            _contains(verifySource, "RouterTerminalRegistry.trustedForwarder == expected"),
            "verifier asserts RouterTerminalRegistry trustedForwarder"
        );
        assertTrue(
            _contains(verifySource, "RouterTerminal.trustedForwarder == expected"),
            "verifier asserts RouterTerminal trustedForwarder"
        );
        assertTrue(
            _contains(verifySource, "HookDeployer.trustedForwarder == expected"),
            "verifier asserts 721 hook deployer trustedForwarder"
        );
        assertTrue(
            _contains(verifySource, "HookProjectDeployer.trustedForwarder == expected"),
            "verifier asserts 721 hook project deployer trustedForwarder"
        );
        assertTrue(
            _contains(verifySource, "CTPublisher.trustedForwarder == expected"),
            "verifier asserts CTPublisher trustedForwarder"
        );
        assertTrue(
            _contains(verifySource, "CTDeployer.trustedForwarder == expected"),
            "verifier asserts CTDeployer trustedForwarder"
        );

        // Wildcard grant coverage.
        assertTrue(
            _contains(verifySource, "SuckerRegistry wildcard MAP_SUCKER_TOKEN granted by OmnichainDeployer"),
            "verifier asserts MAP_SUCKER_TOKEN wildcard grant"
        );
        assertTrue(
            _contains(verifySource, "CTPublisher wildcard ADJUST_721_TIERS granted by CTDeployer"),
            "verifier asserts ADJUST_721_TIERS wildcard grant"
        );

        // Production-required split-operator manifest.
        assertTrue(
            _contains(verifySource, "MUST be set on production for"),
            "verifier fails closed when split-operator env var is unset on production"
        );
    }

    /// @dev Runtime assertion: when `JBOmnichainDeployer` has not granted the canonical
    /// `MAP_SUCKER_TOKEN` wildcard to the sucker registry, the verifier rejects. Mirrors the
    /// existing REVLoans / buyback wildcard-grant regressions but on the new omnichain branch.
    function test_permissionsVerifierRejectsMissingOmnichainMapSuckerTokenGrant() public {
        address trustedForwarder = makeAddr("trusted forwarder");
        JBPermissions permissions = new JBPermissions(trustedForwarder);

        address revDeployer = makeAddr("rev deployer");
        address revLoans = makeAddr("rev loans");
        address buybackRegistry = makeAddr("buyback registry");
        address omnichainDeployer = makeAddr("omnichain deployer");
        address suckerRegistry = makeAddr("sucker registry");

        // O PERMISSIONS-getter stubs.
        vm.mockCall(revDeployer, abi.encodeWithSignature("PERMISSIONS()"), abi.encode(address(permissions)));
        vm.mockCall(revLoans, abi.encodeWithSignature("PERMISSIONS()"), abi.encode(address(permissions)));
        vm.mockCall(buybackRegistry, abi.encodeWithSignature("PERMISSIONS()"), abi.encode(address(permissions)));
        vm.mockCall(omnichainDeployer, abi.encodeWithSignature("PERMISSIONS()"), abi.encode(address(permissions)));
        vm.mockCall(suckerRegistry, abi.encodeWithSignature("PERMISSIONS()"), abi.encode(address(permissions)));
        // O trustedForwarder-getter stubs so the new ERC-2771 sweep passes through to the P checks
        // we actually want to exercise here.
        vm.mockCall(buybackRegistry, abi.encodeWithSignature("trustedForwarder()"), abi.encode(trustedForwarder));
        vm.mockCall(suckerRegistry, abi.encodeWithSignature("trustedForwarder()"), abi.encode(trustedForwarder));
        vm.mockCall(omnichainDeployer, abi.encodeWithSignature("trustedForwarder()"), abi.encode(trustedForwarder));
        vm.mockCall(revDeployer, abi.encodeWithSignature("trustedForwarder()"), abi.encode(trustedForwarder));
        vm.mockCall(revLoans, abi.encodeWithSignature("trustedForwarder()"), abi.encode(trustedForwarder));
        // O DIRECTORY getter on the omnichain deployer. Must match the harness's directory.
        address mockDirectory = address(new MockPermissioned(address(permissions)));
        vm.mockCall(omnichainDeployer, abi.encodeWithSignature("DIRECTORY()"), abi.encode(mockDirectory));

        // Grant the prior wildcards so the verifier reaches the new MAP_SUCKER_TOKEN check.
        uint8[] memory useAllowanceIds = new uint8[](1);
        useAllowanceIds[0] = JBPermissionIds.USE_ALLOWANCE;
        vm.prank(revDeployer);
        permissions.setPermissionsFor({
            account: revDeployer,
            permissionsData: JBPermissionsData({operator: revLoans, projectId: 0, permissionIds: useAllowanceIds})
        });
        uint8[] memory poolIds = new uint8[](1);
        poolIds[0] = JBPermissionIds.SET_BUYBACK_POOL;
        vm.prank(revDeployer);
        permissions.setPermissionsFor({
            account: revDeployer,
            permissionsData: JBPermissionsData({operator: buybackRegistry, projectId: 0, permissionIds: poolIds})
        });

        // The setup leaves MAP_SUCKER_TOKEN ungranted from `omnichainDeployer`. The new check fires.
        assertFalse(
            permissions.hasPermission({
                operator: suckerRegistry,
                account: omnichainDeployer,
                projectId: 0,
                permissionId: JBPermissionIds.MAP_SUCKER_TOKEN,
                includeRoot: true,
                includeWildcardProjectId: true
            }),
            "setup must omit the canonical MAP_SUCKER_TOKEN grant"
        );

        VerifyAuthSurfaceHarness harness = new VerifyAuthSurfaceHarness();
        harness.setBaseMocks({
            permissions_: address(permissions),
            controller_: address(new MockPermissioned2771(address(permissions), trustedForwarder)),
            terminal_: address(new MockPermissioned2771(address(permissions), trustedForwarder)),
            directory_: mockDirectory,
            projects_: address(new MockTrustedForwarder(trustedForwarder)),
            expectedTrustedForwarder_: trustedForwarder
        });
        harness.setStackMocks({
            revDeployer_: revDeployer,
            revLoans_: revLoans,
            buybackRegistry_: buybackRegistry,
            omnichainDeployer_: omnichainDeployer,
            suckerRegistry_: suckerRegistry
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "Permissions: SuckerRegistry wildcard MAP_SUCKER_TOKEN granted by OmnichainDeployer"
            )
        );
        harness.verifyPermissionsAndForwarder();
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0) return true;
        if (n.length > h.length) return false;
        for (uint256 i; i <= h.length - n.length; i++) {
            bool matched = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) return true;
        }
        return false;
    }
}

contract VerifyAuthSurfaceHarness is Verify {
    function setBaseMocks(
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

    function setStackMocks(
        address revDeployer_,
        address revLoans_,
        address buybackRegistry_,
        address omnichainDeployer_,
        address suckerRegistry_
    )
        external
    {
        revDeployer = REVDeployer(revDeployer_);
        revLoans = REVLoans(payable(revLoans_));
        buybackRegistry = JBBuybackHookRegistry(buybackRegistry_);
        omnichainDeployer = JBOmnichainDeployer(payable(omnichainDeployer_));
        suckerRegistry = JBSuckerRegistry(suckerRegistry_);
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
