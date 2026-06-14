// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Regression: the live smoke proposal must not mutate REVLoans burn permissions unless the operator
/// explicitly opts into the loan leg and permission mutation.
contract LivePostDeploySmokeSafetyTest is Test {
    function test_liveSmokeLoanPermissionMutationIsOptIn() public view {
        string memory smokeSource = vm.readFile("script/LivePostDeploySmoke.s.sol");
        string memory runbook = vm.readFile("DEPLOY.md");

        assertTrue(_contains(smokeSource, "_DEFAULT_LOAN_BUDGET = 0"), "loan smoke must be disabled by default");
        assertTrue(
            _contains(smokeSource, "_DEFAULT_LOAN_PAYMENT = 0"), "loan payment must be zero when loan smoke is off"
        );
        assertTrue(
            _contains(smokeSource, "SMOKE_ALLOW_PERMISSION_MUTATION"),
            "permission mutation requires an explicit env flag"
        );
        assertTrue(
            _contains(smokeSource, "LivePostDeploySmoke_PermissionMutationDisabled"),
            "missing mutation opt-in must revert"
        );
        assertTrue(
            _contains(smokeSource, "_buybackBudget != 0 && _buybackPayment == 0"),
            "nonzero buyback budget rejects zero payment"
        );
        assertTrue(
            _contains(smokeSource, "_loanBudget != 0 && _loanPayment == 0"), "nonzero loan budget rejects zero payment"
        );
        assertTrue(_contains(runbook, "Loan smoke is disabled by default"), "runbook documents loan opt-in");
        assertTrue(
            _contains(runbook, "SMOKE_ALLOW_PERMISSION_MUTATION=true"),
            "runbook documents the permission-mutation opt-in"
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
