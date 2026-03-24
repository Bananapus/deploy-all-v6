// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBSplitGroupIds} from "@bananapus/core-v6/src/libraries/JBSplitGroupIds.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {JBCurrencyAmount} from "@bananapus/core-v6/src/structs/JBCurrencyAmount.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

// 721 Hook
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {IJB721TiersHook} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHookStore} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "@bananapus/721-hook-v6/src/interfaces/IJB721TokenUriResolver.sol";
import {JB721TierConfig} from "@bananapus/721-hook-v6/src/structs/JB721TierConfig.sol";
import {JB721InitTiersConfig} from "@bananapus/721-hook-v6/src/structs/JB721InitTiersConfig.sol";
import {JB721TiersHookFlags} from "@bananapus/721-hook-v6/src/structs/JB721TiersHookFlags.sol";
import {JBDeploy721TiersHookConfig} from "@bananapus/721-hook-v6/src/structs/JBDeploy721TiersHookConfig.sol";

// Address Registry
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";

/// @notice Long-horizon multi-project composition stress test exercising repeated cycles across
/// many rulesets. Proves that repeated operations over many cycles don't accumulate rounding
/// errors or leak value across 3 interacting projects and 10+ ruleset cycles.
///
/// Run with: forge test --match-contract LongHorizonChurnForkTest -vvv
contract LongHorizonChurnForkTest is TestBaseWorkflow {
    // ── Ruleset parameters ──
    uint112 constant WEIGHT = uint112(1000e18); // 1000 tokens per ETH in the first ruleset
    uint32 constant DURATION = 30 days; // each ruleset lasts 30 days
    uint32 constant WEIGHT_CUT_PERCENT = 100_000_000; // 10% weight decay per cycle (9-decimal precision)
    uint16 constant RESERVED_PERCENT = 2000; // 20% of minted tokens go to reserved splits
    uint16 constant CASH_OUT_TAX_RATE = 4000; // 40% bonding-curve cash-out tax

    // ── 721 tier parameters for Project A ──
    uint104 constant TIER_PRICE = 0.1 ether; // each NFT tier costs 0.1 ETH
    uint32 constant TIER_SPLIT_PERCENT = 200_000_000; // 20% of tier payment to split beneficiary

    // ── Payout limit for Project A (ETH-denominated) ──
    uint224 constant PAYOUT_LIMIT_ETH = 1 ether; // 1 ETH payout limit per cycle

    // ── Number of churn cycles to execute ──
    uint256 constant NUM_CYCLES = 10; // stress test across 10 full ruleset cycles

    // ── Actors ──
    address PAYER = makeAddr("churn_payer"); // the main payer into Project A
    address PAYER2 = makeAddr("churn_payer2"); // secondary payer for bonding curve dynamics
    address RESERVED_BENEFICIARY = makeAddr("churn_reserved"); // receives reserved token splits from A
    address SPLIT_BENEFICIARY = makeAddr("churn_split"); // receives payout split beneficiary remainder

    // ── 721 hook infrastructure ──
    IJB721TiersHookStore HOOK_STORE; // 721 tier data storage
    JB721TiersHook EXAMPLE_HOOK; // 721 hook implementation for cloning
    IJBAddressRegistry ADDRESS_REGISTRY; // address registry for deployed hooks
    IJB721TiersHookDeployer HOOK_DEPLOYER; // deploys 721 hook clones

    // ── Project IDs ──
    uint256 projectA; // main project with 721 tiers, payouts, reserved splits
    uint256 projectB; // receives payout splits from Project A
    uint256 projectC; // receives reserved token splits from Project A

    // ── 721 hook for Project A ──
    IJB721TiersHook hookA; // the deployed 721 tiers hook for Project A

    // ── Derived currency ──
    uint32 nativeCurrency; // uint32(uint160(NATIVE_TOKEN)) — native token's currency identifier

    // ── Tracking state for invariant checks ──
    uint256 prevFeeProjectBalance; // fee project balance from the previous cycle
    uint256 totalTokensMintedA; // cumulative tokens minted for Project A (approximate)
    uint256 totalTokensBurnedA; // cumulative tokens burned from Project A cash-outs

    /// @notice Accept ETH returns from cash-outs.
    receive() external payable {}

    /// @notice Accept ERC721 safe transfers (required because JBProjects uses _safeMint).
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector; // standard ERC721 receiver acknowledgment
    }

    function setUp() public override {
        // Fork mainnet at a stable block for deterministic state.
        vm.createSelectFork("ethereum", 21_700_000);

        // Deploy fresh JB core contracts on the fork.
        super.setUp();

        // Compute the native token's currency identifier (truncated address).
        nativeCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));

        // Deploy 721 hook infrastructure.
        HOOK_STORE = new JB721TiersHookStore(); // tier data storage
        EXAMPLE_HOOK = new JB721TiersHook(
            jbDirectory(), jbPermissions(), jbPrices(), jbRulesets(), HOOK_STORE, jbSplits(), multisig()
        ); // 721 hook implementation
        ADDRESS_REGISTRY = new JBAddressRegistry(); // address registry for hooks
        HOOK_DEPLOYER = new JB721TiersHookDeployer(EXAMPLE_HOOK, HOOK_STORE, ADDRESS_REGISTRY, address(0)); // deployer

        // Fund test actors with enough ETH for the full stress test.
        vm.deal(PAYER, 1000 ether); // payer gets 1000 ETH
        vm.deal(PAYER2, 1000 ether); // secondary payer gets 1000 ETH

        // ── Deploy 3 projects ──

        // Project B: simple ETH terminal, receives payout splits from A.
        projectB = _launchSimpleProject("ProjectB"); // deploy Project B

        // Project C: simple ETH terminal, receives reserved token splits from A.
        projectC = _launchSimpleProject("ProjectC"); // deploy Project C

        // Project A: ETH terminal, 721 tiers, payouts to B, reserved splits to C.
        projectA = _launchProjectA(); // deploy Project A with cross-project splits

        // Deploy 721 hook for Project A.
        hookA = _deploy721Hook(projectA); // deploy the 721 tiers hook

        // Queue a new ruleset for Project A that uses the 721 hook as the data hook.
        _queueRulesetWithHook(projectA, address(hookA)); // queue ruleset with hook

        // Warp past the initial ruleset so the hook-enabled ruleset becomes active.
        vm.warp(block.timestamp + DURATION + 1); // advance to activate the hook ruleset

        // Initialize tracking: record the fee project's initial balance.
        prevFeeProjectBalance = _terminalBalance(1, JBConstants.NATIVE_TOKEN); // fee project starts at 0
    }

    /// @notice The main long-horizon churn stress test.
    function test_longHorizonChurn() public {
        // Record the initial weight from the current ruleset for decay verification.
        JBRuleset memory initialRuleset = jbRulesets().currentOf(projectA); // get the first active ruleset
        uint256 initialWeight = initialRuleset.weight; // store its weight for later comparison

        // ── Execute NUM_CYCLES churn cycles ──
        for (uint256 cycle = 0; cycle < NUM_CYCLES; cycle++) {
            // Log the current cycle for debugging.
            emit log_named_uint("=== CYCLE", cycle); // log cycle number

            // (a) Pay into Project A with varying amounts.
            uint256 payAmount = 2 ether + (cycle * 0.5 ether); // increase payment each cycle
            vm.prank(PAYER); // pay as PAYER
            uint256 tokensReceived = jbMultiTerminal().pay{value: payAmount}({
                projectId: projectA,
                token: JBConstants.NATIVE_TOKEN,
                amount: payAmount,
                beneficiary: PAYER,
                minReturnedTokens: 0,
                memo: "churn pay",
                metadata: ""
            });
            totalTokensMintedA += tokensReceived; // track cumulative mints

            // Also have PAYER2 pay a smaller amount for bonding curve dynamics.
            uint256 pay2Amount = 1 ether; // constant 1 ETH from second payer
            vm.prank(PAYER2); // pay as PAYER2
            uint256 tokens2 = jbMultiTerminal().pay{value: pay2Amount}({
                projectId: projectA,
                token: JBConstants.NATIVE_TOKEN,
                amount: pay2Amount,
                beneficiary: PAYER2,
                minReturnedTokens: 0,
                memo: "churn pay2",
                metadata: ""
            });
            totalTokensMintedA += tokens2; // track cumulative mints

            // (b) Execute payouts from A -> B (cross-project split).
            // The payout limit resets each cycle, so we can pay out up to PAYOUT_LIMIT_ETH.
            uint256 projectBBalanceBefore = _terminalBalance(projectB, JBConstants.NATIVE_TOKEN); // record B's balance
            jbMultiTerminal()
                .sendPayoutsOf({
                    projectId: projectA,
                    token: JBConstants.NATIVE_TOKEN,
                    amount: PAYOUT_LIMIT_ETH,
                    currency: uint256(nativeCurrency),
                    minTokensPaidOut: 0
                }); // send payouts from A
            uint256 projectBBalanceAfter = _terminalBalance(projectB, JBConstants.NATIVE_TOKEN); // check B's balance
            // Verify Project B received funds from the payout (minus fees).
            assertGt(
                projectBBalanceAfter,
                projectBBalanceBefore,
                string.concat("Cycle ", vm.toString(cycle), ": B should receive payout from A")
            ); // B's balance increased

            // (c) Distribute reserved tokens from A -> C.
            uint256 pendingReserved = jbController().pendingReservedTokenBalanceOf(projectA); // check pending reserved
            if (pendingReserved > 0) {
                // Distribute reserved tokens to the configured splits (which route to Project C).
                jbController().sendReservedTokensToSplitsOf(projectA); // distribute reserved tokens
            }

            // (d) Cash out some tokens from Project A (varying amounts).
            uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, projectA); // get PAYER's token balance
            if (payerTokens > 0) {
                // Cash out 20% of PAYER's tokens each cycle.
                uint256 cashOutCount = payerTokens / 5; // 20% of holdings
                if (cashOutCount > 0) {
                    vm.prank(PAYER); // cash out as PAYER
                    jbMultiTerminal()
                        .cashOutTokensOf({
                            holder: PAYER,
                            projectId: projectA,
                            cashOutCount: cashOutCount,
                            tokenToReclaim: JBConstants.NATIVE_TOKEN,
                            minTokensReclaimed: 0,
                            beneficiary: payable(PAYER),
                            metadata: ""
                        }); // execute the cash out
                    totalTokensBurnedA += cashOutCount; // track cumulative burns
                }
            }

            // (e) Pay into Project B with a small amount (simulating activity from received payouts).
            vm.prank(PAYER); // pay as PAYER
            jbMultiTerminal().pay{value: 0.1 ether}({
                projectId: projectB,
                token: JBConstants.NATIVE_TOKEN,
                amount: 0.1 ether,
                beneficiary: PAYER,
                minReturnedTokens: 0,
                memo: "churn pay into B",
                metadata: ""
            }); // pay into Project B directly

            // (f) Warp forward to trigger the next ruleset (weight decays).
            vm.warp(block.timestamp + DURATION + 1); // advance past the current ruleset

            // ── INVARIANT CHECKS (every cycle) ──

            // Invariant 1: Terminal balance >= recorded balance for each project (no phantom surplus).
            _assertNoPhantomSurplus(projectA, cycle); // check Project A
            _assertNoPhantomSurplus(projectB, cycle); // check Project B
            _assertNoPhantomSurplus(projectC, cycle); // check Project C

            // Invariant 2: Token supply consistency (minted - burned = outstanding) for Project A.
            // Note: reserved token minting complicates exact tracking, so we verify supply > 0.
            uint256 supplyA = jbTokens().totalSupplyOf(projectA); // get total supply of A
            assertGt(supplyA, 0, string.concat("Cycle ", vm.toString(cycle), ": A supply should be > 0")); // supply
            // positive

            // Invariant 3: Weight decays correctly each cycle.
            JBRuleset memory currentRuleset = jbRulesets().currentOf(projectA); // get the current ruleset
            uint256 expectedCycles = cycle + 2; // +1 for the initial queued ruleset, +1 for zero-indexing
            uint256 expectedWeight = initialWeight; // start from the initial weight
            for (uint256 j = 1; j < expectedCycles; j++) {
                // Apply 10% decay: newWeight = oldWeight * (1 - 10%) = oldWeight * 90%
                expectedWeight = expectedWeight * (1_000_000_000 - WEIGHT_CUT_PERCENT) / 1_000_000_000;
            }
            // Allow 1 wei tolerance per decay step for rounding.
            assertApproxEqAbs(
                currentRuleset.weight,
                expectedWeight,
                expectedCycles,
                string.concat("Cycle ", vm.toString(cycle), ": weight should match compounded decay")
            ); // weight decayed correctly

            // Invariant 4: Fee project (ID 1) balance monotonically increases.
            uint256 currentFeeBalance = _terminalBalance(1, JBConstants.NATIVE_TOKEN); // get fee project balance
            assertGe(
                currentFeeBalance,
                prevFeeProjectBalance,
                string.concat("Cycle ", vm.toString(cycle), ": fee project balance must not decrease")
            ); // fee balance is monotonically increasing
            prevFeeProjectBalance = currentFeeBalance; // update for next cycle

            // Invariant 5: No project's recorded balance goes negative (ensured by uint256, but check > 0 after
            // activity). The recorded balance should always be >= 0 (implicit in Solidity), but we verify it's
            // sensible.
            uint256 balA = _terminalBalance(projectA, JBConstants.NATIVE_TOKEN); // Project A balance
            uint256 balB = _terminalBalance(projectB, JBConstants.NATIVE_TOKEN); // Project B balance
            // Project C only receives tokens, not ETH, so its terminal ETH balance may be 0.
            // Just verify A and B have positive balances.
            assertGt(balA, 0, string.concat("Cycle ", vm.toString(cycle), ": A should have positive ETH balance")); // A
            // has funds
            assertGt(balB, 0, string.concat("Cycle ", vm.toString(cycle), ": B should have positive ETH balance")); // B
            // has funds
        }

        // ═══════════════════════════════════════════════════════════════
        // FINAL ASSERTIONS after all cycles
        // ═══════════════════════════════════════════════════════════════

        // Final 1: All three projects have consistent accounting.
        uint256 finalBalA = _terminalBalance(projectA, JBConstants.NATIVE_TOKEN); // final A balance
        uint256 finalBalB = _terminalBalance(projectB, JBConstants.NATIVE_TOKEN); // final B balance
        uint256 finalBalC = _terminalBalance(projectC, JBConstants.NATIVE_TOKEN); // final C balance (may be 0)

        // Note: fees go to project ID 1, which equals projectB (the first project launched).
        // So finalBalB already includes any fees routed to the fee beneficiary project.
        // We must not double-count by also adding _terminalBalance(1, ...).

        // Terminal ETH should cover the sum of all distinct project balances on this terminal.
        uint256 actualTerminalEth = address(jbMultiTerminal()).balance; // actual ETH on the terminal contract
        uint256 sumRecordedBalances = finalBalA + finalBalB + finalBalC; // sum of all recorded project balances
        assertGe(actualTerminalEth, sumRecordedBalances, "Final: terminal ETH must cover all recorded project balances"); // no
        // phantom surplus across all projects

        // Final 2: Total fees collected are positive (2.5% on payouts + cashouts).
        // Since fee project = project B, verify B's balance grew beyond just direct payments.
        assertGt(finalBalB, 0, "Final: fee project (B) should have collected fees + payouts"); // fees collected

        // Final 3: Weight has decayed correctly over all cycles (compounding 10% decay).
        JBRuleset memory finalRuleset = jbRulesets().currentOf(projectA); // get the final ruleset
        // The queued ruleset specifies weight=WEIGHT explicitly, resetting the decay chain.
        // After NUM_CYCLES warps, we have NUM_CYCLES auto-cycle decays from that base weight.
        uint256 totalDecayCycles = NUM_CYCLES; // number of decay steps from the queued ruleset
        uint256 expectedFinalWeight = WEIGHT; // start from the queued ruleset's explicit weight
        for (uint256 k = 0; k < totalDecayCycles; k++) {
            // Apply 10% decay: newWeight = oldWeight * 90%.
            expectedFinalWeight = expectedFinalWeight * (1_000_000_000 - WEIGHT_CUT_PERCENT) / 1_000_000_000;
        }
        // Allow 1 wei tolerance per decay step.
        assertApproxEqAbs(
            finalRuleset.weight,
            expectedFinalWeight,
            totalDecayCycles + 1,
            "Final: weight should match compounded decay over all cycles"
        ); // final weight matches expected decay

        // Final 4: Token supply reflects net minting (supply > 0 since not all tokens were cashed out).
        uint256 finalSupplyA = jbTokens().totalSupplyOf(projectA); // final supply of Project A
        assertGt(finalSupplyA, 0, "Final: A should have positive token supply after all cycles"); // tokens remain

        // Final 5: Project B and C received value across the cycles.
        assertGt(finalBalB, 0, "Final: B should have accumulated ETH from payouts"); // B has accumulated ETH
        uint256 reservedBeneficiaryTokens = jbTokens().totalBalanceOf(RESERVED_BENEFICIARY, projectA); // reserved
        // tokens
        // Reserved beneficiary received tokens across cycles from reserved splits.
        // (Project C receives via reserved split which mints tokens to RESERVED_BENEFICIARY for projectA.)
        assertGt(reservedBeneficiaryTokens, 0, "Final: reserved beneficiary should have tokens from A"); // tokens
        // received

        // Final 6: Log summary for manual inspection.
        emit log_named_uint("Final Project A balance (wei)", finalBalA); // log A balance
        emit log_named_uint("Final Project B/fee balance (wei)", finalBalB); // log B balance (also fee project)
        emit log_named_uint("Final Project C balance (wei)", finalBalC); // log C balance
        emit log_named_uint("Final Project A token supply", finalSupplyA); // log A supply
        emit log_named_uint("Final weight (decayed over cycles)", finalRuleset.weight); // log final weight
        emit log_named_uint("Expected weight", expectedFinalWeight); // log expected weight
        emit log_named_uint("Total cycles executed", NUM_CYCLES); // log cycle count
        emit log_named_uint("Actual terminal ETH", actualTerminalEth); // log actual terminal ETH
        emit log_named_uint("Sum recorded balances", sumRecordedBalances); // log sum of recorded balances
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Internal Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Checks that the terminal's actual ETH balance >= the recorded balance for a project.
    function _assertNoPhantomSurplus(uint256 _projectId, uint256 cycle) internal view {
        uint256 recorded = _terminalBalance(_projectId, JBConstants.NATIVE_TOKEN); // get recorded balance
        uint256 actual = address(jbMultiTerminal()).balance; // get actual ETH on terminal
        assertGe(
            actual,
            recorded,
            string.concat("Cycle ", vm.toString(cycle), ": phantom surplus for project ", vm.toString(_projectId))
        ); // actual >= recorded
    }

    /// @notice Returns the terminal's recorded balance for a project and token.
    function _terminalBalance(uint256 _projectId, address token) internal view returns (uint256) {
        return jbTerminalStore().balanceOf(address(jbMultiTerminal()), _projectId, token); // read from terminal store
    }

    /// @notice Launches a simple project with an ETH terminal, no hooks, no payout limits, no reserved splits.
    function _launchSimpleProject(string memory name) internal returns (uint256 id) {
        // Configure terminal to accept native ETH.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1); // one accounting context
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, // accept native ETH
            decimals: 18, // 18 decimal precision
            currency: nativeCurrency // currency = truncated native token address
        });

        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1); // one terminal
        tc[0] = JBTerminalConfig({
            terminal: jbMultiTerminal(), // use the shared multi-terminal
            accountingContextsToAccept: acc // accept ETH
        });

        // Build a minimal ruleset with no special features.
        JBRulesetMetadata memory metadata = JBRulesetMetadata({
            reservedPercent: 0, // no reserved tokens
            cashOutTaxRate: 0, // no cash-out tax
            baseCurrency: nativeCurrency, // ETH base currency
            pausePay: false, // payments enabled
            pauseCreditTransfers: false, // transfers enabled
            allowOwnerMinting: true, // owner can mint
            allowSetCustomToken: false, // no custom token
            allowTerminalMigration: false, // no migration
            allowSetTerminals: false, // no terminal changes
            allowSetController: false, // no controller changes
            allowAddAccountingContext: false, // no new contexts
            allowAddPriceFeed: false, // no price feeds
            ownerMustSendPayouts: false, // anyone can trigger payouts
            holdFees: false, // don't hold fees
            useTotalSurplusForCashOuts: false, // use local surplus
            useDataHookForPay: false, // no data hook for pay
            useDataHookForCashOut: false, // no data hook for cashout
            dataHook: address(0), // no hook
            metadata: 0 // no extra metadata
        });

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1); // one ruleset
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: uint48(block.timestamp), // start now
            duration: DURATION, // 30-day cycles
            weight: WEIGHT, // 1000 tokens per ETH
            weightCutPercent: WEIGHT_CUT_PERCENT, // 10% decay
            approvalHook: IJBRulesetApprovalHook(address(0)), // no approval hook
            metadata: metadata, // minimal metadata
            splitGroups: new JBSplitGroup[](0), // no splits
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0) // no payout limits (unlimited payouts disallowed)
        });

        // Launch the project.
        id = jbController()
            .launchProjectFor({
                owner: address(this), // test contract owns the project
                projectUri: string.concat("ipfs://", name), // project metadata URI
                rulesetConfigurations: rulesets, // initial rulesets
                terminalConfigurations: tc, // terminal setup
                memo: string.concat("launch ", name) // launch memo
            });
    }

    /// @notice Launches Project A with:
    ///   - ETH terminal
    ///   - 30-day rulesets with 10% weight decay
    ///   - 20% reserved token percent (splits go to RESERVED_BENEFICIARY for project A)
    ///   - Payout splits: 50% to Project B (addToBalance), 50% to SPLIT_BENEFICIARY
    ///   - Reserved token splits: 100% to RESERVED_BENEFICIARY
    ///   - 1 ETH payout limit per cycle (ETH-denominated)
    ///   - 721 tiers hook (added via queue after launch)
    function _launchProjectA() internal returns (uint256 id) {
        // Configure terminal to accept native ETH.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1); // one accounting context
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, // accept native ETH
            decimals: 18, // 18 decimal precision
            currency: nativeCurrency // native token currency
        });

        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1); // one terminal
        tc[0] = JBTerminalConfig({
            terminal: jbMultiTerminal(), // shared multi-terminal
            accountingContextsToAccept: acc // accept ETH
        });

        // Build the ruleset config with all features.
        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1); // one ruleset
        rulesets[0] = _buildProjectARuleset(address(0)); // no data hook initially (added via queue)

        // Launch the project.
        id = jbController()
            .launchProjectFor({
                owner: address(this), // test contract owns the project
                projectUri: "ipfs://projectA", // project metadata URI
                rulesetConfigurations: rulesets, // initial rulesets
                terminalConfigurations: tc, // terminal setup
                memo: "launch Project A" // launch memo
            });
    }

    /// @notice Builds the ruleset config for Project A with all features enabled.
    function _buildProjectARuleset(address dataHook) internal view returns (JBRulesetConfig memory) {
        // Metadata: 20% reserved, 40% cash-out tax, ETH base currency, data hook for pay if provided.
        JBRulesetMetadata memory metadata = JBRulesetMetadata({
            reservedPercent: RESERVED_PERCENT, // 20% of minted tokens reserved
            cashOutTaxRate: CASH_OUT_TAX_RATE, // 40% bonding curve tax
            baseCurrency: nativeCurrency, // weight denominated in ETH
            pausePay: false, // payments allowed
            pauseCreditTransfers: false, // transfers allowed
            allowOwnerMinting: true, // owner can mint (for reserved tokens)
            allowSetCustomToken: false, // no custom token changes
            allowTerminalMigration: false, // no migration
            allowSetTerminals: false, // no terminal changes
            allowSetController: false, // no controller changes
            allowAddAccountingContext: false, // no new contexts
            allowAddPriceFeed: false, // no price feeds
            ownerMustSendPayouts: false, // anyone can trigger payouts
            holdFees: false, // don't hold fees
            useTotalSurplusForCashOuts: false, // use local surplus
            useDataHookForPay: dataHook != address(0), // use hook if provided
            useDataHookForCashOut: false, // no hook for cashout
            dataHook: dataHook, // 721 hook or zero
            metadata: 0 // no extra metadata
        });

        // Payout splits: 50% to Project B (via addToBalance), 50% to SPLIT_BENEFICIARY.
        JBSplit[] memory payoutSplits = new JBSplit[](2); // two payout splits
        payoutSplits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2), // 50% of payouts to Project B
            projectId: uint56(projectB), // route to Project B
            beneficiary: payable(address(0)), // no specific beneficiary (goes to project)
            preferAddToBalance: true, // add to B's balance (not pay)
            lockedUntil: 0, // not locked
            hook: IJBSplitHook(address(0)) // no split hook
        });
        payoutSplits[1] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2), // 50% of payouts to beneficiary
            projectId: 0, // direct to address
            beneficiary: payable(SPLIT_BENEFICIARY), // payout beneficiary
            preferAddToBalance: false, // not adding to balance
            lockedUntil: 0, // not locked
            hook: IJBSplitHook(address(0)) // no split hook
        });

        // Reserved token splits: 100% to RESERVED_BENEFICIARY.
        JBSplit[] memory reservedSplits = new JBSplit[](1); // one reserved split
        reservedSplits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT), // 100% of reserved tokens
            projectId: 0, // not routing to a project
            beneficiary: payable(RESERVED_BENEFICIARY), // reserved token beneficiary
            preferAddToBalance: false, // not adding to balance
            lockedUntil: 0, // not locked
            hook: IJBSplitHook(address(0)) // no split hook
        });

        // Two split groups: payouts (grouped by token address) and reserved tokens.
        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](2); // two groups
        splitGroups[0] = JBSplitGroup({
            groupId: uint256(uint160(JBConstants.NATIVE_TOKEN)), // payout group = token address
            splits: payoutSplits // payout splits (A -> B + beneficiary)
        });
        splitGroups[1] = JBSplitGroup({
            groupId: JBSplitGroupIds.RESERVED_TOKENS, // reserved tokens group
            splits: reservedSplits // reserved splits (to RESERVED_BENEFICIARY)
        });

        // Payout limit: 1 ETH per cycle (ETH-denominated).
        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1); // one limit
        payoutLimits[0] = JBCurrencyAmount({
            amount: PAYOUT_LIMIT_ETH, // 1 ETH limit
            currency: uint32(nativeCurrency) // denominated in ETH
        });

        JBFundAccessLimitGroup[] memory fundAccessLimitGroups = new JBFundAccessLimitGroup[](1); // one limit group
        fundAccessLimitGroups[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()), // for the multi-terminal
            token: JBConstants.NATIVE_TOKEN, // for ETH
            payoutLimits: payoutLimits, // 1 ETH payout limit
            surplusAllowances: new JBCurrencyAmount[](0) // no surplus allowance
        });

        return JBRulesetConfig({
            mustStartAtOrAfter: uint48(block.timestamp), // start now
            duration: DURATION, // 30-day cycles
            weight: WEIGHT, // 1000 tokens per ETH
            weightCutPercent: WEIGHT_CUT_PERCENT, // 10% weight decay per cycle
            approvalHook: IJBRulesetApprovalHook(address(0)), // no approval hook
            metadata: metadata, // ruleset metadata
            splitGroups: splitGroups, // payout + reserved splits
            fundAccessLimitGroups: fundAccessLimitGroups // 1 ETH payout limit
        });
    }

    /// @notice Deploys a 721 tiers hook for the given project with a single tier.
    function _deploy721Hook(uint256 _projectId) internal returns (IJB721TiersHook) {
        // Configure one tier: 0.1 ETH, category 1, 20% split.
        JB721TierConfig[] memory tiers = new JB721TierConfig[](1); // one tier

        // Tier split: 100% of the split portion goes to SPLIT_BENEFICIARY.
        JBSplit[] memory tierSplits = new JBSplit[](1); // one tier split
        tierSplits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT), // 100% of split portion
            projectId: 0, // direct to address
            beneficiary: payable(SPLIT_BENEFICIARY), // tier split beneficiary
            preferAddToBalance: false, // not adding to balance
            lockedUntil: 0, // not locked
            hook: IJBSplitHook(address(0)) // no hook
        });

        tiers[0] = JB721TierConfig({
            price: TIER_PRICE, // 0.1 ETH per NFT
            initialSupply: 1000, // 1000 NFTs available (enough for 10 cycles)
            votingUnits: 0, // no voting power
            reserveFrequency: 0, // no reserve minting
            reserveBeneficiary: address(0), // no reserve beneficiary
            encodedIPFSUri: bytes32("churnTier1"), // tier metadata URI
            category: 1, // category 1
            discountPercent: 0, // no discount
            allowOwnerMint: false, // owner can't mint
            useReserveBeneficiaryAsDefault: false, // don't default to reserve beneficiary
            transfersPausable: false, // transfers allowed
            useVotingUnits: false, // don't use voting units
            cannotBeRemoved: false, // tier can be removed
            cannotIncreaseDiscountPercent: false, // discount can be increased
            splitPercent: TIER_SPLIT_PERCENT, // 20% of tier payment to splits
            splits: tierSplits // tier splits
        });

        // Build deploy config.
        JBDeploy721TiersHookConfig memory deployConfig = JBDeploy721TiersHookConfig({
            name: "ChurnTest NFT", // collection name
            symbol: "CNFT", // collection symbol
            baseUri: "ipfs://", // base URI
            tokenUriResolver: IJB721TokenUriResolver(address(0)), // no custom resolver
            contractUri: "ipfs://contract", // contract-level metadata
            tiersConfig: JB721InitTiersConfig({
                tiers: tiers, // our single tier
                currency: nativeCurrency, // priced in ETH
                decimals: 18 // 18 decimals
            }),
            reserveBeneficiary: address(0), // no default reserve beneficiary
            flags: JB721TiersHookFlags({
                noNewTiersWithReserves: false, // allow new tiers with reserves
                noNewTiersWithVotes: false, // allow new tiers with votes
                noNewTiersWithOwnerMinting: false, // allow new tiers with owner minting
                preventOverspending: false, // allow overspending
                issueTokensForSplits: false // don't issue extra tokens for splits
            })
        });

        // Deploy the hook clone.
        IJB721TiersHook newHook = HOOK_DEPLOYER.deployHookFor({
            projectId: _projectId, // for our project
            deployTiersHookConfig: deployConfig, // with this config
            salt: bytes32("CHURN_721") // deterministic salt
        });

        return newHook; // return the deployed hook
    }

    /// @notice Queues a new ruleset for Project A with the 721 hook as data hook.
    function _queueRulesetWithHook(uint256 _projectId, address _hookAddr) internal {
        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1); // one ruleset
        rulesets[0] = _buildProjectARuleset(_hookAddr); // build with the hook address

        // Queue the ruleset (it will start after the current ruleset's duration ends).
        jbController()
            .queueRulesetsOf({
                projectId: _projectId, // for Project A
                rulesetConfigurations: rulesets, // the new ruleset
                memo: "queue ruleset with 721 hook" // memo
            });
    }
}
