// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {JBPrices} from "@bananapus/core-v6/src/JBPrices.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";
import {JBRatioPriceFeed} from "@bananapus/core-v6/src/periphery/JBRatioPriceFeed.sol";

import {BuybackFloorFixBase} from "../../script/DeployBuybackFloorFix.s.sol";
import {JBChainTokens} from "../../script/libraries/JBChainTokens.sol";
import {MockPriceFeed} from "../helpers/MockPriceFeed.sol";

/// @notice Exposes the deploy script's own price-feed step so the registration direction is asserted against the
/// code that will actually run, not a restatement of it.
contract BuybackFloorFixFeedHarness is BuybackFloorFixBase {
    function usePrices(IJBPrices prices) external {
        _prices = prices;
    }

    /// @dev The harness owns `JBPrices`, so seeding the launch-time defaults has to route through it.
    function seedDefaultFeed(uint256 pricingCurrency, uint256 unitCurrency, IJBPriceFeed feed) external {
        _prices.addPriceFeedFor({
            projectId: _DEFAULT_PROJECT_ID, pricingCurrency: pricingCurrency, unitCurrency: unitCurrency, feed: feed
        });
    }

    function ensureFeeds() external returns (address) {
        return _ensureUsdcPerNativeDefaultFeeds();
    }
}

/// @notice Stand-in for the canonical deterministic CREATE2 factory, which does not exist on a bare test EVM. Takes a
/// 32-byte salt followed by init code and returns the deployed address, exactly as the real factory does, so
/// `_deployPrecompiledIfNeeded` and its address prediction both behave as they will on chain.
contract Create2FactoryStub {
    fallback() external payable {
        assembly {
            let size := sub(calldatasize(), 32)
            let ptr := mload(0x40)
            calldatacopy(ptr, 32, size)
            let deployed := create2(callvalue(), ptr, size, calldataload(0))
            if iszero(deployed) { revert(0, 0) }
            mstore(0, deployed)
            return(12, 20)
        }
    }
}

/// @notice Proves `DeployBuybackFloorFix` composes and registers its USDC↔NATIVE ratio feed in the direction its
/// consumers query, so every lookup lands on the direct feed rather than `JBPrices._priceFromInverse`.
/// @dev The direction is not cosmetic. `JBPrices` resolves a pair by trying the direct feed list and then the
/// opposite-direction list, and the inverse path quotes the stored feed at the CALLER's decimals BEFORE inverting it.
/// Both consumers put the paid or held token's currency on the pricing side — a pay reads
/// `pricePerUnitOf(pricing: amount.currency, unit: ruleset.baseCurrency(), decimals: amount.decimals)` and a cash out
/// reads `pricePerUnitOf(pricing: accountingContext.currency, unit: targetCurrency, decimals: 18)` — so with USDC as
/// that token, a feed registered as {NATIVE←uint32(usdc)} is only ever reached inverted. A USDC pay passes 6 decimals
/// there, and a sub-unit NATIVE-per-USDC price quantizes to three significant figures, permanently shorting every
/// USDC payer by ~0.16%. Registering {uint32(usdc)←NATIVE} keeps the large number on the quoted side. Nothing else
/// in the suite exercises this: the deploy's price step needs a live `JBPrices` with the launch defaults already in
/// it, which the fork tests build from scratch and never register these pairs on.
contract BuybackFloorFixPriceFeedDirectionTest is Test {
    /// @notice Ethereum mainnet's two live 8-decimal Chainlink legs, as read at block 22,000,000: 0.99987 USD per
    /// USDC and 2151.53445084 USD per NATIVE. Real answers rather than round numbers, because the defect is a
    /// quantization artifact that round numbers hide.
    uint256 internal constant _USDC_USD_ANSWER = 99_987_000;
    uint256 internal constant _ETH_USD_ANSWER = 215_153_445_084;
    uint8 internal constant _FEED_DECIMALS = 8;

    /// @notice What the outgoing {NATIVE←uint32(usdc)} registration produced for a USDC pay: the feed floors
    /// 0.000464724… to `464` at the payer's 6 decimals, and `mulDiv(1e6, 1e6, 464)` lands here — 0.156% high.
    uint256 internal constant _INVERSE_PATH_PAY_PRICE = 2_155_172_413;

    address internal constant _CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    BuybackFloorFixFeedHarness internal _harness;
    JBPrices internal _prices;
    IJBPriceFeed internal _ethUsdFeed;
    IJBPriceFeed internal _usdcUsdFeed;

    uint32 internal _nativeCurrency;
    uint32 internal _usdcCurrency;

    function setUp() public {
        // The script's USDC table is keyed by chain, so the harness has to believe it is on one of them.
        vm.chainId(1);

        _nativeCurrency = JBChainTokens.currencyIdOf(JBConstants.NATIVE_TOKEN);
        _usdcCurrency = JBChainTokens.currencyIdOf(JBChainTokens.usdcTokenFor(1));

        _harness = new BuybackFloorFixFeedHarness();

        // Only the project-0 owner path is exercised, so the controller-facing dependencies are unused.
        _prices = new JBPrices({
            directory: IJBDirectory(address(0)),
            permissions: IJBPermissions(address(0)),
            projects: IJBProjects(address(0)),
            owner: address(_harness),
            trustedForwarder: address(0)
        });
        _harness.usePrices(_prices);

        // The two launch-time defaults the script reads its constructor arguments back out of.
        _ethUsdFeed = new MockPriceFeed(_ETH_USD_ANSWER, _FEED_DECIMALS);
        _usdcUsdFeed = new MockPriceFeed(_USDC_USD_ANSWER, _FEED_DECIMALS);
        _harness.seedDefaultFeed(JBCurrencyIds.USD, _nativeCurrency, _ethUsdFeed);
        _harness.seedDefaultFeed(JBCurrencyIds.USD, _usdcCurrency, _usdcUsdFeed);

        vm.etch(_CREATE2_FACTORY, address(new Create2FactoryStub()).code);
    }

    /// @notice The composed feed quotes USDC per NATIVE, and both registrations put the USDC currency on the pricing
    /// side so the direct lookup is the one that hits.
    function test_registersUsdcAsThePricingSide() public {
        address feed = _deployFeed();

        // Argument order is the direction: numerator over denominator cancels USD and leaves USDC per NATIVE.
        assertEq(address(JBRatioPriceFeed(feed).NUMERATOR()), address(_ethUsdFeed), "numerator must be the ETH/USD leg");
        assertEq(
            address(JBRatioPriceFeed(feed).DENOMINATOR()), address(_usdcUsdFeed), "denominator must be the USDC/USD leg"
        );

        assertEq(address(_prices.priceFeedFor(0, _usdcCurrency, _nativeCurrency)), feed, "{usdc<-NATIVE} unregistered");
        assertEq(address(_prices.priceFeedFor(0, _usdcCurrency, JBCurrencyIds.ETH)), feed, "{usdc<-ETH} unregistered");

        // The opposite direction must stay empty: a feed there would be reachable only through the inverse path.
        assertEq(address(_prices.priceFeedFor(0, _nativeCurrency, _usdcCurrency)), address(0), "{NATIVE<-usdc} written");
        assertEq(address(_prices.priceFeedFor(0, JBCurrencyIds.ETH, _usdcCurrency)), address(0), "{ETH<-usdc} written");
    }

    /// @notice A USDC pay under an ETH or NATIVE base currency resolves at full feed precision.
    function test_usdcPayWeightRatioKeepsFullPrecision() public {
        _deployFeed();

        // Exactly what the legs support at 6 decimals, derived here rather than copied from the feed's own math.
        uint256 exact = (_ETH_USD_ANSWER * 1e6) / _USDC_USD_ANSWER;

        for (uint256 i; i < 2; i++) {
            uint256 baseCurrency = i == 0 ? JBCurrencyIds.ETH : _nativeCurrency;
            uint256 weightRatio = _prices.pricePerUnitOf({
                projectId: 1, pricingCurrency: _usdcCurrency, unitCurrency: baseCurrency, decimals: 6
            });

            assertEq(weightRatio, exact, "USDC pay must resolve at full precision");
            assertTrue(weightRatio != _INVERSE_PATH_PAY_PRICE, "USDC pay fell back to the inverse path");
            // 1e18 is 100%, so this rejects anything above 1e-7% — three orders of magnitude tighter than the
            // 0.156% the inverse path introduced.
            assertApproxEqRel(weightRatio, exact, 1e9, "USDC pay drifted from the legs");
        }
    }

    /// @notice Cash outs quote at 18 decimals, where the surviving inverse leg costs nothing measurable.
    function test_cashOutConversionsStayExactInBothDirections() public {
        _deployFeed();

        // A USDC accounting context measured against a NATIVE target is now the direct hit.
        uint256 usdcContext = _prices.pricePerUnitOf({
            projectId: 1, pricingCurrency: _usdcCurrency, unitCurrency: _nativeCurrency, decimals: 18
        });
        assertEq(usdcContext, (_ETH_USD_ANSWER * 1e18) / _USDC_USD_ANSWER, "USDC context conversion is not direct");

        // A NATIVE accounting context measured against a USDC target is the one that still inverts. At 18 decimals it
        // reproduces the naive quotient bit for bit, so the flip costs the cash-out path nothing.
        uint256 nativeContext = _prices.pricePerUnitOf({
            projectId: 1, pricingCurrency: _nativeCurrency, unitCurrency: _usdcCurrency, decimals: 18
        });
        assertEq(nativeContext, (_USDC_USD_ANSWER * 1e18) / _ETH_USD_ANSWER, "NATIVE context conversion lost precision");
    }

    /// @notice Runs the script's own price-feed step, skipping when the canonical artifacts have not been built.
    function _deployFeed() internal returns (address feed) {
        // Same rationale as `DeployArtifactCompletenessGap`: a bare `forge test` with no prior `npm run artifacts` has
        // nothing to load, so skip rather than report a false failure.
        if (!vm.exists("artifacts/JBRatioPriceFeed.json")) {
            vm.skip(true);
            return address(0);
        }

        feed = _harness.ensureFeeds();
        assertTrue(feed != address(0), "expected the ratio feed to be deployed");
    }
}
