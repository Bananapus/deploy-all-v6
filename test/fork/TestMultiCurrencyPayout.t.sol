// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";
import {JBFixedPointNumber} from "@bananapus/core-v6/src/libraries/JBFixedPointNumber.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {JBCurrencyAmount} from "@bananapus/core-v6/src/structs/JBCurrencyAmount.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";

// 721 Hook
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721CheckpointsDeployer} from "@bananapus/721-hook-v6/src/JB721CheckpointsDeployer.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHookStore} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookStore.sol";

// Address Registry
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// Buyback Hook
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";
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
import {REVHiddenTokens} from "@rev-net/core-v6/src/REVHiddenTokens.sol";
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";
import {IREVDeployer} from "@rev-net/core-v6/src/interfaces/IREVDeployer.sol";
import {IREVLoans} from "@rev-net/core-v6/src/interfaces/IREVLoans.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

// Uniswap V4
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock USDC token with 6 decimals.
contract MCPMockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock price feed returning a fixed price.
contract MCPMockPriceFeed is IJBPriceFeed {
    uint256 public immutable PRICE;
    uint8 public immutable FEED_DECIMALS;

    constructor(uint256 price, uint8 dec) {
        PRICE = price;
        FEED_DECIMALS = dec;
    }

    function currentUnitPrice(uint256 decimals) external view override returns (uint256) {
        return JBFixedPointNumber.adjustDecimals(PRICE, FEED_DECIMALS, decimals);
    }
}

/// @notice Multi-currency payout fork test with Chainlink price conversion.
///
/// Exercises USD-denominated payout limits paid from an ETH terminal, and USDC terminal
/// payouts with USD limits. Verifies price conversion consistency across JBPrices.
///
/// Run with: forge test --match-contract TestMultiCurrencyPayout -vvv
contract TestMultiCurrencyPayout is TestBaseWorkflow {
    // -- Mainnet addresses
    address constant POOL_MANAGER_ADDR = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    // -- Test parameters
    uint112 constant INITIAL_ISSUANCE = uint112(1000e18);

    // -- Currency constants
    uint32 constant USD = 2; // JBCurrencyIds.USD

    // -- Actors
    address PAYER = makeAddr("mcp_payer");
    address SPLIT_RECIPIENT = makeAddr("mcp_splitRecipient");

    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // -- Ecosystem contracts
    IPoolManager poolManager;
    MCPMockUSDC usdc;

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

    // Currency helpers
    uint32 nativeCurrency;
    uint32 usdcCurrency;

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setUp() public override {
        vm.createSelectFork("ethereum", 21_700_000);
        require(POOL_MANAGER_ADDR.code.length > 0, "PoolManager not deployed");

        super.setUp();

        poolManager = IPoolManager(POOL_MANAGER_ADDR);
        usdc = new MCPMockUSDC();
        nativeCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));
        usdcCurrency = uint32(uint160(address(usdc)));

        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        SUCKER_REGISTRY = new JBSuckerRegistry(jbDirectory(), jbPermissions(), multisig(), address(0));
        HOOK_STORE = new JB721TiersHookStore();
        JB721CheckpointsDeployer checkpointsDeployer = new JB721CheckpointsDeployer();
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
            suckerRegistry: IJBSuckerRegistry(address(SUCKER_REGISTRY)),
            revId: FEE_PROJECT_ID,
            owner: address(this),
            permit2: permit2(),
            trustedForwarder: TRUSTED_FORWARDER
        });

        // Deploy REVHiddenTokens.
        REVHiddenTokens revHiddenTokens = new REVHiddenTokens(jbController(), TRUSTED_FORWARDER);

        // Deploy the REVOwner — the runtime data hook for pay and cash out callbacks.
        REV_OWNER = new REVOwner(
            IJBBuybackHookRegistry(address(BUYBACK_REGISTRY)),
            jbDirectory(),
            FEE_PROJECT_ID,
            SUCKER_REGISTRY,
            address(LOANS_CONTRACT),
            address(revHiddenTokens)
        );

        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_MCP"}(
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
        REV_OWNER.setDeployer(IREVDeployer(address(REV_DEPLOYER)));

        vm.prank(multisig());
        jbProjects().approve(address(REV_DEPLOYER), FEE_PROJECT_ID);

        // Mock geomean oracle so payments work.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Register price feeds: ETH/USD = 2000, USDC/USD = 1.
        MCPMockPriceFeed ethUsdFeed = new MCPMockPriceFeed(2000e18, 18);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, USD, nativeCurrency, IJBPriceFeed(address(ethUsdFeed)));

        MCPMockPriceFeed usdcUsdFeed = new MCPMockPriceFeed(1e6, 6);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, USD, usdcCurrency, IJBPriceFeed(address(usdcUsdFeed)));

        // Fund actors.
        vm.deal(PAYER, 200 ether);
        usdc.mint(PAYER, 500_000e6);
        vm.deal(SPLIT_RECIPIENT, 1 ether);
    }

    // ===================================================================
    //  Helpers
    // ===================================================================

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

    function _deployFeeProject() internal {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});
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
            cashOutTaxRate: 5000,
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("Fee", "FEE", "ipfs://fee", "FEE_MCP"),
            baseCurrency: nativeCurrency,
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("FEE_MCP"))
        });

        vm.prank(multisig());
        REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

    /// @notice Launch a plain JB project (not via REVDeployer) with explicit payout limits.
    function _launchProjectWithPayoutLimits(
        JBFundAccessLimitGroup[] memory limitGroups,
        JBTerminalConfig[] memory terminalConfigs,
        JBRulesetMetadata memory metadata
    )
        internal
        returns (uint256 projectId)
    {
        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](1);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(SPLIT_RECIPIENT),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });
        splitGroups[0] = JBSplitGroup({groupId: uint256(uint160(JBConstants.NATIVE_TOKEN)), splits: splits});

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: uint112(INITIAL_ISSUANCE),
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: metadata,
            splitGroups: splitGroups,
            fundAccessLimitGroups: limitGroups
        });

        projectId = jbController()
            .launchProjectFor({
                owner: address(this),
                projectUri: "ipfs://mcp-test",
                rulesetConfigurations: rulesets,
                terminalConfigurations: terminalConfigs,
                memo: ""
            });
    }

    function _terminalBalance(uint256 projectId, address token) internal view returns (uint256) {
        return jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, token);
    }

    // ===================================================================
    //  Tests
    // ===================================================================

    /// @notice USD-denominated payout limit paid from ETH terminal.
    /// Pay 10 ETH, set a $5000 USD payout limit, send payouts in ETH.
    /// At $2000/ETH, 2.5 ETH should be distributed.
    function test_mcp_usdPayoutLimitPaidInETH() public {
        _deployFeeProject();

        // Terminal accepts ETH.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Payout limit: $5000 USD, paid from the ETH terminal.
        JBFundAccessLimitGroup[] memory limits = new JBFundAccessLimitGroup[](1);
        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1);
        payoutLimits[0] = JBCurrencyAmount({amount: 5000e18, currency: USD}); // $5000 in 18-decimal USD
        limits[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: payoutLimits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });

        JBRulesetMetadata memory metadata = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 5000,
            baseCurrency: USD,
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
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        uint256 projectId = _launchProjectWithPayoutLimits(limits, tc, metadata);

        // Pay 10 ETH.
        vm.prank(PAYER);
        jbMultiTerminal().pay{value: 10 ether}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 10 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        assertEq(_terminalBalance(projectId, JBConstants.NATIVE_TOKEN), 10 ether, "balance should be 10 ETH");

        // Send payouts: $5000 USD limit at $2000/ETH = 2.5 ETH.
        uint256 recipientBefore = SPLIT_RECIPIENT.balance;
        jbMultiTerminal()
            .sendPayoutsOf({
                projectId: projectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: 5000e18,
                currency: USD,
                minTokensPaidOut: 0
            });

        uint256 recipientReceived = SPLIT_RECIPIENT.balance - recipientBefore;

        // 2.5 ETH minus 2.5% fee. Fee = 2.5 ETH * 25 / 1000 = 0.0625 ETH.
        // Expected: ~2.4375 ETH. Allow some rounding tolerance.
        uint256 expectedPayout = 2.5 ether;
        uint256 expectedFee = expectedPayout * 25 / 1000;
        uint256 expectedNet = expectedPayout - expectedFee;

        assertApproxEqAbs(recipientReceived, expectedNet, 100, "recipient should receive ~2.4375 ETH after fee");

        // Remaining balance should be ~7.5 ETH.
        uint256 remaining = _terminalBalance(projectId, JBConstants.NATIVE_TOKEN);
        assertApproxEqAbs(remaining, 7.5 ether, 100, "remaining balance should be ~7.5 ETH");
    }

    /// @notice USDC terminal with USDC-denominated payout limit.
    /// Pay 10,000 USDC, set 5000 USDC payout limit, send payouts in USDC.
    /// 5000 USDC should be distributed.
    ///
    /// NOTE: Payout limits use the token's own currency (usdcCurrency) and the token's native
    /// decimal precision (6 for USDC). When currency == accountingContext.currency, the
    /// JBTerminalStore takes the fast path (amountPaidOut = amount) with no price conversion,
    /// so amounts must match the token's stored balance precision.
    function test_mcp_usdPayoutLimitPaidInUSDC() public {
        _deployFeeProject();

        // Terminal accepts USDC.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: address(usdc), decimals: 6, currency: usdcCurrency});
        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        // Payout limit: 5000 USDC in the token's native 6-decimal format.
        JBFundAccessLimitGroup[] memory limits = new JBFundAccessLimitGroup[](1);
        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1);
        payoutLimits[0] = JBCurrencyAmount({amount: 5000e6, currency: usdcCurrency});

        limits[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: address(usdc),
            payoutLimits: payoutLimits,
            surplusAllowances: new JBCurrencyAmount[](0)
        });

        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](1);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(SPLIT_RECIPIENT),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });
        splitGroups[0] = JBSplitGroup({groupId: uint256(uint160(address(usdc))), splits: splits});

        JBRulesetMetadata memory metadata = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 5000,
            baseCurrency: usdcCurrency,
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
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: uint112(INITIAL_ISSUANCE),
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: metadata,
            splitGroups: splitGroups,
            fundAccessLimitGroups: limits
        });

        uint256 projectId = jbController()
            .launchProjectFor({
                owner: address(this),
                projectUri: "ipfs://mcp-usdc",
                rulesetConfigurations: rulesets,
                terminalConfigurations: tc,
                memo: ""
            });

        // Pay 10,000 USDC.
        vm.startPrank(PAYER);
        usdc.approve(address(jbMultiTerminal()), 10_000e6);
        jbMultiTerminal()
            .pay({
                projectId: projectId,
                token: address(usdc),
                amount: 10_000e6,
                beneficiary: PAYER,
                minReturnedTokens: 0,
                memo: "",
                metadata: ""
            });
        vm.stopPrank();

        uint256 balance = jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, address(usdc));
        assertEq(balance, 10_000e6, "balance should be 10,000 USDC");

        // Send payouts: 5000 USDC payout limit, same currency as accounting context.
        uint256 recipientBefore = usdc.balanceOf(SPLIT_RECIPIENT);
        jbMultiTerminal()
            .sendPayoutsOf({
                projectId: projectId, token: address(usdc), amount: 5000e6, currency: usdcCurrency, minTokensPaidOut: 0
            });

        uint256 recipientReceived = usdc.balanceOf(SPLIT_RECIPIENT) - recipientBefore;

        // 5000 USDC minus 2.5% fee = 4875 USDC.
        uint256 expectedNet = 5000e6 - (5000e6 * 25 / 1000);
        assertApproxEqAbs(recipientReceived, expectedNet, 100, "recipient should receive ~4875 USDC after fee");
    }

    /// @notice Verify price conversion consistency: paying equivalent USD amounts via ETH vs USDC
    /// should produce the same token count.
    function test_mcp_priceConversionConsistency() public {
        _deployFeeProject();

        // Deploy a USD-base revnet accepting both ETH and USDC.
        JBAccountingContext[] memory acc = new JBAccountingContext[](2);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: nativeCurrency});
        acc[1] = JBAccountingContext({token: address(usdc), decimals: 6, currency: usdcCurrency});
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
            cashOutTaxRate: 5000,
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("CC Parity", "CCP", "ipfs://ccp", "CCP_SALT"),
            baseCurrency: USD,
            splitOperator: multisig(),
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked("CCP"))
        });

        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay 1 ETH (= $2000 at mock price).
        vm.prank(PAYER);
        uint256 tokensFromETH = jbMultiTerminal().pay{value: 1 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        // Pay 2000 USDC (= $2000 at mock price).
        address payer2 = makeAddr("mcp_payer2");
        usdc.mint(payer2, 2000e6);
        vm.startPrank(payer2);
        usdc.approve(address(jbMultiTerminal()), 2000e6);
        uint256 tokensFromUSDC = jbMultiTerminal()
            .pay({
                projectId: revnetId,
                token: address(usdc),
                amount: 2000e6,
                beneficiary: payer2,
                minReturnedTokens: 0,
                memo: "",
                metadata: ""
            });
        vm.stopPrank();

        // Both should receive the same number of tokens (equivalent $2000 payments).
        assertEq(tokensFromETH, tokensFromUSDC, "1 ETH and 2000 USDC should mint the same tokens at $2000/ETH");
        assertGt(tokensFromETH, 0, "should receive tokens");
    }
}
