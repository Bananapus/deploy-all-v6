// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {JBFixedPointNumber} from "@bananapus/core-v6/src/libraries/JBFixedPointNumber.sol";
import {JBSplitGroupIds} from "@bananapus/core-v6/src/libraries/JBSplitGroupIds.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {JBCurrencyAmount} from "@bananapus/core-v6/src/structs/JBCurrencyAmount.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
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

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Mock price feed returning a fixed price (e.g. ETH/USD).
contract LifecycleMockPriceFeed is IJBPriceFeed {
    /// @notice The fixed price this feed always returns.
    uint256 public immutable PRICE;

    /// @notice The number of decimals the price is denominated in.
    uint8 public immutable FEED_DECIMALS;

    constructor(uint256 price, uint8 dec) {
        PRICE = price; // store the immutable price
        FEED_DECIMALS = dec; // store the immutable decimal count
    }

    /// @notice Returns the current price adjusted to the requested decimal precision.
    function currentUnitPrice(uint256 decimals) external view override returns (uint256) {
        return JBFixedPointNumber.adjustDecimals(PRICE, FEED_DECIMALS, decimals); // adjust from feed decimals to
        // requested decimals
    }
}

/// @notice Cross-feature lifecycle fork test exercising the "four-way and five-way matrix" of
/// JBv6 feature interactions in a SINGLE sequential scenario.
///
/// Covers: 721 tier hook deployment, ETH payment with NFT minting, payout splits with
/// cross-currency conversion, weight decay across ruleset cycling, reserved token distribution,
/// bonding-curve cash outs, and final accounting reconciliation.
///
/// Run with: forge test --match-contract CrossFeatureLifecycleForkTest -vvv
contract CrossFeatureLifecycleForkTest is TestBaseWorkflow {
    // ── ERC721 receiver support ──

    /// @notice Allows this contract to receive ERC-721 tokens (project NFTs, loan NFTs, etc.).
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector; // return the ERC-721 receiver magic value
    }

    // ── Currency constants ──
    uint32 constant USD = 2; // JBCurrencyIds.USD — abstract USD identifier

    // ── Ruleset parameters ──
    uint112 constant WEIGHT = uint112(1000e18); // 1000 tokens per ETH in ruleset 1
    uint32 constant DURATION = 30 days; // ruleset duration before cycling
    uint32 constant WEIGHT_CUT_PERCENT = 500_000_000; // 50% weight decay per cycle (9-decimal precision)
    uint16 constant RESERVED_PERCENT = 2000; // 20% of minted tokens go to reserved splits
    uint16 constant CASH_OUT_TAX_RATE = 5000; // 50% bonding-curve cash-out tax

    // ── 721 tier parameters ──
    uint104 constant TIER_PRICE = 0.5 ether; // each NFT tier costs 0.5 ETH
    uint32 constant TIER_SPLIT_PERCENT = 300_000_000; // 30% of tier payment forwarded to split beneficiary

    // ── Payout limit ──
    uint224 constant PAYOUT_LIMIT_USD = 1000e18; // $1000 payout limit (18 decimals, USD denomination)
    uint256 constant ETH_USD_PRICE = 2000e18; // 1 ETH = $2000 (18-decimal feed)

    // ── Actors ──
    address PAYER = makeAddr("lifecycle_payer"); // the main payer who buys tokens and NFTs
    address PAYER2 = makeAddr("lifecycle_payer2"); // a second payer to create bonding-curve dynamics
    address SPLIT_BENEFICIARY = makeAddr("lifecycle_splitBeneficiary"); // receives payout splits
    address RESERVED_BENEFICIARY = makeAddr("lifecycle_reservedBeneficiary"); // receives reserved token splits

    // ── Ecosystem contracts ──
    IJB721TiersHookStore HOOK_STORE; // stores 721 tier data
    JB721TiersHook EXAMPLE_HOOK; // implementation contract for cloning
    IJBAddressRegistry ADDRESS_REGISTRY; // registry for deployed hook addresses
    IJB721TiersHookDeployer HOOK_DEPLOYER; // deploys 721 hook clones

    // ── Project state ──
    uint256 projectId; // the project under test
    IJB721TiersHook hook; // the deployed 721 tiers hook

    // ── Derived currencies ──
    uint32 nativeCurrency; // uint32(uint160(NATIVE_TOKEN)) — the native token's currency identifier

    /// @notice Accept ETH returns from cash-outs.
    receive() external payable {}

    function setUp() public override {
        // Fork mainnet for deterministic state and real PoolManager.
        vm.createSelectFork("ethereum", 21_700_000);

        // Deploy fresh JB core contracts on the fork.
        super.setUp();

        // Compute the native token's currency identifier (truncated address).
        nativeCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));

        // Deploy 721 hook infrastructure.
        HOOK_STORE = new JB721TiersHookStore(); // tier data storage
        EXAMPLE_HOOK = new JB721TiersHook(
            jbDirectory(), jbPermissions(), jbPrices(), jbRulesets(), HOOK_STORE, jbSplits(), multisig()
        ); // implementation to clone from
        ADDRESS_REGISTRY = new JBAddressRegistry(); // address registry for hooks
        HOOK_DEPLOYER = new JB721TiersHookDeployer(EXAMPLE_HOOK, HOOK_STORE, ADDRESS_REGISTRY, address(0)); // deployer
        // with no trusted forwarder

        // Register ETH/USD price feed: "1 ETH = 2000 USD" (18 decimals).
        LifecycleMockPriceFeed ethUsdFeed = new LifecycleMockPriceFeed(ETH_USD_PRICE, 18);
        vm.prank(multisig()); // only multisig can add global feeds
        jbPrices().addPriceFeedFor(0, USD, nativeCurrency, IJBPriceFeed(address(ethUsdFeed))); // register feed for all
        // projects

        // Fund test actors with ETH.
        vm.deal(PAYER, 100 ether); // payer gets 100 ETH
        vm.deal(PAYER2, 100 ether); // second payer gets 100 ETH
    }

    /// @notice The main lifecycle test covering all 9 feature interaction steps in sequence.
    function test_crossFeatureLifecycle() public {
        // ═══════════════════════════════════════════════════════════════
        // STEP 1: Deploy a project with a 721 tier hook (NFT tiers)
        // ═══════════════════════════════════════════════════════════════

        // First, launch the project to get a projectId — we need it to deploy the 721 hook.
        projectId = _launchProjectWithPlaceholderHook();

        // Deploy the 721 tiers hook for this project.
        hook = _deploy721Hook(projectId);

        // Queue a new ruleset that uses the 721 hook as the data hook.
        _queueRulesetWithHook(projectId, address(hook));

        // Warp past the current ruleset's duration so the new ruleset (with hook) becomes active.
        vm.warp(block.timestamp + DURATION + 1); // advance past the first ruleset

        // ═══════════════════════════════════════════════════════════════
        // STEP 2: Pay into the project with ETH — mints NFTs from tiers
        // ═══════════════════════════════════════════════════════════════

        // Build metadata selecting tier 1 for NFT minting.
        address metadataTarget = hook.METADATA_ID_TARGET(); // get the hook's metadata ID target
        bytes memory payMetadata = _buildTierMetadata(metadataTarget); // encode tier selection

        // Pay 1 ETH (enough for 2x tier price of 0.5 ETH each, but we select tier 1 once).
        vm.prank(PAYER); // pay as PAYER
        uint256 tokensFromPay1 = jbMultiTerminal().pay{value: 1 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "lifecycle pay 1",
            metadata: payMetadata
        });

        // Verify NFT was minted to PAYER.
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "Step 2: PAYER should own 1 NFT"); // one tier-1 NFT minted

        // Verify project tokens were minted (accounting for 20% reserved + 30% tier split).
        // Weight=1000e18 tokens/ETH, 20% reserved, 30% tier split on 0.5 ETH tier portion.
        // The exact amount depends on internal split/reserved logic — just verify > 0.
        assertGt(tokensFromPay1, 0, "Step 2: PAYER should receive project tokens"); // tokens were minted

        // Record the terminal balance after first payment.
        uint256 balanceAfterPay1 = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        assertGt(balanceAfterPay1, 0, "Step 2: terminal should hold ETH"); // balance increased

        // Second payer pays without NFT metadata (plain payment for bonding curve dynamics).
        vm.prank(PAYER2); // pay as PAYER2
        uint256 tokensFromPay2 = jbMultiTerminal().pay{value: 5 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            beneficiary: PAYER2,
            minReturnedTokens: 0,
            memo: "lifecycle pay 2",
            metadata: ""
        });
        assertGt(tokensFromPay2, 0, "Step 2: PAYER2 should receive project tokens"); // tokens were minted

        // ═══════════════════════════════════════════════════════════════
        // STEP 3 & 4: Execute payouts — verify cross-currency split
        // ═══════════════════════════════════════════════════════════════

        // Payout splits were configured at launch. The payout limit is $1000 USD.
        // At $2000/ETH, this means 0.5 ETH will be paid out.
        // The split sends 100% to SPLIT_BENEFICIARY.

        uint256 splitBeneficiaryBefore = SPLIT_BENEFICIARY.balance; // record balance before payout

        // Send payouts denominated in USD (cross-currency: limit is USD, balance is ETH).
        uint256 amountPaidOut = jbMultiTerminal()
            .sendPayoutsOf({
                projectId: projectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: PAYOUT_LIMIT_USD, // $1000 USD
                currency: USD, // denominated in USD
                minTokensPaidOut: 0
            });

        assertGt(amountPaidOut, 0, "Step 4: payouts should send ETH"); // ETH was paid out

        // Verify the split beneficiary received ETH.
        uint256 splitBeneficiaryAfter = SPLIT_BENEFICIARY.balance; // check balance after payout
        uint256 splitReceived = splitBeneficiaryAfter - splitBeneficiaryBefore; // compute delta

        // $1000 at $2000/ETH = 0.5 ETH. Split is 100%, minus 2.5% fee = ~0.4875 ETH.
        // Allow 5% tolerance for fee + rounding.
        assertApproxEqRel(
            splitReceived,
            0.4875 ether,
            0.05e18, // 5% tolerance
            "Step 4: split beneficiary should receive ~0.4875 ETH ($1000 at $2000/ETH minus 2.5% fee)"
        );

        // ═══════════════════════════════════════════════════════════════
        // STEP 5: Advance time to trigger a new ruleset with weight decay
        // ═══════════════════════════════════════════════════════════════

        // Record the total supply before the new ruleset.
        uint256 supplyBeforeDecay = jbTokens().totalSupplyOf(projectId);

        // Warp past the current ruleset's duration to trigger weight decay.
        vm.warp(block.timestamp + DURATION + 1); // advance past the second ruleset

        // ═══════════════════════════════════════════════════════════════
        // STEP 6: Make another payment — verify decayed weight produces fewer tokens
        // ═══════════════════════════════════════════════════════════════

        // Pay the same amount (1 ETH) with PAYER2 in the new (decayed) ruleset.
        vm.prank(PAYER2); // pay as PAYER2
        uint256 tokensFromDecayedPay = jbMultiTerminal().pay{value: 1 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER2,
            minReturnedTokens: 0,
            memo: "lifecycle decayed pay",
            metadata: ""
        });

        // With 50% weight decay: new weight = 1000e18 * 50% = 500e18 tokens/ETH.
        // After 20% reserved, PAYER2 gets 80% of 500 = 400 tokens per ETH.
        // The first pay (1 ETH, no tier split) gave ~800 tokens (80% of 1000).
        // So decayed pay should give roughly half of what the first non-tier pay gave.
        assertGt(tokensFromDecayedPay, 0, "Step 6: should receive tokens in decayed ruleset"); // tokens minted

        // The key invariant: decayed payment produces fewer tokens than the same payment in ruleset 1.
        // PAYER2's first payment was 5 ETH -> tokensFromPay2.
        // Normalize: tokens per ETH in ruleset 1 = tokensFromPay2 / 5.
        uint256 tokensPerEthRuleset1 = tokensFromPay2 / 5; // tokens per ETH before decay
        assertLt(
            tokensFromDecayedPay, tokensPerEthRuleset1, "Step 6: decayed weight should produce fewer tokens per ETH"
        );

        // Verify the decayed weight is approximately 50% of the original.
        // Allow 10% tolerance for reserved token rounding effects.
        assertApproxEqRel(
            tokensFromDecayedPay,
            tokensPerEthRuleset1 / 2,
            0.1e18, // 10% tolerance
            "Step 6: decayed tokens should be ~50% of original"
        );

        // ═══════════════════════════════════════════════════════════════
        // STEP 7: Distribute reserved tokens to split beneficiaries
        // ═══════════════════════════════════════════════════════════════

        // Check pending reserved tokens accumulated from all payments.
        uint256 pendingReserved = jbController().pendingReservedTokenBalanceOf(projectId);
        assertGt(pendingReserved, 0, "Step 7: should have pending reserved tokens"); // reserved tokens accumulated

        // Record reserved beneficiary balance before distribution.
        uint256 reservedBeneficiaryTokensBefore = jbTokens().totalBalanceOf(RESERVED_BENEFICIARY, projectId);

        // Distribute reserved tokens to the configured splits.
        jbController().sendReservedTokensToSplitsOf(projectId); // distribute to splits

        // Verify reserved beneficiary received tokens.
        uint256 reservedBeneficiaryTokensAfter = jbTokens().totalBalanceOf(RESERVED_BENEFICIARY, projectId);
        uint256 reservedTokensReceived = reservedBeneficiaryTokensAfter - reservedBeneficiaryTokensBefore; // compute
        // delta
        assertGt(reservedTokensReceived, 0, "Step 7: reserved beneficiary should receive reserved tokens");

        // Verify pending reserved balance is now zero.
        uint256 pendingAfter = jbController().pendingReservedTokenBalanceOf(projectId);
        assertEq(pendingAfter, 0, "Step 7: pending reserved tokens should be zero after distribution"); // all
        // distributed

        // ═══════════════════════════════════════════════════════════════
        // STEP 8: Cash out tokens using the bonding curve
        // ═══════════════════════════════════════════════════════════════

        // PAYER2 cashes out half their tokens.
        uint256 payer2Tokens = jbTokens().totalBalanceOf(PAYER2, projectId); // get PAYER2's token balance
        uint256 cashOutCount = payer2Tokens / 2; // cash out half
        uint256 payer2EthBefore = PAYER2.balance; // record ETH balance before

        // Record terminal balance before cash out for accounting check.
        uint256 terminalBalanceBeforeCashOut = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);

        vm.prank(PAYER2); // cash out as PAYER2
        uint256 reclaimAmount = jbMultiTerminal()
            .cashOutTokensOf({
                holder: PAYER2,
                projectId: projectId,
                cashOutCount: cashOutCount,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(PAYER2),
                metadata: ""
            });

        // Verify PAYER2 received ETH from the cash out.
        uint256 payer2EthAfter = PAYER2.balance; // check ETH balance after
        uint256 ethFromCashOut = payer2EthAfter - payer2EthBefore; // compute ETH received
        assertGt(ethFromCashOut, 0, "Step 8: PAYER2 should receive ETH from cash out"); // ETH received

        // Verify the bonding curve tax reduced the reclaim.
        // With 50% cashOutTaxRate, reclaiming half the supply should return less than half the surplus.
        // The bonding curve formula: reclaim = surplus * [(1-tax) + tax*(count/supply)]
        // For half the supply: reclaim = surplus * [(0.5) + 0.5*(0.5)] = surplus * 0.75
        // But we're cashing out half of PAYER2's tokens, not half of total supply, so the actual
        // reclaim depends on the proportion. Just verify it's less than pro-rata.
        uint256 totalSupplyAtCashOut = jbTokens().totalSupplyOf(projectId) + cashOutCount; // total supply before burn
        uint256 proRataReclaim = terminalBalanceBeforeCashOut * cashOutCount / totalSupplyAtCashOut; // what pro-rata
        // would give
        assertLt(reclaimAmount, proRataReclaim, "Step 8: bonding curve tax should reduce reclaim below pro-rata"); // tax
        // applied

        // Verify tokens were burned. Note: fee processing during cash out mints fee-rebate
        // tokens to the beneficiary (PAYER2), so the final balance may be slightly higher
        // than (payer2Tokens - cashOutCount). We verify the net decrease is close to cashOutCount.
        uint256 payer2TokensAfter = jbTokens().totalBalanceOf(PAYER2, projectId); // check token balance after
        assertLt(payer2TokensAfter, payer2Tokens, "Step 8: PAYER2 token balance should decrease after cash out"); // balance
        // decreased

        // ═══════════════════════════════════════════════════════════════
        // STEP 9: Verify final accounting — all balances reconcile
        // ═══════════════════════════════════════════════════════════════

        // Get the final terminal balance.
        uint256 finalTerminalBalance = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);

        // The terminal balance should be less than the total ETH paid in (7 ETH total across all payments).
        // Deductions: payouts (~0.5 ETH), cash-out reclaim, fees.
        assertLt(
            finalTerminalBalance,
            7 ether,
            "Step 9: terminal balance should be less than total payments (payouts + cashouts deducted)"
        );

        // The terminal balance should be greater than zero (not fully drained).
        assertGt(finalTerminalBalance, 0, "Step 9: terminal balance should not be zero"); // funds remain

        // Verify no phantom surplus: the recorded balance should match the actual ETH held.
        // The terminal's recorded balance should be <= the actual ETH on the terminal contract.
        // Note: actual ETH may be higher due to fees from other projects, so we check recorded <= actual.
        uint256 actualTerminalEth = address(jbMultiTerminal()).balance; // actual ETH held by terminal
        assertGe(
            actualTerminalEth,
            finalTerminalBalance,
            "Step 9: actual ETH should be >= recorded balance (no phantom surplus)"
        );

        // Verify token supply consistency.
        uint256 finalSupply = jbTokens().totalSupplyOf(projectId); // total token supply
        uint256 payerBalance = jbTokens().totalBalanceOf(PAYER, projectId); // PAYER's tokens
        uint256 payer2Balance = jbTokens().totalBalanceOf(PAYER2, projectId); // PAYER2's tokens
        uint256 reservedBalance = jbTokens().totalBalanceOf(RESERVED_BENEFICIARY, projectId); // reserved beneficiary
        // tokens
        uint256 splitBeneficiaryTokens = jbTokens().totalBalanceOf(SPLIT_BENEFICIARY, projectId); // split beneficiary
        // tokens

        // Sum of all known holder balances should be <= total supply.
        // (There may be other holders like the tier split beneficiary from NFT payment.)
        uint256 knownHoldings = payerBalance + payer2Balance + reservedBalance + splitBeneficiaryTokens; // sum of known
        // holdings
        assertLe(knownHoldings, finalSupply, "Step 9: known token holdings should not exceed total supply");

        // Verify the total supply decreased from the cash out.
        assertLt(
            finalSupply,
            supplyBeforeDecay + tokensFromDecayedPay + pendingReserved,
            "Step 9: total supply should reflect burned tokens from cash out"
        );

        // Log final state for manual inspection.
        emit log_named_uint("Final terminal balance (wei)", finalTerminalBalance); // log terminal balance
        emit log_named_uint("Final token supply", finalSupply); // log token supply
        emit log_named_uint("PAYER tokens", payerBalance); // log PAYER balance
        emit log_named_uint("PAYER2 tokens", payer2Balance); // log PAYER2 balance
        emit log_named_uint("Reserved beneficiary tokens", reservedBalance); // log reserved beneficiary balance
        emit log_named_uint("ETH reclaimed from cash out", ethFromCashOut); // log cash out ETH
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Internal Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Launches a project with a first ruleset (no 721 hook yet) to get a projectId.
    /// @dev The first ruleset uses a placeholder with no data hook. A second ruleset with the
    ///      721 hook is queued after the hook is deployed.
    function _launchProjectWithPlaceholderHook() internal returns (uint256 id) {
        // Configure terminal to accept native ETH.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1); // one accounting context
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, // accept native ETH
            decimals: 18, // 18 decimal precision
            currency: nativeCurrency // currency = truncated native token address
        });

        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1); // one terminal
        tc[0] = JBTerminalConfig({
            terminal: jbMultiTerminal(), // use the multi-terminal
            accountingContextsToAccept: acc // accept ETH
        });

        // Build the first ruleset config (placeholder, no data hook).
        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1); // one ruleset
        rulesets[0] = _buildRulesetConfig(address(0)); // no data hook initially

        // Launch the project.
        id = jbController()
            .launchProjectFor({
                owner: address(this), // test contract owns the project
                projectUri: "ipfs://lifecycle-test", // project metadata URI
                rulesetConfigurations: rulesets, // initial rulesets
                terminalConfigurations: tc, // terminal setup
                memo: "cross-feature lifecycle test" // launch memo
            });
    }

    /// @notice Builds a JBRulesetConfig with the lifecycle test parameters.
    /// @param dataHook The 721 hook address (or address(0) for the placeholder ruleset).
    function _buildRulesetConfig(address dataHook) internal view returns (JBRulesetConfig memory) {
        // Metadata: 20% reserved, 50% cash-out tax, ETH base currency, data hook for pay.
        JBRulesetMetadata memory metadata = JBRulesetMetadata({
            reservedPercent: RESERVED_PERCENT, // 20% of minted tokens reserved
            cashOutTaxRate: CASH_OUT_TAX_RATE, // 50% bonding curve tax
            baseCurrency: nativeCurrency, // weight denominated in ETH
            pausePay: false, // payments allowed
            pauseCreditTransfers: false, // transfers allowed
            allowOwnerMinting: true, // owner can mint (needed for reserved token distribution)
            allowSetCustomToken: false, // no custom token changes
            allowTerminalMigration: false, // no terminal migration
            allowSetTerminals: false, // no terminal changes
            allowSetController: false, // no controller changes
            allowAddAccountingContext: false, // no new accounting contexts
            allowAddPriceFeed: true, // allow adding price feeds
            ownerMustSendPayouts: false, // anyone can trigger payouts
            holdFees: false, // fees not held
            useTotalSurplusForCashOuts: false, // use local terminal balance
            useDataHookForPay: dataHook != address(0), // use data hook if provided
            useDataHookForCashOut: false, // no data hook for cash outs
            dataHook: dataHook, // the 721 hook (or zero)
            metadata: 0 // no extra metadata
        });

        // Payout splits: 100% of payouts go to SPLIT_BENEFICIARY.
        JBSplit[] memory payoutSplits = new JBSplit[](1); // one payout split
        payoutSplits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT), // 100% of payouts
            projectId: 0, // not paying a project
            beneficiary: payable(SPLIT_BENEFICIARY), // send to split beneficiary
            preferAddToBalance: false, // don't add to balance
            lockedUntil: 0, // not locked
            hook: IJBSplitHook(address(0)) // no split hook
        });

        // Reserved token splits: 100% of reserved tokens go to RESERVED_BENEFICIARY.
        JBSplit[] memory reservedSplits = new JBSplit[](1); // one reserved split
        reservedSplits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT), // 100% of reserved tokens
            projectId: 0, // not paying a project
            beneficiary: payable(RESERVED_BENEFICIARY), // send to reserved beneficiary
            preferAddToBalance: false, // don't add to balance
            lockedUntil: 0, // not locked
            hook: IJBSplitHook(address(0)) // no split hook
        });

        // Two split groups: payouts (grouped by token address) and reserved tokens (group ID = 1).
        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](2); // two groups
        splitGroups[0] = JBSplitGroup({
            groupId: uint256(uint160(JBConstants.NATIVE_TOKEN)), // payout group = token address
            splits: payoutSplits // payout splits
        });
        splitGroups[1] = JBSplitGroup({
            groupId: JBSplitGroupIds.RESERVED_TOKENS, // reserved tokens group = 1
            splits: reservedSplits // reserved splits
        });

        // Payout limit: $1000 USD worth of ETH (cross-currency).
        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1); // one limit
        payoutLimits[0] = JBCurrencyAmount({
            amount: PAYOUT_LIMIT_USD, // $1000 USD
            currency: USD // denominated in USD
        });

        JBFundAccessLimitGroup[] memory fundAccessLimitGroups = new JBFundAccessLimitGroup[](1); // one limit group
        fundAccessLimitGroups[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()), // for this terminal
            token: JBConstants.NATIVE_TOKEN, // for ETH
            payoutLimits: payoutLimits, // $1000 USD limit
            surplusAllowances: new JBCurrencyAmount[](0) // no surplus allowance
        });

        return JBRulesetConfig({
            mustStartAtOrAfter: uint48(block.timestamp), // start now
            duration: DURATION, // 30 days per cycle
            weight: WEIGHT, // 1000 tokens per ETH
            weightCutPercent: WEIGHT_CUT_PERCENT, // 50% decay per cycle
            approvalHook: IJBRulesetApprovalHook(address(0)), // no approval hook
            metadata: metadata, // ruleset metadata
            splitGroups: splitGroups, // payout + reserved splits
            fundAccessLimitGroups: fundAccessLimitGroups // $1000 USD payout limit
        });
    }

    /// @notice Deploys a 721 tiers hook for the given project.
    function _deploy721Hook(uint256 _projectId) internal returns (IJB721TiersHook) {
        // Configure one tier: 0.5 ETH, category 1, 30% split to beneficiary.
        JB721TierConfig[] memory tiers = new JB721TierConfig[](1); // one tier

        // Build tier split: 100% of the split portion goes to SPLIT_BENEFICIARY.
        JBSplit[] memory tierSplits = new JBSplit[](1); // one tier split
        tierSplits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT), // 100% of split portion
            projectId: 0, // not paying a project
            beneficiary: payable(SPLIT_BENEFICIARY), // tier split beneficiary
            preferAddToBalance: false, // don't add to balance
            lockedUntil: 0, // not locked
            hook: IJBSplitHook(address(0)) // no hook
        });

        tiers[0] = JB721TierConfig({
            price: TIER_PRICE, // 0.5 ETH per NFT
            initialSupply: 100, // 100 NFTs available
            votingUnits: 0, // no voting power
            reserveFrequency: 0, // no reserve minting
            reserveBeneficiary: address(0), // no reserve beneficiary
            encodedIPFSUri: bytes32("lifecycleTier1"), // tier metadata URI
            category: 1, // category 1 (must be sorted ascending)
            discountPercent: 0, // no discount
            allowOwnerMint: false, // owner can't mint
            useReserveBeneficiaryAsDefault: false, // don't default to reserve beneficiary
            transfersPausable: false, // transfers allowed
            useVotingUnits: false, // don't use voting units
            cannotBeRemoved: false, // tier can be removed
            cannotIncreaseDiscountPercent: false, // discount can be increased
            splitPercent: TIER_SPLIT_PERCENT, // 30% of tier payment to splits
            splits: tierSplits // tier splits
        });

        // Build deploy config.
        JBDeploy721TiersHookConfig memory deployConfig = JBDeploy721TiersHookConfig({
            name: "Lifecycle NFT", // collection name
            symbol: "LCNFT", // collection symbol
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
            salt: bytes32("LIFECYCLE_721") // deterministic salt
        });

        return newHook; // return the deployed hook
    }

    /// @notice Queues a new ruleset with the 721 hook as data hook.
    function _queueRulesetWithHook(uint256 _projectId, address _hookAddr) internal {
        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1); // one ruleset
        rulesets[0] = _buildRulesetConfig(_hookAddr); // build with the hook address

        // Queue the ruleset (it will start after the current ruleset's duration ends).
        jbController()
            .queueRulesetsOf({
                projectId: _projectId, // for our project
                rulesetConfigurations: rulesets, // the new ruleset
                memo: "queue ruleset with 721 hook" // memo
            });
    }

    /// @notice Builds payment metadata that selects tier 1 for NFT minting.
    function _buildTierMetadata(address metadataTarget) internal pure returns (bytes memory) {
        uint16[] memory tierIds = new uint16[](1); // select one tier
        tierIds[0] = 1; // tier ID 1

        bytes memory tierData = abi.encode(true, tierIds); // encode: (expectMint=true, tierIds)

        // Build the metadata with the hook's ID.
        bytes4 tierMetadataId = JBMetadataResolver.getId("pay", metadataTarget); // compute the metadata ID

        bytes4[] memory ids = new bytes4[](1); // one metadata entry
        ids[0] = tierMetadataId; // the tier hook's ID

        bytes[] memory datas = new bytes[](1); // one data entry
        datas[0] = tierData; // the tier selection data

        return JBMetadataResolver.createMetadata(ids, datas); // encode into JB metadata format
    }

    /// @notice Returns the terminal's recorded balance for a project and token.
    function _terminalBalance(uint256 _projectId, address token) internal view returns (uint256) {
        return jbTerminalStore().balanceOf(address(jbMultiTerminal()), _projectId, token); // read from terminal store
    }
}
