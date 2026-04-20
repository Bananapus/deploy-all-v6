// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";

// ── Core ──
import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBPrices} from "@bananapus/core-v6/src/JBPrices.sol";
import {JBRulesets} from "@bananapus/core-v6/src/JBRulesets.sol";
import {JBDirectory} from "@bananapus/core-v6/src/JBDirectory.sol";
import {JBTokens} from "@bananapus/core-v6/src/JBTokens.sol";
import {JBSplits} from "@bananapus/core-v6/src/JBSplits.sol";
import {JBFeelessAddresses} from "@bananapus/core-v6/src/JBFeelessAddresses.sol";
import {JBFundAccessLimits} from "@bananapus/core-v6/src/JBFundAccessLimits.sol";
import {JBController} from "@bananapus/core-v6/src/JBController.sol";
import {JBTerminalStore} from "@bananapus/core-v6/src/JBTerminalStore.sol";
import {JBMultiTerminal} from "@bananapus/core-v6/src/JBMultiTerminal.sol";

// ── Core Libraries ──
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";

// ── Core Interfaces ──
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// ── 721 Hook ──
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHookProjectDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookProjectDeployer.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";

// ── Buyback Hook ──
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";

// ── Router Terminal ──
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";

// ── Suckers ──
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";

// ── Omnichain Deployer ──
import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";

// ── Croptop ──
import {CTDeployer} from "@croptop/core-v6/src/CTDeployer.sol";
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";
import {CTProjectOwner} from "@croptop/core-v6/src/CTProjectOwner.sol";

// ── Revnet ──
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";

/// @title Verify — Post-Deployment Verification for Juicebox V6
/// @notice Read-only Forge Script that validates all deployed contracts are correctly wired together.
/// @dev Run against a live deployment via:
///   forge script script/Verify.s.sol --rpc-url <RPC_URL> -vvv
///   All checks log pass/fail. Any critical failure causes a revert.
contract Verify is Script {
    // ════════════════════════════════════════════════════════════════════
    //  Errors — one per category so the revert reason is descriptive
    // ════════════════════════════════════════════════════════════════════

    // Reverts when a critical wiring check fails.
    error Verify_CriticalCheckFailed(string reason);

    // ════════════════════════════════════════════════════════════════════
    //  Contract Addresses — set by the caller via constructor args or
    //  environment variables. Using public storage so `run()` can read
    //  them after being populated by the entry-point function.
    // ════════════════════════════════════════════════════════════════════

    // -- Core --
    // The JBProjects ERC-721 registry.
    JBProjects public projects;
    // The JBDirectory that routes projects to terminals/controllers.
    JBDirectory public directory;
    // The JBController that orchestrates project lifecycle.
    JBController public controller;
    // The JBMultiTerminal that handles payments/cashouts.
    JBMultiTerminal public terminal;
    // The JBTerminalStore that holds bookkeeping state.
    JBTerminalStore public terminalStore;
    // The JBTokens contract managing credit/ERC-20 dual token system.
    JBTokens public tokens;
    // The JBFundAccessLimits contract managing payout/surplus limits.
    JBFundAccessLimits public fundAccessLimits;
    // The JBPrices contract for price feed resolution.
    JBPrices public prices;
    // The JBRulesets contract for ruleset lifecycle.
    JBRulesets public rulesets;
    // The JBSplits contract for split distribution.
    JBSplits public splits;
    // The JBFeelessAddresses contract for fee-exempt addresses.
    JBFeelessAddresses public feelessAddresses;
    // The JBPermissions contract for permission management.
    JBPermissions public permissions;

    // -- 721 Hook --
    // The 721 tier hook store.
    JB721TiersHookStore public hookStore;
    // The 721 tier hook deployer.
    JB721TiersHookDeployer public hookDeployer;
    // The 721 project deployer wrapping the hook deployer.
    JB721TiersHookProjectDeployer public hookProjectDeployer;

    // -- Buyback Hook --
    // The buyback hook registry that resolves hooks per project.
    JBBuybackHookRegistry public buybackRegistry;

    // -- Router Terminal --
    // The router terminal registry that resolves terminals per project.
    JBRouterTerminalRegistry public routerTerminalRegistry;
    // The default router terminal instance.
    JBRouterTerminal public routerTerminal;

    // -- Suckers --
    // The sucker registry for cross-chain bridging.
    JBSuckerRegistry public suckerRegistry;

    // -- Omnichain --
    // The omnichain deployer that wraps suckers + 721 hook for cross-chain project launches.
    JBOmnichainDeployer public omnichainDeployer;

    // -- Croptop --
    // The Croptop publisher contract.
    CTPublisher public ctPublisher;
    // The Croptop deployer contract.
    CTDeployer public ctDeployer;
    // The Croptop project owner contract.
    CTProjectOwner public ctProjectOwner;

    // -- Revnet --
    // The REV deployer contract.
    REVDeployer public revDeployer;
    // The REV owner (runtime data hook) contract.
    REVOwner public revOwner;
    // The REV loans contract.
    REVLoans public revLoans;
    // Optional canonical Safe owner to assert during verification.
    address public expectedSafe;

    // -- Address Registry & Defifa (optional) --
    // The address registry contract (optional, not deployed on all chains).
    address public addressRegistry;
    // The Defifa deployer contract (optional, not deployed on all chains).
    address public defifaDeployer;

    // ════════════════════════════════════════════════════════════════════
    //  Counters — track pass/fail for summary
    // ════════════════════════════════════════════════════════════════════

    // Total number of checks that passed.
    uint256 private _passed;
    // Total number of checks that failed.
    uint256 private _failed;
    // Total number of checks skipped (e.g. Uniswap stack not deployed).
    uint256 private _skipped;

    // ════════════════════════════════════════════════════════════════════
    //  Project ID Constants — must match Deploy.s.sol
    // ════════════════════════════════════════════════════════════════════

    // The fee/NANA project is always project 1.
    uint256 private constant _FEE_PROJECT_ID = 1;
    // The CPN/Croptop project is always project 2.
    uint256 private constant _CPN_PROJECT_ID = 2;
    // The REV project is always project 3.
    uint256 private constant _REV_PROJECT_ID = 3;
    // The BAN/Banny project is always project 4.
    uint256 private constant _BAN_PROJECT_ID = 4;

    // ════════════════════════════════════════════════════════════════════
    //  Entry Point
    // ════════════════════════════════════════════════════════════════════

    /// @notice Main entry point. Reads contract addresses from environment variables, then runs all checks.
    /// @dev Set addresses via env vars:
    ///   VERIFY_PROJECTS=0x... VERIFY_DIRECTORY=0x... ... forge script script/Verify.s.sol --rpc-url <RPC_URL> -vvv
    function run() public {
        // Load all contract addresses from environment variables.
        _loadAddresses();

        // Log a header banner for the verification run.
        console.log("========================================");
        console.log("  Juicebox V6 Post-Deploy Verification  ");
        console.log("========================================");
        // Log the chain ID being verified.
        console.log("Chain ID", block.chainid);
        console.log("");

        // Run all verification categories in order.
        _verifyProjectIds();
        _verifyDirectoryWiring();
        _verifyControllerWiring();
        _verifyTerminalWiring();
        _verifyHookRegistries();
        _verifyOmnichain();
        _verifyAddressRegistryAndDefifa();
        _verifyPriceFeeds();

        // Print final summary of results.
        _printSummary();
    }

    // ════════════════════════════════════════════════════════════════════
    //  Address Loading
    // ════════════════════════════════════════════════════════════════════

    /// @dev Reads each contract address from a VERIFY_* environment variable.
    function _loadAddresses() internal {
        // Read the JBProjects address from env.
        projects = JBProjects(vm.envAddress("VERIFY_PROJECTS"));
        // Read the JBDirectory address from env.
        directory = JBDirectory(vm.envAddress("VERIFY_DIRECTORY"));
        // Read the JBController address from env.
        controller = JBController(vm.envAddress("VERIFY_CONTROLLER"));
        // Read the JBMultiTerminal address from env.
        terminal = JBMultiTerminal(payable(vm.envAddress("VERIFY_TERMINAL")));
        // Read the JBTerminalStore address from env.
        terminalStore = JBTerminalStore(vm.envAddress("VERIFY_TERMINAL_STORE"));
        // Read the JBTokens address from env.
        tokens = JBTokens(vm.envAddress("VERIFY_TOKENS"));
        // Read the JBFundAccessLimits address from env.
        fundAccessLimits = JBFundAccessLimits(vm.envAddress("VERIFY_FUND_ACCESS_LIMITS"));
        // Read the JBPrices address from env.
        prices = JBPrices(vm.envAddress("VERIFY_PRICES"));
        // Read the JBRulesets address from env.
        rulesets = JBRulesets(vm.envAddress("VERIFY_RULESETS"));
        // Read the JBSplits address from env.
        splits = JBSplits(vm.envAddress("VERIFY_SPLITS"));
        // Read the JBFeelessAddresses address from env.
        feelessAddresses = JBFeelessAddresses(vm.envAddress("VERIFY_FEELESS"));
        // Read the JBPermissions address from env.
        permissions = JBPermissions(vm.envAddress("VERIFY_PERMISSIONS"));

        // Read the 721 hook store address from env.
        hookStore = JB721TiersHookStore(vm.envAddress("VERIFY_HOOK_STORE"));
        // Read the 721 hook deployer address from env.
        hookDeployer = JB721TiersHookDeployer(vm.envAddress("VERIFY_HOOK_DEPLOYER"));
        // Read the 721 hook project deployer address from env.
        hookProjectDeployer = JB721TiersHookProjectDeployer(vm.envAddress("VERIFY_HOOK_PROJECT_DEPLOYER"));

        // Read the buyback hook registry address from env (address(0) if not deployed on this chain).
        buybackRegistry = JBBuybackHookRegistry(vm.envOr("VERIFY_BUYBACK_REGISTRY", address(0)));

        // Read the router terminal registry address from env (address(0) if not deployed on this chain).
        routerTerminalRegistry =
            JBRouterTerminalRegistry(payable(vm.envOr("VERIFY_ROUTER_TERMINAL_REGISTRY", address(0))));
        // Read the router terminal address from env (address(0) if not deployed on this chain).
        routerTerminal = JBRouterTerminal(payable(vm.envOr("VERIFY_ROUTER_TERMINAL", address(0))));

        // Read the sucker registry address from env.
        suckerRegistry = JBSuckerRegistry(vm.envAddress("VERIFY_SUCKER_REGISTRY"));

        // Read the omnichain deployer address from env.
        omnichainDeployer = JBOmnichainDeployer(vm.envAddress("VERIFY_OMNICHAIN_DEPLOYER"));

        // Read the Croptop publisher address from env.
        ctPublisher = CTPublisher(vm.envAddress("VERIFY_CT_PUBLISHER"));
        // Read the Croptop deployer address from env.
        ctDeployer = CTDeployer(vm.envAddress("VERIFY_CT_DEPLOYER"));
        // Read the Croptop project owner address from env.
        ctProjectOwner = CTProjectOwner(vm.envAddress("VERIFY_CT_PROJECT_OWNER"));

        // Read the REV deployer address from env (address(0) if not deployed on this chain).
        revDeployer = REVDeployer(vm.envOr("VERIFY_REV_DEPLOYER", address(0)));
        // Read the REV owner address from env (address(0) if not deployed on this chain).
        revOwner = REVOwner(vm.envOr("VERIFY_REV_OWNER", address(0)));
        // Read the REV loans address from env (address(0) if not deployed on this chain).
        revLoans = REVLoans(payable(vm.envOr("VERIFY_REV_LOANS", address(0))));
        // Read the canonical Safe owner if provided.
        expectedSafe = vm.envOr("VERIFY_SAFE", address(0));

        // Read the address registry address from env (address(0) if not deployed on this chain).
        addressRegistry = vm.envOr("VERIFY_ADDRESS_REGISTRY", address(0));
        // Read the Defifa deployer address from env (address(0) if not deployed on this chain).
        defifaDeployer = vm.envOr("VERIFY_DEFIFA_DEPLOYER", address(0));

        // On production chains, require the full deployment stack.
        // Testnets may omit optional components, but mainnet and major L2s must fail-closed.
        bool isProductionChain =
            (block.chainid == 1 || block.chainid == 10 || block.chainid == 8453 || block.chainid == 42_161);
        if (isProductionChain) {
            require(
                address(routerTerminal) != address(0), "Verify: VERIFY_ROUTER_TERMINAL required on production chain"
            );
            require(
                address(buybackRegistry) != address(0), "Verify: VERIFY_BUYBACK_REGISTRY required on production chain"
            );
            require(
                address(routerTerminalRegistry) != address(0),
                "Verify: VERIFY_ROUTER_TERMINAL_REGISTRY required on production chain"
            );
            require(address(revDeployer) != address(0), "Verify: VERIFY_REV_DEPLOYER required on production chain");
            require(address(revOwner) != address(0), "Verify: VERIFY_REV_OWNER required on production chain");
            require(address(revLoans) != address(0), "Verify: VERIFY_REV_LOANS required on production chain");
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 1: Project IDs
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates that expected projects exist and the total count is correct.
    function _verifyProjectIds() internal {
        // Log the section header.
        console.log("--- Category 1: Project IDs ---");

        // Read the current total project count from the registry.
        uint256 totalProjects = projects.count();

        // Deploy.s.sol always creates 4 projects (NANA, CPN, REV, BAN) regardless of whether the
        // Uniswap stack is present. The router terminal is optional but does not gate project creation.
        _check(totalProjects >= 4, "Project count >= 4", true);

        // Verify project 1 (NANA/FEE) has an owner (ERC-721 ownerOf does not revert).
        _checkProjectHasOwner(_FEE_PROJECT_ID, "Project 1 (NANA) exists with owner");

        // Verify project 2 (CPN/Croptop) has an owner.
        _checkProjectHasOwner(_CPN_PROJECT_ID, "Project 2 (CPN) exists with owner");

        // Verify project 3 (REV) has an owner.
        _checkProjectHasOwner(_REV_PROJECT_ID, "Project 3 (REV) exists with owner");

        // Verify project 4 (BAN/Banny) has an owner.
        _checkProjectHasOwner(_BAN_PROJECT_ID, "Project 4 (BAN) exists with owner");

        // Log a blank line for readability.
        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 2: Directory Wiring
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates that every project has a controller, a primary terminal, and the terminal is in the list.
    function _verifyDirectoryWiring() internal {
        // Log the section header.
        console.log("--- Category 2: Directory Wiring ---");

        // Verify directory's PROJECTS points to the correct JBProjects contract.
        _check(address(directory.PROJECTS()) == address(projects), "Directory.PROJECTS == JBProjects", true);

        // Check that the controller is allowed to set first controllers.
        _check(
            directory.isAllowedToSetFirstController(address(controller)),
            "Controller allowed to set first controller",
            true
        );

        // Deploy.s.sol always creates and configures all 4 canonical projects regardless of
        // whether the Uniswap stack is present. Check directory wiring for all of them.
        uint256 projectCount = 4;

        // For each canonical project, check directory wiring.
        uint256[4] memory projectIds = [_FEE_PROJECT_ID, _CPN_PROJECT_ID, _REV_PROJECT_ID, _BAN_PROJECT_ID];
        // Corresponding human-readable labels for logging.
        string[4] memory labels = ["NANA(1)", "CPN(2)", "REV(3)", "BAN(4)"];

        // Iterate through each project to validate its directory entries.
        for (uint256 i; i < projectCount; i++) {
            // Read the controller set for this project in the directory.
            IERC165 projectController = directory.controllerOf(projectIds[i]);
            // Verify a controller is actually set (non-zero address).
            _check(address(projectController) != address(0), string.concat(labels[i], " has controller set"), true);

            // Read the primary terminal for this project for the native token.
            IJBTerminal primaryTerm = directory.primaryTerminalOf(projectIds[i], JBConstants.NATIVE_TOKEN);
            // Verify a primary terminal is set.
            _check(
                address(primaryTerm) != address(0),
                string.concat(labels[i], " has primary terminal for native token"),
                true
            );

            // Read the full list of terminals for this project.
            IJBTerminal[] memory terminals = directory.terminalsOf(projectIds[i]);
            // Verify the terminal list is non-empty.
            _check(terminals.length > 0, string.concat(labels[i], " has >= 1 terminal"), true);

            // Verify the main JBMultiTerminal is in the project's terminal list.
            bool terminalFound = false;
            // Search through all terminals for the expected JBMultiTerminal address.
            for (uint256 j; j < terminals.length; j++) {
                // Compare each terminal address to the expected JBMultiTerminal.
                if (address(terminals[j]) == address(terminal)) {
                    // Mark as found when we get a match.
                    terminalFound = true;
                    break;
                }
            }
            // Assert the JBMultiTerminal was found in the project's terminal list.
            _check(terminalFound, string.concat(labels[i], " terminal list contains JBMultiTerminal"), true);
        }

        // Log a blank line for readability.
        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 3: Controller Wiring
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates that the controller's immutable references point to the correct contracts.
    function _verifyControllerWiring() internal {
        // Log the section header.
        console.log("--- Category 3: Controller Wiring ---");

        // Verify the controller's DIRECTORY immutable points to JBDirectory.
        _check(address(controller.DIRECTORY()) == address(directory), "Controller.DIRECTORY == JBDirectory", true);

        // Verify the controller's FUND_ACCESS_LIMITS immutable points to JBFundAccessLimits.
        _check(
            address(controller.FUND_ACCESS_LIMITS()) == address(fundAccessLimits),
            "Controller.FUND_ACCESS_LIMITS == JBFundAccessLimits",
            true
        );

        // Verify the controller's TOKENS immutable points to JBTokens.
        _check(address(controller.TOKENS()) == address(tokens), "Controller.TOKENS == JBTokens", true);

        // Verify the controller's PRICES immutable points to JBPrices.
        _check(address(controller.PRICES()) == address(prices), "Controller.PRICES == JBPrices", true);

        // Verify the controller's PROJECTS immutable points to JBProjects.
        _check(address(controller.PROJECTS()) == address(projects), "Controller.PROJECTS == JBProjects", true);

        // Verify the controller's RULESETS immutable points to JBRulesets.
        _check(address(controller.RULESETS()) == address(rulesets), "Controller.RULESETS == JBRulesets", true);

        // Verify the controller's SPLITS immutable points to JBSplits.
        _check(address(controller.SPLITS()) == address(splits), "Controller.SPLITS == JBSplits", true);

        // Verify the controller's OMNICHAIN_RULESET_OPERATOR points to the omnichain deployer.
        _check(
            controller.OMNICHAIN_RULESET_OPERATOR() == address(omnichainDeployer),
            "Controller.OMNICHAIN_RULESET_OPERATOR == JBOmnichainDeployer",
            true
        );

        // Log a blank line for readability.
        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 4: Terminal Wiring
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates that the terminal's immutable references point to the correct contracts.
    function _verifyTerminalWiring() internal {
        // Log the section header.
        console.log("--- Category 4: Terminal Wiring ---");

        // Verify the terminal's STORE immutable points to JBTerminalStore.
        _check(address(terminal.STORE()) == address(terminalStore), "Terminal.STORE == JBTerminalStore", true);

        // Verify the terminal's DIRECTORY immutable points to JBDirectory.
        _check(address(terminal.DIRECTORY()) == address(directory), "Terminal.DIRECTORY == JBDirectory", true);

        // Verify the terminal's PROJECTS immutable points to JBProjects.
        _check(address(terminal.PROJECTS()) == address(projects), "Terminal.PROJECTS == JBProjects", true);

        // Verify the terminal's SPLITS immutable points to JBSplits.
        _check(address(terminal.SPLITS()) == address(splits), "Terminal.SPLITS == JBSplits", true);

        // Verify the terminal's TOKENS immutable points to JBTokens.
        _check(address(terminal.TOKENS()) == address(tokens), "Terminal.TOKENS == JBTokens", true);

        // Verify the terminal's FEELESS_ADDRESSES immutable points to JBFeelessAddresses.
        _check(
            address(terminal.FEELESS_ADDRESSES()) == address(feelessAddresses),
            "Terminal.FEELESS_ADDRESSES == JBFeelessAddresses",
            true
        );

        // Verify the terminal store's DIRECTORY immutable points to JBDirectory.
        _check(address(terminalStore.DIRECTORY()) == address(directory), "TerminalStore.DIRECTORY == JBDirectory", true);

        // Verify the terminal store's RULESETS immutable points to JBRulesets.
        _check(address(terminalStore.RULESETS()) == address(rulesets), "TerminalStore.RULESETS == JBRulesets", true);

        // Verify the terminal store's PRICES immutable points to JBPrices.
        _check(address(terminalStore.PRICES()) == address(prices), "TerminalStore.PRICES == JBPrices", true);

        // Log a blank line for readability.
        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 5: Hook Registries
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates that hook deployers and registries are correctly configured.
    function _verifyHookRegistries() internal {
        // Log the section header.
        console.log("--- Category 5: Hook Registries ---");

        // Verify the 721 hook deployer has deployed code (is a live contract).
        _check(address(hookDeployer).code.length > 0, "721 hook deployer is deployed", true);

        // Verify the 721 hook store has deployed code (is a live contract).
        _check(address(hookStore).code.length > 0, "721 hook store is deployed", true);

        // Verify the 721 project deployer references the correct hook deployer.
        _check(
            address(hookProjectDeployer.HOOK_DEPLOYER()) == address(hookDeployer),
            "HookProjectDeployer.HOOK_DEPLOYER == JB721TiersHookDeployer",
            true
        );

        // The buyback registry is always deployed, but the default hook requires the Uniswap stack.
        // Use the router terminal presence to determine if the full Uniswap-dependent stack was deployed.
        bool uniswapStackDeployed = address(routerTerminal) != address(0);

        if (address(buybackRegistry) != address(0)) {
            // Verify the buyback registry's PROJECTS points to JBProjects.
            _check(
                address(buybackRegistry.PROJECTS()) == address(projects), "BuybackRegistry.PROJECTS == JBProjects", true
            );

            // The default hook is only set on chains with the full Uniswap stack.
            if (uniswapStackDeployed) {
                _check(
                    address(buybackRegistry.defaultHook()) != address(0), "BuybackRegistry has default hook set", true
                );
            } else {
                _skip("BuybackRegistry default hook check (Uniswap stack not deployed)");
            }
        } else {
            // Skip buyback checks when the registry itself is not deployed.
            _skip("BuybackRegistry checks (not deployed on this chain)");
        }

        // Verify router terminal registry has a non-zero default terminal (only if deployed).
        if (address(routerTerminalRegistry) != address(0)) {
            // Read the default terminal from the router terminal registry.
            _check(
                address(routerTerminalRegistry.defaultTerminal()) != address(0),
                "RouterTerminalRegistry has default terminal set",
                true
            );

            // If the explicit router terminal address was provided, verify it matches the default.
            if (address(routerTerminal) != address(0)) {
                // Verify the default terminal in the registry matches the expected router terminal.
                _check(
                    address(routerTerminalRegistry.defaultTerminal()) == address(routerTerminal),
                    "RouterTerminalRegistry.defaultTerminal == JBRouterTerminal",
                    true
                );

                // Verify the router terminal is marked as feeless.
                _check(feelessAddresses.isFeeless(address(routerTerminal)), "RouterTerminal is feeless", true);
            }
        } else {
            // Skip router terminal checks when not deployed.
            _skip("RouterTerminalRegistry checks (Uniswap stack not deployed)");
        }

        // Log a blank line for readability.
        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 6: Omnichain
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates that the omnichain deployer and sucker registry are correctly wired.
    function _verifyOmnichain() internal {
        // Log the section header.
        console.log("--- Category 6: Omnichain ---");

        // Verify the omnichain deployer has deployed code.
        _check(address(omnichainDeployer).code.length > 0, "OmnichainDeployer is deployed", true);

        // Verify the omnichain deployer's SUCKER_REGISTRY points to the sucker registry.
        _check(
            address(omnichainDeployer.SUCKER_REGISTRY()) == address(suckerRegistry),
            "OmnichainDeployer.SUCKER_REGISTRY == JBSuckerRegistry",
            true
        );

        // Verify the omnichain deployer's HOOK_DEPLOYER points to the 721 hook deployer.
        _check(
            address(omnichainDeployer.HOOK_DEPLOYER()) == address(hookDeployer),
            "OmnichainDeployer.HOOK_DEPLOYER == JB721TiersHookDeployer",
            true
        );

        // Verify the omnichain deployer's PROJECTS points to JBProjects.
        _check(
            address(omnichainDeployer.PROJECTS()) == address(projects), "OmnichainDeployer.PROJECTS == JBProjects", true
        );

        // Verify the sucker registry's DIRECTORY points to JBDirectory.
        _check(
            address(suckerRegistry.DIRECTORY()) == address(directory), "SuckerRegistry.DIRECTORY == JBDirectory", true
        );

        // Verify the sucker registry's PROJECTS points to JBProjects.
        _check(address(suckerRegistry.PROJECTS()) == address(projects), "SuckerRegistry.PROJECTS == JBProjects", true);

        // Verify the controller's OMNICHAIN_RULESET_OPERATOR matches the omnichain deployer.
        _check(
            controller.OMNICHAIN_RULESET_OPERATOR() == address(omnichainDeployer),
            "Controller recognizes OmnichainDeployer as ruleset operator",
            true
        );

        // Verify revnet deployer wiring (only if deployed).
        if (address(revDeployer) != address(0)) {
            // Verify the REV deployer's CONTROLLER points to the correct controller.
            _check(
                address(revDeployer.CONTROLLER()) == address(controller), "REVDeployer.CONTROLLER == JBController", true
            );

            // Verify the REV deployer's SUCKER_REGISTRY points to the sucker registry.
            _check(
                address(revDeployer.SUCKER_REGISTRY()) == address(suckerRegistry),
                "REVDeployer.SUCKER_REGISTRY == JBSuckerRegistry",
                true
            );

            // Verify the REV deployer's HOOK_DEPLOYER points to the 721 hook deployer.
            _check(
                address(revDeployer.HOOK_DEPLOYER()) == address(hookDeployer),
                "REVDeployer.HOOK_DEPLOYER == JB721TiersHookDeployer",
                true
            );

            // Verify the REV deployer's PUBLISHER points to the Croptop publisher.
            _check(
                address(revDeployer.PUBLISHER()) == address(ctPublisher), "REVDeployer.PUBLISHER == CTPublisher", true
            );

            // Verify the REV deployer's LOANS points to the REV loans contract.
            if (address(revLoans) != address(0)) {
                // Compare the LOANS() address against the expected REVLoans contract.
                _check(revDeployer.LOANS() == address(revLoans), "REVDeployer.LOANS == REVLoans", true);
            }

            // Verify the REV deployer's OWNER points to the REV owner contract.
            if (address(revOwner) != address(0)) {
                _check(revDeployer.OWNER() == address(revOwner), "REVDeployer.OWNER == REVOwner", true);
                // Verify the REV owner's DEPLOYER points back to the REV deployer.
                _check(address(revOwner.DEPLOYER()) == address(revDeployer), "REVOwner.DEPLOYER == REVDeployer", true);
            }
        } else {
            // Skip revnet checks when not deployed.
            _skip("REVDeployer checks (not deployed on this chain)");
        }

        // Log a blank line for readability.
        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 7: Address Registry & Defifa
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates that the address registry and Defifa deployer are deployed (if configured).
    function _verifyAddressRegistryAndDefifa() internal {
        // Log the section header.
        console.log("--- Category 7: Address Registry & Defifa ---");

        // If the address registry is not set, skip these checks.
        if (addressRegistry == address(0)) {
            _skip("AddressRegistry not deployed (VERIFY_ADDRESS_REGISTRY not set)");
        } else {
            // Verify the registry is deployed (has code).
            _check(addressRegistry.code.length > 0, "AddressRegistry has code", true);
        }

        // If the Defifa deployer is not set, skip these checks.
        if (defifaDeployer == address(0)) {
            _skip("DefifaDeployer not deployed (VERIFY_DEFIFA_DEPLOYER not set)");
        } else {
            // Verify the Defifa deployer is deployed (has code).
            _check(defifaDeployer.code.length > 0, "DefifaDeployer has code", true);
        }

        // Log a blank line for readability.
        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 8: Price Feeds
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates that price feeds are configured and return sane values.
    function _verifyPriceFeeds() internal {
        // Log the section header.
        console.log("--- Category 8: Price Feeds ---");

        // Check the ETH/USD price feed (pricingCurrency=USD, unitCurrency=NATIVE_TOKEN).
        IJBPriceFeed ethUsdFeed = prices.priceFeedFor(0, JBCurrencyIds.USD, uint32(uint160(JBConstants.NATIVE_TOKEN)));
        // Verify the ETH/USD feed address is set (non-zero).
        _check(address(ethUsdFeed) != address(0), "ETH/USD price feed is configured", true);

        // If the feed is configured, query the current price and validate it is sane.
        if (address(ethUsdFeed) != address(0)) {
            // Try to read the current ETH/USD price with 18 decimals.
            try ethUsdFeed.currentUnitPrice(18) returns (uint256 ethPrice) {
                // ETH price must be above $100 (100e18 in 18-decimal fixed point).
                bool aboveMin = ethPrice > 100e18;
                // ETH price must be below $1,000,000 (1_000_000e18 in 18-decimal fixed point).
                bool belowMax = ethPrice < 1_000_000e18;
                // Log the actual price for debugging.
                console.log("  ETH/USD price (18 dec)", ethPrice);
                // Check the lower bound.
                _check(aboveMin, "ETH/USD price > $100", true);
                // Check the upper bound.
                _check(belowMax, "ETH/USD price < $1,000,000", true);
            } catch {
                // Feed reverted — mark as critical failure (staleness, sequencer down, etc).
                _check(false, "ETH/USD feed.currentUnitPrice() did not revert", true);
            }
        }

        // Check the inverse feed: ETH/NATIVE_TOKEN (should be a matching/identity feed).
        IJBPriceFeed ethNativeFeed =
            prices.priceFeedFor(0, JBCurrencyIds.ETH, uint32(uint160(JBConstants.NATIVE_TOKEN)));
        // Verify the ETH/NATIVE feed address is set.
        _check(address(ethNativeFeed) != address(0), "ETH/NATIVE_TOKEN matching feed is configured", true);

        // If the matching feed exists, verify it returns ~1e18 (identity price).
        if (address(ethNativeFeed) != address(0)) {
            // Try to read the matching feed price (should be 1:1 = 1e18).
            try ethNativeFeed.currentUnitPrice(18) returns (uint256 matchPrice) {
                // The price should be exactly 1e18 for a matching/identity feed.
                bool isUnity = matchPrice == 1e18;
                // Log the actual price for debugging.
                console.log("  ETH/NATIVE price (18 dec)", matchPrice);
                // Verify the price is exactly 1:1.
                _check(isUnity, "ETH/NATIVE matching feed returns 1e18", true);
            } catch {
                // Feed reverted — mark as failure.
                _check(false, "ETH/NATIVE matching feed did not revert", true);
            }
        }

        // Check the USD/NATIVE_TOKEN feed (inverse of ETH/USD, should also be set).
        IJBPriceFeed usdNativeFeed = prices.priceFeedFor(0, JBCurrencyIds.USD, JBCurrencyIds.ETH);
        // Verify the USD/ETH feed is configured (this is the same feed as ETH/USD, just different key).
        _check(address(usdNativeFeed) != address(0), "USD/ETH price feed is configured", false);

        // Check the USDC/USD price feed — registered during deployment but not previously verified.
        address usdc;
        if (block.chainid == 1) usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        else if (block.chainid == 11_155_111) usdc = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        else if (block.chainid == 10) usdc = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
        else if (block.chainid == 11_155_420) usdc = 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;
        else if (block.chainid == 8453) usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        else if (block.chainid == 84_532) usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        else if (block.chainid == 42_161) usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        else if (block.chainid == 421_614) usdc = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;

        if (usdc != address(0)) {
            // forge-lint: disable-next-line(unsafe-typecast)
            IJBPriceFeed usdcUsdFeed = prices.priceFeedFor(0, JBCurrencyIds.USD, uint32(uint160(usdc)));
            _check(address(usdcUsdFeed) != address(0), "USDC/USD price feed is configured", true);

            if (address(usdcUsdFeed) != address(0)) {
                try usdcUsdFeed.currentUnitPrice(18) returns (uint256 usdcPrice) {
                    // USDC should be ~$1 (between $0.90 and $1.10).
                    bool aboveMin = usdcPrice > 0.9e18;
                    bool belowMax = usdcPrice < 1.1e18;
                    console.log("  USDC/USD price (18 dec)", usdcPrice);
                    _check(aboveMin, "USDC/USD price > $0.90", true);
                    _check(belowMax, "USDC/USD price < $1.10", true);
                } catch {
                    _check(false, "USDC/USD feed.currentUnitPrice() did not revert", true);
                }
            }
        }

        // Verify oracle provenance — ensure the protocol is using the expected Chainlink feeds.
        // Only check mainnet ETH/USD as a starting point; expand to other chains as needed.
        if (block.chainid == 1) {
            // Mainnet ETH/USD Chainlink aggregator.
            address expectedEthUsdFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            // Look up the feed the protocol is actually using.
            try prices.priceFeedFor({
                projectId: 0,
                pricingCurrency: JBCurrencyIds.USD,
                unitCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }) returns (
                IJBPriceFeed feed
            ) {
                // Verify the feed address matches the canonical Chainlink ETH/USD aggregator.
                _check(
                    address(feed) == expectedEthUsdFeed,
                    "ETH/USD feed matches expected Chainlink aggregator (mainnet)",
                    false
                );
            } catch {
                // priceFeedFor reverted — already covered by earlier checks, skip provenance.
                _skip("ETH/USD oracle provenance (feed lookup reverted)");
            }
        }

        // Log a blank line for readability.
        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Internal Helpers
    // ════════════════════════════════════════════════════════════════════

    /// @dev Checks whether a project exists by calling ownerOf on the ERC-721.
    /// @param projectId The project ID to check.
    /// @param label Human-readable label for the check.
    function _checkProjectHasOwner(uint256 projectId, string memory label) internal {
        // Try calling ownerOf; if the project does not exist, this reverts.
        try projects.ownerOf(projectId) returns (address owner) {
            // Verify the owner is not the zero address (burned token).
            _check(owner != address(0), label, true);
            if (expectedSafe != address(0)) {
                _check(owner == expectedSafe, string.concat(label, " and is canonically safe-owned"), true);
            }
        } catch {
            // ownerOf reverted, meaning the project does not exist.
            _check(false, label, true);
        }
    }

    /// @dev Core check function. Logs pass/fail, increments counters, reverts on critical failure.
    /// @param condition Whether the check passed.
    /// @param label Human-readable description of the check.
    /// @param critical If true, reverts on failure instead of just logging.
    function _check(bool condition, string memory label, bool critical) internal {
        if (condition) {
            // Increment the pass counter.
            _passed++;
            // Log the passing check with a PASS prefix.
            console.log(string.concat("  [PASS] ", label));
        } else {
            // Increment the fail counter.
            _failed++;
            // Log the failing check with a FAIL prefix.
            console.log(string.concat("  [FAIL] ", label));
            // If this is a critical check, revert with a descriptive error.
            if (critical) {
                revert Verify_CriticalCheckFailed(label);
            }
        }
    }

    /// @dev Logs a skipped check and increments the skip counter.
    /// @param label Human-readable description of the skipped check.
    function _skip(string memory label) internal {
        // Increment the skip counter.
        _skipped++;
        // Log the skipped check with a SKIP prefix.
        console.log(string.concat("  [SKIP] ", label));
    }

    /// @dev Prints a final summary of all verification results.
    function _printSummary() internal view {
        // Log the summary header.
        console.log("========================================");
        console.log("            VERIFICATION SUMMARY         ");
        console.log("========================================");
        // Log the total number of passing checks.
        console.log("Passed", _passed);
        // Log the total number of failing checks.
        console.log("Failed", _failed);
        // Log the total number of skipped checks.
        console.log("Skipped", _skipped);

        // If all checks passed, log a success message.
        if (_failed == 0) {
            // Indicate the deployment is verified.
            console.log("Result: ALL CHECKS PASSED");
        } else {
            // Indicate there were failures (script should have already reverted on critical ones).
            console.log("Result: SOME CHECKS FAILED");
        }
    }
}
