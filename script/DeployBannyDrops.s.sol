// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Deploy} from "./Deploy.s.sol";

/// @title DeployBannyDrops
/// @notice Follow-up deployment script for Banny retail Drop 1 and Drop 2 metadata/tier registration.
/// @dev Run after `Deploy.s.sol` has executed successfully. It assumes project 4 already exists and is owned by
/// `REVOwner`, with the deployment Sphinx Safe still holding BAN operator permissions and resolver ownership.
contract DeployBannyDrops is Deploy {
    function run() public override {
        _requireExpectedSafe();
        deployBannyDrops();
    }

    function deployBannyDrops() public sphinx {
        _hydrateBannyDropContext();
        _registerBannyDrop1();
        _registerBannyDrop2();
        _finalizeBannyOwnership();
    }
}

/// @title DeployBannyDrop1
/// @notice Follow-up deployment script for only Banny retail Drop 1 metadata/tier registration.
contract DeployBannyDrop1 is Deploy {
    function run() public override {
        _requireExpectedSafe();
        deployBannyDrop1();
    }

    function deployBannyDrop1() public sphinx {
        _hydrateBannyDropContext();
        _registerBannyDrop1();
    }
}

/// @title DeployBannyDrop2
/// @notice Follow-up deployment script for Banny retail Drop 2 metadata/tier registration and final handoff.
/// @dev Run after `DeployBannyDrop1` has executed successfully.
contract DeployBannyDrop2 is Deploy {
    function run() public override {
        _requireExpectedSafe();
        deployBannyDrop2();
    }

    function deployBannyDrop2() public sphinx {
        _hydrateBannyDropContext();
        _registerBannyDrop2();
        _finalizeBannyOwnership();
    }
}
