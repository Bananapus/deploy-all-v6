// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice The single canonical per-chain token table for the deploy scripts, plus the currency-ID convention that
/// turns a token address into a `JBPrices` / `JBAccountingContext` currency. Every script reads the table from here so
/// a chain added or corrected in one place cannot drift from another.
library JBChainTokens {
    /// @notice The canonical USDC token on a chain, or the zero address if the chain has none.
    /// @param chainId The chain to look up.
    /// @return The USDC token address, or the zero address.
    function usdcTokenFor(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (chainId == 11_155_111) return 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        if (chainId == 10) return 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
        if (chainId == 11_155_420) return 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;
        if (chainId == 8453) return 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        if (chainId == 84_532) return 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        if (chainId == 42_161) return 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        if (chainId == 421_614) return 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
        return address(0);
    }

    /// @dev Juicebox price-feed currency IDs use the low 32 bits of ERC-20 token addresses.
    /// @param token The token to derive a currency ID for.
    /// @return The currency ID.
    function currencyIdOf(address token) internal pure returns (uint32) {
        // The truncation is intentional: JBAccountingContext identifies ERC-20 currencies by uint32(uint160(token)).
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint32(uint160(token));
    }
}
