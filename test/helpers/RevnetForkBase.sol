// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";

// 721 Hook
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721CheckpointsDeployer} from "@bananapus/721-hook-v6/src/JB721CheckpointsDeployer.sol";
import {IJB721TiersHook} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHookStore} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "@bananapus/721-hook-v6/src/interfaces/IJB721TokenUriResolver.sol";
import {JB721TierConfig} from "@bananapus/721-hook-v6/src/structs/JB721TierConfig.sol";
import {JB721InitTiersConfig} from "@bananapus/721-hook-v6/src/structs/JB721InitTiersConfig.sol";
import {JB721TierConfigFlags} from "@bananapus/721-hook-v6/src/structs/JB721TierConfigFlags.sol";

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
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";
import {IREVDeployer} from "@rev-net/core-v6/src/interfaces/IREVDeployer.sol";
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
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {V4LiquidityHelper} from "./V4LiquidityHelper.sol";

/// @notice Base class for all deploy-all-v6 fork tests using native ETH.
/// Deploys the full Juicebox V6 ecosystem on forked mainnet and provides shared helpers.
/// Replaces ~13 copies of setUp + _mockOracle + _deployFeeProject + _payRevnet.
abstract contract RevnetForkBase is TestBaseWorkflow {
    // ── Mainnet addresses
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    // ── Tick range for full-range liquidity
    int24 constant TICK_LOWER = -887_200;
    int24 constant TICK_UPPER = 887_200;

    // ── Default test parameters
    uint112 constant INITIAL_ISSUANCE = uint112(1000e18);
    uint32 constant STAGE_DURATION = 30 days;
    uint104 constant TIER_PRICE = 1 ether;
    uint32 constant SPLIT_PERCENT_30 = 300_000_000;

    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // ── Actors
    address PAYER = makeAddr("payer");
    address BORROWER = makeAddr("borrower");
    address SPLIT_BENEFICIARY = makeAddr("splitBeneficiary");

    // ── Ecosystem contracts
    IPoolManager poolManager;
    V4LiquidityHelper liqHelper;

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

    receive() external payable {}

    /// @dev Override to provide a unique CREATE2 salt for REVDeployer per test contract.
    function _deployerSalt() internal pure virtual returns (bytes32) {
        return "RevnetForkBase";
    }

    function setUp() public virtual override {
        vm.createSelectFork("ethereum", 21_700_000);
        require(POOL_MANAGER_ADDR.code.length > 0, "PoolManager not deployed at expected address");

        super.setUp();

        poolManager = IPoolManager(POOL_MANAGER_ADDR);
        liqHelper = new V4LiquidityHelper(poolManager);

        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        SUCKER_REGISTRY = new JBSuckerRegistry(jbDirectory(), jbPermissions(), multisig(), address(0));
        HOOK_STORE = new JB721TiersHookStore();
        JB721CheckpointsDeployer checkpointsDeployer = new JB721CheckpointsDeployer(HOOK_STORE);
        EXAMPLE_HOOK = new JB721TiersHook(
            jbDirectory(),
            jbPermissions(),
            jbPrices(),
            jbRulesets(),
            HOOK_STORE,
            jbSplits(),
            checkpointsDeployer,
            multisig()
        );
        ADDRESS_REGISTRY = new JBAddressRegistry();
        HOOK_DEPLOYER = new JB721TiersHookDeployer(EXAMPLE_HOOK, HOOK_STORE, ADDRESS_REGISTRY, multisig());
        PUBLISHER = new CTPublisher(jbDirectory(), jbPermissions(), FEE_PROJECT_ID, multisig());

        BUYBACK_HOOK = new JBBuybackHook(
            jbDirectory(), jbPermissions(), jbPrices(), jbProjects(), jbTokens(), address(this), address(0)
        );
        BUYBACK_HOOK.setChainSpecificConstants(poolManager, IHooks(address(0)));

        BUYBACK_REGISTRY = new JBBuybackHookRegistry(jbPermissions(), jbProjects(), address(this), address(0));
        BUYBACK_REGISTRY.setDefaultHook(IJBRulesetDataHook(address(BUYBACK_HOOK)));

        LOANS_CONTRACT = new REVLoans({
            controller: jbController(),
            suckerRegistry: IJBSuckerRegistry(address(SUCKER_REGISTRY)),
            revId: FEE_PROJECT_ID,
            owner: address(this),
            permit2: permit2(),
            trustedForwarder: TRUSTED_FORWARDER
        });

        REV_OWNER = new REVOwner(
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            jbDirectory(),
            FEE_PROJECT_ID,
            SUCKER_REGISTRY,
            LOANS_CONTRACT,
            address(this)
        );

        REV_DEPLOYER = new REVDeployer{salt: _deployerSalt()}(
            jbController(),
            SUCKER_REGISTRY,
            FEE_PROJECT_ID,
            HOOK_DEPLOYER,
            PUBLISHER,
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            LOANS_CONTRACT,
            TRUSTED_FORWARDER,
            address(REV_OWNER)
        );
        REV_OWNER.setDeployer(IREVDeployer(address(REV_DEPLOYER)));

        vm.prank(multisig());
        jbProjects().approve(address(REV_DEPLOYER), FEE_PROJECT_ID);

        // Fund default actors.
        vm.deal(PAYER, 100 ether);
        vm.deal(BORROWER, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Oracle Mock
    // ═══════════════════════════════════════════════════════════════════

    function _mockOracle(int256 liquidity, int24 tick, uint32 twapWindow) internal {
        vm.etch(address(0), hex"00");

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = 0;
        // forge-lint: disable-next-line(unsafe-typecast)
        tickCumulatives[1] = int56(tick) * int56(int32(twapWindow));

        uint136[] memory secondsPerLiquidityCumulativeX128s = new uint136[](2);
        secondsPerLiquidityCumulativeX128s[0] = 0;
        uint256 liq = uint256(liquidity > 0 ? liquidity : -liquidity);
        if (liq == 0) liq = 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        secondsPerLiquidityCumulativeX128s[1] = uint136((uint256(twapWindow) << 128) / liq);

        vm.mockCall(
            address(0),
            abi.encodeWithSelector(IGeomeanOracle.observe.selector),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Fee Project Deployment
    // ═══════════════════════════════════════════════════════════════════

    function _deployFeeProject(uint16 cashOutTaxRate) internal {
        (REVConfig memory feeCfg, JBTerminalConfig[] memory feeTc, REVSuckerDeploymentConfig memory feeSdc) =
            _buildNativeConfig(cashOutTaxRate);
        feeCfg.description = REVDescription("Fee", "FEE", "ipfs://fee", "FEE_SALT");

        // FEE_PROJECT_ID is created before the registry's default-hook threshold is set, so wire the hook explicitly.
        vm.prank(multisig());
        BUYBACK_REGISTRY.setHookFor(FEE_PROJECT_ID, IJBRulesetDataHook(address(BUYBACK_HOOK)));

        vm.prank(multisig());
        REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID,
            configuration: feeCfg,
            terminalConfigurations: feeTc,
            suckerDeploymentConfiguration: feeSdc
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Config Builders
    // ═══════════════════════════════════════════════════════════════════

    function _buildNativeConfig(uint16 cashOutTaxRate)
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
            description: REVDescription("Revnet", "REV", "ipfs://rev", "REV_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            splitOperator: multisig(),
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("REV"))
        });
    }

    function _buildTwoStageNativeConfig(
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
            startsAtOrAfter: uint40(block.timestamp + STAGE_DURATION),
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
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("2STG"))
        });
    }

    function _build721Config() internal view virtual returns (REVDeploy721TiersHookConfig memory) {
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
            splitPercent: SPLIT_PERCENT_30,
            splits: tierSplits
        });

        return REVDeploy721TiersHookConfig({
            baseline721HookConfiguration: REVBaseline721HookConfig({
                name: "Test NFT",
                symbol: "TNFT",
                baseUri: "ipfs://",
                tokenUriResolver: IJB721TokenUriResolver(address(0)),
                contractUri: "ipfs://contract",
                tiersConfig: JB721InitTiersConfig({
                    tiers: tiers, currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18
                }),
                flags: REV721TiersHookFlags({
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false,
                    preventOverspending: false
                })
            }),
            // forge-lint: disable-next-line(unsafe-typecast)
            salt: bytes32("TEST_721"),
            preventSplitOperatorAdjustingTiers: false,
            preventSplitOperatorUpdatingMetadata: false,
            preventSplitOperatorMinting: false,
            preventSplitOperatorIncreasingDiscountPercent: false
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Deployment Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _deployRevnet(uint16 cashOutTaxRate) internal returns (uint256 revnetId) {
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildNativeConfig(cashOutTaxRate);

        (revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

    function _deployRevnetWith721(uint16 cashOutTaxRate) internal returns (uint256 revnetId, IJB721TiersHook hook) {
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildNativeConfig(cashOutTaxRate);
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

    // ═══════════════════════════════════════════════════════════════════
    //  Pool Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _setupNativePool(uint256 revnetId, uint256 liquidityTokenAmount) internal returns (PoolKey memory key) {
        address projectToken = address(jbTokens().tokenOf(revnetId));
        require(projectToken != address(0), "project token not deployed");

        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(projectToken),
            fee: REV_DEPLOYER.DEFAULT_BUYBACK_POOL_FEE(),
            tickSpacing: REV_DEPLOYER.DEFAULT_BUYBACK_TICK_SPACING(),
            hooks: IHooks(address(0))
        });

        vm.prank(address(jbController()));
        jbTokens().mintFor(address(liqHelper), revnetId, liquidityTokenAmount * 50);
        vm.deal(address(liqHelper), liquidityTokenAmount);

        vm.prank(address(liqHelper));
        IERC20(projectToken).approve(address(poolManager), type(uint256).max);

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 liquidityDelta = int256(liquidityTokenAmount / 50);
        vm.prank(address(liqHelper));
        liqHelper.addLiquidity{value: liquidityTokenAmount}(key, TICK_LOWER, TICK_UPPER, liquidityDelta);

        _mockOracle(liquidityDelta, 69_078, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Payment Helpers
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
                // forge-lint: disable-next-line(unsafe-typecast)
                operator: address(LOANS_CONTRACT),
                // forge-lint: disable-next-line(unsafe-typecast)
                projectId: uint64(revnetId),
                permissionIds: permissionIds
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
}
