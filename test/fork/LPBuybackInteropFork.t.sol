// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";
import {RevnetEcosystemBase} from "../helpers/RevnetEcosystemBase.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

// Revnet
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// Uniswap V4
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Fork tests verifying LP split hook and buyback hook interoperation on the same Uniswap V4 pool.
///
/// Both hooks target the same native ETH hookless pool (Currency.wrap(address(0)) + projectToken,
/// fee=10_000, tickSpacing=200). The LP split hook accumulates reserved tokens and deploys liquidity,
/// while the buyback hook routes payments through that same pool when the swap price beats the mint price.
///
/// Tests both as a revnet (deployed via REVDeployer) and as a standalone JB project.
///
/// Run with: forge test --match-contract LPBuybackInteropForkTest -vvv
contract LPBuybackInteropForkTest is RevnetEcosystemBase {
    // ── Extra actor not in base
    address PAYER2 = makeAddr("payer2");

    /// @dev Accept LP position NFTs from PositionManager.
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_LPBuybackInterop";
    }

    function setUp() public override {
        super.setUp();

        // Fund extra actor.
        vm.deal(PAYER2, 200 ether);
        // Bump PAYER to 200 ether (base gives 200 already via RevnetEcosystemBase).
        vm.deal(PAYER, 200 ether);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Config Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Mock the oracle at address(0) with defaults (tick 0 = 1:1, mint path wins).
    function _mockDefaultOracle() internal {
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
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
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("LBH"))
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Seed manual liquidity into the buyback pool to make the swap path competitive.
    /// The buyback pool uses native ETH (address(0)) -- the same pool the LP split hook deploys into.
    /// Uses a conservative liquidity delta to avoid ERC20InsufficientBalance when the pool tick
    /// is high (project token cheap relative to ETH -> full-range needs many more project tokens than ETH).
    function _seedBuybackPoolLiquidity(
        uint256 revnetId,
        uint256 liquidityTokenAmount
    )
        internal
        returns (PoolKey memory key)
    {
        address projectToken = address(jbTokens().tokenOf(revnetId));

        // Native ETH is address(0) -- always sorts before any ERC-20.
        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(projectToken),
            fee: REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(),
            tickSpacing: REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(),
            hooks: IHooks(address(0))
        });

        // Mint extra project tokens to account for pool tick being far from 0.
        // At high ticks (e.g., ~68800 where 1 ETH ~ 1000 tokens), full-range positions
        // need ~30x more project tokens than ETH.
        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, liquidityTokenAmount * 50);
        vm.deal(address(liqHelper), liquidityTokenAmount);

        vm.prank(address(liqHelper));
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);

        // Use a conservative liquidity delta (1/50th) to stay within token budgets.
        // forge-lint: disable-next-line(unsafe-typecast)
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
            abi.encodeCall(IJBPermissions.hasPermission, (operator, projectOwner, projectId, 29, true, true)),
            abi.encode(true)
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Revnet Tests -- LP Split Hook + Buyback Hook
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Full revnet lifecycle: deploy -> pay (pre-AMM) -> distribute reserved -> LP split accumulates ->
    /// deploy pool via LP split hook -> pay again (post-AMM, buyback active) -> verify buyback routes through
    /// the LP split hook's pool.
    /// @notice Full lifecycle: deploy -> pay -> distribute -> LP deploy -> buyback -> cashout.
    function test_interop_revnet_fullLifecycle() public {
        _deployFeeProject(5000);

        // Deploy revnet with LP split hook in reserved splits.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildRevnetConfigWithLPSplit(5000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Mock oracle before any payments (buyback hook queries TWAP on every pay).
        _mockDefaultOracle();

        // Verify buyback pool was initialized by REVDeployer (pool exists in PoolManager).
        address projectToken = address(jbTokens().tokenOf(revnetId));
        assertFalse(projectToken == address(0), "project token should be deployed");

        // 1. Pre-AMM: pay -> mint path (pool has no liquidity).
        uint256 tokensPreAMM = _payRevnet(revnetId, PAYER, 10 ether);
        assertGt(tokensPreAMM, 0, "pre-AMM payment should mint tokens");

        // Another payer to increase surplus.
        _payRevnet(revnetId, PAYER2, 10 ether);

        // 2. Distribute reserved tokens -> LP split hook accumulates 50%.
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
        LP_SPLIT_HOOK.deployPool({projectId: revnetId, minCashOutReturn: 0});

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

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
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

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _mockDefaultOracle();

        // Pay and distribute -> accumulate.
        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, PAYER2, 10 ether);
        jbController().sendReservedTokensToSplitsOf(revnetId);

        // Deploy pool.
        _grantDeployPoolPermission(address(this), revnetId);
        LP_SPLIT_HOOK.deployPool({projectId: revnetId, minCashOutReturn: 0});

        // More payments -> more reserved tokens.
        _payRevnet(revnetId, PAYER, 5 ether);

        uint256 hookBalanceBefore = jbTokens().totalBalanceOf(address(LP_SPLIT_HOOK), revnetId);

        // Distribute again -- LP split hook should burn these tokens (pool already deployed).
        jbController().sendReservedTokensToSplitsOf(revnetId);

        // Accumulated should remain 0 (burned, not accumulated).
        assertEq(LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId), 0, "should not accumulate after deployment");

        // Hook balance should not increase (tokens were burned, not held).
        uint256 hookBalanceAfter = jbTokens().totalBalanceOf(address(LP_SPLIT_HOOK), revnetId);
        assertEq(hookBalanceAfter, hookBalanceBefore, "hook should burn tokens, not hold them");
    }

    /// @notice Pool parameters match: both hooks use the same fee and tick spacing.
    function test_interop_revnet_poolParametersMatch() public view {
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

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _mockDefaultOracle();

        // Pay heavily to build surplus and generate reserved tokens.
        _payRevnet(revnetId, PAYER, 20 ether);
        _payRevnet(revnetId, PAYER2, 20 ether);

        // Distribute and deploy pool.
        jbController().sendReservedTokensToSplitsOf(revnetId);
        _grantDeployPoolPermission(address(this), revnetId);
        LP_SPLIT_HOOK.deployPool({projectId: revnetId, minCashOutReturn: 0});

        // Also add manual liquidity to the same native ETH pool to ensure swap path is competitive with mint.
        _seedBuybackPoolLiquidity(revnetId, 10_000 ether);

        // Pay after pool deployment -- buyback hook routes through the same pool the LP split hook deployed.
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

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _mockDefaultOracle();

        // Build surplus.
        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, PAYER2, 10 ether);

        // Distribute and deploy pool.
        jbController().sendReservedTokensToSplitsOf(revnetId);
        _grantDeployPoolPermission(address(this), revnetId);
        LP_SPLIT_HOOK.deployPool({projectId: revnetId, minCashOutReturn: 0});

        // Cash out tokens -- bonding curve should work with pool deployed.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        uint256 reclaimed = jbMultiTerminal()
            .cashOutTokensOf({
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
    //  Standalone JB Project Tests -- LP Split Hook + Buyback Hook
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
                scopeCashOutsToLocalBalances: true,
                useDataHookForPay: true,
                useDataHookForCashOut: false,
                dataHook: address(BUYBACK_HOOK),
                metadata: 0
            }),
            splitGroups: splitGroups,
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        uint256 projectId = jbController()
            .launchProjectFor({
            owner: address(this),
            projectUri: "ipfs://standalone",
            rulesetConfigurations: rulesetConfigs,
            terminalConfigurations: tc,
            memo: ""
        });

        // 2. Deploy ERC-20 (needed for buyback hook and LP split hook).
        jbController().deployERC20For({projectId: projectId, name: "Standalone", symbol: "SOLO", salt: bytes32(0)});

        // 3. Pre-AMM payments (no buyback pool yet -> buyback hook returns 0 quote -> mint path).
        uint256 tokensPreAMM = _payRevnet(projectId, PAYER, 10 ether);
        assertGt(tokensPreAMM, 0, "pre-AMM: should receive tokens via mint");

        _payRevnet(projectId, PAYER2, 10 ether);

        // 4. Distribute reserved tokens -> LP split hook accumulates.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(projectId);
        assertGt(pending, 0, "should have pending reserved tokens");

        jbController().sendReservedTokensToSplitsOf(projectId);

        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(projectId);
        assertGt(accumulated, 0, "LP split hook should accumulate tokens");

        // 5. Deploy pool via LP split hook -- initializes pool at geometric mean price.
        // Must happen BEFORE initializePoolFor, because initializePoolFor would set tick 0
        // which puts the LP range out of reach (the range is one-sided project-token only).
        // No permission grant needed -- address(this) IS the project owner.
        LP_SPLIT_HOOK.deployPool({projectId: projectId, minCashOutReturn: 0});

        assertEq(LP_SPLIT_HOOK.accumulatedProjectTokens(projectId), 0, "accumulated should be cleared");
        assertGt(LP_SPLIT_HOOK.tokenIdOf(projectId, JBConstants.NATIVE_TOKEN), 0, "LP position should exist");

        // 6. Configure buyback hook to use the pool the LP split hook created.
        // Pool already exists -> use setPoolFor (not initializePoolFor which would try to re-init).
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

        // 8. Post-AMM payment -- buyback hook routes through the same pool the LP split hook deployed.
        uint256 tokensPostAMM = _payRevnet(projectId, PAYER, 1 ether);
        assertGt(tokensPostAMM, 0, "post-AMM: should receive tokens");

        // 9. Cash out should still work.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, projectId);
        uint256 payerEthBefore = PAYER.balance;

        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
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
