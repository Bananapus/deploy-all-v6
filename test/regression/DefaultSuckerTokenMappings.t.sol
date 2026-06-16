// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Deploy} from "../../script/Deploy.s.sol";

contract DefaultSuckerTokenMappingsHarness is Deploy {
    function defaultSuckerRemoteChainIds() external view returns (uint256[] memory) {
        return _defaultSuckerRemoteChainIds();
    }

    function usdcTokenFor(uint256 chainId) external pure returns (address) {
        return _usdcTokenFor(chainId);
    }
}

contract DefaultSuckerTokenMappingsTest is Test {
    DefaultSuckerTokenMappingsHarness internal harness;

    function setUp() external {
        harness = new DefaultSuckerTokenMappingsHarness();
    }

    function test_defaultSuckerRemoteChainIds_arbitrumMainnet() external {
        vm.chainId(42_161);

        uint256[] memory ids = harness.defaultSuckerRemoteChainIds();

        assertEq(ids.length, 3);
        assertEq(ids[0], 1);
        assertEq(ids[1], 10);
        assertEq(ids[2], 8453);
    }

    function test_defaultSuckerRemoteChainIds_baseMainnet() external {
        vm.chainId(8453);

        uint256[] memory ids = harness.defaultSuckerRemoteChainIds();

        assertEq(ids.length, 3);
        assertEq(ids[0], 1);
        assertEq(ids[1], 10);
        assertEq(ids[2], 42_161);
    }

    function test_defaultSuckerRemoteChainIds_ethereumMainnet() external {
        vm.chainId(1);

        uint256[] memory ids = harness.defaultSuckerRemoteChainIds();

        assertEq(ids.length, 3);
        assertEq(ids[0], 10);
        assertEq(ids[1], 8453);
        assertEq(ids[2], 42_161);
    }

    function test_defaultSuckerRemoteChainIds_optimismMainnet() external {
        vm.chainId(10);

        uint256[] memory ids = harness.defaultSuckerRemoteChainIds();

        assertEq(ids.length, 3);
        assertEq(ids[0], 1);
        assertEq(ids[1], 42_161);
        assertEq(ids[2], 8453);
    }

    function test_defaultSuckerRemoteChainIds_testnets() external {
        vm.chainId(11_155_111);

        uint256[] memory ids = harness.defaultSuckerRemoteChainIds();

        assertEq(ids.length, 3);
        assertEq(ids[0], 11_155_420);
        assertEq(ids[1], 84_532);
        assertEq(ids[2], 421_614);
    }

    function test_defaultSuckerRemoteChainIds_unsupported() external {
        vm.chainId(999);

        uint256[] memory ids = harness.defaultSuckerRemoteChainIds();

        assertEq(ids.length, 0);
    }

    function test_deployCallsDefaultSuckerTokenMappingApprovals() external {
        string memory source = vm.readFile("script/Deploy.s.sol");

        assertTrue(_contains(source, "_allowDefaultSuckerTokenMappings();"));
        assertTrue(_contains(source, "allowTokenMapping({"));
        assertTrue(_contains(source, "tokenMappingIsAllowed({"));
    }

    function test_usdcTokenForSupportedChains() external view {
        assertEq(harness.usdcTokenFor(1), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        assertEq(harness.usdcTokenFor(10), 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85);
        assertEq(harness.usdcTokenFor(8453), 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
        assertEq(harness.usdcTokenFor(42_161), 0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        assertEq(harness.usdcTokenFor(11_155_111), 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        assertEq(harness.usdcTokenFor(11_155_420), 0x5fd84259d66Cd46123540766Be93DFE6D43130D7);
        assertEq(harness.usdcTokenFor(84_532), 0x036CbD53842c5426634e7929541eC2318f3dCF7e);
        assertEq(harness.usdcTokenFor(421_614), 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d);
        assertEq(harness.usdcTokenFor(999), address(0));
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);

        if (needleBytes.length == 0) return true;
        if (needleBytes.length > haystackBytes.length) return false;

        for (uint256 i; i <= haystackBytes.length - needleBytes.length; i++) {
            bool matches = true;
            for (uint256 j; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) return true;
        }

        return false;
    }
}
