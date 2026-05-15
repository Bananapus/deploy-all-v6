// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

/// @notice Coverage: each swap-CCIP deployer's swap-specific endpoint pointers
/// (bridgeToken, poolManager, v3Factory, univ4Hook, wrappedNativeToken) must match the
/// canonical chain manifest. Artifact bytecode parity masks immutables and `setSwapConstants`
/// writes to storage rather than immutables — either way, per-surface getter equality is the
/// only way to authenticate them.
contract SwapCcipSwapConstantsVerifierGapTest is Test {
    address internal constant CANONICAL_MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant CANONICAL_MAINNET_V4_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant CANONICAL_MAINNET_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant CANONICAL_MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function test_swapCcipVerifierRejectsWrongBridgeTokenOnMainnet() public {
        vm.chainId(1);

        address wrongBridgeToken = makeAddr("wrong bridge token");
        assertTrue(wrongBridgeToken != CANONICAL_MAINNET_USDC, "test must use a noncanonical bridge token");

        VerifySwapCcipSwapConstantsHarness harness = new VerifySwapCcipSwapConstantsHarness();
        // Wire every other constant to canonical so the bridgeToken branch is the one that fails.
        address deployer = address(
            new MockSwapCcipDeployer({
                bridgeToken_: wrongBridgeToken,
                poolManager_: CANONICAL_MAINNET_V4_POOL_MANAGER,
                v3Factory_: CANONICAL_MAINNET_V3_FACTORY,
                univ4Hook_: address(0),
                wrappedNativeToken_: CANONICAL_MAINNET_WETH
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                string.concat("Swap-CCIP deployer ", vm.toString(deployer), " bridgeToken == canonical USDC")
            )
        );
        harness.checkSwapConstants(deployer);
    }

    function test_swapCcipVerifierRejectsWrongV4PoolManagerOnMainnet() public {
        vm.chainId(1);

        address wrongPoolManager = makeAddr("wrong v4 pool manager");
        assertTrue(wrongPoolManager != CANONICAL_MAINNET_V4_POOL_MANAGER, "test must use a noncanonical pool manager");

        VerifySwapCcipSwapConstantsHarness harness = new VerifySwapCcipSwapConstantsHarness();
        address deployer = address(
            new MockSwapCcipDeployer({
                bridgeToken_: CANONICAL_MAINNET_USDC,
                poolManager_: wrongPoolManager,
                v3Factory_: CANONICAL_MAINNET_V3_FACTORY,
                univ4Hook_: address(0),
                wrappedNativeToken_: CANONICAL_MAINNET_WETH
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                string.concat("Swap-CCIP deployer ", vm.toString(deployer), " poolManager == canonical V4")
            )
        );
        harness.checkSwapConstants(deployer);
    }

    function test_swapCcipVerifierRejectsWrongWrappedNativeOnMainnet() public {
        vm.chainId(1);

        address wrongWeth = makeAddr("wrong weth");
        assertTrue(wrongWeth != CANONICAL_MAINNET_WETH, "test must use a noncanonical WETH");

        VerifySwapCcipSwapConstantsHarness harness = new VerifySwapCcipSwapConstantsHarness();
        address deployer = address(
            new MockSwapCcipDeployer({
                bridgeToken_: CANONICAL_MAINNET_USDC,
                poolManager_: CANONICAL_MAINNET_V4_POOL_MANAGER,
                v3Factory_: CANONICAL_MAINNET_V3_FACTORY,
                univ4Hook_: address(0),
                wrappedNativeToken_: wrongWeth
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                string.concat("Swap-CCIP deployer ", vm.toString(deployer), " wrappedNativeToken == canonical")
            )
        );
        harness.checkSwapConstants(deployer);
    }
}

contract VerifySwapCcipSwapConstantsHarness is Verify {
    function checkSwapConstants(address deployer) external {
        _checkSwapCcipSwapConstants(deployer);
    }
}

contract MockSwapCcipDeployer {
    address internal immutable _bridgeToken;
    address internal immutable _poolManager;
    address internal immutable _v3Factory;
    address internal immutable _univ4Hook;
    address internal immutable _wrappedNativeToken;

    constructor(
        address bridgeToken_,
        address poolManager_,
        address v3Factory_,
        address univ4Hook_,
        address wrappedNativeToken_
    ) {
        _bridgeToken = bridgeToken_;
        _poolManager = poolManager_;
        _v3Factory = v3Factory_;
        _univ4Hook = univ4Hook_;
        _wrappedNativeToken = wrappedNativeToken_;
    }

    function bridgeToken() external view returns (address) {
        return _bridgeToken;
    }

    function poolManager() external view returns (address) {
        return _poolManager;
    }

    function v3Factory() external view returns (address) {
        return _v3Factory;
    }

    function univ4Hook() external view returns (address) {
        return _univ4Hook;
    }

    function wrappedNativeToken() external view returns (address) {
        return _wrappedNativeToken;
    }
}
