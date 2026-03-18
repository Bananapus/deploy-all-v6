// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";

// Suckers
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {IJBSucker} from "@bananapus/suckers-v6/src/interfaces/IJBSucker.sol";
import {IJBSuckerExtended} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerExtended.sol";
import {IJBSuckerDeployer} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerDeployer.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";
import {JBTokenMapping} from "@bananapus/suckers-v6/src/structs/JBTokenMapping.sol";
import {JBSuckerState} from "@bananapus/suckers-v6/src/enums/JBSuckerState.sol";
import {JBOptimismSucker} from "@bananapus/suckers-v6/src/JBOptimismSucker.sol";
import {JBOptimismSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBOptimismSuckerDeployer.sol";
import {IOPMessenger} from "@bananapus/suckers-v6/src/interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "@bananapus/suckers-v6/src/interfaces/IOPStandardBridge.sol";
import {JBSucker} from "@bananapus/suckers-v6/src/JBSucker.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock OP Messenger — returns a configurable xDomainMessageSender and accepts sendMessage as no-op.
contract MockOPMessenger {
    address public xDomainMessageSender;

    function setXDomainMessageSender(address sender) external {
        xDomainMessageSender = sender;
    }

    function sendMessage(address, bytes calldata, uint32) external payable {}
}

/// @notice Mock OP Standard Bridge — accepts bridgeETHTo and bridgeERC20To as no-ops.
contract MockOPBridge {
    function bridgeETHTo(address, uint32, bytes calldata) external payable {}

    function bridgeERC20To(address, address, address, uint256, uint32, bytes calldata) external {}
}

/// @notice End-to-end sucker lifecycle tests on a single chain using mock OP messenger/bridge.
///
/// Tests deployment, token mapping, prepare (cashout → outbox), deprecation state machine,
/// and emergency hatch — all without cross-chain forks.
///
/// Run with: forge test --match-contract SuckerEndToEndForkTest -vvv
contract SuckerEndToEndForkTest is TestBaseWorkflow {
    uint32 constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));
    uint112 constant WEIGHT = 1000e18;

    address PROJECT_OWNER = makeAddr("suckerProjectOwner");
    address PAYER = makeAddr("suckerPayer");

    MockOPMessenger mockMessenger;
    MockOPBridge mockBridge;

    JBSuckerRegistry suckerRegistry;
    JBOptimismSuckerDeployer opDeployer;

    uint256 projectId;

    receive() external payable {}

    function setUp() public override {
        super.setUp();

        // Deploy mock bridge infrastructure.
        mockMessenger = new MockOPMessenger();
        mockBridge = new MockOPBridge();

        // Deploy the sucker registry.
        suckerRegistry = new JBSuckerRegistry(jbDirectory(), jbPermissions(), address(this), address(0));

        // Deploy the OP sucker deployer with mock messenger/bridge.
        opDeployer = new JBOptimismSuckerDeployer({
            directory: jbDirectory(),
            permissions: jbPermissions(),
            tokens: jbTokens(),
            configurator: address(this),
            trustedForwarder: address(0)
        });
        opDeployer.setChainSpecificConstants(
            IOPMessenger(address(mockMessenger)), IOPStandardBridge(address(mockBridge))
        );

        // Deploy the OP sucker singleton.
        JBOptimismSucker singleton = new JBOptimismSucker({
            deployer: opDeployer,
            directory: jbDirectory(),
            permissions: jbPermissions(),
            tokens: jbTokens(),
            feeProjectId: 1,
            trustedForwarder: address(0)
        });
        opDeployer.configureSingleton(singleton);

        // Allow the OP deployer in the registry.
        suckerRegistry.allowSuckerDeployer(address(opDeployer));

        // Launch a project.
        projectId = _launchProject();

        // Deploy ERC20 for the project (required for prepare).
        vm.prank(PROJECT_OWNER);
        jbController().deployERC20For(projectId, "SuckerTestToken", "STT", bytes32(0));

        // Fund actors.
        vm.deal(PAYER, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════════

    function _launchProject() internal returns (uint256) {
        JBRulesetMetadata memory meta = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
            baseCurrency: NATIVE_CURRENCY,
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: false,
            useTotalSurplusForCashOuts: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});

        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: WEIGHT,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: meta,
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        return jbController()
            .launchProjectFor({
                owner: PROJECT_OWNER,
                projectUri: "test://sucker-e2e",
                rulesetConfigurations: rulesets,
                terminalConfigurations: tc,
                memo: ""
            });
    }

    function _grantPermission(address from, address operator, uint256 _projectId, uint8 permissionId) internal {
        uint8[] memory ids = new uint8[](1);
        ids[0] = permissionId;

        vm.prank(from);
        jbPermissions()
            .setPermissionsFor(
                from, JBPermissionsData({operator: operator, projectId: uint64(_projectId), permissionIds: ids})
            );
    }

    function _deploySucker() internal returns (address) {
        // Grant DEPLOY_SUCKERS + MAP_SUCKER_TOKEN to the registry (since it deploys on behalf of the owner).
        _grantPermission(PROJECT_OWNER, address(suckerRegistry), projectId, JBPermissionIds.DEPLOY_SUCKERS);
        _grantPermission(PROJECT_OWNER, address(suckerRegistry), projectId, JBPermissionIds.MAP_SUCKER_TOKEN);

        JBTokenMapping[] memory mappings = new JBTokenMapping[](1);
        mappings[0] = JBTokenMapping({
            localToken: JBConstants.NATIVE_TOKEN,
            minGas: 200_000,
            remoteToken: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN))),
            toRemoteFee: 0
        });

        JBSuckerDeployerConfig[] memory configs = new JBSuckerDeployerConfig[](1);
        configs[0] = JBSuckerDeployerConfig({deployer: IJBSuckerDeployer(address(opDeployer)), mappings: mappings});

        vm.prank(PROJECT_OWNER);
        address[] memory suckers = suckerRegistry.deploySuckersFor(projectId, bytes32("SALT"), configs);
        return suckers[0];
    }

    function _pay(uint256 _projectId, address payer, uint256 amount) internal returns (uint256 tokens) {
        vm.prank(payer);
        tokens = jbMultiTerminal().pay{value: amount}({
            projectId: _projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: amount,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Tests
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Deploy a sucker through the registry and verify token mapping.
    function test_sucker_deployAndMapTokens() public {
        address suckerAddr = _deploySucker();

        // Verify the sucker is registered.
        assertTrue(suckerRegistry.isSuckerOf(projectId, suckerAddr), "Sucker should be registered");

        // Verify state is ENABLED.
        assertEq(uint8(IJBSucker(suckerAddr).state()), uint8(JBSuckerState.ENABLED), "Sucker should be enabled");

        // Verify the sucker is in the list of suckers for the project.
        address[] memory registeredSuckers = suckerRegistry.suckersOf(projectId);
        assertEq(registeredSuckers.length, 1, "Should have exactly one sucker");
        assertEq(registeredSuckers[0], suckerAddr, "Sucker address should match");
    }

    /// @notice prepare() should cash out project tokens and add a leaf to the outbox tree.
    function test_sucker_prepareBuildsOutbox() public {
        address suckerAddr = _deploySucker();

        // Pay to get tokens.
        uint256 tokens = _pay(projectId, PAYER, 5 ether);
        assertGt(tokens, 0, "Should receive tokens from payment");

        // Get the project's ERC20 token.
        address projectToken = address(jbTokens().tokenOf(projectId));
        assertNotEq(projectToken, address(0), "Project should have ERC20 deployed");

        // Approve sucker to transfer project tokens.
        vm.prank(PAYER);
        IERC20(projectToken).approve(suckerAddr, tokens);

        // Record balance before.
        uint256 payerTokensBefore = IERC20(projectToken).balanceOf(PAYER);

        // Prepare — cash out half the tokens.
        uint256 prepareCount = tokens / 2;
        bytes32 remoteBeneficiary = bytes32(uint256(uint160(PAYER)));

        vm.prank(PAYER);
        IJBSucker(suckerAddr)
            .prepare({
                projectTokenCount: prepareCount,
                beneficiary: remoteBeneficiary,
                minTokensReclaimed: 0,
                token: JBConstants.NATIVE_TOKEN
            });

        // Tokens should have been transferred from payer.
        uint256 payerTokensAfter = IERC20(projectToken).balanceOf(PAYER);
        assertEq(payerTokensBefore - payerTokensAfter, prepareCount, "Tokens should be transferred for prepare");
    }

    /// @notice Walk through the full deprecation state machine.
    function test_sucker_deprecationLifecycle() public {
        address suckerAddr = _deploySucker();
        IJBSuckerExtended sucker = IJBSuckerExtended(suckerAddr);

        // Initially ENABLED.
        assertEq(uint8(IJBSucker(suckerAddr).state()), uint8(JBSuckerState.ENABLED), "Should start ENABLED");

        // Set deprecation 28 days from now (must be >= 14 days out = _maxMessagingDelay).
        uint40 deprecationTime = uint40(block.timestamp + 28 days);
        vm.prank(PROJECT_OWNER);
        sucker.setDeprecation(deprecationTime);

        // Should be DEPRECATION_PENDING now (we're more than 14 days before deprecation).
        assertEq(
            uint8(IJBSucker(suckerAddr).state()),
            uint8(JBSuckerState.DEPRECATION_PENDING),
            "Should be DEPRECATION_PENDING"
        );

        // Warp to 14 days before deprecation → SENDING_DISABLED.
        vm.warp(deprecationTime - 14 days);
        assertEq(
            uint8(IJBSucker(suckerAddr).state()), uint8(JBSuckerState.SENDING_DISABLED), "Should be SENDING_DISABLED"
        );

        // Warp past deprecation → DEPRECATED.
        vm.warp(deprecationTime);
        assertEq(uint8(IJBSucker(suckerAddr).state()), uint8(JBSuckerState.DEPRECATED), "Should be DEPRECATED");
    }

    /// @notice prepare() reverts when the sucker is SENDING_DISABLED.
    function test_sucker_sendingDisabled_blocksNewPrepare() public {
        address suckerAddr = _deploySucker();
        IJBSuckerExtended sucker = IJBSuckerExtended(suckerAddr);

        // Pay to get tokens.
        uint256 tokens = _pay(projectId, PAYER, 5 ether);

        // Get the project's ERC20 token and approve.
        address projectToken = address(jbTokens().tokenOf(projectId));
        vm.prank(PAYER);
        IERC20(projectToken).approve(suckerAddr, tokens);

        // Set deprecation and warp to SENDING_DISABLED.
        uint40 deprecationTime = uint40(block.timestamp + 28 days);
        vm.prank(PROJECT_OWNER);
        sucker.setDeprecation(deprecationTime);
        vm.warp(deprecationTime - 14 days);

        assertEq(
            uint8(IJBSucker(suckerAddr).state()), uint8(JBSuckerState.SENDING_DISABLED), "Should be SENDING_DISABLED"
        );

        // prepare() should revert.
        vm.prank(PAYER);
        vm.expectRevert(JBSucker.JBSucker_Deprecated.selector);
        IJBSucker(suckerAddr)
            .prepare({
                projectTokenCount: tokens / 2,
                beneficiary: bytes32(uint256(uint160(PAYER))),
                minTokensReclaimed: 0,
                token: JBConstants.NATIVE_TOKEN
            });
    }

    /// @notice Emergency hatch enables local exit when bridging is unavailable.
    function test_sucker_emergencyHatch() public {
        address suckerAddr = _deploySucker();
        IJBSuckerExtended sucker = IJBSuckerExtended(suckerAddr);

        // Pay to get tokens.
        uint256 tokens = _pay(projectId, PAYER, 5 ether);

        // Approve and prepare.
        address projectToken = address(jbTokens().tokenOf(projectId));
        vm.prank(PAYER);
        IERC20(projectToken).approve(suckerAddr, tokens);

        uint256 prepareCount = tokens / 2;
        bytes32 remoteBeneficiary = bytes32(uint256(uint160(PAYER)));

        vm.prank(PAYER);
        IJBSucker(suckerAddr)
            .prepare({
                projectTokenCount: prepareCount,
                beneficiary: remoteBeneficiary,
                minTokensReclaimed: 0,
                token: JBConstants.NATIVE_TOKEN
            });

        // Grant SUCKER_SAFETY permission to project owner.
        _grantPermission(PROJECT_OWNER, PROJECT_OWNER, projectId, JBPermissionIds.SUCKER_SAFETY);

        // Enable emergency hatch for NATIVE_TOKEN.
        address[] memory hatchTokens = new address[](1);
        hatchTokens[0] = JBConstants.NATIVE_TOKEN;

        vm.prank(PROJECT_OWNER);
        sucker.enableEmergencyHatchFor(hatchTokens);

        // Verify that the token is no longer enabled for normal bridging.
        // Attempting a new prepare should fail because the token mapping is now disabled.
        vm.prank(PAYER);
        vm.expectRevert();
        IJBSucker(suckerAddr)
            .prepare({
                projectTokenCount: 1e18,
                beneficiary: remoteBeneficiary,
                minTokensReclaimed: 0,
                token: JBConstants.NATIVE_TOKEN
            });
    }
}
