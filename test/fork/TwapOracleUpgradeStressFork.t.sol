// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";
import {JuiceboxSwapRouter} from "../helpers/JuiceboxSwapRouter.sol";
import {RevnetEcosystemBase} from "../helpers/RevnetEcosystemBase.sol";

// Buyback Hook
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";

// Core
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBSplitGroupIds} from "@bananapus/core-v6/src/libraries/JBSplitGroupIds.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";

// Revnet
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

// Router Terminal
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";
import {IWETH9 as IRouterWETH9} from "@bananapus/router-terminal-v6/src/interfaces/IWETH9.sol";

// Suckers
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";

// Uniswap V4
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

// Uniswap V4 Hooks
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";
import {JBUniswapV4LPSplitHookDeployer} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHookDeployer.sol";
import {JBUniswapV4Hook} from "@bananapus/univ4-router-v6/src/JBUniswapV4Hook.sol";

// Math
import {mulDiv, sqrt} from "@prb/math/src/Common.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Fork stress test for the post-launch TWAP oracle migration across the router, buyback hook, router
/// terminal, and LP split hook packages.
///
/// The revnet is first deployed through the old hookless-oracle path, then migrated onto freshly deployed replacement
/// contracts from the unmerged package pins in this deployment repo. The flow proves that historical registry cohorts
/// do not move silently, project-level operator txs switch the existing revnet, and the replacement hooks interoperate
/// after the hooked V4 oracle has accrued real coverage.
contract TwapOracleUpgradeStressForkTest is RevnetEcosystemBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    address internal constant V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    uint256 internal constant _FEE_PROJECT_ID = 1;
    uint256 internal constant _LP_SPLIT_FEE_PERCENT = 2000;

    address internal PAYER2 = makeAddr("payer2");

    JBBuybackHook internal _newBuybackHook;
    JBRouterTerminal internal _newRouterTerminal;
    JBRouterTerminal internal _oldRouterTerminal;
    JBRouterTerminalRegistry internal _routerRegistry;
    JBUniswapV4Hook internal _newOracleHook;
    JBUniswapV4LPSplitHook internal _newLpSplitHook;
    JBUniswapV4LPSplitHookDeployer internal _newLpSplitHookDeployer;
    JuiceboxSwapRouter internal _swapRouter;

    /// @dev Accept LP position NFTs from PositionManager.
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_TwapUpgradeStress";
    }

    function _forkBlock() internal pure override returns (uint256) {
        return 0;
    }

    function setUp() public override {
        super.setUp();

        vm.deal(PAYER, 250 ether);
        vm.deal(PAYER2, 250 ether);
        vm.deal(address(this), 250 ether);

        _swapRouter = new JuiceboxSwapRouter(poolManager);
    }

    /// @notice Migrates an existing old-stack revnet and checks the replacement stack remains fully interactive.
    function test_stress_migratedRevnetFullInterop() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBAccountingContext[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageNativeConfigWithLPSplit({stage1Tax: 5000, stage2Tax: 5000, splitPercent: 2000});

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, accountingContextsToAccept: tc, suckerDeploymentConfiguration: sdc
        });

        _mockDefaultOracle();

        uint256 oldStackTokens = _payRevnet({revnetId: revnetId, payer: PAYER, amount: 10 ether});
        assertGt(oldStackTokens, 0, "old-stack payment should mint");

        _payRevnet({revnetId: revnetId, payer: PAYER2, amount: 10 ether});
        jbController().sendReservedTokensToSplitsOf({projectId: revnetId});
        assertGt(LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId), 0, "old LP split should accumulate first");

        _deployReplacementStack();
        _migrateFeeProjectInInfraProposal();
        _migrateRevnetOperatorSettings({revnetId: revnetId});

        assertEq(address(BUYBACK_REGISTRY.hookOf(revnetId)), address(_newBuybackHook), "revnet buyback hook");
        assertEq(address(_routerRegistry.terminalOf(revnetId)), address(_newRouterTerminal), "revnet router terminal");

        uint256 newStackTokens = _payRevnet({revnetId: revnetId, payer: PAYER2, amount: 5 ether});
        assertGt(newStackTokens, 0, "new-stack direct payment should mint or buy back");

        jbController().sendReservedTokensToSplitsOf({projectId: revnetId});
        assertGt(_newLpSplitHook.accumulatedProjectTokens(revnetId), 0, "new LP split should accumulate");

        _grantDeployPoolPermission({operator: address(this), projectId: revnetId});
        _newLpSplitHook.deployPool({projectId: revnetId, minCashOutReturn: 0});

        PoolKey memory buybackKey = _newBuybackHook.poolKeyOf({projectId: revnetId, terminalToken: address(0)});
        PoolKey memory lpKey = _newLpSplitHook.poolKeyOf({projectId: revnetId, terminalToken: JBConstants.NATIVE_TOKEN});
        assertEq(address(buybackKey.hooks), address(_newOracleHook), "buyback pool should use new oracle hook");
        assertEq(address(lpKey.hooks), address(_newOracleHook), "LP split pool should use new oracle hook");
        assertEq(
            PoolId.unwrap(buybackKey.toId()),
            PoolId.unwrap(lpKey.toId()),
            "buyback and LP split should share one hooked pool"
        );
        assertGt(
            _newLpSplitHook.tokenIdOf({projectId: revnetId, terminalToken: JBConstants.NATIVE_TOKEN}),
            0,
            "new LP split should own a position"
        );

        _seedHookedPoolLiquidity({revnetId: revnetId, liquidityTokenAmount: 10_000 ether});
        _warmOracleCoverage(buybackKey);

        assertTrue(
            _newOracleHook.hasObservationCoverage({key: buybackKey, secondsAgo: _newOracleHook.TWAP_PERIOD()}),
            "oracle should cover the TWAP window"
        );

        uint256 directBefore = jbTokens().totalBalanceOf({holder: PAYER, projectId: revnetId});
        uint256 directTokens = _payRevnet({revnetId: revnetId, payer: PAYER, amount: 1 ether});
        assertGt(directTokens, 0, "direct payment should return project tokens");
        assertEq(
            jbTokens().totalBalanceOf({holder: PAYER, projectId: revnetId}),
            directBefore + directTokens,
            "direct payment balance"
        );

        uint256 routerTokens = _payViaRouterRegistry({revnetId: revnetId, payer: PAYER2, amount: 1 ether});
        assertGt(routerTokens, 0, "router-registry payment should return project tokens");
        assertEq(address(_newRouterTerminal).balance, 0, "new router should not retain native tokens");
        assertEq(weth.balanceOf(address(_newRouterTerminal)), 0, "new router should not retain WETH");

        _payRevnet({revnetId: revnetId, payer: PAYER, amount: 5 ether});
        jbController().sendReservedTokensToSplitsOf({projectId: revnetId});

        uint256 accumulatedBeforeAdd = _newLpSplitHook.accumulatedProjectTokens(revnetId);
        assertGt(accumulatedBeforeAdd, 0, "new LP split should have post-deploy accumulation");

        _grantDeployPoolPermission({operator: address(this), projectId: revnetId});
        _newLpSplitHook.addLiquidity({
            projectId: revnetId, terminalToken: JBConstants.NATIVE_TOKEN, minCashOutReturn: 0
        });
        assertLt(
            _newLpSplitHook.accumulatedProjectTokens(revnetId),
            accumulatedBeforeAdd,
            "addLiquidity should consume accumulation"
        );

        uint256 payerBalance = jbTokens().totalBalanceOf({holder: PAYER, projectId: revnetId});
        uint256 ethBefore = PAYER.balance;

        uint256 cashOutCount = payerBalance / 4;

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

        assertEq(
            jbTokens().totalBalanceOf({holder: PAYER, projectId: revnetId}),
            payerBalance - cashOutCount,
            "cash out should burn project tokens"
        );
        assertGt(PAYER.balance, ethBefore, "cash out should pay beneficiary");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Replacement Stack Deployment
    // ═══════════════════════════════════════════════════════════════════

    function _deployReplacementStack() internal {
        _newOracleHook = _deployReplacementOracleHook();

        _newBuybackHook = new JBBuybackHook({
            directory: jbDirectory(),
            permissions: jbPermissions(),
            prices: jbPrices(),
            projects: jbProjects(),
            tokens: jbTokens(),
            deployer: address(this),
            trustedForwarder: address(0)
        });
        _newBuybackHook.setChainSpecificConstants({
            newPoolManager: poolManager, newOracleHook: IHooks(address(_newOracleHook))
        });

        _oldRouterTerminal = new JBRouterTerminal({
            directory: jbDirectory(),
            tokens: jbTokens(),
            permit2: permit2(),
            buybackHook: address(BUYBACK_HOOK),
            trustedForwarder: address(0),
            deployer: address(this)
        });
        _oldRouterTerminal.setChainSpecificConstants({
            newWrappedNativeToken: IRouterWETH9(WETH_ADDR),
            newFactory: IUniswapV3Factory(V3_FACTORY),
            newPoolManager: poolManager,
            newUniv4Hook: address(0)
        });

        _newRouterTerminal = new JBRouterTerminal({
            directory: jbDirectory(),
            tokens: jbTokens(),
            permit2: permit2(),
            buybackHook: address(_newBuybackHook),
            trustedForwarder: address(0),
            deployer: address(this)
        });
        _newRouterTerminal.setChainSpecificConstants({
            newWrappedNativeToken: IRouterWETH9(WETH_ADDR),
            newFactory: IUniswapV3Factory(V3_FACTORY),
            newPoolManager: poolManager,
            newUniv4Hook: address(_newOracleHook)
        });

        _routerRegistry = new JBRouterTerminalRegistry({
            permissions: jbPermissions(),
            projects: jbProjects(),
            permit2: permit2(),
            owner: address(this),
            trustedForwarder: address(0)
        });
        _routerRegistry.setDefaultTerminal({terminal: IJBTerminal(address(_oldRouterTerminal))});

        JBUniswapV4LPSplitHook lpSplitImpl = new JBUniswapV4LPSplitHook(
            address(jbDirectory()),
            jbPermissions(),
            address(jbTokens()),
            permit2(),
            IJBSuckerRegistry(address(SUCKER_REGISTRY))
        );
        _newLpSplitHookDeployer = new JBUniswapV4LPSplitHookDeployer({
            addressRegistry: ADDRESS_REGISTRY, newHookImplementation: lpSplitImpl, deployer: address(this)
        });
        _newLpSplitHookDeployer.setChainSpecificConstants({
            newPoolManager: poolManager,
            newPositionManager: positionManager,
            newOracleHook: IHooks(address(_newOracleHook))
        });

        _newLpSplitHook = JBUniswapV4LPSplitHook(
            payable(address(
                    _newLpSplitHookDeployer.deployHookFor({
                        feeProjectId: _FEE_PROJECT_ID,
                        feePercent: _LP_SPLIT_FEE_PERCENT,
                        buybackHook: IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
                        salt: bytes32("TWAP_UPGRADE_STRESS_LP")
                    })
                ))
        );
    }

    function _deployReplacementOracleHook() internal returns (JBUniswapV4Hook hook) {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );
        bytes memory constructorArgs = abi.encode(poolManager, jbTokens(), jbDirectory(), jbPrices());

        (, bytes32 salt) = HookMiner.find(address(this), flags, type(JBUniswapV4Hook).creationCode, constructorArgs);
        hook = new JBUniswapV4Hook{salt: salt}({
            poolManager: poolManager, tokens: jbTokens(), directory: jbDirectory(), prices: jbPrices()
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Migration Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _migrateFeeProjectInInfraProposal() internal {
        BUYBACK_REGISTRY.setDefaultHook({hook: IJBRulesetDataHook(address(_newBuybackHook))});
        _routerRegistry.setDefaultTerminal({terminal: IJBTerminal(address(_newRouterTerminal))});

        vm.startPrank(multisig());
        BUYBACK_REGISTRY.setHookFor({projectId: _FEE_PROJECT_ID, hook: IJBRulesetDataHook(address(_newBuybackHook))});
        _routerRegistry.setTerminalFor({projectId: _FEE_PROJECT_ID, terminal: IJBTerminal(address(_newRouterTerminal))});
        vm.stopPrank();

        _initializeReplacementBuybackPoolFor(_FEE_PROJECT_ID);

        BUYBACK_REGISTRY.disallowHook({hook: IJBRulesetDataHook(address(BUYBACK_HOOK))});
        _routerRegistry.disallowTerminal({terminal: IJBTerminal(address(_oldRouterTerminal))});

        assertFalse(
            BUYBACK_REGISTRY.isHookAllowed(IJBRulesetDataHook(address(BUYBACK_HOOK))), "old hook should be retired"
        );
        assertFalse(
            _routerRegistry.isTerminalAllowed(IJBTerminal(address(_oldRouterTerminal))),
            "old terminal should be retired"
        );
    }

    function _migrateRevnetOperatorSettings(uint256 revnetId) internal {
        assertEq(address(BUYBACK_REGISTRY.hookOf(revnetId)), address(BUYBACK_HOOK), "historical buyback default");
        assertEq(address(_routerRegistry.terminalOf(revnetId)), address(_oldRouterTerminal), "historical terminal");

        vm.startPrank(multisig());
        BUYBACK_REGISTRY.setHookFor({projectId: revnetId, hook: IJBRulesetDataHook(address(_newBuybackHook))});
        _routerRegistry.setTerminalFor({projectId: revnetId, terminal: IJBTerminal(address(_newRouterTerminal))});
        vm.stopPrank();

        _initializeReplacementBuybackPoolFor(revnetId);
        _routeReservedSplitsToReplacementLpHook(revnetId);
    }

    function _initializeReplacementBuybackPoolFor(uint256 projectId) internal {
        (bool ok, uint160 sqrtPriceX96) = _poolInitSqrtPriceX96For(projectId);
        assertTrue(ok, "pool init price");

        uint24 poolFee = REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE();
        int24 tickSpacing = REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING();
        uint32 twapWindow = REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW();

        vm.prank(multisig());
        BUYBACK_REGISTRY.initializePoolFor({
            projectId: projectId,
            fee: poolFee,
            tickSpacing: tickSpacing,
            twapWindow: twapWindow,
            terminalToken: JBConstants.NATIVE_TOKEN,
            sqrtPriceX96: sqrtPriceX96
        });
    }

    function _routeReservedSplitsToReplacementLpHook(uint256 revnetId) internal {
        (JBRuleset memory ruleset,) = jbController().currentRulesetOf(revnetId);

        JBSplit[] memory splits = new JBSplit[](2);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2),
            projectId: 0,
            beneficiary: payable(address(0)),
            lockedUntil: 0,
            hook: IJBSplitHook(address(_newLpSplitHook))
        });
        splits[1] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2),
            projectId: 0,
            beneficiary: payable(multisig()),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JBSplitGroup[] memory groups = new JBSplitGroup[](1);
        groups[0] = JBSplitGroup({groupId: JBSplitGroupIds.RESERVED_TOKENS, splits: splits});

        vm.prank(multisig());
        jbController().setSplitGroupsOf({projectId: revnetId, rulesetId: ruleset.id, splitGroups: groups});
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Interaction Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _grantDeployPoolPermission(address operator, uint256 projectId) internal {
        address projectOwner = jbProjects().ownerOf(projectId);
        mockExpect(
            address(jbPermissions()),
            abi.encodeCall(IJBPermissions.hasPermission, (operator, projectOwner, projectId, 29, true, true)),
            abi.encode(true)
        );
    }

    function _mockDefaultOracle() internal {
        _mockOracle(1, 0, REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW());
    }

    function _payViaRouterRegistry(uint256 revnetId, address payer, uint256 amount) internal returns (uint256 tokens) {
        uint256 balanceBefore = jbTokens().totalBalanceOf({holder: payer, projectId: revnetId});

        vm.prank(payer);
        tokens = _routerRegistry.pay{value: amount}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: amount,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        assertEq(
            jbTokens().totalBalanceOf({holder: payer, projectId: revnetId}),
            balanceBefore + tokens,
            "router-registry payment balance"
        );
    }

    function _seedHookedPoolLiquidity(
        uint256 revnetId,
        uint256 liquidityTokenAmount
    )
        internal
        returns (PoolKey memory key)
    {
        key = _newBuybackHook.poolKeyOf({projectId: revnetId, terminalToken: address(0)});
        address projectToken = address(jbTokens().tokenOf(revnetId));

        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, liquidityTokenAmount * 50);
        vm.deal(address(liqHelper), liquidityTokenAmount);

        vm.prank(address(liqHelper));
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 liquidityDelta = int256(liquidityTokenAmount / 50);
        vm.prank(address(liqHelper));
        liqHelper.addLiquidity{value: liquidityTokenAmount}(key, TICK_LOWER, TICK_UPPER, liquidityDelta);
    }

    function _swapNativeThroughHook(PoolKey memory key, uint256 amount) internal {
        bool zeroForOne = Currency.unwrap(key.currency0) == address(0);
        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;

        _swapRouter.swap{value: amount}(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(amount),
                sqrtPriceLimitX96: sqrtPriceLimitX96
            }),
            0
        );
    }

    function _warmOracleCoverage(PoolKey memory key) internal {
        vm.warp(block.timestamp + 1);
        _swapNativeThroughHook({key: key, amount: 0.001 ether});

        vm.warp(block.timestamp + _newOracleHook.TWAP_PERIOD());
        _swapNativeThroughHook({key: key, amount: 0.001 ether});
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Pool Price Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _poolInitSqrtPriceX96For(uint256 projectId) internal view returns (bool ok, uint160 sqrtPriceX96) {
        JBAccountingContext memory context =
            jbMultiTerminal().accountingContextForTokenOf({projectId: projectId, token: JBConstants.NATIVE_TOKEN});
        if (context.token != JBConstants.NATIVE_TOKEN || context.decimals == 0 || context.currency == 0) {
            return (false, 0);
        }

        (JBRuleset memory ruleset, JBRulesetMetadata memory metadata) = jbController().currentRulesetOf(projectId);
        if (ruleset.id == 0) return (false, 0);

        uint256 terminalTokenUnit = 10 ** context.decimals;
        uint256 adjustedIssuance;
        if (ruleset.weight == 0) {
            adjustedIssuance = 0;
        } else if (context.currency == metadata.baseCurrency) {
            adjustedIssuance = uint256(ruleset.weight);
        } else {
            try jbPrices()
                .pricePerUnitOf({
                projectId: projectId,
                pricingCurrency: context.currency,
                unitCurrency: metadata.baseCurrency,
                decimals: context.decimals
            }) returns (
                uint256 rate
            ) {
                if (rate == 0) return (false, 0);
                adjustedIssuance = mulDiv({x: uint256(ruleset.weight), y: terminalTokenUnit, denominator: rate});
            } catch {
                return (false, 0);
            }
        }

        if (adjustedIssuance == 0) return (true, uint160(1 << 96));

        address projectToken = address(jbTokens().tokenOf(projectId));
        if (projectToken == address(0)) return (true, uint160(1 << 96));

        if (address(0) < projectToken) {
            sqrtPriceX96 = _sqrtPriceX96From({numerator: adjustedIssuance, denominator: terminalTokenUnit});
        } else {
            sqrtPriceX96 = _sqrtPriceX96From({numerator: terminalTokenUnit, denominator: adjustedIssuance});
        }

        return (sqrtPriceX96 != 0, sqrtPriceX96);
    }

    function _sqrtPriceX96From(uint256 numerator, uint256 denominator) internal pure returns (uint160 sqrtPriceX96) {
        uint256 q192 = 1 << 192;
        uint256 maxRatio = type(uint256).max / q192;
        uint256 maxNumerator = denominator > type(uint256).max / maxRatio ? type(uint256).max : maxRatio * denominator;

        if (denominator == 0 || numerator > maxNumerator) return 0;

        sqrtPriceX96 = uint160(sqrt(mulDiv({x: numerator, y: q192, denominator: denominator})));
    }
}
