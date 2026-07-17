// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";
import {JBUniswapV4LPSplitHookDeployer} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHookDeployer.sol";
import {LpSplitHookFixBase} from "../../script/DeployLpSplitHookFix.s.sol";

/// @notice Exposes the base's internal deploy steps for a fork run (no Sphinx harness).
contract LpSplitHookFixHarness is LpSplitHookFixBase {
    function setupAndLoad() external {
        _setupChainAddresses();
        _loadExistingDeploymentAddresses();
    }

    function deployMathLib() external returns (address) {
        return
            _deployPrecompiledIfNeeded({artifactName: "JBUniswapV4LPSplitHookMath", salt: _MATH_LIB_SALT, ctorArgs: ""});
    }

    function deployHookAndFactory() external {
        _lpSplitHook = JBUniswapV4LPSplitHook(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBUniswapV4LPSplitHook", salt: _LP_SPLIT_HOOK_SALT, ctorArgs: _lpSplitHookCtorArgs()
                }))
        );
        _lpSplitHookDeployer = JBUniswapV4LPSplitHookDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "JBUniswapV4LPSplitHookDeployer",
                salt: _LP_SPLIT_HOOK_DEPLOYER_SALT,
                ctorArgs: _lpSplitHookDeployerCtorArgs()
            })
        );
    }

    function poolManagerAddr() external view returns (address) {
        return _poolManager;
    }

    function positionManagerAddr() external view returns (address) {
        return _positionManager;
    }

    function oracleHookAddr() external view returns (address) {
        return _oracleHook;
    }

    function deployer() external view returns (JBUniswapV4LPSplitHookDeployer) {
        return _lpSplitHookDeployer;
    }

    function hook() external view returns (JBUniswapV4LPSplitHook) {
        return _lpSplitHook;
    }

    /// @notice Deploy the shared instance directly off the (already-configured) deployer, mirroring the script's
    /// params. Called via the harness (not the Safe), so it exercises deployHookFor's mechanics + init params rather
    /// than the Safe-folded deterministic address (which the production `sphinx` run and the mismatch guard cover).
    function deployInstanceDirect() external returns (JBUniswapV4LPSplitHook h) {
        h = JBUniswapV4LPSplitHook(
            payable(address(
                    _lpSplitHookDeployer.deployHookFor({
                        feeProjectId: _LP_SPLIT_HOOK_INSTANCE_FEE_PROJECT_ID,
                        feePercent: _LP_SPLIT_HOOK_INSTANCE_FEE_PERCENT,
                        buybackHook: _buybackRegistry,
                        salt: _LP_SPLIT_HOOK_INSTANCE_SALT
                    })
                ))
        );
    }
}

interface IDeployerState {
    function poolManager() external view returns (address);
    function positionManager() external view returns (address);
    function oracleHook() external view returns (address);
}

/// @notice Fork-simulates the LP-split-hook-fix deploy on a Base mainnet fork to guard the deploy MECHANICS:
/// deployment-JSON reads, constructor encoding, deterministic CREATE2, and the deployer's one-shot chain wiring.
/// The behavioral fix (findHighestValueTerminalTokenOf skipping store-less terminals like JBRouterTerminalRegistry)
/// is proven in the source repo by `test/regression/NonStoreTerminalSkip.t.sol`; here we prove the script deploys
/// that exact fixed stack and wires it. Requires `npm run artifacts` (CI does this) + RPC_BASE_MAINNET.
contract DeployLpSplitHookFixForkTest is Test {
    address internal constant _SAFE = 0x4dc161eF837fF1C4485b08DDFcDB182F2157bE18;

    LpSplitHookFixHarness internal harness;

    function setUp() public {
        vm.createSelectFork("base");
        harness = new LpSplitHookFixHarness();
        harness.setupAndLoad();
    }

    function test_deploysAndWires() public {
        address mathLib = harness.deployMathLib();
        harness.deployHookAndFactory();

        // Cache before pranking — each getter is itself a call that would otherwise consume the prank.
        JBUniswapV4LPSplitHookDeployer dep = harness.deployer();
        address pm = harness.poolManagerAddr();
        address posm = harness.positionManagerAddr();
        address oh = harness.oracleHookAddr();

        // The deployer's ctor pins its admin to _SAFE; the one-shot wiring call must come directly from it.
        vm.prank(_SAFE);
        dep.setChainSpecificConstants({
            newPoolManager: IPoolManager(pm), newPositionManager: IPositionManager(posm), newOracleHook: IHooks(oh)
        });

        // The linked math library lands at its deterministic (chain-independent) CREATE2 address — the same one the
        // build linker bakes into the rebuilt hook artifact. A mismatch means the hook would call an empty address.
        assertEq(mathLib, 0x734bfC66606DfE7943BCF541Cf5dcBC5312e695b, "math lib must match the link target");

        // Hook + deployer deployed, and the deployer wired to this chain's V4 stack + the live oracle hook.
        assertTrue(address(harness.hook()).code.length != 0, "hook implementation deployed");
        IDeployerState d = IDeployerState(address(dep));
        assertEq(d.poolManager(), pm, "poolManager wired");
        assertEq(d.positionManager(), posm, "positionManager wired");
        assertEq(d.oracleHook(), oh, "oracleHook = live JBUniswapV4Hook (reused, not redeployed)");

        // The shared instance projects use (JBP6FeeLPSplitHook): a clone of the freshly-deployed fixed implementation,
        // with the live instance's params. Must be a NEW address (not the old 0xae6705c3, which delegates to the buggy
        // implementation) and carry feeProjectId=1 / feePercent=2000.
        JBUniswapV4LPSplitHook instance = harness.deployInstanceDirect();
        assertTrue(address(instance).code.length != 0, "shared instance deployed");
        assertEq(instance.feeProjectId(), 1, "instance feeProjectId matches live");
        assertEq(instance.feePercent(), 2000, "instance feePercent matches live");
        assertTrue(
            address(instance) != 0xAe6705c33C8B46f56878a1D4f1cE4d75fcFb6F62,
            "fresh instance, not the old implementation-bound one"
        );
    }
}
