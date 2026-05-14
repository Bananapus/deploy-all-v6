// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBDirectory} from "@bananapus/core-v6/src/JBDirectory.sol";
import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBTokens} from "@bananapus/core-v6/src/JBTokens.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {CTDeployer} from "@croptop/core-v6/src/CTDeployer.sol";
import {CTProjectOwner} from "@croptop/core-v6/src/CTProjectOwner.sol";
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";

contract Canonical721HookVerifierGapTest is Test {
    function test_canonicalIdentityVerifierRejectsMissingCpnTiered721Hook() public {
        MockRevDeployer revDeployer = new MockRevDeployer();
        MockProjects projects = new MockProjects(address(revDeployer));
        MockTokens tokens = new MockTokens();
        MockRevOwner revOwner = new MockRevOwner();

        tokens.setTokenOf(1, address(new MockToken("NANA")));
        tokens.setTokenOf(2, address(new MockToken("CPN")));
        tokens.setTokenOf(3, address(new MockToken("REV")));
        tokens.setTokenOf(4, address(new MockToken("BAN")));

        address hookStore = makeAddr("hook store");
        revOwner.setTiered721HookOf(4, address(new MockBannyHook(hookStore)));

        VerifyCanonical721HookHarness harness = new VerifyCanonical721HookHarness();
        harness.setCanonicalMocks({
            projects_: address(projects),
            tokens_: address(tokens),
            revDeployer_: address(revDeployer),
            revOwner_: address(revOwner),
            hookStore_: hookStore
        });

        assertEq(revOwner.tiered721HookOf(2), address(0), "test leaves CPN hook unset");

        // BS fix: Category 1 now requires the CPN hook to be recorded. The mock leaves it unset,
        // so the verifier rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "CPN(2) has Croptop 721 hook recorded"
            )
        );
        harness.verifyCanonicalProjectIdentities();
    }

    function test_croptopImmutableVerifierIgnoresCpnPostingCriteria() public {
        address directory = makeAddr("directory");
        address hookDeployer = makeAddr("hook deployer");
        address suckerRegistry = makeAddr("sucker registry");
        address permissions = makeAddr("permissions");
        address hookStore = makeAddr("hook store");
        address cpnHook = address(new MockCpnHook(hookStore));

        MockProjects projects = new MockProjects(makeAddr("rev deployer"));
        MockPublisher publisher = new MockPublisher(directory, 2);
        MockCTDeployer ctDeployer = new MockCTDeployer({
            hookDeployer_: hookDeployer,
            projects_: address(projects),
            publisher_: address(publisher),
            suckerRegistry_: suckerRegistry
        });
        MockCTProjectOwner ctProjectOwner = new MockCTProjectOwner({
            permissions_: permissions, projects_: address(projects), publisher_: address(publisher)
        });

        for (uint256 category; category < 5; category++) {
            (
                uint256 minimumPrice,
                uint256 minimumTotalSupply,
                uint256 maximumTotalSupply,
                uint256 maximumSplitPercent,
                address[] memory allowedAddresses
            ) = publisher.allowanceFor(cpnHook, category);
            assertEq(minimumPrice, 0, "CPN minimum price unset");
            assertEq(minimumTotalSupply, 0, "CPN minimum supply unset");
            assertEq(maximumTotalSupply, 0, "CPN maximum supply unset");
            assertEq(maximumSplitPercent, 0, "CPN maximum split percent unset");
            assertEq(allowedAddresses.length, 0, "CPN allowed addresses unset");
        }

        VerifyCanonical721HookHarness harness = new VerifyCanonical721HookHarness();
        harness.setCroptopMocks({
            directory_: directory,
            projects_: address(projects),
            hookDeployer_: hookDeployer,
            suckerRegistry_: suckerRegistry,
            permissions_: permissions,
            publisher_: address(publisher),
            ctDeployer_: address(ctDeployer),
            ctProjectOwner_: address(ctProjectOwner)
        });

        // Category 15 verifies Croptop contract wiring but never reads the CPN hook's
        // five posting criteria configured by Deploy.s.sol.
        harness.verifyCroptopImmutables();
    }
}

contract VerifyCanonical721HookHarness is Verify {
    function setCanonicalMocks(
        address projects_,
        address tokens_,
        address revDeployer_,
        address revOwner_,
        address hookStore_
    )
        external
    {
        projects = JBProjects(projects_);
        tokens = JBTokens(tokens_);
        revDeployer = REVDeployer(revDeployer_);
        revOwner = REVOwner(revOwner_);
        hookStore = JB721TiersHookStore(hookStore_);
    }

    function verifyCanonicalProjectIdentities() external {
        _verifyCanonicalProjectIdentities();
    }

    function setCroptopMocks(
        address directory_,
        address projects_,
        address hookDeployer_,
        address suckerRegistry_,
        address permissions_,
        address publisher_,
        address ctDeployer_,
        address ctProjectOwner_
    )
        external
    {
        directory = JBDirectory(directory_);
        projects = JBProjects(projects_);
        hookDeployer = JB721TiersHookDeployer(hookDeployer_);
        suckerRegistry = JBSuckerRegistry(suckerRegistry_);
        permissions = JBPermissions(permissions_);
        ctPublisher = CTPublisher(publisher_);
        ctDeployer = CTDeployer(ctDeployer_);
        ctProjectOwner = CTProjectOwner(ctProjectOwner_);
    }

    function verifyCroptopImmutables() external {
        _verifyCroptopImmutables();
    }
}

contract MockProjects {
    address internal immutable _revDeployer;

    constructor(address revDeployer_) {
        _revDeployer = revDeployer_;
    }

    function ownerOf(uint256) external view returns (address) {
        return _revDeployer;
    }
}

contract MockTokens {
    mapping(uint256 projectId => address token) internal _tokenOf;

    function setTokenOf(uint256 projectId, address token) external {
        _tokenOf[projectId] = token;
    }

    function tokenOf(uint256 projectId) external view returns (address) {
        return _tokenOf[projectId];
    }
}

contract MockRevDeployer {
    function hashedEncodedConfigurationOf(uint256 projectId) external pure returns (bytes32) {
        return keccak256(abi.encodePacked("canonical-project", projectId));
    }
}

contract MockRevOwner {
    mapping(uint256 projectId => address hook) internal _tiered721HookOf;

    function setTiered721HookOf(uint256 projectId, address hook) external {
        _tiered721HookOf[projectId] = hook;
    }

    function tiered721HookOf(uint256 projectId) external view returns (address) {
        return _tiered721HookOf[projectId];
    }
}

contract MockToken {
    string internal _symbol;

    constructor(string memory symbol_) {
        _symbol = symbol_;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }
}

contract MockBannyHook is MockToken {
    address internal immutable _hookStore;

    constructor(address hookStore_) MockToken("BANNY") {
        _hookStore = hookStore_;
    }

    function PROJECT_ID() external pure returns (uint256) {
        return 4;
    }

    function STORE() external view returns (address) {
        return _hookStore;
    }
}

contract MockCpnHook is MockToken {
    address internal immutable _hookStore;

    constructor(address hookStore_) MockToken("CPN") {
        _hookStore = hookStore_;
    }

    function PROJECT_ID() external pure returns (uint256) {
        return 2;
    }

    function STORE() external view returns (address) {
        return _hookStore;
    }
}

contract MockPublisher {
    address internal immutable _directory;
    uint256 internal immutable _feeProjectId;

    constructor(address directory_, uint256 feeProjectId_) {
        _directory = directory_;
        _feeProjectId = feeProjectId_;
    }

    function DIRECTORY() external view returns (address) {
        return _directory;
    }

    function FEE_PROJECT_ID() external view returns (uint256) {
        return _feeProjectId;
    }

    function allowanceFor(
        address,
        uint256
    )
        external
        pure
        returns (
            uint256 minimumPrice,
            uint256 minimumTotalSupply,
            uint256 maximumTotalSupply,
            uint256 maximumSplitPercent,
            address[] memory allowedAddresses
        )
    {}
}

contract MockCTDeployer {
    address internal immutable _hookDeployer;
    address internal immutable _projects;
    address internal immutable _publisher;
    address internal immutable _suckerRegistry;

    constructor(address hookDeployer_, address projects_, address publisher_, address suckerRegistry_) {
        _hookDeployer = hookDeployer_;
        _projects = projects_;
        _publisher = publisher_;
        _suckerRegistry = suckerRegistry_;
    }

    function DEPLOYER() external view returns (address) {
        return _hookDeployer;
    }

    function PROJECTS() external view returns (address) {
        return _projects;
    }

    function PUBLISHER() external view returns (address) {
        return _publisher;
    }

    function SUCKER_REGISTRY() external view returns (address) {
        return _suckerRegistry;
    }
}

contract MockCTProjectOwner {
    address internal immutable _permissions;
    address internal immutable _projects;
    address internal immutable _publisher;

    constructor(address permissions_, address projects_, address publisher_) {
        _permissions = permissions_;
        _projects = projects_;
        _publisher = publisher_;
    }

    function PERMISSIONS() external view returns (address) {
        return _permissions;
    }

    function PROJECTS() external view returns (address) {
        return _projects;
    }

    function PUBLISHER() external view returns (address) {
        return _publisher;
    }
}
