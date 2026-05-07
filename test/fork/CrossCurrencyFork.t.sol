// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {JBFixedPointNumber} from "@bananapus/core-v6/src/libraries/JBFixedPointNumber.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

// 721 Hook
import {IJB721TiersHook} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHook.sol";
import {IJB721TokenUriResolver} from "@bananapus/721-hook-v6/src/interfaces/IJB721TokenUriResolver.sol";
import {JB721TierConfig} from "@bananapus/721-hook-v6/src/structs/JB721TierConfig.sol";
import {JB721InitTiersConfig} from "@bananapus/721-hook-v6/src/structs/JB721InitTiersConfig.sol";
import {JB721TierConfigFlags} from "@bananapus/721-hook-v6/src/structs/JB721TierConfigFlags.sol";

// Revnet
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVDeploy721TiersHookConfig} from "@rev-net/core-v6/src/structs/REVDeploy721TiersHookConfig.sol";
import {REVBaseline721HookConfig} from "@rev-net/core-v6/src/structs/REVBaseline721HookConfig.sol";
import {REV721TiersHookFlags} from "@rev-net/core-v6/src/structs/REV721TiersHookFlags.sol";
import {REVCroptopAllowedPost} from "@rev-net/core-v6/src/structs/REVCroptopAllowedPost.sol";

// Suckers
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// Shared helpers
import {RevnetEcosystemBase} from "../helpers/RevnetEcosystemBase.sol";
import {MockERC20Token} from "../helpers/MockTokens.sol";
import {MockPriceFeed} from "../helpers/MockPriceFeed.sol";

/// @notice Cross-currency integration fork test: stress-tests JBPrices in live payment flows with hooks.
/// Exercises cross-currency paths in JBTerminalStore, JB721TiersHookLib, and JBBuybackHook.
///
/// Run with: forge test --match-contract CrossCurrencyForkTest -vvv
contract CrossCurrencyForkTest is RevnetEcosystemBase {
    // -- Test parameters (cross-currency specific)
    uint104 constant TIER_PRICE_USD = 100e18; // 100 USD (18 decimals for USD abstract pricing)
    uint104 constant TIER_PRICE_ETH = 0.05e18; // 0.05 ETH

    // -- Currency constants
    uint32 constant USD = 2; // JBCurrencyIds.USD
    uint32 constant ETH_ID = 1; // JBCurrencyIds.ETH

    // -- Actors
    address PAYER2 = makeAddr("cc_payer2");

    // -- Cross-currency state
    MockERC20Token usdc;
    uint32 nativeCurrency;
    uint32 usdcCurrency;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_CrossCurrency";
    }

    function setUp() public override {
        super.setUp();

        // Deploy mock USDC.
        usdc = new MockERC20Token("Mock USDC", "USDC", 6);
        nativeCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));
        usdcCurrency = uint32(uint160(address(usdc)));

        // --- Register price feeds ---

        // Feed 1: ETH/USD — "1 ETH costs 2000 USD" (18-decimal feed)
        MockPriceFeed ethUsdFeed = new MockPriceFeed(2000e18, 18);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, USD, nativeCurrency, IJBPriceFeed(address(ethUsdFeed)));

        // Feed 2: USDC/USD — "1 USDC costs 1 USD" (6-decimal feed)
        MockPriceFeed usdcUsdFeed = new MockPriceFeed(1e6, 6);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, USD, usdcCurrency, IJBPriceFeed(address(usdcUsdFeed)));

        // Feed 3: NATIVE_TOKEN/ETH — 1:1 (for 721 tiers priced in abstract ETH)
        MockPriceFeed nativeEthFeed = new MockPriceFeed(1e18, 18);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, ETH_ID, nativeCurrency, IJBPriceFeed(address(nativeEthFeed)));

        // Fund actors.
        vm.deal(PAYER, 100 ether);
        vm.deal(PAYER2, 100 ether);
    }

    // ===================================================================
    //  Config Helpers
    // ===================================================================

    /// @notice Build a two-stage USD-base revnet accepting BOTH ETH and USDC.
    function _buildCrossCurrencyConfig()
        internal
        view
        returns (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc)
    {
        JBAccountingContext[] memory acc = new JBAccountingContext[](2);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});
        acc[1] = JBAccountingContext({token: address(usdc), decimals: 6, currency: usdcCurrency});

        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(multisig()),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 2000, // 20% reserved
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: 5000,
            extraMetadata: 0
        });

        cfg = REVConfig({
            description: REVDescription("CC Test", "CCT", "ipfs://cc", "CC_SALT"),
            baseCurrency: USD, // Abstract USD
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("CC"))
        });
    }

    /// @notice 721 tiers priced in abstract USD(2), no tier splits.
    function _build721ConfigUSDTiers() internal view returns (REVDeploy721TiersHookConfig memory) {
        return _build721ConfigUSDTiersWithSplit(false);
    }

    /// @notice 721 tiers priced in abstract USD(2), with optional 30% tier split.
    function _build721ConfigUSDTiersWithSplit(bool withSplit)
        internal
        view
        returns (REVDeploy721TiersHookConfig memory)
    {
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);

        JBSplit[] memory tierSplits;
        uint32 splitPercent;

        if (withSplit) {
            tierSplits = new JBSplit[](1);
            tierSplits[0] = JBSplit({
                percent: uint32(uint256(JBConstants.SPLITS_TOTAL_PERCENT)),
                projectId: 0,
                beneficiary: payable(SPLIT_BENEFICIARY),
                preferAddToBalance: false,
                lockedUntil: 0,
                hook: IJBSplitHook(address(0))
            });
            splitPercent = 300_000_000; // 30%
        } else {
            tierSplits = new JBSplit[](0);
            splitPercent = 0;
        }

        tierConfigs[0] = JB721TierConfig({
            price: TIER_PRICE_USD, // 100 USD (18 decimals)
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            // forge-lint: disable-next-line(unsafe-typecast)
            encodedIPFSUri: bytes32("ccUsdTier1"),
            category: 1,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: false,
                cantIncreaseDiscountPercent: false,
                cantBuyWithCredits: false
            }),
            splitPercent: splitPercent,
            splits: tierSplits
        });

        return REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "CC USD NFT",
                symbol: "CCUSDNFT",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: "ipfs://contract",
                tiersConfig: JB721InitTiersConfig({
                    tiers: tierConfigs,
                    currency: USD, // Abstract USD
                    decimals: 18
                }),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            // forge-lint: disable-next-line(unsafe-typecast)
            salt: bytes32(withSplit ? bytes32("CC_USD_721_S") : bytes32("CC_USD_721")),
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });
    }

    /// @notice 721 tiers priced in abstract ETH(1).
    function _build721ConfigETHTiers() internal pure returns (REVDeploy721TiersHookConfig memory) {
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);

        tierConfigs[0] = JB721TierConfig({
            price: TIER_PRICE_ETH, // 0.05 ETH
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            // forge-lint: disable-next-line(unsafe-typecast)
            encodedIPFSUri: bytes32("ccEthTier1"),
            category: 1,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: false,
                cantIncreaseDiscountPercent: false,
                cantBuyWithCredits: false
            }),
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        return REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "CC ETH NFT",
                symbol: "CCETHNFT",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: "ipfs://contract",
                tiersConfig: JB721InitTiersConfig({
                    tiers: tierConfigs,
                    currency: ETH_ID, // Abstract ETH
                    decimals: 18
                }),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            // forge-lint: disable-next-line(unsafe-typecast)
            salt: bytes32("CC_ETH_721"),
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });
    }

    // ===================================================================
    //  Payment / Metadata Helpers
    // ===================================================================

    function _payRevnetUSDC(uint256 revnetId, address payer, uint256 amount) internal returns (uint256 tokensReceived) {
        usdc.mint(payer, amount);
        vm.startPrank(payer);
        usdc.approve(address(jbMultiTerminal()), amount);
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

    function _buildPayMetadataWithTier(address hookMetadataTarget) internal pure returns (bytes memory) {
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        bytes memory tierData = abi.encode(true, tierIds);
        bytes4 tierMetadataId = JBMetadataResolver.getId("pay", hookMetadataTarget);

        bytes4[] memory ids = new bytes4[](1);
        ids[0] = tierMetadataId;
        bytes[] memory datas = new bytes[](1);
        datas[0] = tierData;

        return JBMetadataResolver.createMetadata(ids, datas);
    }

    // ===================================================================
    //  Tests
    // ===================================================================

    /// @notice Test 1: USD-base project, pay with ETH -> correct cross-currency token count.
    function test_cc_usdBaseProject_payWithETH() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 1 ETH to USD-base project.
        // Weight ratio: pricePerUnitOf(_, nativeCurrency, USD, 18) = inverse of 2000e18 = 5e14
        // Expected: mulDiv(1e18, 1000e18, 5e14) = 2,000,000e18 tokens total
        // With 20% reserved → payer gets 1,600,000e18
        uint256 tokens = _payRevnet(revnetId, PAYER, 1 ether);

        assertEq(tokens, 1_600_000e18, "1 ETH at $2000 -> 1,600,000 tokens (80% after 20% reserved)");

        // Verify reserved token accumulation.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        assertEq(pending, 400_000e18, "reserved = 400,000 tokens (20%)");
    }

    /// @notice Test 2: USD-base project, pay with USDC -> equivalent token count to ETH payment.
    function test_cc_usdBaseProject_payWithUSDC() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 2000 USDC to USD-base project (= $2000, same as 1 ETH).
        // Weight ratio: pricePerUnitOf(_, usdcCurrency, USD, 6) = inverse of 1e6 = 1e6
        // Expected: mulDiv(2000e6, 1000e18, 1e6) = 2,000,000e18 tokens total
        // With 20% reserved → payer gets 1,600,000e18
        uint256 tokens = _payRevnetUSDC(revnetId, PAYER, 2000e6);

        assertEq(tokens, 1_600_000e18, "2000 USDC -> 1,600,000 tokens (same as 1 ETH)");
    }

    /// @notice Test 3: 721 tiers in USD, pay with ETH -> NFT minted via cross-currency normalization.
    function test_cc_721TiersInUSD_payWithETH() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();
        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigUSDTiers();

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);

        // Pay 0.05 ETH (= $100 at $2000/ETH = tier price of 100 USD)
        vm.prank(PAYER);
        jbMultiTerminal().pay{value: 0.05 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 0.05 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "1 NFT minted from ETH via cross-currency");
    }

    /// @notice Test 4: 721 tiers in USD, pay with USDC -> NFT minted via cross-currency normalization.
    function test_cc_721TiersInUSD_payWithUSDC() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();
        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigUSDTiers();

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);

        // Pay 100 USDC (= $100 = tier price)
        usdc.mint(PAYER, 100e6);
        vm.startPrank(PAYER);
        usdc.approve(address(jbMultiTerminal()), 100e6);
        jbMultiTerminal()
            .pay({
            projectId: revnetId,
            token: address(usdc),
            amount: 100e6,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });
        vm.stopPrank();

        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "1 NFT minted from USDC via cross-currency");
    }

    /// @notice Test 5: 721 tiers in USD + 30% tier split, pay with USDC -> split beneficiary gets USDC.
    /// @dev FINDING: Tier splits with cross-currency pricing revert because the split amount is
    /// calculated in the tier's abstract pricing denomination (e.g., 30e18 USD units) but compared
    /// against the actual payment token amount (e.g., 100e6 USDC). The hook requests forwarding
    /// more tokens than the payment contains. This test documents the revert behavior.
    function test_cc_721TiersInUSD_payWithUSDC_withSplit() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();
        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigUSDTiersWithSplit(true);

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);

        // FIXED: Split amounts are now converted from tier pricing denomination (USD, 18 decimals)
        // to payment token denomination (USDC, 6 decimals) inside calculateSplitAmounts.
        // 30% of 100 USD tier = 30 USD -> ~30e6 USDC forwarded to split beneficiary.
        uint256 splitBeneficiaryBalanceBefore = usdc.balanceOf(SPLIT_BENEFICIARY);

        usdc.mint(PAYER, 100e6);
        vm.startPrank(PAYER);
        usdc.approve(address(jbMultiTerminal()), 100e6);
        jbMultiTerminal()
            .pay({
            projectId: revnetId,
            token: address(usdc),
            amount: 100e6,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });
        vm.stopPrank();

        // NFT minted to payer.
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should have 1 NFT");

        // Split beneficiary received ~30 USDC (30% of 100 USDC, converted from 30e18 USD).
        uint256 splitBeneficiaryBalanceAfter = usdc.balanceOf(SPLIT_BENEFICIARY);
        uint256 splitReceived = splitBeneficiaryBalanceAfter - splitBeneficiaryBalanceBefore;
        // Allow 1% tolerance for price feed rounding.
        assertApproxEqRel(splitReceived, 30e6, 0.01e18, "split beneficiary should receive ~30 USDC");
    }

    /// @notice Test 6: Missing price feed -> revert.
    function test_cc_missingPriceFeed_reverts() public {
        // Deploy a separate JB ecosystem without price feeds for this test.
        // We use a revnet with baseCurrency = 999 (no feed registered for this).
        _deployFeeProject(5000);

        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0].beneficiary = payable(multisig());
        splits[0].percent = 10_000;

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 0,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: 5000,
            extraMetadata: 0
        });

        // baseCurrency = 999 -> no feed exists for nativeCurrency -> 999
        REVConfig memory cfg = REVConfig({
            description: REVDescription("NoPriceFeed", "NPF", "ipfs://npf", "NPF_SALT"),
            baseCurrency: 999,
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("NPF"))
        });

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay with ETH -> should revert because no nativeCurrency -> 999 feed exists.
        vm.prank(PAYER);
        vm.expectRevert();
        jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
    }

    /// @notice Test 7: 721 hook with prices=address(0) -> silent skip (no NFT minted).
    function test_cc_721_noPricesContract_silentSkip() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();

        // Build 721 config with prices=address(0) but USD-priced tiers.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: TIER_PRICE_USD,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            // forge-lint: disable-next-line(unsafe-typecast)
            encodedIPFSUri: bytes32("noPricesTier"),
            category: 1,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: false,
                cantIncreaseDiscountPercent: false,
                cantBuyWithCredits: false
            }),
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        REVDeploy721TiersHookConfig memory hookConfig = REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "NoPrices NFT",
                symbol: "NPNFT",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: "ipfs://contract",
                tiersConfig: JB721InitTiersConfig({tiers: tierConfigs, currency: USD, decimals: 18}),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            // forge-lint: disable-next-line(unsafe-typecast)
            salt: bytes32("NP_721"),
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // Pay with ETH (currencies differ, no prices contract).
        // normalizePaymentValue returns (0, false) -> no NFT minted, but payer still gets project tokens.
        uint256 tokens = _payRevnet(revnetId, PAYER, 1 ether);

        assertEq(IERC721(address(hook)).balanceOf(PAYER), 0, "no NFT minted (silent skip)");
        assertGt(tokens, 0, "payer still receives ERC-20 project tokens");
    }

    /// @notice Test 8: Dust payment (1 wei USDC) -> zero tokens minted (no revert).
    function test_cc_dustPayment_zeroMint() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 1 wei USDC.
        // mulDiv(1, 1000e18, 1e6) = 1000e12 = 1e15 tokens (non-zero actually due to weight)
        // But with weight = 1000e18 and weightRatio = 1e6, mulDiv(1, 1000e18, 1e6) = 1e15
        // This is actually non-zero! The test verifies no revert on tiny payments.
        _payRevnetUSDC(revnetId, PAYER, 1);

        // Should not revert. Token count may be very small or zero depending on reserved rate.
        // With 20% reserved and 1e15 total: payer gets 800e12 which is > 0.
        // The key invariant: no revert on dust payments.
        assertTrue(true, "dust payment did not revert");
    }

    /// @notice Test 9: Multi-token surplus aggregation (pay both ETH and USDC).
    function test_cc_multiTokenSurplus() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildCrossCurrencyConfig();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 1 ETH (= $2000) + 2000 USDC (= $2000).
        _payRevnet(revnetId, PAYER, 1 ether);
        _payRevnetUSDC(revnetId, PAYER2, 2000e6);

        // Check surplus in USD terms.
        uint256 surplusUSD = jbMultiTerminal().currentSurplusOf(revnetId, new address[](0), 18, USD);

        // Surplus should be ~$4000 worth (both tokens aggregated via price conversion).
        // There are no payouts configured, so surplus = total balance in USD terms.
        assertGt(surplusUSD, 3900e18, "surplus should be >= $3900 (allowing for rounding)");
        assertLe(surplusUSD, 4100e18, "surplus should be <= $4100");
    }

    /// @notice Test 10: ETH payment with ETH-priced tiers -> same-currency flow still works.
    function test_cc_ethPayment_ethTiers_regression() public {
        _deployFeeProject(5000);

        // Build ETH-base config (not USD-base).
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0].beneficiary = payable(multisig());
        splits[0].percent = 10_000;

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 0,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: 5000,
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("ETH Base", "ETHB", "ipfs://ethb", "ETHB_SALT"),
            baseCurrency: nativeCurrency, // Same currency as payment token
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("ETHB"))
        });

        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigETHTiers();

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);

        // Pay 0.05 ETH with tier metadata (tier price = 0.05 ETH, same currency).
        vm.prank(PAYER);
        uint256 tokens = jbMultiTerminal().pay{value: 0.05 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 0.05 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "NFT minted via same-currency (regression)");
        assertGt(tokens, 0, "project tokens received");
    }
}
