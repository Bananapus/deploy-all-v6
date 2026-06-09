// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {JBChainlinkV3PriceFeed} from "@bananapus/core-v6/src/JBChainlinkV3PriceFeed.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";
import {JBPrices} from "@bananapus/core-v6/src/JBPrices.sol";

contract OracleVerifierGapTest is Test {
    address internal constant MAINNET_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant MAINNET_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant BASE_SEPOLIA_ETH_USD = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;
    address internal constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address internal constant BASE_SEPOLIA_USDC_USD = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;

    function test_priceVerifierRejectsCanonicalEthUsdAggregatorWithWrongThreshold() public {
        vm.chainId(1);
        vm.warp(1_800_000_000);

        _mockAggregator({aggregator: MAINNET_ETH_USD, price: 3000e8});
        _mockAggregator({aggregator: MAINNET_USDC_USD, price: 1e8});

        uint256 wrongThreshold = 365 days;
        JBChainlinkV3PriceFeed ethUsdFeed =
            new JBChainlinkV3PriceFeed({feed: AggregatorV3Interface(MAINNET_ETH_USD), threshold: wrongThreshold});

        MockPriceFeed ethNativeFeed = new MockPriceFeed(1e18);
        MockPriceFeed usdEthFeed = new MockPriceFeed(3000e18);
        JBChainlinkV3PriceFeed usdcUsdFeed =
            new JBChainlinkV3PriceFeed({feed: AggregatorV3Interface(MAINNET_USDC_USD), threshold: 86_400});

        MockPriceStore priceStore = new MockPriceStore({
            ethUsdFeed_: address(ethUsdFeed),
            ethNativeFeed_: address(ethNativeFeed),
            usdEthFeed_: address(usdEthFeed),
            usdcUsdFeed_: address(usdcUsdFeed),
            usdc_: MAINNET_USDC
        });

        VerifyOracleHarness harness = new VerifyOracleHarness();
        harness.setPrices(address(priceStore));

        assertEq(address(ethUsdFeed.FEED()), MAINNET_ETH_USD);
        assertNotEq(ethUsdFeed.THRESHOLD(), 3600, "test must use noncanonical threshold");

        // Coverage: Verify.s.sol now asserts the wrapper's THRESHOLD matches the canonical 3600s.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "ETH/USD: THRESHOLD matches deploy-time staleness window"
            )
        );
        harness.verifyPriceFeeds();
    }

    function test_priceVerifierRejectsWrongUsdcUsdAggregator() public {
        vm.chainId(1);
        vm.warp(1_800_000_000);

        address wrongUsdcUsd = makeAddr("wrong usdc/usd aggregator");

        _mockAggregator({aggregator: MAINNET_ETH_USD, price: 3000e8});
        _mockAggregator({aggregator: wrongUsdcUsd, price: 1e8});

        JBChainlinkV3PriceFeed ethUsdFeed =
            new JBChainlinkV3PriceFeed({feed: AggregatorV3Interface(MAINNET_ETH_USD), threshold: 3600});
        MockPriceFeed ethNativeFeed = new MockPriceFeed(1e18);
        MockPriceFeed usdEthFeed = new MockPriceFeed(3000e18);
        JBChainlinkV3PriceFeed usdcUsdFeed =
            new JBChainlinkV3PriceFeed({feed: AggregatorV3Interface(wrongUsdcUsd), threshold: 86_400});

        MockPriceStore priceStore = new MockPriceStore({
            ethUsdFeed_: address(ethUsdFeed),
            ethNativeFeed_: address(ethNativeFeed),
            usdEthFeed_: address(usdEthFeed),
            usdcUsdFeed_: address(usdcUsdFeed),
            usdc_: MAINNET_USDC
        });

        VerifyOracleHarness harness = new VerifyOracleHarness();
        harness.setPrices(address(priceStore));

        assertNotEq(address(usdcUsdFeed.FEED()), MAINNET_USDC_USD, "test must use noncanonical USDC/USD feed");

        // Coverage: Category 8 now also pins the USDC/USD aggregator to the per-chain expected.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "USDC/USD: FEED matches expected Chainlink aggregator"
            )
        );
        harness.verifyPriceFeeds();
    }

    function test_priceVerifierAcceptsSparseBaseSepoliaUsdcUsdUpdatesWithThirtyDayThreshold() public {
        vm.chainId(84_532);
        vm.warp(1_800_000_000);

        _mockAggregator({aggregator: BASE_SEPOLIA_ETH_USD, price: 3000e8});
        _mockAggregatorUpdatedAt({aggregator: BASE_SEPOLIA_USDC_USD, price: 1e8, updatedAt: block.timestamp - 8 days});

        JBChainlinkV3PriceFeed ethUsdFeed =
            new JBChainlinkV3PriceFeed({feed: AggregatorV3Interface(BASE_SEPOLIA_ETH_USD), threshold: 3600});
        MockPriceFeed ethNativeFeed = new MockPriceFeed(1e18);
        MockPriceFeed usdEthFeed = new MockPriceFeed(3000e18);
        JBChainlinkV3PriceFeed usdcUsdFeed =
            new JBChainlinkV3PriceFeed({feed: AggregatorV3Interface(BASE_SEPOLIA_USDC_USD), threshold: 30 days});

        MockPriceStore priceStore = new MockPriceStore({
            ethUsdFeed_: address(ethUsdFeed),
            ethNativeFeed_: address(ethNativeFeed),
            usdEthFeed_: address(usdEthFeed),
            usdcUsdFeed_: address(usdcUsdFeed),
            usdc_: BASE_SEPOLIA_USDC
        });

        VerifyOracleHarness harness = new VerifyOracleHarness();
        harness.setPrices(address(priceStore));

        assertEq(address(usdcUsdFeed.FEED()), BASE_SEPOLIA_USDC_USD);
        assertEq(usdcUsdFeed.THRESHOLD(), 30 days, "Base Sepolia USDC/USD sparse updates need wider threshold");

        harness.verifyPriceFeeds();
    }

    function _mockAggregator(address aggregator, int256 price) internal {
        _mockAggregatorUpdatedAt({aggregator: aggregator, price: price, updatedAt: block.timestamp});
    }

    function _mockAggregatorUpdatedAt(address aggregator, int256 price, uint256 updatedAt) internal {
        vm.mockCall(aggregator, abi.encodeWithSelector(AggregatorV3Interface.decimals.selector), abi.encode(uint8(8)));
        vm.mockCall(
            aggregator,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), price, uint256(0), updatedAt, uint80(1))
        );
    }
}

contract VerifyOracleHarness is Verify {
    function setPrices(address prices_) external {
        prices = JBPrices(prices_);
    }

    function verifyPriceFeeds() external {
        _verifyPriceFeeds();
    }
}

contract MockPriceStore {
    IJBPriceFeed internal immutable _ethUsdFeed;
    IJBPriceFeed internal immutable _ethNativeFeed;
    IJBPriceFeed internal immutable _usdEthFeed;
    IJBPriceFeed internal immutable _usdcUsdFeed;
    address internal immutable _usdc;

    constructor(address ethUsdFeed_, address ethNativeFeed_, address usdEthFeed_, address usdcUsdFeed_, address usdc_) {
        _ethUsdFeed = IJBPriceFeed(ethUsdFeed_);
        _ethNativeFeed = IJBPriceFeed(ethNativeFeed_);
        _usdEthFeed = IJBPriceFeed(usdEthFeed_);
        _usdcUsdFeed = IJBPriceFeed(usdcUsdFeed_);
        _usdc = usdc_;
    }

    function priceFeedFor(
        uint256 projectId,
        uint256 pricingCurrency,
        uint256 unitCurrency
    )
        external
        view
        returns (IJBPriceFeed)
    {
        if (projectId != 0) return IJBPriceFeed(address(0));
        if (pricingCurrency == JBCurrencyIds.USD && unitCurrency == uint32(uint160(JBConstants.NATIVE_TOKEN))) {
            return _ethUsdFeed;
        }
        if (pricingCurrency == JBCurrencyIds.ETH && unitCurrency == uint32(uint160(JBConstants.NATIVE_TOKEN))) {
            return _ethNativeFeed;
        }
        if (pricingCurrency == JBCurrencyIds.USD && unitCurrency == JBCurrencyIds.ETH) return _usdEthFeed;
        if (pricingCurrency == JBCurrencyIds.USD && unitCurrency == uint32(uint160(_usdc))) return _usdcUsdFeed;
        return IJBPriceFeed(address(0));
    }
}

contract MockPriceFeed is IJBPriceFeed {
    uint256 internal immutable _price;

    constructor(uint256 price_) {
        _price = price_;
    }

    function currentUnitPrice(uint256) external view returns (uint256) {
        return _price;
    }
}
