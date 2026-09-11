// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalGateway} from "@bananapus/router-terminal-v6/src/JBRouterTerminalGateway.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";

import {BuybackFloorFixBase} from "../../script/DeployBuybackFloorFix.s.sol";
import {VerifyBuybackFloorFix} from "../../script/VerifyBuybackFloorFix.s.sol";

/// @notice Runs the whole proposal body, Sphinx-free. Its code is etched over the infra Safe so every call it makes
/// comes from the Safe: the registry owner, the router's one-shot deployer, and project 1's operator.
contract BuybackFloorFixRehearsalHarness is BuybackFloorFixBase {
    function rehearse(address outgoingRouter) external {
        _setupChainAddresses();
        _loadCoreDeploymentAddresses();
        _loadBuybackDeploymentAddresses();
        // The fork rehearses the original proposal against its historical outgoing router. Canonical deployment
        // records now describe the production successor, which did not exist at the pinned fork block.
        _oldRouterTerminal = JBRouterTerminal(payable(outgoingRouter));
        _deployFloorFix();
    }

    function newBuybackHook() external view returns (JBBuybackHook) {
        return _newBuybackHook;
    }

    function newRouterTerminal() external view returns (JBRouterTerminal) {
        return _newRouterTerminal;
    }

    function gateway() external view returns (JBRouterTerminalGateway) {
        return _gateway;
    }

    function oldRouterTerminal() external view returns (JBRouterTerminal) {
        return _oldRouterTerminal;
    }

    function routerRegistry() external view returns (JBRouterTerminalRegistry) {
        return _routerRegistry;
    }

    function buybackRegistry() external view returns (JBBuybackHookRegistry) {
        return _buybackRegistry;
    }

    function oracleHook() external view returns (address) {
        return _oracleHook;
    }

    function poolManager() external view returns (address) {
        return _poolManager;
    }
}

/// @notice Operator-mode verification without `vm.setEnv`, which is process-global and would leak into sibling tests.
contract VerifyBuybackFloorFixOperatorsHarness is VerifyBuybackFloorFix {
    function runAsOperators() external {
        _verifyOperators = true;
        _run();
    }
}

/// @notice Rehearses the buyback floor fix + router gateway proposal against live Base: the existing registry, the
/// REVOwner-owned fee project, and the infra Safe's real permissions. Proves the proposal deploys and wires the
/// `Registry -> Gateway -> Router(new hook)` graph, is a no-op when rerun, routes a USDC fee through it, and never
/// lets an underfunded USDC fee be forgiven. Requires `npm run artifacts` (CI does this) + RPC_BASE_MAINNET.
contract DeployBuybackFloorFixForkTest is Test {
    using stdJson for string;

    address internal constant _SAFE = 0x4dc161eF837fF1C4485b08DDFcDB182F2157bE18;
    address internal constant _USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint256 internal constant _FEE_PROJECT_ID = 1;
    string internal constant _FORK_FIXTURE = "test/fixtures/buyback-floor-fix/base-before-rollout.json";

    BuybackFloorFixRehearsalHarness internal harness;
    address internal outgoingRouter;
    address internal payer = makeAddr("payer");

    function setUp() public {
        string memory fixture = vm.readFile(_FORK_FIXTURE);
        vm.createSelectFork("base", fixture.readUint(".forkBlock"));
        assertEq(block.chainid, fixture.readUint(".chainId"), "fixture matches the fork chain");
        outgoingRouter = fixture.readAddress(".routerTerminal");
        assertGt(outgoingRouter.code.length, 0, "historical outgoing router exists at the fork block");
        assertEq(
            address(JBRouterTerminalRegistry(payable(_liveAddressOf("JBRouterTerminalRegistry"))).defaultTerminal()),
            outgoingRouter,
            "fixture matches the pre-rollout registry default"
        );
        vm.etch(_SAFE, address(new BuybackFloorFixRehearsalHarness()).code);
        vm.allowCheatcodes(_SAFE);
        harness = BuybackFloorFixRehearsalHarness(_SAFE);
    }

    function test_deploysAndWiresTheGatewayGraphOnTheExistingRegistry() public {
        address registryBefore = _liveAddressOf("JBRouterTerminalRegistry");
        address oldRouterBefore = outgoingRouter;

        harness.rehearse(outgoingRouter);

        JBRouterTerminalRegistry registry = harness.routerRegistry();
        JBRouterTerminal newRouter = harness.newRouterTerminal();
        JBRouterTerminal oldRouter = harness.oldRouterTerminal();
        JBRouterTerminalGateway gateway = harness.gateway();
        JBBuybackHook newHook = harness.newBuybackHook();

        // The registry is the one REVDeployer pins; nothing here may replace it.
        assertEq(address(registry), registryBefore, "registry must be reused, never redeployed");
        assertEq(address(oldRouter), oldRouterBefore, "outgoing router is the historical deployment record");

        // Fresh contracts, new addresses.
        assertTrue(address(newHook).code.length != 0, "new buyback hook deployed");
        assertTrue(address(newRouter).code.length != 0, "new router deployed");
        assertTrue(address(gateway).code.length != 0, "gateway deployed");
        assertTrue(address(newRouter) != address(oldRouter), "router is replaced, not reused");

        // The historical rehearsal must reproduce the contracts recorded by the executed production rollout.
        assertEq(address(newHook), _liveAddressOf("JBBuybackHook"), "hook matches the executed artifact");
        assertEq(address(newRouter), _liveAddressOf("JBRouterTerminal"), "router matches the executed artifact");
        assertEq(address(gateway), _liveAddressOf("JBRouterTerminalGateway"), "gateway matches the executed artifact");

        // Registry -> Gateway -> Router(new hook).
        assertEq(address(registry.defaultTerminal()), address(gateway), "registry default is the gateway");
        assertEq(address(registry.terminalOf(_FEE_PROJECT_ID)), address(gateway), "fee project pinned to gateway");
        assertEq(address(gateway.ROUTER()), address(newRouter), "gateway calls the new router");
        assertEq(newRouter.BUYBACK_HOOK(), address(newHook), "new router is bound to the new hook");

        // Chain wiring copied from the live router; V4 oracle hook reused.
        assertEq(address(newRouter.wrappedNativeToken()), address(oldRouter.wrappedNativeToken()), "WETH copied");
        assertEq(address(newRouter.factory()), address(oldRouter.factory()), "V3 factory copied");
        assertEq(address(newRouter.poolManager()), harness.poolManager(), "PoolManager wired");
        assertEq(address(newRouter.poolManager()), address(oldRouter.poolManager()), "PoolManager matches live");
        assertEq(newRouter.univ4Hook(), harness.oracleHook(), "live JBUniswapV4Hook reused");

        // Only the gateway is selectable: the raw router would skip custody, and the old router is retired.
        assertTrue(registry.isTerminalAllowed(IJBTerminal(address(gateway))), "gateway selectable");
        assertFalse(registry.isTerminalAllowed(IJBTerminal(address(newRouter))), "raw router never selectable");
        assertFalse(registry.isTerminalAllowed(IJBTerminal(address(oldRouter))), "old router retired");

        // The buyback side of the proposal is unchanged.
        JBBuybackHookRegistry buybackRegistry = harness.buybackRegistry();
        assertEq(address(buybackRegistry.defaultHook()), address(newHook), "buyback default is the new hook");
        assertEq(address(buybackRegistry.hookOf(_FEE_PROJECT_ID)), address(newHook), "fee project on new hook");
    }

    function test_rerunIsANoOp() public {
        harness.rehearse(outgoingRouter);

        vm.startStateDiffRecording();
        harness.rehearse(outgoingRouter);
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

    function test_usdcFeeRoutesThroughGatewayToTheNewRouter() public {
        harness.rehearse(outgoingRouter);
        JBRouterTerminalRegistry registry = harness.routerRegistry();
        JBRouterTerminalGateway gateway = harness.gateway();
        uint256 amount = 100e6;
        _fundPayer(amount);

        vm.prank(payer);
        uint256 received = registry.pay({
            projectId: _FEE_PROJECT_ID,
            token: _USDC,
            amount: amount,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });

        assertGt(received, 0, "the fee project issued tokens for the routed USDC");
        assertEq(IERC20(_USDC).balanceOf(payer), 0, "the whole payment left the payer");
        assertEq(IERC20(_USDC).balanceOf(address(gateway)), 0, "a settled route leaves nothing in custody");
        assertEq(gateway.pendingCallCount(), 0, "a settled route creates no pending call");
    }

    /// @notice The Base incident: a USDC protocol fee whose route ran out of gas was caught by core and forgiven.
    /// Under the gateway, every outcome of an underfunded fee call conserves the input: it settles, it is retained
    /// in custody with a pending record, or the call reverts and the payer keeps it. It is never forgiven.
    function test_underfundedUsdcFeeIsRetainedOrRevertedNeverForgiven() public {
        harness.rehearse(outgoingRouter);
        JBRouterTerminalRegistry registry = harness.routerRegistry();
        JBRouterTerminalGateway gateway = harness.gateway();
        uint256 amount = 100e6;
        _fundPayer(amount);

        // Exact source-project metadata is the escrow opt-in core's fee payers already send.
        bytes memory data = abi.encodeCall(
            IJBTerminal.pay, (_FEE_PROJECT_ID, _USDC, amount, payer, 0, "", abi.encodePacked(uint256(2)))
        );
        uint256[6] memory budgets = [uint256(300_000), 500_000, 700_000, 900_000, 1_200_000, 2_000_000];

        uint256 snapshot = vm.snapshotState();
        bool sawRetained;
        for (uint256 i; i < budgets.length; i++) {
            vm.prank(payer);
            (bool success,) = address(registry).call{gas: budgets[i]}(data);

            uint256 payerLeft = IERC20(_USDC).balanceOf(payer);
            uint256 custody = IERC20(_USDC).balanceOf(address(gateway));
            emit log_named_uint("budget", budgets[i]);
            emit log_named_string(
                "outcome", !success ? "reverted" : gateway.pendingCallCount() != 0 ? "retained" : "settled"
            );
            if (!success) {
                assertEq(payerLeft, amount, "a reverted call leaves the payer whole");
            } else if (gateway.pendingCallCount() != 0) {
                sawRetained = true;
                assertEq(custody, amount, "a retained fee sits fully in custody");
                assertTrue(
                    gateway.pendingCallCommitmentOf(bytes32(uint256(1))) != bytes32(0),
                    "a retained fee has a pending record"
                );
            } else {
                assertEq(payerLeft + custody, 0, "a settled fee neither stays with the payer nor in custody");
            }

            assertTrue(vm.revertToState(snapshot));
        }
        assertTrue(sawRetained, "the sweep should include a budget that reaches custody but not settlement");
    }

    /// @notice The post-proposal verifier must reject the chain before the proposal and accept it after, off the same
    /// records and artifacts the proposal used, so a signer can trust a green run.
    function test_verifierRejectsBeforeAndAcceptsAfterTheProposal() public {
        VerifyBuybackFloorFix verifier = new VerifyBuybackFloorFix();
        vm.allowCheatcodes(address(verifier));

        vm.expectRevert(
            abi.encodeWithSelector(
                VerifyBuybackFloorFix.VerifyBuybackFloorFix_CriticalCheckFailed.selector,
                "USDC-per-NATIVE ratio feed is deployed"
            )
        );
        verifier.run();

        harness.rehearse(outgoingRouter);
        verifier.run();
    }

    /// @notice Operator mode must stay red until projects 2-7 are actually migrated by their operators.
    function test_verifierOperatorModeRejectsUnmigratedProjects() public {
        harness.rehearse(outgoingRouter);
        VerifyBuybackFloorFixOperatorsHarness verifier = new VerifyBuybackFloorFixOperatorsHarness();
        vm.allowCheatcodes(address(verifier));

        vm.expectRevert(
            abi.encodeWithSelector(
                VerifyBuybackFloorFix.VerifyBuybackFloorFix_CriticalCheckFailed.selector,
                "project 2 uses the new buyback hook"
            )
        );
        verifier.runAsOperators();
    }

    function _fundPayer(uint256 amount) internal {
        // Resolve the spender before pranking: the getter is itself a call that would consume the prank.
        address registry = address(harness.routerRegistry());
        deal(_USDC, payer, amount);
        vm.prank(payer);
        IERC20(_USDC).approve(registry, amount);
    }

    function _liveAddressOf(string memory name) internal view returns (address) {
        return vm.readFile(string.concat("deployments/base/", name, ".json")).readAddress(".address");
    }
}
