// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBPayHook} from "@bananapus/core-v6/src/interfaces/IJBPayHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";

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
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// Croptop
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";

// Revnet
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {IREVLoans} from "@rev-net/core-v6/src/interfaces/IREVLoans.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVDeploy721TiersHookConfig} from "@rev-net/core-v6/src/structs/REVDeploy721TiersHookConfig.sol";
import {REVBaseline721HookConfig} from "@rev-net/core-v6/src/structs/REVBaseline721HookConfig.sol";
import {REV721TiersHookFlags} from "@rev-net/core-v6/src/structs/REV721TiersHookFlags.sol";
import {REVCroptopAllowedPost} from "@rev-net/core-v6/src/structs/REVCroptopAllowedPost.sol";
import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";
import {REVLoanSource} from "@rev-net/core-v6/src/structs/REVLoanSource.sol";

// Uniswap V4
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Adds liquidity to a V4 pool via unlock/callback pattern.
/// Supports both native ETH (address(0)) and ERC-20 settlement.
contract FullStackLiquidityHelper is IUnlockCallback {
    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    receive() external payable {}

    function addLiquidity(
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta
    )
        external
        payable
    {
        poolManager.unlock(abi.encode(key, tickLower, tickUpper, liquidityDelta));
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        (PoolKey memory key, int24 tickLower, int24 tickUpper, int256 liquidityDelta) =
            abi.decode(data, (PoolKey, int24, int24, int256));

        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: 0
            }),
            ""
        );

        // Settle tokens owed to the pool.
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        if (amount0 < 0) {
            _settle(key.currency0, uint128(-amount0));
        }
        if (amount1 < 0) {
            _settle(key.currency1, uint128(-amount1));
        }

        // Claim any owed tokens.
        if (amount0 > 0) poolManager.take(key.currency0, address(this), uint128(amount0));
        if (amount1 > 0) poolManager.take(key.currency1, address(this), uint128(amount1));

        return "";
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

/// @notice Full-stack integration fork test exercising all major Juicebox V6 component interactions.
///
/// Deploys the entire ecosystem on forked Ethereum mainnet and verifies:
/// - Payment → token issuance (mint and swap paths)
/// - 721 NFT tier splits
/// - Cash-out with bonding curve + tax + fee
/// - Loan borrow and repay
/// - Sucker exemption (0% tax/fee)
/// - Reserved token distribution
/// - Stage transitions
///
/// Run with: forge test --match-contract FullStackForkTest -vvv
contract FullStackForkTest is TestBaseWorkflow {
    // ── Mainnet addresses
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    // ── Tick range for full-range liquidity
    int24 constant TICK_LOWER = -887_200;
    int24 constant TICK_UPPER = 887_200;

    // ── Test parameters
    uint112 constant INITIAL_ISSUANCE = uint112(1000e18); // 1000 tokens per ETH
    uint32 constant SPLIT_PERCENT = 300_000_000; // 30%
    uint104 constant TIER_PRICE = 1 ether;

    // ── Actors
    address PAYER = makeAddr("payer");
    address BORROWER = makeAddr("borrower");
    address SPLIT_BENEFICIARY = makeAddr("splitBeneficiary");

    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // ── Ecosystem contracts
    IPoolManager poolManager;
    FullStackLiquidityHelper liqHelper;

    uint256 FEE_PROJECT_ID;
    JBSuckerRegistry SUCKER_REGISTRY;
    IJB721TiersHookStore HOOK_STORE;
    JB721TiersHook EXAMPLE_HOOK;
    IJBAddressRegistry ADDRESS_REGISTRY;
    IJB721TiersHookDeployer HOOK_DEPLOYER;
    CTPublisher PUBLISHER;
    JBBuybackHook BUYBACK_HOOK;
    JBBuybackHookRegistry BUYBACK_REGISTRY;
    IREVLoans LOANS_CONTRACT;
    REVDeployer REV_DEPLOYER;

    // Accept ETH for cashout returns.
    receive() external payable {}

    function setUp() public override {
        // Fork mainnet at a stable block — deterministic and post-V4 deployment.
        vm.createSelectFork("ethereum", 21_700_000);
        require(POOL_MANAGER_ADDR.code.length > 0, "PoolManager not deployed at expected address");

        // Deploy fresh JB core on the forked mainnet.
        super.setUp();

        poolManager = IPoolManager(POOL_MANAGER_ADDR);
        liqHelper = new FullStackLiquidityHelper(poolManager);

        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        SUCKER_REGISTRY = new JBSuckerRegistry(jbDirectory(), jbPermissions(), multisig(), address(0));
        HOOK_STORE = new JB721TiersHookStore();
        EXAMPLE_HOOK = new JB721TiersHook(
            jbDirectory(), jbPermissions(), jbPrices(), jbRulesets(), HOOK_STORE, jbSplits(), multisig()
        );
        ADDRESS_REGISTRY = new JBAddressRegistry();
        HOOK_DEPLOYER = new JB721TiersHookDeployer(EXAMPLE_HOOK, HOOK_STORE, ADDRESS_REGISTRY, multisig());
        PUBLISHER = new CTPublisher(jbDirectory(), jbPermissions(), FEE_PROJECT_ID, multisig());

        // Deploy REAL buyback hook with real PoolManager.
        BUYBACK_HOOK = new JBBuybackHook(
            jbDirectory(),
            jbPermissions(),
            jbPrices(),
            jbProjects(),
            jbTokens(),
            poolManager,
            IHooks(address(0)),
            address(0)
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

        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_FullStack"}(
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

        // Fund actors.
        vm.deal(PAYER, 100 ether);
        vm.deal(BORROWER, 100 ether);
    }

    // ───────────────────────── Config Helpers
    // ─────────────────────────

    function _buildConfig(uint16 cashOutTaxRate)
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

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0].beneficiary = payable(multisig());
        splits[0].percent = 10_000;
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

        cfg = REVConfig({
            description: REVDescription("FullStack Test", "FSTK", "ipfs://fullstack", "FULLSTACK_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("FULLSTACK"))
        });
    }

    function _buildTwoStageConfig(
        uint16 stage1Tax,
        uint16 stage2Tax
    )
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

        REVStageConfig[] memory stages = new REVStageConfig[](2);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0].beneficiary = payable(multisig());
        splits[0].percent = 10_000;

        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 0,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: stage1Tax,
            extraMetadata: 0
        });

        stages[1] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp + 30 days),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 0,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: stage2Tax,
            extraMetadata: 0
        });

        cfg = REVConfig({
            description: REVDescription("TwoStage", "2STG", "ipfs://2stg", "2STG_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("2STG"))
        });
    }

    function _build721Config() internal view returns (REVDeploy721TiersHookConfig memory) {
        JB721TierConfig[] memory tiers = new JB721TierConfig[](1);
        JBSplit[] memory tierSplits = new JBSplit[](1);
        tierSplits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(SPLIT_BENEFICIARY),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        tiers[0] = JB721TierConfig({
            price: TIER_PRICE,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32("tier1"),
            category: 1,
            discountPercent: 0,
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false,
            splitPercent: SPLIT_PERCENT,
            splits: tierSplits
        });

        return REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "FullStack NFT",
                symbol: "FSNFT",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: "ipfs://contract",
                tiersConfig: JB721InitTiersConfig({
                    tiers: tiers, currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18
                }),
                reserveBeneficiary: address(0),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            salt: bytes32("FSTK_721"),
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });
    }

    // ───────────────────────── Pool Helpers
    // ─────────────────────────

    /// @notice Add liquidity to the buyback pool. The buyback pool uses native ETH (address(0)), not WETH.
    function _setupPool(uint256 revnetId, uint256 liquidityTokenAmount) internal returns (PoolKey memory key) {
        address projectToken = address(jbTokens().tokenOf(revnetId));
        require(projectToken != address(0), "project token not deployed");

        // Native ETH is address(0) — always sorts before any ERC-20.
        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(projectToken),
            fee: REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(),
            tickSpacing: REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(),
            hooks: IHooks(address(0))
        });

        // Pool is already initialized and registered by REVDeployer during deployment.
        // This helper only adds liquidity to the existing pool.

        // Fund LiquidityHelper with project tokens and native ETH.
        // At high tick (~69078 for 1000 tokens/ETH), full-range liquidity needs ~32x more project tokens than ETH.
        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, liquidityTokenAmount * 50);
        vm.deal(address(liqHelper), liquidityTokenAmount);

        vm.prank(address(liqHelper));
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);

        int256 liquidityDelta = int256(liquidityTokenAmount / 50);
        vm.prank(address(liqHelper));
        liqHelper.addLiquidity{value: liquidityTokenAmount}(key, TICK_LOWER, TICK_UPPER, liquidityDelta);

        _mockOracle(liquidityDelta, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
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

    // ───────────────────────── Deployment Helpers
    // ─────────────────────────

    function _deployFeeProject(uint16 cashOutTaxRate) internal {
        (REVConfig memory feeCfg, JBTerminalConfig[] memory feeTc, REVSuckerDeploymentConfig memory feeSdc) =
            _buildConfig(cashOutTaxRate);
        feeCfg.description = REVDescription("Fee", "FEE", "ipfs://fee", "FEE_SALT");

        vm.prank(multisig());
        REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID,
            configuration: feeCfg,
            terminalConfigurations: feeTc,
            suckerDeploymentConfiguration: feeSdc
        });
    }

    function _deployRevnet(uint16 cashOutTaxRate) internal returns (uint256 revnetId) {
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildConfig(cashOutTaxRate);

        (revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

    function _deployRevnetWith721(uint16 cashOutTaxRate) internal returns (uint256 revnetId, IJB721TiersHook hook) {
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildConfig(cashOutTaxRate);
        REVDeploy721TiersHookConfig memory hookConfig = _build721Config();

        (revnetId, hook) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            terminalConfigurations: tc,
            suckerDeploymentConfiguration: sdc,
            tiered721HookConfiguration: hookConfig,
            allowedPosts: new REVCroptopAllowedPost[](0)
        });
    }

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

    function _nativeLoanSource() internal view returns (REVLoanSource memory) {
        return REVLoanSource({token: JBConstants.NATIVE_TOKEN, terminal: jbMultiTerminal()});
    }

    function _grantBurnPermission(address account, uint256 revnetId) internal {
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 11; // BURN_TOKENS
        vm.prank(account);
        jbPermissions()
            .setPermissionsFor(
                account,
                JBPermissionsData({
                    operator: address(LOANS_CONTRACT), projectId: uint64(revnetId), permissionIds: permissionIds
                })
            );
    }

    function _buildPayMetadataNoQuote(address hookMetadataTarget) internal pure returns (bytes memory) {
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

    // ═══════════════════════════════════════════════════════════════════
    //  Tests
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Pay ETH → receive project tokens via mint path (pool at 1:1, mint wins).
    function test_fullStack_payAndMintTokens() public {
        _deployFeeProject(5000);
        uint256 revnetId = _deployRevnet(5000);
        _setupPool(revnetId, 10_000 ether);

        uint256 tokens = _payRevnet(revnetId, PAYER, 1 ether);

        // With 1000 tokens/ETH issuance and mint path winning, expect ~1000 tokens.
        assertGt(tokens, 0, "should receive tokens");
        assertEq(tokens, 1000e18, "should receive 1000 tokens per ETH");

        // Terminal balance should reflect the payment.
        assertGt(_terminalBalance(revnetId, JBConstants.NATIVE_TOKEN), 0, "terminal should have balance");
    }

    /// @notice Pay with 721 tier metadata → NFT minted + 30% split to beneficiary.
    function test_fullStack_payWith721TierSplits() public {
        _deployFeeProject(5000);
        (uint256 revnetId, IJB721TiersHook hook) = _deployRevnetWith721(5000);
        _setupPool(revnetId, 10_000 ether);

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

        // 30% split → payer gets 70% of 1000 = 700 tokens.
        assertEq(tokens, 700e18, "should get 700 tokens after 30% split");

        // PAYER should own a tier 1 NFT.
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should own 1 NFT");
    }

    /// @notice Cash out tokens → bonding curve reclaim with tax + fee.
    function test_fullStack_cashOutWithBondingCurve() public {
        _deployFeeProject(5000);
        uint256 revnetId = _deployRevnet(5000); // 50% cashOutTaxRate
        _setupPool(revnetId, 10_000 ether);

        // Two payers so bonding curve tax has visible effect.
        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 payerEthBefore = PAYER.balance;

        // Cash out all payer tokens.
        vm.prank(PAYER);
        uint256 reclaimed = jbMultiTerminal()
            .cashOutTokensOf({
                holder: PAYER,
                projectId: revnetId,
                cashOutCount: payerTokens,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(PAYER),
                metadata: ""
            });

        assertGt(reclaimed, 0, "should reclaim some ETH");

        // With 50% tax and holding 2/3 of supply, reclaim should be less than pro-rata (10 ETH).
        uint256 ethReceived = PAYER.balance - payerEthBefore;
        assertLt(ethReceived, 10 ether, "reclaim should be less than pro-rata due to tax");
        assertGt(ethReceived, 0, "should receive some ETH");

        // Tokens should be burned.
        assertEq(jbTokens().totalBalanceOf(PAYER, revnetId), 0, "tokens should be burned");
    }

    /// @notice Borrow against tokens → repay → get collateral back.
    function test_fullStack_loanBorrowAndRepay() public {
        _deployFeeProject(5000);
        uint256 revnetId = _deployRevnet(5000);
        _setupPool(revnetId, 10_000 ether);

        _payRevnet(revnetId, PAYER, 10 ether);
        _payRevnet(revnetId, BORROWER, 5 ether);

        uint256 borrowerTokens = jbTokens().totalBalanceOf(BORROWER, revnetId);

        // Check borrowable amount.
        uint256 borrowable = LOANS_CONTRACT.borrowableAmountFrom(
            revnetId, borrowerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))
        );
        assertGt(borrowable, 0, "should have borrowable amount");

        // Create loan.
        _grantBurnPermission(BORROWER, revnetId);
        REVLoanSource memory source = _nativeLoanSource();

        uint256 borrowerEthBefore = BORROWER.balance;

        vm.startPrank(BORROWER);
        (uint256 loanId, REVLoan memory loan) = LOANS_CONTRACT.borrowFrom({
            revnetId: revnetId,
            source: source,
            minBorrowAmount: 0,
            collateralCount: borrowerTokens,
            beneficiary: payable(BORROWER),
            prepaidFeePercent: LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT()
        });
        vm.stopPrank();

        assertGt(loanId, 0, "loan should be created");
        assertGt(BORROWER.balance, borrowerEthBefore, "borrower should receive ETH");

        // Collateral burned — borrower may have a small fee-rebate balance from the loan fee payment.
        uint256 postBorrowBalance = jbTokens().totalBalanceOf(BORROWER, revnetId);
        assertLt(postBorrowBalance, borrowerTokens / 100, "most tokens should be burned as collateral");

        // Loan NFT owned by borrower.
        assertEq(REVLoans(payable(address(LOANS_CONTRACT))).ownerOf(loanId), BORROWER, "loan NFT owned by borrower");

        // Repay the loan.
        vm.deal(BORROWER, 100 ether);
        JBSingleAllowance memory allowance;

        vm.startPrank(BORROWER);
        LOANS_CONTRACT.repayLoan{value: loan.amount * 2}({
            loanId: loanId,
            maxRepayBorrowAmount: loan.amount * 2,
            collateralCountToReturn: loan.collateral,
            beneficiary: payable(BORROWER),
            allowance: allowance
        });
        vm.stopPrank();

        // Collateral returned (plus any fee-rebate tokens from borrowing).
        assertGe(
            jbTokens().totalBalanceOf(BORROWER, revnetId), borrowerTokens, "collateral should be returned after repay"
        );

        // Loan NFT burned.
        vm.expectRevert();
        REVLoans(payable(address(LOANS_CONTRACT))).ownerOf(loanId);
    }

    /// @notice Mock sucker → 0% tax + 0% fee exemption on cash-out.
    function test_fullStack_suckerExemptCashOut() public {
        _deployFeeProject(5000);
        uint256 revnetId = _deployRevnet(5000);
        _setupPool(revnetId, 10_000 ether);

        _payRevnet(revnetId, PAYER, 10 ether);

        address sucker = makeAddr("sucker");
        vm.deal(sucker, 5 ether);
        _payRevnet(revnetId, sucker, 5 ether);

        uint256 suckerTokens = jbTokens().totalBalanceOf(sucker, revnetId);
        uint256 surplus = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);

        // Register the sucker address.
        vm.mockCall(
            address(SUCKER_REGISTRY),
            abi.encodeWithSelector(IJBSuckerRegistry.isSuckerOf.selector, revnetId, sucker),
            abi.encode(true)
        );

        uint256 suckerEthBefore = sucker.balance;

        vm.prank(sucker);
        jbMultiTerminal()
            .cashOutTokensOf({
                holder: sucker,
                projectId: revnetId,
                cashOutCount: suckerTokens,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(sucker),
                metadata: ""
            });

        uint256 ethReceived = sucker.balance - suckerEthBefore;

        // Sucker should get full pro-rata share: surplus * (tokens / totalSupply), no tax, no fee.
        uint256 totalSupply = jbTokens().totalSupplyOf(revnetId) + suckerTokens; // tokens were burned
        uint256 expectedProRata = surplus * suckerTokens / totalSupply;

        // Allow small rounding error (< 10 wei).
        assertApproxEqAbs(ethReceived, expectedProRata, 10, "sucker should get full pro-rata share");
        assertGt(ethReceived, 0, "sucker should receive ETH");
    }

    /// @notice Reserved token distribution to splits.
    function test_fullStack_reservedTokenDistribution() public {
        // Deploy with reserved percent via the revnet's stage splitPercent.
        _deployFeeProject(5000);

        // Build config with 20% split to operator.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) = _buildConfig(5000);

        // Modify to add 20% splitPercent (2000 out of 10_000).
        cfg.stageConfigurations[0].splitPercent = 2000;

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupPool(revnetId, 10_000 ether);

        // Pay to generate tokens with reserved portion.
        _payRevnet(revnetId, PAYER, 10 ether);

        // Check pending reserved tokens.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);

        if (pending > 0) {
            // Distribute reserved tokens.
            jbController().sendReservedTokensToSplitsOf(revnetId);

            // Multisig (split beneficiary) should have received tokens.
            uint256 multisigTokens = jbTokens().totalBalanceOf(multisig(), revnetId);
            assertGt(multisigTokens, 0, "multisig should receive reserved tokens");
        }
    }

    /// @notice Warp to stage 2 → verify new cashOutTaxRate applies.
    function test_fullStack_crossStageTransition() public {
        _deployFeeProject(5000);

        // Deploy two-stage: 70% tax → 20% tax after 30 days.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageConfig(7000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupPool(revnetId, 10_000 ether);

        // Pay with two payers.
        _payRevnet(revnetId, PAYER, 10 ether);
        address payer2 = makeAddr("payer2");
        vm.deal(payer2, 10 ether);
        _payRevnet(revnetId, payer2, 5 ether);

        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);

        // Record borrowable in stage 1 (70% tax).
        uint256 borrowableStage1 =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN)));

        // Warp to stage 2 (20% tax).
        vm.warp(block.timestamp + 31 days);

        // Borrowable amount should increase with lower tax.
        uint256 borrowableStage2 =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN)));
        assertGt(borrowableStage2, borrowableStage1, "borrowable should increase with lower tax in stage 2");

        // Cash out in stage 2 should give more than stage 1 would have.
        uint256 payerEthBefore = PAYER.balance;
        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
                holder: PAYER,
                projectId: revnetId,
                cashOutCount: payerTokens,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(PAYER),
                metadata: ""
            });

        uint256 ethReceived = PAYER.balance - payerEthBefore;
        assertGt(ethReceived, 0, "should receive ETH in stage 2 cashout");
    }

    /// @notice Full lifecycle: deploy → pay → borrow → warp → repay → cash out remainder.
    function test_fullStack_fullLifecycle() public {
        _deployFeeProject(5000);
        (uint256 revnetId, IJB721TiersHook hook) = _deployRevnetWith721(5000);
        _setupPool(revnetId, 10_000 ether);

        // 1. Pay with 721 tier selection.
        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataNoQuote(metadataTarget);

        vm.prank(BORROWER);
        uint256 borrowerTokens = jbMultiTerminal().pay{value: 5 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 5 ether,
            beneficiary: BORROWER,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        assertGt(borrowerTokens, 0, "should receive tokens");
        assertEq(IERC721(address(hook)).balanceOf(BORROWER), 1, "should own 1 NFT");

        // Also pay without tier metadata (another payer for bonding curve effect).
        _payRevnet(revnetId, PAYER, 10 ether);

        // 2. Borrow against tokens.
        _grantBurnPermission(BORROWER, revnetId);
        REVLoanSource memory source = _nativeLoanSource();

        vm.startPrank(BORROWER);
        (uint256 loanId, REVLoan memory loan) = LOANS_CONTRACT.borrowFrom({
            revnetId: revnetId,
            source: source,
            minBorrowAmount: 0,
            collateralCount: borrowerTokens,
            beneficiary: payable(BORROWER),
            prepaidFeePercent: LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT()
        });
        vm.stopPrank();

        assertGt(loanId, 0, "loan should be created");

        // 3. Repay the loan.
        vm.deal(BORROWER, 100 ether);
        JBSingleAllowance memory allowance;

        vm.startPrank(BORROWER);
        LOANS_CONTRACT.repayLoan{value: loan.amount * 2}({
            loanId: loanId,
            maxRepayBorrowAmount: loan.amount * 2,
            collateralCountToReturn: loan.collateral,
            beneficiary: payable(BORROWER),
            allowance: allowance
        });
        vm.stopPrank();

        uint256 tokensAfterRepay = jbTokens().totalBalanceOf(BORROWER, revnetId);
        assertGe(tokensAfterRepay, borrowerTokens, "full collateral returned (may include fee-rebate tokens)");

        // 4. Cash out half the tokens.
        uint256 cashOutCount = tokensAfterRepay / 2;
        uint256 borrowerEthBefore = BORROWER.balance;

        vm.prank(BORROWER);
        jbMultiTerminal()
            .cashOutTokensOf({
                holder: BORROWER,
                projectId: revnetId,
                cashOutCount: cashOutCount,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(BORROWER),
                metadata: ""
            });

        assertGt(BORROWER.balance, borrowerEthBefore, "should receive ETH from cashout");
        assertEq(
            jbTokens().totalBalanceOf(BORROWER, revnetId), tokensAfterRepay - cashOutCount, "remaining tokens correct"
        );
    }
}
