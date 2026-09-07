// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";

import {IJBFeelessAddresses} from "@bananapus/core-v6/src/interfaces/IJBFeelessAddresses.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalGateway} from "@bananapus/router-terminal-v6/src/JBRouterTerminalGateway.sol";

import {BuybackFloorFixBase} from "./DeployBuybackFloorFix.s.sol";
import {JBChainTokens} from "./libraries/JBChainTokens.sol";

/// @title VerifyBuybackFloorFix
/// @notice Read-only post-proposal checks for the buyback floor fix + router gateway rollout. Resolves every address
/// the same way the proposal did (deployment records for what it reused, CREATE2 predictions off the artifacts for
/// what it deployed), so it needs no env beyond the RPC. Run with `VERIFY_FLOOR_FIX_OPERATORS=true` after the
/// project-operator Safe transactions for projects 2-7 execute.
contract VerifyBuybackFloorFix is BuybackFloorFixBase {
    error VerifyBuybackFloorFix_CriticalCheckFailed(string reason);

    IJBFeelessAddresses internal _feeless;
    address internal _feed;
    bool internal _verifyOperators;
    uint256 private _failed;
    uint256 private _passed;
    uint256 private _skipped;

    // ════════════════════════════════════════════════════════════════════
    //  Entry Point
    // ════════════════════════════════════════════════════════════════════

    function run() external {
        _verifyOperators = vm.envOr({name: "VERIFY_FLOOR_FIX_OPERATORS", defaultValue: false});
        _run();
    }

    /// @notice The checks, with the operator flag already decided so a rehearsal can set it without touching env.
    function _run() internal {
        console.log("==============================================");
        console.log("  Juicebox V6 Buyback Floor Fix Verification");
        console.log("==============================================");
        console.log("Chain ID", block.chainid);
        console.log("");

        _setupChainAddresses();
        _loadCoreDeploymentAddresses();
        _verifyPriceFeeds();

        if (!_shouldDeployUniswapStack()) {
            _verifyFeedsOnlyChain();
            _printSummary();
            return;
        }

        _loadBuybackDeploymentAddresses();
        _feeless = IJBFeelessAddresses(_deploymentAddressOf("JBFeelessAddresses"));
        _predictDeployedContracts();

        _verifyContractDeployments();
        _verifyContractWiring();
        _verifyRegistryState();
        _verifyFeeProjectState();
        _verifyProjectOperatorState();
        _printSummary();
    }

    // ════════════════════════════════════════════════════════════════════
    //  Address Resolution
    // ════════════════════════════════════════════════════════════════════

    /// @notice The proposal's contracts at the addresses the proposal itself predicts. `_oldBuybackHook` is what the
    /// registry served before the proposal only until the proposal runs; afterwards the registry default IS the new
    /// hook, so the retired hook is recovered from the deployment record the proposal replaced.
    function _predictDeployedContracts() internal {
        (address hook,) = _isDeployed({
            salt: _BUYBACK_HOOK_SALT, creationCode: _loadArtifact("JBBuybackHook"), arguments: _buybackHookCtorArgs()
        });
        _newBuybackHook = JBBuybackHook(payable(hook));
        if (address(_oldBuybackHook) == address(_newBuybackHook)) {
            _oldBuybackHook = JBBuybackHook(payable(_optionalDeploymentAddressOf("JBBuybackHook_deprecated")));
        }

        (address routerTerminal,) = _isDeployed({
            salt: _ROUTER_TERMINAL_SALT,
            creationCode: _loadArtifact("JBRouterTerminal"),
            arguments: _routerTerminalCtorArgs(hook)
        });
        _newRouterTerminal = JBRouterTerminal(payable(routerTerminal));
        if (address(_oldRouterTerminal) == address(_newRouterTerminal)) {
            _oldRouterTerminal = JBRouterTerminal(payable(_optionalDeploymentAddressOf("JBRouterTerminal_deprecated")));
        }

        (address gateway,) = _isDeployed({
            salt: _ROUTER_TERMINAL_GATEWAY_SALT,
            creationCode: _loadArtifact("JBRouterTerminalGateway"),
            arguments: _routerTerminalGatewayCtorArgs(routerTerminal)
        });
        _gateway = JBRouterTerminalGateway(payable(gateway));
    }

    /// @notice A deployment record that may legitimately be absent, such as a `_deprecated` copy before the first
    /// artifact distribution.
    function _optionalDeploymentAddressOf(string memory name) internal view returns (address) {
        string memory path = string.concat("deployments/", _chainFolder(), "/", name, ".json");
        if (!vm.exists(path)) return address(0);
        return _deploymentAddressOf(name);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Checks
    // ════════════════════════════════════════════════════════════════════

    function _verifyPriceFeeds() internal {
        console.log("--- Price Feeds ---");
        (bytes memory ctorArgs, bool available) = _usdcPerNativeFeedCtorArgs();
        if (!available) {
            _skip("USDC-per-NATIVE feed not composable on this chain (no canonical USDC or leg feed)");
            console.log("");
            return;
        }

        (_feed,) = _isDeployed({
            salt: _USDC_PER_NATIVE_FEED_SALT, creationCode: _loadArtifact("JBRatioPriceFeed"), arguments: ctorArgs
        });
        _check(_feed.code.length != 0, "USDC-per-NATIVE ratio feed is deployed", true);

        uint32 usdcCurrency = JBChainTokens.currencyIdOf(JBChainTokens.usdcTokenFor(block.chainid));
        _check(
            _defaultFeedFor({
                pricingCurrency: usdcCurrency, unitCurrency: JBChainTokens.currencyIdOf(JBConstants.NATIVE_TOKEN)
            }) == _feed,
            "project-0 default {USDC <- NATIVE} is the ratio feed",
            true
        );
        _check(
            _defaultFeedFor({pricingCurrency: usdcCurrency, unitCurrency: JBCurrencyIds.ETH}) == _feed,
            "project-0 default {USDC <- ETH} is the ratio feed",
            true
        );
        console.log("");
    }

    /// @notice OP Sepolia: the feeds above are the whole proposal; the registry must still have no router at all.
    function _verifyFeedsOnlyChain() internal {
        console.log("--- Feeds-Only Chain ---");
        address registry = _optionalDeploymentAddressOf("JBRouterTerminalRegistry");
        if (registry == address(0)) {
            _skip("no router terminal registry record on this chain");
            console.log("");
            return;
        }
        (bool ok, bytes memory data) = registry.staticcall(abi.encodeWithSignature("defaultTerminal()"));
        _check(
            ok && data.length >= 32 && abi.decode(data, (address)) == address(0),
            "router terminal registry default stays unset without a Uniswap stack",
            true
        );
        console.log("");
    }

    function _verifyContractDeployments() internal {
        console.log("--- Contract Deployments ---");
        _check(address(_newBuybackHook).code.length != 0, "new JBBuybackHook is deployed", true);
        _check(address(_newRouterTerminal).code.length != 0, "new JBRouterTerminal is deployed", true);
        _check(address(_gateway).code.length != 0, "JBRouterTerminalGateway is deployed", true);
        _check(
            address(_newRouterTerminal) != address(_oldRouterTerminal),
            "new router terminal is not the retired one",
            true
        );
        console.log("");
    }

    function _verifyContractWiring() internal {
        console.log("--- Contract Wiring ---");
        _check(address(_newBuybackHook.poolManager()) == _poolManager, "new hook uses the canonical PoolManager", true);
        _check(
            address(_newBuybackHook.oracleHook()) == _oracleHook, "new hook uses the live JBUniswapV4Hook oracle", true
        );

        _check(_newRouterTerminal.BUYBACK_HOOK() == address(_newBuybackHook), "router is bound to the new hook", true);
        _check(address(_newRouterTerminal.poolManager()) == _poolManager, "router uses the canonical PoolManager", true);
        _check(_newRouterTerminal.univ4Hook() == _oracleHook, "router uses the live JBUniswapV4Hook oracle", true);
        if (address(_oldRouterTerminal) != address(0)) {
            _check(
                address(_newRouterTerminal.wrappedNativeToken()) == address(_oldRouterTerminal.wrappedNativeToken()),
                "router WETH matches the retired router",
                true
            );
            _check(
                address(_newRouterTerminal.factory()) == address(_oldRouterTerminal.factory()),
                "router V3 factory matches the retired router",
                true
            );
        } else {
            _skip("router WETH/V3 factory comparison (no retired router record)");
        }
        _check(address(_newRouterTerminal.wrappedNativeToken()) != address(0), "router WETH is wired", true);

        _check(address(_gateway.ROUTER()) == address(_newRouterTerminal), "gateway calls the new router", true);
        _check(address(_gateway.DIRECTORY()) == address(_directory), "gateway uses the canonical directory", true);
        console.log("");
    }

    function _verifyRegistryState() internal {
        console.log("--- Registry State ---");
        _check(
            address(_buybackRegistry.defaultHook()) == address(_newBuybackHook),
            "buyback registry default is the new hook",
            true
        );
        if (address(_oldBuybackHook) != address(0) && address(_oldBuybackHook) != address(_newBuybackHook)) {
            _check(
                !_buybackRegistry.isHookAllowed(IJBRulesetDataHook(address(_oldBuybackHook))),
                "old buyback hook is disallowed",
                true
            );
        } else {
            _skip("old buyback hook disallow check (no retired hook record)");
        }

        _check(
            address(_routerRegistry.defaultTerminal()) == address(_gateway),
            "router terminal registry default is the gateway",
            true
        );
        _check(
            !_routerRegistry.isTerminalAllowed(IJBTerminal(address(_newRouterTerminal))),
            "raw router terminal is not selectable",
            true
        );
        if (address(_oldRouterTerminal) != address(0)) {
            _check(
                !_routerRegistry.isTerminalAllowed(IJBTerminal(address(_oldRouterTerminal))),
                "old router terminal is disallowed",
                true
            );
        } else {
            _skip("old router terminal disallow check (no retired router record)");
        }
        _check(
            !_feeless.isFeelessFor({addr: address(_newRouterTerminal), projectId: 0, caller: address(0)}),
            "new router terminal is not globally feeless",
            true
        );
        _check(
            !_feeless.isFeelessFor({addr: address(_gateway), projectId: 0, caller: address(0)}),
            "gateway is not globally feeless",
            true
        );
        console.log("");
    }

    function _verifyFeeProjectState() internal {
        console.log("--- Fee Project State ---");
        _check(
            address(_buybackRegistry.hookOf(_FEE_PROJECT_ID)) == address(_newBuybackHook),
            "project 1 uses the new buyback hook",
            true
        );
        _check(
            _newBuybackHook.twapWindowOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)})
                == _FEE_PROJECT_TWAP_WINDOW,
            "project 1 buyback pool carried over with the 30-minute TWAP window",
            true
        );
        // The carried-over pool is the live one: it trades against the oracle hook every other buyback pool uses.
        PoolKey memory key = _newBuybackHook.poolKeyOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)});
        _check(address(key.hooks) == _oracleHook, "project 1 buyback pool uses the live JBUniswapV4Hook oracle", true);
        _check(
            address(_routerRegistry.terminalOf(_FEE_PROJECT_ID)) == address(_gateway),
            "project 1 uses the gateway",
            true
        );
        console.log("");
    }

    function _verifyProjectOperatorState() internal {
        console.log("--- Project Operator State ---");
        if (!_verifyOperators) {
            _skip("project 2-7 operator checks skipped; set VERIFY_FLOOR_FIX_OPERATORS=true after Safe txs execute");
            console.log("");
            return;
        }
        uint256 count = _projects.count();
        bool includeArtProject = block.chainid == 8453 || block.chainid == 84_532;
        for (uint256 projectId = 2; projectId <= 7 && projectId <= count; projectId++) {
            if (projectId == 6 && !includeArtProject) continue;
            _check(
                address(_buybackRegistry.hookOf(projectId)) == address(_newBuybackHook),
                string.concat("project ", vm.toString(projectId), " uses the new buyback hook"),
                true
            );
            _check(
                address(_routerRegistry.terminalOf(projectId)) == address(_gateway),
                string.concat("project ", vm.toString(projectId), " uses the gateway"),
                true
            );
        }
        console.log("");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Helpers
    // ════════════════════════════════════════════════════════════════════

    function _defaultFeedFor(uint256 pricingCurrency, uint256 unitCurrency) internal view returns (address) {
        return address(
            _prices.priceFeedFor({
                projectId: _DEFAULT_PROJECT_ID, pricingCurrency: pricingCurrency, unitCurrency: unitCurrency
            })
        );
    }

    function _check(bool condition, string memory label, bool critical) internal {
        if (condition) {
            _passed++;
            console.log(string.concat("  [PASS] ", label));
        } else {
            _failed++;
            console.log(string.concat("  [FAIL] ", label));
            if (critical) revert VerifyBuybackFloorFix_CriticalCheckFailed(label);
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
