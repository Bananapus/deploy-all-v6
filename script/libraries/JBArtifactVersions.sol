// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";

/// @notice Ties a rollout to the npm releases it names. A rollout deploys `artifacts/` under salts that name a
/// release, so artifacts built from another release would put other code under those names.
library JBArtifactVersions {
    error JBArtifactVersions_UnexpectedVersion(string artifact, string expected, string actual);

    Vm private constant _VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Reverts unless `artifacts/` holds `artifact` built from release `expected` of its package.
    /// @param artifact The artifact name, as `artifacts/artifacts.manifest.json` records it.
    /// @param expected The package version the rollout deploys.
    function requireVersion(string memory artifact, string memory expected) internal view {
        string memory actual = _VM.parseJsonString({
            json: _VM.readFile("artifacts/artifacts.manifest.json"),
            key: string.concat(".contracts.", artifact, ".sourceVersion")
        });
        if (keccak256(bytes(actual)) != keccak256(bytes(expected))) {
            revert JBArtifactVersions_UnexpectedVersion({artifact: artifact, expected: expected, actual: actual});
        }
    }
}
