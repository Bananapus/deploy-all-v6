// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {JuiceboxSwapRouter} from "../helpers/JuiceboxSwapRouter.sol";
import {MockERC20Token} from "../helpers/MockTokens.sol";
import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";

/// @notice Fork test proving an ART-like USDC revnet can use a normal AMM surface.
///
/// This intentionally swaps through a small Uniswap-style router instead of a Juicebox terminal:
/// deploy ART-like revnet -> add ART/USDC liquidity -> trade USDC for ART through PoolManager.
contract ArtAmmInteropForkTest is RevnetForkBase {
    MockERC20Token internal usdc;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_ArtAmmInterop";
    }

    function setUp() public override {
        super.setUp();

        usdc = new MockERC20Token("Mock USDC", "USDC", 6);
        usdc.mint(PAYER, 1_000_000e6);
    }

    function test_artLikeRevnetAllowsExternalAmmLiquidityAndTrade() public {
        (REVConfig memory cfg, JBAccountingContext[] memory contexts, REVSuckerDeploymentConfig memory suckerConfig) =
            _buildArtLikeRevnetConfig();

        (uint256 artProjectId,) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            accountingContextsToAccept: contexts,
            suckerDeploymentConfiguration: suckerConfig
        });

        address artToken = address(jbTokens().tokenOf(artProjectId));
        assertGt(artToken.code.length, 0, "ART token should be deployed");

        PoolKey memory key = _addArtUsdcLiquidity({projectId: artProjectId, liquidityUsdcAmount: 100_000e6});

        JuiceboxSwapRouter router = new JuiceboxSwapRouter(poolManager);
        uint256 swapAmount = 1000e6;
        bool usdcIsCurrency0 = address(usdc) < artToken;

        uint256 artBefore = IERC20(artToken).balanceOf(PAYER);
        uint256 usdcBefore = usdc.balanceOf(PAYER);

        vm.startPrank(PAYER);
        IERC20(address(usdc)).approve(address(router), swapAmount);
        router.swap(
            key,
            SwapParams({
                zeroForOne: usdcIsCurrency0,
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: usdcIsCurrency0 ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            0
        );
        vm.stopPrank();

        assertGt(IERC20(artToken).balanceOf(PAYER), artBefore, "off-JB swap should deliver ART tokens");
        assertLt(usdc.balanceOf(PAYER), usdcBefore, "off-JB swap should spend USDC");
    }

    function _buildArtLikeRevnetConfig()
        internal
        view
        returns (REVConfig memory cfg, JBAccountingContext[] memory contexts, REVSuckerDeploymentConfig memory sdc)
    {
        contexts = new JBAccountingContext[](1);
        contexts[0] = JBAccountingContext({token: address(usdc), decimals: 6, currency: uint32(uint160(address(usdc)))});

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
            cashOutTaxRate: 5000,
            extraMetadata: 0
        });

        cfg = REVConfig({
            description: REVDescription("Art", "ART", "ipfs://art", "ART_SALT"),
            baseCurrency: uint32(uint160(address(usdc))),
            operator: multisig(),
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("ART"))
        });
    }

    function _addArtUsdcLiquidity(uint256 projectId, uint256 liquidityUsdcAmount)
        internal
        returns (PoolKey memory key)
    {
        address artToken = address(jbTokens().tokenOf(projectId));
        address token0 = address(usdc) < artToken ? address(usdc) : artToken;
        address token1 = address(usdc) < artToken ? artToken : address(usdc);

        key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(),
            tickSpacing: REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(),
            hooks: IHooks(address(0))
        });

        usdc.mint(address(liqHelper), liquidityUsdcAmount);

        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), projectId, liquidityUsdcAmount * 1e12);

        vm.startPrank(address(liqHelper));
        IERC20(address(usdc)).approve(address(poolManager), type(uint256).max);
        IERC20(artToken).approve(address(poolManager), type(uint256).max);
        vm.stopPrank();

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 liquidityDelta = int256(liquidityUsdcAmount / 2);
        vm.prank(address(liqHelper));
        liqHelper.addLiquidity(key, TICK_LOWER, TICK_UPPER, liquidityDelta);

        int24 issuanceTick = address(usdc) < artToken ? int24(345_400) : int24(-345_400);
        _mockOracle(liquidityDelta, issuanceTick, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
    }
}
