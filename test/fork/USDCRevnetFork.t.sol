// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

// LP Split Hook
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";

// Revnet
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

// Uniswap V4
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

// Suckers
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";

import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";
import {MockERC20Token} from "../helpers/MockTokens.sol";

/// @notice Full lifecycle fork test with USDC terminal instead of ETH.
///
/// Tests the complete Juicebox V6 ecosystem with USDC-denominated payments, buyback hook,
/// LP split hook, and cashout. All payments use USDC (6 decimals) instead of native ETH.
///
/// Run with: forge test --match-contract USDCRevnetForkTest -vvv
contract USDCRevnetForkTest is RevnetForkBase {
    // ── Mainnet addresses (position manager needed for LP split hook)
    address constant V4_POSITION_MANAGER_ADDR = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;

    // ── LP-split hook
    JBUniswapV4LPSplitHook LP_SPLIT_HOOK;

    // ── USDC mock
    MockERC20Token usdc;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_USDCRevnet";
    }

    function setUp() public override {
        super.setUp();

        IPositionManager positionManager = IPositionManager(V4_POSITION_MANAGER_ADDR);
        require(V4_POSITION_MANAGER_ADDR.code.length > 0, "PositionManager not deployed");

        // Deploy MockUSDC (6 decimals) and mint a large supply for the test contract.
        usdc = new MockERC20Token("Mock USDC", "USDC", 6);
        usdc.mint(address(this), 100_000_000e6); // 100M USDC

        // Deploy LP-split hook (clone pattern).
        JBUniswapV4LPSplitHook lpSplitImpl = new JBUniswapV4LPSplitHook(
            address(jbDirectory()),
            jbPermissions(),
            address(jbTokens()),
            poolManager,
            positionManager,
            permit2(),
            IHooks(address(0))
        );
        LP_SPLIT_HOOK = JBUniswapV4LPSplitHook(payable(LibClone.clone(address(lpSplitImpl))));
        LP_SPLIT_HOOK.initialize(0, 0); // No fee project for simplicity.

        // Mock geomean oracle at address(0) so payments work before buyback pool is set up.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Fund actors with USDC instead of ETH.
        usdc.mint(PAYER, 10_000_000e6); // 10M USDC
        usdc.mint(BORROWER, 5_000_000e6); // 5M USDC
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Config Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Build a single-stage USDC revnet config.
    function _buildUSDCRevnetConfig(
        uint16 cashOutTaxRate,
        uint16 reservedPercent
    )
        internal
        view
        returns (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc)
    {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: address(usdc), decimals: 6, currency: uint32(uint160(address(usdc)))});
        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

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
            splitPercent: reservedPercent,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: cashOutTaxRate,
            extraMetadata: 0
        });

        cfg = REVConfig({
            description: REVDescription("USDC Revnet", "UREV", "ipfs://urev", "UREV_SALT"),
            baseCurrency: uint32(uint160(address(usdc))),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("UREV"))
        });
    }

    /// @notice Build a single-stage USDC revnet config with LP-split hook as reserved split recipient.
    function _buildUSDCRevnetConfigWithLPSplit(
        uint16 cashOutTaxRate,
        uint16 reservedPercent
    )
        internal
        view
        returns (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc)
    {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: address(usdc), decimals: 6, currency: uint32(uint160(address(usdc)))});
        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Splits: 50% to LP-split hook, 50% to multisig.
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
            splitPercent: reservedPercent,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: cashOutTaxRate,
            extraMetadata: 0
        });

        cfg = REVConfig({
            description: REVDescription("USDC Revnet LP", "UREVLP", "ipfs://urevlp", "UREVLP_SALT"),
            baseCurrency: uint32(uint160(address(usdc))),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("UREVLP"))
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Pool / Buyback Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Add liquidity to the USDC buyback pool for the given revnet.
    /// REVDeployer already initializes the pool and registers it in the buyback hook
    /// for ALL terminal tokens (including USDC) during deployFor. This helper only
    /// adds liquidity to the existing pool.
    function _setupUSDCBuybackPool(uint256 revnetId, uint256 liquidityUSDCAmount)
        internal
        returns (PoolKey memory key)
    {
        address projectToken = address(jbTokens().tokenOf(revnetId));
        require(projectToken != address(0), "project token not deployed");

        // Sort currencies — both are ERC-20s, no native ETH.
        address token0 = address(usdc) < projectToken ? address(usdc) : projectToken;
        address token1 = address(usdc) < projectToken ? projectToken : address(usdc);

        key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(),
            tickSpacing: REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(),
            hooks: IHooks(address(0))
        });

        // Pool is already initialized and registered by REVDeployer during deployment.
        // Just add liquidity to it.

        // Fund liquidity helper with USDC and project tokens.
        usdc.mint(address(liqHelper), liquidityUSDCAmount);
        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, liquidityUSDCAmount * 1e12); // scale 6 -> 18 decimals

        vm.startPrank(address(liqHelper));
        IERC20(address(usdc)).approve(address(poolManager), type(uint256).max);
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);
        vm.stopPrank();

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 liquidityDelta = int256(liquidityUSDCAmount / 2);
        vm.prank(address(liqHelper));
        liqHelper.addLiquidity(key, TICK_LOWER, TICK_UPPER, liquidityDelta);

        // Compute the oracle tick that matches the issuance rate: 1000 project tokens (18 dec) per USDC (6 dec).
        // Raw ratio = 1e21 / 1e6 = 1e15. tick = ln(1e15)/ln(1.0001) ≈ 345_400.
        // Sign depends on token sort order: positive if USDC is token0 (project token is more expensive in raw terms).
        int24 issuanceTick = address(usdc) < projectToken ? int24(345_400) : int24(-345_400);
        _mockOracle(liquidityDelta, issuanceTick, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Payment / Utility Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Pay a revnet with USDC. Mints USDC to the payer, approves terminal, and pays.
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

    // ═══════════════════════════════════════════════════════════════════
    //  Tests
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Pre-AMM: Pay from the terminal with USDC before any pool is set up. Mint path must work.
    function test_usdc_preAMM_payFromTerminal() public {
        _deployFeeProject(5000);

        // Deploy revnet with USDC terminal, 20% reserved, 50% cashout tax.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildUSDCRevnetConfig(5000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay with varying USDC amounts — no pool yet, should mint directly.
        uint256[3] memory amounts = [uint256(100e6), 1000e6, 10_000e6];

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 tokens = _payRevnetUSDC(revnetId, PAYER, amounts[i]);
            assertGt(tokens, 0, "should receive tokens pre-AMM");

            emit log_named_uint("USDC paid", amounts[i]);
            emit log_named_uint("tokens received", tokens);
        }

        // Terminal should have USDC balance.
        assertGt(_terminalBalance(revnetId, address(usdc)), 0, "terminal should have USDC balance");
    }

    /// @notice Distribute reserved tokens after USDC payments and verify LP split hook accumulates.
    function test_usdc_lpSplitHookAccumulates() public {
        _deployFeeProject(5000);

        // Deploy revnet with LP-split hook in reserved splits.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildUSDCRevnetConfigWithLPSplit(5000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay with USDC to generate reserved tokens.
        _payRevnetUSDC(revnetId, PAYER, 10_000e6);
        _payRevnetUSDC(revnetId, BORROWER, 5000e6);

        // Check pending reserved tokens.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        assertGt(pending, 0, "should have pending reserved tokens");

        // Distribute reserved tokens.
        jbController().sendReservedTokensToSplitsOf(revnetId);

        // LP-split hook should have accumulated tokens (50% of reserved).
        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);
        assertGt(accumulated, 0, "LP split hook should have accumulated tokens");

        // Multisig should also have received the other 50%.
        uint256 multisigTokens = jbTokens().totalBalanceOf(multisig(), revnetId);
        assertGt(multisigTokens, 0, "multisig should receive reserved tokens");
    }

    /// @notice Post-AMM: Set up buyback pool for USDC/projectToken pair and pay with USDC.
    function test_usdc_postAMM_payFromTerminal() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildUSDCRevnetConfig(5000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Set up USDC buyback pool with real liquidity.
        _setupUSDCBuybackPool(revnetId, 100_000e6);

        // Pay some surplus so bonding curve has visible effect.
        _payRevnetUSDC(revnetId, BORROWER, 5000e6);

        // Pay again — buyback hook is now active for USDC.
        uint256 tokens = _payRevnetUSDC(revnetId, PAYER, 1000e6);

        // Should receive tokens (either via mint or swap, whichever wins).
        assertGt(tokens, 0, "should receive tokens post-AMM");

        // Terminal USDC balance should be non-zero.
        assertGt(_terminalBalance(revnetId, address(usdc)), 0, "terminal USDC balance should be non-zero");
    }

    /// @notice Pay USDC, acquire tokens, cash out tokens for USDC.
    function test_usdc_cashOut() public {
        _deployFeeProject(5000);

        // Deploy with moderate cashout tax.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildUSDCRevnetConfig(5000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay with USDC to acquire tokens.
        _payRevnetUSDC(revnetId, PAYER, 10_000e6);

        // Another payer to create surplus (needed for bonding curve to return value).
        _payRevnetUSDC(revnetId, BORROWER, 5000e6);

        // Get payer's token balance.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        assertGt(payerTokens, 0, "payer should have tokens");

        uint256 cashOutCount = payerTokens / 2;
        uint256 payerUSDCBefore = usdc.balanceOf(PAYER);

        // Cash out tokens for USDC.
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

    /// @notice Full lifecycle test at varying USDC order sizes.
    function test_usdc_varyingOrderSizes() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildUSDCRevnetConfig(5000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        uint256[5] memory amounts = [
            uint256(100e6), // 100 USDC
            1000e6, // 1,000 USDC
            10_000e6, // 10,000 USDC
            100_000e6, // 100,000 USDC
            1_000_000e6 // 1,000,000 USDC
        ];

        uint256 cumulativeTokens;

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 tokens = _payRevnetUSDC(revnetId, PAYER, amounts[i]);
            assertGt(tokens, 0, "should receive tokens for each order size");

            cumulativeTokens += tokens;

            emit log_named_uint("--- Order size (USDC) ---", amounts[i] / 1e6);
            emit log_named_uint("tokens received", tokens);
            emit log_named_uint("cumulative tokens", cumulativeTokens);
        }

        // Verify total tokens are reasonable — all orders should have minted.
        uint256 totalTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        assertEq(totalTokens, cumulativeTokens, "total tokens should equal cumulative");
        assertGt(totalTokens, 0, "should have non-zero total tokens");

        // Terminal should have all the USDC.
        uint256 terminalUSDC = _terminalBalance(revnetId, address(usdc));
        assertGt(terminalUSDC, 0, "terminal should hold USDC");

        emit log_named_uint("total terminal USDC", terminalUSDC);
        emit log_named_uint("total payer tokens", totalTokens);
    }

    /// @notice Complete lifecycle: deploy USDC revnet, pre-AMM pay, distribute reserved, set up
    /// USDC buyback pool, post-AMM pay, cash out USDC.
    function test_usdc_fullLifecycle() public {
        _deployFeeProject(5000);

        // 1. Deploy revnet with USDC terminal and LP-split hook.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildUSDCRevnetConfigWithLPSplit(5000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // 2. Pre-AMM payment (mint path only, no USDC pool).
        uint256 tokensPreAMM = _payRevnetUSDC(revnetId, PAYER, 5000e6);
        assertGt(tokensPreAMM, 0, "pre-AMM payment should mint tokens");

        // Another payer for bonding curve effects.
        _payRevnetUSDC(revnetId, BORROWER, 5000e6);

        // 3. Distribute reserved tokens — LP-split hook accumulates.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        if (pending > 0) {
            jbController().sendReservedTokensToSplitsOf(revnetId);
        }
        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);
        assertGt(accumulated, 0, "LP split hook should accumulate from reserved distribution");

        // 4. Set up USDC buyback pool (separate from LP-split hook's pool).
        _setupUSDCBuybackPool(revnetId, 100_000e6);

        // 5. Post-AMM payment — buyback hook compares swap vs mint.
        uint256 tokensPostAMM = _payRevnetUSDC(revnetId, PAYER, 1000e6);
        assertGt(tokensPostAMM, 0, "post-AMM payment should return tokens");

        // 6. Cash out some tokens for USDC.
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

        // Verify terminal still has USDC balance.
        assertGt(_terminalBalance(revnetId, address(usdc)), 0, "terminal should still hold USDC");

        emit log_named_uint("pre-AMM tokens", tokensPreAMM);
        emit log_named_uint("post-AMM tokens", tokensPostAMM);
        emit log_named_uint("USDC reclaimed", usdc.balanceOf(PAYER) - payerUSDCBefore);
        emit log_named_uint("remaining terminal USDC", _terminalBalance(revnetId, address(usdc)));
    }
}
