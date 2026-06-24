// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";

import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBSplitGroupIds} from "@bananapus/core-v6/src/libraries/JBSplitGroupIds.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {TwapOracleUpgradeBase} from "./DeployTwapOracleUpgrade.s.sol";

/// @title VerifyTwapOracleUpgrade
/// @notice Read-only post-upgrade checks for the TWAP oracle upgrade.
/// @dev Run with `VERIFY_TWAP_UPGRADE_OPERATORS=true` after the project-operator Safe transactions execute.
contract VerifyTwapOracleUpgrade is TwapOracleUpgradeBase {
    error VerifyTwapOracleUpgrade_CriticalCheckFailed(string reason);

    bool private _verifyOperators;
    uint256 private _failed;
    uint256 private _passed;
    uint256 private _skipped;

    // ════════════════════════════════════════════════════════════════════
    //  Entry Point
    // ════════════════════════════════════════════════════════════════════

    function run() external {
        console.log("========================================");
        console.log("  Juicebox V6 TWAP Upgrade Verification");
        console.log("========================================");
        console.log("Chain ID", block.chainid);
        console.log("");

        _verifyOperators = vm.envOr({name: "VERIFY_TWAP_UPGRADE_OPERATORS", defaultValue: false});

        _setupChainAddresses();
        _loadExistingDeploymentAddresses();

        if (!_shouldDeployUniswapStack()) {
            _skip("TWAP upgrade skipped: no Uniswap V4 PositionManager configured for this chain");
            _printSummary();
            return;
        }

        _predictOrLoadUpgradeContracts();

        _verifyContractDeployments();
        _verifyContractWiring();
        _verifyRegistryState();
        _verifyFeeProjectState();
        _verifyProjectOperatorState();
        _printSummary();
    }

    // ════════════════════════════════════════════════════════════════════
    //  Infra Checks
    // ════════════════════════════════════════════════════════════════════

    function _verifyContractDeployments() internal {
        console.log("--- Contract Deployments ---");

        _check(address(_upgradeUniv4Hook).code.length != 0, "new JBUniswapV4Hook is deployed", true);
        _check(address(_upgradeBuybackHook).code.length != 0, "new JBBuybackHook is deployed", true);
        _check(address(_upgradeRouterTerminal).code.length != 0, "new JBRouterTerminal is deployed", true);
        _check(address(_upgradeLpSplitHook).code.length != 0, "new JBUniswapV4LPSplitHook is deployed", true);
        _check(
            address(_upgradeLpSplitHookDeployer).code.length != 0,
            "new JBUniswapV4LPSplitHookDeployer is deployed",
            true
        );
        _check(
            _upgradeUniv4Hook.MAX_TWAP_CARDINALITY() == 1801,
            "new JBUniswapV4Hook has 1801 observation cardinality cap",
            true
        );

        console.log("");
    }

    function _verifyContractWiring() internal {
        console.log("--- Contract Wiring ---");

        _check(
            address(_upgradeBuybackHook.poolManager()) == _poolManager,
            "buyback hook uses the canonical PoolManager",
            true
        );
        _check(
            address(_upgradeBuybackHook.oracleHook()) == address(_upgradeUniv4Hook),
            "buyback hook uses the new oracle hook",
            true
        );
        _check(
            address(_upgradeRouterTerminal.wrappedNativeToken()) == _wrappedNativeToken,
            "router terminal uses the canonical wrapped native token",
            true
        );
        _check(
            address(_upgradeRouterTerminal.factory()) == _v3Factory,
            "router terminal uses the canonical Uniswap V3 factory",
            true
        );
        _check(
            address(_upgradeRouterTerminal.poolManager()) == _poolManager,
            "router terminal uses the canonical PoolManager",
            true
        );
        _check(
            _upgradeRouterTerminal.univ4Hook() == address(_upgradeUniv4Hook),
            "router terminal uses the new oracle hook",
            true
        );
        _check(
            _upgradeRouterTerminal.BUYBACK_HOOK() == address(_upgradeBuybackHook),
            "router terminal points at the new buyback hook",
            true
        );
        _check(
            address(_upgradeLpSplitHookDeployer.hookImplementation()) == address(_upgradeLpSplitHook),
            "LP split hook deployer uses the new implementation",
            true
        );
        _check(
            address(_upgradeLpSplitHookDeployer.poolManager()) == _poolManager,
            "LP split hook deployer uses the canonical PoolManager",
            true
        );
        _check(
            address(_upgradeLpSplitHookDeployer.positionManager()) == _positionManager,
            "LP split hook deployer uses the canonical PositionManager",
            true
        );
        _check(
            address(_upgradeLpSplitHookDeployer.oracleHook()) == address(_upgradeUniv4Hook),
            "LP split hook deployer uses the new oracle hook",
            true
        );

        console.log("");
    }

    function _verifyRegistryState() internal {
        console.log("--- Registry State ---");

        _check(
            address(_buybackRegistry.defaultHook()) == address(_upgradeBuybackHook),
            "buyback registry default is the new hook",
            true
        );
        _check(
            _buybackRegistry.isHookAllowed(IJBRulesetDataHook(address(_upgradeBuybackHook))),
            "new buyback hook is allowed",
            true
        );
        if (address(_oldBuybackHook) != address(0) && address(_oldBuybackHook) != address(_upgradeBuybackHook)) {
            _check(
                !_buybackRegistry.isHookAllowed(IJBRulesetDataHook(address(_oldBuybackHook))),
                "old buyback hook is disallowed",
                true
            );
        }

        _check(
            address(_routerTerminalRegistry.defaultTerminal()) == address(_upgradeRouterTerminal),
            "router terminal registry default is the new terminal",
            true
        );
        _check(
            _routerTerminalRegistry.isTerminalAllowed(IJBTerminal(address(_upgradeRouterTerminal))),
            "new router terminal is allowed",
            true
        );
        if (address(_oldRouterTerminal) != address(0) && address(_oldRouterTerminal) != address(_upgradeRouterTerminal))
        {
            _check(
                !_routerTerminalRegistry.isTerminalAllowed(IJBTerminal(address(_oldRouterTerminal))),
                "old router terminal is disallowed",
                true
            );
            _check(
                !_feeless.isFeelessFor({addr: address(_oldRouterTerminal), projectId: 0, caller: address(0)}),
                "old router terminal is not globally feeless",
                true
            );
        }
        _check(
            !_feeless.isFeelessFor({addr: address(_upgradeRouterTerminal), projectId: 0, caller: address(0)}),
            "new router terminal is not globally feeless",
            true
        );

        console.log("");
    }

    function _verifyFeeProjectState() internal {
        console.log("--- Project 1 Admin State ---");
        _verifyProjectOperatorStateOf(_FEE_PROJECT_ID);
        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Operator-Safe Checks
    // ════════════════════════════════════════════════════════════════════

    function _verifyProjectOperatorState() internal {
        console.log("--- Project Operator State ---");

        if (!_verifyOperators) {
            _skip("project 2-7 operator checks skipped; set VERIFY_TWAP_UPGRADE_OPERATORS=true after Safe txs execute");
            console.log("");
            return;
        }

        uint256[] memory projectIds = _operatorProjectIds();
        for (uint256 i; i < projectIds.length; i++) {
            _verifyProjectOperatorStateOf(projectIds[i]);
        }

        _verifyBanLpSplitHookState();
        console.log("");
    }

    function _verifyProjectOperatorStateOf(uint256 projectId) internal {
        address controller = address(_directory.controllerOf(projectId));
        _check(controller != address(0), string.concat("project ", vm.toString(projectId), " has a controller"), true);

        _check(
            address(_buybackRegistry.hookOf(projectId)) == address(_upgradeBuybackHook),
            string.concat("project ", vm.toString(projectId), " uses the new buyback hook"),
            true
        );
        _check(
            address(_routerTerminalRegistry.terminalOf(projectId)) == address(_upgradeRouterTerminal),
            string.concat("project ", vm.toString(projectId), " uses the new router terminal"),
            true
        );

        address terminalToken = _terminalTokenFor(projectId);
        address normalizedTerminalToken = _normalizeTerminalToken(terminalToken);
        PoolKey memory key =
            _upgradeBuybackHook.poolKeyOf({projectId: projectId, terminalToken: normalizedTerminalToken});

        _check(
            address(key.hooks) == address(_upgradeUniv4Hook),
            string.concat("project ", vm.toString(projectId), " buyback pool uses the new oracle hook"),
            true
        );
        _check(
            key.fee == _DEFAULT_BUYBACK_POOL_FEE,
            string.concat("project ", vm.toString(projectId), " buyback pool fee is 10000"),
            true
        );
        _check(
            key.tickSpacing == _DEFAULT_BUYBACK_TICK_SPACING,
            string.concat("project ", vm.toString(projectId), " buyback pool tick spacing is 200"),
            true
        );
        _check(
            _poolKeyMatchesProjectPair({projectId: projectId, terminalToken: normalizedTerminalToken, key: key}),
            string.concat("project ", vm.toString(projectId), " buyback pool matches project/token pair"),
            true
        );
        _check(
            _upgradeBuybackHook.twapWindowOf({projectId: projectId, terminalToken: normalizedTerminalToken})
                == _DEFAULT_BUYBACK_TWAP_WINDOW,
            string.concat("project ", vm.toString(projectId), " buyback pool TWAP window is 2 days"),
            true
        );
    }

    function _verifyBanLpSplitHookState() internal {
        JBUniswapV4LPSplitHook hook = _banLpSplitHookForOperator();
        _check(address(hook).code.length != 0, "BAN LP split hook clone is deployed", true);
        _check(hook.feeProjectId() == _LP_SPLIT_HOOK_FEE_PROJECT_ID, "BAN LP split hook fee project is 1", true);
        _check(hook.feePercent() == _LP_SPLIT_HOOK_FEE_PERCENT, "BAN LP split hook fee percent is 2000", true);
        _check(
            address(hook.buybackHook()) == address(_buybackRegistry),
            "BAN LP split hook force-directs cash-outs through the buyback registry",
            true
        );
        _check(address(hook.poolManager()) == _poolManager, "BAN LP split hook uses the canonical PoolManager", true);
        _check(
            address(hook.positionManager()) == _positionManager,
            "BAN LP split hook uses the canonical PositionManager",
            true
        );
        _check(
            address(hook.oracleHook()) == address(_upgradeUniv4Hook), "BAN LP split hook uses the new oracle hook", true
        );

        address controller = address(_directory.controllerOf(_BAN_PROJECT_ID));
        (JBRuleset memory ruleset,) = IJBController(controller).currentRulesetOf(_BAN_PROJECT_ID);
        JBSplit[] memory splits = _splits.splitsOf({
            projectId: _BAN_PROJECT_ID, rulesetId: ruleset.id, groupId: JBSplitGroupIds.RESERVED_TOKENS
        });

        bool routed;
        for (uint256 i; i < splits.length; i++) {
            if (
                address(splits[i].hook) == address(hook) && splits[i].percent == JBConstants.SPLITS_TOTAL_PERCENT
                    && splits[i].projectId == 0 && splits[i].beneficiary == address(0) && !splits[i].preferAddToBalance
            ) {
                routed = true;
                break;
            }
        }
        _check(routed, "BAN reserved split routes 100% to the LP split hook clone", true);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Helpers
    // ════════════════════════════════════════════════════════════════════

    function _check(bool condition, string memory label, bool critical) internal {
        if (condition) {
            _passed++;
            console.log(string.concat("  [PASS] ", label));
        } else {
            _failed++;
            console.log(string.concat("  [FAIL] ", label));
            if (critical) revert VerifyTwapOracleUpgrade_CriticalCheckFailed(label);
        }
    }

    function _poolKeyMatchesProjectPair(
        uint256 projectId,
        address terminalToken,
        PoolKey memory key
    )
        internal
        view
        returns (bool)
    {
        address projectToken = address(_tokens.tokenOf(projectId));
        address currency0 = Currency.unwrap(key.currency0);
        address currency1 = Currency.unwrap(key.currency1);
        return projectToken != address(0)
            && ((currency0 == projectToken && currency1 == terminalToken)
                || (currency0 == terminalToken && currency1 == projectToken));
    }

    function _printSummary() internal view {
        console.log("========================================");
        console.log("            VERIFICATION SUMMARY         ");
        console.log("========================================");
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
