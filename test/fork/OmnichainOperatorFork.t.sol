// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../helpers/RevnetForkBase.sol";

import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {JBPermissioned} from "@bananapus/core-v6/src/abstract/JBPermissioned.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";

import {JBController} from "@bananapus/core-v6/src/JBController.sol";

import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";
import {IJBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/interfaces/IJBOmnichainDeployer.sol";

/// @notice Pins the `JBController.OMNICHAIN_RULESET_OPERATOR` trust boundary (the B-class omnichain-operator concern).
///
/// The controller bakes a single omnichain operator address as an immutable and lets it BYPASS the permission system
/// for `launchRulesetsFor` / `queueRulesetsOf` on ANY project. Two properties matter for safety:
///   1. **Detectability** — a genuine `JBOmnichainDeployer` is identifiable (interface + back-pointer + bytecode), so
///      the deploy pipeline can verify the baked-in operator is the real singleton (not attacker bytecode placed at a
///      predicted CREATE3 address). This test demonstrates that identification technique on a known-genuine instance.
///   2. **Bounded blast radius** — the bypass is narrow and function-scoped, NOT root. The operator can re-queue
///      rulesets on a project it does not own, but it CANNOT mint that project's tokens, rewrite its splits, or drain
///      its funds.
///
/// Run with: forge test --match-contract OmnichainOperatorForkTest -vvv
contract OmnichainOperatorForkTest is RevnetForkBase {
    address internal constant TRUSTED_FWD = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;
    address internal VICTIM_OWNER = makeAddr("victimOwner");
    address internal ATTACKER = makeAddr("attacker");

    JBOmnichainDeployer internal omnichainDeployer;
    JBController internal opController; // a controller whose baked-in operator is a real (non-zero) deployer
    uint256 internal victimProjectId;
    address internal omnichainOp; // == address(omnichainDeployer)

    function _deployerSalt() internal pure override returns (bytes32) {
        return "OmnichainOperator";
    }

    function setUp() public override {
        super.setUp();
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // A genuine omnichain deployer (identifiable; mirrors Deploy.s.sol's singleton).
        omnichainDeployer =
            new JBOmnichainDeployer(SUCKER_REGISTRY, HOOK_DEPLOYER, jbPermissions(), jbController(), TRUSTED_FWD);
        omnichainOp = address(omnichainDeployer);

        // TestBaseWorkflow's controller bakes a zero operator, which degenerately collides with empty data hooks. Stand
        // up a controller wired to the SAME core stack but with the genuine (non-zero) deployer as its omnichain
        // operator, so the bounded-blast-radius assertions exercise a realistic operator.
        opController = new JBController(
            jbController().DIRECTORY(),
            jbController().FUND_ACCESS_LIMITS(),
            jbPermissions(),
            jbController().PRICES(),
            jbController().PROJECTS(),
            jbController().RULESETS(),
            jbController().SPLITS(),
            jbController().TOKENS(),
            omnichainOp,
            TRUSTED_FWD
        );
        vm.prank(multisig());
        jbDirectory().setIsAllowedToSetFirstController(address(opController), true);

        // An independent project owned by VICTIM_OWNER (not by any singleton), controlled by opController.
        JBRulesetConfig[] memory rulesetConfigs = new JBRulesetConfig[](1);
        rulesetConfigs[0].metadata.allowOwnerMinting = true;
        rulesetConfigs[0].metadata.baseCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));
        rulesetConfigs[0].weight = 1000e18;

        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        JBTerminalConfig[] memory termConfigs = new JBTerminalConfig[](1);
        termConfigs[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        vm.prank(VICTIM_OWNER);
        victimProjectId = opController.launchProjectFor({
            owner: VICTIM_OWNER,
            projectUri: "ipfs://victim",
            rulesetConfigurations: rulesetConfigs,
            terminalConfigurations: termConfigs,
            memo: ""
        });

        vm.deal(address(this), 100 ether);
        jbMultiTerminal().pay{value: 10 ether}({
            projectId: victimProjectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 10 ether,
            beneficiary: VICTIM_OWNER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
    }

    /// @notice A genuine `JBOmnichainDeployer` is identifiable by interface + back-pointer + deployed bytecode — the
    /// provenance the deploy pipeline checks before trusting a baked-in operator address.
    function test_omnichain_genuineDeployerIsIdentifiable() public view {
        assertGt(address(omnichainDeployer).code.length, 0, "deployer has code");
        assertEq(
            address(omnichainDeployer.CONTROLLER()), address(jbController()), "back-pointer binds to this controller"
        );
        assertTrue(
            omnichainDeployer.supportsInterface(type(IJBOmnichainDeployer).interfaceId),
            "advertises the omnichain-deployer interface"
        );
    }

    /// @notice The operator's permission BYPASS is real and scoped to ruleset queuing: it can queue rulesets on a
    /// project it does not own, where a non-operator is rejected.
    function test_omnichain_operatorCanQueueRulesetsWhereOthersCannot() public {
        JBRulesetConfig[] memory configs = new JBRulesetConfig[](1);
        configs[0].metadata.baseCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));
        configs[0].weight = 500e18;

        // A non-operator cannot queue rulesets on the victim's project.
        vm.prank(ATTACKER);
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER,
                ATTACKER,
                victimProjectId,
                JBPermissionIds.QUEUE_RULESETS
            )
        );
        opController.queueRulesetsOf(victimProjectId, configs, "");

        // The omnichain operator may — the immutable bypass fires regardless of ownership.
        vm.prank(omnichainOp);
        uint256 rulesetId = opController.queueRulesetsOf(victimProjectId, configs, "");
        assertGt(rulesetId, 0, "operator queued a ruleset via the bypass");
    }

    /// @notice The bypass does NOT extend to minting — the operator cannot inflate a non-owned project's token.
    function test_omnichain_operatorCannotMintTokens() public {
        vm.prank(omnichainOp);
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER,
                omnichainOp,
                victimProjectId,
                JBPermissionIds.MINT_TOKENS
            )
        );
        opController.mintTokensOf(victimProjectId, 1_000_000e18, omnichainOp, "", false);
    }

    /// @notice The bypass does NOT extend to splits — the operator cannot redirect a non-owned project's payouts.
    function test_omnichain_operatorCannotSetSplitGroups() public {
        vm.prank(omnichainOp);
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER,
                omnichainOp,
                victimProjectId,
                JBPermissionIds.SET_SPLIT_GROUPS
            )
        );
        opController.setSplitGroupsOf(victimProjectId, 0, new JBSplitGroup[](0));
    }

    /// @notice The bypass does NOT extend to fund access — the operator cannot drain a non-owned project's treasury.
    function test_omnichain_operatorCannotUseAllowance() public {
        vm.prank(omnichainOp);
        vm.expectRevert(
            abi.encodeWithSelector(
                JBPermissioned.JBPermissioned_Unauthorized.selector,
                VICTIM_OWNER,
                omnichainOp,
                victimProjectId,
                JBPermissionIds.USE_ALLOWANCE
            )
        );
        jbMultiTerminal()
            .useAllowanceOf({
            projectId: victimProjectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            currency: uint256(uint32(uint160(JBConstants.NATIVE_TOKEN))),
            minTokensPaidOut: 0,
            beneficiary: payable(omnichainOp),
            feeBeneficiary: payable(omnichainOp),
            memo: ""
        });
    }
}
