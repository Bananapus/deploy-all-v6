// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBTokens} from "@bananapus/core-v6/src/JBTokens.sol";

contract TokenImplementationVerifierGapTest is Test {
    function test_tokenImplementationVerifierRejectsNoncanonicalImplementation() public {
        address projects = makeAddr("projects");
        address permissions = makeAddr("permissions");

        MockJBERC20Implementation maliciousImplementation =
            new MockJBERC20Implementation({projects_: projects, permissions_: permissions});
        MockJBTokens maliciousTokens = new MockJBTokens({tokenImplementation_: address(maliciousImplementation)});

        VerifyTokenImplementationHarness harness = new VerifyTokenImplementationHarness();
        harness.setTokenMocks({tokens_: address(maliciousTokens), projects_: projects, permissions_: permissions});

        // CJ fix (Decision A): Category 12 now asserts the clone target's runtime bytecode equals
        // the JBERC20 artifact's deployedBytecode. The mock implementation has different code, so
        // the verifier rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "JBERC20 impl: runtime bytecode == artifact deployedBytecode"
            )
        );
        harness.verifyTokenImplementation();
    }
}

contract VerifyTokenImplementationHarness is Verify {
    function setTokenMocks(address tokens_, address projects_, address permissions_) external {
        tokens = JBTokens(tokens_);
        projects = JBProjects(projects_);
        permissions = JBPermissions(permissions_);
    }

    function verifyTokenImplementation() external {
        _verifyTokenImplementation();
    }
}

contract MockJBTokens {
    address internal immutable _tokenImplementation;

    constructor(address tokenImplementation_) {
        _tokenImplementation = tokenImplementation_;
    }

    function TOKEN() external view returns (address) {
        return _tokenImplementation;
    }
}

contract MockJBERC20Implementation {
    address internal immutable _projects;
    address internal immutable _permissions;

    constructor(address projects_, address permissions_) {
        _projects = projects_;
        _permissions = permissions_;
    }

    function PROJECTS() external view returns (address) {
        return _projects;
    }

    function PERMISSIONS() external view returns (address) {
        return _permissions;
    }

    function initialize(string memory, string memory, address) external pure {
        // A noncanonical implementation can expose the checked ABI while
        // omitting or changing JBERC20's initialization, mint, burn, permit,
        // voting, ERC-1271, and metadata behavior.
    }
}
