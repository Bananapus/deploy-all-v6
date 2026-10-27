// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalGateway} from "@bananapus/router-terminal-v6/src/JBRouterTerminalGateway.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";
import {JBUniswapV4Hook} from "@bananapus/univ4-router-v6/src/JBUniswapV4Hook.sol";

import {HooksV2Base} from "../../script/DeployHooksV2.s.sol";

/// @notice Runs the whole proposal body, Sphinx-free. Its code is etched over the infra Safe so every call it makes
/// comes from the Safe: both registries' owner, the hooks' and router's one-shot deployer, and project 1's operator.
contract HooksV2RehearsalHarness is HooksV2Base {
    function rehearse() external {
        _setupChainAddresses();
        _loadDeploymentAddresses();
        _deployHooksV2();
    }

    function feeProjectPoolSqrtPriceX96() external view returns (bool ok, uint160 sqrtPriceX96) {
        return _feeProjectPoolSqrtPriceX96();
    }

    function univ4Hook() external view returns (JBUniswapV4Hook) {
        return _univ4Hook;
    }

    function buybackHook() external view returns (JBBuybackHook) {
        return _buybackHook;
    }

    function routerTerminal() external view returns (JBRouterTerminal) {
        return _routerTerminal;
    }

    function gateway() external view returns (JBRouterTerminalGateway) {
        return _gateway;
    }

    function oldBuybackHook() external view returns (JBBuybackHook) {
        return _oldBuybackHook;
    }

    function oldRouterTerminal() external view returns (JBRouterTerminal) {
        return _oldRouterTerminal;
    }

    function oldGateway() external view returns (JBRouterTerminalGateway) {
        return _oldGateway;
    }

    function buybackRegistry() external view returns (JBBuybackHookRegistry) {
        return _buybackRegistry;
    }

    function routerRegistry() external view returns (JBRouterTerminalRegistry) {
        return _routerRegistry;
    }

    function terminal() external view returns (IJBTerminal) {
        return _terminal;
    }

    function poolManager() external view returns (address) {
        return _poolManager;
    }
}

/// @notice Rehearses the hooks 2.0.0 proposal against live Base: the existing registries, the REVOwner-owned fee
/// project, and the infra Safe's real permissions. Proves the proposal deploys and wires the new graph, moves only
/// project 1, is a no-op when rerun, and that project 1's new pool and routes work end to end. Requires artifacts built
/// from buyback-hook-v6 2.0.0 and univ4-router-v6 2.0.0 (`npm run artifacts`) and RPC_BASE_MAINNET.
contract DeployHooksV2ForkTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using stdJson for string;

    address internal constant _SAFE = 0x4dc161eF837fF1C4485b08DDFcDB182F2157bE18;
    uint256 internal constant _FEE_PROJECT_ID = 1;
    uint256 internal constant _FORK_BLOCK = 53_138_000;

    /// @notice A revnet that keeps its outgoing hook and gateway until its own operator migrates it.
    uint256 internal constant _UNMIGRATED_PROJECT_ID = 7;

    HooksV2RehearsalHarness internal harness;
    address internal payer = makeAddr("payer");

    function setUp() public {
        vm.createSelectFork("base", _FORK_BLOCK);
        vm.etch(_SAFE, address(new HooksV2RehearsalHarness()).code);
        vm.allowCheatcodes(_SAFE);
        harness = HooksV2RehearsalHarness(_SAFE);
    }

    function test_deploysAndWiresTheNewGraph() public {
        address buybackRegistryBefore = _liveAddressOf("JBBuybackHookRegistry");
        address routerRegistryBefore = _liveAddressOf("JBRouterTerminalRegistry");

        harness.rehearse();

        JBUniswapV4Hook univ4Hook = harness.univ4Hook();
        JBBuybackHook buybackHook = harness.buybackHook();
        JBRouterTerminal router = harness.routerTerminal();
        JBRouterTerminalGateway gateway = harness.gateway();
        JBBuybackHookRegistry buybackRegistry = harness.buybackRegistry();
        JBRouterTerminalRegistry routerRegistry = harness.routerRegistry();

        // REVDeployer pins both registries, so they are reused.
        assertEq(address(buybackRegistry), buybackRegistryBefore, "buyback registry reused");
        assertEq(address(routerRegistry), routerRegistryBefore, "router registry reused");

        // The V4 hook's address carries exactly its permission flags.
        assertGt(address(univ4Hook).code.length, 0, "V4 hook deployed");
        assertEq(
            uint160(address(univ4Hook)) & HookMiner.FLAG_MASK,
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
                    | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                    | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            ),
            "V4 hook flags: afterInitialize, afterAdd/RemoveLiquidity, beforeSwap, afterSwap, beforeSwapReturnDelta"
        );
        assertTrue(address(univ4Hook) != _liveAddressOf("JBUniswapV4Hook"), "a new V4 hook, not the live one");

        // Buyback hook on the new V4 hook.
        assertEq(address(buybackHook.poolManager()), harness.poolManager(), "buyback PoolManager");
        assertEq(address(buybackHook.oracleHook()), address(univ4Hook), "buyback reads the new V4 hook");

        // Router bound to the new buyback hook and V4 hook, chain wiring copied from the live router.
        JBRouterTerminal oldRouter = harness.oldRouterTerminal();
        assertEq(router.BUYBACK_HOOK(), address(buybackHook), "router bound to the new buyback hook");
        assertEq(router.univ4Hook(), address(univ4Hook), "router routes through the new V4 hook");
        assertEq(address(router.poolManager()), harness.poolManager(), "router PoolManager");
        assertEq(address(router.wrappedNativeToken()), address(oldRouter.wrappedNativeToken()), "WETH copied");
        assertEq(address(router.factory()), address(oldRouter.factory()), "V3 factory copied");
        assertEq(address(gateway.ROUTER()), address(router), "gateway calls the new router");

        // Registries: new defaults allowed, outgoing ones disallowed, the raw router never allowed.
        assertEq(address(buybackRegistry.defaultHook()), address(buybackHook), "buyback default");
        assertTrue(buybackRegistry.isHookAllowed(IJBRulesetDataHook(address(buybackHook))), "new hook allowed");
        assertFalse(
            buybackRegistry.isHookAllowed(IJBRulesetDataHook(address(harness.oldBuybackHook()))), "old hook retired"
        );
        assertEq(address(routerRegistry.defaultTerminal()), address(gateway), "router default");
        assertTrue(routerRegistry.isTerminalAllowed(IJBTerminal(address(gateway))), "new gateway allowed");
        assertFalse(routerRegistry.isTerminalAllowed(IJBTerminal(address(harness.oldGateway()))), "old gateway retired");
        assertFalse(routerRegistry.isTerminalAllowed(IJBTerminal(address(router))), "raw router never selectable");

        // Project 1 moved; an unmigrated revnet keeps its outgoing contracts.
        assertEq(address(buybackRegistry.hookOf(_FEE_PROJECT_ID)), address(buybackHook), "project 1 hook");
        assertEq(address(routerRegistry.terminalOf(_FEE_PROJECT_ID)), address(gateway), "project 1 router");
        assertEq(
            address(buybackRegistry.hookOf(_UNMIGRATED_PROJECT_ID)),
            address(harness.oldBuybackHook()),
            "project 7 keeps its hook"
        );
        assertEq(
            address(routerRegistry.terminalOf(_UNMIGRATED_PROJECT_ID)),
            address(harness.oldGateway()),
            "project 7 keeps its router"
        );

        // Project 1's pool lives on the new V4 hook and starts at the issuance weight.
        PoolKey memory key = buybackHook.poolKeyOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)});
        assertEq(address(key.hooks), address(univ4Hook), "pool on the new V4 hook");
        assertEq(key.fee, 10_000, "pool fee");
        assertEq(key.tickSpacing, 200, "pool tick spacing");
        assertEq(
            buybackHook.twapWindowOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)}), 30 minutes, "window"
        );
        (uint160 sqrtPriceX96,,,) = IPoolManager(harness.poolManager()).getSlot0(key.toId());
        (, uint160 expected) = harness.feeProjectPoolSqrtPriceX96();
        assertEq(sqrtPriceX96, expected, "pool starts at the computed price");
        (uint256 weight,) = _issuancePerEth();
        assertApproxEqRel(
            FullMath.mulDiv(uint256(sqrtPriceX96) * sqrtPriceX96, 1e18, 1 << 192),
            weight,
            1e12,
            "the pool starts at the issuance weight per ETH, as REVDeployer seeds revnet pools"
        );
    }

    function test_rerunIsANoOp() public {
        harness.rehearse();

        vm.startStateDiffRecording();
        harness.rehearse();
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        for (uint256 i; i < accesses.length; i++) {
            VmSafe.AccountAccess memory access = accesses[i];
            assertTrue(access.kind != VmSafe.AccountAccessKind.Create, "second run must not deploy anything");
            // The harness itself lives at the Safe and rewrites its own loaded addresses; nothing else may change.
            if (access.account == _SAFE) continue;
            for (uint256 j; j < access.storageAccesses.length; j++) {
                assertFalse(access.storageAccesses[j].isWrite, "second run must not write any protocol state");
            }
        }
    }

    /// @notice Someone initializes project 1's pool between the V4 hook's deploy and the pool step, at another
    /// price. The proposal registers the pool as it is instead of reverting on `initializePoolFor`'s price check.
    function test_frontRunPoolIsRegisteredAsIs() public {
        // Learn the V4 hook's address and code, then rewind to before the proposal.
        uint256 snapshot = vm.snapshotState();
        harness.rehearse();
        address univ4Hook = address(harness.univ4Hook());
        bytes memory univ4HookCode = univ4Hook.code;
        PoolKey memory key = harness.buybackHook().poolKeyOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)});
        IPoolManager manager = IPoolManager(harness.poolManager());
        vm.revertToState(snapshot);

        // The hook exists (its immutables live in its code), and an outsider initializes the pool first.
        vm.etch(univ4Hook, univ4HookCode);
        uint160 otherPrice = TickMath.getSqrtPriceAtTick(0);
        manager.initialize(key, otherPrice);

        harness.rehearse();

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(key.toId());
        assertEq(sqrtPriceX96, otherPrice, "the existing price stands");
        PoolKey memory registered =
            harness.buybackHook().poolKeyOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)});
        assertEq(PoolId.unwrap(registered.toId()), PoolId.unwrap(key.toId()), "the existing pool is registered");
    }

    /// @notice With the new pool still empty, a pay through the router registry reaches the gateway and new router
    /// and mints the payer's share of issuance.
    function test_payThroughTheRouterRegistryMintsWhileThePoolIsEmpty() public {
        harness.rehearse();
        JBRouterTerminalRegistry registry = harness.routerRegistry();
        vm.deal(payer, 1 ether);

        vm.prank(payer);
        uint256 received = registry.pay{value: 1 ether}({
            projectId: _FEE_PROJECT_ID,
            token: JBConstants.NATIVE_TOKEN,
            amount: 1 ether,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        (, uint256 payerShare) = _issuancePerEth();
        assertEq(received, payerShare, "minted the payer's share of issuance");
        assertEq(address(harness.gateway()).balance, 0, "a settled route leaves nothing in custody");
    }

    /// @notice Once project 1's new pool has liquidity, direct Uniswap trades go through the 2.0.0 hook, and a pay
    /// through the terminal sees the pool through the 2.0.0 buyback hook.
    function test_newPoolTradesThroughTheNewHooks() public {
        harness.rehearse();
        IPoolManager manager = IPoolManager(harness.poolManager());
        PoolKey memory key = harness.buybackHook().poolKeyOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)});
        IERC20 nana = IERC20(Currency.unwrap(key.currency1));
        (uint256 weight, uint256 payerShare) = _issuancePerEth();

        // Seed liquidity around the starting price, with tokens minted by paying the project.
        PoolModifyLiquidityTest lp = new PoolModifyLiquidityTest(manager);
        _mintNana(address(this), 20 ether);
        nana.approve(address(lp), type(uint256).max);
        (, int24 tick,,) = manager.getSlot0(key.toId());
        tick = tick / 200 * 200;
        lp.modifyLiquidity{value: 20 ether}(
            key,
            ModifyLiquidityParams({tickLower: tick - 4000, tickUpper: tick + 4000, liquidityDelta: 1e21, salt: 0}),
            ""
        );

        PoolSwapTest swapper = new PoolSwapTest(manager);
        nana.approve(address(swapper), type(uint256).max);

        // A direct buy never gets less than minting the whole input.
        uint256 nanaBefore = nana.balanceOf(address(this));
        swapper.swap{value: 0.1 ether}(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -0.1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        uint256 bought = nana.balanceOf(address(this)) - nanaBefore;
        assertGe(bought, payerShare / 10, "a direct buy gets at least what minting gives the payer");

        // Selling pushes the pool above the weight (more tokens per ETH), so the next pay should buy from it.
        uint256 ethBefore = address(this).balance;
        swapper.swap(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -int256(5000 ether), sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        assertGt(address(this).balance, ethBefore, "a direct sell pays ETH");
        // The oracle writes one observation per block and reports coverage from its second one, so trade once in a
        // later block, then wait out the TWAP window so the buyback hook's oracle sees the moved price.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 2);
        swapper.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 31 minutes);

        vm.deal(payer, 0.01 ether);
        vm.prank(payer);
        uint256 paid = harness.terminal().pay{value: 0.01 ether}({
            projectId: _FEE_PROJECT_ID,
            token: JBConstants.NATIVE_TOKEN,
            amount: 0.01 ether,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
        assertGt(paid, payerShare / 100, "the buyback hook bought from the pool, beating the mint");
    }

    receive() external payable {}

    // ── helpers ──

    function _mintNana(address beneficiary, uint256 ethAmount) internal {
        harness.terminal().pay{value: ethAmount}({
            projectId: _FEE_PROJECT_ID,
            token: JBConstants.NATIVE_TOKEN,
            amount: ethAmount,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
    }

    /// @notice Project 1's issuance per ETH, read straight from the ruleset (its base currency is ETH), and the
    /// payer's share of it after the reserved split.
    function _issuancePerEth() internal view returns (uint256 weight, uint256 payerShare) {
        (JBRuleset memory ruleset, JBRulesetMetadata memory metadata) =
            IJBController(address(_directory().controllerOf(_FEE_PROJECT_ID))).currentRulesetOf(_FEE_PROJECT_ID);
        assertEq(metadata.baseCurrency, JBCurrencyIds.ETH, "project 1 is priced in ETH");
        weight = ruleset.weight;
        payerShare =
            weight * (JBConstants.MAX_RESERVED_PERCENT - metadata.reservedPercent) / JBConstants.MAX_RESERVED_PERCENT;
    }

    function _directory() internal view returns (IJBDirectory) {
        return IJBDirectory(_liveAddressOf("JBDirectory"));
    }

    function _liveAddressOf(string memory name) internal view returns (address) {
        return vm.readFile(string.concat("deployments/base/", name, ".json")).readAddress(".address");
    }
}
