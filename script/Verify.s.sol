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
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
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

    /// Foundry's parseJson requires struct fields in alphabetical order to match JSON keys.
    /// `{length, start}` for `{start, length}` JSON.
    struct ImmutableRange {
        uint256 length;
        uint256 start;
    }

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
    // The 721 checkpoints deployer that owns the checkpoints clone implementation.
    JB721CheckpointsDeployer public checkpointsDeployer;
    /// BA residual: tracked separately so the verifier can assert the LP split hook deployer
    /// carries the canonical V4 PositionManager. Loaded from `VERIFY_LP_SPLIT_HOOK_DEPLOYER`;
    /// `address(0)` when the chain has no canonical PositionManager.
    address public lpSplitHookDeployer;

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
        // Read the 721 checkpoints deployer address from env (optional until manifests are updated).
        checkpointsDeployer =
            JB721CheckpointsDeployer(vm.envOr({name: "VERIFY_721_CHECKPOINTS_DEPLOYER", defaultValue: address(0)}));

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
        checkpointsDeployer =
            JB721CheckpointsDeployer(vm.envOr({name: "VERIFY_CHECKPOINTS_DEPLOYER", defaultValue: address(0)}));
        lpSplitHookDeployer = vm.envOr({name: "VERIFY_LP_SPLIT_HOOK_DEPLOYER", defaultValue: address(0)});

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

            // BS: CPN (Croptop) also gets a 721 hook recorded at project 2. The pre-fix verifier
            // ignored it entirely; an attacker-deployed CPN hook (wrong PROJECT_ID, wrong store,
            // wrong symbol) survived. Same identity shape as Banny.
            IJB721TiersHook cpnHook = revOwner.tiered721HookOf(_CPN_PROJECT_ID);
            _check({
                condition: address(cpnHook) != address(0), label: "CPN(2) has Croptop 721 hook recorded", critical: true
            });
            if (address(cpnHook) != address(0)) {
                _check({
                    condition: cpnHook.PROJECT_ID() == _CPN_PROJECT_ID,
                    label: "CPN hook PROJECT_ID == 2",
                    critical: true
                });
                _check({
                    condition: address(cpnHook.STORE()) == address(hookStore),
                    label: "CPN hook uses canonical 721 store",
                    critical: true
                });
                _check({
                    condition: _metadataSymbolIs({token: address(cpnHook), expected: "CPN"}),
                    label: "CPN hook symbol == CPN",
                    critical: true
                });

                // BS: CPN posting criteria for categories 0-4 must be configured. The on-chain
                // assertion proves the CTPublisher has registered criteria for the canonical
                // category set rather than leaving them unset (which would let any poster onto
                // an unconfigured category with default zero-permission semantics).
                //
                // BS residual: when env vars are provided, also assert exact value equality on
                // every criterion. Env shape (per category 0-4):
                //   VERIFY_CPN_MIN_PRICE_<cat>          uint
                //   VERIFY_CPN_MIN_SUPPLY_<cat>         uint
                //   VERIFY_CPN_MAX_SUPPLY_<cat>         uint
                //   VERIFY_CPN_MAX_SPLIT_PERCENT_<cat>  uint
                //   VERIFY_CPN_ALLOWED_ADDRESSES_<cat>  "0x..,0x.." CSV (empty = no allowlist)
                if (address(ctPublisher) != address(0)) {
                    for (uint256 cat; cat <= 4; cat++) {
                        (
                            uint256 minPrice,
                            uint256 minSupply,
                            uint256 maxSupply,
                            uint256 maxSplitPct,
                            address[] memory allowed
                        ) = ctPublisher.allowanceFor(address(cpnHook), cat);
                        _check({
                            condition: minPrice > 0,
                            label: string.concat(
                                "CPN posting criteria category ", vm.toString(cat), " configured (minPrice > 0)"
                            ),
                            critical: true
                        });
                        _verifyCpnCriterionExact({
                            cat: cat,
                            minPrice: minPrice,
                            minSupply: minSupply,
                            maxSupply: maxSupply,
                            maxSplitPct: maxSplitPct,
                            allowed: allowed
                        });
                    }
                }
            }
        } else {
            _skip("Banny / CPN 721 hook identity checks (REVOwner not configured)");
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
            // CH fix: require the controller pointer to equal the canonical controller, not just
            // be non-zero. A noncanonical controller would otherwise pass and silently authorize
            // ruleset queues / token mints / payout calls that the canonical operator never
            // approved.
            _check({
                condition: address(projectController) == address(controller),
                label: string.concat(labels[i], " controller == canonical JBController"),
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

            // CQ fix: assert the live accounting context for the native token matches the
            // expected shape (token sentinel + 18 decimals + native currency id). A wrong
            // accounting context — e.g. decimals=6 because the deployer mis-configured a USD
            // currency — silently mis-scales every cash-out and pay on that project.
            try terminal.accountingContextForTokenOf(projectIds[i], JBConstants.NATIVE_TOKEN) returns (
                JBAccountingContext memory ctx
            ) {
                _check({
                    condition: ctx.token == JBConstants.NATIVE_TOKEN,
                    label: string.concat(labels[i], " native accounting context token == NATIVE_TOKEN"),
                    critical: true
                });
                _check({
                    condition: ctx.decimals == 18,
                    label: string.concat(labels[i], " native accounting context decimals == 18"),
                    critical: true
                });
                // The native currency id is `uint32(uint160(NATIVE_TOKEN))` per JBAccountingContext.
                _check({
                    condition: ctx.currency == uint32(uint160(JBConstants.NATIVE_TOKEN)),
                    label: string.concat(labels[i], " native accounting context currency == NATIVE_TOKEN id"),
                    critical: true
                });
            } catch {
                _check({
                    condition: false,
                    label: string.concat(labels[i], " terminal exposes accountingContextForTokenOf"),
                    critical: true
                });
            }

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

                // Also verify the router terminal is NOT globally feeless. We dropped the global feeless
                // grant: the router was forwarding fees from arbitrary projects on its own balance, which
                // is too broad. Per-project feeless wiring (if needed) is the explicit path going forward.
                _check({
                    condition: !feelessAddresses.isFeelessFor({addr: address(routerTerminal), projectId: 0}),
                    label: "RouterTerminal is NOT globally feeless",
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

        // BG: oracle exactness. The audit calls for asserting not just the aggregator address but
        // also THRESHOLD(), SEQUENCER_FEED() (per L2), and GRACE_PERIOD_TIME() (per L2) against
        // the canonical Deploy.s.sol values. Without these the verifier accepts any sequencer-aware
        // wrapper whose getters happen to return plausible values.
        _verifyEthUsdOracleExactness();
        _verifyUsdcUsdOracleExactness({usdc: usdc});

        // Log a blank line for readability.
        console.log("");
    }

    /// BG: assert the deployed ETH/USD feed wraps the canonical Chainlink aggregator with the
    /// expected THRESHOLD, and on L2s the canonical SEQUENCER_FEED + GRACE_PERIOD_TIME.
    function _verifyEthUsdOracleExactness() internal {
        (address expectedAggregator, uint256 expectedThreshold, address expectedSequencerFeed, uint256 expectedGrace) =
            _expectedEthUsdOracle();
        if (expectedAggregator == address(0)) {
            _skip("ETH/USD oracle exactness (unsupported chain)");
            return;
        }
        try prices.priceFeedFor({
            projectId: 0, pricingCurrency: JBCurrencyIds.USD, unitCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        }) returns (
            IJBPriceFeed feed
        ) {
            try JBChainlinkV3PriceFeed(address(feed)).FEED() returns (AggregatorV3Interface innerFeed) {
                _check({
                    condition: address(innerFeed) == expectedAggregator,
                    label: "ETH/USD: FEED matches expected Chainlink aggregator",
                    critical: true
                });
            } catch {
                _check({condition: false, label: "ETH/USD feed wrapper does not expose FEED()", critical: true});
            }
            try JBChainlinkV3PriceFeed(address(feed)).THRESHOLD() returns (uint256 threshold) {
                _check({
                    condition: threshold == expectedThreshold,
                    label: "ETH/USD: THRESHOLD matches deploy-time staleness window",
                    critical: true
                });
            } catch {
                _check({condition: false, label: "ETH/USD feed wrapper does not expose THRESHOLD()", critical: true});
            }
            if (expectedSequencerFeed != address(0)) {
                try JBChainlinkV3SequencerPriceFeed(address(feed)).SEQUENCER_FEED() returns (
                    AggregatorV2V3Interface sequencerFeed
                ) {
                    _check({
                        condition: address(sequencerFeed) == expectedSequencerFeed,
                        label: "ETH/USD: SEQUENCER_FEED matches expected L2 sequencer feed",
                        critical: true
                    });
                } catch {
                    _check({
                        condition: false,
                        label: "ETH/USD feed is not the sequencer-aware variant on this L2",
                        critical: true
                    });
                }
                try JBChainlinkV3SequencerPriceFeed(address(feed)).GRACE_PERIOD_TIME() returns (uint256 grace) {
                    _check({
                        condition: grace == expectedGrace,
                        label: "ETH/USD: GRACE_PERIOD_TIME matches deploy-time L2 grace",
                        critical: true
                    });
                } catch {
                    _check({
                        condition: false,
                        label: "ETH/USD feed does not expose GRACE_PERIOD_TIME on this L2",
                        critical: true
                    });
                }
            }
        } catch {
            _skip("ETH/USD oracle exactness (feed lookup reverted)");
        }
    }

    /// BG: same shape as `_verifyEthUsdOracleExactness` for the USDC/USD feed. Per-chain USDC
    /// address is already in scope from the parent function — pass it through so we don't
    /// re-derive it.
    function _verifyUsdcUsdOracleExactness(address usdc) internal {
        if (usdc == address(0)) return;
        (address expectedAggregator, uint256 expectedThreshold, address expectedSequencerFeed, uint256 expectedGrace) =
            _expectedUsdcUsdOracle();
        if (expectedAggregator == address(0)) {
            _skip("USDC/USD oracle exactness (unsupported chain)");
            return;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        try prices.priceFeedFor({
            projectId: 0, pricingCurrency: JBCurrencyIds.USD, unitCurrency: uint32(uint160(usdc))
        }) returns (
            IJBPriceFeed feed
        ) {
            try JBChainlinkV3PriceFeed(address(feed)).FEED() returns (AggregatorV3Interface innerFeed) {
                _check({
                    condition: address(innerFeed) == expectedAggregator,
                    label: "USDC/USD: FEED matches expected Chainlink aggregator",
                    critical: true
                });
            } catch {
                _check({condition: false, label: "USDC/USD feed wrapper does not expose FEED()", critical: true});
            }
            try JBChainlinkV3PriceFeed(address(feed)).THRESHOLD() returns (uint256 threshold) {
                _check({
                    condition: threshold == expectedThreshold,
                    label: "USDC/USD: THRESHOLD matches deploy-time staleness window",
                    critical: true
                });
            } catch {
                _check({condition: false, label: "USDC/USD feed wrapper does not expose THRESHOLD()", critical: true});
            }
            if (expectedSequencerFeed != address(0)) {
                try JBChainlinkV3SequencerPriceFeed(address(feed)).SEQUENCER_FEED() returns (
                    AggregatorV2V3Interface sequencerFeed
                ) {
                    _check({
                        condition: address(sequencerFeed) == expectedSequencerFeed,
                        label: "USDC/USD: SEQUENCER_FEED matches expected L2 sequencer feed",
                        critical: true
                    });
                } catch {
                    _check({
                        condition: false,
                        label: "USDC/USD feed is not the sequencer-aware variant on this L2",
                        critical: true
                    });
                }
                try JBChainlinkV3SequencerPriceFeed(address(feed)).GRACE_PERIOD_TIME() returns (uint256 grace) {
                    _check({
                        condition: grace == expectedGrace,
                        label: "USDC/USD: GRACE_PERIOD_TIME matches deploy-time L2 grace",
                        critical: true
                    });
                } catch {
                    _check({
                        condition: false,
                        label: "USDC/USD feed does not expose GRACE_PERIOD_TIME on this L2",
                        critical: true
                    });
                }
            }
        } catch {
            _skip("USDC/USD oracle exactness (feed lookup reverted)");
        }
    }

    /// Returns the canonical ETH/USD oracle params for this chain, mirroring Deploy.s.sol's
    /// _deployEthUsdFeed. Returns (0, 0, 0, 0) on unsupported chains so the caller can skip.
    /// Sequencer feed + grace period are zero on L1s; non-zero implies L2 sequencer-aware variant.
    function _expectedEthUsdOracle()
        internal
        view
        returns (address aggregator, uint256 threshold, address sequencerFeed, uint256 gracePeriod)
    {
        if (block.chainid == 1) {
            return (0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, 3600, address(0), 0);
        } else if (block.chainid == 11_155_111) {
            return (0x694AA1769357215DE4FAC081bf1f309aDC325306, 3600, address(0), 0);
        } else if (block.chainid == 10) {
            return (0x13e3Ee699D1909E989722E753853AE30b17e08c5, 3600, 0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389, 3600);
        } else if (block.chainid == 11_155_420) {
            return (0x61Ec26aA57019C486B10502285c5A3D4A4750AD7, 3600, address(0), 0);
        } else if (block.chainid == 8453) {
            return (0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70, 3600, 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433, 3600);
        } else if (block.chainid == 84_532) {
            return (0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1, 3600, address(0), 0);
        } else if (block.chainid == 42_161) {
            return (0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612, 3600, 0xFdB631F5EE196F0ed6FAa767959853A9F217697D, 3600);
        }
        return (address(0), 0, address(0), 0);
    }

    /// Returns the canonical USDC/USD oracle params for this chain. Same shape as
    /// `_expectedEthUsdOracle`. Mirrors Deploy.s.sol's _deployUsdcFeed.
    function _expectedUsdcUsdOracle()
        internal
        view
        returns (address aggregator, uint256 threshold, address sequencerFeed, uint256 gracePeriod)
    {
        if (block.chainid == 1) {
            return (0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, 86_400, address(0), 0);
        } else if (block.chainid == 11_155_111) {
            return (0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E, 86_400, address(0), 0);
        } else if (block.chainid == 10) {
            return
                (0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3, 86_400, 0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389, 3600);
        } else if (block.chainid == 11_155_420) {
            return (0x6e44e50E3cc14DD16e01C590DC1d7020cb36eD4C, 86_400, address(0), 0);
        } else if (block.chainid == 8453) {
            return
                (0x7e860098F58bBFC8648a4311b374B1D669a2bc6B, 86_400, 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433, 3600);
        } else if (block.chainid == 84_532) {
            return (0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165, 86_400, address(0), 0);
        } else if (block.chainid == 42_161) {
            return
                (0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3, 86_400, 0xFdB631F5EE196F0ed6FAa767959853A9F217697D, 3600);
        } else if (block.chainid == 421_614) {
            return (0x0153002d20B96532C639313c2d54c3dA09109309, 86_400, address(0), 0);
        }
        return (address(0), 0, address(0), 0);
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
                    // BK: each listed deployer must actually be allowed in the registry.
                    bool allowed = suckerRegistry.suckerDeployerIsAllowed(deployer);
                    _check({
                        condition: allowed,
                        label: string.concat("Sucker deployer ", vm.toString(deployer), " is allowed"),
                        critical: true
                    });
                    // CP: each listed deployer must be a real deployer with canonical wiring.
                    // Without these checks, a non-executable EOA or a deployer admined by an
                    // attacker-controlled Safe could survive in the allowlist undetected.
                    _verifySuckerDeployerCanonicalWiring(deployer);
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

        // BK known gap: JBSuckerRegistry has no enumeration of its allowed-deployer set, so the
        // on-chain verifier cannot prove the absence of unexpected allowed deployers. Operators
        // must reconcile against the `SuckerDeployerSetAllowed` event log off-chain. The
        // VERIFY_SUCKER_DEPLOYER_COUNT check above provides a sanity gate; the event-log
        // reconciliation is documented in DEPLOY.md.
        console.log("  [INFO] BK: no on-chain enumeration of sucker-deployer allowlist - reconcile off-chain");

        console.log("");
    }

    /// CP: for each env-listed sucker deployer, assert it is a real, canonically-wired deployer.
    /// Checks:
    ///   - has code (not an EOA / non-executable address)
    ///   - LAYER_SPECIFIC_CONFIGURATOR == expectedSafe (admin gate)
    ///   - singleton() returns an address with code
    ///   - DIRECTORY / TOKENS / PERMISSIONS match the canonical core singletons
    /// Without these, an empty EOA or an attacker-admined deployer can sit in the allowlist
    /// looking like a legitimate route while routing through unverified wiring.
    function _verifySuckerDeployerCanonicalWiring(address deployer) internal {
        _check({
            condition: deployer.code.length > 0,
            label: string.concat("Sucker deployer ", vm.toString(deployer), " has code"),
            critical: true
        });
        if (deployer.code.length == 0) return;

        // LAYER_SPECIFIC_CONFIGURATOR is the admin Safe — must equal the canonical expected Safe
        // when one is configured (production chains). Non-production runs without expectedSafe
        // just verify it's non-zero.
        (bool okConfig, bytes memory configData) =
            deployer.staticcall(abi.encodeWithSignature("LAYER_SPECIFIC_CONFIGURATOR()"));
        if (okConfig && configData.length >= 32) {
            address configurator = abi.decode(configData, (address));
            if (expectedSafe != address(0)) {
                _check({
                    condition: configurator == expectedSafe,
                    label: string.concat(
                        "Sucker deployer ", vm.toString(deployer), ".LAYER_SPECIFIC_CONFIGURATOR == safe"
                    ),
                    critical: true
                });
            } else {
                _check({
                    condition: configurator != address(0),
                    label: string.concat(
                        "Sucker deployer ", vm.toString(deployer), ".LAYER_SPECIFIC_CONFIGURATOR is non-zero"
                    ),
                    critical: true
                });
            }
        } else {
            _check({
                condition: false,
                label: string.concat(
                    "Sucker deployer ", vm.toString(deployer), " exposes LAYER_SPECIFIC_CONFIGURATOR()"
                ),
                critical: true
            });
        }

        // singleton() must be a real implementation contract — not an EOA, not address(0). The
        // exact-identity check is part of BR's emission work (the singleton appears in the address
        // dump and gets verified separately via artifact identity in CK/CM).
        (bool okSing, bytes memory singData) = deployer.staticcall(abi.encodeWithSignature("singleton()"));
        if (okSing && singData.length >= 32) {
            address singleton = abi.decode(singData, (address));
            _check({
                condition: singleton != address(0) && singleton.code.length > 0,
                label: string.concat("Sucker deployer ", vm.toString(deployer), ".singleton has code"),
                critical: true
            });
        } else {
            _check({
                condition: false,
                label: string.concat("Sucker deployer ", vm.toString(deployer), " exposes singleton()"),
                critical: true
            });
        }

        // DIRECTORY / TOKENS / PERMISSIONS must match the canonical core singletons.
        (bool okDir, bytes memory dirData) = deployer.staticcall(abi.encodeWithSignature("DIRECTORY()"));
        if (okDir && dirData.length >= 32) {
            _check({
                condition: abi.decode(dirData, (address)) == address(directory),
                label: string.concat("Sucker deployer ", vm.toString(deployer), ".DIRECTORY == directory"),
                critical: true
            });
        }
        (bool okTok, bytes memory tokData) = deployer.staticcall(abi.encodeWithSignature("TOKENS()"));
        if (okTok && tokData.length >= 32) {
            _check({
                condition: abi.decode(tokData, (address)) == address(tokens),
                label: string.concat("Sucker deployer ", vm.toString(deployer), ".TOKENS == tokens"),
                critical: true
            });
        }
        (bool okPerm, bytes memory permData) = deployer.staticcall(abi.encodeWithSignature("PERMISSIONS()"));
        if (okPerm && permData.length >= 32) {
            _check({
                condition: abi.decode(permData, (address)) == address(permissions),
                label: string.concat("Sucker deployer ", vm.toString(deployer), ".PERMISSIONS == permissions"),
                critical: true
            });
        }
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

                // BL: require the registry to resolve each canonical project to the canonical
                // router terminal. Without this, the registry could route project N through a
                // forked router (different fee handling, different beneficiary resolution) while
                // still passing the "registry in terminal list" check.
                if (address(routerTerminal) != address(0)) {
                    (bool ok, bytes memory data) = address(routerTerminalRegistry)
                        .staticcall(abi.encodeWithSignature("terminalOf(uint256)", projectIds[i]));
                    if (ok && data.length >= 32) {
                        _check({
                            condition: abi.decode(data, (address)) == address(routerTerminal),
                            label: string.concat(
                                labels[i], " RouterTerminalRegistry.terminalOf == canonical RouterTerminal"
                            ),
                            critical: true
                        });
                    } else {
                        _check({
                            condition: false,
                            label: string.concat(labels[i], " RouterTerminalRegistry exposes terminalOf(uint256)"),
                            critical: true
                        });
                    }
                }

                // BL: exact terminal-list membership. The canonical deployment installs exactly
                // two terminals: JBMultiTerminal + JBRouterTerminalRegistry. Anything else in the
                // list is either a stale leftover or a malicious injection. Refusing extras is
                // the audit's "exact list" gate.
                _check({
                    condition: terminals.length == 2,
                    label: string.concat(labels[i], " terminal list has exactly 2 entries"),
                    critical: true
                });
                if (terminals.length == 2) {
                    bool hasMulti;
                    bool hasRegistry;
                    for (uint256 j; j < 2; j++) {
                        if (address(terminals[j]) == address(terminal)) hasMulti = true;
                        if (address(terminals[j]) == address(routerTerminalRegistry)) hasRegistry = true;
                    }
                    _check({
                        condition: hasMulti && hasRegistry,
                        label: string.concat(
                            labels[i], " terminal list == {JBMultiTerminal, JBRouterTerminalRegistry}"
                        ),
                        critical: true
                    });
                }
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

        // CJ: assert the JBERC20 implementation bytecode matches the published artifact.
        _requireArtifactIdentity({artifactName: "JBERC20", deployed: address(tokenImpl), label: "JBERC20 impl"});

        // Decision A: run the implementation-identity sweep for every audited contract group.
        // Coverage: CK / CL / CM / CN / CO / CI / BE / BF / BH / BJ. Skips when an artifact file
        // is missing so partial-coverage chains still get a clear log; production-chain build
        // pipeline regenerates the manifest so the artifacts are always present.
        _verifyImplementationIdentities();

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
        // VERIFY_TRUSTED_FORWARDER is required on production chains (see the production guard
        // earlier in `setUp`), so on those chains this block always runs.
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

            // Extend the trusted-forwarder check across every ERC-2771-aware surface the deployment
            // graph touches. Decision A masks immutables before bytecode comparison, so it cannot
            // prove which forwarder a contract was constructed with — only the per-surface getter
            // can. Each `address != 0` guard mirrors the conditional load convention used for
            // PERMISSIONS() below so periphery contracts unloaded on the current chain are skipped
            // by the production manifest, not by silent fall-through.
            if (address(prices) != address(0)) {
                _check({
                    condition: prices.trustedForwarder() == expectedTrustedForwarder,
                    label: "Prices.trustedForwarder == expected",
                    critical: true
                });
            }
            if (address(buybackRegistry) != address(0)) {
                _check({
                    condition: buybackRegistry.trustedForwarder() == expectedTrustedForwarder,
                    label: "BuybackRegistry.trustedForwarder == expected",
                    critical: true
                });
            }
            if (address(suckerRegistry) != address(0)) {
                _check({
                    condition: suckerRegistry.trustedForwarder() == expectedTrustedForwarder,
                    label: "SuckerRegistry.trustedForwarder == expected",
                    critical: true
                });
            }
            if (address(omnichainDeployer) != address(0)) {
                _check({
                    condition: omnichainDeployer.trustedForwarder() == expectedTrustedForwarder,
                    label: "OmnichainDeployer.trustedForwarder == expected",
                    critical: true
                });
            }
            if (address(revDeployer) != address(0)) {
                _check({
                    condition: revDeployer.trustedForwarder() == expectedTrustedForwarder,
                    label: "REVDeployer.trustedForwarder == expected",
                    critical: true
                });
            }
            if (address(revLoans) != address(0)) {
                _check({
                    condition: revLoans.trustedForwarder() == expectedTrustedForwarder,
                    label: "REVLoans.trustedForwarder == expected",
                    critical: true
                });
            }
            if (address(routerTerminalRegistry) != address(0)) {
                _check({
                    condition: routerTerminalRegistry.trustedForwarder() == expectedTrustedForwarder,
                    label: "RouterTerminalRegistry.trustedForwarder == expected",
                    critical: true
                });
            }
            if (address(routerTerminal) != address(0)) {
                _check({
                    condition: routerTerminal.trustedForwarder() == expectedTrustedForwarder,
                    label: "RouterTerminal.trustedForwarder == expected",
                    critical: true
                });
            }
            if (address(hookDeployer) != address(0)) {
                _check({
                    condition: hookDeployer.trustedForwarder() == expectedTrustedForwarder,
                    label: "HookDeployer.trustedForwarder == expected",
                    critical: true
                });
            }
            if (address(hookProjectDeployer) != address(0)) {
                _check({
                    condition: hookProjectDeployer.trustedForwarder() == expectedTrustedForwarder,
                    label: "HookProjectDeployer.trustedForwarder == expected",
                    critical: true
                });
            }
            if (address(ctPublisher) != address(0)) {
                _check({
                    condition: ctPublisher.trustedForwarder() == expectedTrustedForwarder,
                    label: "CTPublisher.trustedForwarder == expected",
                    critical: true
                });
            }
            if (address(ctDeployer) != address(0)) {
                _check({
                    condition: ctDeployer.trustedForwarder() == expectedTrustedForwarder,
                    label: "CTDeployer.trustedForwarder == expected",
                    critical: true
                });
            }
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

        // JBPrices is itself a permissioned surface — `addPriceFeedFor` is gated by
        // `JBPermissioned._requirePermissionFrom`, so a noncanonical registry pointer could let
        // a stale operator install price feeds against the wrong account graph.
        if (address(prices) != address(0)) {
            _check({
                condition: address(prices.PERMISSIONS()) == address(permissions),
                label: "Prices.PERMISSIONS == permissions",
                critical: true
            });
        }
        // CTPublisher / CTDeployer both extend JBPermissioned. `mintFrom` and the deployer's tier
        // adjustments are gated by `_requirePermissionFrom`, so a wrong registry here lets a stale
        // operator set tiers on canonical-deployer-owned hooks during the launch window.
        if (address(ctPublisher) != address(0)) {
            _check({
                condition: address(ctPublisher.PERMISSIONS()) == address(permissions),
                label: "CTPublisher.PERMISSIONS == permissions",
                critical: true
            });
        }
        if (address(ctDeployer) != address(0)) {
            _check({
                condition: address(ctDeployer.PERMISSIONS()) == address(permissions),
                label: "CTDeployer.PERMISSIONS == permissions",
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

        // Wildcard 3: sucker registry MAP_SUCKER_TOKEN on any project, granted by
        // JBOmnichainDeployer in its constructor (`SUCKER_REGISTRY` operator, account=deployer).
        // Without this grant, omnichain-deployed revnets cannot map their cross-chain tokens
        // post-launch — a silent breakage of sucker functionality the verifier must catch.
        if (address(omnichainDeployer) != address(0) && address(suckerRegistry) != address(0)) {
            _check({
                condition: permissions.hasPermission({
                    operator: address(suckerRegistry),
                    account: address(omnichainDeployer),
                    projectId: 0,
                    permissionId: JBPermissionIds.MAP_SUCKER_TOKEN,
                    includeRoot: true,
                    includeWildcardProjectId: true
                }),
                label: "Permissions: SuckerRegistry wildcard MAP_SUCKER_TOKEN granted by OmnichainDeployer",
                critical: true
            });
        }

        // Wildcard 4: Croptop publisher ADJUST_721_TIERS on any project the deployer temporarily
        // owns, granted by CTDeployer's constructor (`PUBLISHER` operator, account=deployer).
        // Without it, every Croptop hook launched through `CTDeployer.deployHookFor` will revert
        // on the first publisher-driven tier adjustment.
        if (address(ctDeployer) != address(0) && address(ctPublisher) != address(0)) {
            _check({
                condition: permissions.hasPermission({
                    operator: address(ctPublisher),
                    account: address(ctDeployer),
                    projectId: 0,
                    permissionId: JBPermissionIds.ADJUST_721_TIERS,
                    includeRoot: true,
                    includeWildcardProjectId: true
                }),
                label: "Permissions: CTPublisher wildcard ADJUST_721_TIERS granted by CTDeployer",
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
    /// `envVar`. On production chains the env var is mandatory (fail-closed); on testnets and
    /// partial-stack chains the check skips when the env var is not set.
    function _verifySplitOperatorGrantsFor(string memory envVar, uint256 projectId, string memory label) internal {
        address operator = vm.envOr({name: envVar, defaultValue: address(0)});
        if (operator == address(0)) {
            // Fail-closed on the canonical production chains so a launch run cannot silently skip
            // verifying the broad operator grants for any of the four canonical projects. The
            // mainnet chain list mirrors the production guard in `setUp`.
            bool isProductionChain =
                (block.chainid == 1 || block.chainid == 10 || block.chainid == 8453 || block.chainid == 42_161);
            if (isProductionChain) {
                _check({
                    condition: false,
                    label: string.concat(envVar, " MUST be set on production for ", label, " split-operator grants"),
                    critical: true
                });
                return;
            }
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

        // BI: require exact expected config hashes on every canonical project on production chains.
        // Per-project env vars VERIFY_CONFIG_HASH_{1..4} take precedence (matches the audit's
        // recommendation); the legacy VERIFY_CONFIG_HASHES CSV is still accepted for backwards
        // compatibility. On production chains, missing or zero expected hashes are critical.
        uint256[4] memory pids = [_FEE_PROJECT_ID, _CPN_PROJECT_ID, _REV_PROJECT_ID, _BAN_PROJECT_ID];
        string[4] memory names = ["NANA(1)", "CPN(2)", "REV(3)", "BAN(4)"];
        string[4] memory envVars =
            ["VERIFY_CONFIG_HASH_1", "VERIFY_CONFIG_HASH_2", "VERIFY_CONFIG_HASH_3", "VERIFY_CONFIG_HASH_4"];

        bytes32[4] memory expectedHashes = _loadExpectedConfigHashes(envVars);
        bool isProductionChain =
            (block.chainid == 1 || block.chainid == 10 || block.chainid == 8453 || block.chainid == 42_161);

        for (uint256 i; i < 4; i++) {
            bytes32 actual = revDeployer.hashedEncodedConfigurationOf(pids[i]);
            _check({
                condition: actual != bytes32(0),
                label: string.concat(names[i], " has non-zero config hash"),
                critical: true
            });

            if (expectedHashes[i] != bytes32(0)) {
                _check({
                    condition: actual == expectedHashes[i],
                    label: string.concat(names[i], " config hash == expected"),
                    critical: true
                });
            } else if (isProductionChain) {
                _check({
                    condition: false,
                    label: string.concat(names[i], " expected config hash MUST be set on production via ", envVars[i]),
                    critical: true
                });
            } else {
                _skip(string.concat(names[i], " expected config hash not provided (", envVars[i], " unset)"));
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

            // BC: per-pair runtime sanity — each pair's local sucker must have code, must be
            // registered with the canonical sucker registry, and must expose a non-zero remote
            // chain id alongside the non-zero remote address. Without these, a malformed entry
            // (zero remote chain id, EOA local, unregistered sucker) survives just because the
            // count happens to match.
            for (uint256 j; j < pairs.length; j++) {
                string memory pairLabel = string.concat(names[i], " sucker pair ", vm.toString(j));
                _check({
                    condition: pairs[j].remote != bytes32(0),
                    label: string.concat(pairLabel, " has non-zero remote"),
                    critical: true
                });
                address local = pairs[j].local;
                _check({
                    condition: local != address(0) && local.code.length > 0,
                    label: string.concat(pairLabel, " local sucker has code"),
                    critical: true
                });
                if (local.code.length == 0) continue;

                // Local sucker must be registered under the canonical project ID.
                (bool okIsOf, bytes memory isOfData) = address(suckerRegistry)
                    .staticcall(abi.encodeWithSignature("isSuckerOf(uint256,address)", pids[i], local));
                if (okIsOf && isOfData.length >= 32) {
                    _check({
                        condition: abi.decode(isOfData, (bool)),
                        label: string.concat(pairLabel, " local is registered as a sucker of the project"),
                        critical: true
                    });
                }

                // Local sucker must expose a non-zero remote chain id. Format mismatches
                // (uint vs bytes32, missing getter) are surfaced as a critical failure rather
                // than silent skip — the canonical sucker types all expose this.
                (bool okChainId, bytes memory chainIdData) = local.staticcall(abi.encodeWithSignature("peerChainId()"));
                if (okChainId && chainIdData.length >= 32) {
                    _check({
                        condition: abi.decode(chainIdData, (uint256)) != 0,
                        label: string.concat(pairLabel, " peerChainId is non-zero"),
                        critical: true
                    });
                } else {
                    _check({
                        condition: false,
                        label: string.concat(pairLabel, " local sucker exposes peerChainId()"),
                        critical: true
                    });
                }

                // BC residual: native-token bridge mapping must be enabled. A pair where the
                // native-token mapping is intentionally disabled (or emergency-hatch-stuck) is
                // structurally indistinguishable from a properly-deployed pair on the count +
                // remote checks, but the native cross-chain transfer path is dead for end users.
                // The audit explicitly called this out: "disabled native-token mapping still
                // passes" in the BC residual list.
                (bool okMap, bytes memory mapData) =
                    local.staticcall(abi.encodeWithSignature("remoteTokenFor(address)", JBConstants.NATIVE_TOKEN));
                if (okMap && mapData.length >= 32) {
                    // JBRemoteToken layout: { enabled, emergencyHatch, minGas, addr } — the first
                    // 32-byte slot holds `enabled` as the right-aligned bool.
                    bool nativeEnabled;
                    assembly {
                        nativeEnabled := iszero(iszero(mload(add(mapData, 0x20))))
                    }
                    _check({
                        condition: nativeEnabled,
                        label: string.concat(pairLabel, " native-token remote mapping is enabled"),
                        critical: true
                    });
                } else {
                    _check({
                        condition: false,
                        label: string.concat(pairLabel, " local sucker exposes remoteTokenFor(address)"),
                        critical: true
                    });
                }
            }
        }

        // BC known gap: exact-manifest equality (each pair's expected remote address, remote
        // chain id, and per-token mapping) requires per-route env vars or an off-chain manifest.
        // The on-chain verifier proves no malformed pair survives; per-route expected values are
        // a follow-up that the BC PR description points to.
        console.log("  [INFO] BC: per-pair runtime sanity asserted; exact-manifest follow-up via env vars");

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

        // BA: pin the immutable PERMIT2 wiring on every deployed contract that exposes it to the
        // canonical Permit2 singleton. Without the exact-address check, a deployment that wired in
        // a forked Permit2 (different signature semantics, different ownership) would still pass.
        address expectedPermit2 = _expectedPermit2();
        address expectedWrappedNative = _expectedWrappedNative();

        if (expectedPermit2 != address(0)) {
            _check({
                condition: address(terminal.PERMIT2()) == expectedPermit2,
                label: "Terminal.PERMIT2 == canonical Permit2",
                critical: true
            });
            if (address(routerTerminal) != address(0)) {
                _check({
                    condition: address(routerTerminal.PERMIT2()) == expectedPermit2,
                    label: "RouterTerminal.PERMIT2 == canonical Permit2",
                    critical: true
                });
            }
            if (address(revLoans) != address(0)) {
                _check({
                    condition: address(revLoans.PERMIT2()) == expectedPermit2,
                    label: "REVLoans.PERMIT2 == canonical Permit2",
                    critical: true
                });
            }
        } else {
            // Fall back to non-zero on chains without a canonical Permit2 manifest. The skip is
            // logged so operators see which chains are still gaps.
            _check({
                condition: address(terminal.PERMIT2()) != address(0),
                label: "Terminal.PERMIT2 is non-zero (no canonical manifest for this chain)",
                critical: true
            });
            _skip("BA: Permit2 exact-address check skipped (no manifest for this chain)");
        }

        // BA: pin WRAPPED_NATIVE_TOKEN on the router terminal to the canonical WETH for this chain.
        // The router uses this to settle native unwrapping on swap-out — a wrong WETH lets the
        // router pull from / push to a token with attacker-controlled mint/burn semantics.
        if (address(routerTerminal) != address(0)) {
            if (expectedWrappedNative != address(0)) {
                _check({
                    condition: address(routerTerminal.WRAPPED_NATIVE_TOKEN()) == expectedWrappedNative,
                    label: "RouterTerminal.WRAPPED_NATIVE_TOKEN == canonical WETH",
                    critical: true
                });
            } else {
                _check({
                    condition: address(routerTerminal.WRAPPED_NATIVE_TOKEN()) != address(0),
                    label: "RouterTerminal.WRAPPED_NATIVE_TOKEN is non-zero (no canonical manifest)",
                    critical: true
                });
                _skip("BA: WETH exact-address check skipped (no manifest for this chain)");
            }
        }

        // OmnichainDeployer DIRECTORY (existing check — kept).
        _check({
            condition: address(omnichainDeployer.DIRECTORY()) == address(directory),
            label: "OmnichainDeployer.DIRECTORY == directory",
            critical: true
        });

        // BA residual: Defifa typeface. DefifaTokenUriResolver.TYPEFACE() must equal the per-chain
        // canonical typeface contract. The resolver SVGs read on-chain glyphs from this typeface;
        // a wrong typeface ships incorrect or attacker-controlled imagery for every Defifa NFT.
        address expectedTypeface = _expectedDefifaTypeface();
        if (address(defifaDeployer) != address(0) && expectedTypeface != address(0)) {
            (bool okResolver, bytes memory resolverData) =
                address(defifaDeployer).staticcall(abi.encodeWithSignature("TOKEN_URI_RESOLVER()"));
            if (okResolver && resolverData.length >= 32) {
                address resolver = abi.decode(resolverData, (address));
                if (resolver != address(0)) {
                    (bool okType, bytes memory typeData) = resolver.staticcall(abi.encodeWithSignature("TYPEFACE()"));
                    if (okType && typeData.length >= 32) {
                        _check({
                            condition: abi.decode(typeData, (address)) == expectedTypeface,
                            label: "DefifaTokenUriResolver.TYPEFACE == canonical Capsules typeface",
                            critical: true
                        });
                    } else {
                        _check({condition: false, label: "DefifaTokenUriResolver exposes TYPEFACE()", critical: true});
                    }
                }
            }
        }

        // BA residual: Uniswap stack provenance — V3 factory, V4 PoolManager, V4 PositionManager.
        // The buyback hook reads pool state from these to price the buyback route, and the
        // LP-split hook deposits liquidity into them. A forked V3/V4 deployment with attacker-
        // controlled fee/observation semantics survives without these checks.
        address expectedV3Factory = _expectedV3Factory();
        address expectedV4PoolManager = _expectedV4PoolManager();
        if (address(_uniswapV4Hook()) != address(0)) {
            if (expectedV4PoolManager != address(0)) {
                (bool okPM, bytes memory pmData) =
                    address(_uniswapV4Hook()).staticcall(abi.encodeWithSignature("poolManager()"));
                if (okPM && pmData.length >= 32) {
                    _check({
                        condition: abi.decode(pmData, (address)) == expectedV4PoolManager,
                        label: "JBUniswapV4Hook.poolManager == canonical V4 PoolManager",
                        critical: true
                    });
                }
            }
        }
        if (address(buybackRegistry) != address(0) && expectedV3Factory != address(0)) {
            (bool okHook, bytes memory hookData) =
                address(buybackRegistry).staticcall(abi.encodeWithSignature("defaultHook()"));
            if (okHook && hookData.length >= 32) {
                address bh = abi.decode(hookData, (address));
                if (bh != address(0)) {
                    (bool okFac, bytes memory facData) = bh.staticcall(abi.encodeWithSignature("UNISWAP_V3_FACTORY()"));
                    if (okFac && facData.length >= 32) {
                        _check({
                            condition: abi.decode(facData, (address)) == expectedV3Factory,
                            label: "JBBuybackHook.UNISWAP_V3_FACTORY == canonical V3 factory",
                            critical: true
                        });
                    }
                }
            }
        }

        // BA residual: V4 PositionManager identity on the LP split hook deployer. Every clone
        // produced by `deployHookFor` is initialized with the deployer's `POSITION_MANAGER`, so
        // proving the deployer's pointer matches the canonical PositionManager bounds every
        // future LP split hook clone to the canonical V4 liquidity surface. Skip on chains
        // without a published PositionManager (e.g. Optimism Sepolia) or when the env var is
        // not provided (testnets / partial stacks).
        address expectedV4PositionManager = _expectedV4PositionManager();
        if (lpSplitHookDeployer != address(0) && expectedV4PositionManager != address(0)) {
            (bool okPosMgr, bytes memory posMgrData) =
                lpSplitHookDeployer.staticcall(abi.encodeWithSignature("POSITION_MANAGER()"));
            if (okPosMgr && posMgrData.length >= 32) {
                _check({
                    condition: abi.decode(posMgrData, (address)) == expectedV4PositionManager,
                    label: "JBUniswapV4LPSplitHookDeployer.POSITION_MANAGER == canonical V4 PositionManager",
                    critical: true
                });
            } else {
                _check({
                    condition: false, label: "JBUniswapV4LPSplitHookDeployer exposes POSITION_MANAGER()", critical: true
                });
            }
        } else if (lpSplitHookDeployer == address(0) && expectedV4PositionManager != address(0)) {
            // Production chain has a canonical PositionManager but operator did not provide the
            // deployer address. Fail closed so the manifest gap is visible at verify time.
            bool isProductionChain =
                (block.chainid == 1 || block.chainid == 10 || block.chainid == 8453 || block.chainid == 42_161);
            if (isProductionChain) {
                _check({
                    condition: false,
                    label: "VERIFY_LP_SPLIT_HOOK_DEPLOYER MUST be set on production for V4 PositionManager identity",
                    critical: true
                });
            } else {
                _skip("V4 PositionManager identity (VERIFY_LP_SPLIT_HOOK_DEPLOYER not set on non-production chain)");
            }
        }

        console.log("");
    }

    /// Stub: returns the registered Uniswap V4 hook address. Used by the BA external-address
    /// sweep to chain into V4 PoolManager identity. Reads from the loaded buyback registry
    /// rather than introducing a new state var — the registry's defaultHook on production
    /// chains is the V4 hook.
    function _uniswapV4Hook() internal view returns (address) {
        if (address(buybackRegistry) == address(0)) return address(0);
        (bool ok, bytes memory data) = address(buybackRegistry).staticcall(abi.encodeWithSignature("defaultHook()"));
        if (!ok || data.length < 32) return address(0);
        return abi.decode(data, (address));
    }

    function _checkpointsDeployer() internal view returns (address) {
        return address(checkpointsDeployer);
    }

    /// BS residual: when VERIFY_CPN_* env vars are set for a category, assert exact equality on
    /// each criterion field. Skips per-field when its env var is unset so operators can opt in
    /// incrementally. The on-chain "minPrice > 0" sanity check above remains the always-on gate.
    function _verifyCpnCriterionExact(
        uint256 cat,
        uint256 minPrice,
        uint256 minSupply,
        uint256 maxSupply,
        uint256 maxSplitPct,
        address[] memory allowed
    )
        internal
    {
        string memory minPriceVar = string.concat("VERIFY_CPN_MIN_PRICE_", vm.toString(cat));
        string memory minSupplyVar = string.concat("VERIFY_CPN_MIN_SUPPLY_", vm.toString(cat));
        string memory maxSupplyVar = string.concat("VERIFY_CPN_MAX_SUPPLY_", vm.toString(cat));
        string memory maxSplitVar = string.concat("VERIFY_CPN_MAX_SPLIT_PERCENT_", vm.toString(cat));
        string memory allowedVar = string.concat("VERIFY_CPN_ALLOWED_ADDRESSES_", vm.toString(cat));

        string memory raw;
        raw = vm.envOr({name: minPriceVar, defaultValue: string("")});
        if (bytes(raw).length > 0) {
            _check({
                condition: minPrice == vm.parseUint(raw),
                label: string.concat("CPN category ", vm.toString(cat), " minPrice == expected"),
                critical: true
            });
        }
        raw = vm.envOr({name: minSupplyVar, defaultValue: string("")});
        if (bytes(raw).length > 0) {
            _check({
                condition: minSupply == vm.parseUint(raw),
                label: string.concat("CPN category ", vm.toString(cat), " minSupply == expected"),
                critical: true
            });
        }
        raw = vm.envOr({name: maxSupplyVar, defaultValue: string("")});
        if (bytes(raw).length > 0) {
            _check({
                condition: maxSupply == vm.parseUint(raw),
                label: string.concat("CPN category ", vm.toString(cat), " maxSupply == expected"),
                critical: true
            });
        }
        raw = vm.envOr({name: maxSplitVar, defaultValue: string("")});
        if (bytes(raw).length > 0) {
            _check({
                condition: maxSplitPct == vm.parseUint(raw),
                label: string.concat("CPN category ", vm.toString(cat), " maxSplitPercent == expected"),
                critical: true
            });
        }
        raw = vm.envOr({name: allowedVar, defaultValue: string("")});
        if (bytes(raw).length > 0) {
            // Empty CSV literal "" (handled above) skips. Non-empty: each entry must be parseable;
            // require lengths match and elements equal in order. The canonical CPN config sets an
            // empty allowed-addresses list, so the most common operator setting is `""` (skip).
            string[] memory parts = vm.split(raw, ",");
            _check({
                condition: allowed.length == parts.length,
                label: string.concat("CPN category ", vm.toString(cat), " allowed-addresses length == expected"),
                critical: true
            });
            for (uint256 i; i < parts.length && i < allowed.length; i++) {
                _check({
                    condition: allowed[i] == vm.parseAddress(parts[i]),
                    label: string.concat(
                        "CPN category ", vm.toString(cat), " allowed[", vm.toString(i), "] == expected"
                    ),
                    critical: true
                });
            }
        }
    }

    /// BI helper: loads the expected per-project config hashes from VERIFY_CONFIG_HASH_{1..4}.
    /// Falls back to the legacy VERIFY_CONFIG_HASHES CSV when individual vars are unset, for
    /// backwards compatibility with existing operator scripts.
    function _loadExpectedConfigHashes(string[4] memory envVars) internal view returns (bytes32[4] memory hashes) {
        // Per-project env vars take precedence.
        for (uint256 i; i < 4; i++) {
            string memory v = vm.envOr({name: envVars[i], defaultValue: string("")});
            if (bytes(v).length > 0) {
                hashes[i] = vm.parseBytes32(v);
            }
        }
        // Fall back to the legacy CSV for any slots not filled above.
        string memory csv = vm.envOr({name: "VERIFY_CONFIG_HASHES", defaultValue: string("")});
        if (bytes(csv).length > 0) {
            string[] memory parts = vm.split(csv, ",");
            for (uint256 i; i < parts.length && i < 4; i++) {
                if (hashes[i] == bytes32(0) && bytes(parts[i]).length > 0) {
                    hashes[i] = vm.parseBytes32(parts[i]);
                }
            }
        }
    }

    /// Returns the canonical Permit2 singleton address for this chain. Permit2 is deployed at the
    /// same CREATE2 address on every supported chain. Returns address(0) on unsupported chains.
    function _expectedPermit2() internal view returns (address) {
        // Canonical Permit2 across all EVM chains where deployed.
        if (
            block.chainid == 1 || block.chainid == 11_155_111 || block.chainid == 10 || block.chainid == 11_155_420
                || block.chainid == 8453 || block.chainid == 84_532 || block.chainid == 42_161
                || block.chainid == 421_614
        ) {
            return 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        }
        return address(0);
    }

    /// Returns the per-chain canonical Capsules typeface address used by DefifaTokenUriResolver.
    /// Mirrors Deploy.s.sol's chain-specific `_typeface` assignments.
    function _expectedDefifaTypeface() internal view returns (address) {
        if (block.chainid == 1) return 0xA77b7D93E79f1E6B4f77FaB29d9ef85733A3D44A;
        if (block.chainid == 11_155_111) return 0x8C420d3388C882F40d263714d7A6e2c8DB93905F;
        if (block.chainid == 10) return 0xe160e47928907894F97a0DC025c61D64E862fEAa;
        if (block.chainid == 11_155_420) return 0xe160e47928907894F97a0DC025c61D64E862fEAa;
        if (block.chainid == 8453) return 0x3DE45A14ea0fe24037D6363Ae71Ef18F336D1C27;
        if (block.chainid == 84_532) return 0xEb269d9F0850CEf5e3aB0F9718fb79c466720784;
        if (block.chainid == 42_161) return 0x431C35e9fA5152A906A38390910d0Cfcba0Fb43b;
        if (block.chainid == 421_614) return 0x431C35e9fA5152A906A38390910d0Cfcba0Fb43b;
        return address(0);
    }

    /// Returns the per-chain canonical Uniswap V3 factory address. Mirrors Deploy.s.sol's
    /// chain-specific `_v3Factory` assignments.
    function _expectedV3Factory() internal view returns (address) {
        if (block.chainid == 1) return 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        if (block.chainid == 11_155_111) return 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
        if (block.chainid == 10) return 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        if (block.chainid == 11_155_420) return 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
        if (block.chainid == 8453) return 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
        if (block.chainid == 84_532) return 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
        if (block.chainid == 42_161) return 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        if (block.chainid == 421_614) return 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e;
        return address(0);
    }

    /// Returns the per-chain canonical Uniswap V4 PoolManager address. Mirrors Deploy.s.sol's
    /// chain-specific `_poolManager` assignments.
    function _expectedV4PoolManager() internal view returns (address) {
        if (block.chainid == 1) return 0x000000000004444c5dc75cB358380D2e3dE08A90;
        if (block.chainid == 11_155_111) return 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
        if (block.chainid == 10) return 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
        if (block.chainid == 11_155_420) return 0x000000000004444c5dc75cB358380D2e3dE08A90;
        if (block.chainid == 8453) return 0x498581fF718922c3f8e6A244956aF099B2652b2b;
        if (block.chainid == 84_532) return 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
        if (block.chainid == 42_161) return 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
        if (block.chainid == 421_614) return 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
        return address(0);
    }

    /// Returns the per-chain canonical Uniswap V4 PositionManager address. Mirrors Deploy.s.sol's
    /// chain-specific `_positionManager` assignments. Optimism Sepolia returns `address(0)`
    /// because Uniswap has not published a canonical PositionManager there yet.
    function _expectedV4PositionManager() internal view returns (address) {
        if (block.chainid == 1) return 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
        if (block.chainid == 11_155_111) return 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
        if (block.chainid == 10) return 0x3C3Ea4B57a46241e54610e5f022E5c45859A1017;
        if (block.chainid == 11_155_420) return address(0);
        if (block.chainid == 8453) return 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
        if (block.chainid == 84_532) return 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
        if (block.chainid == 42_161) return 0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869;
        if (block.chainid == 421_614) return 0xAc631556d3d4019C95769033B5E719dD77124BAc;
        return address(0);
    }

    /// Returns the canonical WETH (wrapped native token) address for this chain.
    function _expectedWrappedNative() internal view returns (address) {
        if (block.chainid == 1) return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        if (block.chainid == 11_155_111) return 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        if (block.chainid == 10) return 0x4200000000000000000000000000000000000006;
        if (block.chainid == 11_155_420) return 0x4200000000000000000000000000000000000006;
        if (block.chainid == 8453) return 0x4200000000000000000000000000000000000006;
        if (block.chainid == 84_532) return 0x4200000000000000000000000000000000000006;
        if (block.chainid == 42_161) return 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        if (block.chainid == 421_614) return 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
        return address(0);
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

    /// Decision A sweep across every audited group. Each call asserts the deployed runtime
    /// bytecode equals the artifact's deployedBytecode. Logs INFO and skips gracefully when the
    /// artifact file is missing (e.g. partial-coverage testnet) or the contract is not loaded
    /// (e.g. optional Phase 11 periphery on testnet).
    ///
    /// Coverage:
    /// - CK: JBProjects, JBDirectory, JBController, JBMultiTerminal, JBTerminalStore
    /// - CO: JBFundAccessLimits, JBTokens, JBPrices, JBRulesets, JBSplits, JBFeelessAddresses,
    ///       JBPermissions
    /// - CL: REVDeployer, REVOwner, REVLoans
    /// - CM: JBOmnichainDeployer, JBSuckerRegistry
    /// - CN: JB721TiersHookDeployer/Store/ProjectDeployer, JBBuybackHookRegistry,
    ///       JBRouterTerminalRegistry
    /// - CI: CTPublisher, CTDeployer, CTProjectOwner
    /// - BE: JBBuybackHook (default hook implementation)
    /// - BF: JB721TiersHook (base hook implementation)
    /// - BH: JBProjectHandles, JB721Distributor, JBTokenDistributor, JBProjectPayerDeployer
    /// - BJ: JBAddressRegistry, DefifaDeployer + sub-targets (HOOK_CODE_ORIGIN,
    ///       TOKEN_URI_RESOLVER, GOVERNOR)
    function _verifyImplementationIdentities() internal {
        console.log("--- Decision A: Implementation Identity (artifact bytecode parity) ---");

        // CK: core singletons
        _requireArtifactIdentity("JBProjects", address(projects), "JBProjects");
        _requireArtifactIdentity("JBDirectory", address(directory), "JBDirectory");
        _requireArtifactIdentity("JBController", address(controller), "JBController");
        _requireArtifactIdentity("JBMultiTerminal", address(terminal), "JBMultiTerminal");
        _requireArtifactIdentity("JBTerminalStore", address(terminalStore), "JBTerminalStore");

        // CO: core support
        _requireArtifactIdentity("JBFundAccessLimits", address(fundAccessLimits), "JBFundAccessLimits");
        _requireArtifactIdentity("JBTokens", address(tokens), "JBTokens");
        _requireArtifactIdentity("JBPrices", address(prices), "JBPrices");
        _requireArtifactIdentity("JBRulesets", address(rulesets), "JBRulesets");
        _requireArtifactIdentity("JBSplits", address(splits), "JBSplits");
        _requireArtifactIdentity("JBFeelessAddresses", address(feelessAddresses), "JBFeelessAddresses");
        _requireArtifactIdentity("JBPermissions", address(permissions), "JBPermissions");

        // CL: Revnet stack
        _requireArtifactIdentity("REVDeployer", address(revDeployer), "REVDeployer");
        _requireArtifactIdentity("REVOwner", address(revOwner), "REVOwner");
        _requireArtifactIdentity("REVLoans", address(revLoans), "REVLoans");

        // CM: omnichain
        _requireArtifactIdentity("JBOmnichainDeployer", address(omnichainDeployer), "JBOmnichainDeployer");
        _requireArtifactIdentity("JBSuckerRegistry", address(suckerRegistry), "JBSuckerRegistry");

        // CN: hook & registry singletons
        _requireArtifactIdentity("JB721TiersHookDeployer", address(hookDeployer), "JB721TiersHookDeployer");
        _requireArtifactIdentity("JB721TiersHookStore", address(hookStore), "JB721TiersHookStore");
        _requireArtifactIdentity(
            "JB721TiersHookProjectDeployer", address(hookProjectDeployer), "JB721TiersHookProjectDeployer"
        );
        _requireArtifactIdentity("JBBuybackHookRegistry", address(buybackRegistry), "JBBuybackHookRegistry");
        _requireArtifactIdentity(
            "JBRouterTerminalRegistry", address(routerTerminalRegistry), "JBRouterTerminalRegistry"
        );

        // CI: Croptop
        _requireArtifactIdentity("CTPublisher", address(ctPublisher), "CTPublisher");
        _requireArtifactIdentity("CTDeployer", address(ctDeployer), "CTDeployer");
        _requireArtifactIdentity("CTProjectOwner", address(ctProjectOwner), "CTProjectOwner");

        // BE: buyback hook default implementation (via registry getter)
        if (address(buybackRegistry) != address(0)) {
            (bool ok, bytes memory data) = address(buybackRegistry).staticcall(abi.encodeWithSignature("defaultHook()"));
            if (ok && data.length >= 32) {
                _requireArtifactIdentity("JBBuybackHook", abi.decode(data, (address)), "JBBuybackHook default");
            }
        }

        // BF: 721 tiers hook base implementation (via low-level call so the interface return-type
        // mismatch between JB721TiersHookDeployer.HOOK() and IJB721TiersHook doesn't bite).
        {
            (bool okHook, bytes memory hookData) = address(hookDeployer).staticcall(abi.encodeWithSignature("HOOK()"));
            if (okHook && hookData.length >= 32) {
                _requireArtifactIdentity("JB721TiersHook", abi.decode(hookData, (address)), "JB721TiersHook base impl");
            }
        }

        // BH: Phase 11 periphery
        _requireArtifactIdentity("JBProjectHandles", address(projectHandles), "JBProjectHandles");
        _requireArtifactIdentity("JB721Distributor", address(distributor721), "JB721Distributor");
        _requireArtifactIdentity("JBTokenDistributor", address(tokenDistributor), "JBTokenDistributor");
        _requireArtifactIdentity("JBProjectPayerDeployer", address(projectPayerDeployer), "JBProjectPayerDeployer");

        // BH residual: the JBProjectPayer implementation behind JBProjectPayerDeployer.IMPLEMENTATION
        // also needs identity. Deployer-only identity proves the FACTORY is canonical but not the
        // CLONE TARGET — and every JBProjectPayer clone delegates to that implementation.
        if (address(projectPayerDeployer) != address(0)) {
            (bool okImpl, bytes memory implData) =
                address(projectPayerDeployer).staticcall(abi.encodeWithSignature("IMPLEMENTATION()"));
            if (okImpl && implData.length >= 32) {
                _requireArtifactIdentity("JBProjectPayer", abi.decode(implData, (address)), "JBProjectPayer clone impl");
            }
        }

        // BF residual: the JB721Checkpoints implementation behind JB721CheckpointsDeployer.IMPLEMENTATION
        // is the analogous case for the 721 checkpoint module. Deployer-only identity (covered in CN)
        // is insufficient; the clone target needs its own check.
        if (address(_checkpointsDeployer()) != address(0)) {
            (bool okImpl, bytes memory implData) =
                _checkpointsDeployer().staticcall(abi.encodeWithSignature("IMPLEMENTATION()"));
            if (okImpl && implData.length >= 32) {
                _requireArtifactIdentity(
                    "JB721Checkpoints", abi.decode(implData, (address)), "JB721Checkpoints clone impl"
                );
            }
        }

        // BJ: Defifa + AddressRegistry
        _requireArtifactIdentity("JBAddressRegistry", addressRegistry, "JBAddressRegistry");
        _requireArtifactIdentity("DefifaDeployer", address(defifaDeployer), "DefifaDeployer");
        if (address(defifaDeployer) != address(0)) {
            (bool okOrigin, bytes memory originData) =
                address(defifaDeployer).staticcall(abi.encodeWithSignature("HOOK_CODE_ORIGIN()"));
            if (okOrigin && originData.length >= 32) {
                _requireArtifactIdentity("DefifaHook", abi.decode(originData, (address)), "DefifaHook code origin");
            }
            (bool okResolver, bytes memory resolverData) =
                address(defifaDeployer).staticcall(abi.encodeWithSignature("TOKEN_URI_RESOLVER()"));
            if (okResolver && resolverData.length >= 32) {
                _requireArtifactIdentity(
                    "DefifaTokenUriResolver", abi.decode(resolverData, (address)), "DefifaTokenUriResolver"
                );
            }
            (bool okGov, bytes memory govData) =
                address(defifaDeployer).staticcall(abi.encodeWithSignature("GOVERNOR()"));
            if (okGov && govData.length >= 32) {
                _requireArtifactIdentity("DefifaGovernor", abi.decode(govData, (address)), "DefifaGovernor");
            }
        }

        // Phase 4 rollout-evidence gate: each listed swap-enabled CCIP sucker deployer (and its
        // singleton) must match the canonical artifact bytecode. Without this check the deploy
        // can ship a swap-enabled sucker that pre-dates the S+AH fixes (out-of-order batch
        // metadata stranding earlier batches; raw-ETH V4 settlement reverting before unwrap),
        // but reads as "allowed in registry" and "canonically wired". Identity covers both the
        // deployer factory and the per-route singleton that every clone proxies to.
        _verifySwapCcipSuckerRolloutIdentity();

        console.log("");
    }

    /// @dev Phase 4 / S+AH: prove each listed swap-enabled CCIP sucker deployer + singleton
    /// carries the canonical (post-PR-#120) bytecode. Comma-separated env list keeps the env
    /// surface aligned with `VERIFY_SUCKER_DEPLOYERS` — operators populate this with the
    /// swap-enabled subset only.
    function _verifySwapCcipSuckerRolloutIdentity() internal {
        string memory swapDeployersCsv = vm.envOr("VERIFY_SWAP_CCIP_SUCKER_DEPLOYERS", string(""));
        if (bytes(swapDeployersCsv).length == 0) {
            _skip("Swap-CCIP sucker rollout identity (VERIFY_SWAP_CCIP_SUCKER_DEPLOYERS not set)");
            return;
        }

        string[] memory parts = vm.split(swapDeployersCsv, ",");
        for (uint256 i; i < parts.length; i++) {
            address deployer = vm.parseAddress(parts[i]);
            if (deployer == address(0)) continue;

            // Deployer factory must match the canonical JBSwapCCIPSuckerDeployer runtime.
            _requireArtifactIdentity({
                artifactName: "JBSwapCCIPSuckerDeployer",
                deployed: deployer,
                label: string.concat("JBSwapCCIPSuckerDeployer ", vm.toString(deployer))
            });

            // Per-route singleton is the actual sucker implementation that every clone
            // delegates to; the S/AH fixes live there. Read via `singleton()` to avoid
            // hard-coding a per-chain immutable getter.
            (bool ok, bytes memory data) = deployer.staticcall(abi.encodeWithSignature("singleton()"));
            if (ok && data.length >= 32) {
                address singleton = abi.decode(data, (address));
                _requireArtifactIdentity({
                    artifactName: "JBSwapCCIPSucker",
                    deployed: singleton,
                    label: string.concat("JBSwapCCIPSucker singleton ", vm.toString(singleton))
                });
            } else {
                _check({
                    condition: false,
                    label: string.concat(
                        "Swap-CCIP deployer ", vm.toString(deployer), " exposes singleton() for identity check"
                    ),
                    critical: true
                });
            }
        }
    }

    /// Decision A: assert deployed runtime bytecode at `addr` is structurally identical to the
    /// published artifact's `deployedBytecode`, with all immutable-reference byte ranges masked
    /// to zero on both sides. The mask ranges are read from the artifact's
    /// `deployedBytecode.immutableReferences` (a map of AST-ID -> [{start, length}, ...]).
    ///
    /// The constructor of any contract using Solidity `immutable` keywords writes the immutable
    /// value into runtime bytecode at compiler-chosen offsets. The artifact carries zero bytes
    /// at those positions; a real deployment carries the constructor-injected values. Raw
    /// `extcodehash` equality fails for any such contract — but the bytes OUTSIDE those ranges
    /// are byte-equal between artifact and live, which is what proves the audited source was
    /// compiled and deployed.
    ///
    /// Requires `bytecode_hash = "none"` (BW). Skips with a logged note when the artifact is
    /// missing so partial-coverage chains still produce a clear log line.
    function _requireArtifactIdentity(string memory artifactName, address deployed, string memory label) internal {
        if (deployed == address(0)) {
            _skip(string.concat(label, ": skipped (deployed address is zero)"));
            return;
        }
        string memory artifactPath = string.concat("artifacts/", artifactName, ".json");
        string memory json;
        try vm.readFile(artifactPath) returns (string memory j) {
            json = j;
        } catch {
            _skip(string.concat(label, ": artifact unavailable at ", artifactPath));
            return;
        }
        bytes memory artifactBytecode;
        try vm.parseJsonBytes(json, ".deployedBytecode.object") returns (bytes memory bc) {
            artifactBytecode = bc;
        } catch {
            _skip(string.concat(label, ": artifact has no .deployedBytecode.object"));
            return;
        }

        bytes memory liveBytecode = deployed.code;
        _check({
            condition: liveBytecode.length == artifactBytecode.length,
            label: string.concat(label, ": runtime length == artifact length"),
            critical: true
        });
        if (liveBytecode.length != artifactBytecode.length) return;

        // Mask immutable-reference ranges in both sides.
        _zeroImmutableRanges(artifactBytecode, json);
        _zeroImmutableRanges(liveBytecode, json);

        _check({
            condition: keccak256(liveBytecode) == keccak256(artifactBytecode),
            label: string.concat(label, ": runtime bytecode == artifact (immutable-masked)"),
            critical: true
        });
    }

    /// Zeroes every immutable-reference byte range in `bytecode`, in place. Iterates the artifact's
    /// `deployedBytecode.immutableReferences` map (keyed by AST ID, value an array of
    /// `{start, length}` ranges). The key order doesn't matter; the ranges are byte-aligned.
    function _zeroImmutableRanges(bytes memory bytecode, string memory artifactJson) internal pure {
        string[] memory keys;
        try vm.parseJsonKeys(artifactJson, ".deployedBytecode.immutableReferences") returns (string[] memory k) {
            keys = k;
        } catch {
            return; // No immutableReferences field — nothing to mask.
        }
        for (uint256 i; i < keys.length; i++) {
            string memory keyPath = string.concat(".deployedBytecode.immutableReferences.", keys[i]);
            // The value is an array of `{start, length}` objects. Foundry's parseJson requires
            // struct fields in alphabetical order — so we decode as `ImmutableRange[]` with
            // fields ordered `length` then `start`.
            try vm.parseJson(artifactJson, keyPath) returns (bytes memory rangeBytes) {
                ImmutableRange[] memory ranges = abi.decode(rangeBytes, (ImmutableRange[]));
                for (uint256 j; j < ranges.length; j++) {
                    uint256 start = ranges[j].start;
                    uint256 len = ranges[j].length;
                    for (uint256 k; k < len && start + k < bytecode.length; k++) {
                        bytecode[start + k] = 0;
                    }
                }
            } catch {
                // Skip ranges we can't parse — defensive against artifact-format changes.
            }
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
