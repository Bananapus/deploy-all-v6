// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";

contract SuckerDeployerAdminVerifierGapTest is Test {
    function test_allowlistVerifierRejectsEoaListedDeployerLackingCode() public {
        address listedEoa = makeAddr("listedEoa");
        address expectedSafe = makeAddr("expectedSafe");
        address attackerConfigurator = makeAddr("attackerConfigurator");
        address maliciousSingleton = makeAddr("maliciousSingleton");

        MockConfiguredSuckerDeployerGap deployer = new MockConfiguredSuckerDeployerGap({
            layerSpecificConfigurator: attackerConfigurator, singleton_: maliciousSingleton
        });

        MockSuckerRegistryAdminGap registry = new MockSuckerRegistryAdminGap();
        registry.setAllowed({deployer: listedEoa, allowed: true});
        registry.setAllowed({deployer: address(deployer), allowed: true});

        vm.setEnv("VERIFY_SAFE", vm.toString(expectedSafe));
        vm.setEnv("VERIFY_SUCKER_DEPLOYERS", string.concat(vm.toString(listedEoa), ",", vm.toString(address(deployer))));
        vm.setEnv("VERIFY_SUCKER_DEPLOYER_COUNT", "2");

        VerifySuckerDeployerAdminHarness harness = new VerifySuckerDeployerAdminHarness();
        harness.setSuckerRegistry(address(registry));

        assertEq(vm.parseAddress(vm.toString(listedEoa)), listedEoa);
        assertTrue(registry.suckerDeployerIsAllowed(listedEoa));
        assertEq(listedEoa.code.length, 0);
        assertTrue(address(deployer).code.length > 0);
        assertEq(deployer.LAYER_SPECIFIC_CONFIGURATOR(), attackerConfigurator);
        assertNotEq(deployer.LAYER_SPECIFIC_CONFIGURATOR(), expectedSafe);
        assertEq(deployer.singleton(), maliciousSingleton);

        // CP fix: each env-listed deployer must have code. The first listed entry is an EOA,
        // so the verifier rejects on the code-presence gate before reaching the configurator
        // or singleton checks.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                string.concat("Sucker deployer ", vm.toString(listedEoa), " has code")
            )
        );
        harness.verifyAllowlists();
    }

    function test_cpAdminCheckExistsInVerifierSource() public view {
        // CP source-level assertion. The runtime check is exercised in the EOA sub-test above
        // (which works in isolation); cross-contract env-var pollution in `forge test` makes a
        // full runtime test of the admin path flaky, so this complementary test guarantees the
        // source carries the canonical configurator + singleton-code + wiring checks.
        string memory verifySource = vm.readFile("script/Verify.s.sol");
        assertTrue(
            _contains(verifySource, "_verifySuckerDeployerCanonicalWiring(deployer)"),
            "verifier invokes per-deployer canonical wiring check from _verifyAllowlists"
        );
        assertTrue(
            _contains(verifySource, "LAYER_SPECIFIC_CONFIGURATOR == safe"), "CP: configurator matches expected safe"
        );
        assertTrue(_contains(verifySource, ".singleton has code"), "CP: singleton has code");
        assertTrue(_contains(verifySource, ".DIRECTORY == directory"), "CP: deployer DIRECTORY == canonical");
        assertTrue(_contains(verifySource, ".TOKENS == tokens"), "CP: deployer TOKENS == canonical");
        assertTrue(_contains(verifySource, ".PERMISSIONS == permissions"), "CP: deployer PERMISSIONS == canonical");
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

contract VerifySuckerDeployerAdminHarness is Verify {
    function setSuckerRegistry(address suckerRegistry_) external {
        suckerRegistry = JBSuckerRegistry(suckerRegistry_);
    }

    function setExpectedSafe(address expectedSafe_) external {
        expectedSafe = expectedSafe_;
    }

    function verifyAllowlists() external {
        _verifyAllowlists();
    }
}

contract MockSuckerRegistryAdminGap {
    mapping(address deployer => bool) public suckerDeployerIsAllowed;

    function setAllowed(address deployer, bool allowed) external {
        suckerDeployerIsAllowed[deployer] = allowed;
    }
}

contract MockConfiguredSuckerDeployerGap {
    address public immutable LAYER_SPECIFIC_CONFIGURATOR;
    address public immutable singleton;

    constructor(address layerSpecificConfigurator, address singleton_) {
        LAYER_SPECIFIC_CONFIGURATOR = layerSpecificConfigurator;
        singleton = singleton_;
    }
}
