// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";
import {JBCashOuts} from "@bananapus/core-v6/src/libraries/JBCashOuts.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {JBTriangularPriceFeed} from "@bananapus/core-v6/src/periphery/JBTriangularPriceFeed.sol";

// Suckers
import {IJBSucker} from "@bananapus/suckers-v6/src/interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerDeployer.sol";
import {JBSucker} from "@bananapus/suckers-v6/src/JBSucker.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";
import {JBTokenMapping} from "@bananapus/suckers-v6/src/structs/JBTokenMapping.sol";
import {JBMessageRoot} from "@bananapus/suckers-v6/src/structs/JBMessageRoot.sol";
import {JBInboxTreeRoot} from "@bananapus/suckers-v6/src/structs/JBInboxTreeRoot.sol";
import {JBPeerChainValue} from "@bananapus/suckers-v6/src/structs/JBPeerChainValue.sol";
import {JBOptimismSucker} from "@bananapus/suckers-v6/src/JBOptimismSucker.sol";
import {JBOptimismSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBOptimismSuckerDeployer.sol";
import {IOPMessenger} from "@bananapus/suckers-v6/src/interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "@bananapus/suckers-v6/src/interfaces/IOPStandardBridge.sol";

import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";

// Revnet
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";
import {MockERC20Token} from "../helpers/MockTokens.sol";
import {MockPriceFeed} from "../helpers/MockPriceFeed.sol";

/// @notice Mock Optimism messenger — drives `xDomainMessageSender` so a staged `fromRemote` looks like it came
/// from the registered peer sucker, and accepts `sendMessage` as a no-op.
contract SurplusMockOPMessenger {
    address public xDomainMessageSender;

    function setXDomainMessageSender(address sender) external {
        xDomainMessageSender = sender;
    }

    function sendMessage(address, bytes calldata, uint32) external payable {}
}

/// @notice Mock Optimism bridge — no-op for both ERC20 and ETH bridging so sucker deployment wiring succeeds.
contract SurplusMockOPBridge {
    function bridgeETHTo(address, uint32, bytes calldata) external payable {}

    function bridgeERC20To(address, address, address, uint256, uint32, bytes calldata) external {}
}

/// @notice Proves a USD-base, USDC-terminal revnet that aggregates a remote ETH-denominated surplus snapshot
/// values that snapshot through the ETH<->USDC triangular price feed, and that the cross-chain valuation path
/// silently under-prices (without reverting) when that feed is absent.
///
/// The remote snapshot is stored with its source currency set to the native-token currency (ETH). The data hook
/// and the loan contract read it back through `JBPrices`, which has no built-in triangulation — the ETH/USD and
/// USDC/USD legs are composed by a real `JBTriangularPriceFeed` registered for the exact pair the sucker queries.
contract USDCCrossChainSurplusForkTest is RevnetForkBase {
    // The native-token currency id the sucker stamps onto the stored remote surplus snapshot and then uses as the
    // `pricingCurrency` when it reads that snapshot back through `JBPrices`. This is the address-derived id, not the
    // standard ETH=1 id — the registered feed pair must match this exactly or the lookup silently resolves to zero.
    uint32 constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));

    // Round-number leg prices: 1 USDC is worth 1 USD, 1 ETH is worth 2000 USD.
    uint256 constant USD_PER_USDC = 1e6; // 6-decimal feed: 1 USDC -> 1 USD.
    uint256 constant USD_PER_ETH = 2000e18; // 18-decimal feed: 1 ETH -> 2000 USD.

    // The remote snapshot we inject: 10 ETH of surplus (18-decimal, ETH-denominated) backing 50k remote tokens.
    uint256 constant REMOTE_ETH_SURPLUS = 10 ether;
    uint256 constant REMOTE_TOTAL_SUPPLY = 50_000e18;

    // 10 ETH at $2000 = $20,000 = 20,000 USDC once triangulated into the USDC accounting currency.
    uint256 constant EXPECTED_REMOTE_USDC = 20_000e6;

    MockERC20Token usdc;
    uint32 usdcCurrency;

    SurplusMockOPMessenger internal mockMessenger;
    SurplusMockOPBridge internal mockBridge;
    JBOptimismSuckerDeployer internal opSuckerDeployer;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_USDCXChainSurplus";
    }

    function setUp() public override {
        super.setUp();
        require(block.chainid == 1, "fork must be on mainnet");

        // The buyback oracle lives at address(0); mock it so payments can run before any pool exists.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Fresh 6-decimal USDC and its address-derived accounting currency.
        usdc = new MockERC20Token("Mock USDC", "USDC", 6);
        usdcCurrency = uint32(uint160(address(usdc)));

        // The fee revnet must exist before any other revnet deploys (it receives cash-out fees).
        _deployFeeProject(0);

        // Stand up the Optimism sucker deployer against mocked bridge contracts so a sucker can be deployed and
        // registered for the revnet. Only registration + the stored snapshot matter here; no real bridging happens.
        mockMessenger = new SurplusMockOPMessenger();
        mockBridge = new SurplusMockOPBridge();

        opSuckerDeployer = new JBOptimismSuckerDeployer({
            directory: jbDirectory(),
            permissions: jbPermissions(),
            tokens: jbTokens(),
            configurator: address(this),
            trustedForwarder: address(0)
        });
        opSuckerDeployer.setChainSpecificConstants({
            messenger: IOPMessenger(address(mockMessenger)), bridge: IOPStandardBridge(address(mockBridge))
        });

        JBOptimismSucker singleton = new JBOptimismSucker({
            deployer: opSuckerDeployer,
            directory: jbDirectory(),
            permissions: jbPermissions(),
            prices: jbPrices(),
            tokens: jbTokens(),
            feeProjectId: FEE_PROJECT_ID,
            registry: SUCKER_REGISTRY,
            trustedForwarder: address(0)
        });
        opSuckerDeployer.configureSingleton(singleton);

        vm.prank(multisig());
        SUCKER_REGISTRY.allowSuckerDeployer(address(opSuckerDeployer));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Tests
    // ═══════════════════════════════════════════════════════════════════

    /// @notice With the triangular feed registered, the remote ETH surplus snapshot resolves to its USDC value and
    /// flows into both the loan capacity and the cash-out valuation alongside the local USDC surplus.
    function test_xchainSurplus_valuesRemoteLeg_withTriangularFeed() public {
        // Register the USDC/USD and ETH/USD legs plus the triangular feed that composes them.
        _registerLegFeeds();
        _registerTriangularFeed();

        // ── Assertion 1: the registered ETH<->USDC pair resolves to the triangulated rate.
        // ──────────────────
        // "ETH per 1 USDC" at 18 decimals = (1 USD/USDC) / (2000 USD/ETH) = 0.0005 ETH.
        uint256 ethPerUsdc = jbPrices()
            .pricePerUnitOf({projectId: 0, pricingCurrency: NATIVE_CURRENCY, unitCurrency: usdcCurrency, decimals: 18});
        assertApproxEqRel(ethPerUsdc, 0.0005e18, 0.001e18, "1 USDC should price at ~0.0005 ETH");

        // The inverse direction is auto-derived by JBPrices: "USDC per 1 ETH" at 6 decimals = 2000 USDC.
        uint256 usdcPerEth = jbPrices()
            .pricePerUnitOf({projectId: 0, pricingCurrency: usdcCurrency, unitCurrency: NATIVE_CURRENCY, decimals: 6});
        assertApproxEqRel(usdcPerEth, 2000e6, 0.001e18, "1 ETH should price at ~2000 USDC");

        // Deploy the USD-base, USDC-terminal revnet and a sucker, then stamp the remote ETH snapshot onto it.
        (uint256 revnetId, address sucker) = _deployUSDCRevnetWithSucker("XSURP_FEED");
        _stageRemoteSurplusSnapshot(sucker);

        // ── Assertion 2: the remote ETH surplus converts to its nonzero USDC value (the surgical probe).
        // ─────
        // This call is exactly zero when the feed does not resolve, so a nonzero result proves the feed is live.
        JBPeerChainValue memory peer =
            IJBSucker(sucker).peerChainSurplusValueOf({decimals: 6, currency: uint256(usdcCurrency)});
        assertApproxEqRel(peer.value, EXPECTED_REMOTE_USDC, 0.001e18, "remote 10 ETH should value at ~20,000 USDC");

        // The registry aggregate over all of the revnet's suckers must report the same converted surplus.
        uint256 registryRemote =
            SUCKER_REGISTRY.remoteSurplusOf({projectId: revnetId, decimals: 6, currency: uint256(usdcCurrency)});
        assertApproxEqRel(registryRemote, EXPECTED_REMOTE_USDC, 0.001e18, "registry remote surplus should match");

        // Pay USDC locally so the revnet has a real local surplus and a real local token supply to value against.
        // Paying ~20,000 USDC makes the local leg approximately equal to the ~20,000-USDC remote leg.
        _payUSDC(revnetId, PAYER, 20_000e6);
        uint256 localSurplus = _terminalBalance(revnetId, address(usdc));
        assertGt(localSurplus, 0, "local USDC surplus should be present");

        // ── Assertion 3: the loan capacity values BOTH the local USDC surplus and the remote ETH snapshot.
        // ───
        // Borrowing valuation runs the bonding curve over (effectiveSurplus, effectiveSupply) where the effective
        // figures fold in the remote leg. Reproduce that exact formula from the measured local state and the known
        // remote leg, and check the contract agrees.
        uint256 collateral = 1000e18; // A small slice of supply so the curve output stays below the local surplus.
        uint16 tax = 5000; // 50% cash-out tax — matches the revnet config below.

        uint256 localSupply = jbController().totalTokenSupplyWithReservedTokensOf(revnetId);
        uint256 effectiveSurplus = localSurplus + registryRemote;
        uint256 effectiveSupply = localSupply + SUCKER_REGISTRY.remoteTotalSupplyOf(revnetId);
        uint256 expectedCapacity = JBCashOuts.cashOutFrom({
            surplus: effectiveSurplus, cashOutCount: collateral, totalSupply: effectiveSupply, cashOutTaxRate: tax
        });

        (, uint256 borrowableCapacity) =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, collateral, 6, uint256(usdcCurrency));
        assertApproxEqRel(
            borrowableCapacity, expectedCapacity, 0.001e18, "loan capacity should value local + remote surplus"
        );

        // Cross-check that the remote leg actually moved the number: a purely local valuation (local surplus over
        // local supply, no remote terms at all) is a lower bound, and the cross-chain-aware capacity must exceed it.
        uint256 localOnlyCapacity = JBCashOuts.cashOutFrom({
            surplus: localSurplus, cashOutCount: collateral, totalSupply: localSupply, cashOutTaxRate: tax
        });
        assertGt(borrowableCapacity, localOnlyCapacity, "remote leg must increase the borrow capacity");

        emit log_named_uint("ETH per USDC (1e18)", ethPerUsdc);
        emit log_named_uint("USDC per ETH (1e6)", usdcPerEth);
        emit log_named_uint("registry remote surplus (USDC)", registryRemote);
        emit log_named_uint("local USDC surplus", localSurplus);
        emit log_named_uint("borrowable capacity (local+remote)", borrowableCapacity);
        emit log_named_uint("borrowable capacity (local only)", localOnlyCapacity);
    }

    /// @notice Negative control with identical setup but WITHOUT the triangular feed: the cross-chain path does not
    /// revert, the remote surplus silently resolves to zero, and the loan capacity drops to (roughly half of) the
    /// feed-present value because only the local leg remains.
    function test_xchainSurplus_underPricesSilently_withoutTriangularFeed() public {
        // Register only the leg feeds (the USDC/USD leg is needed for USDC payments to mint), but NOT the
        // triangular feed that composes them into an ETH<->USDC price.
        _registerLegFeeds();

        // The ETH<->USDC pair must be unresolvable so the conversion swallow path is exercised.
        vm.expectRevert();
        jbPrices()
            .pricePerUnitOf({projectId: 0, pricingCurrency: NATIVE_CURRENCY, unitCurrency: usdcCurrency, decimals: 18});

        (uint256 revnetId, address sucker) = _deployUSDCRevnetWithSucker("XSURP_NOFEED");
        _stageRemoteSurplusSnapshot(sucker);

        // The remote conversion is wrapped in try/catch, so the missing feed yields zero rather than a revert.
        JBPeerChainValue memory peer =
            IJBSucker(sucker).peerChainSurplusValueOf({decimals: 6, currency: uint256(usdcCurrency)});
        assertEq(peer.value, 0, "missing feed must swallow the remote surplus to zero");

        uint256 registryRemote =
            SUCKER_REGISTRY.remoteSurplusOf({projectId: revnetId, decimals: 6, currency: uint256(usdcCurrency)});
        assertEq(registryRemote, 0, "registry remote surplus must be zero without the feed");

        // Same local state as the positive case so the only difference is the (now-missing) remote leg. The local
        // leg (~20,000 USDC) is sized to approximately equal the ~20,000-USDC remote leg.
        _payUSDC(revnetId, PAYER, 20_000e6);
        uint256 localSurplus = _terminalBalance(revnetId, address(usdc));
        assertGt(localSurplus, 0, "local USDC surplus should still be present");

        uint256 collateral = 1000e18;
        uint16 tax = 5000;
        uint256 localSupply = jbController().totalTokenSupplyWithReservedTokensOf(revnetId);

        // The cross-chain path does not revert; it under-prices asymmetrically. The remote total supply needs no
        // price feed (it is a raw token count), so it STILL inflates the denominator, while the remote surplus
        // (which does need the missing feed) silently resolves to zero. The valuation therefore runs the bonding
        // curve over the LOCAL surplus spread across the LOCAL-PLUS-REMOTE supply — the defining under-pricing.
        uint256 remoteSupply = SUCKER_REGISTRY.remoteTotalSupplyOf(revnetId);
        (, uint256 borrowableCapacity) =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, collateral, 6, uint256(usdcCurrency));
        uint256 expectedUnderPriced = JBCashOuts.cashOutFrom({
            surplus: localSurplus,
            cashOutCount: collateral,
            totalSupply: localSupply + remoteSupply,
            cashOutTaxRate: tax
        });
        assertApproxEqRel(
            borrowableCapacity,
            expectedUnderPriced,
            0.001e18,
            "feed-absent capacity values only the local surplus over the full local+remote supply"
        );

        // ── The load-bearing comparison: register the feed in this same fork and show the capacity roughly
        // doubles once the remote leg (sized to ~equal the local leg) is valued.
        _registerTriangularFeed();
        // The stored snapshot already carries the surplus; the freshly-registered feed makes it resolve. Confirm.
        uint256 registryRemoteWithFeed =
            SUCKER_REGISTRY.remoteSurplusOf({projectId: revnetId, decimals: 6, currency: uint256(usdcCurrency)});
        assertApproxEqRel(
            registryRemoteWithFeed, EXPECTED_REMOTE_USDC, 0.001e18, "feed registration should revive the remote leg"
        );

        (, uint256 borrowableCapacityWithFeed) =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, collateral, 6, uint256(usdcCurrency));

        // The remote supply already sits in the denominator of both readings (it needs no feed), so registering the
        // feed only adds the remote surplus to the numerator. With the remote surplus (~20,000 USDC) sized to equal
        // the local surplus (~20,000 USDC), the feed-present capacity is therefore close to exactly twice the
        // feed-absent capacity — the curve's tax factor is identical between the two because the supply is unchanged.
        assertGt(borrowableCapacityWithFeed, borrowableCapacity, "feed-present capacity must exceed feed-absent");
        assertApproxEqRel(
            borrowableCapacityWithFeed,
            borrowableCapacity * 2,
            0.01e18,
            "feed-present capacity should be ~2x feed-absent when remote ~= local"
        );

        emit log_named_uint("capacity WITHOUT feed (under-priced)", borrowableCapacity);
        emit log_named_uint("capacity WITH feed (local + remote)", borrowableCapacityWithFeed);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Feed registration
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Register the two USD-pivot legs as project-0 defaults: USDC/USD and ETH/USD.
    /// @dev The USDC/USD leg also powers the USDC pay path (the revnet's base currency is USD), so it is registered
    /// in both the feed-present and feed-absent tests.
    function _registerLegFeeds() internal {
        // "1 USDC costs 1 USD" — the numerator leg of the triangle and the base-currency feed for USDC payments.
        MockPriceFeed usdcUsdFeed = new MockPriceFeed(USD_PER_USDC, 6);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, JBCurrencyIds.USD, usdcCurrency, IJBPriceFeed(address(usdcUsdFeed)));

        // "1 ETH costs 2000 USD" — the denominator leg of the triangle, keyed to the native-token currency so the
        // triangle's denominator lookup resolves against the same id the snapshot stamps onto its ETH surplus.
        MockPriceFeed ethUsdFeed = new MockPriceFeed(USD_PER_ETH, 18);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, JBCurrencyIds.USD, NATIVE_CURRENCY, IJBPriceFeed(address(ethUsdFeed)));
    }

    /// @notice Register the real triangular feed for the exact pair the sucker queries: pricing in the native-token
    /// (ETH) currency, per unit of the USDC accounting currency.
    /// @dev `convertPeerValue` calls `pricePerUnitOf(pricingCurrency = source.currency, unitCurrency = targetCurrency)`
    /// where `source.currency` is the snapshot's stamped native-token currency and `targetCurrency` is the USDC
    /// accounting currency. The pair registered here is therefore (NATIVE_CURRENCY, usdcCurrency). The triangular feed
    /// composes numerator (USD-per-USDC) over denominator (USD-per-ETH), yielding "ETH per 1 USDC".
    function _registerTriangularFeed() internal {
        IJBPriceFeed numerator = jbPrices().priceFeedFor(0, JBCurrencyIds.USD, usdcCurrency); // USD-per-USDC leg.
        IJBPriceFeed denominator = jbPrices().priceFeedFor(0, JBCurrencyIds.USD, NATIVE_CURRENCY); // USD-per-ETH leg.

        JBTriangularPriceFeed triangular = new JBTriangularPriceFeed(numerator, denominator);
        vm.prank(multisig());
        jbPrices().addPriceFeedFor(0, NATIVE_CURRENCY, usdcCurrency, IJBPriceFeed(address(triangular)));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Revnet + sucker deployment
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Deploy a USD-base, USDC-terminal revnet that aggregates cross-chain state, then deploy and register an
    /// Optimism sucker for it.
    function _deployUSDCRevnetWithSucker(bytes32 salt) internal returns (uint256 revnetId, address sucker) {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        // Token-keyed accounting currency for USDC; the data hook and loans read remote surplus in this currency.
        acc[0] = JBAccountingContext({token: address(usdc), decimals: 6, currency: usdcCurrency});

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
            cashOutTaxRate: 5000, // 50% tax — keeps the small-slice curve output well below the local surplus.
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("XSurplus", "XSURP", "ipfs://xsurp", salt),
            // USD base currency forces the remote ETH snapshot to be valued through the triangular feed rather than
            // matched directly to the USDC accounting currency.
            baseCurrency: JBCurrencyIds.USD,
            operator: multisig(),
            // Aggregate cross-chain state so the remote surplus snapshot enters cash-out and loan valuation.
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc =
            REVSuckerDeploymentConfig({deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: salt});

        (revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, accountingContextsToAccept: acc, suckerDeploymentConfiguration: sdc
        });

        sucker = _deployRevnetSucker(revnetId, salt);
    }

    /// @notice Deploy an Optimism sucker for the revnet via the registry, mapping the USDC terminal token.
    function _deployRevnetSucker(uint256 revnetId, bytes32 registrySalt) internal returns (address) {
        _grantPermissionFrom(address(REV_DEPLOYER), address(SUCKER_REGISTRY), revnetId, JBPermissionIds.DEPLOY_SUCKERS);
        _grantPermissionFrom(
            address(REV_DEPLOYER), address(SUCKER_REGISTRY), revnetId, JBPermissionIds.MAP_SUCKER_TOKEN
        );

        JBTokenMapping[] memory mappings = new JBTokenMapping[](1);
        // Map the local USDC token to a remote token. The mapping is irrelevant to the passive surplus snapshot read,
        // but the registry requires at least one mapping to deploy the sucker.
        mappings[0] = JBTokenMapping({
            localToken: address(usdc), minGas: 200_000, remoteToken: bytes32(uint256(uint160(address(usdc))))
        });

        JBSuckerDeployerConfig[] memory configs = new JBSuckerDeployerConfig[](1);
        configs[0] = JBSuckerDeployerConfig({
            deployer: IJBSuckerDeployer(address(opSuckerDeployer)), peer: bytes32(0), mappings: mappings
        });

        vm.prank(address(REV_DEPLOYER));
        address[] memory deployed = SUCKER_REGISTRY.deploySuckersFor(revnetId, registrySalt, configs);
        return deployed[0];
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Remote snapshot injection
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Stamp a remote, ETH-denominated surplus snapshot onto the sucker via `fromRemote`.
    /// @dev `fromRemote` stores `_peerChainSurplus = {value: sourceSurplus, currency: sourceCurrency, decimals}`,
    /// which `peerChainSurplusValueOf` later converts through `JBPrices`. The snapshot currency is the native-token
    /// (ETH) currency at 18 decimals, so its conversion to the USDC accounting currency needs the triangular feed.
    function _stageRemoteSurplusSnapshot(address sucker) internal {
        // The shared snapshot state only advances when the source freshness key strictly exceeds the stored one,
        // which starts at zero, so any nonzero timestamp is accepted.
        uint64 freshness = uint64(block.timestamp);

        // Spoof the cross-domain sender so the sucker accepts the message as coming from its peer.
        mockMessenger.setXDomainMessageSender(sucker);
        vm.prank(address(mockMessenger));
        JBSucker(payable(sucker))
            .fromRemote(
                JBMessageRoot({
                version: 1,
                // An unmapped/native token is fine: only the empty inbox tree is touched, no claim is made.
                token: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN))),
                amount: 0,
                // Empty remote root with nonce 1 — no leaves are claimed, only the shared snapshot is updated.
                remoteRoot: JBInboxTreeRoot({nonce: 1, root: bytes32(0)}),
                sourceTotalSupply: REMOTE_TOTAL_SUPPLY,
                // The remote surplus is ETH-denominated, stamped with the native-token currency id.
                sourceCurrency: NATIVE_CURRENCY,
                sourceDecimals: 18,
                sourceSurplus: REMOTE_ETH_SURPLUS,
                sourceBalance: REMOTE_ETH_SURPLUS,
                sourceTimestamp: freshness
            })
            );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Shared helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Pay the revnet with USDC: mint to the payer, approve the terminal, and pay.
    function _payUSDC(uint256 revnetId, address payer, uint256 amount) internal returns (uint256 tokensReceived) {
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

    /// @notice Grant a single permission from `from` to `operator` on `projectId`.
    function _grantPermissionFrom(address from, address operator, uint256 projectId, uint8 permissionId) internal {
        uint8[] memory ids = new uint8[](1);
        ids[0] = permissionId;
        vm.prank(from);
        jbPermissions()
            .setPermissionsFor(
                from,
                // forge-lint: disable-next-line(unsafe-typecast)
                JBPermissionsData({operator: operator, projectId: uint64(projectId), permissionIds: ids})
            );
    }
}
