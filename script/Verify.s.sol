// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";

// ── Core ──
import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
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
import {JBChainlinkV3PriceFeed} from "@bananapus/core-v6/src/JBChainlinkV3PriceFeed.sol";
import {JBChainlinkV3SequencerPriceFeed} from "@bananapus/core-v6/src/JBChainlinkV3SequencerPriceFeed.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AggregatorV2V3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// ── 721 Hook ──
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHookProjectDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookProjectDeployer.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721CheckpointsDeployer} from "@bananapus/721-hook-v6/src/JB721CheckpointsDeployer.sol";
import {IJB721CheckpointsDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721CheckpointsDeployer.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {IJB721TiersHook} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHook.sol";

// ── Buyback Hook ──
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";

// ── Router Terminal ──
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";

// ── Suckers ──
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {JBSuckersPair} from "@bananapus/suckers-v6/src/structs/JBSuckersPair.sol";

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

// ── Defifa ──
import {DefifaDeployer} from "@ballkidz/defifa/src/DefifaDeployer.sol";
import {DefifaGovernor} from "@ballkidz/defifa/src/DefifaGovernor.sol";
import {DefifaHook} from "@ballkidz/defifa/src/DefifaHook.sol";

// ── Phase 11 Periphery ──
import {JBProjectHandles} from "@bananapus/project-handles-v6/src/JBProjectHandles.sol";
import {JB721Distributor} from "@bananapus/distributor-v6/src/JB721Distributor.sol";
import {JBTokenDistributor} from "@bananapus/distributor-v6/src/JBTokenDistributor.sol";
import {JBProjectPayer} from "@bananapus/project-payer-v6/src/JBProjectPayer.sol";
import {JBProjectPayerDeployer} from "@bananapus/project-payer-v6/src/JBProjectPayerDeployer.sol";

import {IJBToken} from "@bananapus/core-v6/src/interfaces/IJBToken.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {JBERC20} from "@bananapus/core-v6/src/JBERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
    DefifaDeployer public defifaDeployer;

    // Dedicated Defifa hook store (separate from shared 721 hook store).
    JB721TiersHookStore public defifaHookStore;
    // Expected trusted forwarder address.
    address public expectedTrustedForwarder;

    // -- Phase 11 Periphery (optional on testnets) --
    // ENS-backed project handle registry.
    JBProjectHandles public projectHandles;
    // 721 staking reward distributor.
    JB721Distributor public distributor721;
    // ERC-20 staking reward distributor.
    JBTokenDistributor public tokenDistributor;
    // Project payer clone deployer.
    JBProjectPayerDeployer public projectPayerDeployer;

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
    // Phase 11 distributor vesting rounds must match Deploy.s.sol.
    uint256 private constant _VESTING_ROUNDS = 52;

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
        _verifyAllowlists();
        _verifyRoutes();
        _verifyPeripheryExtensions();
        _verifyTokenImplementation();
        _verifyOwnership();
        _verifyPermissionsAndForwarder();
        _verifyCroptopImmutables();
        _verifyHookDeployerImmutables();
        _verifyRevImmutables();
        _verifyCanonicalProjectEconomics();
        _verifySuckerManifest();
        _verifyExternalAddresses();

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
        buybackRegistry = JBBuybackHookRegistry(vm.envOr({name: "VERIFY_BUYBACK_REGISTRY", defaultValue: address(0)}));

        // Read the router terminal registry address from env (address(0) if not deployed on this chain).
        routerTerminalRegistry = JBRouterTerminalRegistry(
            payable(vm.envOr({name: "VERIFY_ROUTER_TERMINAL_REGISTRY", defaultValue: address(0)}))
        );
        // Read the router terminal address from env (address(0) if not deployed on this chain).
        routerTerminal = JBRouterTerminal(payable(vm.envOr({name: "VERIFY_ROUTER_TERMINAL", defaultValue: address(0)})));

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
        revDeployer = REVDeployer(vm.envOr({name: "VERIFY_REV_DEPLOYER", defaultValue: address(0)}));
        // Read the REV owner address from env (address(0) if not deployed on this chain).
        revOwner = REVOwner(vm.envOr({name: "VERIFY_REV_OWNER", defaultValue: address(0)}));
        // Read the REV loans address from env (address(0) if not deployed on this chain).
        revLoans = REVLoans(payable(vm.envOr({name: "VERIFY_REV_LOANS", defaultValue: address(0)})));
        // Read the canonical Safe owner if provided.
        expectedSafe = vm.envOr({name: "VERIFY_SAFE", defaultValue: address(0)});

        // Read the address registry address from env (address(0) if not deployed on this chain).
        addressRegistry = vm.envOr({name: "VERIFY_ADDRESS_REGISTRY", defaultValue: address(0)});
        // Read the Defifa deployer address from env (address(0) if not deployed on this chain).
        defifaDeployer = DefifaDeployer(vm.envOr({name: "VERIFY_DEFIFA_DEPLOYER", defaultValue: address(0)}));

        // Read the dedicated Defifa hook store address (separate from shared 721 hook store).
        defifaHookStore = JB721TiersHookStore(vm.envOr({name: "VERIFY_DEFIFA_HOOK_STORE", defaultValue: address(0)}));
        // Read the expected trusted forwarder address.
        expectedTrustedForwarder = vm.envOr({name: "VERIFY_TRUSTED_FORWARDER", defaultValue: address(0)});

        // Read Phase 11 periphery addresses from env (address(0) if intentionally omitted on a testnet).
        projectHandles = JBProjectHandles(vm.envOr({name: "VERIFY_PROJECT_HANDLES", defaultValue: address(0)}));
        distributor721 = JB721Distributor(payable(vm.envOr({name: "VERIFY_721_DISTRIBUTOR", defaultValue: address(0)})));
        tokenDistributor =
            JBTokenDistributor(payable(vm.envOr({name: "VERIFY_TOKEN_DISTRIBUTOR", defaultValue: address(0)})));
        projectPayerDeployer =
            JBProjectPayerDeployer(vm.envOr({name: "VERIFY_PROJECT_PAYER_DEPLOYER", defaultValue: address(0)}));

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
            require(addressRegistry != address(0), "Verify: VERIFY_ADDRESS_REGISTRY required on production chain");
            require(
                address(defifaDeployer) != address(0), "Verify: VERIFY_DEFIFA_DEPLOYER required on production chain"
            );
            require(
                address(projectHandles) != address(0), "Verify: VERIFY_PROJECT_HANDLES required on production chain"
            );
            require(
                address(distributor721) != address(0), "Verify: VERIFY_721_DISTRIBUTOR required on production chain"
            );
            require(
                address(tokenDistributor) != address(0), "Verify: VERIFY_TOKEN_DISTRIBUTOR required on production chain"
            );
            require(
                address(projectPayerDeployer) != address(0),
                "Verify: VERIFY_PROJECT_PAYER_DEPLOYER required on production chain"
            );
            require(expectedSafe != address(0), "Verify: VERIFY_SAFE required on production chain");
            require(
                expectedTrustedForwarder != address(0), "Verify: VERIFY_TRUSTED_FORWARDER required on production chain"
            );
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
        _check({condition: totalProjects >= 4, label: "Project count >= 4", critical: true});

        // Verify project 1 (NANA/FEE) has an owner (ERC-721 ownerOf does not revert).
        _checkProjectHasOwner({projectId: _FEE_PROJECT_ID, label: "Project 1 (NANA) exists with owner"});

        // Verify project 2 (CPN/Croptop) has an owner.
        _checkProjectHasOwner({projectId: _CPN_PROJECT_ID, label: "Project 2 (CPN) exists with owner"});

        // Verify project 3 (REV) has an owner.
        _checkProjectHasOwner({projectId: _REV_PROJECT_ID, label: "Project 3 (REV) exists with owner"});

        // Verify project 4 (BAN/Banny) has an owner.
        _checkProjectHasOwner({projectId: _BAN_PROJECT_ID, label: "Project 4 (BAN) exists with owner"});

        _verifyCanonicalProjectIdentities();

        // No stale ERC-721 approvals on canonical projects.
        _check({
            condition: projects.getApproved(_FEE_PROJECT_ID) == address(0),
            label: "Project 1 (NANA) has no stale approval",
            critical: true
        });
        _check({
            condition: projects.getApproved(_CPN_PROJECT_ID) == address(0),
            label: "Project 2 (CPN) has no stale approval",
            critical: true
        });
        _check({
            condition: projects.getApproved(_REV_PROJECT_ID) == address(0),
            label: "Project 3 (REV) has no stale approval",
            critical: true
        });
        _check({
            condition: projects.getApproved(_BAN_PROJECT_ID) == address(0),
            label: "Project 4 (BAN) has no stale approval",
            critical: true
        });

        // Log a blank line for readability.
        console.log("");
    }

    function _verifyCanonicalProjectIdentities() internal {
        if (address(revDeployer) == address(0)) {
            _skip("Canonical project identity checks (REVDeployer not configured)");
            return;
        }

        _verifyCanonicalRevnetProject({projectId: _FEE_PROJECT_ID, symbol: "NANA", label: "NANA(1)"});
        _verifyCanonicalRevnetProject({projectId: _CPN_PROJECT_ID, symbol: "CPN", label: "CPN(2)"});
        _verifyCanonicalRevnetProject({projectId: _REV_PROJECT_ID, symbol: "REV", label: "REV(3)"});
        _verifyCanonicalRevnetProject({projectId: _BAN_PROJECT_ID, symbol: "BAN", label: "BAN(4)"});

        if (address(revOwner) != address(0)) {
            IJB721TiersHook bannyHook = revOwner.tiered721HookOf(_BAN_PROJECT_ID);
            _check({
                condition: address(bannyHook) != address(0), label: "BAN(4) has Banny 721 hook recorded", critical: true
            });
            if (address(bannyHook) != address(0)) {
                _check({
                    condition: bannyHook.PROJECT_ID() == _BAN_PROJECT_ID,
                    label: "Banny hook PROJECT_ID == 4",
                    critical: true
                });
                _check({
                    condition: address(bannyHook.STORE()) == address(hookStore),
                    label: "Banny hook uses canonical 721 store",
                    critical: true
                });
                _check({
                    condition: _metadataSymbolIs({token: address(bannyHook), expected: "BANNY"}),
                    label: "Banny hook symbol == BANNY",
                    critical: true
                });
            }
        } else {
            _skip("Banny 721 hook identity checks (REVOwner not configured)");
        }
    }

    function _verifyCanonicalRevnetProject(uint256 projectId, string memory symbol, string memory label) internal {
        try projects.ownerOf(projectId) returns (address owner) {
            _check({
                condition: owner == address(revDeployer),
                label: string.concat(label, " project NFT is owned by REVDeployer"),
                critical: true
            });
        } catch {
            _check({condition: false, label: string.concat(label, " project NFT owner readable"), critical: true});
        }

        _check({
            condition: revDeployer.hashedEncodedConfigurationOf(projectId) != bytes32(0),
            label: string.concat(label, " has REVDeployer configuration hash"),
            critical: true
        });

        address token = address(tokens.tokenOf(projectId));
        _check({
            condition: token != address(0), label: string.concat(label, " project token is deployed"), critical: true
        });
        if (token != address(0)) {
            _check({
                condition: _metadataSymbolIs({token: token, expected: symbol}),
                label: string.concat(label, " project token symbol matches"),
                critical: true
            });
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 2: Directory Wiring
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates that every project has a controller, a primary terminal, and the terminal is in the list.
    function _verifyDirectoryWiring() internal {
        // Log the section header.
        console.log("--- Category 2: Directory Wiring ---");

        // Verify directory's PROJECTS points to the correct JBProjects contract.
        _check({
            condition: address(directory.PROJECTS()) == address(projects),
            label: "Directory.PROJECTS == JBProjects",
            critical: true
        });

        // Check that the controller is allowed to set first controllers.
        // Note: Cannot prove no OTHER controllers are allowed (non-enumerable mapping).
        // Operators must reconcile via archive logs or accept this limitation.
        _check({
            condition: directory.isAllowedToSetFirstController(address(controller)),
            label: "Controller allowed to set first controller",
            critical: true
        });

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
            _check({
                condition: address(projectController) != address(0),
                label: string.concat(labels[i], " has controller set"),
                critical: true
            });

            // Read the primary terminal for this project for the native token.
            IJBTerminal primaryTerm = directory.primaryTerminalOf(projectIds[i], JBConstants.NATIVE_TOKEN);
            // Verify a primary terminal is set.
            _check({
                condition: address(primaryTerm) != address(0),
                label: string.concat(labels[i], " has primary terminal for native token"),
                critical: true
            });

            // Read the full list of terminals for this project.
            IJBTerminal[] memory terminals = directory.terminalsOf(projectIds[i]);
            // Verify the terminal list is non-empty.
            _check({
                condition: terminals.length > 0, label: string.concat(labels[i], " has >= 1 terminal"), critical: true
            });

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
            _check({
                condition: terminalFound,
                label: string.concat(labels[i], " terminal list contains JBMultiTerminal"),
                critical: true
            });
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
        _check({
            condition: address(controller.DIRECTORY()) == address(directory),
            label: "Controller.DIRECTORY == JBDirectory",
            critical: true
        });

        // Verify the controller's FUND_ACCESS_LIMITS immutable points to JBFundAccessLimits.
        _check({
            condition: address(controller.FUND_ACCESS_LIMITS()) == address(fundAccessLimits),
            label: "Controller.FUND_ACCESS_LIMITS == JBFundAccessLimits",
            critical: true
        });

        // Verify the controller's TOKENS immutable points to JBTokens.
        _check({
            condition: address(controller.TOKENS()) == address(tokens),
            label: "Controller.TOKENS == JBTokens",
            critical: true
        });

        // Verify the controller's PRICES immutable points to JBPrices.
        _check({
            condition: address(controller.PRICES()) == address(prices),
            label: "Controller.PRICES == JBPrices",
            critical: true
        });

        // Verify the controller's PROJECTS immutable points to JBProjects.
        _check({
            condition: address(controller.PROJECTS()) == address(projects),
            label: "Controller.PROJECTS == JBProjects",
            critical: true
        });

        // Verify the controller's RULESETS immutable points to JBRulesets.
        _check({
            condition: address(controller.RULESETS()) == address(rulesets),
            label: "Controller.RULESETS == JBRulesets",
            critical: true
        });

        // Verify the controller's SPLITS immutable points to JBSplits.
        _check({
            condition: address(controller.SPLITS()) == address(splits),
            label: "Controller.SPLITS == JBSplits",
            critical: true
        });

        // Verify the controller's OMNICHAIN_RULESET_OPERATOR points to the omnichain deployer.
        _check({
            condition: controller.OMNICHAIN_RULESET_OPERATOR() == address(omnichainDeployer),
            label: "Controller.OMNICHAIN_RULESET_OPERATOR == JBOmnichainDeployer",
            critical: true
        });

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
        _check({
            condition: address(terminal.STORE()) == address(terminalStore),
            label: "Terminal.STORE == JBTerminalStore",
            critical: true
        });

        // Verify the terminal's DIRECTORY immutable points to JBDirectory.
        _check({
            condition: address(terminal.DIRECTORY()) == address(directory),
            label: "Terminal.DIRECTORY == JBDirectory",
            critical: true
        });

        // Verify the terminal's PROJECTS immutable points to JBProjects.
        _check({
            condition: address(terminal.PROJECTS()) == address(projects),
            label: "Terminal.PROJECTS == JBProjects",
            critical: true
        });

        // Verify the terminal's SPLITS immutable points to JBSplits.
        _check({
            condition: address(terminal.SPLITS()) == address(splits),
            label: "Terminal.SPLITS == JBSplits",
            critical: true
        });

        // Verify the terminal's TOKENS immutable points to JBTokens.
        _check({
            condition: address(terminal.TOKENS()) == address(tokens),
            label: "Terminal.TOKENS == JBTokens",
            critical: true
        });

        // Verify the terminal's FEELESS_ADDRESSES immutable points to JBFeelessAddresses.
        _check({
            condition: address(terminal.FEELESS_ADDRESSES()) == address(feelessAddresses),
            label: "Terminal.FEELESS_ADDRESSES == JBFeelessAddresses",
            critical: true
        });

        // Verify the terminal store's DIRECTORY immutable points to JBDirectory.
        _check({
            condition: address(terminalStore.DIRECTORY()) == address(directory),
            label: "TerminalStore.DIRECTORY == JBDirectory",
            critical: true
        });

        // Verify the terminal store's RULESETS immutable points to JBRulesets.
        _check({
            condition: address(terminalStore.RULESETS()) == address(rulesets),
            label: "TerminalStore.RULESETS == JBRulesets",
            critical: true
        });

        // Verify the terminal store's PRICES immutable points to JBPrices.
        _check({
            condition: address(terminalStore.PRICES()) == address(prices),
            label: "TerminalStore.PRICES == JBPrices",
            critical: true
        });

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
        _check({
            condition: address(hookDeployer).code.length > 0, label: "721 hook deployer is deployed", critical: true
        });

        // Verify the 721 hook store has deployed code (is a live contract).
        _check({condition: address(hookStore).code.length > 0, label: "721 hook store is deployed", critical: true});

        // Verify the 721 project deployer references the correct hook deployer.
        _check({
            condition: address(hookProjectDeployer.HOOK_DEPLOYER()) == address(hookDeployer),
            label: "HookProjectDeployer.HOOK_DEPLOYER == JB721TiersHookDeployer",
            critical: true
        });

        // The buyback registry is always deployed, but the default hook requires the Uniswap stack.
        // Use the router terminal presence to determine if the full Uniswap-dependent stack was deployed.
        bool uniswapStackDeployed = address(routerTerminal) != address(0);

        if (address(buybackRegistry) != address(0)) {
            // Verify the buyback registry's PROJECTS points to JBProjects.
            _check({
                condition: address(buybackRegistry.PROJECTS()) == address(projects),
                label: "BuybackRegistry.PROJECTS == JBProjects",
                critical: true
            });

            // The default hook is only set on chains with the full Uniswap stack.
            if (uniswapStackDeployed) {
                _check({
                    condition: address(buybackRegistry.defaultHook()) != address(0),
                    label: "BuybackRegistry has default hook set",
                    critical: true
                });

                // Verify project 1 has an explicit buyback hook pinned.
                _check({
                    condition: address(buybackRegistry.hookOf(_FEE_PROJECT_ID)) != address(0),
                    label: "NANA(1) has explicit buyback hook pinned",
                    critical: true
                });
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
            _check({
                condition: address(routerTerminalRegistry.defaultTerminal()) != address(0),
                label: "RouterTerminalRegistry has default terminal set",
                critical: true
            });

            // If the explicit router terminal address was provided, verify it matches the default.
            if (address(routerTerminal) != address(0)) {
                // Verify the default terminal in the registry matches the expected router terminal.
                _check({
                    condition: address(routerTerminalRegistry.defaultTerminal()) == address(routerTerminal),
                    label: "RouterTerminalRegistry.defaultTerminal == JBRouterTerminal",
                    critical: true
                });

                // Verify the router terminal is marked as feeless.
                _check({
                    condition: feelessAddresses.isFeelessFor({addr: address(routerTerminal), projectId: 0}),
                    label: "RouterTerminal is feeless",
                    critical: true
                });
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
        _check({
            condition: address(omnichainDeployer).code.length > 0,
            label: "OmnichainDeployer is deployed",
            critical: true
        });

        // Verify the omnichain deployer's SUCKER_REGISTRY points to the sucker registry.
        _check({
            condition: address(omnichainDeployer.SUCKER_REGISTRY()) == address(suckerRegistry),
            label: "OmnichainDeployer.SUCKER_REGISTRY == JBSuckerRegistry",
            critical: true
        });

        // Verify the omnichain deployer's HOOK_DEPLOYER points to the 721 hook deployer.
        _check({
            condition: address(omnichainDeployer.HOOK_DEPLOYER()) == address(hookDeployer),
            label: "OmnichainDeployer.HOOK_DEPLOYER == JB721TiersHookDeployer",
            critical: true
        });

        // Verify the omnichain deployer's PROJECTS points to JBProjects.
        _check({
            condition: address(omnichainDeployer.PROJECTS()) == address(projects),
            label: "OmnichainDeployer.PROJECTS == JBProjects",
            critical: true
        });

        // Verify the sucker registry's DIRECTORY points to JBDirectory.
        _check({
            condition: address(suckerRegistry.DIRECTORY()) == address(directory),
            label: "SuckerRegistry.DIRECTORY == JBDirectory",
            critical: true
        });

        // Verify the sucker registry's PROJECTS points to JBProjects.
        _check({
            condition: address(suckerRegistry.PROJECTS()) == address(projects),
            label: "SuckerRegistry.PROJECTS == JBProjects",
            critical: true
        });

        // Verify the controller's OMNICHAIN_RULESET_OPERATOR matches the omnichain deployer.
        _check({
            condition: controller.OMNICHAIN_RULESET_OPERATOR() == address(omnichainDeployer),
            label: "Controller recognizes OmnichainDeployer as ruleset operator",
            critical: true
        });

        // Verify revnet deployer wiring (only if deployed).
        if (address(revDeployer) != address(0)) {
            // Verify the REV deployer's CONTROLLER points to the correct controller.
            _check({
                condition: address(revDeployer.CONTROLLER()) == address(controller),
                label: "REVDeployer.CONTROLLER == JBController",
                critical: true
            });

            // Verify the REV deployer's SUCKER_REGISTRY points to the sucker registry.
            _check({
                condition: address(revDeployer.SUCKER_REGISTRY()) == address(suckerRegistry),
                label: "REVDeployer.SUCKER_REGISTRY == JBSuckerRegistry",
                critical: true
            });

            // Verify the REV deployer's HOOK_DEPLOYER points to the 721 hook deployer.
            _check({
                condition: address(revDeployer.HOOK_DEPLOYER()) == address(hookDeployer),
                label: "REVDeployer.HOOK_DEPLOYER == JB721TiersHookDeployer",
                critical: true
            });

            // Verify the REV deployer's PUBLISHER points to the Croptop publisher.
            _check({
                condition: address(revDeployer.PUBLISHER()) == address(ctPublisher),
                label: "REVDeployer.PUBLISHER == CTPublisher",
                critical: true
            });

            // Verify the REV deployer's LOANS points to the REV loans contract.
            if (address(revLoans) != address(0)) {
                // Compare the LOANS() address against the expected REVLoans contract.
                _check({
                    condition: address(revDeployer.LOANS()) == address(revLoans),
                    label: "REVDeployer.LOANS == REVLoans",
                    critical: true
                });
            }

            // Verify the REV deployer's OWNER points to the REV owner contract.
            if (address(revOwner) != address(0)) {
                _check({
                    condition: revDeployer.OWNER() == address(revOwner),
                    label: "REVDeployer.OWNER == REVOwner",
                    critical: true
                });
                // Verify the REV owner's DEPLOYER points back to the REV deployer.
                _check({
                    condition: address(revOwner.DEPLOYER()) == address(revDeployer),
                    label: "REVOwner.DEPLOYER == REVDeployer",
                    critical: true
                });
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
            _check({condition: addressRegistry.code.length > 0, label: "AddressRegistry has code", critical: true});
        }

        // If the Defifa deployer is not set, skip these checks.
        if (address(defifaDeployer) == address(0)) {
            _skip("DefifaDeployer not deployed (VERIFY_DEFIFA_DEPLOYER not set)");
        } else {
            // Verify the Defifa deployer is deployed (has code).
            _check({
                condition: address(defifaDeployer).code.length > 0, label: "DefifaDeployer has code", critical: true
            });
            _check({
                condition: defifaDeployer.DEFIFA_PROJECT_ID() == _REV_PROJECT_ID,
                label: "Defifa uses REV(3) as fee project",
                critical: true
            });
            _check({
                condition: defifaDeployer.BASE_PROTOCOL_PROJECT_ID() == _FEE_PROJECT_ID,
                label: "Defifa uses NANA(1) as base protocol project",
                critical: true
            });
            _check({
                condition: address(defifaDeployer.CONTROLLER()) == address(controller),
                label: "Defifa controller wiring",
                critical: true
            });
            _check({
                condition: address(defifaDeployer.REGISTRY()) == addressRegistry,
                label: "Defifa address registry wiring",
                critical: true
            });
            // Defifa uses a DEDICATED hook store, not the shared one.
            if (address(defifaHookStore) != address(0)) {
                _check({
                    condition: address(defifaDeployer.HOOK_STORE()) == address(defifaHookStore),
                    label: "Defifa hook store == dedicated VERIFY_DEFIFA_HOOK_STORE",
                    critical: true
                });
            } else {
                // Fallback: at minimum verify HOOK_STORE has code and is not address(0).
                _check({
                    condition: address(defifaDeployer.HOOK_STORE()).code.length > 0,
                    label: "Defifa HOOK_STORE has code (VERIFY_DEFIFA_HOOK_STORE not set)",
                    critical: true
                });
            }

            address hookCodeOrigin = defifaDeployer.HOOK_CODE_ORIGIN();
            _check({
                condition: hookCodeOrigin.code.length > 0, label: "Defifa hook code origin has code", critical: true
            });
            if (hookCodeOrigin.code.length > 0) {
                _check({
                    condition: address(DefifaHook(hookCodeOrigin).DEFIFA_TOKEN())
                        == address(tokens.tokenOf(_REV_PROJECT_ID)),
                    label: "Defifa hook code origin uses REV token",
                    critical: true
                });
                _check({
                    condition: address(DefifaHook(hookCodeOrigin).BASE_PROTOCOL_TOKEN())
                        == address(tokens.tokenOf(_FEE_PROJECT_ID)),
                    label: "Defifa hook code origin uses NANA token",
                    critical: true
                });
                _check({
                    condition: address(DefifaHook(hookCodeOrigin).DIRECTORY()) == address(directory),
                    label: "Defifa hook code origin DIRECTORY == directory",
                    critical: true
                });
            }

            address tokenUriResolver = address(defifaDeployer.TOKEN_URI_RESOLVER());
            address governor = address(defifaDeployer.GOVERNOR());
            _check({
                condition: tokenUriResolver.code.length > 0, label: "Defifa token URI resolver has code", critical: true
            });
            _check({condition: governor.code.length > 0, label: "Defifa governor has code", critical: true});
            if (governor.code.length > 0) {
                _check({
                    condition: DefifaGovernor(governor).owner() == address(defifaDeployer),
                    label: "Defifa governor owned by deployer",
                    critical: true
                });
                _check({
                    condition: address(DefifaGovernor(governor).CONTROLLER()) == address(controller),
                    label: "Defifa governor controller wiring",
                    critical: true
                });
            }
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
        _check({
            condition: address(ethUsdFeed) != address(0), label: "ETH/USD price feed is configured", critical: true
        });

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
                _check({condition: aboveMin, label: "ETH/USD price > $100", critical: true});
                // Check the upper bound.
                _check({condition: belowMax, label: "ETH/USD price < $1,000,000", critical: true});
            } catch {
                // Feed reverted — mark as critical failure (staleness, sequencer down, etc).
                _check({condition: false, label: "ETH/USD feed.currentUnitPrice() did not revert", critical: true});
            }
        }

        // Check the inverse feed: ETH/NATIVE_TOKEN (should be a matching/identity feed).
        IJBPriceFeed ethNativeFeed =
            prices.priceFeedFor(0, JBCurrencyIds.ETH, uint32(uint160(JBConstants.NATIVE_TOKEN)));
        // Verify the ETH/NATIVE feed address is set.
        _check({
            condition: address(ethNativeFeed) != address(0),
            label: "ETH/NATIVE_TOKEN matching feed is configured",
            critical: true
        });

        // If the matching feed exists, verify it returns ~1e18 (identity price).
        if (address(ethNativeFeed) != address(0)) {
            // Try to read the matching feed price (should be 1:1 = 1e18).
            try ethNativeFeed.currentUnitPrice(18) returns (uint256 matchPrice) {
                // The price should be exactly 1e18 for a matching/identity feed.
                bool isUnity = matchPrice == 1e18;
                // Log the actual price for debugging.
                console.log("  ETH/NATIVE price (18 dec)", matchPrice);
                // Verify the price is exactly 1:1.
                _check({condition: isUnity, label: "ETH/NATIVE matching feed returns 1e18", critical: true});
            } catch {
                // Feed reverted — mark as failure.
                _check({condition: false, label: "ETH/NATIVE matching feed did not revert", critical: true});
            }
        }

        // Check the USD/NATIVE_TOKEN feed (inverse of ETH/USD).
        IJBPriceFeed usdNativeFeed = prices.priceFeedFor(0, JBCurrencyIds.USD, JBCurrencyIds.ETH);
        // The `(USD, ETH)` feed is critical: `JBPrices.pricePerUnitOf` resolves only direct, inverse, and
        // default-project entries — it does NOT compose paths through `(USD, NATIVE)` and `(ETH, NATIVE)` to derive
        // `(USD, ETH)`. Any ETH-base-currency project that prices in USD reverts when this feed is missing, so a
        // missing `(USD, ETH)` is a hard DoS for those projects, not a redundancy gap.
        _check({
            condition: address(usdNativeFeed) != address(0), label: "USD/ETH price feed is configured", critical: true
        });

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
            _check({
                condition: address(usdcUsdFeed) != address(0),
                label: "USDC/USD price feed is configured",
                critical: true
            });

            if (address(usdcUsdFeed) != address(0)) {
                try usdcUsdFeed.currentUnitPrice(18) returns (uint256 usdcPrice) {
                    // USDC should be ~$1 (between $0.90 and $1.10).
                    bool aboveMin = usdcPrice > 0.9e18;
                    bool belowMax = usdcPrice < 1.1e18;
                    console.log("  USDC/USD price (18 dec)", usdcPrice);
                    _check({condition: aboveMin, label: "USDC/USD price > $0.90", critical: true});
                    _check({condition: belowMax, label: "USDC/USD price < $1.10", critical: true});
                } catch {
                    _check({condition: false, label: "USDC/USD feed.currentUnitPrice() did not revert", critical: true});
                }
            }
        }

        // Verify oracle provenance — ensure the protocol is using the expected Chainlink feeds.
        {
            address expectedEthUsdAggregator;
            if (block.chainid == 1) expectedEthUsdAggregator = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            else if (block.chainid == 10) expectedEthUsdAggregator = 0x13e3Ee699D1909E989722E753853AE30b17e08c5;
            else if (block.chainid == 8453) expectedEthUsdAggregator = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
            else if (block.chainid == 42_161) expectedEthUsdAggregator = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

            if (expectedEthUsdAggregator != address(0)) {
                try prices.priceFeedFor({
                    projectId: 0,
                    pricingCurrency: JBCurrencyIds.USD,
                    unitCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }) returns (
                    IJBPriceFeed feed
                ) {
                    // Dereference through the wrapper to compare the inner aggregator.
                    try JBChainlinkV3PriceFeed(address(feed)).FEED() returns (AggregatorV3Interface innerFeed) {
                        _check({
                            condition: address(innerFeed) == expectedEthUsdAggregator,
                            label: "ETH/USD inner aggregator matches expected Chainlink feed",
                            critical: true
                        });
                    } catch {
                        _check({condition: false, label: "ETH/USD feed wrapper does not expose FEED()", critical: true});
                    }

                    // On L2 chains, verify the sequencer-aware variant is used.
                    if (block.chainid == 10 || block.chainid == 8453 || block.chainid == 42_161) {
                        try JBChainlinkV3SequencerPriceFeed(address(feed)).SEQUENCER_FEED() returns (
                            AggregatorV2V3Interface sequencerFeed
                        ) {
                            _check({
                                condition: address(sequencerFeed) != address(0),
                                label: "L2 ETH/USD feed has sequencer feed set",
                                critical: true
                            });
                        } catch {
                            _check({
                                condition: false, label: "L2 ETH/USD feed is sequencer-aware variant", critical: true
                            });
                        }
                    }
                } catch {
                    _skip("ETH/USD oracle provenance (feed lookup reverted)");
                }
            }
        }

        // Log a blank line for readability.
        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 9: Allowlists
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates that sucker deployers are allowed in the registry and feeless addresses are set.
    function _verifyAllowlists() internal {
        console.log("--- Category 9: Allowlists ---");

        // Verify sucker deployers are allowed.
        // Read optional comma-separated list of deployer addresses from env.
        string memory deployersCsv = vm.envOr("VERIFY_SUCKER_DEPLOYERS", string(""));
        if (bytes(deployersCsv).length > 0) {
            // Parse the CSV into addresses and check each.
            string[] memory parts = vm.split(deployersCsv, ",");
            for (uint256 i; i < parts.length; i++) {
                address deployer = vm.parseAddress(parts[i]);
                if (deployer != address(0)) {
                    bool allowed = suckerRegistry.suckerDeployerIsAllowed(deployer);
                    _check({
                        condition: allowed,
                        label: string.concat("Sucker deployer ", vm.toString(deployer), " is allowed"),
                        critical: true
                    });
                }
            }
        } else {
            // On production chains, the sucker deployer allowlist must be provided.
            bool isProductionChain =
                (block.chainid == 1 || block.chainid == 10 || block.chainid == 8453 || block.chainid == 42_161);
            if (isProductionChain) {
                _check({
                    condition: false,
                    label: "Sucker deployer allowlist MUST be set on production (VERIFY_SUCKER_DEPLOYERS)",
                    critical: true
                });
            } else {
                _skip("Sucker deployer allowlist (VERIFY_SUCKER_DEPLOYERS not set)");
            }
        }

        // Verify feeless addresses — router terminal is already checked in Category 5.
        // Add any additional feeless addresses from env.
        string memory feelessCsv = vm.envOr("VERIFY_FEELESS_ADDRESSES", string(""));
        if (bytes(feelessCsv).length > 0) {
            string[] memory parts = vm.split(feelessCsv, ",");
            for (uint256 i; i < parts.length; i++) {
                address feeless = vm.parseAddress(parts[i]);
                if (feeless != address(0)) {
                    bool isFeeless = feelessAddresses.isFeelessFor({addr: feeless, projectId: 0});
                    _check({
                        condition: isFeeless, label: string.concat(vm.toString(feeless), " is feeless"), critical: true
                    });
                }
            }
        } else {
            _skip("Extra feeless addresses (VERIFY_FEELESS_ADDRESSES not set)");
        }

        // Verify expected deployer count matches if provided.
        string memory expectedCountStr = vm.envOr("VERIFY_SUCKER_DEPLOYER_COUNT", string(""));
        if (bytes(expectedCountStr).length > 0) {
            uint256 expectedCount = vm.parseUint(expectedCountStr);
            string memory deployersCsvForCount = vm.envOr("VERIFY_SUCKER_DEPLOYERS", string(""));
            if (bytes(deployersCsvForCount).length > 0) {
                string[] memory countParts = vm.split(deployersCsvForCount, ",");
                _check({
                    condition: countParts.length == expectedCount,
                    label: "Sucker deployer count matches expected",
                    critical: true
                });
            }
        }

        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 10: Routes
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates that the router terminal registry is included in every canonical project's terminal list.
    function _verifyRoutes() internal {
        console.log("--- Category 10: Routes ---");

        // Deploy.s.sol installs the router terminal registry as the project terminal. The registry then resolves to the
        // raw router terminal.
        if (address(routerTerminalRegistry) != address(0)) {
            uint256[4] memory projectIds = [_FEE_PROJECT_ID, _CPN_PROJECT_ID, _REV_PROJECT_ID, _BAN_PROJECT_ID];
            string[4] memory labels = ["NANA(1)", "CPN(2)", "REV(3)", "BAN(4)"];

            for (uint256 i; i < projectIds.length; i++) {
                IJBTerminal[] memory terminals = directory.terminalsOf(projectIds[i]);
                bool found = false;
                for (uint256 j; j < terminals.length; j++) {
                    if (address(terminals[j]) == address(routerTerminalRegistry)) {
                        found = true;
                        break;
                    }
                }
                _check({
                    condition: found,
                    label: string.concat(labels[i], " terminal list includes RouterTerminalRegistry"),
                    critical: true
                });
            }

            // Verify all canonical projects' primary terminal for native token is the JBMultiTerminal.
            for (uint256 i; i < projectIds.length; i++) {
                _check({
                    condition: address(directory.primaryTerminalOf(projectIds[i], JBConstants.NATIVE_TOKEN))
                        == address(terminal),
                    label: string.concat(labels[i], " primary native terminal is JBMultiTerminal"),
                    critical: true
                });
            }
        } else {
            _skip("Router terminal route checks (not deployed on this chain)");
        }

        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 11: Phase 11 Periphery Extensions
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates the late-phase convenience contracts that Deploy.s.sol always deploys.
    function _verifyPeripheryExtensions() internal {
        console.log("--- Category 11: Phase 11 Periphery Extensions ---");

        uint256 expectedRoundDuration = _expectedRoundDuration();

        if (address(projectHandles) == address(0)) {
            _skip("ProjectHandles not deployed (VERIFY_PROJECT_HANDLES not set)");
        } else {
            _check({
                condition: address(projectHandles).code.length > 0, label: "ProjectHandles has code", critical: true
            });
            _check({
                condition: keccak256(bytes(projectHandles.TEXT_KEY())) == keccak256(bytes("juicebox")),
                label: "ProjectHandles text key == juicebox",
                critical: true
            });
            _check({
                condition: projectHandles.trustedForwarder() == projects.trustedForwarder(),
                label: "ProjectHandles trusted forwarder matches core",
                critical: true
            });
        }

        if (address(distributor721) == address(0)) {
            _skip("JB721Distributor not deployed (VERIFY_721_DISTRIBUTOR not set)");
        } else {
            _check({
                condition: address(distributor721).code.length > 0, label: "JB721Distributor has code", critical: true
            });
            _check({
                condition: address(distributor721.DIRECTORY()) == address(directory),
                label: "JB721Distributor directory wiring",
                critical: true
            });
            _verifyDistributorTiming({
                roundDuration: distributor721.roundDuration(),
                vestingRounds: distributor721.vestingRounds(),
                expectedRoundDuration: expectedRoundDuration
            });
        }

        if (address(tokenDistributor) == address(0)) {
            _skip("JBTokenDistributor not deployed (VERIFY_TOKEN_DISTRIBUTOR not set)");
        } else {
            _check({
                condition: address(tokenDistributor).code.length > 0,
                label: "JBTokenDistributor has code",
                critical: true
            });
            _check({
                condition: address(tokenDistributor.DIRECTORY()) == address(directory),
                label: "JBTokenDistributor directory wiring",
                critical: true
            });
            _verifyDistributorTiming({
                roundDuration: tokenDistributor.roundDuration(),
                vestingRounds: tokenDistributor.vestingRounds(),
                expectedRoundDuration: expectedRoundDuration
            });
        }

        if (address(projectPayerDeployer) == address(0)) {
            _skip("ProjectPayerDeployer not deployed (VERIFY_PROJECT_PAYER_DEPLOYER not set)");
        } else {
            _check({
                condition: address(projectPayerDeployer).code.length > 0,
                label: "ProjectPayerDeployer has code",
                critical: true
            });
            _check({
                condition: address(projectPayerDeployer.DIRECTORY()) == address(directory),
                label: "ProjectPayerDeployer directory wiring",
                critical: true
            });

            address implementation = projectPayerDeployer.IMPLEMENTATION();
            _check({
                condition: implementation.code.length > 0, label: "ProjectPayer implementation has code", critical: true
            });

            // Verify the implementation's DIRECTORY and DEPLOYER point to canonical contracts.
            if (implementation.code.length > 0) {
                _check({
                    condition: address(JBProjectPayer(payable(implementation)).DIRECTORY()) == address(directory),
                    label: "ProjectPayer implementation DIRECTORY == directory",
                    critical: true
                });
                _check({
                    condition: JBProjectPayer(payable(implementation)).DEPLOYER() == address(projectPayerDeployer),
                    label: "ProjectPayer implementation DEPLOYER == deployer",
                    critical: true
                });
            }
        }

        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 12: Token Implementation
    // ════════════════════════════════════════════════════════════════════

    function _verifyTokenImplementation() internal {
        console.log("--- Category 12: Token Implementation ---");

        // Verify the TOKEN() implementation on JBTokens is correctly wired.
        IJBToken tokenImpl = tokens.TOKEN();
        _check({condition: address(tokenImpl) != address(0), label: "JBTokens.TOKEN() is non-zero", critical: true});
        _check({
            condition: address(tokenImpl).code.length > 0, label: "JBERC20 implementation has code", critical: true
        });

        // Verify the implementation's PROJECTS() matches canonical projects contract.
        if (address(tokenImpl).code.length > 0) {
            try JBERC20(address(tokenImpl)).PROJECTS() returns (IJBProjects implProjects) {
                _check({
                    condition: address(implProjects) == address(projects),
                    label: "JBERC20 implementation PROJECTS == projects",
                    critical: true
                });
            } catch {
                _check({condition: false, label: "JBERC20 implementation PROJECTS() call failed", critical: true});
            }

            // JBERC20 PERMISSIONS must match canonical permissions.
            (bool permSuccess, bytes memory permData) =
                address(tokenImpl).staticcall(abi.encodeWithSignature("PERMISSIONS()"));
            if (permSuccess && permData.length >= 32) {
                address implPermissions = abi.decode(permData, (address));
                _check({
                    condition: implPermissions == address(permissions),
                    label: "JBERC20 implementation PERMISSIONS == permissions",
                    critical: true
                });
            } else {
                _check({condition: false, label: "JBERC20 implementation PERMISSIONS() call failed", critical: true});
            }
        }

        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 13: Ownership
    // ════════════════════════════════════════════════════════════════════

    function _verifyOwnership() internal {
        console.log("--- Category 13: Ownership ---");

        if (expectedSafe == address(0)) {
            _skip("Ownership checks (VERIFY_SAFE not set)");
            console.log("");
            return;
        }

        _check({condition: projects.owner() == expectedSafe, label: "JBProjects owner == safe", critical: true});
        _check({condition: directory.owner() == expectedSafe, label: "JBDirectory owner == safe", critical: true});
        _check({condition: prices.owner() == expectedSafe, label: "JBPrices owner == safe", critical: true});
        _check({
            condition: feelessAddresses.owner() == expectedSafe,
            label: "JBFeelessAddresses owner == safe",
            critical: true
        });

        if (address(buybackRegistry) != address(0)) {
            _check({
                condition: buybackRegistry.owner() == expectedSafe,
                label: "JBBuybackHookRegistry owner == safe",
                critical: true
            });
        }

        _check({
            condition: suckerRegistry.owner() == expectedSafe, label: "JBSuckerRegistry owner == safe", critical: true
        });

        if (address(routerTerminalRegistry) != address(0)) {
            _check({
                condition: routerTerminalRegistry.owner() == expectedSafe,
                label: "RouterTerminalRegistry owner == safe",
                critical: true
            });
        }
        if (address(revLoans) != address(0)) {
            _check({condition: revLoans.owner() == expectedSafe, label: "REVLoans owner == safe", critical: true});
        }

        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 14: Permissions & Forwarder Wiring
    // ════════════════════════════════════════════════════════════════════

    function _verifyPermissionsAndForwarder() internal {
        console.log("--- Category 14: Permissions & Forwarder Wiring ---");

        // Verify PERMISSIONS() on all permissioned contracts.
        _check({
            condition: address(controller.PERMISSIONS()) == address(permissions),
            label: "Controller.PERMISSIONS == permissions",
            critical: true
        });
        _check({
            condition: address(terminal.PERMISSIONS()) == address(permissions),
            label: "Terminal.PERMISSIONS == permissions",
            critical: true
        });
        _check({
            condition: address(directory.PERMISSIONS()) == address(permissions),
            label: "Directory.PERMISSIONS == permissions",
            critical: true
        });

        // Verify trustedForwarder() on ERC-2771 contracts.
        address controllerForwarder = controller.trustedForwarder();
        address terminalForwarder = terminal.trustedForwarder();
        _check({
            condition: controllerForwarder == terminalForwarder,
            label: "Controller and Terminal share the same trustedForwarder",
            critical: true
        });
        _check({condition: controllerForwarder != address(0), label: "trustedForwarder is non-zero", critical: true});

        // If expected trusted forwarder is provided, verify all ERC-2771 contracts use it.
        if (expectedTrustedForwarder != address(0)) {
            _check({
                condition: controllerForwarder == expectedTrustedForwarder,
                label: "Controller.trustedForwarder == expected",
                critical: true
            });
            _check({
                condition: terminalForwarder == expectedTrustedForwarder,
                label: "Terminal.trustedForwarder == expected",
                critical: true
            });
            _check({
                condition: projects.trustedForwarder() == expectedTrustedForwarder,
                label: "Projects.trustedForwarder == expected",
                critical: true
            });
            // JBPermissions is itself ERC-2771 aware — its forwarder address is baked at construction
            // and never reset. If it diverges from the canonical forwarder, the protocol routes
            // meta-tx through two different relayers and trust assumptions silently break.
            _check({
                condition: permissions.trustedForwarder() == expectedTrustedForwarder,
                label: "Permissions.trustedForwarder == expected",
                critical: true
            });
        }

        // JBOmnichainDeployer's immutable DIRECTORY auth input must match the canonical directory.
        // Without this check, a noncanonical omnichain deployer that routes against a different
        // directory could still pass every other wiring check.
        if (address(omnichainDeployer) != address(0)) {
            _check({
                condition: address(omnichainDeployer.DIRECTORY()) == address(directory),
                label: "OmnichainDeployer.DIRECTORY == directory",
                critical: true
            });
            // PERMISSIONS() pointer must match the canonical registry — a deployer pointed at a
            // forked registry could otherwise mint projects with privileges the canonical operator
            // never granted.
            _check({
                condition: address(omnichainDeployer.PERMISSIONS()) == address(permissions),
                label: "OmnichainDeployer.PERMISSIONS == permissions",
                critical: true
            });
        }
        if (address(suckerRegistry) != address(0)) {
            _check({
                condition: address(suckerRegistry.PERMISSIONS()) == address(permissions),
                label: "SuckerRegistry.PERMISSIONS == permissions",
                critical: true
            });
        }
        // hookDeployer and hookProjectDeployer don't extend JBPermissioned themselves — they
        // deploy hook clones whose PERMISSIONS pointer is verified at clone time, not on the
        // deployer. The clones inherit from JBPermissioned via the hook implementation, which is
        // identity-checked separately (CN).

        // Optional periphery — only check if loaded on this chain.
        if (address(buybackRegistry) != address(0)) {
            _check({
                condition: address(buybackRegistry.PERMISSIONS()) == address(permissions),
                label: "BuybackRegistry.PERMISSIONS == permissions",
                critical: true
            });
        }
        // routerTerminal doesn't extend JBPermissioned directly — it composes the registry.
        // routerTerminalRegistry is the permissioned surface; check it instead when present.
        if (address(routerTerminalRegistry) != address(0)) {
            _check({
                condition: address(routerTerminalRegistry.PERMISSIONS()) == address(permissions),
                label: "RouterTerminalRegistry.PERMISSIONS == permissions",
                critical: true
            });
        }
        if (address(revDeployer) != address(0)) {
            _check({
                condition: address(revDeployer.PERMISSIONS()) == address(permissions),
                label: "REVDeployer.PERMISSIONS == permissions",
                critical: true
            });
        }
        if (address(revLoans) != address(0)) {
            _check({
                condition: address(revLoans.PERMISSIONS()) == address(permissions),
                label: "REVLoans.PERMISSIONS == permissions",
                critical: true
            });
        }

        // P: assert the runtime permission grants the canonical deployment is supposed to create.
        _verifyPermissionGrants();

        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 14b: Permission Grants (P)
    // ════════════════════════════════════════════════════════════════════

    /// Asserts the canonical runtime permission grants. Three classes:
    ///   1. Wildcard (projectId=0) grants made by REVDeployer's constructor:
    ///        - operator=REVLoans,         permId=USE_ALLOWANCE
    ///        - operator=buyback registry, permId=SET_BUYBACK_POOL
    ///      account=REVDeployer in both cases.
    ///   2. Per-revnet split-operator grants made by REVDeployer when each revnet is launched.
    ///      Verified for projects {2 CPN, 3 REV, 4 BAN} when their split operator env var is set.
    ///   3. (Gap) No "extra grants" gate — JBPermissions has no enumeration, so the verifier
    ///      cannot prove the absence of unexpected grants on chain. Operators must rely on
    ///      off-chain event-log reconciliation against `OperatorPermissionsSet` until a future
    ///      protocol change exposes enumeration. The gap is logged below.
    function _verifyPermissionGrants() internal {
        if (address(revDeployer) == address(0) || address(revLoans) == address(0)) {
            console.log("  [SKIP] REV stack not loaded on this chain - permission grants check skipped");
            _skipped += 1;
            return;
        }

        // Wildcard 1: REVLoans USE_ALLOWANCE on any revnet, granted by REVDeployer in its ctor.
        _check({
            condition: permissions.hasPermission({
                operator: address(revLoans),
                account: address(revDeployer),
                projectId: 0,
                permissionId: JBPermissionIds.USE_ALLOWANCE,
                includeRoot: true,
                includeWildcardProjectId: true
            }),
            label: "Permissions: REVLoans wildcard USE_ALLOWANCE granted by REVDeployer",
            critical: true
        });

        // Wildcard 2: buyback registry SET_BUYBACK_POOL on any revnet, granted by REVDeployer.
        if (address(buybackRegistry) != address(0)) {
            _check({
                condition: permissions.hasPermission({
                    operator: address(buybackRegistry),
                    account: address(revDeployer),
                    projectId: 0,
                    permissionId: JBPermissionIds.SET_BUYBACK_POOL,
                    includeRoot: true,
                    includeWildcardProjectId: true
                }),
                label: "Permissions: BuybackRegistry wildcard SET_BUYBACK_POOL granted by REVDeployer",
                critical: true
            });
        }

        // Per-revnet split-operator grants. The split operator is configured at revnet launch and
        // exposed via VERIFY_SPLIT_OPERATOR_{2,3,4} env vars. When set, the verifier asserts the
        // operator has the 9 canonical split-operator permissions on its revnet.
        _verifySplitOperatorGrantsFor({
            envVar: "VERIFY_SPLIT_OPERATOR_2", projectId: _CPN_PROJECT_ID, label: "Project 2 (CPN)"
        });
        _verifySplitOperatorGrantsFor({
            envVar: "VERIFY_SPLIT_OPERATOR_3", projectId: _REV_PROJECT_ID, label: "Project 3 (REV)"
        });
        _verifySplitOperatorGrantsFor({
            envVar: "VERIFY_SPLIT_OPERATOR_4", projectId: _BAN_PROJECT_ID, label: "Project 4 (BAN)"
        });

        // Known gap (logged, not failed): exhaustive "no extra grants" verification requires either
        // an enumerable JBPermissions or off-chain event-log reconciliation against
        // `OperatorPermissionsSet`. The on-chain verifier proves positive grants only.
        console.log("  [INFO] No on-chain enumeration - see DEPLOY.md for off-chain grant reconciliation");
    }

    /// Asserts the 9 canonical split-operator permissions on `projectId` for the operator named by
    /// `envVar`. Skips silently when the env var is not set (testnets, partial chains).
    function _verifySplitOperatorGrantsFor(string memory envVar, uint256 projectId, string memory label) internal {
        address operator = vm.envOr({name: envVar, defaultValue: address(0)});
        if (operator == address(0)) {
            console.log(string.concat("  [SKIP] ", envVar, " unset - split-operator grants for ", label, " skipped"));
            _skipped += 1;
            return;
        }
        uint8[9] memory expectedPermissions = [
            JBPermissionIds.SET_SPLIT_GROUPS,
            JBPermissionIds.SET_BUYBACK_POOL,
            JBPermissionIds.SET_BUYBACK_TWAP,
            JBPermissionIds.SET_PROJECT_URI,
            JBPermissionIds.SUCKER_SAFETY,
            JBPermissionIds.SET_BUYBACK_HOOK,
            JBPermissionIds.SET_ROUTER_TERMINAL,
            JBPermissionIds.SET_TOKEN_METADATA,
            JBPermissionIds.SIGN_FOR_ERC20
        ];
        for (uint256 i; i < expectedPermissions.length; i++) {
            _check({
                condition: permissions.hasPermission({
                    operator: operator,
                    account: address(revDeployer),
                    projectId: uint64(projectId),
                    permissionId: expectedPermissions[i],
                    includeRoot: true,
                    includeWildcardProjectId: true
                }),
                label: string.concat(
                    "Permissions: ",
                    label,
                    " split-operator has permission ",
                    vm.toString(uint256(expectedPermissions[i]))
                ),
                critical: true
            });
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 15: Croptop Immutables
    // ════════════════════════════════════════════════════════════════════

    function _verifyCroptopImmutables() internal {
        console.log("--- Category 15: Croptop Immutables ---");

        // CTPublisher immutables.
        _check({
            condition: address(ctPublisher.DIRECTORY()) == address(directory),
            label: "CTPublisher.DIRECTORY == directory",
            critical: true
        });
        _check({
            condition: ctPublisher.FEE_PROJECT_ID() == _CPN_PROJECT_ID,
            label: "CTPublisher.FEE_PROJECT_ID == 2",
            critical: true
        });

        // CTDeployer immutables.
        _check({
            condition: address(ctDeployer.DEPLOYER()) == address(hookDeployer),
            label: "CTDeployer.DEPLOYER == hookDeployer",
            critical: true
        });
        _check({
            condition: address(ctDeployer.PROJECTS()) == address(projects),
            label: "CTDeployer.PROJECTS == projects",
            critical: true
        });
        _check({
            condition: address(ctDeployer.PUBLISHER()) == address(ctPublisher),
            label: "CTDeployer.PUBLISHER == ctPublisher",
            critical: true
        });
        _check({
            condition: address(ctDeployer.SUCKER_REGISTRY()) == address(suckerRegistry),
            label: "CTDeployer.SUCKER_REGISTRY == suckerRegistry",
            critical: true
        });

        // CTProjectOwner immutables.
        _check({
            condition: address(ctProjectOwner.PERMISSIONS()) == address(permissions),
            label: "CTProjectOwner.PERMISSIONS == permissions",
            critical: true
        });
        _check({
            condition: address(ctProjectOwner.PROJECTS()) == address(projects),
            label: "CTProjectOwner.PROJECTS == projects",
            critical: true
        });
        _check({
            condition: address(ctProjectOwner.PUBLISHER()) == address(ctPublisher),
            label: "CTProjectOwner.PUBLISHER == ctPublisher",
            critical: true
        });

        // Note: CTPublisher fee calculation assumes ETH/18-decimal tier prices.
        // Non-ETH-priced hooks may produce incorrect fee amounts.
        // This is a known limitation — not verifiable on-chain.

        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 16: Hook Deployer Immutables
    // ════════════════════════════════════════════════════════════════════

    function _verifyHookDeployerImmutables() internal {
        console.log("--- Category 16: Hook Deployer Immutables ---");

        // JB721TiersHookDeployer immutables.
        _check({
            condition: address(hookDeployer.STORE()) == address(hookStore),
            label: "HookDeployer.STORE == hookStore",
            critical: true
        });
        _check({
            condition: address(hookDeployer.ADDRESS_REGISTRY()) == addressRegistry,
            label: "HookDeployer.ADDRESS_REGISTRY == addressRegistry",
            critical: true
        });

        // Verify the base hook (implementation) immutables.
        address baseHook = address(hookDeployer.HOOK());
        _check({condition: baseHook != address(0), label: "HookDeployer.HOOK is non-zero", critical: true});

        if (baseHook != address(0) && baseHook.code.length > 0) {
            IJB721TiersHook hook = IJB721TiersHook(baseHook);
            _check({
                condition: address(hook.PRICES()) == address(prices),
                label: "Base hook PRICES == prices",
                critical: true
            });
            _check({
                condition: address(hook.RULESETS()) == address(rulesets),
                label: "Base hook RULESETS == rulesets",
                critical: true
            });
            _check({
                condition: address(hook.STORE()) == address(hookStore),
                label: "Base hook STORE == hookStore",
                critical: true
            });
            _check({
                condition: address(hook.SPLITS()) == address(splits),
                label: "Base hook SPLITS == splits",
                critical: true
            });
            _check({
                condition: address(JB721TiersHook(baseHook).DIRECTORY()) == address(directory),
                label: "Base hook DIRECTORY == directory",
                critical: true
            });
        }

        // Note: CHECKPOINTS_DEPLOYER is internal on JB721TiersHook and not externally accessible.
        // The checkpoint deployer wiring is verified indirectly through STORE checks above.

        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 17: REVOwner & REVLoans Immutables
    // ════════════════════════════════════════════════════════════════════

    function _verifyRevImmutables() internal {
        console.log("--- Category 17: REVOwner & REVLoans Immutables ---");

        if (address(revOwner) == address(0)) {
            _skip("REVOwner immutables (not deployed)");
        } else {
            _check({
                condition: address(revOwner.BUYBACK_HOOK()) == address(buybackRegistry),
                label: "REVOwner.BUYBACK_HOOK == buybackRegistry",
                critical: true
            });
            _check({
                condition: address(revOwner.DIRECTORY()) == address(directory),
                label: "REVOwner.DIRECTORY == directory",
                critical: true
            });
            _check({
                condition: revOwner.FEE_REVNET_ID() == _REV_PROJECT_ID,
                label: "REVOwner.FEE_REVNET_ID == 3",
                critical: true
            });
            _check({
                condition: address(revOwner.LOANS()) == address(revLoans),
                label: "REVOwner.LOANS == revLoans",
                critical: true
            });
            _check({
                condition: address(revOwner.SUCKER_REGISTRY()) == address(suckerRegistry),
                label: "REVOwner.SUCKER_REGISTRY == suckerRegistry",
                critical: true
            });
        }

        if (address(revLoans) == address(0)) {
            _skip("REVLoans immutables (not deployed)");
        } else {
            _check({
                condition: address(revLoans.CONTROLLER()) == address(controller),
                label: "REVLoans.CONTROLLER == controller",
                critical: true
            });
            _check({
                condition: address(revLoans.DIRECTORY()) == address(directory),
                label: "REVLoans.DIRECTORY == directory",
                critical: true
            });
            _check({
                condition: address(revLoans.PRICES()) == address(prices),
                label: "REVLoans.PRICES == prices",
                critical: true
            });
            _check({condition: revLoans.REV_ID() == _REV_PROJECT_ID, label: "REVLoans.REV_ID == 3", critical: true});
            _check({
                condition: address(revLoans.SUCKER_REGISTRY()) == address(suckerRegistry),
                label: "REVLoans.SUCKER_REGISTRY == suckerRegistry",
                critical: true
            });
            _check({
                condition: address(revLoans.PERMIT2()) != address(0),
                label: "REVLoans.PERMIT2 is non-zero",
                critical: true
            });
        }

        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 18: Canonical Project Economics
    // ════════════════════════════════════════════════════════════════════

    function _verifyCanonicalProjectEconomics() internal {
        console.log("--- Category 18: Canonical Project Economics ---");

        if (address(revDeployer) == address(0)) {
            _skip("Canonical project economics (REVDeployer not configured)");
            console.log("");
            return;
        }

        // Verify all 4 projects have a config hash recorded.
        uint256[4] memory pids = [_FEE_PROJECT_ID, _CPN_PROJECT_ID, _REV_PROJECT_ID, _BAN_PROJECT_ID];
        string[4] memory names = ["NANA(1)", "CPN(2)", "REV(3)", "BAN(4)"];
        for (uint256 i; i < 4; i++) {
            bytes32 configHash = revDeployer.hashedEncodedConfigurationOf(pids[i]);
            _check({
                condition: configHash != bytes32(0),
                label: string.concat(names[i], " has non-zero config hash"),
                critical: true
            });
        }

        // Verify env-provided expected config hashes match deployed config hashes (if provided).
        string memory expectedHashesCsv = vm.envOr("VERIFY_CONFIG_HASHES", string(""));
        if (bytes(expectedHashesCsv).length > 0) {
            string[] memory hashes = vm.split(expectedHashesCsv, ",");
            for (uint256 i; i < hashes.length && i < 4; i++) {
                bytes32 expected = vm.parseBytes32(hashes[i]);
                if (expected != bytes32(0)) {
                    bytes32 actual = revDeployer.hashedEncodedConfigurationOf(pids[i]);
                    _check({
                        condition: actual == expected,
                        label: string.concat(names[i], " config hash matches expected"),
                        critical: true
                    });
                }
            }
        }

        // Verify Banny hook resolver and contractURI.
        if (address(revOwner) != address(0)) {
            IJB721TiersHook bannyHook = revOwner.tiered721HookOf(_BAN_PROJECT_ID);
            if (address(bannyHook) != address(0)) {
                address resolver = address(hookStore.tokenUriResolverOf(address(bannyHook)));
                _check({condition: resolver != address(0), label: "Banny hook has token URI resolver", critical: true});
                if (resolver != address(0)) {
                    _check({condition: resolver.code.length > 0, label: "Banny resolver has code", critical: true});
                }

                try bannyHook.contractURI() returns (string memory uri) {
                    _check({
                        condition: bytes(uri).length > 0, label: "Banny hook contractURI is non-empty", critical: true
                    });
                } catch {
                    _skip("Banny hook contractURI() call failed");
                }
            }
        }

        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 19: Cross-Chain Sucker Manifest
    // ════════════════════════════════════════════════════════════════════

    function _verifySuckerManifest() internal {
        console.log("--- Category 19: Cross-Chain Sucker Manifest ---");

        // Load optional per-project sucker pair counts from env.
        // Format: VERIFY_SUCKER_PAIRS_1=<count>,VERIFY_SUCKER_PAIRS_2=<count>, etc.
        uint256[4] memory pids = [_FEE_PROJECT_ID, _CPN_PROJECT_ID, _REV_PROJECT_ID, _BAN_PROJECT_ID];
        string[4] memory names = ["NANA(1)", "CPN(2)", "REV(3)", "BAN(4)"];
        bool anySuckerChecks = false;

        for (uint256 i; i < 4; i++) {
            string memory envKey = string.concat("VERIFY_SUCKER_PAIRS_", vm.toString(pids[i]));
            string memory expectedCountStr = vm.envOr(envKey, string(""));
            if (bytes(expectedCountStr).length == 0) continue;
            anySuckerChecks = true;

            uint256 expectedCount = vm.parseUint(expectedCountStr);
            JBSuckersPair[] memory pairs = suckerRegistry.suckerPairsOf(pids[i]);
            _check({
                condition: pairs.length == expectedCount,
                label: string.concat(names[i], " sucker pair count matches expected"),
                critical: true
            });

            // Verify each pair has a non-zero remote.
            for (uint256 j; j < pairs.length; j++) {
                _check({
                    condition: pairs[j].remote != bytes32(0),
                    label: string.concat(names[i], " sucker pair ", vm.toString(j), " has non-zero remote"),
                    critical: true
                });
            }
        }

        if (!anySuckerChecks) {
            _skip("Sucker manifest checks (VERIFY_SUCKER_PAIRS_* not set)");
        }

        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 20: External Address Provenance
    // ════════════════════════════════════════════════════════════════════

    function _verifyExternalAddresses() internal {
        console.log("--- Category 20: External Address Provenance ---");

        // Terminal Permit2 wiring.
        _check({
            condition: address(terminal.PERMIT2()) != address(0), label: "Terminal.PERMIT2 is non-zero", critical: true
        });

        // Router terminal wrapped-native-token and Permit2 wiring.
        if (address(routerTerminal) != address(0)) {
            _check({
                condition: address(routerTerminal.WRAPPED_NATIVE_TOKEN()) != address(0),
                label: "RouterTerminal.WRAPPED_NATIVE_TOKEN is non-zero",
                critical: true
            });
            _check({
                condition: address(routerTerminal.PERMIT2()) != address(0),
                label: "RouterTerminal.PERMIT2 is non-zero",
                critical: true
            });
        }

        // REVLoans PERMIT2.
        if (address(revLoans) != address(0)) {
            _check({
                condition: address(revLoans.PERMIT2()) != address(0),
                label: "REVLoans.PERMIT2 is non-zero",
                critical: true
            });
        }

        // OmnichainDeployer DIRECTORY.
        _check({
            condition: address(omnichainDeployer.DIRECTORY()) == address(directory),
            label: "OmnichainDeployer.DIRECTORY == directory",
            critical: true
        });

        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Internal Helpers
    // ════════════════════════════════════════════════════════════════════

    function _verifyDistributorTiming(
        uint256 roundDuration,
        uint256 vestingRounds,
        uint256 expectedRoundDuration
    )
        internal
    {
        if (expectedRoundDuration != 0) {
            _check({
                condition: roundDuration == expectedRoundDuration, label: "Distributor round duration", critical: true
            });
        }
        _check({condition: vestingRounds == _VESTING_ROUNDS, label: "Distributor vesting rounds", critical: true});
    }

    function _expectedRoundDuration() internal pure returns (uint256) {
        return 604_800; // 7 days
    }

    /// @dev Checks whether a project exists by calling ownerOf on the ERC-721.
    /// @param projectId The project ID to check.
    /// @param label Human-readable label for the check.
    function _checkProjectHasOwner(uint256 projectId, string memory label) internal {
        // Try calling ownerOf; if the project does not exist, this reverts.
        try projects.ownerOf(projectId) returns (address owner) {
            // Verify the owner is not the zero address (burned token).
            _check({condition: owner != address(0), label: label, critical: true});
        } catch {
            // ownerOf reverted, meaning the project does not exist.
            _check({condition: false, label: label, critical: true});
        }
    }

    function _metadataSymbolIs(address token, string memory expected) internal view returns (bool) {
        try IERC20Metadata(token).symbol() returns (string memory actual) {
            return keccak256(bytes(actual)) == keccak256(bytes(expected));
        } catch {
            return false;
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
