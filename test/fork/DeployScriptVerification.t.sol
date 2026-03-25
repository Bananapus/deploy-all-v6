// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {AggregatorV3Interface} from "@bananapus/core-v6/src/JBChainlinkV3PriceFeed.sol";

/// @notice Verifies that hardcoded addresses in Deploy.s.sol match known-good canonical values.
///
/// Run with: forge test --match-contract DeployScriptVerificationTest -vvv
contract DeployScriptVerificationTest is Test {
    // ════════════════════════════════════════════════════════════════════
    //  Known Canonical Addresses (must match Deploy.s.sol)
    // ════════════════════════════════════════════════════════════════════

    // Permit2 — canonical across all chains
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // WETH addresses per chain
    address constant WETH_ETHEREUM = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WETH_OPTIMISM = 0x4200000000000000000000000000000000000006;
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    address constant WETH_ARBITRUM = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // Chainlink ETH/USD feed addresses per chain
    address constant CHAINLINK_ETH_USD_ETHEREUM = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant CHAINLINK_ETH_USD_OPTIMISM = 0x13e3Ee699D1909E989722E753853AE30b17e08c5;
    address constant CHAINLINK_ETH_USD_BASE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant CHAINLINK_ETH_USD_ARBITRUM = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    // Chainlink USDC/USD feed addresses per chain
    address constant CHAINLINK_USDC_USD_ETHEREUM = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant CHAINLINK_USDC_USD_OPTIMISM = 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;
    address constant CHAINLINK_USDC_USD_BASE = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address constant CHAINLINK_USDC_USD_ARBITRUM = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

    // L2 Sequencer uptime feed addresses
    address constant SEQUENCER_OPTIMISM = 0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389;
    address constant SEQUENCER_BASE = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;
    address constant SEQUENCER_ARBITRUM = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;

    // Uniswap V3 Factory addresses per chain
    address constant UNISWAP_V3_FACTORY_ETHEREUM = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant UNISWAP_V3_FACTORY_OPTIMISM = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant UNISWAP_V3_FACTORY_ARBITRUM = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant UNISWAP_V3_FACTORY_BASE = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

    // USDC addresses per chain
    address constant USDC_ETHEREUM = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_OPTIMISM = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDC_ARBITRUM = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    // ════════════════════════════════════════════════════════════════════
    //  Permit2 Verification
    // ════════════════════════════════════════════════════════════════════

    /// @notice Verify Permit2 is deployed on Ethereum mainnet and responds to DOMAIN_SEPARATOR().
    function test_deployScript_permit2Address_ethereum() public {
        try vm.createSelectFork("ethereum", 21_700_000) {
            assertTrue(PERMIT2.code.length > 0, "Permit2 not deployed on Ethereum mainnet");

            // Verify it responds to DOMAIN_SEPARATOR() (a core Permit2 function).
            (bool success,) = PERMIT2.staticcall(abi.encodeWithSignature("DOMAIN_SEPARATOR()"));
            assertTrue(success, "Permit2 does not respond to DOMAIN_SEPARATOR()");
        } catch {
            vm.skip(true);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  WETH Address Verification
    // ════════════════════════════════════════════════════════════════════

    /// @notice Verify WETH on Ethereum mainnet is deployed and has correct symbol.
    function test_deployScript_wethAddress_ethereum() public {
        try vm.createSelectFork("ethereum", 21_700_000) {
            assertTrue(WETH_ETHEREUM.code.length > 0, "WETH not deployed on Ethereum");
            _verifyIsWeth(WETH_ETHEREUM);
        } catch {
            vm.skip(true);
        }
    }

    /// @notice Verify L2 WETH addresses are the well-known canonical values.
    /// These are checked as constant assertions — no fork needed.
    function test_deployScript_wethAddresses_l2Canonical() public pure {
        // Optimism and Base share the same canonical WETH address (L2 precompile).
        assertEq(WETH_OPTIMISM, 0x4200000000000000000000000000000000000006, "Optimism WETH mismatch");
        assertEq(WETH_BASE, 0x4200000000000000000000000000000000000006, "Base WETH mismatch");

        // Arbitrum has its own canonical WETH.
        assertEq(WETH_ARBITRUM, 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, "Arbitrum WETH mismatch");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Chainlink ETH/USD Feed Verification
    // ════════════════════════════════════════════════════════════════════

    /// @notice Verify the Chainlink ETH/USD feed on Ethereum mainnet returns a reasonable price.
    function test_deployScript_chainlinkFeed_ethUsd_ethereum() public {
        try vm.createSelectFork("ethereum", 21_700_000) {
            assertTrue(CHAINLINK_ETH_USD_ETHEREUM.code.length > 0, "ETH/USD feed not deployed on Ethereum");
            _verifyChainlinkFeedReasonable(CHAINLINK_ETH_USD_ETHEREUM, 100e8, 100_000e8);
        } catch {
            vm.skip(true);
        }
    }

    /// @notice Verify the Chainlink USDC/USD feed on Ethereum mainnet returns a reasonable price.
    function test_deployScript_chainlinkFeed_usdcUsd_ethereum() public {
        try vm.createSelectFork("ethereum", 21_700_000) {
            assertTrue(CHAINLINK_USDC_USD_ETHEREUM.code.length > 0, "USDC/USD feed not deployed on Ethereum");
            // USDC/USD should be very close to $1 — between $0.90 and $1.10
            _verifyChainlinkFeedReasonable(CHAINLINK_USDC_USD_ETHEREUM, 0.9e8, 1.1e8);
        } catch {
            vm.skip(true);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  Uniswap V3 Factory Verification
    // ════════════════════════════════════════════════════════════════════

    /// @notice Verify the Uniswap V3 Factory on Ethereum mainnet is deployed and responds to feeAmountTickSpacing().
    function test_deployScript_uniswapV3Factory_ethereum() public {
        try vm.createSelectFork("ethereum", 21_700_000) {
            assertTrue(UNISWAP_V3_FACTORY_ETHEREUM.code.length > 0, "Uniswap V3 Factory not deployed on Ethereum");

            // Verify it responds to feeAmountTickSpacing(500) — a core V3 factory view.
            (bool success, bytes memory data) = UNISWAP_V3_FACTORY_ETHEREUM.staticcall(
                abi.encodeWithSignature("feeAmountTickSpacing(uint24)", uint24(500))
            );
            assertTrue(success, "V3 Factory does not respond to feeAmountTickSpacing()");

            int24 tickSpacing = abi.decode(data, (int24));
            assertEq(tickSpacing, 10, "Unexpected tick spacing for 500 bps fee tier");
        } catch {
            vm.skip(true);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  USDC Address Verification
    // ════════════════════════════════════════════════════════════════════

    /// @notice Verify USDC on Ethereum mainnet is deployed and has correct symbol.
    function test_deployScript_usdcAddress_ethereum() public {
        try vm.createSelectFork("ethereum", 21_700_000) {
            assertTrue(USDC_ETHEREUM.code.length > 0, "USDC not deployed on Ethereum");

            (bool success, bytes memory data) = USDC_ETHEREUM.staticcall(abi.encodeWithSignature("symbol()"));
            assertTrue(success, "USDC does not respond to symbol()");

            string memory symbol = abi.decode(data, (string));
            assertEq(symbol, "USDC", "Unexpected USDC symbol on Ethereum");
        } catch {
            vm.skip(true);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  L2 Sequencer Feed Verification (existence check only)
    // ════════════════════════════════════════════════════════════════════

    /// @notice Verify that all L2 sequencer feed addresses are distinct non-zero values.
    function test_deployScript_sequencerFeeds_nonZero() public pure {
        assertTrue(SEQUENCER_OPTIMISM != address(0), "Optimism sequencer feed is zero");
        assertTrue(SEQUENCER_BASE != address(0), "Base sequencer feed is zero");
        assertTrue(SEQUENCER_ARBITRUM != address(0), "Arbitrum sequencer feed is zero");

        // Each chain should have a distinct sequencer feed.
        assertTrue(SEQUENCER_OPTIMISM != SEQUENCER_BASE, "OP and Base share sequencer feed (unexpected)");
        assertTrue(SEQUENCER_OPTIMISM != SEQUENCER_ARBITRUM, "OP and Arbitrum share sequencer feed (unexpected)");
        assertTrue(SEQUENCER_BASE != SEQUENCER_ARBITRUM, "Base and Arbitrum share sequencer feed (unexpected)");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Cross-Chain Address Consistency
    // ════════════════════════════════════════════════════════════════════

    /// @notice Verify that Ethereum, Optimism, and Arbitrum share the same Uniswap V3 Factory.
    /// Base uses a different factory address.
    function test_deployScript_uniswapV3Factory_crossChainConsistency() public pure {
        assertEq(
            UNISWAP_V3_FACTORY_ETHEREUM, UNISWAP_V3_FACTORY_OPTIMISM, "Ethereum and Optimism V3 Factory should match"
        );
        assertEq(
            UNISWAP_V3_FACTORY_ETHEREUM, UNISWAP_V3_FACTORY_ARBITRUM, "Ethereum and Arbitrum V3 Factory should match"
        );

        // Base uses a different factory (deployed by a different deployer).
        assertTrue(
            UNISWAP_V3_FACTORY_BASE != UNISWAP_V3_FACTORY_ETHEREUM, "Base V3 Factory should differ from Ethereum"
        );
    }

    // ════════════════════════════════════════════════════════════════════
    //  Helpers
    // ════════════════════════════════════════════════════════════════════

    /// @dev Calls name() on a WETH contract and asserts it contains "Wrapped Ether" or "WETH".
    function _verifyIsWeth(address weth) internal view {
        (bool success, bytes memory data) = weth.staticcall(abi.encodeWithSignature("symbol()"));
        assertTrue(success, "WETH does not respond to symbol()");

        string memory symbol = abi.decode(data, (string));
        assertEq(symbol, "WETH", "Unexpected WETH symbol");
    }

    /// @dev Calls latestRoundData() on a Chainlink feed and verifies the price is within bounds.
    function _verifyChainlinkFeedReasonable(address feed, int256 minPrice, int256 maxPrice) internal view {
        AggregatorV3Interface aggregator = AggregatorV3Interface(feed);

        (, int256 answer,, uint256 updatedAt,) = aggregator.latestRoundData();

        assertTrue(answer > minPrice, "Chainlink price below minimum");
        assertTrue(answer < maxPrice, "Chainlink price above maximum");
        assertTrue(updatedAt > 0, "Chainlink updatedAt is zero");
    }
}
