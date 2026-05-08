// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJB721TiersHook} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHook.sol";
import {IJB721TokenUriResolver} from "@bananapus/721-hook-v6/src/interfaces/IJB721TokenUriResolver.sol";
import {JB721TierConfig} from "@bananapus/721-hook-v6/src/structs/JB721TierConfig.sol";
import {JB721InitTiersConfig} from "@bananapus/721-hook-v6/src/structs/JB721InitTiersConfig.sol";
import {JB721TierConfigFlags} from "@bananapus/721-hook-v6/src/structs/JB721TierConfigFlags.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVDeploy721TiersHookConfig} from "@rev-net/core-v6/src/structs/REVDeploy721TiersHookConfig.sol";
import {REVBaseline721HookConfig} from "@rev-net/core-v6/src/structs/REVBaseline721HookConfig.sol";
import {REV721TiersHookFlags} from "@rev-net/core-v6/src/structs/REV721TiersHookFlags.sol";
import {REVCroptopAllowedPost} from "@rev-net/core-v6/src/structs/REVCroptopAllowedPost.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {RevnetEcosystemBase} from "../helpers/RevnetEcosystemBase.sol";
import {MockERC20Token} from "../helpers/MockTokens.sol";

/// @notice USDC ecosystem integration fork test: multi-stage revnet with buyback hook, 721 tier splits,
/// LP-split hook, and payments via USDC terminal.
///
/// Run with: forge test --match-contract USDCEcosystemForkTest -vvv
contract USDCEcosystemForkTest is RevnetEcosystemBase {
    uint104 constant USDC_TIER_PRICE = 100e6; // 100 USDC for NFT tier

    MockERC20Token usdc;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_USDC";
    }

    function setUp() public override {
        super.setUp();
        usdc = new MockERC20Token("Mock USDC", "USDC", 6);
        usdc.mint(PAYER, 200_000e6);
        usdc.mint(BORROWER, 100_000e6);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  USDC Config Builders
    // ═══════════════════════════════════════════════════════════════════

    function _buildTwoStageUSDCConfigWithLPSplit(
        uint16 stage1Tax,
        uint16 stage2Tax,
        uint16 splitPercent
    )
        internal
        view
        returns (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc)
    {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: address(usdc), decimals: 6, currency: uint32(uint160(address(usdc)))});
        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBSplit[] memory splits = new JBSplit[](2);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2),
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(LP_SPLIT_HOOK))
        });
        splits[1] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2),
            projectId: 0,
            beneficiary: payable(multisig()),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        REVStageConfig[] memory stages = new REVStageConfig[](2);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: splitPercent,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: stage1Tax,
            extraMetadata: 0
        });
        stages[1] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp + STAGE_DURATION),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: splitPercent,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: stage2Tax,
            extraMetadata: 0
        });

        cfg = REVConfig({
            description: REVDescription("USDC Ecosystem", "UECO", "ipfs://ueco", "UECO_SALT"),
            baseCurrency: uint32(uint160(address(usdc))),
            splitOperator: multisig(),
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("UECO"))
        });
    }

    function _build721ConfigUSDC() internal view returns (REVDeploy721TiersHookConfig memory) {
        JB721TierConfig[] memory tiers = new JB721TierConfig[](1);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(SPLIT_BENEFICIARY),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        tiers[0] = JB721TierConfig({
            price: USDC_TIER_PRICE,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            // forge-lint: disable-next-line(unsafe-typecast)
            encodedIPFSUri: bytes32("tier1"),
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
            splitPercent: 300_000_000,
            splits: splits
        });

        return REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "USDC Ecosystem NFT",
                symbol: "UECONOMFT",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: "ipfs://contract",
                tiersConfig: JB721InitTiersConfig({
                    tiers: tiers, currency: uint32(uint160(address(usdc))), decimals: 6
                }),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            // forge-lint: disable-next-line(unsafe-typecast)
            salt: bytes32("UECO_721"),
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  USDC Pool Helper
    // ═══════════════════════════════════════════════════════════════════

    function _setupUSDCBuybackPool(uint256 revnetId, uint256 liquidityAmount) internal returns (PoolKey memory key) {
        address projectToken = address(jbTokens().tokenOf(revnetId));
        require(projectToken != address(0), "project token not deployed");

        address token0 = address(usdc) < projectToken ? address(usdc) : projectToken;
        address token1 = address(usdc) < projectToken ? projectToken : address(usdc);

        key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(),
            tickSpacing: REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(),
            hooks: IHooks(address(0))
        });

        usdc.mint(address(liqHelper), liquidityAmount);
        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, liquidityAmount * 1e12);

        vm.startPrank(address(liqHelper));
        IERC20(address(usdc)).approve(address(poolManager), type(uint256).max);
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);
        vm.stopPrank();

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 liquidityDelta = int256(liquidityAmount / 2);
        vm.prank(address(liqHelper));
        liqHelper.addLiquidity(key, TICK_LOWER, TICK_UPPER, liquidityDelta);

        int24 issuanceTick = address(usdc) < projectToken ? int24(345_400) : int24(-345_400);
        _mockOracle(liquidityDelta, issuanceTick, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  USDC Payment Helpers
    // ═══════════════════════════════════════════════════════════════════

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

    function _terminalBalanceUSDC(uint256 projectId) internal view returns (uint256) {
        return jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, address(usdc));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Tests
    // ═══════════════════════════════════════════════════════════════════

    function test_eco_usdc_preAMM_payFromTerminal() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageUSDCConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigUSDC();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        uint256 tokens = _payRevnetUSDC(revnetId, PAYER, 1000e6);

        assertGt(tokens, 0, "should receive tokens pre-AMM");
        assertEq(tokens, 800_000e18, "should receive 800,000 tokens (80% of 1,000,000 after 20% reserved)");
        assertGt(_terminalBalanceUSDC(revnetId), 0, "terminal should have USDC balance");
    }

    function test_eco_usdc_preAMM_payWith721TierSplit() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageUSDCConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigUSDC();

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataNoQuote(metadataTarget);

        usdc.mint(PAYER, 100e6);
        vm.startPrank(PAYER);
        usdc.approve(address(jbMultiTerminal()), 100e6);
        uint256 tokens = jbMultiTerminal()
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

        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should own 1 NFT");
        assertEq(usdc.balanceOf(SPLIT_BENEFICIARY), 30e6, "split beneficiary should have 30 USDC");
        assertGt(tokens, 0, "should receive tokens");
        assertEq(tokens, 56_000e18, "payer should receive 56,000 tokens (80% of 70k)");
    }

    function test_eco_usdc_lpSplitHookAccumulates() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageUSDCConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _payRevnetUSDC(revnetId, PAYER, 10_000e6);
        _payRevnetUSDC(revnetId, BORROWER, 5000e6);

        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        assertGt(pending, 0, "should have pending reserved tokens");

        jbController().sendReservedTokensToSplitsOf(revnetId);

        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);
        assertGt(accumulated, 0, "LP split hook should have accumulated tokens");

        uint256 multisigTokens = jbTokens().totalBalanceOf(multisig(), revnetId);
        assertGt(multisigTokens, 0, "multisig should receive reserved tokens");
    }

    function test_eco_usdc_postAMM_payFromTerminal() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageUSDCConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupUSDCBuybackPool(revnetId, 10_000e6);
        _payRevnetUSDC(revnetId, BORROWER, 5000e6);

        uint256 tokens = _payRevnetUSDC(revnetId, PAYER, 1000e6);
        assertGt(tokens, 0, "should receive tokens post-AMM");
        assertGt(_terminalBalanceUSDC(revnetId), 0, "terminal balance should increase");
    }

    function test_eco_usdc_crossStageWithBuyback() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageUSDCConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupUSDCBuybackPool(revnetId, 10_000e6);
        _payRevnetUSDC(revnetId, PAYER, 10_000e6);
        _payRevnetUSDC(revnetId, BORROWER, 5000e6);

        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 borrowableStage1 =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 6, uint32(uint160(address(usdc))));

        vm.warp(block.timestamp + STAGE_DURATION + 1);

        uint256 borrowableStage2 =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 6, uint32(uint160(address(usdc))));
        assertGt(borrowableStage2, borrowableStage1, "borrowable should increase in stage 2");

        address payer2 = makeAddr("payer2");
        uint256 tokens = _payRevnetUSDC(revnetId, payer2, 1000e6);
        assertGt(tokens, 0, "payment should work in stage 2 with buyback");
    }

    function test_eco_usdc_fullLifecycle() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageUSDCConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721ConfigUSDC();

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // 1. Pre-AMM payment.
        uint256 tokensPreAMM = _payRevnetUSDC(revnetId, PAYER, 5000e6);
        assertGt(tokensPreAMM, 0, "pre-AMM payment should mint tokens");
        _payRevnetUSDC(revnetId, BORROWER, 5000e6);

        // 2. Distribute reserved tokens.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        if (pending > 0) {
            jbController().sendReservedTokensToSplitsOf(revnetId);
        }
        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);
        assertGt(accumulated, 0, "LP split hook should accumulate from reserved distribution");

        // 3. Set up USDC buyback pool.
        _setupUSDCBuybackPool(revnetId, 10_000e6);

        // 4. Post-AMM payment with 721 tier.
        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataNoQuote(metadataTarget);

        usdc.mint(PAYER, 100e6);
        vm.startPrank(PAYER);
        usdc.approve(address(jbMultiTerminal()), 100e6);
        uint256 tokensPostAMM = jbMultiTerminal()
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
        assertGt(tokensPostAMM, 0, "post-AMM payment should return tokens");
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "should own NFT from post-AMM payment");

        // 5. Cash out some tokens for USDC.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 cashOutCount = payerTokens / 2;
        uint256 payerUSDCBefore = usdc.balanceOf(PAYER);

        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: cashOutCount,
            tokenToReclaim: address(usdc),
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        assertGt(usdc.balanceOf(PAYER), payerUSDCBefore, "should receive USDC from cashout");
        assertEq(
            jbTokens().totalBalanceOf(PAYER, revnetId), payerTokens - cashOutCount, "remaining tokens should be correct"
        );
    }
}
