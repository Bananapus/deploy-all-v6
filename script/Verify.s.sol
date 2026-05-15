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
import {JB721Tier} from "@bananapus/721-hook-v6/src/structs/JB721Tier.sol";

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

// ── Periphery (optional on testnets) ──
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
    /// tracked separately so the verifier can assert the LP split hook deployer
    /// carries the canonical V4 PositionManager. Loaded from `VERIFY_LP_SPLIT_HOOK_DEPLOYER`;
    /// `address(0)` when the chain has no canonical PositionManager.
    address public lpSplitHookDeployer;
    /// per-type sucker-deployer slots so each bridge/CCIP endpoint manifest can be
    /// asserted against the canonical chain constants. `address(0)` means the deployer is not
    /// listed for this verify run (testnet / partial stack); production chains fail closed.
    address public opSuckerDeployer;
    address public baseSuckerDeployer;
    address public arbSuckerDeployer;
    /// CCIP deployers are per-remote-route, so a single deployer slot is not enough. CSV format
    /// is `<remoteChainId>:<address>,<remoteChainId>:<address>,...`. See _verifyBridgeAndCcipEndpoints.
    string public ccipSuckerDeployersCsv;

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

    // -- Periphery (optional on testnets) --
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
    // The DEFIFA revnet project is always project 5.
    uint256 private constant _DEFIFA_REV_PROJECT_ID = 5;
    // The ART/Artizen project is always project 6 (Base-only).
    uint256 private constant _ART_PROJECT_ID = 6;
    // The MARKEE project is always project 7.
    uint256 private constant _MARKEE_PROJECT_ID = 7;
    // Distributor vesting rounds must match Deploy.s.sol.
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

        // Read periphery addresses from env (address(0) if intentionally omitted on a testnet).
        projectHandles = JBProjectHandles(vm.envOr({name: "VERIFY_PROJECT_HANDLES", defaultValue: address(0)}));
        distributor721 = JB721Distributor(payable(vm.envOr({name: "VERIFY_721_DISTRIBUTOR", defaultValue: address(0)})));
        tokenDistributor =
            JBTokenDistributor(payable(vm.envOr({name: "VERIFY_TOKEN_DISTRIBUTOR", defaultValue: address(0)})));
        projectPayerDeployer =
            JBProjectPayerDeployer(vm.envOr({name: "VERIFY_PROJECT_PAYER_DEPLOYER", defaultValue: address(0)}));
        checkpointsDeployer =
            JB721CheckpointsDeployer(vm.envOr({name: "VERIFY_CHECKPOINTS_DEPLOYER", defaultValue: address(0)}));
        lpSplitHookDeployer = vm.envOr({name: "VERIFY_LP_SPLIT_HOOK_DEPLOYER", defaultValue: address(0)});

        // per-type sucker-deployer addresses so each endpoint manifest (OP messenger
        // + standard bridge, Arbitrum inbox + gateway router, CCIP router + remote selector +
        // remote chain id) can be checked exactly against the canonical chain manifest.
        opSuckerDeployer = vm.envOr({name: "VERIFY_OP_SUCKER_DEPLOYER", defaultValue: address(0)});
        baseSuckerDeployer = vm.envOr({name: "VERIFY_BASE_SUCKER_DEPLOYER", defaultValue: address(0)});
        arbSuckerDeployer = vm.envOr({name: "VERIFY_ARB_SUCKER_DEPLOYER", defaultValue: address(0)});
        // CCIP deployers are per-remote-route (one address per (local, remote) pair). Take CSV of
        // `<remoteChainId>:<address>` pairs so each route can be checked against its expected
        // remote selector and the local-chain canonical router.
        ccipSuckerDeployersCsv = vm.envOr({name: "VERIFY_CCIP_SUCKER_DEPLOYERS_BY_REMOTE", defaultValue: string("")});

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

        // Conditional existence checks for newer projects.
        if (totalProjects >= _DEFIFA_REV_PROJECT_ID) {
            _checkProjectHasOwner({projectId: _DEFIFA_REV_PROJECT_ID, label: "Project 5 (DEFIFA) exists with owner"});
        }
        if (totalProjects >= _ART_PROJECT_ID) {
            _checkProjectHasOwner({projectId: _ART_PROJECT_ID, label: "Project 6 (ART) exists with owner"});
        }
        if (totalProjects >= _MARKEE_PROJECT_ID) {
            _checkProjectHasOwner({projectId: _MARKEE_PROJECT_ID, label: "Project 7 (MARKEE) exists with owner"});
        }

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
        if (totalProjects >= _DEFIFA_REV_PROJECT_ID) {
            _check({
                condition: projects.getApproved(_DEFIFA_REV_PROJECT_ID) == address(0),
                label: "Project 5 (DEFIFA) has no stale approval",
                critical: true
            });
        }
        if (totalProjects >= _ART_PROJECT_ID) {
            _check({
                condition: projects.getApproved(_ART_PROJECT_ID) == address(0),
                label: "Project 6 (ART) has no stale approval",
                critical: true
            });
        }
        if (totalProjects >= _MARKEE_PROJECT_ID) {
            _check({
                condition: projects.getApproved(_MARKEE_PROJECT_ID) == address(0),
                label: "Project 7 (MARKEE) has no stale approval",
                critical: true
            });
        }

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

        // Hoist `projects.count()` once and swallow reverts: tests inject mocks that don't expose
        // `count()`, and a bare call inside the existence guards would surface as a no-data revert
        // and mask the assertion the test actually targets.
        uint256 totalProjects;
        if (address(projects) != address(0)) {
            try projects.count() returns (uint256 c) {
                totalProjects = c;
            } catch {}
        }

        if (totalProjects >= _DEFIFA_REV_PROJECT_ID) {
            _verifyCanonicalRevnetProject({projectId: _DEFIFA_REV_PROJECT_ID, symbol: "DEFIFA", label: "DEFIFA(5)"});
        }
        if (totalProjects >= _ART_PROJECT_ID) {
            // ART is a fully wired revnet ONLY on Base — off-Base, project 6 is a bare placeholder
            // owned by the canonical operator (no controller/terminals/ruleset). Run the revnet
            // identity check only on Base; on other chains, just authenticate the placeholder.
            if (block.chainid == 8453 || block.chainid == 84_532) {
                _verifyCanonicalRevnetProject({projectId: _ART_PROJECT_ID, symbol: "ART", label: "ART(6)"});
            } else {
                address expectedOperator = vm.envOr({name: "VERIFY_ART_OPS_OPERATOR", defaultValue: address(0)});
                if (expectedOperator != address(0)) {
                    _check({
                        condition: projects.ownerOf(_ART_PROJECT_ID) == expectedOperator,
                        label: "ART(6) off-Base placeholder owner == VERIFY_ART_OPS_OPERATOR",
                        critical: true
                    });
                } else {
                    _skip("ART(6) off-Base placeholder owner (VERIFY_ART_OPS_OPERATOR not set)");
                }
            }
        }
        if (totalProjects >= _MARKEE_PROJECT_ID) {
            _verifyCanonicalRevnetProject({projectId: _MARKEE_PROJECT_ID, symbol: "MARKEE", label: "MARKEE(7)"});
        }

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

            // CPN (Croptop) also gets a 721 hook recorded at project 2. An attacker-deployed CPN
            // hook with wrong PROJECT_ID, wrong store, or wrong symbol must not survive — same
            // identity shape as Banny.
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

                // CPN posting criteria for categories 0-4 must match the canonical values that
                // `Deploy.s.sol::_deployCroptop` registers. The verifier hardcodes the same
                // constants the deploy script uses so an off-chain operator manifest isn't
                // required — same source of truth, no env-var dependency. The default deploy
                // sets an empty `allowedAddresses` list per category; if that ever changes, the
                // deploy script and the canonical-values table here must move together.
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

        // Iterate every canonical revnet present on this chain — baseline 1-4 plus DEFIFA(5),
        // ART(6), and MARKEE(7) where the deploy has reserved their IDs. Without the 5-7
        // extension, those projects' directory wiring (controller, native accounting context,
        // terminal list) would never be authenticated, leaving room for a noncanonical controller
        // or a misconfigured accounting context on the newer projects.
        (uint256[] memory projectIds, string[] memory labels) = _canonicalRevnetProjectIdsAndLabels();

        for (uint256 i; i < projectIds.length; i++) {
            // Read the controller set for this project in the directory.
            IERC165 projectController = directory.controllerOf(projectIds[i]);
            // require the controller pointer to equal the canonical controller, not just
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

            // assert the live accounting context for the native token matches the
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

                // assert the registry's default hook AND every canonical
                // project's resolved hook equal the operator-declared canonical buyback hook.
                // Without this, a deployment can ship with `defaultHook != address(0)` and
                // `hookOf(1) != address(0)` while the actual addresses point at a noncanonical
                // hook (e.g. a forked implementation, or a default set after canonical projects
                // 2-4 existed so they fall through `defaultHookProjectIdThreshold` and resolve
                // to no hook at all).
                _verifyBuybackHookCanonicalManifest();
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

    /// assert canonical buyback hook identity across the registry. On
    /// production chains `VERIFY_BUYBACK_HOOK` is mandatory (fail-closed); on non-production
    /// chains a missing env var skips with a logged note. Checks both `defaultHook()` and the
    /// per-project resolved `hookOf(projectId)` for canonical projects 1-4. The latter
    /// catches the case where a default hook is set AFTER projects 2-4 already existed
    /// (`defaultHookProjectIdThreshold` excludes them and they fall through to no hook).
    function _verifyBuybackHookCanonicalManifest() internal {
        address expectedHook = vm.envOr({name: "VERIFY_BUYBACK_HOOK", defaultValue: address(0)});
        if (expectedHook == address(0)) {
            bool isProductionChain =
                (block.chainid == 1 || block.chainid == 10 || block.chainid == 8453 || block.chainid == 42_161);
            if (isProductionChain) {
                _check({
                    condition: false,
                    label: "VERIFY_BUYBACK_HOOK MUST be set on production for canonical buyback identity",
                    critical: true
                });
            } else {
                _skip("Canonical buyback hook identity (VERIFY_BUYBACK_HOOK not set on non-production chain)");
            }
            return;
        }

        _check({
            condition: address(buybackRegistry.defaultHook()) == expectedHook,
            label: "BuybackRegistry.defaultHook == canonical buyback hook",
            critical: true
        });

        uint256[4] memory pids = [_FEE_PROJECT_ID, _CPN_PROJECT_ID, _REV_PROJECT_ID, _BAN_PROJECT_ID];
        string[4] memory names = ["NANA(1)", "CPN(2)", "REV(3)", "BAN(4)"];
        for (uint256 i; i < 4; i++) {
            _check({
                condition: address(buybackRegistry.hookOf(pids[i])) == expectedHook,
                label: string.concat(names[i], " resolved buyback hookOf == canonical"),
                critical: true
            });
        }

        // Conditional buyback checks for newer projects (5, 6, 7).
        uint256 totalProjects = projects.count();
        uint256[3] memory extraPids = [_DEFIFA_REV_PROJECT_ID, _ART_PROJECT_ID, _MARKEE_PROJECT_ID];
        string[3] memory extraNames = ["DEFIFA(5)", "ART(6)", "MARKEE(7)"];
        for (uint256 i; i < extraPids.length; i++) {
            if (totalProjects < extraPids[i]) continue;
            // ART is a wired revnet only on Base. Off-Base, project 6 is a bare placeholder with no
            // buyback wiring — skip the buyback hook check there.
            if (extraPids[i] == _ART_PROJECT_ID && block.chainid != 8453 && block.chainid != 84_532) continue;
            _check({
                condition: address(buybackRegistry.hookOf(extraPids[i])) == expectedHook,
                label: string.concat(extraNames[i], " resolved buyback hookOf == canonical"),
                critical: true
            });
        }
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
                condition: defifaDeployer.DEFIFA_PROJECT_ID() == _DEFIFA_REV_PROJECT_ID,
                label: "Defifa uses DEFIFA_REV(5) as fee project",
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
                        == address(tokens.tokenOf(_DEFIFA_REV_PROJECT_ID)),
                    label: "Defifa hook code origin uses DEFIFA_REV token",
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

        // Oracle exactness: assert not just the aggregator address but also THRESHOLD(),
        // SEQUENCER_FEED() (per L2), and GRACE_PERIOD_TIME() (per L2) against the canonical
        // Deploy.s.sol values. Without these the verifier accepts any sequencer-aware
        // wrapper whose getters happen to return plausible values.
        _verifyEthUsdOracleExactness();
        _verifyUsdcUsdOracleExactness({usdc: usdc});

        // Log a blank line for readability.
        console.log("");
    }

    /// @notice Assert the deployed ETH/USD feed wraps the canonical Chainlink aggregator with the
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

    /// @notice Same shape as `_verifyEthUsdOracleExactness` for the USDC/USD feed. Per-chain USDC
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
                    // Each listed deployer must actually be allowed in the registry.
                    bool allowed = suckerRegistry.suckerDeployerIsAllowed(deployer);
                    _check({
                        condition: allowed,
                        label: string.concat("Sucker deployer ", vm.toString(deployer), " is allowed"),
                        critical: true
                    });
                    // Each listed deployer must be a real deployer with canonical wiring.
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

        // JBSuckerRegistry has no enumeration of its allowed-deployer set, so the
        // on-chain verifier cannot prove the absence of unexpected allowed deployers. Operators
        // must reconcile against the `SuckerDeployerSetAllowed` event log off-chain. The
        // VERIFY_SUCKER_DEPLOYER_COUNT check above provides a sanity gate; the event-log
        // reconciliation is documented in DEPLOY.md.
        console.log("  [INFO] no on-chain enumeration of sucker-deployer allowlist - reconcile off-chain");

        console.log("");
    }

    /// @notice For each env-listed sucker deployer, assert it is a real, canonically-wired deployer.
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
        // exact-identity check is part of the address-dump emission work — the singleton appears
        // in the address dump and gets verified separately via the artifact-identity sweep.
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
            // Every canonical revnet present on this chain — see `_canonicalRevnetProjectIdsAndLabels`
            // for the 1-4 baseline plus DEFIFA(5) / ART(6) / MARKEE(7) extension. The router-terminal
            // registry is wired into every canonical revnet's terminal list, so every project
            // (including 5-7) needs its registry registration AND `terminalOf` resolution proved.
            (uint256[] memory projectIds, string[] memory labels) = _canonicalRevnetProjectIdsAndLabels();

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

                // Require the registry to resolve each canonical project to the canonical router
                // terminal. Without this, the registry could route project N through a forked
                // router (different fee handling, different beneficiary resolution) while still
                // passing the "registry in terminal list" check.
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

                // Exact terminal-list membership. The canonical deployment installs exactly
                // two terminals: JBMultiTerminal + JBRouterTerminalRegistry. Anything else in the
                // list is either a stale leftover or a malicious injection. The two-entry check
                // refuses extras so neither shape can survive.
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
    //  Category 11: Periphery Extensions
    // ════════════════════════════════════════════════════════════════════

    /// @dev Validates the late-phase convenience contracts that Deploy.s.sol always deploys.
    function _verifyPeripheryExtensions() internal {
        console.log("--- Category 11: Periphery Extensions ---");

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

        // Assert the JBERC20 implementation bytecode matches the published artifact.
        _requireArtifactIdentity({artifactName: "JBERC20", deployed: address(tokenImpl), label: "JBERC20 impl"});

        // Run the implementation-identity sweep for every contract group with a published artifact.
        // Skips when an artifact file
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
            // graph touches. Artifact bytecode parity masks immutables before bytecode comparison, so it cannot
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
        // identity-checked separately in the hook & registry singletons block.

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
    ///   2. Per-revnet operator grants made by REVDeployer when each revnet is launched.
    ///      Verified for projects {2 CPN, 3 REV, 4 BAN} when their operator env var is set.
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

        // Per-revnet operator grants. The operator is configured at revnet launch and
        // exposed via VERIFY_OPERATOR_{2,3,4} env vars. When set, the verifier asserts the
        // operator has the 9 canonical operator permissions on its revnet.
        _verifyOperatorGrantsFor({envVar: "VERIFY_OPERATOR_2", projectId: _CPN_PROJECT_ID, label: "Project 2 (CPN)"});
        _verifyOperatorGrantsFor({envVar: "VERIFY_OPERATOR_3", projectId: _REV_PROJECT_ID, label: "Project 3 (REV)"});
        _verifyOperatorGrantsFor({envVar: "VERIFY_OPERATOR_4", projectId: _BAN_PROJECT_ID, label: "Project 4 (BAN)"});

        // Known gap (logged, not failed): exhaustive "no extra grants" verification requires either
        // an enumerable JBPermissions or off-chain event-log reconciliation against
        // `OperatorPermissionsSet`. The on-chain verifier proves positive grants only.
        console.log("  [INFO] No on-chain enumeration - see DEPLOY.md for off-chain grant reconciliation");
    }

    /// Asserts the 9 canonical operator permissions on `projectId` for the operator named by
    /// `envVar`. On production chains the env var is mandatory (fail-closed); on testnets and
    /// partial-stack chains the check skips when the env var is not set.
    function _verifyOperatorGrantsFor(string memory envVar, uint256 projectId, string memory label) internal {
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
                    label: string.concat(envVar, " MUST be set on production for ", label, " operator grants"),
                    critical: true
                });
                return;
            }
            console.log(string.concat("  [SKIP] ", envVar, " unset - operator grants for ", label, " skipped"));
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
                    "Permissions: ", label, " operator has permission ", vm.toString(uint256(expectedPermissions[i]))
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

        // Require exact expected config hashes on every canonical project on production chains.
        // Per-project env vars VERIFY_CONFIG_HASH_{1..4} take precedence; the legacy
        // VERIFY_CONFIG_HASHES CSV is still accepted for backwards compatibility. On production
        // chains, missing or zero expected hashes are critical.
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

        // Conditional config hash checks for newer projects (5, 6, 7).
        {
            uint256 totalProjects = projects.count();
            uint256[3] memory extraPids = [_DEFIFA_REV_PROJECT_ID, _ART_PROJECT_ID, _MARKEE_PROJECT_ID];
            string[3] memory extraNames = ["DEFIFA(5)", "ART(6)", "MARKEE(7)"];
            string[3] memory extraEnvVars = ["VERIFY_CONFIG_HASH_5", "VERIFY_CONFIG_HASH_6", "VERIFY_CONFIG_HASH_7"];
            for (uint256 i; i < extraPids.length; i++) {
                if (totalProjects < extraPids[i]) continue;
                // ART is a wired revnet only on Base. Off-Base project 6 is a bare placeholder with
                // no revnet config hash — skip the config hash check there.
                if (extraPids[i] == _ART_PROJECT_ID && block.chainid != 8453 && block.chainid != 84_532) continue;

                bytes32 actual = revDeployer.hashedEncodedConfigurationOf(extraPids[i]);
                _check({
                    condition: actual != bytes32(0),
                    label: string.concat(extraNames[i], " has non-zero config hash"),
                    critical: true
                });

                string memory hashStr = vm.envOr({name: extraEnvVars[i], defaultValue: string("")});
                if (bytes(hashStr).length > 0) {
                    _check({
                        condition: actual == vm.parseBytes32(hashStr),
                        label: string.concat(extraNames[i], " config hash == expected"),
                        critical: true
                    });
                } else if (isProductionChain) {
                    _check({
                        condition: false,
                        label: string.concat(
                            extraNames[i], " expected config hash MUST be set on production via ", extraEnvVars[i]
                        ),
                        critical: true
                    });
                } else {
                    _skip(
                        string.concat(extraNames[i], " expected config hash not provided (", extraEnvVars[i], " unset)")
                    );
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

                // assert the resolver's owner / trusted-forwarder /
                // metadata / drop-tier manifest match the canonical Banny launch. Without
                // these, a deployment can ship with a code-bearing resolver and nonempty
                // contractURI while resolver custody, metadata, and tier count drift from
                // `_deployBanny` + `_registerBannyDrop*` + `_finalizeBannyOwnership`.
                if (resolver != address(0)) {
                    _verifyBannyResolverManifest({resolver: resolver, bannyHook: address(bannyHook)});
                }
            }
        }

        console.log("");
    }

    /// per-field equality on the canonical Banny resolver and tier count.
    /// Each env var defaults to a no-op skip on non-production chains; production chains fail
    /// closed when the manifest envs are unset.
    /// @dev Reads every operator-supplied expectation via `_loadBannyExpectations` (overridable in
    /// test harnesses) so production-style env reads aren't interleaved through the verification
    /// flow. Forge runs sibling test contracts in parallel and `vm.setEnv` is process-wide; mixing
    /// env reads with verifier work would race against any sibling test that touches the same
    /// `VERIFY_BANNY_*` keys. Loading once at the top, with the loader virtualised, means tests
    /// can supply stable expectations from harness storage and skip env entirely.
    function _verifyBannyResolverManifest(address resolver, address bannyHook) internal {
        bool isProductionChain =
            (block.chainid == 1 || block.chainid == 10 || block.chainid == 8453 || block.chainid == 42_161);

        BannyExpectations memory expected = _loadBannyExpectations();

        // 1. Resolver owner — final handoff target. Operator declares `_BAN_OPS_OPERATOR`.
        _checkResolverField({
            ok: _enforceBannyExpectationOnProduction(
                isProductionChain, expected.banOpsOperatorSet, "VERIFY_BAN_OPS_OPERATOR"
            ),
            expectedAddress: expected.banOpsOperator,
            actualAddress: _staticAddress(resolver, "owner()"),
            label: "Banny resolver owner == VERIFY_BAN_OPS_OPERATOR"
        });

        // 2. Resolver trusted forwarder — must match the canonical forwarder (already used by
        // the broader O sweep). Skip if no expected forwarder is configured.
        if (expectedTrustedForwarder != address(0)) {
            _check({
                condition: _staticAddress(resolver, "trustedForwarder()") == expectedTrustedForwarder,
                label: "Banny resolver trustedForwarder == expected",
                critical: true
            });
        }

        // 3. Resolver SVG metadata triple — exact-string equality against operator manifest.
        _checkResolverStringField({
            ok: _enforceBannyExpectationOnProduction(
                isProductionChain, expected.svgDescriptionSet, "VERIFY_BANNY_SVG_DESCRIPTION"
            ),
            expectedRaw: expected.svgDescription,
            actualRaw: _staticString(resolver, "svgDescription()"),
            label: "Banny resolver svgDescription == expected"
        });
        _checkResolverStringField({
            ok: _enforceBannyExpectationOnProduction(
                isProductionChain, expected.svgExternalUrlSet, "VERIFY_BANNY_SVG_EXTERNAL_URL"
            ),
            expectedRaw: expected.svgExternalUrl,
            actualRaw: _staticString(resolver, "svgExternalUrl()"),
            label: "Banny resolver svgExternalUrl == expected"
        });
        _checkResolverStringField({
            ok: _enforceBannyExpectationOnProduction(
                isProductionChain, expected.svgBaseUriSet, "VERIFY_BANNY_SVG_BASE_URI"
            ),
            expectedRaw: expected.svgBaseUri,
            actualRaw: _staticString(resolver, "svgBaseUri()"),
            label: "Banny resolver svgBaseUri == expected"
        });

        // 4. Hook-store tier count — the canonical deployment ends with 4 baseline body tiers
        // plus 64 Drop 1/Drop 2 tiers = 68 total. Drop missing/incomplete = wrong count.
        if (expected.tierCountSet) {
            _check({
                condition: hookStore.maxTierIdOf(bannyHook) == expected.tierCount,
                label: "Banny hook maxTierIdOf == VERIFY_BANNY_TIER_COUNT",
                critical: true
            });
        } else if (isProductionChain) {
            _check({
                condition: false,
                label: "VERIFY_BANNY_TIER_COUNT MUST be set on production for Banny tier manifest",
                critical: true
            });
        } else {
            _skip("Banny tier count (VERIFY_BANNY_TIER_COUNT not set on non-production chain)");
        }

        // 5. Per-tier manifest commitment — the prior checks pin shell metadata (owner, base URI,
        // tier count) but say nothing about each tier's price / supply / category / reserve, the
        // resolver's per-UPC SVG hash, or its product-name commitment. A wrong drop registration
        // (off-by-one tier inputs, swapped SVG hashes, missing product names) still satisfied every
        // earlier check. Hash the canonical per-tier fields off-chain, supply via
        // `VERIFY_BANNY_TIER_MANIFEST_HASH`, and verify on-chain by accumulating the same digest
        // over `tierOf` + `svgHashOf` + `productNameOf` for tiers `1..expectedTierCount`.
        if (expected.tierCountSet && expected.tierCount > 0) {
            _verifyBannyTierManifestHash({
                bannyHook: bannyHook,
                resolver: resolver,
                tierCount: expected.tierCount,
                tierManifestHash: expected.tierManifestHash,
                tierManifestHashSet: expected.tierManifestHashSet,
                isProductionChain: isProductionChain
            });
        }
    }

    /// @notice Operator-supplied Banny manifest expectations, captured once before the verifier
    /// runs so the per-field assertions don't race against a sibling test contract's `vm.setEnv`.
    /// Tests inherit a harness that overrides `_loadBannyExpectations` to supply canned values
    /// directly from storage; production runs receive the defaults loaded from env vars.
    struct BannyExpectations {
        bool banOpsOperatorSet;
        address banOpsOperator;
        bool svgDescriptionSet;
        string svgDescription;
        bool svgExternalUrlSet;
        string svgExternalUrl;
        bool svgBaseUriSet;
        string svgBaseUri;
        bool tierCountSet;
        uint256 tierCount;
        bool tierManifestHashSet;
        bytes32 tierManifestHash;
    }

    /// @notice Default loader for `BannyExpectations`. Reads every `VERIFY_BANNY_*` /
    /// `VERIFY_BAN_OPS_OPERATOR` env var once and packs them into the struct so downstream
    /// verification work is decoupled from env-var timing.
    function _loadBannyExpectations() internal virtual returns (BannyExpectations memory e) {
        string memory raw = vm.envOr({name: "VERIFY_BAN_OPS_OPERATOR", defaultValue: string("")});
        if (bytes(raw).length > 0) {
            e.banOpsOperatorSet = true;
            e.banOpsOperator = vm.parseAddress(raw);
        }
        e.svgDescription = vm.envOr({name: "VERIFY_BANNY_SVG_DESCRIPTION", defaultValue: string("")});
        e.svgDescriptionSet = bytes(e.svgDescription).length > 0;
        e.svgExternalUrl = vm.envOr({name: "VERIFY_BANNY_SVG_EXTERNAL_URL", defaultValue: string("")});
        e.svgExternalUrlSet = bytes(e.svgExternalUrl).length > 0;
        e.svgBaseUri = vm.envOr({name: "VERIFY_BANNY_SVG_BASE_URI", defaultValue: string("")});
        e.svgBaseUriSet = bytes(e.svgBaseUri).length > 0;
        raw = vm.envOr({name: "VERIFY_BANNY_TIER_COUNT", defaultValue: string("")});
        if (bytes(raw).length > 0) {
            e.tierCountSet = true;
            e.tierCount = vm.parseUint(raw);
        }
        e.tierManifestHash = vm.envOr({name: "VERIFY_BANNY_TIER_MANIFEST_HASH", defaultValue: bytes32(0)});
        e.tierManifestHashSet = e.tierManifestHash != bytes32(0);
    }

    /// @notice Replacement for the previous `_expectBannyEnvOnProduction` helper. Returns `true`
    /// when the per-field assertion should proceed (operator supplied a value). On production with
    /// no value supplied, fails closed with a label tied to the env var the operator forgot.
    function _enforceBannyExpectationOnProduction(
        bool isProductionChain,
        bool fieldSet,
        string memory envName
    )
        internal
        returns (bool)
    {
        if (fieldSet) return true;
        if (isProductionChain) {
            _check({
                condition: false,
                label: string.concat(envName, " MUST be set on production for Banny resolver identity"),
                critical: true
            });
        } else {
            _skip(string.concat(envName, " (not set on non-production chain)"));
        }
        return false;
    }

    /// @notice Walk `1..tierCount` on the canonical Banny hook + resolver and accumulate a
    /// keccak256 digest of every committed tier field. Compare against the operator-supplied
    /// `tierManifestHash` (captured upstream by `_loadBannyExpectations`). Fails closed on
    /// production when the operator didn't supply a hash.
    /// @dev Digest shape per tier (matches the off-chain manifest generator):
    ///   `keccak256(abi.encode(running, tierId, price, initialSupply, category, reserveFrequency,
    ///                          encodedIPFSUri, svgHash, keccak256(productName)))`
    /// Drop a single field or reorder one tier and the digest diverges; that's the whole point.
    function _verifyBannyTierManifestHash(
        address bannyHook,
        address resolver,
        uint256 tierCount,
        bytes32 tierManifestHash,
        bool tierManifestHashSet,
        bool isProductionChain
    )
        internal
    {
        if (!tierManifestHashSet) {
            if (isProductionChain) {
                _check({
                    condition: false,
                    label: "VERIFY_BANNY_TIER_MANIFEST_HASH MUST be set on production for per-tier identity",
                    critical: true
                });
            } else {
                _skip("Banny per-tier manifest hash (VERIFY_BANNY_TIER_MANIFEST_HASH not set on non-production chain)");
            }
            return;
        }

        bytes32 digest;
        for (uint256 id = 1; id <= tierCount; id++) {
            JB721Tier memory tier = hookStore.tierOf({hook: bannyHook, id: id, includeResolvedUri: false});
            bytes32 svgHash = _readResolverSvgHash({resolver: resolver, upc: id});
            bytes32 nameHash = keccak256(bytes(_readResolverProductName({resolver: resolver, upc: id})));
            digest = keccak256(
                abi.encode(
                    digest,
                    id,
                    uint256(tier.price),
                    uint256(tier.initialSupply),
                    uint256(tier.category),
                    uint256(tier.reserveFrequency),
                    tier.encodedIPFSUri,
                    svgHash,
                    nameHash
                )
            );
        }

        _check({
            condition: digest == tierManifestHash,
            label: "Banny per-tier manifest hash == VERIFY_BANNY_TIER_MANIFEST_HASH",
            critical: true
        });
    }

    /// @notice Read `svgHashOf(upc)` from the resolver via low-level staticcall. The accessor is
    /// a public storage mapping, so a real Banny resolver always responds; an out-of-shape resolver
    /// fails closed.
    function _readResolverSvgHash(address resolver, uint256 upc) internal view returns (bytes32) {
        (bool ok, bytes memory data) = resolver.staticcall(abi.encodeWithSignature("svgHashOf(uint256)", upc));
        if (!ok || data.length < 32) return bytes32(0);
        return abi.decode(data, (bytes32));
    }

    /// @notice Read `productNameOf(upc)` from the resolver via low-level staticcall. The accessor
    /// was added in banny-retail-v6 0.0.32; older deployments revert and the empty-string
    /// fallback surfaces as a digest mismatch via the surrounding `_check`.
    function _readResolverProductName(address resolver, uint256 upc) internal view returns (string memory) {
        (bool ok, bytes memory data) = resolver.staticcall(abi.encodeWithSignature("productNameOf(uint256)", upc));
        if (!ok || data.length == 0) return "";
        return abi.decode(data, (string));
    }

    function _checkResolverField(
        bool ok,
        address expectedAddress,
        address actualAddress,
        string memory label
    )
        internal
    {
        if (!ok) return;
        _check({condition: actualAddress == expectedAddress, label: label, critical: true});
    }

    function _checkResolverStringField(
        bool ok,
        string memory expectedRaw,
        string memory actualRaw,
        string memory label
    )
        internal
    {
        if (!ok) return;
        _check({condition: keccak256(bytes(actualRaw)) == keccak256(bytes(expectedRaw)), label: label, critical: true});
    }

    /// Helper: staticcall a zero-arg getter that returns an address. Returns address(0) on
    /// revert or wrong return-data length. Used by the Banny resolver manifest checks.
    function _staticAddress(address target, string memory signature) internal view returns (address) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature(signature));
        if (!ok || data.length < 32) return address(0);
        return abi.decode(data, (address));
    }

    /// Helper: staticcall a zero-arg getter that returns a string. Returns empty string on
    /// revert or empty return data. Used by the Banny resolver manifest checks.
    function _staticString(address target, string memory signature) internal view returns (string memory) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature(signature));
        if (!ok || data.length == 0) return "";
        return abi.decode(data, (string));
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 19: Cross-Chain Sucker Manifest
    // ════════════════════════════════════════════════════════════════════

    function _verifySuckerManifest() internal {
        console.log("--- Category 19: Cross-Chain Sucker Manifest ---");

        // Load optional per-project sucker pair counts from env.
        // Format: VERIFY_SUCKER_PAIRS_1=<count>,VERIFY_SUCKER_PAIRS_2=<count>, etc.
        // Covers the full canonical revnet set (1-7) so DEFIFA / ART / MARKEE sucker manifests can
        // also be authenticated when their `VERIFY_SUCKER_PAIRS_*` env var is supplied.
        (uint256[] memory pids, string[] memory names) = _canonicalRevnetProjectIdsAndLabels();
        bool anySuckerChecks = false;
        bool isProductionChainNow =
            (block.chainid == 1 || block.chainid == 10 || block.chainid == 8453 || block.chainid == 42_161);

        for (uint256 i; i < pids.length; i++) {
            string memory envKey = string.concat("VERIFY_SUCKER_PAIRS_", vm.toString(pids[i]));
            string memory expectedCountStr = vm.envOr(envKey, string(""));
            if (bytes(expectedCountStr).length == 0) {
                // Partial-missing-env gap: on production, every canonical project must declare its
                // pair count explicitly (use `"0"` for zero-sucker projects). Without this gate, a
                // deployment can ship with only some VERIFY_SUCKER_PAIRS_* set and silently skip
                // per-pair manifest verification for the unset projects.
                if (isProductionChainNow) {
                    _check({
                        condition: false,
                        label: string.concat(
                            envKey, " MUST be set on production for ", names[i], " (use \"0\" for no suckers)"
                        ),
                        critical: true
                    });
                }
                continue;
            }
            anySuckerChecks = true;

            uint256 expectedCount = vm.parseUint(expectedCountStr);
            JBSuckersPair[] memory pairs = suckerRegistry.suckerPairsOf(pids[i]);
            _check({
                condition: pairs.length == expectedCount,
                label: string.concat(names[i], " sucker pair count matches expected"),
                critical: true
            });

            // Per-pair runtime sanity — each pair's local sucker must have code, must be
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

                // native-token bridge mapping must be enabled. A pair where the
                // native-token mapping is intentionally disabled (or emergency-hatch-stuck) is
                // structurally indistinguishable from a properly-deployed pair on the count +
                // remote checks, but the native cross-chain transfer path is dead for end users.
                // Reject the disabled mapping so a launch cannot ship a registered-but-unusable
                // sucker pair.
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

                // per-pair exact-manifest equality. Env var
                // `VERIFY_SUCKER_PAIR_<projectId>_<j>` carries
                // `<peer>:<remoteChainId>:<remoteNativeToken>:<emergencyHatch>` so each pair's
                // remote peer (bytes32), remote chain id (decimal uint), native-token addr
                // (bytes32), and emergency-hatch flag (0/1) can be checked exactly. Without this
                // a deployment can ship the right pair count + nonzero/enabled liveness
                // predicates while the actual peers / chain ids / native-token mappings drift
                // from the canonical manifest — which makes `fromRemote` reject legitimate
                // messages or strand bridged value.
                _checkSuckerPairAgainstManifest({
                    pair: pairs[j], local: local, projectId: pids[i], pairIndex: j, pairLabel: pairLabel
                });
            }
        }

        // Projects 5-7 are folded into the main loop above via
        // `_canonicalRevnetProjectIdsAndLabels` — no duplicate iteration here.

        if (!anySuckerChecks) {
            // production chains must declare a manifest for every canonical project
            // (use "0" for projects with no suckers). Silent skip on production let a deployment
            // ship without ever exercising the per-pair manifest gate.
            bool isProductionChain =
                (block.chainid == 1 || block.chainid == 10 || block.chainid == 8453 || block.chainid == 42_161);
            if (isProductionChain) {
                _check({
                    condition: false,
                    label: "VERIFY_SUCKER_PAIRS_{1..7} MUST be set on production (use \"0\" for projects with no suckers)",
                    critical: true
                });
            } else {
                _skip("Sucker manifest checks (VERIFY_SUCKER_PAIRS_* not set)");
            }
        }

        console.log("");
    }

    /// assert per-pair exact-manifest equality against the env var
    /// `VERIFY_SUCKER_PAIR_<projectId>_<idx>=<peer>:<remoteChainId>:<remoteNativeToken>:<emergencyHatch>`.
    /// On production chains the env var is mandatory (fail-closed) so a launch cannot silently
    /// drop the exact-manifest gate; on non-production chains a missing env var skips with a log.
    /// @param pair The pair returned by `suckerRegistry.suckerPairsOf(projectId)[pairIndex]`.
    /// @param local The local sucker address inside the pair.
    /// @param projectId The canonical project ID this pair belongs to.
    /// @param pairIndex The pair's index (matches the env var suffix).
    /// @param pairLabel Pre-built label like "NANA(1) sucker pair 0" used in check labels.
    function _checkSuckerPairAgainstManifest(
        JBSuckersPair memory pair,
        address local,
        uint256 projectId,
        uint256 pairIndex,
        string memory pairLabel
    )
        internal
    {
        string memory envKey = string.concat("VERIFY_SUCKER_PAIR_", vm.toString(projectId), "_", vm.toString(pairIndex));
        string memory manifest = vm.envOr({name: envKey, defaultValue: string("")});

        if (bytes(manifest).length == 0) {
            bool isProductionChain =
                (block.chainid == 1 || block.chainid == 10 || block.chainid == 8453 || block.chainid == 42_161);
            if (isProductionChain) {
                _check({
                    condition: false,
                    label: string.concat(envKey, " MUST be set on production for exact pair manifest"),
                    critical: true
                });
            } else {
                _skip(string.concat(envKey, " unset - exact pair manifest skipped on non-production chain"));
            }
            return;
        }

        // Format: `<peer>:<remoteChainId>:<remoteNativeToken>:<emergencyHatch>`.
        string[] memory parts = vm.split(manifest, ":");
        if (parts.length != 4) {
            _check({
                condition: false,
                label: string.concat(envKey, " manifest must have 4 colon-separated fields"),
                critical: true
            });
            return;
        }
        bytes32 expectedPeer = vm.parseBytes32(parts[0]);
        uint256 expectedRemoteChainId = vm.parseUint(parts[1]);
        bytes32 expectedRemoteNativeToken = vm.parseBytes32(parts[2]);
        bool expectedEmergencyHatch = vm.parseUint(parts[3]) != 0;

        // 1. Pair's `remoteChainId` (from the registry) matches expected.
        _check({
            condition: pair.remoteChainId == expectedRemoteChainId,
            label: string.concat(pairLabel, " registry-side remoteChainId == expected"),
            critical: true
        });

        // 2. Local sucker's `peer()` matches expected remote peer bytes32.
        (bool okPeer, bytes memory peerData) = local.staticcall(abi.encodeWithSignature("peer()"));
        _check({
            condition: okPeer && peerData.length >= 32 && abi.decode(peerData, (bytes32)) == expectedPeer,
            label: string.concat(pairLabel, " peer() == expected"),
            critical: true
        });

        // 3. Local sucker's `peerChainId()` matches expected (over and above the prior
        //    non-zero predicate which already fired).
        (bool okPcid, bytes memory pcidData) = local.staticcall(abi.encodeWithSignature("peerChainId()"));
        _check({
            condition: okPcid && pcidData.length >= 32 && abi.decode(pcidData, (uint256)) == expectedRemoteChainId,
            label: string.concat(pairLabel, " peerChainId() == expected remote chain id"),
            critical: true
        });

        // 4. Native-token mapping: addr + emergencyHatch. The first 32 bytes hold `enabled`
        //    (already asserted above), the next hold `emergencyHatch`, then `minGas`, then
        //    `addr` — total 4 word slots in the ABI-encoded JBRemoteToken layout.
        (bool okMap, bytes memory mapData) =
            local.staticcall(abi.encodeWithSignature("remoteTokenFor(address)", JBConstants.NATIVE_TOKEN));
        if (okMap && mapData.length >= 128) {
            bool actualEmergencyHatch;
            bytes32 actualAddr;
            assembly {
                actualEmergencyHatch := iszero(iszero(mload(add(mapData, 0x40))))
                actualAddr := mload(add(mapData, 0x80))
            }
            _check({
                condition: actualAddr == expectedRemoteNativeToken,
                label: string.concat(pairLabel, " remoteTokenFor(NATIVE_TOKEN).addr == expected"),
                critical: true
            });
            _check({
                condition: actualEmergencyHatch == expectedEmergencyHatch,
                label: string.concat(pairLabel, " remoteTokenFor(NATIVE_TOKEN).emergencyHatch == expected"),
                critical: true
            });
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  Category 20: External Address Provenance
    // ════════════════════════════════════════════════════════════════════

    function _verifyExternalAddresses() internal {
        console.log("--- Category 20: External Address Provenance ---");

        // Pin the immutable PERMIT2 wiring on every deployed contract that exposes it to the
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
            _skip("Permit2 exact-address check skipped (no manifest for this chain)");
        }

        // Pin WRAPPED_NATIVE_TOKEN on the router terminal to the canonical WETH for this chain.
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
                _skip("WETH exact-address check skipped (no manifest for this chain)");
            }
        }

        // OmnichainDeployer DIRECTORY (existing check — kept).
        _check({
            condition: address(omnichainDeployer.DIRECTORY()) == address(directory),
            label: "OmnichainDeployer.DIRECTORY == directory",
            critical: true
        });

        // Defifa typeface. DefifaTokenUriResolver.TYPEFACE() must equal the per-chain
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

        // Uniswap stack provenance — V3 factory, V4 PoolManager, V4 PositionManager.
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

        // V4 PositionManager identity on the LP split hook deployer. Every clone
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

            // same deployer also stores POOL_MANAGER and ORACLE_HOOK via
            // `setChainSpecificConstants` after deploy. Artifact bytecode parity doesn't bind these (they're
            // public storage, not immutable; the deploy explicitly chose storage so constructor
            // bytes stay chain-identical for CREATE2 address parity). Read-and-equal-check is
            // the only authentication path.
            address expectedLpPoolManager = _expectedV4PoolManager();
            if (expectedLpPoolManager != address(0)) {
                (bool okPm, bytes memory pmData) =
                    lpSplitHookDeployer.staticcall(abi.encodeWithSignature("POOL_MANAGER()"));
                _check({
                    condition: okPm && pmData.length >= 32 && abi.decode(pmData, (address)) == expectedLpPoolManager,
                    label: "JBUniswapV4LPSplitHookDeployer.POOL_MANAGER == canonical V4 PoolManager",
                    critical: true
                });
            }
            address expectedOracleHook = _uniswapV4Hook();
            if (expectedOracleHook != address(0)) {
                (bool okOh, bytes memory ohData) =
                    lpSplitHookDeployer.staticcall(abi.encodeWithSignature("ORACLE_HOOK()"));
                _check({
                    condition: okOh && ohData.length >= 32 && abi.decode(ohData, (address)) == expectedOracleHook,
                    label: "JBUniswapV4LPSplitHookDeployer.ORACLE_HOOK == canonical JBUniswapV4Hook",
                    critical: true
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

        // per-deployer bridge / CCIP endpoint manifests. Each branch fires only
        // when the operator supplied the deployer address; production chains fail closed in
        // the helper via per-type production-required guards.
        _verifyBridgeAndCcipEndpoints();

        console.log("");
    }

    /// assert each bridge/CCIP sucker deployer carries its canonical chain
    /// endpoints. The deploy script wires per-route immutables (opMessenger, opBridge,
    /// arbInbox, arbGatewayRouter, ccipRouter, ccipRemoteChainSelector, ccipRemoteChainId)
    /// that survive artifact bytecode parity's immutable-mask. A wrong endpoint here lets a deployment ship
    /// with infrastructure pointed at a non-canonical bridge / CCIP router while every other
    /// allowlist/wiring check still passes.
    function _verifyBridgeAndCcipEndpoints() internal {
        bool isProductionChain =
            (block.chainid == 1 || block.chainid == 10 || block.chainid == 8453 || block.chainid == 42_161);

        // --- Optimism bridge ---
        address expectedOpMessenger = _expectedOpBridgeMessenger();
        address expectedOpBridge = _expectedOpStandardBridge();
        bool chainHasOp =
            (block.chainid == 1 || block.chainid == 11_155_111 || block.chainid == 10 || block.chainid == 11_155_420);
        if (chainHasOp) {
            if (opSuckerDeployer != address(0)) {
                _checkOpDeployerEndpoints({
                    deployer: opSuckerDeployer,
                    expectedMessenger: expectedOpMessenger,
                    expectedBridge: expectedOpBridge,
                    label: "Optimism"
                });
            } else if (isProductionChain) {
                _check({
                    condition: false,
                    label: "VERIFY_OP_SUCKER_DEPLOYER MUST be set on production for Optimism endpoint identity",
                    critical: true
                });
            } else {
                _skip("Optimism endpoint identity (VERIFY_OP_SUCKER_DEPLOYER not set on non-production chain)");
            }
        }

        // --- Base bridge ---
        address expectedBaseMessenger = _expectedBaseBridgeMessenger();
        address expectedBaseBridge = _expectedBaseStandardBridge();
        bool chainHasBase =
            (block.chainid == 1 || block.chainid == 11_155_111 || block.chainid == 8453 || block.chainid == 84_532);
        if (chainHasBase) {
            if (baseSuckerDeployer != address(0)) {
                _checkOpDeployerEndpoints({
                    deployer: baseSuckerDeployer,
                    expectedMessenger: expectedBaseMessenger,
                    expectedBridge: expectedBaseBridge,
                    label: "Base"
                });
            } else if (isProductionChain) {
                _check({
                    condition: false,
                    label: "VERIFY_BASE_SUCKER_DEPLOYER MUST be set on production for Base endpoint identity",
                    critical: true
                });
            } else {
                _skip("Base endpoint identity (VERIFY_BASE_SUCKER_DEPLOYER not set on non-production chain)");
            }
        }

        // --- Arbitrum bridge ---
        address expectedArbInbox = _expectedArbInbox();
        address expectedArbGatewayRouter = _expectedArbGatewayRouter();
        bool chainHasArb =
            (block.chainid == 1 || block.chainid == 11_155_111 || block.chainid == 42_161 || block.chainid == 421_614);
        if (chainHasArb) {
            if (arbSuckerDeployer != address(0)) {
                _checkArbDeployerEndpoints({
                    deployer: arbSuckerDeployer,
                    expectedInbox: expectedArbInbox,
                    expectedGatewayRouter: expectedArbGatewayRouter
                });
            } else if (isProductionChain) {
                _check({
                    condition: false,
                    label: "VERIFY_ARB_SUCKER_DEPLOYER MUST be set on production for Arbitrum endpoint identity",
                    critical: true
                });
            } else {
                _skip("Arbitrum endpoint identity (VERIFY_ARB_SUCKER_DEPLOYER not set on non-production chain)");
            }
        }

        // --- CCIP routes ---
        // CCIP deployers are per-(local, remote) pair. The CSV form
        // `<remoteChainId>:<address>,<remoteChainId>:<address>` lets the operator supply each
        // route deployer alongside its expected remote chain id; the verifier then asserts the
        // router (per local chain) and remote selector (per remote chain) match canonical.
        address expectedCcipRouter = _expectedCcipRouter();
        if (bytes(ccipSuckerDeployersCsv).length > 0) {
            string[] memory pairs = vm.split(ccipSuckerDeployersCsv, ",");
            for (uint256 i; i < pairs.length; i++) {
                string[] memory kv = vm.split(pairs[i], ":");
                if (kv.length != 2) {
                    _check({
                        condition: false,
                        label: string.concat("VERIFY_CCIP_SUCKER_DEPLOYERS_BY_REMOTE entry malformed: ", pairs[i]),
                        critical: true
                    });
                    continue;
                }
                uint256 remoteChainId = vm.parseUint(kv[0]);
                address deployer = vm.parseAddress(kv[1]);
                _checkCcipDeployerEndpoints({
                    deployer: deployer, expectedRemoteChainId: remoteChainId, expectedRouter: expectedCcipRouter
                });
            }
        } else if (isProductionChain && expectedCcipRouter != address(0)) {
            _check({
                condition: false,
                label: "VERIFY_CCIP_SUCKER_DEPLOYERS_BY_REMOTE MUST be set on production for CCIP route identity",
                critical: true
            });
        } else {
            _skip("CCIP route identity (VERIFY_CCIP_SUCKER_DEPLOYERS_BY_REMOTE not set)");
        }
    }

    /// Assert OP/Base flavored deployer endpoints.
    function _checkOpDeployerEndpoints(
        address deployer,
        address expectedMessenger,
        address expectedBridge,
        string memory label
    )
        internal
    {
        if (expectedMessenger != address(0)) {
            (bool okMsg, bytes memory msgData) = deployer.staticcall(abi.encodeWithSignature("opMessenger()"));
            _check({
                condition: okMsg && msgData.length >= 32 && abi.decode(msgData, (address)) == expectedMessenger,
                label: string.concat(label, " sucker deployer opMessenger == canonical"),
                critical: true
            });
        }
        if (expectedBridge != address(0)) {
            (bool okBr, bytes memory brData) = deployer.staticcall(abi.encodeWithSignature("opBridge()"));
            _check({
                condition: okBr && brData.length >= 32 && abi.decode(brData, (address)) == expectedBridge,
                label: string.concat(label, " sucker deployer opBridge == canonical"),
                critical: true
            });
        }
    }

    /// Assert Arbitrum flavored deployer endpoints. `expectedInbox == address(0)` on L2 (no
    /// inbox required); the helper still asserts the deployer's inbox is zero there so a wrong
    /// L1-side inbox baked into an L2 deployer is also caught.
    function _checkArbDeployerEndpoints(
        address deployer,
        address expectedInbox,
        address expectedGatewayRouter
    )
        internal
    {
        (bool okInbox, bytes memory inboxData) = deployer.staticcall(abi.encodeWithSignature("arbInbox()"));
        _check({
            condition: okInbox && inboxData.length >= 32 && abi.decode(inboxData, (address)) == expectedInbox,
            label: "Arbitrum sucker deployer arbInbox == canonical",
            critical: true
        });
        if (expectedGatewayRouter != address(0)) {
            (bool okGw, bytes memory gwData) = deployer.staticcall(abi.encodeWithSignature("arbGatewayRouter()"));
            _check({
                condition: okGw && gwData.length >= 32 && abi.decode(gwData, (address)) == expectedGatewayRouter,
                label: "Arbitrum sucker deployer arbGatewayRouter == canonical",
                critical: true
            });
        }
    }

    /// Assert CCIP-route deployer endpoints (router + remote selector + remote chain id). The
    /// expected selector is keyed by the remote chain id supplied by the operator; the local
    /// chain id is implicit through `_expectedCcipRouter`. A wrong `ccipRemoteChainId` means
    /// the deployer is bridging to a different chain than the operator declared in the env CSV.
    function _checkCcipDeployerEndpoints(
        address deployer,
        uint256 expectedRemoteChainId,
        address expectedRouter
    )
        internal
    {
        // ccipRouter() == local-chain canonical router.
        if (expectedRouter != address(0)) {
            (bool okRouter, bytes memory routerData) = deployer.staticcall(abi.encodeWithSignature("ccipRouter()"));
            _check({
                condition: okRouter && routerData.length >= 32 && abi.decode(routerData, (address)) == expectedRouter,
                label: string.concat(
                    "CCIP sucker deployer (remote=", vm.toString(expectedRemoteChainId), ") ccipRouter == canonical"
                ),
                critical: true
            });
        }
        // ccipRemoteChainId() == operator-declared remote chain id.
        (bool okId, bytes memory idData) = deployer.staticcall(abi.encodeWithSignature("ccipRemoteChainId()"));
        _check({
            condition: okId && idData.length >= 32 && abi.decode(idData, (uint256)) == expectedRemoteChainId,
            label: string.concat(
                "CCIP sucker deployer (remote=", vm.toString(expectedRemoteChainId), ") ccipRemoteChainId == declared"
            ),
            critical: true
        });
        // ccipRemoteChainSelector() == Chainlink's canonical selector for the declared remote.
        uint64 expectedSelector = _expectedCcipSelectorFor(expectedRemoteChainId);
        if (expectedSelector != 0) {
            (bool okSel, bytes memory selData) =
                deployer.staticcall(abi.encodeWithSignature("ccipRemoteChainSelector()"));
            _check({
                condition: okSel && selData.length >= 32 && abi.decode(selData, (uint64)) == expectedSelector,
                label: string.concat(
                    "CCIP sucker deployer (remote=",
                    vm.toString(expectedRemoteChainId),
                    ") ccipRemoteChainSelector == canonical"
                ),
                critical: true
            });
        }
    }

    /// @notice Returns the registered Uniswap V4 hook address. Used by the external-address
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

    /// @notice Assert the live CTPublisher CPN posting criteria for category `cat` match the
    /// canonical values from `Deploy.s.sol::_deployCroptop`. Same source of truth (the deploy
    /// script's hardcoded REVCroptopAllowedPost values), no operator env input needed.
    /// @dev If the canonical CPN config changes in the deploy script, the table here must change
    /// alongside it. The deploy script uses `DECIMALS = 18`; matching power-of-ten literals are
    /// inlined below to keep the canonical table grep-able next to its checks.
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
        // Canonical values mirror Deploy.s.sol `_deployCroptop`. `DECIMALS = 18`.
        uint256 expectedMinPrice;
        uint256 expectedMinSupply;
        uint256 expectedMaxSupply = 999_999_999; // shared across categories
        uint256 expectedMaxSplitPct = 0; // shared
        if (cat == 0) {
            expectedMinPrice = 10 ** 13; // 10 ** (DECIMALS - 5)
            expectedMinSupply = 10_000;
        } else if (cat == 1) {
            expectedMinPrice = 10 ** 15; // 10 ** (DECIMALS - 3)
            expectedMinSupply = 10_000;
        } else if (cat == 2) {
            expectedMinPrice = 10 ** 17; // 10 ** (DECIMALS - 1)
            expectedMinSupply = 100;
        } else if (cat == 3) {
            expectedMinPrice = 10 ** 18; // 10 ** DECIMALS
            expectedMinSupply = 10;
        } else if (cat == 4) {
            expectedMinPrice = 10 ** 20; // 10 ** (DECIMALS + 2)
            expectedMinSupply = 10;
        } else {
            // Caller loops 0..4; any other category isn't part of the canonical CPN config.
            return;
        }

        _check({
            condition: minPrice == expectedMinPrice,
            label: string.concat("CPN category ", vm.toString(cat), " minPrice == canonical"),
            critical: true
        });
        _check({
            condition: minSupply == expectedMinSupply,
            label: string.concat("CPN category ", vm.toString(cat), " minSupply == canonical"),
            critical: true
        });
        _check({
            condition: maxSupply == expectedMaxSupply,
            label: string.concat("CPN category ", vm.toString(cat), " maxSupply == canonical"),
            critical: true
        });
        _check({
            condition: maxSplitPct == expectedMaxSplitPct,
            label: string.concat("CPN category ", vm.toString(cat), " maxSplitPercent == canonical"),
            critical: true
        });
        _check({
            condition: allowed.length == 0,
            label: string.concat("CPN category ", vm.toString(cat), " allowed-addresses is empty (canonical)"),
            critical: true
        });
    }

    /// loads the expected per-project config hashes from VERIFY_CONFIG_HASH_{1..4}.
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

    /// @notice Returns the canonical-revnet project IDs and human-readable labels that should be
    /// looped over by per-project verifier categories (controller wiring, accounting context,
    /// router-terminal routes, revnet config hash, sucker manifest, etc.).
    ///
    /// The baseline four (NANA(1), CPN(2), REV(3), BAN(4)) are always present on a canonical
    /// deploy. DEFIFA(5), ART(6), and MARKEE(7) join the loop on chains where they've been
    /// deployed — `_projects.count() >= projectId` is the cheap presence check that mirrors how
    /// `_deployDefifaRevnet` / `_deployArt` / `_deployMarkee` reserve their IDs.
    /// @dev The arrays are returned with matching indices so callers can use `labels[i]` for log
    /// strings without re-deriving the human-readable name. Production chains run the full 7
    /// projects on every chain (ART deploys a no-op shell off-Base to keep MARKEE's ID stable);
    /// the count check guards local test fixtures and partial-deploy testnets.
    function _canonicalRevnetProjectIdsAndLabels()
        internal
        view
        returns (uint256[] memory ids, string[] memory labels)
    {
        // Defensive read: `projects` is set during `_loadDeployment` on real runs but several
        // unit/regression harnesses construct `Verify` without populating it. Treat a reverting
        // `count()` call as "baseline four only" so those harnesses keep targeting the assertion
        // they intend to exercise instead of crashing on the count probe.
        uint256 totalProjects;
        if (address(projects) != address(0)) {
            try projects.count() returns (uint256 c) {
                totalProjects = c;
            } catch {
                totalProjects = 0;
            }
        }
        // ART is a wired revnet ONLY on Base — off-Base it's a bare project-ID placeholder with no
        // controller/terminals/ruleset, so the wired-revnet loops would falsely reject it. Existence
        // and ownership of project 6 are still proven separately (outside this helper) on every chain.
        bool isBase = block.chainid == 8453 || block.chainid == 84_532;
        bool includeDefifa = totalProjects >= _DEFIFA_REV_PROJECT_ID;
        bool includeArt = totalProjects >= _ART_PROJECT_ID && isBase;
        bool includeMarkee = totalProjects >= _MARKEE_PROJECT_ID;

        uint256 count = 4 + (includeDefifa ? 1 : 0) + (includeArt ? 1 : 0) + (includeMarkee ? 1 : 0);

        ids = new uint256[](count);
        labels = new string[](count);
        ids[0] = _FEE_PROJECT_ID;
        labels[0] = "NANA(1)";
        ids[1] = _CPN_PROJECT_ID;
        labels[1] = "CPN(2)";
        ids[2] = _REV_PROJECT_ID;
        labels[2] = "REV(3)";
        ids[3] = _BAN_PROJECT_ID;
        labels[3] = "BAN(4)";

        uint256 j = 4;
        if (includeDefifa) {
            ids[j] = _DEFIFA_REV_PROJECT_ID;
            labels[j] = "DEFIFA(5)";
            j++;
        }
        if (includeArt) {
            ids[j] = _ART_PROJECT_ID;
            labels[j] = "ART(6)";
            j++;
        }
        if (includeMarkee) {
            ids[j] = _MARKEE_PROJECT_ID;
            labels[j] = "MARKEE(7)";
            j++;
        }
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

    /// canonical OP CrossDomainMessenger seen from this chain. On L1 the messenger
    /// is the route-specific L1 messenger (different for OP vs Base — see _expectedBase*); on
    /// L2 (Optimism / OP Sepolia) it is the bedrock predeploy at 0x...0007.
    function _expectedOpBridgeMessenger() internal view returns (address) {
        if (block.chainid == 1) return 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1;
        if (block.chainid == 11_155_111) return 0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef;
        if (block.chainid == 10) return 0x4200000000000000000000000000000000000007;
        if (block.chainid == 11_155_420) return 0x4200000000000000000000000000000000000007;
        return address(0);
    }

    /// canonical OP StandardBridge seen from this chain. Bedrock predeploy on L2.
    function _expectedOpStandardBridge() internal view returns (address) {
        if (block.chainid == 1) return 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1;
        if (block.chainid == 11_155_111) return 0xFBb0621E0B23b5478B630BD55a5f21f67730B0F1;
        if (block.chainid == 10) return 0x4200000000000000000000000000000000000010;
        if (block.chainid == 11_155_420) return 0x4200000000000000000000000000000000000010;
        return address(0);
    }

    /// canonical Base CrossDomainMessenger seen from this chain. L1 messenger
    /// differs from the OP messenger because each L2's L1-side messenger is independent.
    function _expectedBaseBridgeMessenger() internal view returns (address) {
        if (block.chainid == 1) return 0x866E82a600A1414e583f7F13623F1aC5d58b0Afa;
        if (block.chainid == 11_155_111) return 0xC34855F4De64F1840e5686e64278da901e261f20;
        if (block.chainid == 8453) return 0x4200000000000000000000000000000000000007;
        if (block.chainid == 84_532) return 0x4200000000000000000000000000000000000007;
        return address(0);
    }

    /// canonical Base StandardBridge seen from this chain. Bedrock predeploy on L2.
    function _expectedBaseStandardBridge() internal view returns (address) {
        if (block.chainid == 1) return 0x3154Cf16ccdb4C6d922629664174b904d80F2C35;
        if (block.chainid == 11_155_111) return 0xfd0Bf71F60660E2f608ed56e1659C450eB113120;
        if (block.chainid == 8453) return 0x4200000000000000000000000000000000000010;
        if (block.chainid == 84_532) return 0x4200000000000000000000000000000000000010;
        return address(0);
    }

    /// canonical Arbitrum inbox seen from this chain. L1-only — the inbox is the
    /// L1 contract that receives retryable tickets; L2 deployers store address(0) here.
    function _expectedArbInbox() internal view returns (address) {
        if (block.chainid == 1) return 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;
        if (block.chainid == 11_155_111) return 0xaAe29B0366299461418F5324a79Afc425BE5ae21;
        // L2 deployers carry inbox = address(0) by design; surface that as the expected value
        // so a wrong nonzero L1 inbox baked into an L2 deployer is still caught.
        if (block.chainid == 42_161 || block.chainid == 421_614) return address(0);
        return address(0);
    }

    /// canonical Arbitrum gateway router seen from this chain (L1 and L2 versions
    /// differ).
    function _expectedArbGatewayRouter() internal view returns (address) {
        if (block.chainid == 1) return 0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef;
        if (block.chainid == 11_155_111) return 0xcE18836b233C83325Cc8848CA4487e94C6288264;
        if (block.chainid == 42_161) return 0x5288c571Fd7aD117beA99bF60FE0846C4E84F933;
        if (block.chainid == 421_614) return 0x9fDD1C4E4AA24EEc1d913FABea925594a20d43C7;
        return address(0);
    }

    /// canonical USDC for this chain — the bridge token swap-CCIP deployers route
    /// value through. Mirrors Deploy.s.sol's `_usdcToken` assignments.
    function _expectedBridgeToken() internal view returns (address) {
        if (block.chainid == 1) return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (block.chainid == 11_155_111) return 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        if (block.chainid == 10) return 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
        if (block.chainid == 11_155_420) return 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;
        if (block.chainid == 8453) return 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        if (block.chainid == 84_532) return 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        if (block.chainid == 42_161) return 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        if (block.chainid == 421_614) return 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
        return address(0);
    }

    /// canonical Chainlink CCIP router on this chain. Mirrors `CCIPHelper.<X>_ROUTER`.
    function _expectedCcipRouter() internal view returns (address) {
        if (block.chainid == 1) return 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
        if (block.chainid == 11_155_111) return 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
        if (block.chainid == 10) return 0x3206695CaE29952f4b0c22a169725a865bc8Ce0f;
        if (block.chainid == 11_155_420) return 0x114A20A10b43D4115e5aeef7345a1A71d2a60C57;
        if (block.chainid == 8453) return 0x881e3A65B4d4a04dD529061dd0071cf975F58bCD;
        if (block.chainid == 84_532) return 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;
        if (block.chainid == 42_161) return 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;
        if (block.chainid == 421_614) return 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165;
        return address(0);
    }

    /// Chainlink's canonical CCIP chain selector for a given remote chain id.
    /// Returns 0 for unknown chains so the caller can skip the assert rather than fail closed
    /// — selectors are immutable per Chainlink so absent entries here mean "not yet supported".
    function _expectedCcipSelectorFor(uint256 remoteChainId) internal pure returns (uint64) {
        if (remoteChainId == 1) return 5_009_297_550_715_157_269; // ETH
        if (remoteChainId == 11_155_111) return 16_015_286_601_757_825_753; // ETH Sepolia
        if (remoteChainId == 10) return 3_734_403_246_176_062_136; // OP
        if (remoteChainId == 11_155_420) return 5_224_473_277_236_331_295; // OP Sepolia
        if (remoteChainId == 42_161) return 4_949_039_107_694_359_620; // ARB
        if (remoteChainId == 421_614) return 3_478_487_238_524_512_106; // ARB Sepolia
        if (remoteChainId == 8453) return 15_971_525_489_660_198_786; // Base
        if (remoteChainId == 84_532) return 10_344_971_235_874_465_080; // Base Sepolia
        return 0;
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

    /// @notice Artifact-identity sweep across every implementation group. Each call asserts the
    /// deployed runtime bytecode equals the artifact's deployedBytecode. Logs INFO and skips
    /// gracefully when the artifact file is missing (e.g. partial-coverage testnet) or the
    /// contract is not loaded (e.g. optional periphery on testnet).
    ///
    /// Coverage groups:
    /// - core singletons: JBProjects, JBDirectory, JBController, JBMultiTerminal, JBTerminalStore
    /// - core support: JBFundAccessLimits, JBTokens, JBPrices, JBRulesets, JBSplits,
    ///   JBFeelessAddresses, JBPermissions
    /// - Revnet stack: REVDeployer, REVOwner, REVLoans
    /// - Omnichain: JBOmnichainDeployer, JBSuckerRegistry
    /// - Hook & registry singletons: JB721TiersHookDeployer/Store/ProjectDeployer,
    ///   JBBuybackHookRegistry, JBRouterTerminalRegistry
    /// - Croptop: CTPublisher, CTDeployer, CTProjectOwner
    /// - Buyback hook (default implementation)
    /// - 721 tiers hook (base implementation)
    /// - Periphery: JBProjectHandles, JB721Distributor, JBTokenDistributor, JBProjectPayerDeployer
    /// - Address registry + Defifa: JBAddressRegistry, DefifaDeployer + sub-targets
    ///   (HOOK_CODE_ORIGIN, TOKEN_URI_RESOLVER, GOVERNOR)
    function _verifyImplementationIdentities() internal {
        console.log("--- Implementation Identity (artifact bytecode parity) ---");

        // Core singletons.
        _requireArtifactIdentity({artifactName: "JBProjects", deployed: address(projects), label: "JBProjects"});
        _requireArtifactIdentity({artifactName: "JBDirectory", deployed: address(directory), label: "JBDirectory"});
        _requireArtifactIdentity({artifactName: "JBController", deployed: address(controller), label: "JBController"});
        _requireArtifactIdentity({
            artifactName: "JBMultiTerminal", deployed: address(terminal), label: "JBMultiTerminal"
        });
        _requireArtifactIdentity({
            artifactName: "JBTerminalStore", deployed: address(terminalStore), label: "JBTerminalStore"
        });

        // Core support.
        _requireArtifactIdentity({
            artifactName: "JBFundAccessLimits", deployed: address(fundAccessLimits), label: "JBFundAccessLimits"
        });
        _requireArtifactIdentity({artifactName: "JBTokens", deployed: address(tokens), label: "JBTokens"});
        _requireArtifactIdentity({artifactName: "JBPrices", deployed: address(prices), label: "JBPrices"});
        _requireArtifactIdentity({artifactName: "JBRulesets", deployed: address(rulesets), label: "JBRulesets"});
        _requireArtifactIdentity({artifactName: "JBSplits", deployed: address(splits), label: "JBSplits"});
        _requireArtifactIdentity({
            artifactName: "JBFeelessAddresses", deployed: address(feelessAddresses), label: "JBFeelessAddresses"
        });
        _requireArtifactIdentity({
            artifactName: "JBPermissions", deployed: address(permissions), label: "JBPermissions"
        });

        // Revnet stack.
        _requireArtifactIdentity({artifactName: "REVDeployer", deployed: address(revDeployer), label: "REVDeployer"});
        _requireArtifactIdentity({artifactName: "REVOwner", deployed: address(revOwner), label: "REVOwner"});
        _requireArtifactIdentity({artifactName: "REVLoans", deployed: address(revLoans), label: "REVLoans"});

        // Omnichain.
        _requireArtifactIdentity({
            artifactName: "JBOmnichainDeployer", deployed: address(omnichainDeployer), label: "JBOmnichainDeployer"
        });
        _requireArtifactIdentity({
            artifactName: "JBSuckerRegistry", deployed: address(suckerRegistry), label: "JBSuckerRegistry"
        });

        // Hook & registry singletons.
        _requireArtifactIdentity({
            artifactName: "JB721TiersHookDeployer", deployed: address(hookDeployer), label: "JB721TiersHookDeployer"
        });
        _requireArtifactIdentity({
            artifactName: "JB721TiersHookStore", deployed: address(hookStore), label: "JB721TiersHookStore"
        });
        _requireArtifactIdentity({
            artifactName: "JB721TiersHookProjectDeployer",
            deployed: address(hookProjectDeployer),
            label: "JB721TiersHookProjectDeployer"
        });
        _requireArtifactIdentity({
            artifactName: "JBBuybackHookRegistry", deployed: address(buybackRegistry), label: "JBBuybackHookRegistry"
        });
        _requireArtifactIdentity({
            artifactName: "JBRouterTerminalRegistry",
            deployed: address(routerTerminalRegistry),
            label: "JBRouterTerminalRegistry"
        });

        // Croptop.
        _requireArtifactIdentity({artifactName: "CTPublisher", deployed: address(ctPublisher), label: "CTPublisher"});
        _requireArtifactIdentity({artifactName: "CTDeployer", deployed: address(ctDeployer), label: "CTDeployer"});
        _requireArtifactIdentity({
            artifactName: "CTProjectOwner", deployed: address(ctProjectOwner), label: "CTProjectOwner"
        });

        // Buyback hook default implementation (via registry getter).
        if (address(buybackRegistry) != address(0)) {
            (bool ok, bytes memory data) = address(buybackRegistry).staticcall(abi.encodeWithSignature("defaultHook()"));
            if (ok && data.length >= 32) {
                _requireArtifactIdentity({
                    artifactName: "JBBuybackHook", deployed: abi.decode(data, (address)), label: "JBBuybackHook default"
                });
            }
        }

        // 721 tiers hook base implementation (via low-level call so the interface return-type
        // mismatch between JB721TiersHookDeployer.HOOK() and IJB721TiersHook doesn't bite).
        {
            (bool okHook, bytes memory hookData) = address(hookDeployer).staticcall(abi.encodeWithSignature("HOOK()"));
            if (okHook && hookData.length >= 32) {
                _requireArtifactIdentity({
                    artifactName: "JB721TiersHook",
                    deployed: abi.decode(hookData, (address)),
                    label: "JB721TiersHook base impl"
                });
            }
        }

        // Periphery.
        _requireArtifactIdentity({
            artifactName: "JBProjectHandles", deployed: address(projectHandles), label: "JBProjectHandles"
        });
        _requireArtifactIdentity({
            artifactName: "JB721Distributor", deployed: address(distributor721), label: "JB721Distributor"
        });
        _requireArtifactIdentity({
            artifactName: "JBTokenDistributor", deployed: address(tokenDistributor), label: "JBTokenDistributor"
        });
        _requireArtifactIdentity({
            artifactName: "JBProjectPayerDeployer",
            deployed: address(projectPayerDeployer),
            label: "JBProjectPayerDeployer"
        });

        // the JBProjectPayer implementation behind JBProjectPayerDeployer.IMPLEMENTATION
        // also needs identity. Deployer-only identity proves the FACTORY is canonical but not the
        // CLONE TARGET — and every JBProjectPayer clone delegates to that implementation.
        if (address(projectPayerDeployer) != address(0)) {
            (bool okImpl, bytes memory implData) =
                address(projectPayerDeployer).staticcall(abi.encodeWithSignature("IMPLEMENTATION()"));
            if (okImpl && implData.length >= 32) {
                _requireArtifactIdentity({
                    artifactName: "JBProjectPayer",
                    deployed: abi.decode(implData, (address)),
                    label: "JBProjectPayer clone impl"
                });
            }
        }

        // The JB721Checkpoints implementation behind JB721CheckpointsDeployer.IMPLEMENTATION is
        // the analogous case for the 721 checkpoint module. Deployer-only identity is insufficient;
        // the clone target needs its own check.
        if (address(_checkpointsDeployer()) != address(0)) {
            (bool okImpl, bytes memory implData) =
                _checkpointsDeployer().staticcall(abi.encodeWithSignature("IMPLEMENTATION()"));
            if (okImpl && implData.length >= 32) {
                _requireArtifactIdentity({
                    artifactName: "JB721Checkpoints",
                    deployed: abi.decode(implData, (address)),
                    label: "JB721Checkpoints clone impl"
                });
            }
        }

        // Defifa + AddressRegistry.
        _requireArtifactIdentity({
            artifactName: "JBAddressRegistry", deployed: addressRegistry, label: "JBAddressRegistry"
        });
        _requireArtifactIdentity({
            artifactName: "DefifaDeployer", deployed: address(defifaDeployer), label: "DefifaDeployer"
        });
        if (address(defifaDeployer) != address(0)) {
            (bool okOrigin, bytes memory originData) =
                address(defifaDeployer).staticcall(abi.encodeWithSignature("HOOK_CODE_ORIGIN()"));
            if (okOrigin && originData.length >= 32) {
                _requireArtifactIdentity({
                    artifactName: "DefifaHook",
                    deployed: abi.decode(originData, (address)),
                    label: "DefifaHook code origin"
                });
            }
            (bool okResolver, bytes memory resolverData) =
                address(defifaDeployer).staticcall(abi.encodeWithSignature("TOKEN_URI_RESOLVER()"));
            if (okResolver && resolverData.length >= 32) {
                _requireArtifactIdentity({
                    artifactName: "DefifaTokenUriResolver",
                    deployed: abi.decode(resolverData, (address)),
                    label: "DefifaTokenUriResolver"
                });
            }
            (bool okGov, bytes memory govData) =
                address(defifaDeployer).staticcall(abi.encodeWithSignature("GOVERNOR()"));
            if (okGov && govData.length >= 32) {
                _requireArtifactIdentity({
                    artifactName: "DefifaGovernor", deployed: abi.decode(govData, (address)), label: "DefifaGovernor"
                });
            }
        }

        // Each listed swap-enabled CCIP sucker deployer (and its singleton) must match the
        // canonical artifact bytecode. Without this check the deploy can ship a swap-enabled
        // sucker whose source diverges from the in-tree implementation (out-of-order batch
        // metadata stranding earlier batches; raw-ETH V4 settlement reverting before unwrap),
        // but reads as "allowed in registry" and "canonically wired". Identity covers both the
        // deployer factory and the per-route singleton that every clone proxies to.
        _verifySwapCcipSuckerRolloutIdentity();

        // Every implementation that backs a clone or per-route singleton carries its own
        // constructor-injected PERMISSIONS / trustedForwarder immutables. The artifact-identity
        // sweep masks those bytes before bytecode parity, so a noncanonical auth-input on the
        // implementation survives that check. Per-surface getter equality is the only way to
        // authenticate them.
        _verifyImplementationAuthInputs();

        console.log("");
    }

    /// @notice Assert canonical PERMISSIONS / trustedForwarder on every implementation that passes
    /// the artifact-identity sweep. Each branch probes the getter via staticcall so a surface
    /// that doesn't expose the getter is silently skipped (the getter absence is itself a
    /// bytecode-shape mismatch that the artifact-identity sweep catches).
    function _verifyImplementationAuthInputs() internal {
        // Base 721 hook implementation (every cloned hook delegates here).
        (bool okHookData, bytes memory hookData) = address(hookDeployer).staticcall(abi.encodeWithSignature("HOOK()"));
        if (okHookData && hookData.length >= 32) {
            address baseHook = abi.decode(hookData, (address));
            _requireCanonicalAuthInputs({impl: baseHook, label: "JB721TiersHook base impl"});
        }

        // 721 Checkpoints implementation (every checkpoint module clones from this).
        if (address(_checkpointsDeployer()) != address(0)) {
            (bool okCp, bytes memory cpData) =
                _checkpointsDeployer().staticcall(abi.encodeWithSignature("IMPLEMENTATION()"));
            if (okCp && cpData.length >= 32) {
                _requireCanonicalAuthInputs({impl: abi.decode(cpData, (address)), label: "JB721Checkpoints clone impl"});
            }
        }

        // ProjectPayer implementation (every clone delegates here).
        if (address(projectPayerDeployer) != address(0)) {
            (bool okPp, bytes memory ppData) =
                address(projectPayerDeployer).staticcall(abi.encodeWithSignature("IMPLEMENTATION()"));
            if (okPp && ppData.length >= 32) {
                _requireCanonicalAuthInputs({impl: abi.decode(ppData, (address)), label: "JBProjectPayer clone impl"});
            }
        }

        // Default buyback hook (the registry's defaultHook is the per-chain implementation).
        if (address(buybackRegistry) != address(0)) {
            (bool okBh, bytes memory bhData) =
                address(buybackRegistry).staticcall(abi.encodeWithSignature("defaultHook()"));
            if (okBh && bhData.length >= 32) {
                _requireCanonicalAuthInputs({impl: abi.decode(bhData, (address)), label: "JBBuybackHook default"});
            }
        }

        // Per-type sucker singletons. Each deployer's `singleton()` is the implementation
        // every clone proxies to; auth-input identity there bounds every produced sucker.
        if (opSuckerDeployer != address(0)) {
            _verifySuckerSingletonAuthInputs({deployer: opSuckerDeployer, label: "JBOptimismSucker singleton"});
        }
        if (baseSuckerDeployer != address(0)) {
            _verifySuckerSingletonAuthInputs({deployer: baseSuckerDeployer, label: "JBBaseSucker singleton"});
        }
        if (arbSuckerDeployer != address(0)) {
            _verifySuckerSingletonAuthInputs({deployer: arbSuckerDeployer, label: "JBArbitrumSucker singleton"});
        }
        // CCIP-route deployers — iterate the same CSV used by endpoint identity.
        if (bytes(ccipSuckerDeployersCsv).length > 0) {
            string[] memory pairs = vm.split(ccipSuckerDeployersCsv, ",");
            for (uint256 i; i < pairs.length; i++) {
                string[] memory kv = vm.split(pairs[i], ":");
                if (kv.length != 2) continue; // Earlier pass already failed closed for malformed entries.
                address deployer = vm.parseAddress(kv[1]);
                _verifySuckerSingletonAuthInputs({
                    deployer: deployer, label: string.concat("JBCCIPSucker singleton (remote=", kv[0], ")")
                });
            }
        }
    }

    /// @notice Helper: read a sucker deployer's `singleton()` and run the auth-input getter checks
    /// against it. Used by the clone/singleton sweep so each per-route sucker implementation gets
    /// per-surface auth-input authentication on top of the artifact-identity sweep.
    function _verifySuckerSingletonAuthInputs(address deployer, string memory label) internal {
        (bool ok, bytes memory data) = deployer.staticcall(abi.encodeWithSignature("singleton()"));
        if (!ok || data.length < 32) return; // Earlier endpoint / wiring pass already flagged the missing getter.
        address singleton = abi.decode(data, (address));
        if (singleton == address(0) || singleton.code.length == 0) return;
        _requireCanonicalAuthInputs({impl: singleton, label: label});
    }

    /// Helper: assert `impl.PERMISSIONS() == permissions` (when exposed) and
    /// `impl.trustedForwarder() == expectedTrustedForwarder` (when exposed and an expected
    /// forwarder is configured). Missing getters are silently skipped — the artifact bytecode
    /// parity sweep already constrains the implementation's interface shape.
    function _requireCanonicalAuthInputs(address impl, string memory label) internal {
        if (impl == address(0) || impl.code.length == 0) return;

        (bool okPerm, bytes memory permData) = impl.staticcall(abi.encodeWithSignature("PERMISSIONS()"));
        if (okPerm && permData.length >= 32) {
            _check({
                condition: abi.decode(permData, (address)) == address(permissions),
                label: string.concat(label, " PERMISSIONS == permissions"),
                critical: true
            });
        }

        if (expectedTrustedForwarder != address(0)) {
            (bool okFwd, bytes memory fwdData) = impl.staticcall(abi.encodeWithSignature("trustedForwarder()"));
            if (okFwd && fwdData.length >= 32) {
                _check({
                    condition: abi.decode(fwdData, (address)) == expectedTrustedForwarder,
                    label: string.concat(label, " trustedForwarder == expected"),
                    critical: true
                });
            }
        }
    }

    /// @dev Prove each listed swap-enabled CCIP sucker deployer and its singleton carry the
    /// canonical artifact bytecode. Comma-separated env list keeps the env surface aligned with
    /// `VERIFY_SUCKER_DEPLOYERS` — operators populate this with the swap-enabled subset only.
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
            // delegates to; the swap/native-settlement fixes live there. Read via `singleton()` to avoid
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

            // Swap-CCIP deployers also store `bridgeToken`, `poolManager`, `v3Factory`,
            // `univ4Hook`, and `wrappedNativeToken` set via `setSwapConstants` after deploy.
            // Artifact bytecode parity masks immutables and `setSwapConstants` writes to storage rather than
            // immutables — but either way, per-surface getter equality is the only way to prove
            // the swap-specific endpoints match canonical. Without these, a swap-enabled sucker
            // could route bridge tokens through a forked V3/V4 surface or settle against a
            // wrong wrapped-native sentinel while the rest of the deployment looks canonical.
            _checkSwapCcipSwapConstants(deployer);
        }
    }

    /// @notice Helper: assert each swap-CCIP deployer's swap-side endpoint pointers match the
    /// canonical per-chain manifest. `bridgeToken` is USDC across the supported chains;
    /// `poolManager`, `v3Factory`, and `wrappedNativeToken` reuse the existing external-address
    /// manifests; `univ4Hook` is the per-chain `JBUniswapV4Hook` (read via the buyback registry's
    /// `defaultHook`).
    function _checkSwapCcipSwapConstants(address deployer) internal {
        // bridgeToken == per-chain canonical USDC.
        address expectedBridgeToken = _expectedBridgeToken();
        if (expectedBridgeToken != address(0)) {
            (bool okBt, bytes memory btData) = deployer.staticcall(abi.encodeWithSignature("bridgeToken()"));
            _check({
                condition: okBt && btData.length >= 32 && abi.decode(btData, (address)) == expectedBridgeToken,
                label: string.concat("Swap-CCIP deployer ", vm.toString(deployer), " bridgeToken == canonical USDC"),
                critical: true
            });
        }

        // poolManager == canonical V4 PoolManager (reuse external-address manifest).
        address expectedPoolManager = _expectedV4PoolManager();
        if (expectedPoolManager != address(0)) {
            (bool okPm, bytes memory pmData) = deployer.staticcall(abi.encodeWithSignature("poolManager()"));
            _check({
                condition: okPm && pmData.length >= 32 && abi.decode(pmData, (address)) == expectedPoolManager,
                label: string.concat("Swap-CCIP deployer ", vm.toString(deployer), " poolManager == canonical V4"),
                critical: true
            });
        }

        // v3Factory == canonical V3 factory (reuse external-address manifest).
        address expectedV3 = _expectedV3Factory();
        if (expectedV3 != address(0)) {
            (bool okV3, bytes memory v3Data) = deployer.staticcall(abi.encodeWithSignature("v3Factory()"));
            _check({
                condition: okV3 && v3Data.length >= 32 && abi.decode(v3Data, (address)) == expectedV3,
                label: string.concat("Swap-CCIP deployer ", vm.toString(deployer), " v3Factory == canonical V3"),
                critical: true
            });
        }

        // wrappedNativeToken == canonical WETH (reuse external-address manifest).
        address expectedWeth = _expectedWrappedNative();
        if (expectedWeth != address(0)) {
            (bool okW, bytes memory wData) = deployer.staticcall(abi.encodeWithSignature("wrappedNativeToken()"));
            _check({
                condition: okW && wData.length >= 32 && abi.decode(wData, (address)) == expectedWeth,
                label: string.concat("Swap-CCIP deployer ", vm.toString(deployer), " wrappedNativeToken == canonical"),
                critical: true
            });
        }

        // univ4Hook == the registered JBUniswapV4Hook (sourced from buyback registry's
        // defaultHook). Skip if the buyback registry isn't loaded on this chain.
        address expectedV4Hook = _uniswapV4Hook();
        if (expectedV4Hook != address(0)) {
            (bool okH, bytes memory hData) = deployer.staticcall(abi.encodeWithSignature("univ4Hook()"));
            _check({
                condition: okH && hData.length >= 32 && abi.decode(hData, (address)) == expectedV4Hook,
                label: string.concat("Swap-CCIP deployer ", vm.toString(deployer), " univ4Hook == canonical"),
                critical: true
            });
        }
    }

    /// Assert deployed runtime bytecode at `addr` is structurally identical to the
    /// published artifact's `deployedBytecode`, with all immutable-reference byte ranges masked
    /// to zero on both sides. The mask ranges are read from the artifact's
    /// `deployedBytecode.immutableReferences` (a map of AST-ID -> [{start, length}, ...]).
    ///
    /// The constructor of any contract using Solidity `immutable` keywords writes the immutable
    /// value into runtime bytecode at compiler-chosen offsets. The artifact carries zero bytes
    /// at those positions; a real deployment carries the constructor-injected values. Raw
    /// `extcodehash` equality fails for any such contract — but the bytes OUTSIDE those ranges
    /// are byte-equal between artifact and live, which is what proves the canonical source was
    /// compiled and deployed.
    ///
    /// Requires `bytecode_hash = "none"` in the build profile. Skips with a logged note when the
    /// artifact is missing so partial-coverage chains still produce a clear log line.
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
        _zeroImmutableRanges({bytecode: artifactBytecode, artifactJson: json});
        _zeroImmutableRanges({bytecode: liveBytecode, artifactJson: json});

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
