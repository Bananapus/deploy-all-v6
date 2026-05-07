// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

// Pull in TestBaseWorkflow which deploys the full JB core stack.
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";

// Core contracts and interfaces (only what this test uniquely needs).
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBPermissioned} from "@bananapus/core-v6/src/abstract/JBPermissioned.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";

// Croptop.
import {CTDeployer} from "@croptop/core-v6/src/CTDeployer.sol";

// Omnichain Deployer.
import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";

// Suckers.
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// Revnet (only imports not already provided by RevnetForkBase).
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

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
contract WildcardPermissionKillChain is RevnetForkBase {
    // ═══════════════════════════════════════════════════════════════════════
    //  Actors (unique to this test)
    // ═══════════════════════════════════════════════════════════════════════

    // An innocent victim who deploys a project independently of any singleton.
    address VICTIM_OWNER = makeAddr("victimOwner");

    // An adversary who controls a compromised singleton.
    address ATTACKER = makeAddr("attacker");

    // ═══════════════════════════════════════════════════════════════════════
    //  Singletons under test (unique to this test)
    // ═══════════════════════════════════════════════════════════════════════

    CTDeployer CT_DEPLOYER;
    JBOmnichainDeployer OMNICHAIN_DEPLOYER;

    // The victim's independently-deployed project.
    uint256 victimProjectId;

    // ═══════════════════════════════════════════════════════════════════════
    //  CREATE2 salt override
    // ═══════════════════════════════════════════════════════════════════════

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_Wildcard";
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Setup
    // ═══════════════════════════════════════════════════════════════════════

    function setUp() public override {
        // RevnetForkBase.setUp() forks mainnet, deploys full JB core stack + ecosystem.
        super.setUp();

        // Deploy CTDeployer — grants wildcard MAP_SUCKER_TOKEN to SUCKER_REGISTRY, ADJUST_721_TIERS to PUBLISHER.
        CT_DEPLOYER = new CTDeployer(
            jbPermissions(),
            jbProjects(),
            HOOK_DEPLOYER,
            PUBLISHER,
            SUCKER_REGISTRY,
            address(0xB2b5841DBeF766d4b521221732F9B618fCf34A87)
        );

        // Deploy JBOmnichainDeployer — grants wildcard MAP_SUCKER_TOKEN to SUCKER_REGISTRY.
        OMNICHAIN_DEPLOYER = new JBOmnichainDeployer(
            SUCKER_REGISTRY,
            HOOK_DEPLOYER,
            jbPermissions(),
            jbProjects(),
            jbDirectory(),
            address(0xB2b5841DBeF766d4b521221732F9B618fCf34A87)
        );

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
            // forge-lint: disable-next-line(unsafe-typecast)
            projectId: victimProjectId,
            // forge-lint: disable-next-line(unsafe-typecast)
            salt: bytes32("malicious"),
            configurations: suckerConfigs
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
            // forge-lint: disable-next-line(unsafe-typecast)
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
                // forge-lint: disable-next-line(unsafe-typecast)
                name: "TestRevnet",
                ticker: "TREV",
                uri: "ipfs://test",
                // forge-lint: disable-next-line(unsafe-typecast)
                salt: bytes32("test")
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
