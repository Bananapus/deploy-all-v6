// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Sphinx} from "@sphinx-labs/contracts/contracts/foundry/SphinxPlugin.sol";
import {Script, stdJson} from "forge-std/Script.sol";

// ── Uniswap ──
import {IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

// ── Address Registry ──
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// ── Core ──
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";

// ── Suckers ──
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";

// ── Uniswap V4 LP Split Hook ──
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";
import {JBUniswapV4LPSplitHookDeployer} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHookDeployer.sol";

/// @notice Focused redeploy of the Uniswap V4 LP split hook stack for the fix in univ4-lp-split-hook-v6 1.3.0:
/// findHighestValueTerminalTokenOf now skips terminals that don't expose STORE() (e.g. JBRouterTerminalRegistry)
/// instead of reverting, which had permanently DoSed deployPool/addLiquidity for any project with such a terminal
/// registered.
///
/// The fix lives in the linked `JBUniswapV4LPSplitHookMath` library, so all three artifacts change: the library
/// bytecode, the hook (relinked against the new library address at build time), and the deployer (ctor references
/// the new hook). Each therefore deploys at a fresh CREATE2 address. Nothing on-chain stores the deployer address,
/// so no re-wiring is required — new LP-split configurations resolve the new deployer/hook from the deployment
/// records. Re-pointing an existing project's reserved split at a clone of the new hook is a separate, project-level
/// operator migration and is intentionally NOT performed here.
///
/// Salts and the 2-arg `_saltOf` fold match `Deploy.s.sol` exactly, so the library lands at the address the build
/// linker (`build-artifacts.sh`) baked into the rebuilt hook artifact. Idempotent: `_deployPrecompiledIfNeeded`
/// skips any contract already present at its predicted address.
abstract contract LpSplitHookFixBase is Script {
    using stdJson for string;

    error LpSplitHookFix_MissingDeployment(string name);
    error LpSplitHookFix_UnexpectedSafe(address expected, address actual);
    error LpSplitHookFix_UnsupportedChain(uint256 chainId);

    // ── Constants (mirror Deploy.s.sol) ──
    IPermit2 internal constant _PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    address internal constant _CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address internal constant _EXPECTED_SAFE = 0x4dc161eF837fF1C4485b08DDFcDB182F2157bE18;
    uint256 internal constant DEPLOYMENT_NONCE = 13;

    bytes32 internal constant _MATH_LIB_SALT = keccak256("_JBUniswapV4LPSplitHookMathV6_");
    bytes32 internal constant _LP_SPLIT_HOOK_SALT = "JBUniswapV4LPSplitHookV6";
    bytes32 internal constant _LP_SPLIT_HOOK_DEPLOYER_SALT = "JBUniswapV4LPSplitHookDeployerV6";

    // ── State ──
    address internal _poolManager;
    address internal _positionManager;

    IJBAddressRegistry internal _addressRegistry;
    IJBDirectory internal _directory;
    IJBPermissions internal _permissions;
    IJBTokens internal _tokens;
    IJBSuckerRegistry internal _suckerRegistry;
    address internal _oracleHook; // the live JBUniswapV4Hook the buyback pools already trade against

    JBUniswapV4LPSplitHook internal _lpSplitHook;
    JBUniswapV4LPSplitHookDeployer internal _lpSplitHookDeployer;

    // ── Chain wiring ──
    function _setupChainAddresses() internal {
        if (block.chainid == 1) {
            _poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            _positionManager = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
        } else if (block.chainid == 11_155_111) {
            _poolManager = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
            _positionManager = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
        } else if (block.chainid == 10) {
            _poolManager = 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
            _positionManager = 0x3C3Ea4B57a46241e54610e5f022E5c45859A1017;
        } else if (block.chainid == 11_155_420) {
            _poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            _positionManager = address(0); // no V4 position manager on OP Sepolia → LP stack not deployed
        } else if (block.chainid == 8453) {
            _poolManager = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
            _positionManager = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
        } else if (block.chainid == 84_532) {
            _poolManager = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
            _positionManager = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
        } else if (block.chainid == 42_161) {
            _poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
            _positionManager = 0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869;
        } else if (block.chainid == 421_614) {
            _poolManager = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
            _positionManager = 0xAc631556d3d4019C95769033B5E719dD77124BAc;
        } else {
            revert LpSplitHookFix_UnsupportedChain(block.chainid);
        }
    }

    function _loadExistingDeploymentAddresses() internal {
        _permissions = IJBPermissions(_deploymentAddressOf("JBPermissions"));
        _directory = IJBDirectory(_deploymentAddressOf("JBDirectory"));
        _tokens = IJBTokens(_deploymentAddressOf("JBTokens"));
        _addressRegistry = IJBAddressRegistry(_deploymentAddressOf("JBAddressRegistry"));
        _suckerRegistry = IJBSuckerRegistry(_deploymentAddressOf("JBSuckerRegistry"));
        _oracleHook = _deploymentAddressOf("JBUniswapV4Hook");
    }

    function _deploymentAddressOf(string memory name) internal view returns (address addr) {
        string memory path = string.concat("deployments/", _chainFolder(), "/", name, ".json");
        string memory json = vm.readFile(path);
        addr = json.readAddress(".address");
        if (addr == address(0)) revert LpSplitHookFix_MissingDeployment(name);
    }

    function _chainFolder() internal view returns (string memory) {
        if (block.chainid == 1) return "ethereum";
        if (block.chainid == 11_155_111) return "sepolia";
        if (block.chainid == 10) return "optimism";
        if (block.chainid == 11_155_420) return "optimism_sepolia";
        if (block.chainid == 8453) return "base";
        if (block.chainid == 84_532) return "base_sepolia";
        if (block.chainid == 42_161) return "arbitrum";
        if (block.chainid == 421_614) return "arbitrum_sepolia";
        revert LpSplitHookFix_UnsupportedChain(block.chainid);
    }

    /// @notice The LP stack is only deployed where a V4 PositionManager exists.
    function _shouldDeployLpStack() internal view returns (bool) {
        return _positionManager != address(0);
    }

    // ── CREATE2 (mirror Deploy.s.sol's 2-arg fold) ──
    function _saltOf(bytes32 base) internal pure returns (bytes32) {
        return keccak256(abi.encode(DEPLOYMENT_NONCE, base));
    }

    function _loadArtifact(string memory artifactName) internal view returns (bytes memory) {
        string memory json = vm.readFile(string.concat("artifacts/", artifactName, ".json"));
        return vm.parseJsonBytes({json: json, key: ".bytecode.object"});
    }

    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (address deployedTo, bool isDeployed)
    {
        salt = _saltOf(salt);
        deployedTo = vm.computeCreate2Address({
            salt: salt, initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)), deployer: _CREATE2_FACTORY
        });
        isDeployed = deployedTo.code.length != 0;
    }

    function _deployViaFactory(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory constructorArgs
    )
        internal
        returns (address addr)
    {
        bytes32 foldedSalt = _saltOf(salt);
        bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);
        (bool success,) = _CREATE2_FACTORY.call(abi.encodePacked(foldedSalt, initCode));
        require(success, "Factory CREATE2 failed");
        addr =
            vm.computeCreate2Address({salt: foldedSalt, initCodeHash: keccak256(initCode), deployer: _CREATE2_FACTORY});
        require(addr.code.length != 0, "Factory CREATE2 produced no code");
    }

    function _deployPrecompiledIfNeeded(
        string memory artifactName,
        bytes32 salt,
        bytes memory ctorArgs
    )
        internal
        returns (address addr)
    {
        bytes memory code = _loadArtifact(artifactName);
        bool already;
        (addr, already) = _isDeployed({salt: salt, creationCode: code, arguments: ctorArgs});
        if (!already) addr = _deployViaFactory({salt: salt, creationCode: code, constructorArgs: ctorArgs});
    }

    // ── Ctor args (mirror Deploy.s.sol) ──
    function _lpSplitHookCtorArgs() internal view returns (bytes memory) {
        return abi.encode(
            address(_directory),
            _permissions,
            address(_tokens),
            IAllowanceTransfer(address(_PERMIT2)),
            IJBSuckerRegistry(address(_suckerRegistry))
        );
    }

    function _lpSplitHookDeployerCtorArgs() internal view returns (bytes memory) {
        return abi.encode(IJBAddressRegistry(address(_addressRegistry)), _lpSplitHook, _EXPECTED_SAFE);
    }
}

/// @notice Sphinx deploy for the LP split hook fix. Propose per `deploy:propose:lp-split-hook-fix:*`.
contract DeployLpSplitHookFix is LpSplitHookFixBase, Sphinx {
    function configureSphinx() public override {
        sphinxConfig.projectName = "v6-deployment";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        if (safeAddress() != _EXPECTED_SAFE) {
            revert LpSplitHookFix_UnexpectedSafe({expected: _EXPECTED_SAFE, actual: safeAddress()});
        }
        _setupChainAddresses();
        if (!_shouldDeployLpStack()) return;
        _loadExistingDeploymentAddresses();
        deploy();
    }

    function deploy() public sphinx {
        // 1. New JBUniswapV4LPSplitHookMath library (carries the fix). New bytecode → fresh address, exactly where
        //    the build linker baked it into the rebuilt hook artifact (same 2-arg salt namespace).
        _deployPrecompiledIfNeeded({artifactName: "JBUniswapV4LPSplitHookMath", salt: _MATH_LIB_SALT, ctorArgs: ""});

        // 2. New hook implementation, relinked against the new library.
        _lpSplitHook = JBUniswapV4LPSplitHook(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBUniswapV4LPSplitHook", salt: _LP_SPLIT_HOOK_SALT, ctorArgs: _lpSplitHookCtorArgs()
                }))
        );

        // 3. New deployer factory pointing at the new hook implementation.
        _lpSplitHookDeployer = JBUniswapV4LPSplitHookDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "JBUniswapV4LPSplitHookDeployer",
                salt: _LP_SPLIT_HOOK_DEPLOYER_SALT,
                ctorArgs: _lpSplitHookDeployerCtorArgs()
            })
        );

        // Wire the chain-specific Uniswap V4 addresses into the deployer (one-shot, DEPLOYER-gated). The oracle hook
        // is the live JBUniswapV4Hook the buyback pools already use — reused, not redeployed.
        if (address(_lpSplitHookDeployer.poolManager()) == address(0)) {
            _lpSplitHookDeployer.setChainSpecificConstants({
                newPoolManager: IPoolManager(_poolManager),
                newPositionManager: IPositionManager(_positionManager),
                newOracleHook: IHooks(_oracleHook)
            });
        }
    }
}
