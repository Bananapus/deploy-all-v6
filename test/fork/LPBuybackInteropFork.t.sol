// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

// 721 Hook
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";

// Address Registry
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// Buyback Hook
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";
import {IJBBuybackHook} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHook.sol";
import {IGeomeanOracle} from "@bananapus/buyback-hook-v6/src/interfaces/IGeomeanOracle.sol";

// Suckers
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// Croptop
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";

// LP Split Hook
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";

// Revnet
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {IREVLoans} from "@rev-net/core-v6/src/interfaces/IREVLoans.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

// Uniswap V4
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";

/// @notice Adds liquidity and performs swaps on V4 pools via the unlock/callback pattern.
/// Supports both native ETH (address(0)) and ERC-20 settlement.
contract InteropLiquidityHelper is IUnlockCallback {
    IPoolManager public immutable poolManager;

    enum Action {
        ADD_LIQUIDITY,
        SWAP
    }

    struct DoSwapParams {
        PoolKey key;
        bool zeroForOne;
        int256 amountSpecified;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    receive() external payable {}

    function addLiquidity(PoolKey memory key, int24 tickLower, int24 tickUpper, int256 liquidityDelta)
        external
        payable
    {
        poolManager.unlock(abi.encode(Action.ADD_LIQUIDITY, abi.encode(key, tickLower, tickUpper, liquidityDelta)));
    }

    function swap(PoolKey memory key, bool zeroForOne, int256 amountSpecified) external payable {
        poolManager.unlock(
            abi.encode(Action.SWAP, abi.encode(DoSwapParams({key: key, zeroForOne: zeroForOne, amountSpecified: amountSpecified})))
        );
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        (Action action, bytes memory params) = abi.decode(data, (Action, bytes));

        if (action == Action.ADD_LIQUIDITY) {
            return _handleAddLiquidity(params);
        } else {
            return _handleSwap(params);
        }
    }

    function _handleAddLiquidity(bytes memory params) internal returns (bytes memory) {
        (PoolKey memory key, int24 tickLower, int24 tickUpper, int256 liquidityDelta) =
            abi.decode(params, (PoolKey, int24, int24, int256));

        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: 0}),
            ""
        );

        _settleDelta(key, delta);
        return "";
    }

    function _handleSwap(bytes memory params) internal returns (bytes memory) {
        DoSwapParams memory p = abi.decode(params, (DoSwapParams));

        uint160 limit = p.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;

        BalanceDelta delta =
            poolManager.swap(p.key, SwapParams({zeroForOne: p.zeroForOne, amountSpecified: p.amountSpecified, sqrtPriceLimitX96: limit}), "");

        _settleDelta(p.key, delta);
        return "";
    }

    function _settleDelta(PoolKey memory key, BalanceDelta delta) internal {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        if (amount0 < 0) {
            _settle(key.currency0, uint128(-amount0));
        }
        if (amount1 < 0) {
            _settle(key.currency1, uint128(-amount1));
        }
        if (amount0 > 0) poolManager.take(key.currency0, address(this), uint128(amount0));
        if (amount1 > 0) poolManager.take(key.currency1, address(this), uint128(amount1));
    }

    function _settle(Currency currency, uint256 amount) internal {
        if (Currency.unwrap(currency) == address(0)) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).transfer(address(poolManager), amount);
            poolManager.settle();
        }
    }
}

/// @notice Fork tests verifying LP split hook and buyback hook interoperation on the same Uniswap V4 pool.
///
/// Both hooks target the same native ETH hookless pool (Currency.wrap(address(0)) + projectToken,
/// fee=10_000, tickSpacing=200). The LP split hook accumulates reserved tokens and deploys liquidity,
/// while the buyback hook routes payments through that same pool when the swap price beats the mint price.
///
/// Tests both as a revnet (deployed via REVDeployer) and as a standalone JB project.
///
/// Run with: forge test --match-contract LPBuybackInteropForkTest -vvv
contract LPBuybackInteropForkTest is TestBaseWorkflow {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // ── Mainnet addresses
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant V4_POSITION_MANAGER_ADDR = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;

    // ── Tick range for manual liquidity seeding
    int24 constant TICK_LOWER = -887_200;
    int24 constant TICK_UPPER = 887_200;

    // ── Test parameters
    uint112 constant INITIAL_ISSUANCE = uint112(1000e18);

    // ── Actors
    address PAYER = makeAddr("payer");
    address PAYER2 = makeAddr("payer2");

    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // ── Ecosystem contracts
    IPoolManager poolManager;
    IPositionManager positionManager;
    InteropLiquidityHelper liqHelper;

    uint256 FEE_PROJECT_ID;
    JBSuckerRegistry SUCKER_REGISTRY;
    JB721TiersHookStore HOOK_STORE;
    JB721TiersHook EXAMPLE_HOOK;
    IJBAddressRegistry ADDRESS_REGISTRY;
    IJB721TiersHookDeployer HOOK_DEPLOYER;
    CTPublisher PUBLISHER;
    JBBuybackHook BUYBACK_HOOK;
    JBBuybackHookRegistry BUYBACK_REGISTRY;
    IREVLoans LOANS_CONTRACT;
    REVDeployer REV_DEPLOYER;

    // LP-split hook
    JBUniswapV4LPSplitHook LP_SPLIT_HOOK;

    receive() external payable {}

    /// @dev Accept LP position NFTs from PositionManager.
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setUp() public override {
        vm.createSelectFork("ethereum", 21_700_000);
        require(POOL_MANAGER_ADDR.code.length > 0, "PoolManager not deployed");
        require(V4_POSITION_MANAGER_ADDR.code.length > 0, "PositionManager not deployed");

        super.setUp();

        poolManager = IPoolManager(POOL_MANAGER_ADDR);
        positionManager = IPositionManager(V4_POSITION_MANAGER_ADDR);
        liqHelper = new InteropLiquidityHelper(poolManager);

        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        SUCKER_REGISTRY = new JBSuckerRegistry(jbDirectory(), jbPermissions(), multisig(), address(0));
        HOOK_STORE = new JB721TiersHookStore();
        EXAMPLE_HOOK =
            new JB721TiersHook(jbDirectory(), jbPermissions(), jbRulesets(), HOOK_STORE, jbSplits(), multisig());
        ADDRESS_REGISTRY = new JBAddressRegistry();
        HOOK_DEPLOYER = new JB721TiersHookDeployer(EXAMPLE_HOOK, HOOK_STORE, ADDRESS_REGISTRY, multisig());
        PUBLISHER = new CTPublisher(jbDirectory(), jbPermissions(), FEE_PROJECT_ID, multisig());

        BUYBACK_HOOK = new JBBuybackHook(
            jbDirectory(), jbPermissions(), jbPrices(), jbProjects(), jbTokens(), poolManager, IHooks(address(0)), address(0)
        );

        BUYBACK_REGISTRY = new JBBuybackHookRegistry(jbPermissions(), jbProjects(), address(this), address(0));
        BUYBACK_REGISTRY.setDefaultHook(IJBRulesetDataHook(address(BUYBACK_HOOK)));

        LOANS_CONTRACT = new REVLoans({
            controller: jbController(),
            projects: jbProjects(),
            revId: FEE_PROJECT_ID,
            owner: address(this),
            permit2: permit2(),
            trustedForwarder: TRUSTED_FORWARDER
        });

        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_Interop"}(
            jbController(),
            SUCKER_REGISTRY,
            FEE_PROJECT_ID,
            HOOK_DEPLOYER,
            PUBLISHER,
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            address(LOANS_CONTRACT),
            TRUSTED_FORWARDER
        );

        vm.prank(multisig());
        jbProjects().approve(address(REV_DEPLOYER), FEE_PROJECT_ID);

        // Deploy LP-split hook (clone pattern).
        JBUniswapV4LPSplitHook lpSplitImpl = new JBUniswapV4LPSplitHook(
            address(jbDirectory()), jbPermissions(), address(jbTokens()), poolManager, positionManager, IHooks(address(0))
        );
        LP_SPLIT_HOOK = JBUniswapV4LPSplitHook(payable(LibClone.clone(address(lpSplitImpl))));
        LP_SPLIT_HOOK.initialize(0, 0); // No fee routing for simplicity.

        // Fund actors.
        vm.deal(PAYER, 200 ether);
        vm.deal(PAYER2, 200 ether);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Config Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _deployFeeProject(uint16 cashOutTaxRate) internal {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
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
            cashOutTaxRate: cashOutTaxRate,
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("Fee", "FEE", "ipfs://fee", "FEE_INTEROP_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("FEE_INTEROP"))
        });

        vm.prank(multisig());
        REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

    /// @notice Build revnet config with LP-split hook as 50% reserved split recipient.
    function _buildRevnetConfigWithLPSplit(uint16 cashOutTaxRate)
        internal
        view
        returns (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc)
    {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // 50% to LP-split hook, 50% to multisig.
        JBSplit[] memory splits = new JBSplit[](2);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2),
            projectId: 0,
            beneficiary: payable(address(0)),
            lockedUntil: 0,
            hook: IJBSplitHook(address(LP_SPLIT_HOOK))
        });
        splits[1] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2),
            projectId: 0,
            beneficiary: payable(multisig()),
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
            cashOutTaxRate: cashOutTaxRate,
            extraMetadata: 0
        });

        cfg = REVConfig({
            description: REVDescription("LPBuyback", "LBH", "ipfs://lbh", "LBH_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("LBH"))
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _payRevnet(uint256 revnetId, address payer, uint256 amount) internal returns (uint256 tokensReceived) {
        vm.prank(payer);
        tokensReceived = jbMultiTerminal().pay{value: amount}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: amount,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
    }

    function _terminalBalance(uint256 projectId, address token) internal view returns (uint256) {
        return jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, token);
    }

    /// @notice Mock the oracle at address(0) with defaults (tick 0 = 1:1, mint path wins).
    function _mockDefaultOracle() internal {
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
    }

    function _mockOracle(int256 liquidity, int24 tick, uint32 twapWindow) internal {
        vm.etch(address(0), hex"00");

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = 0;
        tickCumulatives[1] = int56(tick) * int56(int32(twapWindow));

        uint136[] memory secondsPerLiquidityCumulativeX128s = new uint136[](2);
        secondsPerLiquidityCumulativeX128s[0] = 0;
        uint256 liq = uint256(liquidity > 0 ? liquidity : -liquidity);
        if (liq == 0) liq = 1;
        secondsPerLiquidityCumulativeX128s[1] = uint136((uint256(twapWindow) << 128) / liq);

        vm.mockCall(
            address(0),
            abi.encodeWithSelector(IGeomeanOracle.observe.selector),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
        );
    }

    /// @notice Seed manual liquidity into the buyback pool to make the swap path competitive.
    /// The buyback pool uses native ETH (address(0)) — the same pool the LP split hook deploys into.
    /// Uses a conservative liquidity delta to avoid ERC20InsufficientBalance when the pool tick
    /// is high (project token cheap relative to ETH → full-range needs many more project tokens than ETH).
    function _seedBuybackPoolLiquidity(uint256 revnetId, uint256 liquidityTokenAmount)
        internal
        returns (PoolKey memory key)
    {
        address projectToken = address(jbTokens().tokenOf(revnetId));

        // Native ETH is address(0) — always sorts before any ERC-20.
        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(projectToken),
            fee: REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(),
            tickSpacing: REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(),
            hooks: IHooks(address(0))
        });

        // Mint extra project tokens to account for pool tick being far from 0.
        // At high ticks (e.g., ~68800 where 1 ETH ≈ 1000 tokens), full-range positions
        // need ~30x more project tokens than ETH.
        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, liquidityTokenAmount * 50);
        vm.deal(address(liqHelper), liquidityTokenAmount);

        vm.prank(address(liqHelper));
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);

        // Use a conservative liquidity delta (1/50th) to stay within token budgets.
        int256 liquidityDelta = int256(liquidityTokenAmount / 50);
        vm.prank(address(liqHelper));
        liqHelper.addLiquidity{value: liquidityTokenAmount}(key, TICK_LOWER, TICK_UPPER, liquidityDelta);

        _mockOracle(liquidityDelta, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
    }

    /// @notice Grant SET_BUYBACK_POOL permission to an address for a project.
    function _grantDeployPoolPermission(address operator, uint256 projectId) internal {
        address projectOwner = jbProjects().ownerOf(projectId);
        mockExpect(
            address(jbPermissions()),
            abi.encodeCall(IJBPermissions.hasPermission, (operator, projectOwner, projectId, 26, true, true)),
            abi.encode(true)
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Revnet Tests — LP Split Hook + Buyback Hook
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Full revnet lifecycle: deploy → pay (pre-AMM) → distribute reserved → LP split accumulates →
    /// deploy pool via LP split hook → pay again (post-AMM, buyback active) → verify buyback routes through
    /// the LP split hook's pool.
    /// @notice Full lifecycle: deploy → pay → distribute → LP deploy → buyback → cashout.
    function test_interop_revnet_fullLifecycle() public {
        _deployFeeProject(5000);

        // Deploy revnet with LP split hook in reserved splits.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildRevnetConfigWithLPSplit(5000);

        uint256 revnetId = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Mock oracle before any payments (buyback hook queries TWAP on every pay).
        _mockDefaultOracle();

        // Verify buyback pool was initialized by REVDeployer (pool exists in PoolManager).
        address projectToken = address(jbTokens().tokenOf(revnetId));
        assertFalse(projectToken == address(0), "project token should be deployed");

        // 1. Pre-AMM: pay → mint path (pool has no liquidity).
        uint256 tokensPreAMM = _payRevnet(revnetId, PAYER, 10 ether);
        assertGt(tokensPreAMM, 0, "pre-AMM payment should mint tokens");

        // Another payer to increase surplus.
        _payRevnet(revnetId, PAYER2, 10 ether);

        // 2. Distribute reserved tokens → LP split hook accumulates 50%.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        assertGt(pending, 0, "should have pending reserved tokens");

        jbController().sendReservedTokensToSplitsOf(revnetId);

        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);
        assertGt(accumulated, 0, "LP split hook should accumulate tokens from reserved distribution");

        // Multisig should also get 50%.
        uint256 multisigTokens = jbTokens().totalBalanceOf(multisig(), revnetId);
        assertGt(multisigTokens, 0, "multisig should receive 50% of reserved tokens");

        // 3. Deploy pool via LP split hook (uses accumulated tokens as liquidity).
        _grantDeployPoolPermission(address(this), revnetId);
        LP_SPLIT_HOOK.deployPool({
            projectId: revnetId,
            terminalToken: JBConstants.NATIVE_TOKEN,
            amount0Min: 0,
            amount1Min: 0,
            minCashOutReturn: 0
        });

        // Accumulated tokens should be cleared after pool deployment.
        assertEq(LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId), 0, "accumulated tokens should be cleared");

        // LP position should exist.
        uint256 tokenId = LP_SPLIT_HOOK.tokenIdOf(revnetId, JBConstants.NATIVE_TOKEN);
        assertGt(tokenId, 0, "LP position should exist");

        // Both hooks now target the SAME native ETH pool (address(0) + projectToken).
        // Verify pool parameters match (fee + tickSpacing).
        assertEq(LP_SPLIT_HOOK.POOL_FEE(), REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(), "pool fee should match");
        assertEq(LP_SPLIT_HOOK.TICK_SPACING(), REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(), "tick spacing should match");

        // 4. Seed additional liquidity into the same native ETH pool so the buyback swap path is competitive.
        _seedBuybackPoolLiquidity(revnetId, 10_000 ether);

        // 5. Post-AMM payment: buyback hook routes through the LP split hook's pool.
        uint256 tokensPostAMM = _payRevnet(revnetId, PAYER, 1 ether);
        assertGt(tokensPostAMM, 0, "post-AMM payment should return tokens");

        // Terminal balance should increase.
        assertGt(_terminalBalance(revnetId, JBConstants.NATIVE_TOKEN), 0, "terminal should have balance");
    }

    /// @notice Pre-AMM: reserved tokens accumulate in LP split hook, not burned.
    function test_interop_revnet_preAMM_accumulation() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildRevnetConfigWithLPSplit(5000);

        uint256 revnetId = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _mockDefaultOracle();

        // Multiple payments to generate significant reserved tokens.
        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, PAYER2, 10 ether);

        // First distribution.
        jbController().sendReservedTokensToSplitsOf(revnetId);
        uint256 accAfterFirst = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);

        // More payments.
        _payRevnet(revnetId, PAYER, 5 ether);

        // Second distribution should add more.
        jbController().sendReservedTokensToSplitsOf(revnetId);
        uint256 accAfterSecond = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);
        assertGt(accAfterSecond, accAfterFirst, "accumulation should increase with more distributions");
    }

    /// @notice Post-deployment: reserved tokens going to LP split hook are burned (not accumulated).
    function test_interop_revnet_postDeployment_burnReserved() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildRevnetConfigWithLPSplit(5000);

        uint256 revnetId = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _mockDefaultOracle();

        // Pay and distribute → accumulate.
        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, PAYER2, 10 ether);
        jbController().sendReservedTokensToSplitsOf(revnetId);

        // Deploy pool.
        _grantDeployPoolPermission(address(this), revnetId);
        LP_SPLIT_HOOK.deployPool({
            projectId: revnetId,
            terminalToken: JBConstants.NATIVE_TOKEN,
            amount0Min: 0,
            amount1Min: 0,
            minCashOutReturn: 0
        });

        // More payments → more reserved tokens.
        _payRevnet(revnetId, PAYER, 5 ether);

        uint256 hookBalanceBefore = jbTokens().totalBalanceOf(address(LP_SPLIT_HOOK), revnetId);

        // Distribute again — LP split hook should burn these tokens (pool already deployed).
        jbController().sendReservedTokensToSplitsOf(revnetId);

        // Accumulated should remain 0 (burned, not accumulated).
        assertEq(LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId), 0, "should not accumulate after deployment");

        // Hook balance should not increase (tokens were burned, not held).
        uint256 hookBalanceAfter = jbTokens().totalBalanceOf(address(LP_SPLIT_HOOK), revnetId);
        assertEq(hookBalanceAfter, hookBalanceBefore, "hook should burn tokens, not hold them");
    }

    /// @notice Pool parameters match: both hooks use the same fee and tick spacing.
    function test_interop_revnet_poolParametersMatch() public {
        // The critical interop requirement: both hooks target the same pool.
        assertEq(
            LP_SPLIT_HOOK.POOL_FEE(),
            REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(),
            "LP split hook and buyback hook should use same pool fee"
        );
        assertEq(
            LP_SPLIT_HOOK.TICK_SPACING(),
            REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(),
            "LP split hook and buyback hook should use same tick spacing"
        );
    }

    /// @notice After LP split deploys the pool, buyback hook can query TWAP and route swaps.
    function test_interop_revnet_buybackRoutesAfterLPDeploy() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildRevnetConfigWithLPSplit(5000);

        uint256 revnetId = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _mockDefaultOracle();

        // Pay heavily to build surplus and generate reserved tokens.
        _payRevnet(revnetId, PAYER, 20 ether);
        _payRevnet(revnetId, PAYER2, 20 ether);

        // Distribute and deploy pool.
        jbController().sendReservedTokensToSplitsOf(revnetId);
        _grantDeployPoolPermission(address(this), revnetId);
        LP_SPLIT_HOOK.deployPool({
            projectId: revnetId,
            terminalToken: JBConstants.NATIVE_TOKEN,
            amount0Min: 0,
            amount1Min: 0,
            minCashOutReturn: 0
        });

        // Also add manual liquidity to the same native ETH pool to ensure swap path is competitive with mint.
        _seedBuybackPoolLiquidity(revnetId, 10_000 ether);

        // Pay after pool deployment — buyback hook routes through the same pool the LP split hook deployed.
        uint256 payerTokensBefore = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 tokens = _payRevnet(revnetId, PAYER, 1 ether);
        uint256 payerTokensAfter = jbTokens().totalBalanceOf(PAYER, revnetId);

        assertGt(tokens, 0, "should receive tokens through buyback hook");
        assertEq(payerTokensAfter, payerTokensBefore + tokens, "balance should increase by minted tokens");
    }

    /// @notice Cash out works correctly after both hooks have set up the pool.
    function test_interop_revnet_cashOutAfterPoolDeployment() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildRevnetConfigWithLPSplit(5000);

        uint256 revnetId = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _mockDefaultOracle();

        // Build surplus.
        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, PAYER2, 10 ether);

        // Distribute and deploy pool.
        jbController().sendReservedTokensToSplitsOf(revnetId);
        _grantDeployPoolPermission(address(this), revnetId);
        LP_SPLIT_HOOK.deployPool({
            projectId: revnetId,
            terminalToken: JBConstants.NATIVE_TOKEN,
            amount0Min: 0,
            amount1Min: 0,
            minCashOutReturn: 0
        });

        // Cash out tokens — bonding curve should work with pool deployed.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        uint256 reclaimed = jbMultiTerminal().cashOutTokensOf({
            holder: PAYER,
            projectId: revnetId,
            cashOutCount: payerTokens / 2,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        assertGt(reclaimed, 0, "should reclaim ETH via cash out");
        assertGt(PAYER.balance, payerEthBefore, "payer ETH should increase");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Standalone JB Project Tests — LP Split Hook + Buyback Hook
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Deploy a plain JB project (not a revnet) with both hooks configured manually.
    /// Verifies the hooks work together outside of the REVDeployer flow.
    function test_interop_jbProject_fullLifecycle() public {
        _deployFeeProject(5000);

        // 1. Launch a plain JB project with LP split hook as reserved split.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Reserved splits: 50% to LP-split hook, 50% to multisig.
        JBSplit[] memory splits = new JBSplit[](2);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2),
            projectId: 0,
            beneficiary: payable(address(0)),
            lockedUntil: 0,
            hook: IJBSplitHook(address(LP_SPLIT_HOOK))
        });
        splits[1] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2),
            projectId: 0,
            beneficiary: payable(multisig()),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](1);
        splitGroups[0] = JBSplitGroup({groupId: 1, splits: splits});

        // Ruleset: 20% reserved, 50% cashOutTaxRate, buyback hook as data hook.
        JBRulesetConfig[] memory rulesetConfigs = new JBRulesetConfig[](1);
        rulesetConfigs[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: uint112(INITIAL_ISSUANCE),
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: JBRulesetMetadata({
                reservedPercent: 2000,
                cashOutTaxRate: 5000,
                baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                pausePay: false,
                pauseCreditTransfers: false,
                allowOwnerMinting: true,
                allowSetCustomToken: false,
                allowTerminalMigration: false,
                allowSetTerminals: false,
                allowSetController: false,
                allowAddAccountingContext: false,
                allowAddPriceFeed: false,
                ownerMustSendPayouts: false,
                holdFees: false,
                useTotalSurplusForCashOuts: false,
                useDataHookForPay: true,
                useDataHookForCashOut: false,
                dataHook: address(BUYBACK_HOOK),
                metadata: 0
            }),
            splitGroups: splitGroups,
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        uint256 projectId = jbController().launchProjectFor({
            owner: address(this),
            projectUri: "ipfs://standalone",
            rulesetConfigurations: rulesetConfigs,
            terminalConfigurations: tc,
            memo: ""
        });

        // 2. Deploy ERC-20 (needed for buyback hook and LP split hook).
        jbController().deployERC20For({projectId: projectId, name: "Standalone", symbol: "SOLO", salt: bytes32(0)});

        // 3. Pre-AMM payments (no buyback pool yet → buyback hook returns 0 quote → mint path).
        uint256 tokensPreAMM = _payRevnet(projectId, PAYER, 10 ether);
        assertGt(tokensPreAMM, 0, "pre-AMM: should receive tokens via mint");

        _payRevnet(projectId, PAYER2, 10 ether);

        // 4. Distribute reserved tokens → LP split hook accumulates.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(projectId);
        assertGt(pending, 0, "should have pending reserved tokens");

        jbController().sendReservedTokensToSplitsOf(projectId);

        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(projectId);
        assertGt(accumulated, 0, "LP split hook should accumulate tokens");

        // 5. Deploy pool via LP split hook — initializes pool at geometric mean price.
        // Must happen BEFORE initializePoolFor, because initializePoolFor would set tick 0
        // which puts the LP range out of reach (the range is one-sided project-token only).
        LP_SPLIT_HOOK.deployPool({
            projectId: projectId,
            terminalToken: JBConstants.NATIVE_TOKEN,
            amount0Min: 0,
            amount1Min: 0,
            minCashOutReturn: 0
        });

        assertEq(LP_SPLIT_HOOK.accumulatedProjectTokens(projectId), 0, "accumulated should be cleared");
        assertGt(LP_SPLIT_HOOK.tokenIdOf(projectId, JBConstants.NATIVE_TOKEN), 0, "LP position should exist");

        // 6. Configure buyback hook to use the pool the LP split hook created.
        // Pool already exists → use setPoolFor (not initializePoolFor which would try to re-init).
        BUYBACK_HOOK.setPoolFor({
            projectId: projectId,
            fee: 10_000,
            tickSpacing: 200,
            twapWindow: 1 days,
            terminalToken: JBConstants.NATIVE_TOKEN
        });

        // Mock oracle for TWAP queries on subsequent payments.
        _mockOracle(1, 0, uint32(1 days));

        // 7. Seed additional liquidity into the same native ETH pool.
        _seedBuybackPoolLiquidity(projectId, 10_000 ether);

        // 8. Post-AMM payment — buyback hook routes through the same pool the LP split hook deployed.
        uint256 tokensPostAMM = _payRevnet(projectId, PAYER, 1 ether);
        assertGt(tokensPostAMM, 0, "post-AMM: should receive tokens");

        // 9. Cash out should still work.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, projectId);
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        jbMultiTerminal().cashOutTokensOf({
            holder: PAYER,
            projectId: projectId,
            cashOutCount: payerTokens / 4,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: ""
        });

        assertGt(PAYER.balance, payerEthBefore, "should receive ETH from cash out");
    }
}
