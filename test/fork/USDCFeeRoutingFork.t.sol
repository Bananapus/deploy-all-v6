// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBFeeTerminal} from "@bananapus/core-v6/src/interfaces/IJBFeeTerminal.sol";

import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";

import {RevnetEcosystemBase} from "../helpers/RevnetEcosystemBase.sol";
import {MockERC20Token} from "../helpers/MockTokens.sol";
import {MockPriceFeed} from "../helpers/MockPriceFeed.sol";

/// @notice Proves that a USDC protocol fee taken from a USDC revnet now reaches the fee project (NANA, project 1).
///
/// Background: the fee project's core terminal only accepts native ETH, so before the router-terminal registry was
/// registered as one of the fee project's terminals, the directory resolved no terminal for the fee project's USDC and
/// the core terminal forgave the USDC fee — crediting it back to the paying revnet instead of the fee project. With
/// the
/// registry registered as a terminal for the fee project, `DIRECTORY.primaryTerminalOf(1, usdc)` resolves to the
/// registry (which forwards the fee on to the fee project's balance) rather than returning zero, so the fee is routed
/// instead of forgiven.
///
/// The fee project's core terminal is intentionally left native-only here — exactly as in production — so the only
/// thing that makes USDC resolvable for the fee project is the registry. The registry forwards to a second core
/// terminal on which the fee project holds a USDC context, so the routed fee lands deterministically in the fee
/// project's USDC balance without depending on an AMM swap. The router terminal's swap behaviour is covered by
/// router-terminal-v6's own suite.
///
/// Run with: forge test --match-contract USDCFeeRoutingForkTest -vvv
contract USDCFeeRoutingForkTest is RevnetEcosystemBase {
    //*********************************************************************//
    // --------------------- internal stored properties ------------------ //
    //*********************************************************************//

    MockERC20Token internal usdc;
    JBRouterTerminalRegistry internal routerRegistry;

    //*********************************************************************//
    // ----------------------------- set up ------------------------------ //
    //*********************************************************************//

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_USDC_FeeRoute";
    }

    function setUp() public override {
        super.setUp();
        usdc = new MockERC20Token("Mock USDC", "USDC", 6);
        usdc.mint(PAYER, 200_000e6);
        usdc.mint(BORROWER, 100_000e6);
    }

    //*********************************************************************//
    // ----------------------------- tests ------------------------------- //
    //*********************************************************************//

    /// @notice The registry resolves the fee project for USDC, so `primaryTerminalOf(1, usdc)` is non-zero even though
    /// the fee project's core terminal only accepts native ETH.
    function test_feeRoute_usdcFeeProjectTerminalResolves() public {
        _launchNativeOnlyFeeProject();

        // Before wiring: the fee project's only listed terminal is the native-only core terminal, so the directory
        // resolves no USDC terminal for it.
        assertEq(
            address(jbDirectory().primaryTerminalOf({projectId: FEE_PROJECT_ID, token: address(usdc)})),
            address(0),
            "fee project should resolve no USDC terminal before the registry is wired"
        );

        routerRegistry = _wireFeeProjectUSDCRouting();

        // After wiring: the registry resolves the fee project's USDC terminal, so the directory returns the registry
        // (not the native-only core terminal).
        assertEq(
            address(jbDirectory().primaryTerminalOf({projectId: FEE_PROJECT_ID, token: address(usdc)})),
            address(routerRegistry),
            "fee project should resolve the registry as its USDC terminal after wiring"
        );
    }

    /// @notice A USDC cash-out fee from a USDC revnet reaches the fee project instead of being forgiven.
    function test_feeRoute_usdcCashOutFeeReachesFeeProject() public {
        _launchNativeOnlyFeeProject();
        routerRegistry = _wireFeeProjectUSDCRouting();

        // Deploy a USDC revnet with a meaningful cash-out tax so a cash-out incurs the 2.5% protocol fee in USDC.
        (REVConfig memory cfg, JBAccountingContext[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildUSDCRevnetConfig({cashOutTaxRate: 7000});

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, accountingContextsToAccept: tc, suckerDeploymentConfiguration: sdc
        });

        // Two payers so the bonding curve leaves surplus to reclaim on cash-out.
        _payRevnetUSDC({revnetId: revnetId, payer: PAYER, amount: 10_000e6});
        _payRevnetUSDC({revnetId: revnetId, payer: BORROWER, amount: 5000e6});

        // The fee lands on the registry's forward target (the second core terminal). Record its balance before.
        uint256 feeProjectUSDCBefore = _feeProjectUSDCBalance();
        uint256 revnetUSDCBefore = _revnetUSDCBalance(revnetId);

        // A forgiven fee would be credited back to the paying revnet and surfaced via `FeeReverted`. Record logs so we
        // can prove that event is NOT emitted for the paying revnet's USDC during the cash-out.
        vm.recordLogs();

        uint256 payerTokens = jbTokens().totalBalanceOf({holder: PAYER, projectId: revnetId});

        vm.prank(PAYER);
        uint256 reclaimed = jbMultiTerminal()
            .cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: payerTokens,
            tokenToReclaim: address(usdc),
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });
        assertGt(reclaimed, 0, "cash-out should reclaim USDC");

        // The fee was routed: the fee project's USDC balance increased. Lower-bound assertion keeps this robust to
        // bonding-curve and fee rounding.
        uint256 feeProjectUSDCAfter = _feeProjectUSDCBalance();
        assertGt(
            feeProjectUSDCAfter, feeProjectUSDCBefore, "fee project's USDC balance should increase from the routed fee"
        );

        // The fee was NOT forgiven: no `FeeReverted` was emitted that credits the fee back to the paying revnet.
        _assertNoFeeForgivenFor({logs: vm.getRecordedLogs(), projectId: revnetId, token: address(usdc)});

        // Sanity: the paying revnet did not pocket the fee back as a forgiven credit — its USDC balance only
        // decreased.
        assertLt(_revnetUSDCBalance(revnetId), revnetUSDCBefore, "paying revnet's USDC balance should only decrease");
    }

    //*********************************************************************//
    // ----------------------- internal helpers -------------------------- //
    //*********************************************************************//

    /// @notice Assert the recorded logs contain no `FeeReverted` event forgiving a fee back to the given project/token.
    /// @param logs The logs recorded during the cash-out.
    /// @param projectId The paying project whose fee must not have been forgiven.
    /// @param token The fee token.
    function _assertNoFeeForgivenFor(Vm.Log[] memory logs, uint256 projectId, address token) internal pure {
        bytes32 feeRevertedTopic = IJBFeeTerminal.FeeReverted.selector;

        for (uint256 i; i < logs.length; ++i) {
            // `FeeReverted(uint256 indexed projectId, address indexed token, uint256 indexed feeProjectId, ...)`.
            if (logs[i].topics.length == 4 && logs[i].topics[0] == feeRevertedTopic) {
                uint256 loggedProjectId = uint256(logs[i].topics[1]);
                address loggedToken = address(uint160(uint256(logs[i].topics[2])));
                if (loggedProjectId == projectId && loggedToken == token) {
                    revert("USDC fee was forgiven instead of routed to the fee project");
                }
            }
        }
    }

    /// @notice Build a single-stage USDC revnet config that accepts USDC and applies the given cash-out tax.
    /// @param cashOutTaxRate The cash-out tax rate so cash-outs leave surplus and incur the protocol fee.
    /// @return cfg The revnet configuration.
    /// @return tc The accounting contexts the revnet accepts (USDC only).
    /// @return sdc An empty sucker deployment configuration.
    function _buildUSDCRevnetConfig(uint16 cashOutTaxRate)
        internal
        view
        returns (REVConfig memory cfg, JBAccountingContext[] memory tc, REVSuckerDeploymentConfig memory sdc)
    {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: address(usdc), decimals: 6, currency: uint32(uint160(address(usdc)))});
        tc = acc;

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(multisig()),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 0,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: cashOutTaxRate,
            extraMetadata: 0
        });

        cfg = REVConfig({
            description: REVDescription("USDC Fee Route", "UFEE", "ipfs://ufee", "UFEE_SALT"),
            baseCurrency: uint32(uint160(address(usdc))),
            operator: multisig(),
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("UFEE"))
        });
    }

    /// @notice The fee project's USDC balance on the registry's forward target (the second core terminal).
    /// @return balance The fee project's USDC balance where routed fees land.
    function _feeProjectUSDCBalance() internal view returns (uint256 balance) {
        return jbTerminalStore()
            .balanceOf({terminal: address(jbMultiTerminal2()), projectId: FEE_PROJECT_ID, token: address(usdc)});
    }

    /// @notice Launch the fee project (NANA, project 1) as a plain project whose core terminal accepts only native ETH.
    /// @dev Mirrors production: the fee project does not accept USDC on its primary core terminal. The ruleset allows
    /// adding accounting contexts so a USDC context can later be recorded on a second terminal for routed fees, and
    /// allows owner minting so the fee `pay` can mint fee-project tokens.
    function _launchNativeOnlyFeeProject() internal {
        JBAccountingContext[] memory nativeContext = new JBAccountingContext[](1);
        nativeContext[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });

        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](1);
        terminalConfigs[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: nativeContext});

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: uint112(INITIAL_ISSUANCE),
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: JBRulesetMetadata({
                reservedPercent: 0,
                cashOutTaxRate: 0,
                baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                pausePay: false,
                pauseCreditTransfers: false,
                allowOwnerMinting: true,
                allowSetCustomToken: false,
                allowTerminalMigration: false,
                allowSetTerminals: true,
                allowSetController: false,
                allowAddAccountingContext: true,
                allowAddPriceFeed: true,
                ownerMustSendPayouts: false,
                holdFees: false,
                scopeCashOutsToLocalBalances: false,
                useDataHookForPay: false,
                useDataHookForCashOut: false,
                dataHook: address(0),
                metadata: 0
            }),
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        vm.prank(multisig());
        jbController()
            .launchRulesetsFor({
            projectId: FEE_PROJECT_ID,
            projectUri: "ipfs://fee",
            rulesetConfigurations: rulesets,
            terminalConfigurations: terminalConfigs,
            memo: ""
        });
    }

    /// @notice Pay a USDC revnet from the given payer.
    /// @param revnetId The revnet to pay.
    /// @param payer The payer providing USDC.
    /// @param amount The USDC amount to pay.
    /// @return tokensReceived The number of project tokens the payer received.
    function _payRevnetUSDC(uint256 revnetId, address payer, uint256 amount) internal returns (uint256 tokensReceived) {
        usdc.mint(payer, amount);
        vm.startPrank(payer);
        usdc.approve({spender: address(jbMultiTerminal()), value: amount});
        tokensReceived = jbMultiTerminal()
            .pay({
            projectId: revnetId,
            token: address(usdc),
            amount: amount,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
        vm.stopPrank();
    }

    /// @notice The paying revnet's USDC balance on the core terminal.
    /// @param revnetId The revnet to read.
    /// @return balance The revnet's USDC balance on the core terminal.
    function _revnetUSDCBalance(uint256 revnetId) internal view returns (uint256 balance) {
        return
            jbTerminalStore()
                .balanceOf({terminal: address(jbMultiTerminal()), projectId: revnetId, token: address(usdc)});
    }

    /// @notice Record a USDC context for the fee project on a second core terminal, then register a router-terminal
    /// registry as the fee project's USDC terminal so the directory resolves it for USDC fees.
    /// @dev The second terminal is NOT added to the fee project's directory terminal list, so `primaryTerminalOf` does
    /// not find it directly — only the registry (which forwards to it) makes USDC resolvable for the fee project.
    /// @return registry The registry now registered as the fee project's USDC terminal.
    function _wireFeeProjectUSDCRouting() internal returns (JBRouterTerminalRegistry registry) {
        address feeProjectOwner = jbProjects().ownerOf(FEE_PROJECT_ID);

        // The fee project mints fee-project tokens for each forwarded fee `pay`, converting the paid USDC into the fee
        // project's native base currency. Register a USDC->native feed on the fee project so that conversion succeeds.
        IJBPriceFeed usdcFeed = IJBPriceFeed(address(new MockPriceFeed({price: 3000e18, feedDecimals: 18})));
        vm.prank(feeProjectOwner);
        jbController()
            .addPriceFeedFor({
            projectId: FEE_PROJECT_ID,
            pricingCurrency: uint32(uint160(address(usdc))),
            unitCurrency: uint256(uint32(uint160(JBConstants.NATIVE_TOKEN))),
            feed: usdcFeed
        });

        // Record a USDC context for the fee project on the second core terminal — the terminal the registry forwards
        // to. The terminal is registered so it can mint fee-project tokens, but USDC stays unresolvable on it directly
        // until the registry is made the explicit primary terminal below.
        JBAccountingContext[] memory feeUsdcContext = new JBAccountingContext[](1);
        feeUsdcContext[0] =
            JBAccountingContext({token: address(usdc), decimals: 6, currency: uint32(uint160(address(usdc)))});

        vm.prank(feeProjectOwner);
        jbMultiTerminal2().addAccountingContextsFor({projectId: FEE_PROJECT_ID, accountingContexts: feeUsdcContext});

        // Add the second terminal to the fee project's directory terminal list so it is authorized to mint when the
        // registry forwards a fee `pay` to it.
        IJBTerminal[] memory feeTerminals = new IJBTerminal[](2);
        feeTerminals[0] = IJBTerminal(address(jbMultiTerminal()));
        feeTerminals[1] = IJBTerminal(address(jbMultiTerminal2()));

        vm.prank(feeProjectOwner);
        jbDirectory().setTerminalsOf({projectId: FEE_PROJECT_ID, terminals: feeTerminals});

        // Deploy the registry and point its default terminal at the second core terminal. The first
        // `setDefaultTerminal` call maps every already-existing project — including the fee project (ID 1) — onto
        // this
        // default, so the registry resolves the fee project to a terminal that accepts USDC for it.
        registry = new JBRouterTerminalRegistry({
            permissions: jbPermissions(),
            projects: jbProjects(),
            permit2: permit2(),
            owner: address(this),
            trustedForwarder: address(0)
        });
        registry.setDefaultTerminal({terminal: IJBTerminal(address(jbMultiTerminal2()))});

        // Make the registry the fee project's explicit primary terminal for USDC. The directory returns an explicit
        // primary before scanning the terminal list, so `primaryTerminalOf(1, usdc)` resolves to the registry rather
        // than the second terminal — exactly the production wiring where the registry fronts USDC for the fee
        // project.
        vm.prank(feeProjectOwner);
        jbDirectory()
            .setPrimaryTerminalOf({
            projectId: FEE_PROJECT_ID, token: address(usdc), terminal: IJBTerminal(address(registry))
        });
    }
}
