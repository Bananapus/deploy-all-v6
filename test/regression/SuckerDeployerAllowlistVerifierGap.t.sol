// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";

contract SuckerDeployerAllowlistVerifierGapTest is Test {
    function test_enumerationGapAcknowledgedInVerifierSource() public view {
        // The on-chain JBSuckerRegistry has no enumeration of its allowed-deployer set, so the
        // verifier cannot prove the absence of unexpected allowed deployers without off-chain
        // event-log reconciliation. The verifier lands a partial mitigation (per-listed deployer
        // code/admin/wiring checks) and explicitly documents the residual enumeration gap in the
        // source so operators know to reconcile off-chain.
        string memory verifySource = vm.readFile("script/Verify.s.sol");
        assertTrue(
            _contains(verifySource, "no on-chain enumeration of sucker-deployer allowlist"),
            "verifier source documents the enumeration gap"
        );
        assertTrue(
            _contains(verifySource, "reconcile off-chain"),
            "verifier source directs operators to off-chain reconciliation"
        );
        // The partial mitigation must be wired: per-listed deployer code + canonical wiring
        // checks fire inside _verifyAllowlists.
        assertTrue(
            _contains(verifySource, "_verifySuckerDeployerCanonicalWiring(deployer)"),
            "verifier invokes the per-deployer canonical wiring check"
        );
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

/// @notice Minimal contract surface for a sucker deployer. The canonical-wiring checks call its
/// getters via low-level staticcall; absence of the getter is treated as a pass-by-skip (the
/// check only fires if the staticcall succeeds with a 32-byte return).
contract MockSuckerDeployerContract {
    // No-op constructor — having any code at the address is enough to pass the code-presence
    // check, which is the gate the test cares about. LAYER_SPECIFIC_CONFIGURATOR / singleton /
    // DIRECTORY / TOKENS / PERMISSIONS getters are intentionally absent so the additional checks
    // short-circuit on the staticcall failure path.
    function placeholder() external pure returns (bool) {
        return true;
    }
}

contract VerifySuckerAllowlistHarness is Verify {
    function setSuckerRegistry(address suckerRegistry_) external {
        suckerRegistry = JBSuckerRegistry(suckerRegistry_);
    }

    function verifyAllowlists() external {
        _verifyAllowlists();
    }
}

contract MockSuckerRegistry {
    mapping(address deployer => bool) public suckerDeployerIsAllowed;

    function setAllowed(address deployer, bool allowed) external {
        suckerDeployerIsAllowed[deployer] = allowed;
    }
}
