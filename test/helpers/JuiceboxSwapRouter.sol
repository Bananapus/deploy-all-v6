// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

/// @notice Test router that pre-deposits swap input so the Juicebox V4 hook can route from PoolManager balance.
contract JuiceboxSwapRouter {
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using SafeERC20 for IERC20;

    IPoolManager public immutable poolManager;

    address private _msgSender;

    struct CallbackData {
        address sender;
        PoolKey key;
        SwapParams params;
        bytes hookData;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @notice The user whose swap is being routed.
    function msgSender() external view returns (address) {
        return _msgSender;
    }

    /// @notice Executes a swap with `amountOutMin` encoded for the hook.
    function swap(
        PoolKey memory key,
        SwapParams memory params,
        uint256 amountOutMin
    )
        external
        payable
        returns (BalanceDelta delta)
    {
        _msgSender = msg.sender;

        delta = abi.decode(
            poolManager.unlock(
                abi.encode(
                    CallbackData({sender: msg.sender, key: key, params: params, hookData: abi.encode(amountOutMin)})
                )
            ),
            (BalanceDelta)
        );

        _msgSender = address(0);
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PoolManager can call");

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        Currency inputCurrency = data.params.zeroForOne ? data.key.currency0 : data.key.currency1;
        uint256 inputAmount = data.params.amountSpecified < 0
            ? uint256(-data.params.amountSpecified)
            : uint256(data.params.amountSpecified);

        if (!inputCurrency.isAddressZero()) {
            IERC20 inputToken = IERC20(Currency.unwrap(inputCurrency));
            inputToken.safeTransferFrom(data.sender, address(this), inputAmount);
            inputCurrency.settle(poolManager, address(this), inputAmount, false);
        } else {
            poolManager.settle{value: inputAmount}();
        }

        BalanceDelta delta = poolManager.swap(data.key, data.params, data.hookData);
        int256 delta0 = delta.amount0();
        int256 delta1 = delta.amount1();

        if (data.params.zeroForOne) {
            delta0 += int256(inputAmount);
        } else {
            delta1 += int256(inputAmount);
        }

        uint256 amountOutMin = abi.decode(data.hookData, (uint256));
        if (amountOutMin > 0) {
            uint256 outputAmount;
            if (data.params.zeroForOne) {
                outputAmount = delta1 > 0 ? uint256(delta1) : 0;
            } else {
                outputAmount = delta0 > 0 ? uint256(delta0) : 0;
            }

            if (outputAmount < amountOutMin) revert("Output below minimum");
        }

        if (delta0 < 0) data.key.currency0.settle(poolManager, data.sender, uint256(-delta0), false);
        if (delta1 < 0) data.key.currency1.settle(poolManager, data.sender, uint256(-delta1), false);

        if (delta0 > 0) data.key.currency0.take(poolManager, data.sender, uint256(delta0), false);
        if (delta1 > 0) data.key.currency1.take(poolManager, data.sender, uint256(delta1), false);

        return abi.encode(delta);
    }

    receive() external payable {}
}
