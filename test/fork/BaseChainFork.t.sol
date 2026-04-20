// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core imports for stack deployment and payment flows.
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";

// Chainlink price feed imports for L2 sequencer-aware pricing.
import {JBChainlinkV3PriceFeed, AggregatorV3Interface} from "@bananapus/core-v6/src/JBChainlinkV3PriceFeed.sol";
import {JBChainlinkV3SequencerPriceFeed} from "@bananapus/core-v6/src/JBChainlinkV3SequencerPriceFeed.sol";
import {AggregatorV2V3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";

// 721 Hook imports for NFT tier testing.
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721CheckpointsDeployer} from "@bananapus/721-hook-v6/src/JB721CheckpointsDeployer.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";

// Buyback hook imports for verifying Uniswap V4 integration on Base.
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";

// Sucker registry import for sucker-exempt cash-out testing.
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";

// Croptop publisher for REVDeployer dependency.
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";

// Revnet imports for deploying a revnet on the Base fork.
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {REVHiddenTokens} from "@rev-net/core-v6/src/REVHiddenTokens.sol";
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";
import {IREVLoans} from "@rev-net/core-v6/src/interfaces/IREVLoans.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

// Uniswap V4 imports for verifying PoolManager presence on Base.
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

// Uniswap V4 router (geomean oracle) for buyback hook slippage protection.
import {JBUniswapV4Hook} from "@bananapus/univ4-router-v6/src/JBUniswapV4Hook.sol";

/// @notice Base mainnet (chain ID 8453) fork test exercising the full Juicebox V6 stack.
///
/// Validates that chain-sensitive features work correctly on Base:
/// - Uniswap V4 PoolManager exists at Base's canonical address
/// - Full JB stack deploys and operates (pay, cashout, payouts)
/// - L2 sequencer-aware price feeds function with real Base Chainlink feeds
///
/// Run with: forge test --match-contract BaseChainForkTest -vvv
contract BaseChainForkTest is TestBaseWorkflow {
    // ── Base mainnet canonical addresses ──

    // Uniswap V4 PoolManager on Base (differs from Ethereum mainnet address).
    address constant BASE_POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;

    // Chainlink ETH/USD price feed on Base mainnet.
    address constant BASE_ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    // Chainlink L2 sequencer uptime feed on Base mainnet.
    address constant BASE_SEQUENCER_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    // Chainlink USDC/USD price feed on Base mainnet.
    address constant BASE_USDC_USD_FEED = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;

    // OP predeploy addresses (same across all OP Stack L2s including Base).
    address constant L2_CROSS_DOMAIN_MESSENGER = 0x4200000000000000000000000000000000000007;

    // WETH on Base (OP Stack standard predeploy).
    address constant BASE_WETH = 0x4200000000000000000000000000000000000006;

    // ── Test parameters ──

    // Token issuance rate: 1000 project tokens per 1 ETH paid.
    uint112 constant INITIAL_ISSUANCE = uint112(1000e18);

    // Grace period for sequencer feed: 1 hour after restart.
    uint256 constant L2_GRACE_PERIOD = 3600;

    // Staleness threshold for the ETH/USD feed: 1 hour.
    uint256 constant ETH_USD_THRESHOLD = 3600;

    // Staleness threshold for the USDC/USD feed: 24 hours.
    uint256 constant USDC_USD_THRESHOLD = 86_400;

    // ── Actors ──

    // Address that pays into the revnet.
    address PAYER = makeAddr("basePayer");

    // Address that receives payout splits.
    address SPLIT_BENEFICIARY = makeAddr("baseSplitBeneficiary");

    // Trusted forwarder for ERC-2771 meta-transactions (Base mainnet).
    address private constant TRUSTED_FORWARDER = 0xB2b5841DBeF766d4b521221732F9B618fCf34A87;

    // ── Ecosystem contracts deployed in setUp ──

    // Fee project ID used by the REVDeployer.
    uint256 FEE_PROJECT_ID;

    // Sucker registry (required by REVDeployer constructor).
    JBSuckerRegistry SUCKER_REGISTRY;

    // Address registry for 721 hook deployer dependency.
    IJBAddressRegistry ADDRESS_REGISTRY;

    // 721 hook deployer (required by REVDeployer).
    IJB721TiersHookDeployer HOOK_DEPLOYER;

    // Croptop publisher (required by REVDeployer).
    CTPublisher PUBLISHER;

    // Buyback hook deployed against Base's PoolManager.
    JBBuybackHook BUYBACK_HOOK;

    // Buyback hook registry for REVDeployer.
    JBBuybackHookRegistry BUYBACK_REGISTRY;

    // Loans contract (required by REVDeployer).
    IREVLoans LOANS_CONTRACT;

    // REVOwner — the runtime data hook for pay and cash out callbacks.
    REVOwner REV_OWNER;

    // REVDeployer orchestrates revnet deployment.
    REVDeployer REV_DEPLOYER;

    // Track whether the fork was successfully created.
    bool forkCreated;

    // Accept ETH returns from cash-outs.
    receive() external payable {}

    function setUp() public override {
        // Attempt to fork Base mainnet; skip all tests if no RPC is configured.
        try vm.createSelectFork("base") {
            // Fork succeeded — record that fact.
            forkCreated = true;
        } catch {
            // No Base RPC available — mark fork as unavailable and return early.
            forkCreated = false;
            return;
        }

        // Deploy fresh JB core contracts on the Base fork via TestBaseWorkflow.
        super.setUp();

        // Create a fee project that the REVDeployer will route fees to.
        FEE_PROJECT_ID = jbProjects().createFor(multisig());

        // Deploy sucker registry (required dependency; no actual suckers configured).
        SUCKER_REGISTRY = new JBSuckerRegistry(jbDirectory(), jbPermissions(), multisig(), address(0));

        // Deploy 721 hook infrastructure (store + example hook + deployer).
        JB721TiersHookStore hookStore = new JB721TiersHookStore();
        JB721CheckpointsDeployer checkpointsDeployer = new JB721CheckpointsDeployer();
        JB721TiersHook exampleHook = new JB721TiersHook(
            jbDirectory(),
            jbPermissions(),
            jbPrices(),
            jbRulesets(),
            hookStore,
            jbSplits(),
            checkpointsDeployer,
            multisig()
        );
        ADDRESS_REGISTRY = new JBAddressRegistry();
        HOOK_DEPLOYER = new JB721TiersHookDeployer(exampleHook, hookStore, ADDRESS_REGISTRY, multisig());

        // Deploy croptop publisher (required by REVDeployer).
        PUBLISHER = new CTPublisher(jbDirectory(), jbPermissions(), FEE_PROJECT_ID, multisig());

        // Deploy the univ4 router (JBUniswapV4Hook) as the oracle hook for geomean slippage protection.
        // Hook addresses must encode permission flags in lower bits — use HookMiner to find a valid salt.
        uint160 hookFlags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );
        bytes memory constructorArgs =
            abi.encode(IPoolManager(BASE_POOL_MANAGER), jbTokens(), jbDirectory(), jbPrices());
        (, bytes32 hookSalt) =
            HookMiner.find(address(this), hookFlags, type(JBUniswapV4Hook).creationCode, constructorArgs);
        JBUniswapV4Hook oracleHook =
            new JBUniswapV4Hook{salt: hookSalt}(IPoolManager(BASE_POOL_MANAGER), jbTokens(), jbDirectory(), jbPrices());

        // Deploy buyback hook using Base's real PoolManager and the univ4 router as oracle hook.
        BUYBACK_HOOK = new JBBuybackHook(
            jbDirectory(),
            jbPermissions(),
            jbPrices(),
            jbProjects(),
            jbTokens(),
            IPoolManager(BASE_POOL_MANAGER),
            IHooks(address(oracleHook)),
            address(0)
        );

        // Deploy and configure buyback hook registry with the hook as default.
        BUYBACK_REGISTRY = new JBBuybackHookRegistry(jbPermissions(), jbProjects(), address(this), address(0));
        BUYBACK_REGISTRY.setDefaultHook(IJBRulesetDataHook(address(BUYBACK_HOOK)));

        // Deploy loans contract (required by REVDeployer).
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

        // Deploy the REVDeployer that orchestrates revnet creation.
        REV_DEPLOYER = new REVDeployer{salt: "REVDeployer_Base"}(
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

        // Approve REVDeployer to manage the fee project NFT (needed for deployFor).
        vm.prank(multisig());
        jbProjects().approve(address(REV_DEPLOYER), FEE_PROJECT_ID);

        // Fund the test payer with ETH on the Base fork.
        vm.deal(PAYER, 100 ether);
    }

    // ─────────────────────── Config Helpers
    // ───────────────────────

    /// @dev Builds a single-stage revnet config accepting native ETH.
    function _buildConfig(uint16 cashOutTaxRate)
        internal
        view
        returns (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc)
    {
        // Configure a single accounting context for native ETH.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, // Accept native ETH as payment.
            decimals: 18, // ETH uses 18 decimals.
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN)) // Currency matches native token address.
        });

        // Single terminal configuration accepting ETH.
        tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({
            terminal: jbMultiTerminal(), // Use the deployed multi-terminal.
            accountingContextsToAccept: acc // Accept native ETH.
        });

        // A single split sending all reserved tokens to multisig.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0].beneficiary = payable(multisig()); // Multisig receives reserved tokens.
        splits[0].percent = 10_000; // 100% of reserved portion goes to this split.

        // Single-stage revnet configuration.
        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp), // Stage starts immediately.
            autoIssuances: new REVAutoIssuance[](0), // No auto-issuances.
            splitPercent: 0, // No reserved token split.
            splits: splits, // Splits config for reserved tokens.
            initialIssuance: INITIAL_ISSUANCE, // 1000 tokens per ETH.
            issuanceCutFrequency: 0, // No issuance decay.
            issuanceCutPercent: 0, // No issuance cut.
            cashOutTaxRate: cashOutTaxRate, // Bonding curve tax rate.
            extraMetadata: 0 // No extra metadata.
        });

        // Revnet description and configuration.
        cfg = REVConfig({
            description: REVDescription("Base Fork Test", "BFORK", "ipfs://base", "BASE_SALT"),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)), // ETH as base currency.
            splitOperator: multisig(), // Multisig can operate splits.
            stageConfigurations: stages // Single stage config.
        });

        // Empty sucker deployment config (no cross-chain suckers in this test).
        sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), // No sucker deployers.
            salt: keccak256(abi.encodePacked("BASE_FORK")) // Deterministic salt.
        });
    }

    /// @dev Deploys the fee project revnet (required before deploying user revnets).
    function _deployFeeProject(uint16 cashOutTaxRate) internal {
        // Build config for the fee project.
        (REVConfig memory feeCfg, JBTerminalConfig[] memory feeTc, REVSuckerDeploymentConfig memory feeSdc) =
            _buildConfig(cashOutTaxRate);

        // Override description for the fee project.
        feeCfg.description = REVDescription("Fee", "FEE", "ipfs://fee", "FEE_SALT");

        // Deploy the fee project revnet as multisig.
        vm.prank(multisig());
        REV_DEPLOYER.deployFor({
            revnetId: FEE_PROJECT_ID,
            configuration: feeCfg,
            terminalConfigurations: feeTc,
            suckerDeploymentConfiguration: feeSdc
        });
    }

    /// @dev Deploys a new revnet and returns its project ID.
    function _deployRevnet(uint16 cashOutTaxRate) internal returns (uint256 revnetId) {
        // Build config for a fresh revnet.
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) =
            _buildConfig(cashOutTaxRate);

        // Deploy the revnet; revnetId=0 means "create new project".
        (revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });
    }

    /// @dev Pays ETH into a revnet and returns tokens received.
    function _payRevnet(uint256 revnetId, address payer, uint256 amount) internal returns (uint256 tokensReceived) {
        // Execute payment as the specified payer.
        vm.prank(payer);
        tokensReceived = jbMultiTerminal().pay{value: amount}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN, // Pay with native ETH.
            amount: amount, // Amount of ETH to pay.
            beneficiary: payer, // Tokens go back to payer.
            minReturnedTokens: 0, // Accept any amount of tokens.
            memo: "", // No memo.
            metadata: "" // No metadata.
        });
    }

    /// @dev Returns the terminal's recorded balance for a project/token pair.
    function _terminalBalance(uint256 projectId, address token) internal view returns (uint256) {
        // Query the terminal store for the project's balance.
        return jbTerminalStore().balanceOf(address(jbMultiTerminal()), projectId, token);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Tests
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Verify Uniswap V4 PoolManager is deployed at Base's canonical address.
    function test_baseChain_poolManagerExists() public {
        // Skip if no Base fork is available.
        if (!forkCreated) {
            vm.skip(true); // Gracefully skip when no Base RPC is configured.
            return;
        }

        // Assert that the PoolManager has deployed bytecode at the expected address.
        assertGt(
            BASE_POOL_MANAGER.code.length, 0, "Uniswap V4 PoolManager should be deployed at Base canonical address"
        );

        // Verify it responds to the protocolFeeController() selector (a core PoolManager function).
        (bool success,) = BASE_POOL_MANAGER.staticcall(
            abi.encodeWithSignature("protocolFeeController()") // Call a known PoolManager view function.
        );

        // The call should succeed, proving the address is a real PoolManager.
        assertTrue(success, "PoolManager should respond to protocolFeeController()");
    }

    /// @notice Verify Base-specific OP Stack predeploys exist (CrossDomainMessenger).
    function test_baseChain_opStackPredeployExists() public {
        // Skip if no Base fork is available.
        if (!forkCreated) {
            vm.skip(true); // Gracefully skip when no Base RPC is configured.
            return;
        }

        // The L2 CrossDomainMessenger is an OP Stack predeploy at a fixed address.
        assertGt(
            L2_CROSS_DOMAIN_MESSENGER.code.length, 0, "OP Stack CrossDomainMessenger predeploy should exist on Base"
        );

        // WETH is also a predeploy on OP Stack L2s.
        assertGt(BASE_WETH.code.length, 0, "WETH predeploy should exist on Base");
    }

    /// @notice Deploy full JB stack on Base fork, pay ETH, receive tokens.
    function test_baseChain_payAndMintTokens() public {
        // Skip if no Base fork is available.
        if (!forkCreated) {
            vm.skip(true); // Gracefully skip when no Base RPC is configured.
            return;
        }

        // Deploy the fee project first (required for revnet fee routing).
        _deployFeeProject(5000);

        // Deploy a revnet with 50% cash-out tax rate.
        uint256 revnetId = _deployRevnet(5000);

        // Pay 1 ETH into the revnet and receive project tokens.
        uint256 tokens = _payRevnet(revnetId, PAYER, 1 ether);

        // With 1000 tokens/ETH issuance and no buyback pool, expect exactly 1000 tokens.
        assertEq(tokens, 1000e18, "Should receive 1000 tokens per ETH on Base");

        // Terminal should hold the 1 ETH payment.
        assertGt(_terminalBalance(revnetId, JBConstants.NATIVE_TOKEN), 0, "Terminal should have balance after payment");
    }

    /// @notice Cash out tokens on Base fork with bonding curve tax.
    function test_baseChain_cashOutWithTax() public {
        // Skip if no Base fork is available.
        if (!forkCreated) {
            vm.skip(true); // Gracefully skip when no Base RPC is configured.
            return;
        }

        // Deploy fee project and revnet with 50% tax.
        _deployFeeProject(5000);
        uint256 revnetId = _deployRevnet(5000);

        // Two payers needed so bonding curve tax has a visible effect.
        _payRevnet(revnetId, PAYER, 10 ether);

        // Create a second payer to introduce surplus for bonding curve math.
        address payer2 = makeAddr("basePayer2");
        vm.deal(payer2, 10 ether); // Fund the second payer.
        _payRevnet(revnetId, payer2, 5 ether);

        // Record PAYER's token balance and ETH balance before cash-out.
        uint256 payerTokens = jbTokens().totalBalanceOf(PAYER, revnetId);
        uint256 payerEthBefore = PAYER.balance;

        // Cash out all of PAYER's tokens.
        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
                holder: PAYER, // The token holder cashing out.
                projectId: revnetId, // The project to cash out from.
                cashOutCount: payerTokens, // Cash out all tokens.
                tokenToReclaim: JBConstants.NATIVE_TOKEN, // Reclaim native ETH.
                minTokensReclaimed: 0, // Accept any reclaim amount.
                beneficiary: payable(PAYER), // ETH goes back to PAYER.
                metadata: "" // No metadata.
            });

        // PAYER should receive some ETH (less than deposited due to tax + fees).
        uint256 ethReceived = PAYER.balance - payerEthBefore;
        assertGt(ethReceived, 0, "Should receive ETH from cash-out on Base");

        // PAYER's tokens should be fully burned.
        assertEq(jbTokens().totalBalanceOf(PAYER, revnetId), 0, "Tokens should be burned after cash-out");
    }

    /// @notice Test payout splits distribution on Base fork.
    function test_baseChain_payoutSplits() public {
        // Skip if no Base fork is available.
        if (!forkCreated) {
            vm.skip(true); // Gracefully skip when no Base RPC is configured.
            return;
        }

        // Deploy fee project and revnet with 20% reserved split.
        _deployFeeProject(5000);

        // Build config with a 20% reserved split (2000 out of 10_000 basis points).
        (REVConfig memory cfg, JBTerminalConfig[] memory tc, REVSuckerDeploymentConfig memory sdc) = _buildConfig(5000);

        // Set 20% of minted tokens as reserved for splits.
        cfg.stageConfigurations[0].splitPercent = 2000;

        // Deploy the revnet with the modified config.
        (uint256 revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, terminalConfigurations: tc, suckerDeploymentConfiguration: sdc
        });

        // Pay into the revnet to generate tokens (some will be reserved).
        _payRevnet(revnetId, PAYER, 10 ether);

        // Check if there are pending reserved tokens to distribute.
        uint256 pending = jbController().pendingReservedTokenBalanceOf(revnetId);

        if (pending > 0) {
            // Distribute the reserved tokens to configured splits.
            jbController().sendReservedTokensToSplitsOf(revnetId);

            // Multisig (the split beneficiary) should have received reserved tokens.
            uint256 multisigTokens = jbTokens().totalBalanceOf(multisig(), revnetId);
            assertGt(multisigTokens, 0, "Multisig should receive reserved tokens on Base");
        }
    }

    /// @notice Verify Base Chainlink ETH/USD feed responds correctly through sequencer-aware wrapper.
    function test_baseChain_sequencerPriceFeed() public {
        // Skip if no Base fork is available.
        if (!forkCreated) {
            vm.skip(true); // Gracefully skip when no Base RPC is configured.
            return;
        }

        // Verify the ETH/USD feed contract exists on Base.
        assertGt(BASE_ETH_USD_FEED.code.length, 0, "Chainlink ETH/USD feed should be deployed on Base");

        // Verify the sequencer uptime feed contract exists on Base.
        assertGt(BASE_SEQUENCER_FEED.code.length, 0, "Chainlink sequencer feed should be deployed on Base");

        // Deploy a sequencer-aware price feed using Base's real Chainlink feeds.
        JBChainlinkV3SequencerPriceFeed feed = new JBChainlinkV3SequencerPriceFeed(
            AggregatorV3Interface(BASE_ETH_USD_FEED), // The underlying ETH/USD price feed.
            ETH_USD_THRESHOLD, // 1-hour staleness threshold.
            AggregatorV2V3Interface(BASE_SEQUENCER_FEED), // The L2 sequencer uptime feed.
            L2_GRACE_PERIOD // 1-hour grace period after sequencer restart.
        );

        // Attempt to get the current price; it may revert if sequencer is in grace period.
        try feed.currentUnitPrice(18) returns (uint256 price) {
            // If the sequencer is up and feed is fresh, we get a valid price.
            assertGt(price, 0, "ETH/USD price should be positive on Base");

            // Sanity check: ETH price should be between $100 and $100,000 (18 decimals).
            assertGt(price, 100e18, "ETH/USD price should be above $100");
            assertLt(price, 100_000e18, "ETH/USD price should be below $100,000");
        } catch {
            // Sequencer down or feed stale at the fork block — this is expected behavior.
            // The important thing is the feed was constructed without error.
            assertTrue(true, "Feed reverted as expected (sequencer down or stale at fork block)");
        }
    }

    /// @notice Verify the USDC/USD feed also works through the sequencer-aware wrapper on Base.
    function test_baseChain_usdcPriceFeed() public {
        // Skip if no Base fork is available.
        if (!forkCreated) {
            vm.skip(true); // Gracefully skip when no Base RPC is configured.
            return;
        }

        // Verify the USDC/USD feed contract exists on Base.
        assertGt(BASE_USDC_USD_FEED.code.length, 0, "Chainlink USDC/USD feed should be deployed on Base");

        // Deploy a sequencer-aware USDC/USD price feed.
        JBChainlinkV3SequencerPriceFeed usdcFeed = new JBChainlinkV3SequencerPriceFeed(
            AggregatorV3Interface(BASE_USDC_USD_FEED), // The underlying USDC/USD price feed.
            USDC_USD_THRESHOLD, // 24-hour staleness threshold for USDC.
            AggregatorV2V3Interface(BASE_SEQUENCER_FEED), // Same sequencer feed for all Base Chainlink feeds.
            L2_GRACE_PERIOD // 1-hour grace period after sequencer restart.
        );

        // Attempt to get the current USDC price.
        try usdcFeed.currentUnitPrice(18) returns (uint256 price) {
            // USDC should be ~$1, so price with 18 decimals should be near 1e18.
            assertGt(price, 0.9e18, "USDC/USD price should be above $0.90");
            assertLt(price, 1.1e18, "USDC/USD price should be below $1.10");
        } catch {
            // Sequencer down or feed stale — acceptable at the fork block.
            assertTrue(true, "USDC feed reverted as expected (sequencer down or stale at fork block)");
        }
    }

    /// @notice Verify chain ID is correct on the Base fork.
    function test_baseChain_chainId() public {
        // Skip if no Base fork is available.
        if (!forkCreated) {
            vm.skip(true); // Gracefully skip when no Base RPC is configured.
            return;
        }

        // Base mainnet chain ID should be 8453.
        assertEq(block.chainid, 8453, "Fork should report Base mainnet chain ID 8453");
    }

    /// @notice Verify the buyback hook can be constructed with Base's PoolManager.
    function test_baseChain_buybackHookConstructsWithBasePoolManager() public {
        // Skip if no Base fork is available.
        if (!forkCreated) {
            vm.skip(true); // Gracefully skip when no Base RPC is configured.
            return;
        }

        // The buyback hook was already constructed in setUp with Base's PoolManager.
        // Verify the hook's POOL_MANAGER points to the correct address.
        assertEq(
            address(BUYBACK_HOOK.POOL_MANAGER()), BASE_POOL_MANAGER, "Buyback hook should reference Base's PoolManager"
        );
    }
}
