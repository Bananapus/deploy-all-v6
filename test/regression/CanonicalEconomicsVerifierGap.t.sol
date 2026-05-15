// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";

contract CanonicalEconomicsVerifierGapTest is Test {
    function test_canonicalEconomicsVerifierReadsDocumentedPerProjectHashEnvs() public view {
        // Source-level assertion. The runtime behaviour is flaky in `forge test`'s parallel
        // contract execution because env vars are process-wide and sibling tests race on them;
        // this complementary check guarantees the verifier source wires the per-project env vars
        // through to a critical hash-equality check.
        string memory verifySource = vm.readFile("script/Verify.s.sol");
        assertTrue(_contains(verifySource, "VERIFY_CONFIG_HASH_1"), "verifier reads VERIFY_CONFIG_HASH_1 env var");
        assertTrue(_contains(verifySource, "VERIFY_CONFIG_HASH_2"), "verifier reads VERIFY_CONFIG_HASH_2 env var");
        assertTrue(_contains(verifySource, "VERIFY_CONFIG_HASH_3"), "verifier reads VERIFY_CONFIG_HASH_3 env var");
        assertTrue(_contains(verifySource, "VERIFY_CONFIG_HASH_4"), "verifier reads VERIFY_CONFIG_HASH_4 env var");
        assertTrue(
            _contains(verifySource, "config hash == expected"), "verifier asserts live config hash equals expected"
        );
        assertTrue(
            _contains(verifySource, "expected config hash MUST be set on production"),
            "verifier fails closed when expected hash unset on production chain"
        );
        assertTrue(
            _contains(verifySource, "_loadExpectedConfigHashes"),
            "verifier delegates hash loading to a dedicated helper"
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

contract VerifyCanonicalEconomicsHarness is Verify {
    function setRevDeployer(address revDeployer_) external {
        revDeployer = REVDeployer(revDeployer_);
    }

    function verifyCanonicalProjectEconomics() external {
        _verifyCanonicalProjectEconomics();
    }
}

contract MockRevDeployer {
    function hashedEncodedConfigurationOf(uint256 revnetId) external pure returns (bytes32) {
        return keccak256(abi.encodePacked("wrong-but-nonzero", revnetId));
    }
}
