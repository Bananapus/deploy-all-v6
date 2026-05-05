// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {IJB721TiersHook} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHook.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVDeploy721TiersHookConfig} from "@rev-net/core-v6/src/structs/REVDeploy721TiersHookConfig.sol";
import {REVCroptopAllowedPost} from "@rev-net/core-v6/src/structs/REVCroptopAllowedPost.sol";

// Uniswap V4 Router Hook
import {JBUniswapV4Hook} from "@bananapus/univ4-router-v6/src/JBUniswapV4Hook.sol";
import {JuiceboxSwapRouter} from "../helpers/JuiceboxSwapRouter.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {RevnetEcosystemBase} from "../helpers/RevnetEcosystemBase.sol";

/// @notice Ecosystem integration fork test: multi-stage revnet with buyback hook, 721 tier splits,
/// LP-split hook feeding the buyback AMM, and payments via terminal + V4 router.
///
/// Run with: forge test --match-contract EcosystemForkTest -vvv
contract EcosystemForkTest is RevnetEcosystemBase {
    using PoolIdLibrary for PoolKey;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_Eco";
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Tests
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Pre-AMM: Pay from the terminal before any pool is set up. Mint path must work.
    function test_eco_preAMM_payFromTerminal() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageNativeConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721Config();

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        uint256 tokens = _payRevnet(revnetId, PAYER, 1 ether);

        assertGt(tokens, 0, "should receive tokens pre-AMM");
        assertEq(tokens, 800e18, "should receive 800 tokens (80% of 1000 after 20% reserved)");
        assertGt(_terminalBalance(revnetId, JBConstants.NATIVE_TOKEN), 0, "terminal should have balance");
    }

    /// @notice Pre-AMM: Pay with 721 tier metadata -> NFT minted + 30% tier split.
    function test_eco_preAMM_payWith721TierSplit() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageNativeConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721Config();

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

        vm.prank(PAYER);
        uint256 tokens = jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should own 1 NFT");
        assertGt(tokens, 0, "should receive tokens");
        assertLt(tokens, 800e18, "should be less than 800 due to tier split");
    }

    /// @notice Distribute reserved tokens -> LP-split hook accumulates them.
    function test_eco_lpSplitHookAccumulates() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageNativeConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        assertGt(pending, 0, "should have pending reserved tokens");

        jbController().sendReservedTokensToSplitsOf(revnetId);

        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);
        assertGt(accumulated, 0, "LP split hook should have accumulated tokens");

        uint256 multisigTokens = jbTokens().totalBalanceOf(multisig(), revnetId);
        assertGt(multisigTokens, 0, "multisig should receive reserved tokens");
    }

    /// @notice Post-AMM: Pay from terminal after pool is set up -> buyback hook compares swap vs mint.
    function test_eco_postAMM_payFromTerminal() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageNativeConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupNativePool(revnetId, 10_000 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        uint256 tokens = _payRevnet(revnetId, PAYER, 1 ether);
        assertGt(tokens, 0, "should receive tokens post-AMM");
        assertGt(_terminalBalance(revnetId, JBConstants.NATIVE_TOKEN), 0, "terminal balance should increase");
    }

    /// @notice Post-AMM: Pay with 721 tier metadata while buyback hook is active.
    function test_eco_postAMM_payWith721TierSplitAndBuyback() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageNativeConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721Config();

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        _setupNativePool(revnetId, 10_000 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataNoQuote(metadataTarget);

        vm.prank(PAYER);
        uint256 tokens = jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should own 1 NFT");
        assertGt(tokens, 0, "should receive tokens with 721 tier + buyback");
    }

    /// @notice Warp to stage 2, verify new cashOutTaxRate applies and buyback hook still works.
    function test_eco_crossStageWithBuyback() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageNativeConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupNativePool(revnetId, 10_000 ether);
        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 borrowableStage1 =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN)));

        vm.warp(block.timestamp + STAGE_DURATION + 1);

        uint256 borrowableStage2 =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN)));
        assertGt(borrowableStage2, borrowableStage1, "borrowable should increase in stage 2");

        address payer2 = makeAddr("payer2");
        vm.deal(payer2, 10 ether);
        uint256 tokens = _payRevnet(revnetId, payer2, 1 ether);
        assertGt(tokens, 0, "payment should work in stage 2 with buyback");
    }

    /// @notice Pay via the Uniswap V4 router hook (JBUniswapV4Hook) — routes to best path.
    function test_eco_payViaRouter() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageNativeConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupNativePool(revnetId, 10_000 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        // Deploy the V4 router hook at a valid hook address.
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(poolManager, jbTokens(), jbDirectory(), jbPrices());
        (, bytes32 salt) = HookMiner.find(address(this), flags, type(JBUniswapV4Hook).creationCode, constructorArgs);
        JBUniswapV4Hook routerHook = new JBUniswapV4Hook{salt: salt}(poolManager, jbTokens(), jbDirectory(), jbPrices());

        // Create a V4 pool with the router hook.
        address projectToken = address(jbTokens().tokenOf(revnetId));
        address token0 = projectToken < WETH_ADDR ? projectToken : WETH_ADDR;
        address token1 = projectToken < WETH_ADDR ? WETH_ADDR : projectToken;

        PoolKey memory routerKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(routerHook))
        });

        uint160 sqrtPrice = TickMath.getSqrtPriceAtTick(0);
        poolManager.initialize(routerKey, sqrtPrice);

        // Add liquidity to the router pool.
        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, 1000 ether);
        vm.deal(address(liqHelper), 1000 ether);
        vm.prank(address(liqHelper));
        weth.deposit{value: 1000 ether}();

        vm.startPrank(address(liqHelper));
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);
        IERC20(WETH_ADDR).approve(address(poolManager), type(uint256).max);
        vm.stopPrank();

        vm.prank(address(liqHelper));
        liqHelper.addLiquidity(routerKey, -60, 60, 100 ether);

        // Deploy JuiceboxSwapRouter utility.
        JuiceboxSwapRouter jbSwapRouter = new JuiceboxSwapRouter(poolManager);

        // PAYER swaps WETH -> project token via the router.
        vm.prank(PAYER);
        weth.deposit{value: 1 ether}();

        vm.startPrank(PAYER);
        IERC20(WETH_ADDR).approve(address(jbSwapRouter), 1 ether);

        bool wethIs0 = WETH_ADDR < projectToken;
        SwapParams memory params = SwapParams({
            zeroForOne: wethIs0,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: wethIs0 ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        jbSwapRouter.swap(routerKey, params, 0);
        vm.stopPrank();

        uint256 payerTokens = IERC20(projectToken).balanceOf(PAYER);
        assertGt(payerTokens, 0, "payer should receive project tokens via router");
    }

    /// @notice Full lifecycle: deploy -> pre-AMM pay -> distribute reserved -> set up pool -> post-AMM pay -> cashout.
    function test_eco_fullLifecycle() public {
        _deployFeeProject(5000);

        // 1. Deploy revnet with 721 + LP-split.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageNativeConfigWithLPSplit(7000, 2000, 2000);
        REVDeploy721TiersHookConfig memory hookConfig = _build721Config();

        (uint256 revnetId, IJB721TiersHook hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });

        // 2. Pre-AMM payment (mint path only, no pool).
        uint256 tokensPreAMM = _payRevnet(revnetId, PAYER, 5 ether);
        assertGt(tokensPreAMM, 0, "pre-AMM payment should mint tokens");

        _payRevnet(revnetId, BORROWER, 5 ether);

        // 3. Distribute reserved tokens -> LP-split hook accumulates.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        if (pending > 0) {
            jbController().sendReservedTokensToSplitsOf(revnetId);
        }
        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);
        assertGt(accumulated, 0, "LP split hook should accumulate from reserved distribution");

        // 4. Set up buyback pool.
        _setupNativePool(revnetId, 10_000 ether);

        // 5. Post-AMM payment with 721 tier.
        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataNoQuote(metadataTarget);

        vm.prank(PAYER);
        uint256 tokensPostAMM = jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });
        assertGt(tokensPostAMM, 0, "post-AMM payment should return tokens");
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "should own NFT from post-AMM payment");

        // 6. Cash out some tokens.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 cashOutCount = payerTokens / 2;
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: cashOutCount,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        assertGt(PAYER.balance, payerEthBefore, "should receive ETH from cashout");
        assertEq(
            jbTokens().totalBalanceOf(PAYER, revnetId), payerTokens - cashOutCount, "remaining tokens should be correct"
        );
    }
}
