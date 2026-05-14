// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBController} from "@bananapus/core-v6/src/JBController.sol";
import {JBDirectory} from "@bananapus/core-v6/src/JBDirectory.sol";
import {JBFeelessAddresses} from "@bananapus/core-v6/src/JBFeelessAddresses.sol";
import {JBFundAccessLimits} from "@bananapus/core-v6/src/JBFundAccessLimits.sol";
import {JBMultiTerminal} from "@bananapus/core-v6/src/JBMultiTerminal.sol";
import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBPrices} from "@bananapus/core-v6/src/JBPrices.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBRulesets} from "@bananapus/core-v6/src/JBRulesets.sol";
import {JBSplits} from "@bananapus/core-v6/src/JBSplits.sol";
import {JBTerminalStore} from "@bananapus/core-v6/src/JBTerminalStore.sol";
import {JBTokens} from "@bananapus/core-v6/src/JBTokens.sol";
import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";

contract CoreSupportSingletonVerifierGapTest is Test {
    address internal safe;
    address internal trustedForwarder;
    address internal omnichainDeployer;
    CoreSupportMockPermissions internal permissions;
    CoreSupportMockProjects internal projects;
    CoreSupportMockDirectory internal directory;
    CoreSupportMockOwned internal prices;
    CoreSupportMockOwned internal feelessAddresses;
    CoreSupportMockOwnedPermissioned internal suckerRegistry;
    CoreSupportMockCode internal fundAccessLimits;
    CoreSupportMockCode internal rulesets;
    CoreSupportMockCode internal splits;
    CoreSupportMockTokens internal tokens;
    CoreSupportMockTerminalStore internal terminalStore;
    CoreSupportMockController internal controller;
    CoreSupportMockTerminal internal terminal;

    function test_coreSupportVerifierAcceptsNoncanonicalImplementations() public {
        _deploySupportMocks();

        CoreSupportMockTokenImplementation tokenImplementation =
            new CoreSupportMockTokenImplementation({projects_: address(projects), permissions_: address(permissions)});
        tokens = new CoreSupportMockTokens({tokenImplementation_: address(tokenImplementation)});
        terminalStore = new CoreSupportMockTerminalStore({
            directory_: address(directory), rulesets_: address(rulesets), prices_: address(prices)
        });
        controller = new CoreSupportMockController({
            directory_: address(directory),
            fundAccessLimits_: address(fundAccessLimits),
            tokens_: address(tokens),
            prices_: address(prices),
            projects_: address(projects),
            rulesets_: address(rulesets),
            splits_: address(splits),
            omnichainDeployer_: omnichainDeployer,
            permissions_: address(permissions),
            trustedForwarder_: trustedForwarder
        });
        terminal = new CoreSupportMockTerminal({
            store_: address(terminalStore),
            directory_: address(directory),
            projects_: address(projects),
            splits_: address(splits),
            tokens_: address(tokens),
            feelessAddresses_: address(feelessAddresses),
            permissions_: address(permissions),
            trustedForwarder_: trustedForwarder
        });

        VerifyCoreSupportHarness harness = new VerifyCoreSupportHarness();
        harness.setCoreRuntimeMocks({
            controller_: address(controller),
            terminal_: address(terminal),
            terminalStore_: address(terminalStore),
            directory_: address(directory),
            projects_: address(projects),
            omnichainDeployer_: omnichainDeployer,
            expectedSafe_: safe,
            expectedTrustedForwarder_: trustedForwarder
        });
        harness.setCoreSupportMocks({
            fundAccessLimits_: address(fundAccessLimits),
            tokens_: address(tokens),
            prices_: address(prices),
            rulesets_: address(rulesets),
            splits_: address(splits),
            feelessAddresses_: address(feelessAddresses),
            permissions_: address(permissions),
            suckerRegistry_: address(suckerRegistry)
        });

        // The verifier proves support-contract addresses are wired through the
        // controller, terminal, store, ownership, token implementation, and
        // forwarder checks. It does not prove these support singletons are the
        // deploy-all core artifacts or audited runtime bytecode.
        harness.verifyCoreSupportSurfaces();
    }

    function _deploySupportMocks() internal {
        safe = makeAddr("safe");
        trustedForwarder = makeAddr("trustedForwarder");
        permissions = new CoreSupportMockPermissions(trustedForwarder);
        projects = new CoreSupportMockProjects({owner_: safe, trustedForwarder_: trustedForwarder});
        directory = new CoreSupportMockDirectory({owner_: safe, permissions_: address(permissions)});
        // Use a contract mock for omnichainDeployer so the O fix's PERMISSIONS() / DIRECTORY()
        // checks have valid getters. Set DIRECTORY after the directory mock exists.
        CoreSupportMockOmnichain omnichainMock = new CoreSupportMockOmnichain(address(permissions));
        omnichainMock.setDirectory(address(directory));
        omnichainDeployer = address(omnichainMock);
        prices = new CoreSupportMockOwned({owner_: safe});
        feelessAddresses = new CoreSupportMockOwned({owner_: safe});
        // The O fix asserts suckerRegistry.PERMISSIONS() — use a mock that exposes both
        // owner() and PERMISSIONS() for this regression to still target CO behaviour.
        suckerRegistry = new CoreSupportMockOwnedPermissioned({owner_: safe, permissions_: address(permissions)});
        fundAccessLimits = new CoreSupportMockCode();
        rulesets = new CoreSupportMockCode();
        splits = new CoreSupportMockCode();
    }
}

contract VerifyCoreSupportHarness is Verify {
    function setCoreRuntimeMocks(
        address controller_,
        address terminal_,
        address terminalStore_,
        address directory_,
        address projects_,
        address omnichainDeployer_,
        address expectedSafe_,
        address expectedTrustedForwarder_
    )
        external
    {
        controller = JBController(controller_);
        terminal = JBMultiTerminal(payable(terminal_));
        terminalStore = JBTerminalStore(terminalStore_);
        directory = JBDirectory(directory_);
        projects = JBProjects(projects_);
        omnichainDeployer = JBOmnichainDeployer(omnichainDeployer_);
        expectedSafe = expectedSafe_;
        expectedTrustedForwarder = expectedTrustedForwarder_;
    }

    function setCoreSupportMocks(
        address fundAccessLimits_,
        address tokens_,
        address prices_,
        address rulesets_,
        address splits_,
        address feelessAddresses_,
        address permissions_,
        address suckerRegistry_
    )
        external
    {
        fundAccessLimits = JBFundAccessLimits(fundAccessLimits_);
        tokens = JBTokens(tokens_);
        prices = JBPrices(prices_);
        rulesets = JBRulesets(rulesets_);
        splits = JBSplits(splits_);
        feelessAddresses = JBFeelessAddresses(feelessAddresses_);
        permissions = JBPermissions(permissions_);
        suckerRegistry = JBSuckerRegistry(suckerRegistry_);
    }

    function verifyCoreSupportSurfaces() external {
        _verifyControllerWiring();
        _verifyTerminalWiring();
        _verifyTokenImplementation();
        _verifyOwnership();
        _verifyPermissionsAndForwarder();
    }
}

contract CoreSupportMockController {
    address internal immutable _directory;
    address internal immutable _fundAccessLimits;
    address internal immutable _tokens;
    address internal immutable _prices;
    address internal immutable _projects;
    address internal immutable _rulesets;
    address internal immutable _splits;
    address internal immutable _omnichainDeployer;
    address internal immutable _permissions;
    address internal immutable _trustedForwarder;

    constructor(
        address directory_,
        address fundAccessLimits_,
        address tokens_,
        address prices_,
        address projects_,
        address rulesets_,
        address splits_,
        address omnichainDeployer_,
        address permissions_,
        address trustedForwarder_
    ) {
        _directory = directory_;
        _fundAccessLimits = fundAccessLimits_;
        _tokens = tokens_;
        _prices = prices_;
        _projects = projects_;
        _rulesets = rulesets_;
        _splits = splits_;
        _omnichainDeployer = omnichainDeployer_;
        _permissions = permissions_;
        _trustedForwarder = trustedForwarder_;
    }

    function DIRECTORY() external view returns (address) {
        return _directory;
    }

    function FUND_ACCESS_LIMITS() external view returns (address) {
        return _fundAccessLimits;
    }

    function TOKENS() external view returns (address) {
        return _tokens;
    }

    function PRICES() external view returns (address) {
        return _prices;
    }

    function PROJECTS() external view returns (address) {
        return _projects;
    }

    function RULESETS() external view returns (address) {
        return _rulesets;
    }

    function SPLITS() external view returns (address) {
        return _splits;
    }

    function OMNICHAIN_RULESET_OPERATOR() external view returns (address) {
        return _omnichainDeployer;
    }

    function PERMISSIONS() external view returns (address) {
        return _permissions;
    }

    function trustedForwarder() external view returns (address) {
        return _trustedForwarder;
    }
}

contract CoreSupportMockTerminal {
    address internal immutable _store;
    address internal immutable _directory;
    address internal immutable _projects;
    address internal immutable _splits;
    address internal immutable _tokens;
    address internal immutable _feelessAddresses;
    address internal immutable _permissions;
    address internal immutable _trustedForwarder;

    constructor(
        address store_,
        address directory_,
        address projects_,
        address splits_,
        address tokens_,
        address feelessAddresses_,
        address permissions_,
        address trustedForwarder_
    ) {
        _store = store_;
        _directory = directory_;
        _projects = projects_;
        _splits = splits_;
        _tokens = tokens_;
        _feelessAddresses = feelessAddresses_;
        _permissions = permissions_;
        _trustedForwarder = trustedForwarder_;
    }

    function STORE() external view returns (address) {
        return _store;
    }

    function DIRECTORY() external view returns (address) {
        return _directory;
    }

    function PROJECTS() external view returns (address) {
        return _projects;
    }

    function SPLITS() external view returns (address) {
        return _splits;
    }

    function TOKENS() external view returns (address) {
        return _tokens;
    }

    function FEELESS_ADDRESSES() external view returns (address) {
        return _feelessAddresses;
    }

    function PERMISSIONS() external view returns (address) {
        return _permissions;
    }

    function trustedForwarder() external view returns (address) {
        return _trustedForwarder;
    }
}

contract CoreSupportMockTerminalStore {
    address internal immutable _directory;
    address internal immutable _rulesets;
    address internal immutable _prices;

    constructor(address directory_, address rulesets_, address prices_) {
        _directory = directory_;
        _rulesets = rulesets_;
        _prices = prices_;
    }

    function DIRECTORY() external view returns (address) {
        return _directory;
    }

    function RULESETS() external view returns (address) {
        return _rulesets;
    }

    function PRICES() external view returns (address) {
        return _prices;
    }
}

contract CoreSupportMockDirectory {
    address internal immutable _owner;
    address internal immutable _permissions;

    constructor(address owner_, address permissions_) {
        _owner = owner_;
        _permissions = permissions_;
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function PERMISSIONS() external view returns (address) {
        return _permissions;
    }
}

contract CoreSupportMockProjects {
    address internal immutable _owner;
    address internal immutable _trustedForwarder;

    constructor(address owner_, address trustedForwarder_) {
        _owner = owner_;
        _trustedForwarder = trustedForwarder_;
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function trustedForwarder() external view returns (address) {
        return _trustedForwarder;
    }
}

contract CoreSupportMockOwned {
    address internal immutable _owner;

    constructor(address owner_) {
        _owner = owner_;
    }

    function owner() external view returns (address) {
        return _owner;
    }
}

contract CoreSupportMockOwnedPermissioned {
    address internal immutable _owner;
    address internal immutable _permissions;

    constructor(address owner_, address permissions_) {
        _owner = owner_;
        _permissions = permissions_;
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function PERMISSIONS() external view returns (address) {
        return _permissions;
    }
}

contract CoreSupportMockTokens {
    address internal immutable _tokenImplementation;

    constructor(address tokenImplementation_) {
        _tokenImplementation = tokenImplementation_;
    }

    function TOKEN() external view returns (address) {
        return _tokenImplementation;
    }
}

contract CoreSupportMockTokenImplementation {
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
}

contract CoreSupportMockPermissions {
    address internal immutable _trustedForwarder;

    constructor(address trustedForwarder_) {
        _trustedForwarder = trustedForwarder_;
    }

    function trustedForwarder() external view returns (address) {
        return _trustedForwarder;
    }
}

contract CoreSupportMockOmnichain {
    address internal immutable _permissions;
    address internal _directory;

    constructor(address permissions_) {
        _permissions = permissions_;
    }

    function PERMISSIONS() external view returns (address) {
        return _permissions;
    }

    function DIRECTORY() external view returns (address) {
        return _directory;
    }

    function setDirectory(address directory_) external {
        _directory = directory_;
    }
}

contract CoreSupportMockCode {}
