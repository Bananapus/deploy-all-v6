// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {IGeomeanOracle} from "@bananapus/buyback-hook-v6/src/interfaces/IGeomeanOracle.sol";

// Suckers
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// Croptop
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";

// LP Split Hook
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";
import {IJBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/interfaces/IJBUniswapV4LPSplitHook.sol";

// Uniswap V4 Router Hook
import {JBUniswapV4Hook} from "@bananapus/univ4-router-v6/src/JBUniswapV4Hook.sol";
import {JuiceboxSwapRouter} from "@bananapus/univ4-router-v6/test/utils/JuiceboxSwapRouter.sol";

// Revnet
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";
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
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";

/// @notice Mock USDC token with 6 decimals for fork testing.
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Adds liquidity to a hookless V4 pool via unlock/callback pattern.
/// Supports both native ETH (address(0)) and ERC-20 settlement.
contract USDCEcosystemLiquidityHelper is IUnlockCallback {
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

/// @notice USDC ecosystem integration fork test: multi-stage revnet with buyback hook, 721 tier splits,
/// LP-split hook feeding the buyback AMM, and payments via USDC terminal.
///
/// Mirrors EcosystemForkTest but uses a MockUSDC (6-decimal ERC-20) instead of native ETH.
///
/// Run with: forge test --match-contract USDCEcosystemForkTest -vvv
contract USDCEcosystemForkTest is TestBaseWorkflow {
    using PoolIdLibrary for PoolKey;

    // -- Mainnet addresses
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant V4_POSITION_MANAGER_ADDR = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;

    // -- Tick range for full-range liquidity (hookless pool)
    int24 constant TICK_LOWER = -887_200;
    int24 constant TICK_UPPER = 887_200;

    // -- Test parameters
    uint112 constant INITIAL_ISSUANCE = uint112(1000e18); // 1000 tokens per USDC unit
    uint32 constant STAGE_DURATION = 30 days;
    uint104 constant TIER_PRICE = 100e6; // 100 USDC for NFT tier

    // -- Actors
    address PAYER = makeAddr("payer");
    address BORROWER = makeAddr("borrower");
    address SPLIT_BENEFICIARY = makeAddr("splitBeneficiary");

    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // -- Ecosystem contracts
    IPoolManager poolManager;
    IPositionManager positionManager;
    USDCEcosystemLiquidityHelper liqHelper;

    MockUSDC usdc;

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
    REVOwner REV_OWNER;
    REVDeployer REV_DEPLOYER;

    // LP-split hook
    JBUniswapV4LPSplitHook LP_SPLIT_HOOK;

    receive() external payable {}

    function setUp() public override {
        // Fork mainnet at a stable block — deterministic and post-V4 deployment.
        vm.createSelectFork("ethereum", 21_700_000);
        require(POOL_MANAGER_ADDR.code.length > 0, "PoolManager not deployed");
        require(V4_POSITION_MANAGER_ADDR.code.length > 0, "PositionManager not deployed");

        // Deploy fresh JB core on the forked mainnet.
        super.setUp();

        poolManager = IPoolManager(POOL_MANAGER_ADDR);
        positionManager = IPositionManager(V4_POSITION_MANAGER_ADDR);
        liqHelper = new USDCEcosystemLiquidityHelper(poolManager);

        // Deploy MockUSDC.
        usdc = new MockUSDC();

        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        SUCKER_REGISTRY = new JBSuckerRegistry(jbDirectory(), jbPermissions(), multisig(), address(0));
        HOOK_STORE = new JB721TiersHookStore();
        EXAMPLE_HOOK = new JB721TiersHook(
            jbDirectory(), jbPermissions(), jbPrices(), jbRulesets(), HOOK_STORE, jbSplits(), multisig()
        );
        ADDRESS_REGISTRY = new JBAddressRegistry();
        HOOK_DEPLOYER = new JB721TiersHookDeployer(EXAMPLE_HOOK, HOOK_STORE, ADDRESS_REGISTRY, multisig());
        PUBLISHER = new CTPublisher(jbDirectory(), jbPermissions(), FEE_PROJECT_ID, multisig());

        // Deploy buyback hook with real PoolManager.
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

        // Deploy the REVOwner — the runtime data hook for pay and cash out callbacks.
        REV_OWNER = new REVOwner(
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            jbDirectory(),
            FEE_PROJECT_ID,
            SUCKER_REGISTRY,
            address(LOANS_CONTRACT)
        );

        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_USDC"}(
            jbController(),
            SUCKER_REGISTRY,
            FEE_PROJECT_ID,
            HOOK_DEPLOYER,
            PUBLISHER,
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            address(LOANS_CONTRACT),
            TRUSTED_FORWARDER,
            address(REV_OWNER)
        );

        vm.prank(multisig());
        jbProjects().approve(address(REV_DEPLOYER), FEE_PROJECT_ID);

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
        // The buyback hook queries IGeomeanOracle.observe() on the pool's hooks address (address(0)
        // for hookless pools). Without this mock, any pay() call would revert.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Fund actors with USDC instead of ETH.
        usdc.mint(PAYER, 200_000e6); // 200,000 USDC
        usdc.mint(BORROWER, 100_000e6); // 100,000 USDC

        // Fund actors with some ETH for gas.
        vm.deal(PAYER, 1 ether);
        vm.deal(BORROWER, 1 ether);
    }

    // ===================================================================
    //  Config Helpers
    // ===================================================================

    /// @notice Build a two-stage config: high tax -> low tax. Uses USDC terminal. Includes LP-split hook as a
    /// reserved token split.
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

        // Splits: 50% to LP-split hook, 50% to multisig.
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

        // Stage 1: high tax, starts immediately.
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

        // Stage 2: low tax, starts after STAGE_DURATION.
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
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("UECO"))
        });
    }

    /// @notice Build 721 tier config with USDC pricing and a 30% tier split to SPLIT_BENEFICIARY.
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
            salt: bytes32("UECO_721"),
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });
    }

    // ===================================================================
    //  Pool / Buyback Helpers
    // ===================================================================

    /// @notice Set up a USDC buyback pool. The pool is already initialized and registered by REVDeployer
    /// during deployment. This helper only adds liquidity to the existing pool.
    function _setupUSDCBuybackPool(uint256 revnetId, uint256 liquidityAmount) internal returns (PoolKey memory key) {
        address projectToken = address(jbTokens().tokenOf(revnetId));
        require(projectToken != address(0), "project token not deployed");

        // Sort tokens — USDC is an ERC-20 so ordering depends on addresses.
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
        // This helper only adds liquidity to the existing pool.

        // Fund LiquidityHelper with USDC and project tokens.
        usdc.mint(address(liqHelper), liquidityAmount);
        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, liquidityAmount * 1e12); // Scale 6-dec USDC to 18-dec project
        // tokens.

        vm.startPrank(address(liqHelper));
        IERC20(address(usdc)).approve(address(poolManager), type(uint256).max);
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);
        vm.stopPrank();

        int256 liquidityDelta = int256(liquidityAmount / 2);
        vm.prank(address(liqHelper));
        liqHelper.addLiquidity(key, TICK_LOWER, TICK_UPPER, liquidityDelta);

        // Compute the oracle tick that matches the issuance rate: 1000 project tokens (18 dec) per USDC (6 dec).
        // Raw ratio = 1e21 / 1e6 = 1e15. tick = ln(1e15)/ln(1.0001) ≈ 345_400.
        // Sign depends on token sort order: positive if USDC is token0 (project token is more expensive in raw terms).
        int24 issuanceTick = address(usdc) < projectToken ? int24(345_400) : int24(-345_400);
        _mockOracle(liquidityDelta, issuanceTick, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
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

    // ===================================================================
    //  Payment / Metadata Helpers
    // ===================================================================

    /// @notice Deploy the fee project using ETH (same as EcosystemFork — fee project can use ETH).
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
            description: REVDescription("Fee", "FEE", "ipfs://fee", "FEE_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("FEE"))
        });

        vm.prank(multisig());
        REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

    /// @notice Pay a revnet with USDC. Mints USDC to the payer if needed, approves, and calls pay().
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

    /// @notice Pre-AMM: Pay USDC from the terminal before any pool is set up. Mint path must work.
    function test_eco_usdc_preAMM_payFromTerminal() public {
        _deployFeeProject(5000);

        // Deploy revnet with two stages (70%->20% tax), 20% reserved split.
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

        // No pool set up yet -> payment should mint directly.
        uint256 tokens = _payRevnetUSDC(revnetId, PAYER, 1000e6); // 1000 USDC

        // With 1000 tokens/USDC issuance and 20% reserved, payer gets 80% = 800 tokens per USDC.
        // Paying 1000 USDC: total mint = 1000 * 1000 = 1,000,000 tokens. Reserved 20% = 200,000. Payer gets 800,000.
        assertGt(tokens, 0, "should receive tokens pre-AMM");
        assertEq(tokens, 800_000e18, "should receive 800,000 tokens (80% of 1,000,000 after 20% reserved)");

        // Terminal should have USDC balance.
        assertGt(_terminalBalanceUSDC(revnetId), 0, "terminal should have USDC balance");
    }

    /// @notice Pre-AMM: Pay with 721 tier metadata -> NFT minted, 30% tier split distributed to SPLIT_BENEFICIARY.
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
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);

        // Pay 100 USDC (the tier price) with tier metadata.
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

        // NFT should be minted to PAYER.
        assertEq(IERC721(address(hook)).balanceOf(PAYER), 1, "payer should own 1 NFT");

        // Split beneficiary should have received 30% of 100 USDC = 30 USDC.
        assertEq(usdc.balanceOf(SPLIT_BENEFICIARY), 30e6, "split beneficiary should have 30 USDC");

        // With 30% tier split, weight is adjusted to 70% of original.
        // Total mint = 100 USDC * 1000 tokens/USDC * 0.7 = 70,000 tokens.
        // Reserved takes 20% = 14,000. Payer receives 56,000.
        assertGt(tokens, 0, "should receive tokens");
        assertEq(tokens, 56_000e18, "payer should receive 56,000 tokens (80% of 70k)");
    }

    /// @notice Distribute reserved tokens -> LP-split hook accumulates them.
    function test_eco_usdc_lpSplitHookAccumulates() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageUSDCConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay to generate reserved tokens.
        _payRevnetUSDC(revnetId, PAYER, 10_000e6); // 10,000 USDC
        _payRevnetUSDC(revnetId, BORROWER, 5000e6); // 5,000 USDC

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

    /// @notice Post-AMM: Pay USDC from terminal after pool is set up -> buyback hook compares swap vs mint.
    function test_eco_usdc_postAMM_payFromTerminal() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageUSDCConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Set up USDC buyback pool with real liquidity.
        _setupUSDCBuybackPool(revnetId, 10_000e6); // 10,000 USDC

        // Pay some surplus so bonding curve has visible effect.
        _payRevnetUSDC(revnetId, BORROWER, 5000e6);

        // Pay again — buyback hook is now active.
        uint256 tokens = _payRevnetUSDC(revnetId, PAYER, 1000e6); // 1,000 USDC

        // Should receive tokens (either via mint or swap, whichever wins).
        assertGt(tokens, 0, "should receive tokens post-AMM");

        // Terminal balance should increase.
        assertGt(_terminalBalanceUSDC(revnetId), 0, "terminal balance should increase");
    }

    /// @notice Warp to stage 2, verify new cashOutTaxRate applies and buyback hook still works with USDC.
    function test_eco_usdc_crossStageWithBuyback() public {
        _deployFeeProject(5000);

        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildTwoStageUSDCConfigWithLPSplit(7000, 2000, 2000);

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        _setupUSDCBuybackPool(revnetId, 10_000e6);

        // Pay in stage 1 (70% tax).
        _payRevnetUSDC(revnetId, PAYER, 10_000e6);
        _payRevnetUSDC(revnetId, BORROWER, 5000e6);

        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);

        // Record borrowable in stage 1.
        uint256 borrowableStage1 =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 6, uint32(uint160(address(usdc))));

        // Warp to stage 2 (20% tax).
        vm.warp(block.timestamp + STAGE_DURATION + 1);

        // Borrowable should increase with lower tax.
        uint256 borrowableStage2 =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, payerTokens, 6, uint32(uint160(address(usdc))));
        assertGt(borrowableStage2, borrowableStage1, "borrowable should increase in stage 2");

        // Payment in stage 2 should still work with buyback hook.
        address payer2 = makeAddr("payer2");
        uint256 tokens = _payRevnetUSDC(revnetId, payer2, 1000e6);
        assertGt(tokens, 0, "payment should work in stage 2 with buyback");
    }

    /// @notice Full lifecycle with USDC: deploy -> pre-AMM pay -> distribute reserved -> set up pool ->
    /// post-AMM pay -> cash out USDC.
    function test_eco_usdc_fullLifecycle() public {
        _deployFeeProject(5000);

        // 1. Deploy revnet with 721 + LP-split using USDC terminal.
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

        // 2. Pre-AMM payment (mint path only, no pool).
        uint256 tokensPreAMM = _payRevnetUSDC(revnetId, PAYER, 5000e6); // 5,000 USDC
        assertGt(tokensPreAMM, 0, "pre-AMM payment should mint tokens");

        // Another payer for bonding curve effects.
        _payRevnetUSDC(revnetId, BORROWER, 5000e6);

        // 3. Distribute reserved tokens -> LP-split hook accumulates.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);
        if (pending > 0) {
            jbController().sendReservedTokensToSplitsOf(revnetId);
        }
        uint256 accumulated = LP_SPLIT_HOOK.accumulatedProjectTokens(revnetId);
        assertGt(accumulated, 0, "LP split hook should accumulate from reserved distribution");

        // 4. Set up USDC buyback pool (separate from LP-split hook's pool).
        _setupUSDCBuybackPool(revnetId, 10_000e6);

        // 5. Post-AMM payment with 721 tier.
        address metadataTarget = hook.METADATA_ID_TARGET();
        bytes memory metadata = _buildPayMetadataWithTier(metadataTarget);

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
    }
}
