// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {BuybackFloorFixBase} from "../../script/DeployBuybackFloorFix.s.sol";

contract BuybackFloorFixGuardHarness is BuybackFloorFixBase {
    function shouldDeployUniswapStack() external view returns (bool) {
        return _shouldDeployUniswapStack();
    }

    function loadBuybackDeploymentAddresses() external {
        _loadBuybackDeploymentAddresses();
    }
}

/// @notice OP Sepolia carries the registry and price feeds but no Uniswap stack: no buyback hook, no router, no
/// oracle hook. The proposal must stop after the feeds there, and the guard that stops it must be the only thing
/// standing between the run and a deployment-record read that cannot succeed.
contract BuybackFloorFixOpSepoliaFeedsOnlyTest is Test {
    BuybackFloorFixGuardHarness internal harness;

    function setUp() public {
        harness = new BuybackFloorFixGuardHarness();
    }

    function test_opSepoliaSkipsTheUniswapStack() public {
        vm.chainId(11_155_420);
        assertFalse(harness.shouldDeployUniswapStack(), "OP Sepolia must stay feeds-only");

        // The buyback loader needs records OP Sepolia does not have (JBUniswapV4Hook, JBRouterTerminal), so it must
        // never run there: the guard above is load-bearing, not cosmetic.
        vm.expectRevert();
        harness.loadBuybackDeploymentAddresses();
    }

    function test_everyOtherSupportedChainDeploysTheUniswapStack() public {
        uint256[7] memory chainIds = [uint256(1), 10, 8453, 42_161, 11_155_111, 84_532, 421_614];
        for (uint256 i; i < chainIds.length; i++) {
            vm.chainId(chainIds[i]);
            assertTrue(harness.shouldDeployUniswapStack(), "every other supported chain gets the router and gateway");
        }
    }
}
