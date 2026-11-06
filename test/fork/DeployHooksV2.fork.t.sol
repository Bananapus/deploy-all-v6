// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalGateway} from "@bananapus/router-terminal-v6/src/JBRouterTerminalGateway.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";

import {HooksV2Base} from "../../script/DeployHooksV2.s.sol";
import {JBArtifactVersions} from "../../script/libraries/JBArtifactVersions.sol";

interface ILpSplitHookDeployerState {
    function oracleHook() external view returns (address);
    function poolManager() external view returns (address);
}

/// @notice Runs the whole proposal body, Sphinx-free. Its code is etched over the infra Safe so every call it makes
/// comes from the Safe: both registries' owner, the hooks' and router's one-shot deployer, and project 1's operator.
contract HooksV2RehearsalHarness is HooksV2Base {
    function rehearse() external {
        _requireArtifactVersions();
        _setupChainAddresses();
        _loadDeploymentAddresses();
        _deployHooksV2();
    }

    function requireArtifactVersion(string calldata artifact, string calldata expected) external view {
        JBArtifactVersions.requireVersion({artifact: artifact, expected: expected});
    }
}

/// @notice Checks the executed hooks 2.0.0 rollout against live chain state and the current records: the records name
/// what is deployed, the registries and project 1 point at it, the outgoing hook and gateway are disallowed, and
/// rerunning the proposal changes nothing. Runs on `HOOKS_V2_FORK` (a `deployments/` chain directory, default `base`),
/// at the latest block. Requires artifacts built from the releases the script names (`npm run artifacts`) and that
/// chain's RPC.
contract DeployHooksV2ForkTest is Test {
    using stdJson for string;

    address internal constant _SAFE = 0x4dc161eF837fF1C4485b08DDFcDB182F2157bE18;
    uint256 internal constant _FEE_PROJECT_ID = 1;

    string internal _network;
    HooksV2RehearsalHarness internal harness;

    function setUp() public {
        _network = vm.envOr("HOOKS_V2_FORK", string("base"));
        // Records live under `sepolia`; its RPC alias is `ethereum_sepolia`.
        vm.createSelectFork(keccak256(bytes(_network)) == keccak256("sepolia") ? string("ethereum_sepolia") : _network);
        vm.etch(_SAFE, address(new HooksV2RehearsalHarness()).code);
        vm.allowCheatcodes(_SAFE);
        harness = HooksV2RehearsalHarness(_SAFE);
    }

    /// @notice The script deploys only artifacts built from the releases it names, so stale artifacts cannot put
    /// older code under the 2.0.0 salts.
    function test_refusesArtifactsFromAnotherRelease() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                JBArtifactVersions.JBArtifactVersions_UnexpectedVersion.selector, "JBBuybackHook", "1.4.1", "2.0.0"
            )
        );
        harness.requireArtifactVersion({artifact: "JBBuybackHook", expected: "1.4.1"});
    }

    function test_liveStateMatchesTheRollout() public view {
        JBBuybackHook buybackHook = JBBuybackHook(payable(_recordOf("JBBuybackHook")));
        JBRouterTerminal router = JBRouterTerminal(payable(_recordOf("JBRouterTerminal")));
        JBRouterTerminalGateway gateway = JBRouterTerminalGateway(payable(_recordOf("JBRouterTerminalGateway")));
        address univ4Hook = _recordOf("JBUniswapV4Hook");
        IJBBuybackHookRegistry buybackRegistry = IJBBuybackHookRegistry(_recordOf("JBBuybackHookRegistry"));
        JBRouterTerminalRegistry routerRegistry =
            JBRouterTerminalRegistry(payable(_recordOf("JBRouterTerminalRegistry")));

        // The records name what the rollout deployed and wired together.
        assertGt(address(buybackHook.oracleHook()).code.length, 0, "buyback hook reads a deployed V4 hook");
        assertEq(address(buybackHook.oracleHook()), univ4Hook, "buyback hook reads the recorded V4 hook");
        assertEq(router.BUYBACK_HOOK(), address(buybackHook), "router is bound to the recorded buyback hook");
        assertEq(address(gateway.ROUTER()), address(router), "gateway fronts the recorded router");
        ILpSplitHookDeployerState lpDeployer = ILpSplitHookDeployerState(_recordOf("JBUniswapV4LPSplitHookDeployer"));
        assertEq(lpDeployer.oracleHook(), univ4Hook, "LP split hook deployer reads the recorded V4 hook");
        assertEq(
            JBUniswapV4LPSplitHook(payable(_recordOf("JBP6FeeLPSplitHook"))).feeProjectId(),
            _FEE_PROJECT_ID,
            "the shared LP split hook instance pays project 1"
        );

        // Defaults and project 1.
        assertEq(address(buybackRegistry.defaultHook()), address(buybackHook), "default buyback hook");
        assertEq(address(buybackRegistry.hookOf(_FEE_PROJECT_ID)), address(buybackHook), "project 1 buyback hook");
        assertEq(address(routerRegistry.defaultTerminal()), address(gateway), "default router terminal");
        assertEq(address(routerRegistry.terminalOf(_FEE_PROJECT_ID)), address(gateway), "project 1 router terminal");

        // Project 1's ETH pool is registered on the new V4 hook, keyed under the hook's native address(0).
        PoolKey memory key = buybackHook.poolKeyOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)});
        assertEq(Currency.unwrap(key.currency0), address(0), "project 1 pool pairs native ETH");
        assertEq(
            Currency.unwrap(key.currency1),
            address(IJBTokens(_recordOf("JBTokens")).tokenOf(_FEE_PROJECT_ID)),
            "project 1 pool pairs NANA"
        );
        assertEq(address(key.hooks), univ4Hook, "project 1 pool is on the new V4 hook");
        assertEq(
            buybackHook.twapWindowOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)}),
            1800,
            "project 1 TWAP window"
        );

        // The generation the rollout replaced can no longer be selected.
        assertFalse(
            buybackRegistry.isHookAllowed(IJBRulesetDataHook(_previousRecordOf("JBBuybackHook"))),
            "outgoing buyback hook disallowed"
        );
        assertFalse(
            routerRegistry.isTerminalAllowed(IJBTerminal(_previousRecordOf("JBRouterTerminalGateway"))),
            "outgoing gateway disallowed"
        );
    }

    /// @notice Rebuilding the proposal against the executed state deploys and writes nothing, so a rerun cannot
    /// disallow or replace the contracts it already moved everything onto.
    function test_rerunIsANoOp() public {
        vm.startStateDiffRecording();
        harness.rehearse();
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        for (uint256 i; i < accesses.length; i++) {
            VmSafe.AccountAccess memory access = accesses[i];
            assertTrue(access.kind != VmSafe.AccountAccessKind.Create, "rerun must not deploy anything");
            // The harness itself lives at the Safe and rewrites its own loaded addresses; nothing else may change.
            if (access.account == _SAFE) continue;
            for (uint256 j; j < access.storageAccesses.length; j++) {
                assertFalse(access.storageAccesses[j].isWrite, "rerun must not write any protocol state");
            }
        }
    }

    // ── helpers ──

    function _recordOf(string memory name) internal view returns (address) {
        return vm.readFile(string.concat("deployments/", _network, "/", name, ".json")).readAddress(".address");
    }

    /// @notice The record a rollout replaced is kept at the highest `_deprecatedN` suffix.
    function _previousRecordOf(string memory name) internal view returns (address previous) {
        string memory path = string.concat("deployments/", _network, "/", name, "_deprecated.json");
        for (uint256 n = 1; vm.exists(path); n++) {
            previous = vm.readFile(path).readAddress(".address");
            path = string.concat("deployments/", _network, "/", name, "_deprecated", vm.toString(n), ".json");
        }
    }
}
