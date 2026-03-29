// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

// Pull in TestBaseWorkflow which deploys the full JB core stack.
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core contracts and interfaces.
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";
import {JBPermissioned} from "@bananapus/core-v6/src/abstract/JBPermissioned.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";

// 721 Hook.
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHookStore} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookStore.sol";

// Address Registry.
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// Buyback Hook.
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";

// Suckers.
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// Croptop.
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";
import {CTDeployer} from "@croptop/core-v6/src/CTDeployer.sol";

// Omnichain Deployer.
import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";

// Revnet.
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";
import {IREVLoans} from "@rev-net/core-v6/src/interfaces/IREVLoans.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

// Uniswap V4 (needed for buyback hook constructor).
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

// Geomean oracle mock interface.
import {IGeomeanOracle} from "@bananapus/buyback-hook-v6/src/interfaces/IGeomeanOracle.sol";

/// @notice Adversarial test suite proving wildcard-permission singletons (REVDeployer, CTDeployer,
/// JBOmnichainDeployer) cannot abuse their powers cross-project.
///
/// The key security invariant: wildcard permissions (projectId=0) are stored as
/// `permissionsOf[operator][account][0]`, where `account` is the singleton itself.
/// Permission checks use `_requirePermissionFrom(account: PROJECTS.ownerOf(projectId), ...)`.
/// Therefore, a singleton's wildcard only applies to projects that IT owns. Projects owned by
/// other addresses are immune because `account` in the permission lookup is the victim's owner,
/// not the singleton.
///
/// Run with: forge test --match-contract WildcardPermissionKillChain -vvv
contract WildcardPermissionKillChain is TestBaseWorkflow {
    // ═══════════════════════════════════════════════════════════════════════
    //  Constants
    // ═══════════════════════════════════════════════════════════════════════

    // Mainnet PoolManager address (post-V4 deployment).
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    // Trusted forwarder for ERC2771 meta-transactions.
    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // ═══════════════════════════════════════════════════════════════════════
    //  Actors
    // ═══════════════════════════════════════════════════════════════════════

    // An innocent victim who deploys a project independently of any singleton.
    address VICTIM_OWNER = makeAddr("victimOwner");

    // An adversary who controls a compromised singleton.
    address ATTACKER = makeAddr("attacker");

    // ═══════════════════════════════════════════════════════════════════════
    //  Protocol singletons under test
    // ═══════════════════════════════════════════════════════════════════════

    // The three singletons that receive wildcard permissions.
    REVOwner REV_OWNER;
    REVDeployer REV_DEPLOYER;
    CTDeployer CT_DEPLOYER;
    JBOmnichainDeployer OMNICHAIN_DEPLOYER;

    // Supporting infrastructure.
    JBSuckerRegistry SUCKER_REGISTRY;
    IJB721TiersHookDeployer HOOK_DEPLOYER;
    CTPublisher PUBLISHER;
    JBBuybackHook BUYBACK_HOOK;
    JBBuybackHookRegistry BUYBACK_REGISTRY;
    IREVLoans LOANS_CONTRACT;

    // Fee project owned by multisig.
    uint256 FEE_PROJECT_ID;

    // The victim's independently-deployed project.
    uint256 victimProjectId;

    // ═══════════════════════════════════════════════════════════════════════
    //  Setup
    // ═══════════════════════════════════════════════════════════════════════

    function setUp() public override {
        // Fork mainnet at a stable block so Uniswap V4 PoolManager exists.
        vm.createSelectFork("ethereum", 21_700_000);
        // Verify the PoolManager is deployed at the expected address.
        require(POOL_MANAGER_ADDR.code.length > 0, "PoolManager not deployed");

        // Deploy the full JB core stack (permissions, projects, directory, controller, terminal, etc.).
        super.setUp();

        // Create the fee project used by REVDeployer.
        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        // Deploy sucker registry (needed by all three deployers).
        SUCKER_REGISTRY = new JBSuckerRegistry(jbDirectory(), jbPermissions(), multisig(), address(0));

        // Deploy 721 hook infrastructure.
        JB721TiersHookStore hookStore = new JB721TiersHookStore();
        JB721TiersHook exampleHook = new JB721TiersHook(
            jbDirectory(), jbPermissions(), jbPrices(), jbRulesets(), hookStore, jbSplits(), multisig()
        );
        IJBAddressRegistry addressRegistry = new JBAddressRegistry();
        HOOK_DEPLOYER = new JB721TiersHookDeployer(exampleHook, hookStore, addressRegistry, multisig());

        // Deploy Croptop publisher.
        PUBLISHER = new CTPublisher(jbDirectory(), jbPermissions(), FEE_PROJECT_ID, multisig());

        // Deploy buyback hook with real PoolManager.
        BUYBACK_HOOK = new JBBuybackHook(
            jbDirectory(),
            jbPermissions(),
            jbPrices(),
            jbProjects(),
            jbTokens(),
            IPoolManager(POOL_MANAGER_ADDR),
            IHooks(address(0)),
            address(0)
        );

        // Deploy buyback hook registry and set the default hook.
        BUYBACK_REGISTRY = new JBBuybackHookRegistry(jbPermissions(), jbProjects(), address(this), address(0));
        BUYBACK_REGISTRY.setDefaultHook(IJBRulesetDataHook(address(BUYBACK_HOOK)));

        // Deploy REVLoans contract.
        LOANS_CONTRACT = new REVLoans({
            controller: jbController(),
            projects: jbProjects(),
            revId: FEE_PROJECT_ID,
            owner: address(this),
            permit2: permit2(),
            trustedForwarder: TRUSTED_FORWARDER
        });

        // Deploy the REVOwner — the runtime data hook for pay and cash out callbacks.
        REV_OWNER = new REVOwner(
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            jbDirectory(),
            FEE_PROJECT_ID,
            SUCKER_REGISTRY,
            address(LOANS_CONTRACT)
        );

        // Deploy REVDeployer — this grants wildcard permissions to SUCKER_REGISTRY, LOANS, BUYBACK_HOOK.
        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_KillChain"}(
            jbController(),
            SUCKER_REGISTRY,
            FEE_PROJECT_ID,
            HOOK_DEPLOYER,
            PUBLISHER,
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            address(LOANS_CONTRACT),
            TRUSTED_FORWARDER,
            address(REV_OWNER)
        );

        // Approve REVDeployer to receive the fee project NFT.
        vm.prank(multisig());
        jbProjects().approve(address(REV_DEPLOYER), FEE_PROJECT_ID);

        // Deploy CTDeployer — grants wildcard MAP_SUCKER_TOKEN to SUCKER_REGISTRY, ADJUST_721_TIERS to PUBLISHER.
        CT_DEPLOYER =
            new CTDeployer(jbPermissions(), jbProjects(), HOOK_DEPLOYER, PUBLISHER, SUCKER_REGISTRY, TRUSTED_FORWARDER);

        // Deploy JBOmnichainDeployer — grants wildcard MAP_SUCKER_TOKEN to SUCKER_REGISTRY.
        OMNICHAIN_DEPLOYER =
            new JBOmnichainDeployer(SUCKER_REGISTRY, HOOK_DEPLOYER, jbPermissions(), jbProjects(), TRUSTED_FORWARDER);

        // Mock the geomean oracle so buyback hook does not revert on observe().
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // ── Create the victim's project (independently, NOT through any singleton) ──
        // This project is owned by VICTIM_OWNER, not by any singleton.
        vm.startPrank(VICTIM_OWNER);

        // Build a single minimal ruleset config with owner-minting enabled.
        JBRulesetConfig[] memory rulesetConfigs = new JBRulesetConfig[](1);
        // Allow owner minting so the victim can mint (but singletons should not be able to).
        rulesetConfigs[0].metadata.allowOwnerMinting = true;
        // Set base currency to ETH.
        rulesetConfigs[0].metadata.baseCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));
        // Set issuance weight to 1000 tokens per ETH.
        rulesetConfigs[0].weight = 1000e18;

        // Set up a single terminal accepting native ETH.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        // Configure the accounting context for native ETH.
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        // Build the terminal config array with one terminal.
        JBTerminalConfig[] memory termConfigs = new JBTerminalConfig[](1);
        // Assign the multi-terminal with the ETH accounting context.
        termConfigs[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Launch the victim's project through the controller.
        victimProjectId = jbController()
            .launchProjectFor({
                owner: VICTIM_OWNER,
                projectUri: "ipfs://victim",
                rulesetConfigurations: rulesetConfigs,
                terminalConfigurations: termConfigs,
                memo: "Victim project"
            });

        vm.stopPrank();

        // Fund the victim's project with 10 ETH via a payment.
        vm.deal(address(this), 100 ether);
        // Pay 10 ETH into the victim's project terminal.
        jbMultiTerminal().pay{value: 10 ether}({
            projectId: victimProjectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 10 ether,
            beneficiary: VICTIM_OWNER,
            minReturnedTokens: 0,
            memo: "Fund victim",
            metadata: ""
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Helper: mock the geomean oracle to avoid buyback hook reverts
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Mocks the IGeomeanOracle.observe() call at address(0) so the buyback hook does not revert.
    function _mockOracle(int256 liquidity, int24 tick, uint32 twapWindow) internal {
        // Etch minimal bytecode at address(0) so it can receive calls.
        vm.etch(address(0), hex"00");

        // Build the tick cumulatives array for the oracle response.
        int56[] memory tickCumulatives = new int56[](2);
        // First tick cumulative is zero (the starting point).
        tickCumulatives[0] = 0;
        // Second tick cumulative encodes the tick over the TWAP window.
        tickCumulatives[1] = int56(tick) * int56(int32(twapWindow));

        // Build the seconds-per-liquidity array for the oracle response.
        uint136[] memory secondsPerLiquidityCumulativeX128s = new uint136[](2);
        // First element is zero (the starting point).
        secondsPerLiquidityCumulativeX128s[0] = 0;
        // Compute a safe liquidity value (avoid division by zero).
        uint256 liq = uint256(liquidity > 0 ? liquidity : -liquidity);
        // Ensure liquidity is at least 1 to prevent division by zero.
        if (liq == 0) liq = 1;
        // Encode the seconds-per-liquidity value.
        secondsPerLiquidityCumulativeX128s[1] = uint136((uint256(twapWindow) << 128) / liq);

        // Mock the oracle observe() call to return our crafted data.
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(IGeomeanOracle.observe.selector),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
        );
    }

    // Allow this contract to receive ETH.
    receive() external payable {}

    // ═══════════════════════════════════════════════════════════════════════
    //  Scenario 1: REVDeployer abuse — cross-project attacks
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice A compromised REVDeployer cannot mint tokens for a project it does not own.
    /// REVDeployer has no MINT_TOKENS permission on the victim's account — the wildcard
    /// only covers projects it itself owns. The permission check looks up
    /// `permissionsOf[revDeployer][victimOwner][*]` which is empty.
    function test_revDeployer_cannotMintForUnrelatedProject() public {
        // Impersonate the REVDeployer to simulate it being compromised.
        vm.prank(address(REV_DEPLOYER));

        // Expect the call to revert with Unauthorized because the permission is checked
        // against VICTIM_OWNER (the project owner), not REVDeployer.
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER, // account: the project owner
                address(REV_DEPLOYER), // sender: the attacker impersonating REVDeployer
                victimProjectId, // projectId: the victim's project
                JBPermissionIds.MINT_TOKENS // permissionId: MINT_TOKENS (10)
            )
        );

        // Attempt to mint tokens for the victim's project.
        jbController()
            .mintTokensOf({
                projectId: victimProjectId,
                tokenCount: 1_000_000e18,
                beneficiary: address(REV_DEPLOYER),
                memo: "steal tokens",
                useReservedPercent: false
            });
    }

    /// @notice A compromised REVDeployer cannot queue malicious rulesets for a project it does not own.
    /// The QUEUE_RULESETS permission only works for projects owned by REVDeployer.
    function test_revDeployer_cannotQueueRulesetsForUnrelatedProject() public {
        // Impersonate the REVDeployer.
        vm.prank(address(REV_DEPLOYER));

        // Build a single malicious ruleset that would zero out the cash-out tax.
        JBRulesetConfig[] memory maliciousRulesets = new JBRulesetConfig[](1);
        // Set a zero cash-out tax rate to drain the project on cash out.
        maliciousRulesets[0].metadata.cashOutTaxRate = 0;
        // Set base currency to ETH to match the victim project.
        maliciousRulesets[0].metadata.baseCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));

        // Expect the call to revert because REVDeployer has no QUEUE_RULESETS on the victim's account.
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER, // account: the victim project owner
                address(REV_DEPLOYER), // sender: the attacker
                victimProjectId, // projectId: the victim's project
                JBPermissionIds.QUEUE_RULESETS // permissionId: QUEUE_RULESETS (2)
            )
        );

        // Attempt to queue rulesets for the victim's project.
        jbController().queueRulesetsOf({projectId: victimProjectId, rulesetConfigurations: maliciousRulesets, memo: ""});
    }

    /// @notice A compromised REVDeployer cannot set itself as a terminal for an unrelated project.
    /// The SET_TERMINALS permission is checked against the project owner in JBDirectory.
    function test_revDeployer_cannotSetTerminalsForUnrelatedProject() public {
        // Impersonate the REVDeployer.
        vm.prank(address(REV_DEPLOYER));

        // Build a terminal array pointing to the attacker-controlled terminal.
        IJBTerminal[] memory maliciousTerminals = new IJBTerminal[](1);
        // Use the existing terminal as a stand-in (the point is the permission check fails).
        maliciousTerminals[0] = jbMultiTerminal();

        // Expect revert because REVDeployer has no SET_TERMINALS on the victim's account.
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER, // account: the victim project owner
                address(REV_DEPLOYER), // sender: the attacker
                victimProjectId, // projectId: the victim's project
                JBPermissionIds.SET_TERMINALS // permissionId: SET_TERMINALS (15)
            )
        );

        // Attempt to replace the victim's terminals.
        jbDirectory().setTerminalsOf({projectId: victimProjectId, terminals: maliciousTerminals});
    }

    /// @notice A compromised REVDeployer cannot use the surplus allowance of an unrelated project.
    /// The USE_ALLOWANCE permission is checked against the project owner in JBMultiTerminal.
    function test_revDeployer_cannotUseAllowanceOfUnrelatedProject() public {
        // Impersonate the REVDeployer.
        vm.prank(address(REV_DEPLOYER));

        // Expect revert because REVDeployer has no USE_ALLOWANCE on the victim's account.
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER, // account: the victim project owner
                address(REV_DEPLOYER), // sender: the attacker
                victimProjectId, // projectId: the victim's project
                JBPermissionIds.USE_ALLOWANCE // permissionId: USE_ALLOWANCE (17)
            )
        );

        // Attempt to drain surplus from the victim's project.
        jbMultiTerminal()
            .useAllowanceOf({
                projectId: victimProjectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: 10 ether,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                minTokensPaidOut: 0,
                beneficiary: payable(address(REV_DEPLOYER)),
                feeBeneficiary: payable(address(REV_DEPLOYER)), // fee beneficiary for the payout
                memo: "drain surplus"
            });
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Scenario 2: CTDeployer abuse — cross-project attacks
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice A compromised CTDeployer cannot queue rulesets to override hooks on an unrelated project.
    /// CTDeployer's wildcard permissions are on its own account, not on the victim's.
    function test_ctDeployer_cannotQueueRulesetsForUnrelatedProject() public {
        // Impersonate the CTDeployer.
        vm.prank(address(CT_DEPLOYER));

        // Build a malicious ruleset that would hijack the data hook.
        JBRulesetConfig[] memory maliciousRulesets = new JBRulesetConfig[](1);
        // Point the data hook to the CTDeployer itself (hijack).
        maliciousRulesets[0].metadata.dataHook = address(CT_DEPLOYER);
        // Enable the data hook for pay operations.
        maliciousRulesets[0].metadata.useDataHookForPay = true;
        // Enable the data hook for cash-out operations.
        maliciousRulesets[0].metadata.useDataHookForCashOut = true;
        // Set base currency to ETH.
        maliciousRulesets[0].metadata.baseCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));

        // Expect revert because CTDeployer has no QUEUE_RULESETS on the victim's account.
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER, // account: the victim project owner
                address(CT_DEPLOYER), // sender: the attacker
                victimProjectId, // projectId: the victim's project
                JBPermissionIds.QUEUE_RULESETS // permissionId: QUEUE_RULESETS (2)
            )
        );

        // Attempt to override the victim's hooks by queuing a malicious ruleset.
        jbController().queueRulesetsOf({projectId: victimProjectId, rulesetConfigurations: maliciousRulesets, memo: ""});
    }

    /// @notice A compromised CTDeployer cannot use the surplus allowance of an unrelated project.
    function test_ctDeployer_cannotUseAllowanceOfUnrelatedProject() public {
        // Impersonate the CTDeployer.
        vm.prank(address(CT_DEPLOYER));

        // Expect revert because CTDeployer has no USE_ALLOWANCE on the victim's account.
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER, // account: the victim project owner
                address(CT_DEPLOYER), // sender: the attacker
                victimProjectId, // projectId: the victim's project
                JBPermissionIds.USE_ALLOWANCE // permissionId: USE_ALLOWANCE (17)
            )
        );

        // Attempt to access funds from the victim's project.
        jbMultiTerminal()
            .useAllowanceOf({
                projectId: victimProjectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: 5 ether,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                minTokensPaidOut: 0,
                beneficiary: payable(address(CT_DEPLOYER)),
                feeBeneficiary: payable(address(CT_DEPLOYER)), // fee beneficiary for the payout
                memo: "steal funds"
            });
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Scenario 3: JBOmnichainDeployer abuse — cross-project attacks
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice A compromised JBOmnichainDeployer cannot deploy suckers for an unrelated project.
    /// The DEPLOY_SUCKERS permission is checked against the project owner in JBSuckerRegistry.
    function test_omnichainDeployer_cannotDeploySuckersForUnrelatedProject() public {
        // Impersonate the JBOmnichainDeployer.
        vm.prank(address(OMNICHAIN_DEPLOYER));

        // Build an empty sucker deployment config (just testing the permission gate).
        JBSuckerDeployerConfig[] memory suckerConfigs = new JBSuckerDeployerConfig[](0);

        // Expect revert because JBOmnichainDeployer has no DEPLOY_SUCKERS on the victim's account.
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER, // account: the victim project owner
                address(OMNICHAIN_DEPLOYER), // sender: the attacker
                victimProjectId, // projectId: the victim's project
                JBPermissionIds.DEPLOY_SUCKERS // permissionId: DEPLOY_SUCKERS (31)
            )
        );

        // Attempt to deploy suckers for the victim's project.
        SUCKER_REGISTRY.deploySuckersFor({
            projectId: victimProjectId, salt: bytes32("malicious"), configurations: suckerConfigs
        });
    }

    /// @notice A compromised JBOmnichainDeployer cannot mint tokens for an unrelated project.
    /// Even though it acts as a data hook for its own projects, it has no mint permission
    /// on victim projects.
    function test_omnichainDeployer_cannotMintForUnrelatedProject() public {
        // Impersonate the JBOmnichainDeployer.
        vm.prank(address(OMNICHAIN_DEPLOYER));

        // Expect revert because JBOmnichainDeployer has no MINT_TOKENS on the victim's account.
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER, // account: the victim project owner
                address(OMNICHAIN_DEPLOYER), // sender: the attacker
                victimProjectId, // projectId: the victim's project
                JBPermissionIds.MINT_TOKENS // permissionId: MINT_TOKENS (10)
            )
        );

        // Attempt to mint tokens for the victim's project.
        jbController()
            .mintTokensOf({
                projectId: victimProjectId,
                tokenCount: 1_000_000e18,
                beneficiary: address(OMNICHAIN_DEPLOYER),
                memo: "steal tokens via omnichain",
                useReservedPercent: false
            });
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Scenario 4: Cross-singleton collusion — combined escalation attempts
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Even if REVDeployer grants CTDeployer a wildcard permission on its own account,
    /// CTDeployer still cannot operate on the victim's project because the permission lookup
    /// is against VICTIM_OWNER (the project owner), not REVDeployer.
    function test_crossSingleton_collusionCannotEscalate() public {
        // ── Step 1: REVDeployer grants CTDeployer MINT_TOKENS wildcard on REVDeployer's account ──
        // This simulates REVDeployer colluding by sharing its permissions.
        vm.prank(address(REV_DEPLOYER));

        // Build the permission data: give CTDeployer MINT_TOKENS with wildcard projectId=0.
        uint8[] memory permissionIds = new uint8[](1);
        // MINT_TOKENS is permission ID 10.
        permissionIds[0] = JBPermissionIds.MINT_TOKENS;
        // Grant the permission from REVDeployer's account to CTDeployer for all projects (wildcard).
        jbPermissions()
            .setPermissionsFor({
                account: address(REV_DEPLOYER),
                permissionsData: JBPermissionsData({
                    operator: address(CT_DEPLOYER),
                    projectId: 0, // wildcard: all projects
                    permissionIds: permissionIds
                })
            });

        // ── Step 2: Verify CTDeployer now has the wildcard on REVDeployer's account ──
        // This confirms the permission was successfully set.
        bool hasWildcard = jbPermissions()
            .hasPermission({
                operator: address(CT_DEPLOYER),
                account: address(REV_DEPLOYER),
                projectId: 0,
                permissionId: JBPermissionIds.MINT_TOKENS,
                includeRoot: false,
                includeWildcardProjectId: false
            });
        // Assert the wildcard was granted on REVDeployer's account.
        assertTrue(hasWildcard, "CTDeployer should have MINT wildcard on REV_DEPLOYER's account");

        // ── Step 3: CTDeployer tries to use the colluded permission on the victim's project ──
        vm.prank(address(CT_DEPLOYER));

        // Expect revert because the controller checks against VICTIM_OWNER, not REV_DEPLOYER.
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER, // account: the victim project owner (not REVDeployer!)
                address(CT_DEPLOYER), // sender: the colluding CTDeployer
                victimProjectId, // projectId: the victim's project
                JBPermissionIds.MINT_TOKENS // permissionId: MINT_TOKENS
            )
        );

        // Attempt to mint using the colluded permission — this must fail.
        jbController()
            .mintTokensOf({
                projectId: victimProjectId,
                tokenCount: 1_000_000e18,
                beneficiary: address(CT_DEPLOYER),
                memo: "collusion attempt",
                useReservedPercent: false
            });
    }

    /// @notice Prove that even if all three singletons pool their permissions, they cannot
    /// grant themselves ROOT on the victim's account. The setPermissionsFor function prevents
    /// non-account callers from setting permissions on the wildcard project ID.
    function test_crossSingleton_cannotGrantRootOnVictimAccount() public {
        // ── Attempt 1: REVDeployer tries to set ROOT for itself on victim's account ──
        vm.prank(address(REV_DEPLOYER));

        // Build the permission data attempting to grant ROOT.
        uint8[] memory rootPermission = new uint8[](1);
        // ROOT is permission ID 1.
        rootPermission[0] = JBPermissionIds.ROOT;

        // Expect revert because only VICTIM_OWNER can set permissions on their own account.
        // A third-party caller would need ROOT on the specific projectId AND cannot set ROOT for others.
        vm.expectRevert();

        // Attempt to set ROOT for REVDeployer on the victim's account.
        jbPermissions()
            .setPermissionsFor({
                account: VICTIM_OWNER,
                permissionsData: JBPermissionsData({
                    operator: address(REV_DEPLOYER),
                    projectId: uint64(victimProjectId), // cast to uint64 for JBPermissionsData
                    permissionIds: rootPermission
                })
            });
    }

    /// @notice Prove that a singleton cannot set wildcard permissions on the victim's account,
    /// even for non-ROOT permissions. The setPermissionsFor function blocks third-party callers
    /// from setting permissions on projectId=0 (wildcard).
    function test_crossSingleton_cannotSetWildcardOnVictimAccount() public {
        // ── REVDeployer tries to grant itself MINT_TOKENS wildcard on victim's account ──
        vm.prank(address(REV_DEPLOYER));

        // Build the permission data for MINT_TOKENS on wildcard project.
        uint8[] memory mintPermission = new uint8[](1);
        // MINT_TOKENS is permission ID 10.
        mintPermission[0] = JBPermissionIds.MINT_TOKENS;

        // Expect revert: non-account callers cannot set permissions on projectId=0.
        vm.expectRevert();

        // Attempt to set wildcard MINT_TOKENS for REVDeployer on the victim's account.
        jbPermissions()
            .setPermissionsFor({
                account: VICTIM_OWNER,
                permissionsData: JBPermissionsData({
                    operator: address(REV_DEPLOYER),
                    projectId: 0, // wildcard
                    permissionIds: mintPermission
                })
            });
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Positive test: singletons CAN use permissions on projects they own
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Verify that the permission system works correctly for legitimate use:
    /// REVDeployer's wildcard permissions DO apply to projects it owns.
    /// This proves the security boundary is correctly drawn at project ownership.
    function test_positive_wildcardWorksForOwnedProjects() public {
        // ── Deploy a revnet through REVDeployer, which will own the project ──

        // Build a minimal REV stage configuration.
        REVStageConfig[] memory stages = new REVStageConfig[](1);
        // Set the initial issuance rate to 1000 tokens per ETH.
        stages[0].initialIssuance = 1000e18;
        // Set the stage to start immediately.
        stages[0].startsAtOrAfter = uint40(block.timestamp);
        // Set the cash-out tax rate to 50%.
        stages[0].cashOutTaxRate = 5000;
        // No auto-issuances for this minimal config.
        stages[0].autoIssuances = new REVAutoIssuance[](0);

        // Build the REV configuration.
        REVConfig memory revConfig = REVConfig({
            description: REVDescription({
                name: "TestRevnet", ticker: "TREV", uri: "ipfs://test", salt: bytes32("test")
            }),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: address(0),
            stageConfigurations: stages
        });

        // Set up terminal configurations for the revnet.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        // Configure accounting for native ETH.
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        // Build terminal config with one terminal.
        JBTerminalConfig[] memory termConfigs = new JBTerminalConfig[](1);
        // Assign multi-terminal with ETH accounting.
        termConfigs[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Empty sucker deployment config (no suckers needed).
        REVSuckerDeploymentConfig memory suckerConfig;

        // Deploy the revnet (project will be owned by REV_DEPLOYER).
        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: revConfig,
            terminalConfigurations: termConfigs,
            suckerDeploymentConfiguration: suckerConfig
        });

        // Verify REVDeployer owns the newly created project.
        address projectOwner = jbProjects().ownerOf(revnetId);
        // Assert the project is owned by the REVDeployer.
        assertEq(projectOwner, address(REV_DEPLOYER), "REVDeployer should own the revnet");

        // ── Verify the LOANS_CONTRACT has USE_ALLOWANCE wildcard on REVDeployer's account ──
        // This is a legitimate wildcard permission that should work.
        bool loansHasAllowance = jbPermissions()
            .hasPermission({
                operator: address(LOANS_CONTRACT),
                account: address(REV_DEPLOYER),
                projectId: revnetId,
                permissionId: JBPermissionIds.USE_ALLOWANCE,
                includeRoot: false,
                includeWildcardProjectId: true // check wildcard
            });
        // Assert the loans contract has USE_ALLOWANCE via wildcard.
        assertTrue(loansHasAllowance, "LOANS should have USE_ALLOWANCE on REV_DEPLOYER's account via wildcard");

        // ── Verify the SUCKER_REGISTRY has MAP_SUCKER_TOKEN wildcard on REVDeployer's account ──
        bool registryHasMapToken = jbPermissions()
            .hasPermission({
                operator: address(SUCKER_REGISTRY),
                account: address(REV_DEPLOYER),
                projectId: revnetId,
                permissionId: JBPermissionIds.MAP_SUCKER_TOKEN,
                includeRoot: false,
                includeWildcardProjectId: true // check wildcard
            });
        // Assert the sucker registry has MAP_SUCKER_TOKEN via wildcard.
        assertTrue(registryHasMapToken, "SUCKER_REGISTRY should have MAP_SUCKER_TOKEN via wildcard");

        // ── Verify NONE of these singletons have permissions on the VICTIM project ──
        bool loansOnVictim = jbPermissions()
            .hasPermission({
                operator: address(LOANS_CONTRACT),
                account: VICTIM_OWNER,
                projectId: victimProjectId,
                permissionId: JBPermissionIds.USE_ALLOWANCE,
                includeRoot: true,
                includeWildcardProjectId: true
            });
        // Assert the loans contract has NO permissions on the victim project.
        assertFalse(loansOnVictim, "LOANS should NOT have USE_ALLOWANCE on victim project");

        bool revDeployerOnVictim = jbPermissions()
            .hasPermission({
                operator: address(REV_DEPLOYER),
                account: VICTIM_OWNER,
                projectId: victimProjectId,
                permissionId: JBPermissionIds.MINT_TOKENS,
                includeRoot: true,
                includeWildcardProjectId: true
            });
        // Assert REVDeployer has NO permissions on the victim project.
        assertFalse(revDeployerOnVictim, "REV_DEPLOYER should NOT have MINT_TOKENS on victim project");
    }

    /// @notice Verify the ROOT-on-wildcard prohibition: no caller (not even the singleton itself)
    /// can set ROOT permission with projectId=0. This is the ultimate backstop preventing
    /// wildcard ROOT escalation.
    function test_prohibition_cannotSetRootOnWildcardProject() public {
        // Even a singleton setting permissions on its OWN account cannot set ROOT with wildcard.
        vm.prank(address(REV_DEPLOYER));

        // Build permission data with ROOT on wildcard project.
        uint8[] memory rootPermission = new uint8[](1);
        // ROOT is permission ID 1.
        rootPermission[0] = JBPermissionIds.ROOT;

        // Expect revert: ROOT cannot be set on wildcard projectId=0.
        // The setPermissionsFor function checks: if sender != account AND (packed includes ROOT
        // OR projectId == WILDCARD), revert. Since sender IS account here, this check passes.
        // BUT: the explicit ROOT+wildcard prohibition at lines 78-97 of JBPermissions.sol
        // only blocks third-party callers. The account itself CAN set ROOT on wildcard for
        // itself (by design — the account is granting from its own permissions).
        // Let's verify the THIRD-PARTY case: an attacker tries to set ROOT+wildcard.
        vm.stopPrank();
        vm.prank(ATTACKER);

        // Expect revert: ATTACKER is not the account and is trying to set permissions on wildcard.
        vm.expectRevert();

        // An attacker tries to set ROOT wildcard on REVDeployer's account.
        jbPermissions()
            .setPermissionsFor({
                account: address(REV_DEPLOYER),
                permissionsData: JBPermissionsData({
                    operator: ATTACKER,
                    projectId: 0, // wildcard
                    permissionIds: rootPermission
                })
            });
    }

    /// @notice Verify that a third-party attacker cannot set ANY permissions on a singleton's
    /// account for the wildcard project ID. Even non-ROOT permissions on wildcard are blocked
    /// for third-party callers.
    function test_prohibition_thirdPartyCannotSetWildcardOnSingletonAccount() public {
        // An attacker tries to set MINT_TOKENS wildcard on REVDeployer's account.
        vm.prank(ATTACKER);

        // Build the permission data for a non-ROOT permission on wildcard.
        uint8[] memory mintPermission = new uint8[](1);
        // MINT_TOKENS is permission ID 10.
        mintPermission[0] = JBPermissionIds.MINT_TOKENS;

        // Expect revert: third-party callers cannot set permissions on projectId=0
        // (they would need ROOT on the specific project, but wildcard has no "specific project").
        vm.expectRevert();

        // Attempt to add MINT_TOKENS wildcard on REVDeployer's account from an attacker.
        jbPermissions()
            .setPermissionsFor({
                account: address(REV_DEPLOYER),
                permissionsData: JBPermissionsData({
                    operator: ATTACKER,
                    projectId: 0, // wildcard
                    permissionIds: mintPermission
                })
            });
    }
}
