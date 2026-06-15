// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";

import {JBProjectPayerDeployer} from "@bananapus/project-payer-v6/src/JBProjectPayerDeployer.sol";
import {IJBProjectPayer} from "@bananapus/project-payer-v6/src/interfaces/IJBProjectPayer.sol";

import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

/// @notice Fork test for the project-creation-fee flow that `Deploy.s.sol` wires up in
/// `_configureProjectCreationFee` after the `pay` flip. It proves that creating a project — via the controller
/// or the real revnet deployer — charges exactly `PROJECT_CREATION_FEE`, routes it into the fee project
/// (project 1) via `pay`, and mints project-1 tokens to the resolved FEE PAYER (the account that paid the fee,
/// threaded through `IJBPayerTracker`) rather than the new project's owner.
///
/// Exercises the full end-to-end chain across the published contracts: deployer/controller advertises the payer
/// -> `JBProjects.createFor` resolves it -> `JBProjectPayer` pays project 1 with the payer as beneficiary.
///
/// Run with: forge test --match-contract ProjectCreationFeeForkTest -vvv
contract ProjectCreationFeeForkTest is RevnetForkBase {
    /// @dev Matches `Deploy.s.sol` `PROJECT_CREATION_FEE`.
    uint256 internal constant PROJECT_CREATION_FEE = 0.0001 ether;

    /// @dev Matches `Deploy.s.sol` `_configureProjectCreationFee` default memo.
    string internal constant FEE_MEMO = "Project creation fee";

    uint32 internal constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));

    IJBProjectPayer internal _feeReceiver;

    function _deployerSalt() internal pure override returns (bytes32) {
        return keccak256("ProjectCreationFeeFork.v2");
    }

    function setUp() public override {
        super.setUp();

        // Stand up the fee project (project 1) as a native revnet (it issues tokens on `pay`).
        _deployFeeProject(0);

        // Configure the creation fee exactly as `Deploy.s.sol _configureProjectCreationFee` does after the flip:
        // a JBProjectPayer that PAYS project 1 with no fixed beneficiary, so the fee mints project-1 tokens to the
        // resolved fee payer instead of just topping up the balance.
        JBProjectPayerDeployer payerDeployer = new JBProjectPayerDeployer(jbDirectory());
        _feeReceiver = payerDeployer.deployProjectPayer({
            defaultProjectId: FEE_PROJECT_ID,
            defaultBeneficiary: payable(address(0)),
            defaultMemo: FEE_MEMO,
            defaultMetadata: "",
            defaultAddToBalance: false,
            owner: multisig()
        });

        vm.prank(multisig());
        jbProjects().setCreationFee(PROJECT_CREATION_FEE, payable(address(_feeReceiver)));

        // Precondition: the fee project must have a native-token terminal for the fee to route.
        require(
            address(jbDirectory().primaryTerminalOf(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN)) != address(0),
            "fee project has no native terminal"
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Tests
    // ─────────────────────────────────────────────────────────────────────

    /// @notice The deployed fee config routes via `pay` (not `addToBalanceOf`) with no fixed beneficiary.
    function test_creationFeeConfig_isPayRouting() public view {
        assertEq(jbProjects().creationFee(), PROJECT_CREATION_FEE, "creation fee mismatch");

        IJBProjectPayer payer = IJBProjectPayer(jbProjects().creationFeeReceiver());
        assertEq(payer.defaultProjectId(), FEE_PROJECT_ID, "payer not pointed at the fee project");
        assertFalse(payer.defaultAddToBalance(), "payer must use pay, not addToBalanceOf");
        assertEq(payer.defaultBeneficiary(), address(0), "beneficiary must be unset (resolves to the fee payer)");
        assertEq(keccak256(bytes(payer.defaultMemo())), keccak256(bytes(FEE_MEMO)), "fee memo mismatch");
    }

    /// @notice Via the controller: the fee payer — not the new project's owner — receives the project-1 tokens.
    function test_launchProjectFor_creditsFeePayerNotOwner() public {
        address payer = makeAddr("feePayer");
        address newOwner = makeAddr("newProjectOwner");
        vm.deal(payer, 1 ether);

        uint256 payerTokensBefore = jbTokens().totalBalanceOf(payer, FEE_PROJECT_ID);
        uint256 supplyBefore = jbTokens().totalSupplyOf(FEE_PROJECT_ID);
        uint256 feeProjectBalanceBefore = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        vm.prank(payer);
        uint256 newProjectId = jbController().launchProjectFor{value: PROJECT_CREATION_FEE}({
            owner: newOwner,
            projectUri: "ipfs://new-project",
            rulesetConfigurations: _minimalRulesets(),
            terminalConfigurations: _nativeTerminals(),
            memo: ""
        });

        assertEq(jbProjects().ownerOf(newProjectId), newOwner, "new project owner mismatch");

        // The fee payer received project-1 tokens; the new project's owner received none.
        assertGt(
            jbTokens().totalBalanceOf(payer, FEE_PROJECT_ID),
            payerTokensBefore,
            "fee payer did not receive project-1 tokens"
        );
        assertEq(
            jbTokens().totalBalanceOf(newOwner, FEE_PROJECT_ID), 0, "project owner wrongly received project-1 tokens"
        );

        // The fee minted project-1 tokens and reached project 1's treasury; the collector stranded nothing.
        assertGt(jbTokens().totalSupplyOf(FEE_PROJECT_ID), supplyBefore, "no project-1 tokens minted (pay path)");
        assertGt(
            _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN),
            feeProjectBalanceBefore,
            "fee did not reach project 1"
        );
        assertEq(address(_feeReceiver).balance, 0, "fee collector stranded funds");
    }

    /// @notice Via the revnet deployer (the real deploy sequence): the new revnet is owned by `REVOwner`, yet the
    /// account that called `deployFor` and paid the fee receives the project-1 tokens — proving the payer is
    /// threaded through the deployer -> `JBProjects` -> `JBProjectPayer` chain rather than crediting the owner.
    function test_revnetDeploy_creditsFeePayerNotRevnetOwner() public {
        address payer = makeAddr("revnetDeployer");
        vm.deal(payer, 1 ether);

        (REVConfig memory cfg, JBAccountingContext[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildNativeConfig(2000);
        cfg.description = REVDescription("PayerTest", "PT", "ipfs://pt", "PAYER_TEST_SALT");

        uint256 payerTokensBefore = jbTokens().totalBalanceOf(payer, FEE_PROJECT_ID);
        uint256 feeProjectBalanceBefore = _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN);

        vm.prank(payer);
        (uint256 newRevnetId,) = REV_DEPLOYER.deployFor{value: PROJECT_CREATION_FEE}({
            revnetId: 0, configuration: cfg, accountingContextsToAccept: tc, suckerDeploymentConfiguration: sdc
        });

        // The new revnet is owned by the protocol's `REVOwner`, not the payer.
        assertEq(jbProjects().ownerOf(newRevnetId), address(REV_OWNER), "new revnet not owned by REVOwner");

        // Yet the fee payer received the project-1 tokens, and project 1's treasury grew by the fee.
        assertGt(
            jbTokens().totalBalanceOf(payer, FEE_PROJECT_ID),
            payerTokensBefore,
            "fee payer did not receive project-1 tokens"
        );
        assertGt(
            _terminalBalance(FEE_PROJECT_ID, JBConstants.NATIVE_TOKEN),
            feeProjectBalanceBefore,
            "fee did not reach project 1"
        );
    }

    /// @notice Creation requires exactly the fee — under- or over-payment reverts in `JBController`.
    function test_creationFee_exactValueRequired() public {
        address payer = makeAddr("feePayer3");
        vm.deal(payer, 1 ether);

        vm.prank(payer);
        vm.expectRevert(
            abi.encodeWithSignature(
                "JBController_InvalidCreationFee(uint256,uint256)", PROJECT_CREATION_FEE - 1, PROJECT_CREATION_FEE
            )
        );
        jbController().launchProjectFor{value: PROJECT_CREATION_FEE - 1}({
            owner: payer,
            projectUri: "",
            rulesetConfigurations: _minimalRulesets(),
            terminalConfigurations: _nativeTerminals(),
            memo: ""
        });

        vm.prank(payer);
        vm.expectRevert(
            abi.encodeWithSignature(
                "JBController_InvalidCreationFee(uint256,uint256)", PROJECT_CREATION_FEE + 1, PROJECT_CREATION_FEE
            )
        );
        jbController().launchProjectFor{value: PROJECT_CREATION_FEE + 1}({
            owner: payer,
            projectUri: "",
            rulesetConfigurations: _minimalRulesets(),
            terminalConfigurations: _nativeTerminals(),
            memo: ""
        });
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Config builders
    // ─────────────────────────────────────────────────────────────────────

    function _minimalRulesets() internal view returns (JBRulesetConfig[] memory rulesets) {
        rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: uint48(block.timestamp),
            duration: 0,
            weight: 1e18,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: JBRulesetMetadata({
                reservedPercent: 0,
                cashOutTaxRate: 0,
                baseCurrency: NATIVE_CURRENCY,
                pausePay: false,
                pauseCreditTransfers: false,
                allowOwnerMinting: false,
                allowSetCustomToken: false,
                allowTerminalMigration: false,
                allowSetTerminals: false,
                allowSetController: false,
                allowAddAccountingContext: false,
                allowAddPriceFeed: false,
                ownerMustSendPayouts: false,
                holdFees: false,
                scopeCashOutsToLocalBalances: true,
                useDataHookForPay: false,
                useDataHookForCashOut: false,
                dataHook: address(0),
                metadata: 0
            }),
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });
    }

    function _nativeTerminals() internal view returns (JBTerminalConfig[] memory terminals) {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});

        terminals = new JBTerminalConfig[](1);
        terminals[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});
    }
}
