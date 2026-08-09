// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IGeomeanOracle} from "@bananapus/univ4-router-v6/src/interfaces/IGeomeanOracle.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Flat-tick geomean oracle for fork testing, etched over a pool key's hook address.
/// @dev Cumulatives are derived from the `secondsAgos` the caller actually asks for, the way a real oracle derives
/// them. A consumer that narrows its TWAP window therefore reads back the same mean tick rather than one scaled by
/// the ratio between the window it asked for and the window the pool was registered with.
contract MockGeomeanOracle is IGeomeanOracle {
    /// @notice The tick every observation window averages to.
    int24 public tick;

    /// @notice The in-range liquidity every observation window averages to. Read as 1 when left at zero.
    uint256 public liquidity;

    /// @notice The age of the oldest retained observation, in seconds.
    uint32 public coverage;

    /// @notice Point the oracle at a tick, a liquidity, and a depth of retained history.
    /// @param newTick The tick every window averages to.
    /// @param newLiquidity The liquidity every window averages to.
    /// @param newCoverage The age of the oldest retained observation, in seconds.
    function setObservations(int24 newTick, uint256 newLiquidity, uint32 newCoverage) external {
        tick = newTick;
        liquidity = newLiquidity;
        coverage = newCoverage;
    }

    /// @inheritdoc IGeomeanOracle
    function hasObservationCoverage(PoolKey calldata, uint32) external pure override returns (bool) {
        return true;
    }

    /// @inheritdoc IGeomeanOracle
    function observationCoverageOf(PoolKey calldata) external view override returns (uint32) {
        return coverage;
    }

    /// @inheritdoc IGeomeanOracle
    function observe(
        PoolKey calldata,
        uint32[] calldata secondsAgos
    )
        external
        view
        override
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        uint256 count = secondsAgos.length;

        tickCumulatives = new int56[](count);
        secondsPerLiquidityCumulativeX128s = new uint160[](count);

        // Anchor the cumulatives at the oldest requested offset. Every entry then stays non-negative, and the delta
        // between any two entries spans exactly the seconds between their offsets.
        uint32 oldest;
        for (uint256 i; i < count; i++) {
            if (secondsAgos[i] > oldest) oldest = secondsAgos[i];
        }

        uint256 liquidityToUse = liquidity == 0 ? 1 : liquidity;

        for (uint256 i; i < count; i++) {
            uint56 elapsed = uint56(oldest - secondsAgos[i]);
            // forge-lint: disable-next-line(unsafe-typecast)
            tickCumulatives[i] = int56(tick) * int56(elapsed);
            // forge-lint: disable-next-line(unsafe-typecast)
            secondsPerLiquidityCumulativeX128s[i] = uint160((uint256(elapsed) << 128) / liquidityToUse);
        }
    }

    /// @dev Selectors outside the oracle interface succeed with empty returndata, matching the bare `STOP` byte this
    /// mock is etched over. Consumers that probe the hook address with unrelated calls keep working.
    fallback() external payable {}

    receive() external payable {}
}
