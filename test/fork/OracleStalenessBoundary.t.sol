// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {JBChainlinkV3PriceFeed} from "@bananapus/core-v6/src/JBChainlinkV3PriceFeed.sol";

/// @notice Minimal controllable Chainlink aggregator mock (set the round fields directly).
contract MockAggregatorV3 {
    uint8 public decimals = 8;
    int256 internal _answer;
    uint256 internal _updatedAt;
    uint80 internal _roundId = 1;
    uint80 internal _answeredInRound = 1;

    function set(int256 answer, uint256 updatedAt) external {
        _answer = answer;
        _updatedAt = updatedAt;
    }

    function description() external pure returns (string memory) {
        return "MOCK / USD";
    }

    function version() external pure returns (uint256) {
        return 4;
    }

    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }
}

/// @notice Pins the zero-margin staleness behavior of `JBChainlinkV3PriceFeed`. When a feed's staleness `THRESHOLD`
/// equals the underlying Chainlink heartbeat there is ZERO safety margin — `currentUnitPrice` reverts the instant
/// `block.timestamp > THRESHOLD + updatedAt`, i.e. one second past the heartbeat without an update. ETH/USD ships at
/// its 3600s heartbeat by design (volatile asset, sub-hourly mainnet updates). USDC/USD ships with margin precisely to
/// avoid this edge: 48h (2x heartbeat) on mainnet and 30 days on testnet, where a stablecoin tolerates staleness and
/// testnet feeds update sparsely. When a USD feed does lapse past its threshold, every conversion-dependent
/// pay/payout/cash-out into a USD-base project (DEFIFA 5, ART 6, and NANA cross-pricing) reverts — only one feed is
/// registered per direction, so there is no backup to fall through to.
///
/// This test pins the contract's zero-margin revert at exactly-`THRESHOLD`, using the Chainlink heartbeats as
/// representative thresholds. It is the rationale behind the USDC/USD margin the deploy script now applies.
///
/// Run with: forge test --match-contract OracleStalenessBoundaryTest -vvv
contract OracleStalenessBoundaryTest is Test {
    uint256 internal constant ETH_USD_HEARTBEAT = 3600; // canonical ETH/USD staleness threshold
    uint256 internal constant USDC_USD_HEARTBEAT = 86_400; // Chainlink USDC/USD heartbeat (deploy ships 48h mainnet / 30d testnet)

    function _assertZeroMargin(uint256 threshold) internal {
        MockAggregatorV3 agg = new MockAggregatorV3();
        JBChainlinkV3PriceFeed feed = new JBChainlinkV3PriceFeed(AggregatorV3Interface(address(agg)), threshold);

        // Anchor "now" comfortably past the threshold so updatedAt can be threshold-in-the-past.
        vm.warp(threshold + 1_000_000);

        // updatedAt EXACTLY `threshold` seconds ago -> block.timestamp == THRESHOLD + updatedAt -> NOT stale
        // (accepted).
        agg.set({answer: 2000e8, updatedAt: block.timestamp - threshold});
        uint256 price = feed.currentUnitPrice(18);
        assertGt(price, 0, "a price exactly THRESHOLD-old is the LAST acceptable value (zero margin)");

        // ONE SECOND older -> block.timestamp == THRESHOLD + updatedAt + 1 -> stale -> the whole conversion reverts.
        agg.set({answer: 2000e8, updatedAt: block.timestamp - threshold - 1});
        vm.expectRevert(
            abi.encodeWithSelector(
                JBChainlinkV3PriceFeed.JBChainlinkV3PriceFeed_StalePrice.selector,
                block.timestamp,
                threshold,
                block.timestamp - threshold - 1
            )
        );
        feed.currentUnitPrice(18);
    }

    /// @notice ETH/USD (3600s): one second past the heartbeat reverts every ETH-priced conversion.
    function test_oracle_ethUsd_zeroStalenessMargin() public {
        _assertZeroMargin(ETH_USD_HEARTBEAT);
    }

    /// @notice USDC/USD at its 86400s Chainlink heartbeat: one second past reverts every USDC-denominated conversion
    /// (the zero-margin case the deploy avoids by shipping 48h/30d).
    function test_oracle_usdcUsd_zeroStalenessMargin() public {
        _assertZeroMargin(USDC_USD_HEARTBEAT);
    }

    /// @notice Contrast: a threshold with margin (2x heartbeat) survives a price one heartbeat old — the recommended
    /// fix.
    function test_oracle_marginAboveHeartbeat_survivesBoundary() public {
        MockAggregatorV3 agg = new MockAggregatorV3();
        JBChainlinkV3PriceFeed feed =
            new JBChainlinkV3PriceFeed(AggregatorV3Interface(address(agg)), 2 * ETH_USD_HEARTBEAT);
        vm.warp(10_000_000);

        // A price one full heartbeat (3600s) old + 1s — would revert under the zero-margin config — is fine here.
        agg.set({answer: 2000e8, updatedAt: block.timestamp - ETH_USD_HEARTBEAT - 1});
        assertGt(feed.currentUnitPrice(18), 0, "2x-heartbeat threshold tolerates routine boundary staleness");
    }
}
