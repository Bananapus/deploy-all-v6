// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";

/// @notice Coverage: the verifier asserts the registry's default hook AND every
/// canonical project's resolved hookOf equals the operator-declared canonical buyback hook.
/// Without this, a deployment can ship with nonzero hooks that don't match the canonical
/// implementation while the prior count-only check still passes.
contract CanonicalBuybackHookVerifierGapTest is Test {
    function test_buybackVerifierRejectsNoncanonicalDefaultHook() public {
        vm.chainId(1);

        address canonicalHook = makeAddr("canonical buyback hook");
        address forkedHook = makeAddr("forked buyback hook");
        assertTrue(canonicalHook != forkedHook, "test must use distinct hooks");

        MockBuybackRegistry registry = new MockBuybackRegistry();
        registry.setDefaultHook(forkedHook);
        // hookOf for each canonical project returns the default for this mock.
        registry.setResolvedHook(forkedHook);

        VerifyBuybackHookHarness harness = new VerifyBuybackHookHarness();
        harness.setBuybackRegistry(address(registry));

        vm.setEnv("VERIFY_BUYBACK_HOOK", vm.toString(canonicalHook));

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "BuybackRegistry.defaultHook == canonical buyback hook"
            )
        );
        harness.verifyBuybackHookCanonicalManifest();
    }

    function test_buybackVerifierRejectsThresholdExclusionForCanonicalProject() public {
        vm.chainId(1);

        address canonicalHook = makeAddr("canonical buyback hook");

        MockBuybackRegistry registry = new MockBuybackRegistry();
        registry.setDefaultHook(canonicalHook); // default is canonical
        registry.setResolvedHookFor(1, canonicalHook); // NANA(1) explicitly pinned
        registry.setResolvedHookFor(2, address(0)); // CPN(2) falls through threshold → zero
        registry.setResolvedHookFor(3, canonicalHook);
        registry.setResolvedHookFor(4, canonicalHook);

        VerifyBuybackHookHarness harness = new VerifyBuybackHookHarness();
        harness.setBuybackRegistry(address(registry));

        vm.setEnv("VERIFY_BUYBACK_HOOK", vm.toString(canonicalHook));

        // CPN(2) is the first project that resolves to a non-canonical (zero) hook — the verifier
        // rejects with the per-project label.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "CPN(2) resolved buyback hookOf == canonical"
            )
        );
        harness.verifyBuybackHookCanonicalManifest();
    }

    function test_buybackVerifierFailsClosedWhenEnvUnsetOnMainnet() public {
        vm.chainId(1);

        MockBuybackRegistry registry = new MockBuybackRegistry();
        registry.setDefaultHook(makeAddr("some hook"));
        registry.setResolvedHook(makeAddr("some hook"));

        VerifyBuybackHookHarness harness = new VerifyBuybackHookHarness();
        harness.setBuybackRegistry(address(registry));

        vm.setEnv("VERIFY_BUYBACK_HOOK", ""); // explicit clear in case a sibling test leaked

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "VERIFY_BUYBACK_HOOK MUST be set on production for canonical buyback identity"
            )
        );
        harness.verifyBuybackHookCanonicalManifest();
    }
}

contract VerifyBuybackHookHarness is Verify {
    function setBuybackRegistry(address registry_) external {
        buybackRegistry = JBBuybackHookRegistry(registry_);
    }

    function verifyBuybackHookCanonicalManifest() external {
        _verifyBuybackHookCanonicalManifest();
    }
}

contract MockBuybackRegistry {
    address internal _defaultHook;
    address internal _resolvedFallback;
    mapping(uint256 => address) internal _resolved;
    mapping(uint256 => bool) internal _hasResolved;

    function setDefaultHook(address hook) external {
        _defaultHook = hook;
    }

    /// Default resolved hook returned for any project ID that hasn't been explicitly set.
    function setResolvedHook(address hook) external {
        _resolvedFallback = hook;
    }

    /// Per-project resolved hook override. Used to model `defaultHookProjectIdThreshold`
    /// excluding specific canonical projects without modeling the threshold semantics directly.
    function setResolvedHookFor(uint256 projectId, address hook) external {
        _resolved[projectId] = hook;
        _hasResolved[projectId] = true;
    }

    function defaultHook() external view returns (address) {
        return _defaultHook;
    }

    function hookOf(uint256 projectId) external view returns (address) {
        if (_hasResolved[projectId]) return _resolved[projectId];
        return _resolvedFallback;
    }
}
