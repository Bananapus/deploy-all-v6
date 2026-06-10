// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20Token} from "../helpers/MockTokens.sol";
import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";

/// @notice Fork tests proving an ART-like USDC revnet can use the buyback and normal AMM surfaces.
contract ArtAmmInteropForkTest is RevnetForkBase {
    using PoolIdLibrary for PoolKey;

    MockERC20Token internal usdc;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_ArtAmmInterop";
    }

    function setUp() public override {
        super.setUp();

        usdc = new MockERC20Token("Mock USDC", "USDC", 6);
        usdc.mint(PAYER, 1_000_000e6);
    }

    function test_zeroIssuanceRevnetPayUsesBuybackAfterLiquidity() public {
        (REVConfig memory cfg, JBAccountingContext[] memory contexts, REVSuckerDeploymentConfig memory suckerConfig) =
            _buildArtLikeRevnetConfig();
        cfg.stageConfigurations[0].initialIssuance = 0;

        (uint256 artProjectId,) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            accountingContextsToAccept: contexts,
            suckerDeploymentConfiguration: suckerConfig
        });

        address artToken = address(jbTokens().tokenOf(artProjectId));
        assertGt(artToken.code.length, 0, "ART token should be deployed");

        vm.prank(PAYER);
        usdc.approve(address(jbMultiTerminal()), type(uint256).max);

        uint256 prePoolPayAmount = 1e6;
        uint256 prePoolReturn = _payArtRevnetUSDC(artProjectId, PAYER, prePoolPayAmount);
        assertEq(prePoolReturn, 0, "zero issuance should not mint before liquidity");
        assertEq(jbTokens().totalBalanceOf(PAYER, artProjectId), 0, "payer should not receive ART before liquidity");

        uint256 liquidityUsdcAmount = 100_000_000e6;
        PoolKey memory key = _addArtUsdcLiquidity({projectId: artProjectId, liquidityUsdcAmount: liquidityUsdcAmount});

        // The zero-issuance case only needs the market to beat a zero terminal issuance rate. Keep the mocked TWAP
        // aligned with the pool's initialized spot price so the hook's own slippage floor is executable.
        _mockOracle(
            // forge-lint: disable-next-line(unsafe-typecast)
            int256(liquidityUsdcAmount / 2),
            0,
            uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW())
        );

        uint256 payAmount = 1e6;
        uint256 payerArtBefore = jbTokens().totalBalanceOf(PAYER, artProjectId);
        uint256 poolUsdcBefore = usdc.balanceOf(address(poolManager));
        uint256 poolArtBefore = IERC20(artToken).balanceOf(address(poolManager));

        vm.recordLogs();
        uint256 payReturn = _payArtRevnetUSDC(artProjectId, PAYER, payAmount);
        uint256 swapAmountReceived = _assertBuybackSwapLog(artProjectId, key.toId(), payAmount);

        assertEq(payReturn, swapAmountReceived, "pay return should come from the buyback swap");
        assertGt(swapAmountReceived, 0, "buyback swap should receive ART");
        assertGt(jbTokens().totalBalanceOf(PAYER, artProjectId), payerArtBefore, "buyback should deliver ART");
        assertGt(usdc.balanceOf(address(poolManager)), poolUsdcBefore, "pool should receive pay USDC");
        assertLt(IERC20(artToken).balanceOf(address(poolManager)), poolArtBefore, "pool should sell ART");
        assertEq(_terminalBalance(artProjectId, address(usdc)), prePoolPayAmount, "post-liquidity pay should not mint");
    }

    function test_artLikeRevnetPoolSupportsPlainUniswapV4SwapsBothDirections() public {
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

        PlainV4SwapRouter router = new PlainV4SwapRouter(poolManager);
        uint256 swapAmount = 1000e6;
        bool usdcIsCurrency0 = address(usdc) < artToken;

        uint256 artBefore = IERC20(artToken).balanceOf(PAYER);
        uint256 usdcBefore = usdc.balanceOf(PAYER);

        vm.startPrank(PAYER);
        IERC20(address(usdc)).approve(address(router), swapAmount);
        uint256 artReceived = router.swapExactInput({key: key, zeroForOne: usdcIsCurrency0, amountIn: swapAmount});
        vm.stopPrank();

        assertGt(artReceived, 0, "plain V4 swap should quote ART out");
        assertGt(IERC20(artToken).balanceOf(PAYER), artBefore, "plain V4 swap should deliver ART tokens");
        assertLt(usdc.balanceOf(PAYER), usdcBefore, "plain V4 swap should spend USDC");

        uint256 artToSell = artReceived / 2;
        uint256 artMid = IERC20(artToken).balanceOf(PAYER);
        uint256 usdcMid = usdc.balanceOf(PAYER);

        vm.startPrank(PAYER);
        IERC20(artToken).approve(address(router), artToSell);
        uint256 usdcReceived = router.swapExactInput({key: key, zeroForOne: !usdcIsCurrency0, amountIn: artToSell});
        vm.stopPrank();

        assertGt(usdcReceived, 0, "plain V4 swap should quote USDC out");
        assertLt(IERC20(artToken).balanceOf(PAYER), artMid, "plain V4 swap should spend ART tokens");
        assertGt(usdc.balanceOf(PAYER), usdcMid, "plain V4 swap should deliver USDC");
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

    function _payArtRevnetUSDC(uint256 projectId, address payer, uint256 amount) internal returns (uint256 tokenCount) {
        vm.startPrank(payer);
        tokenCount = jbMultiTerminal()
            .pay({
            projectId: projectId,
            token: address(usdc),
            amount: amount,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
        vm.stopPrank();
    }

    function _assertBuybackSwapLog(
        uint256 projectId,
        PoolId poolId,
        uint256 expectedAmountToSwapWith
    )
        internal
        returns (uint256 amountReceived)
    {
        bytes32 swapTopic = keccak256("Swap(uint256,uint256,bytes32,uint256,address)");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(BUYBACK_HOOK)) continue;
            if (logs[i].topics.length < 3) continue;
            if (logs[i].topics[0] != swapTopic) continue;
            if (logs[i].topics[1] != bytes32(projectId)) continue;
            if (logs[i].topics[2] != PoolId.unwrap(poolId)) continue;

            uint256 amountToSwapWith;
            address caller;
            (amountToSwapWith, amountReceived, caller) = abi.decode(logs[i].data, (uint256, uint256, address));

            assertEq(amountToSwapWith, expectedAmountToSwapWith, "swap should use the forwarded pay amount");
            assertEq(caller, address(jbMultiTerminal()), "swap should be triggered by the terminal pay hook");
            return amountReceived;
        }

        fail("buyback swap event not emitted");
    }
}

contract PlainV4SwapRouter is IUnlockCallback {
    IPoolManager public immutable poolManager;

    struct CallbackData {
        address sender;
        PoolKey key;
        SwapParams params;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    receive() external payable {}

    function swapExactInput(
        PoolKey memory key,
        bool zeroForOne,
        uint256 amountIn
    )
        external
        payable
        returns (uint256 amountOut)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exactInput = -int256(amountIn);

        amountOut = abi.decode(
            poolManager.unlock(
                abi.encode(
                    CallbackData({
                        sender: msg.sender,
                        key: key,
                        params: SwapParams({
                            zeroForOne: zeroForOne,
                            amountSpecified: exactInput,
                            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
                        })
                    })
                )
            ),
            (uint256)
        );
    }

    function unlockCallback(bytes calldata rawData) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PoolManager can call");

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta = poolManager.swap({key: data.key, params: data.params, hookData: ""});

        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // forge-lint: disable-next-line(unsafe-typecast)
        if (amount0 < 0) _settle(data.key.currency0, data.sender, uint128(-amount0));
        // forge-lint: disable-next-line(unsafe-typecast)
        if (amount1 < 0) _settle(data.key.currency1, data.sender, uint128(-amount1));
        // forge-lint: disable-next-line(unsafe-typecast)
        if (amount0 > 0) poolManager.take(data.key.currency0, data.sender, uint128(amount0));
        // forge-lint: disable-next-line(unsafe-typecast)
        if (amount1 > 0) poolManager.take(data.key.currency1, data.sender, uint128(amount1));

        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountOut = data.params.zeroForOne ? uint128(amount1) : uint128(amount0);
        return abi.encode(amountOut);
    }

    function _settle(Currency currency, address sender, uint256 amount) internal {
        if (Currency.unwrap(currency) == address(0)) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(Currency.unwrap(currency)).transferFrom(sender, address(poolManager), amount);
            poolManager.settle();
        }
    }
}
