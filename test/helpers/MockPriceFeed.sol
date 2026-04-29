// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {JBFixedPointNumber} from "@bananapus/core-v6/src/libraries/JBFixedPointNumber.sol";

/// @notice Fixed-price feed for fork testing. Replaces 6+ identical mock price feed contracts.
contract MockPriceFeed is IJBPriceFeed {
    uint256 public immutable PRICE;
    uint8 public immutable FEED_DECIMALS;

    constructor(uint256 price, uint8 feedDecimals) {
        PRICE = price;
        FEED_DECIMALS = feedDecimals;
    }

    function currentUnitPrice(uint256 decimals) external view override returns (uint256) {
        return JBFixedPointNumber.adjustDecimals(PRICE, FEED_DECIMALS, decimals);
    }
}

/// @notice Controllable price feed with toggle to revert. For failure-mode testing.
contract ControllablePriceFeed is IJBPriceFeed {
    uint256 public price;
    uint8 public feedDecimals;
    bool public shouldRevert;

    constructor(uint256 _price, uint8 _feedDecimals) {
        price = _price;
        feedDecimals = _feedDecimals;
    }

    function setPrice(uint256 _price, uint8 _feedDecimals) external {
        price = _price;
        feedDecimals = _feedDecimals;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function currentUnitPrice(uint256 decimals) external view override returns (uint256) {
        require(!shouldRevert, "ControllablePriceFeed: reverted");
        return JBFixedPointNumber.adjustDecimals(price, feedDecimals, decimals);
    }
}

/// @notice Zero-price feed for DoS testing.
contract ZeroPriceFeed is IJBPriceFeed {
    function currentUnitPrice(uint256) external pure override returns (uint256) {
        return 0;
    }
}
