// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBController} from "@bananapus/core-v6/src/JBController.sol";
import {JBDirectory} from "@bananapus/core-v6/src/JBDirectory.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBFeelessAddresses} from "@bananapus/core-v6/src/JBFeelessAddresses.sol";
import {JBFundAccessLimits} from "@bananapus/core-v6/src/JBFundAccessLimits.sol";
import {JBMultiTerminal} from "@bananapus/core-v6/src/JBMultiTerminal.sol";
import {JBPrices} from "@bananapus/core-v6/src/JBPrices.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBRulesets} from "@bananapus/core-v6/src/JBRulesets.sol";
import {JBSplits} from "@bananapus/core-v6/src/JBSplits.sol";
import {JBTerminalStore} from "@bananapus/core-v6/src/JBTerminalStore.sol";
import {JBTokens} from "@bananapus/core-v6/src/JBTokens.sol";
import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";

contract CoreSingletonVerifierGapTest is Test {
    function test_coreWiringVerifierAcceptsNoncanonicalImplementations() public {
        address fundAccessLimits = makeAddr("fundAccessLimits");
        address tokens = makeAddr("tokens");
        address prices = makeAddr("prices");
        address rulesets = makeAddr("rulesets");
        address splits = makeAddr("splits");
        address feelessAddresses = makeAddr("feelessAddresses");
        address omnichainDeployer = makeAddr("omnichainDeployer");

        MockJBProjects maliciousProjects = new MockJBProjects({owner_: makeAddr("projectOwner")});
        MockJBDirectory maliciousDirectory = new MockJBDirectory({
            projects_: address(maliciousProjects), controller_: address(0), terminal_: address(0)
        });
        MockJBController maliciousController = new MockJBController({
            directory_: address(maliciousDirectory),
            fundAccessLimits_: fundAccessLimits,
            tokens_: tokens,
            prices_: prices,
            projects_: address(maliciousProjects),
            rulesets_: rulesets,
            splits_: splits,
            omnichainDeployer_: omnichainDeployer
        });
        maliciousDirectory.setControllerAndTerminal({
            controller_: address(maliciousController), terminal_: makeAddr("placeholderTerminal")
        });
        MockJBTerminalStore maliciousStore =
            new MockJBTerminalStore({directory_: address(maliciousDirectory), rulesets_: rulesets, prices_: prices});
        MockJBMultiTerminal maliciousTerminal = new MockJBMultiTerminal({
            store_: address(maliciousStore),
            directory_: address(maliciousDirectory),
            projects_: address(maliciousProjects),
            splits_: splits,
            tokens_: tokens,
            feelessAddresses_: feelessAddresses
        });
        maliciousDirectory.setControllerAndTerminal({
            controller_: address(maliciousController), terminal_: address(maliciousTerminal)
        });

        VerifyCoreHarness harness = new VerifyCoreHarness();
        harness.setCoreMocks({
            controller_: address(maliciousController),
            terminal_: address(maliciousTerminal),
            terminalStore_: address(maliciousStore),
            directory_: address(maliciousDirectory),
            fundAccessLimits_: fundAccessLimits,
            tokens_: tokens,
            prices_: prices,
            projects_: address(maliciousProjects),
            rulesets_: rulesets,
            splits_: splits,
            feelessAddresses_: feelessAddresses,
            omnichainDeployer_: omnichainDeployer
        });

        // These categories check only spoofable existence/wiring surfaces. They
        // do not prove the project registry, directory, controller, terminal,
        // or terminal store are deploy-all core artifacts or audited runtime
        // bytecode.
        harness.verifyCoreWiring();
    }
}

contract VerifyCoreHarness is Verify {
    function setCoreMocks(
        address controller_,
        address terminal_,
        address terminalStore_,
        address directory_,
        address fundAccessLimits_,
        address tokens_,
        address prices_,
        address projects_,
        address rulesets_,
        address splits_,
        address feelessAddresses_,
        address omnichainDeployer_
    )
        external
    {
        controller = JBController(controller_);
        terminal = JBMultiTerminal(payable(terminal_));
        terminalStore = JBTerminalStore(terminalStore_);
        directory = JBDirectory(directory_);
        fundAccessLimits = JBFundAccessLimits(fundAccessLimits_);
        tokens = JBTokens(tokens_);
        prices = JBPrices(prices_);
        projects = JBProjects(projects_);
        rulesets = JBRulesets(rulesets_);
        splits = JBSplits(splits_);
        feelessAddresses = JBFeelessAddresses(feelessAddresses_);
        omnichainDeployer = JBOmnichainDeployer(omnichainDeployer_);
    }

    function verifyCoreWiring() external {
        _verifyProjectIds();
        _verifyDirectoryWiring();
        _verifyControllerWiring();
        _verifyTerminalWiring();
    }
}

contract MockJBProjects {
    address internal immutable _owner;

    constructor(address owner_) {
        _owner = owner_;
    }

    function count() external pure returns (uint256) {
        return 4;
    }

    function ownerOf(uint256) external view returns (address) {
        return _owner;
    }

    function getApproved(uint256) external pure returns (address) {
        return address(0);
    }
}

contract MockJBDirectory {
    address internal immutable _projects;
    address internal _controller;
    address internal _terminal;

    constructor(address projects_, address controller_, address terminal_) {
        _projects = projects_;
        _controller = controller_;
        _terminal = terminal_;
    }

    function setControllerAndTerminal(address controller_, address terminal_) external {
        _controller = controller_;
        _terminal = terminal_;
    }

    function PROJECTS() external view returns (address) {
        return _projects;
    }

    function isAllowedToSetFirstController(address) external pure returns (bool) {
        return true;
    }

    function controllerOf(uint256) external view returns (address) {
        return _controller;
    }

    function primaryTerminalOf(uint256, address) external view returns (address) {
        return _terminal;
    }

    function terminalsOf(uint256) external view returns (address[] memory terminals) {
        terminals = new address[](1);
        terminals[0] = _terminal;
    }
}

contract MockJBController {
    address internal immutable _directory;
    address internal immutable _fundAccessLimits;
    address internal immutable _tokens;
    address internal immutable _prices;
    address internal immutable _projects;
    address internal immutable _rulesets;
    address internal immutable _splits;
    address internal immutable _omnichainDeployer;

    constructor(
        address directory_,
        address fundAccessLimits_,
        address tokens_,
        address prices_,
        address projects_,
        address rulesets_,
        address splits_,
        address omnichainDeployer_
    ) {
        _directory = directory_;
        _fundAccessLimits = fundAccessLimits_;
        _tokens = tokens_;
        _prices = prices_;
        _projects = projects_;
        _rulesets = rulesets_;
        _splits = splits_;
        _omnichainDeployer = omnichainDeployer_;
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
}

contract MockJBMultiTerminal {
    address internal immutable _store;
    address internal immutable _directory;
    address internal immutable _projects;
    address internal immutable _splits;
    address internal immutable _tokens;
    address internal immutable _feelessAddresses;

    constructor(
        address store_,
        address directory_,
        address projects_,
        address splits_,
        address tokens_,
        address feelessAddresses_
    ) {
        _store = store_;
        _directory = directory_;
        _projects = projects_;
        _splits = splits_;
        _tokens = tokens_;
        _feelessAddresses = feelessAddresses_;
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

    /// @notice Return a valid native accounting context so the test continues to target core
    /// singleton implementation identity rather than reverting on the accounting-context check.
    function accountingContextForTokenOf(uint256, address token) external pure returns (JBAccountingContext memory) {
        return JBAccountingContext({token: token, decimals: 18, currency: uint32(uint160(token))});
    }
}

contract MockJBTerminalStore {
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
