// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";
import {JBUniswapV4LPSplitHookDeployer} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHookDeployer.sol";

import {Defifa1155Hook} from "@ballkidz/defifa/src/Defifa1155Hook.sol";
import {DefifaDeployer} from "@ballkidz/defifa/src/DefifaDeployer.sol";
import {DefifaGovernor} from "@ballkidz/defifa/src/DefifaGovernor.sol";
import {DefifaHook} from "@ballkidz/defifa/src/DefifaHook.sol";
import {DefifaTokenUriResolver} from "@ballkidz/defifa/src/DefifaTokenUriResolver.sol";
import {DefifaVotingReferee} from "@ballkidz/defifa/src/referees/DefifaVotingReferee.sol";

import {DefifaV2Addresses, DefifaV2Base} from "./DeployDefifaV2AndLpSplitHook.s.sol";

/// @title VerifyDefifaV2AndLpSplitHook
/// @notice Read-only post-proposal checks for the Defifa 2.0 + LP split hook 1.5.0 release. Resolves every address
/// the way the proposal did (deployment records for what it reused, CREATE2 predictions off the artifacts for what it
/// deployed), so it needs no env beyond the RPC. After the artifacts are emitted it also checks that each
/// `deployments/<chain>/` record points at the deployed address.
contract VerifyDefifaV2AndLpSplitHook is DefifaV2Base {
    using stdJson for string;

    error VerifyDefifaV2AndLpSplitHook_CriticalCheckFailed(string reason);

    uint256 private _failed;
    uint256 private _passed;
    uint256 private _skipped;

    // ════════════════════════════════════════════════════════════════════
    //  Entry Point
    // ════════════════════════════════════════════════════════════════════

    function run() external {
        console.log("==============================================");
        console.log("  Defifa 2.0 + LP Split Hook 1.5.0 Verification");
        console.log("==============================================");
        console.log("Chain ID", block.chainid);
        console.log("");

        _setupChainAddresses();
        _setupDefifaChainAddresses();
        bool lpChain = _shouldDeployLpStack();
        if (lpChain) _loadExistingDeploymentAddresses();
        _loadDefifaDeploymentAddresses();
        bool defifaChain = _shouldDeployDefifa();

        if (lpChain) {
            _verifyLpStack();
        } else {
            _skip("LP split hook stack (no V4 PositionManager on this chain)");
        }

        if (defifaChain) {
            _verifyDefifa(_predictAll(_EXPECTED_SAFE));
        } else {
            _skip("Defifa (no typeface or fee-project ERC-20 on this chain)");
        }

        _printSummary();
    }

    // ════════════════════════════════════════════════════════════════════
    //  LP split hook 1.5.0
    // ════════════════════════════════════════════════════════════════════

    function _verifyLpStack() internal {
        console.log("--- LP Split Hook 1.5.0 ---");
        (address mathLib, address hook, address deployer, address instance) = _predictLpAddresses();

        _checkDeployed({addr: mathLib, name: "JBUniswapV4LPSplitHookMath"});
        _checkDeployed({addr: hook, name: "JBUniswapV4LPSplitHook"});
        _checkDeployed({addr: deployer, name: "JBUniswapV4LPSplitHookDeployer"});
        _checkDeployed({addr: instance, name: "JBP6FeeLPSplitHook"});
        _check({condition: _codeContains(hook, mathLib), label: "hook links the math library", critical: true});

        JBUniswapV4LPSplitHookDeployer lpDeployer = JBUniswapV4LPSplitHookDeployer(deployer);
        _check({
            condition: address(lpDeployer.hookImplementation()) == hook,
            label: "deployer clones the 1.5.0 hook",
            critical: true
        });
        _check({
            condition: address(lpDeployer.poolManager()) == _poolManager, label: "deployer pool manager", critical: true
        });
        _check({
            condition: address(lpDeployer.positionManager()) == _positionManager,
            label: "deployer position manager",
            critical: true
        });
        _check({
            condition: address(lpDeployer.oracleHook()) == _oracleHook, label: "deployer oracle hook", critical: true
        });

        // The shared instance projects route LP splits to: the standard 10% of collected LP fees to project 1.
        JBUniswapV4LPSplitHook lpInstance = JBUniswapV4LPSplitHook(payable(instance));
        _check({
            condition: _addressRegistry.deployerOf(instance) == deployer,
            label: "instance registered to the 1.5.0 deployer",
            critical: true
        });
        _check({condition: lpInstance.feeProjectId() == 1, label: "instance fee project is 1", critical: true});
        _check({condition: lpInstance.feePercent() == 1000, label: "instance fee is 10%", critical: true});
        _check({
            condition: address(lpInstance.poolManager()) == _poolManager, label: "instance pool manager", critical: true
        });
        _check({
            condition: address(lpInstance.positionManager()) == _positionManager,
            label: "instance position manager",
            critical: true
        });
        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Defifa 2.0
    // ════════════════════════════════════════════════════════════════════

    function _verifyDefifa(DefifaV2Addresses memory a) internal {
        console.log("--- Defifa 2.0 ---");
        _checkDeployed({addr: a.hookLib, name: "DefifaHookLib"});
        _checkDeployed({addr: a.hookLib1155, name: "Defifa1155HookLib"});
        _checkDeployed({addr: a.store, name: "DefifaTiersHookStore"});
        _checkDeployed({addr: a.tokenUriResolver, name: "DefifaTokenUriResolver"});
        _checkDeployed({addr: a.hook, name: "DefifaHook"});
        _checkDeployed({addr: a.governor, name: "DefifaGovernor"});
        _checkDeployed({addr: a.deployer, name: "DefifaDeployer"});
        _checkDeployed({addr: a.hook1155, name: "Defifa1155Hook"});
        _checkDeployed({addr: a.governor1155, name: "Defifa1155Governor"});
        _checkDeployed({addr: a.deployer1155, name: "Defifa1155Deployer"});
        _checkDeployed({addr: a.referee, name: "DefifaVotingReferee"});

        _check({condition: _codeContains(a.hook, a.hookLib), label: "721 hook links DefifaHookLib", critical: true});
        _check({
            condition: _codeContains(a.hook1155, a.hookLib1155),
            label: "1155 hook links Defifa1155HookLib",
            critical: true
        });
        _check({
            condition: address(DefifaTokenUriResolver(a.tokenUriResolver).typeface()) == _typeface,
            label: "resolver typeface",
            critical: true
        });
        _check({
            condition: address(DefifaVotingReferee(a.referee).CONTROLLER()) == address(_controller),
            label: "voting referee controller",
            critical: true
        });
        _check({
            condition: DefifaHook(a.hook).CODE_ORIGIN() == a.hook,
            label: "721 hook is its own code origin",
            critical: true
        });
        _check({
            condition: Defifa1155Hook(a.hook1155).CODE_ORIGIN() == a.hook1155,
            label: "1155 hook is its own code origin",
            critical: true
        });

        _verifyGame({deployer: a.deployer, hook: a.hook, governor: a.governor, a: a, label: "721"});
        _verifyGame({deployer: a.deployer1155, hook: a.hook1155, governor: a.governor1155, a: a, label: "1155"});
        console.log("");
    }

    /// @notice One game type: its deployer clones `hook`, runs games through `governor`, and owns that governor.
    function _verifyGame(
        address deployer,
        address hook,
        address governor,
        DefifaV2Addresses memory a,
        string memory label
    )
        internal
    {
        DefifaDeployer gameDeployer = DefifaDeployer(deployer);
        _check({
            condition: gameDeployer.HOOK_CODE_ORIGIN() == hook,
            label: string.concat(label, " deployer hook code origin"),
            critical: true
        });
        _check({
            condition: address(gameDeployer.GOVERNOR()) == governor,
            label: string.concat(label, " deployer governor"),
            critical: true
        });
        _check({
            condition: address(gameDeployer.HOOK_STORE()) == a.store,
            label: string.concat(label, " deployer tier store"),
            critical: true
        });
        _check({
            condition: address(gameDeployer.TOKEN_URI_RESOLVER()) == a.tokenUriResolver,
            label: string.concat(label, " deployer token URI resolver"),
            critical: true
        });
        _check({
            condition: address(gameDeployer.CONTROLLER()) == address(_controller),
            label: string.concat(label, " deployer controller"),
            critical: true
        });
        _check({
            condition: gameDeployer.DEFIFA_PROJECT_ID() == _DEFIFA_REV_PROJECT_ID,
            label: string.concat(label, " deployer DEFIFA project"),
            critical: true
        });
        _check({
            condition: gameDeployer.BASE_PROTOCOL_PROJECT_ID() == _FEE_PROJECT_ID,
            label: string.concat(label, " deployer base protocol project"),
            critical: true
        });
        _check({
            condition: DefifaGovernor(governor).owner() == deployer,
            label: string.concat(label, " governor owned by its deployer"),
            critical: true
        });
        _check({
            condition: address(DefifaGovernor(governor).CONTROLLER()) == address(_controller),
            label: string.concat(label, " governor controller"),
            critical: true
        });
    }

    // ════════════════════════════════════════════════════════════════════
    //  Helpers
    // ════════════════════════════════════════════════════════════════════

    /// @notice `addr` has code, and its deployment record (once emitted) points at it.
    function _checkDeployed(address addr, string memory name) internal {
        _check({condition: addr.code.length != 0, label: string.concat(name, " is deployed"), critical: true});
        string memory path = string.concat("deployments/", _chainFolder(), "/", name, ".json");
        if (!vm.exists(path)) {
            _skip(string.concat(name, " deployment record not emitted yet"));
            return;
        }
        _check({
            condition: vm.readFile(path).readAddress(".address") == addr,
            label: string.concat(name, " deployment record matches"),
            critical: true
        });
    }

    /// @notice Whether `target`'s runtime code embeds `needle` (a linked library address).
    function _codeContains(address target, address needle) internal view returns (bool) {
        bytes memory code = target.code;
        bytes20 want = bytes20(needle);
        if (code.length < 20) return false;
        for (uint256 i; i <= code.length - 20; i++) {
            bytes20 window;
            // Read 32 bytes at `i`; the leading 20 are the window.
            assembly ("memory-safe") {
                window := mload(add(add(code, 32), i))
            }
            if (window == want) return true;
        }
        return false;
    }

    function _check(bool condition, string memory label, bool critical) internal {
        if (condition) {
            _passed++;
            console.log(string.concat("  [PASS] ", label));
        } else {
            _failed++;
            console.log(string.concat("  [FAIL] ", label));
            if (critical) revert VerifyDefifaV2AndLpSplitHook_CriticalCheckFailed(label);
        }
    }

    function _printSummary() internal view {
        console.log("==============================================");
        console.log("             VERIFICATION SUMMARY             ");
        console.log("==============================================");
        console.log("Passed", _passed);
        console.log("Failed", _failed);
        console.log("Skipped", _skipped);
        if (_failed == 0) {
            console.log("Result: ALL CHECKS PASSED");
        } else {
            console.log("Result: SOME CHECKS FAILED");
        }
    }

    function _skip(string memory label) internal {
        _skipped++;
        console.log(string.concat("  [SKIP] ", label));
    }
}
