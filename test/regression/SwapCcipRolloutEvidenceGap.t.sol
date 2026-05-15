// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

/// @notice Phase 4 / S+AH rollout-evidence gate: the verifier must run Decision-A artifact
/// identity against each listed swap-enabled CCIP sucker deployer AND its singleton. Without
/// these checks the deploy can ship swap-enabled suckers that pre-date PR #120 (out-of-order
/// batch metadata stranding earlier batches; raw-ETH V4 settlement reverting before unwrap)
/// while still reading as "allowed in registry" and "canonically wired".
contract SwapCcipRolloutEvidenceGapTest is Test {
    /// @dev Source-only assertion: confirm the verifier wires up `_verifySwapCcipSuckerRolloutIdentity`
    /// and reads the `VERIFY_SWAP_CCIP_SUCKER_DEPLOYERS` env var so the rollout-evidence gate
    /// cannot silently degrade across future edits.
    function test_verifierWiresSwapCcipRolloutIdentity() public view {
        string memory verifySource = vm.readFile("script/Verify.s.sol");
        assertTrue(
            _contains(verifySource, "_verifySwapCcipSuckerRolloutIdentity"),
            "verifier defines and invokes the swap-CCIP rollout identity check"
        );
        assertTrue(
            _contains(verifySource, "VERIFY_SWAP_CCIP_SUCKER_DEPLOYERS"),
            "verifier reads VERIFY_SWAP_CCIP_SUCKER_DEPLOYERS for the per-route deployer list"
        );
        // The identity gate must touch BOTH the deployer factory and the per-route singleton
        // (every clone proxies to the singleton, so the S/AH fixes only land if the singleton
        // is canonical).
        assertTrue(
            _contains(verifySource, "JBSwapCCIPSuckerDeployer"),
            "verifier runs artifact identity against the deployer factory"
        );
        assertTrue(
            _contains(verifySource, "JBSwapCCIPSucker singleton"),
            "verifier runs artifact identity against the per-route singleton"
        );
    }

    /// @dev Runtime assertion: when the env list points at a non-executable address, the
    /// Decision-A `runtime length == artifact length` check fires. This proves the gate is
    /// actually exercised against the supplied addresses rather than silently skipping.
    function test_verifierRejectsNonCanonicalSwapCcipDeployer() public {
        VerifySwapCcipHarness harness = new VerifySwapCcipHarness();

        // Empty (no-code) address fails the `runtime length == artifact length` check because
        // the canonical artifact has non-zero length but the deployed runtime is empty.
        address fakeDeployer = makeAddr("fake-swap-deployer");
        vm.setEnv("VERIFY_SWAP_CCIP_SUCKER_DEPLOYERS", vm.toString(fakeDeployer));

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                string.concat(
                    "JBSwapCCIPSuckerDeployer ", vm.toString(fakeDeployer), ": runtime length == artifact length"
                )
            )
        );
        harness.verifySwapCcipSuckerRolloutIdentity();
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

contract VerifySwapCcipHarness is Verify {
    function verifySwapCcipSuckerRolloutIdentity() external {
        _verifySwapCcipSuckerRolloutIdentity();
    }
}
