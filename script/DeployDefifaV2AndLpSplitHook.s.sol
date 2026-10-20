// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Sphinx} from "@sphinx-labs/contracts/contracts/foundry/SphinxPlugin.sol";

// ── Address Registry ──
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// ── Core ──
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";

// ── Defifa ──
import {DefifaDeployer} from "@ballkidz/defifa/src/DefifaDeployer.sol";
import {DefifaGovernor} from "@ballkidz/defifa/src/DefifaGovernor.sol";
import {DefifaTokenUriResolver} from "@ballkidz/defifa/src/DefifaTokenUriResolver.sol";

// ── Typeface ──
import {ITypeface} from "lib/typeface/contracts/interfaces/ITypeface.sol";

// ── LP split hook (shared CREATE2 helpers and the LP stack's deploy steps) ──
import {LpSplitHookFixBase} from "./DeployLpSplitHookFix.s.sol";

/// @notice One release deploy: @ballkidz/defifa 2.0 and @bananapus/univ4-lp-split-hook-v6 1.5.0.
///
/// The LP split hook stack (math library, hook, deployer, shared instance) deploys through `LpSplitHookFixBase`'s
/// steps, unchanged: new bytecode alone moves its addresses, and chains without a V4 PositionManager skip it.
///
/// Defifa 2.0: a referee governor (each game names the referee that submits its
/// scorecard; anyone ratifies after a timelock), an ERC-1155 game type alongside the ERC-721 one, and
/// `DefifaVotingReferee`, the sample referee that keeps holder attestation.
///
/// Deploys both external libraries (`DefifaHookLib`, then `Defifa1155HookLib`, which links it), the shared
/// `DefifaTiersHookStore` and `DefifaTokenUriResolver` (typeface set once per chain), and per game type a hook code
/// origin, a governor and a deployer, handing each governor to its deployer. The 1.x Defifa contracts stay live;
/// apps move to these addresses after the deploy.
///
/// Salts, ctor args and the 2-arg `_saltOf` fold match `Deploy.s.sol._deployDefifa` exactly, so a from-scratch
/// deploy and this focused one land at the same addresses, and each library lands where the build linker
/// (`build-artifacts.sh`) baked it into its dependents. Idempotent: `_deployPrecompiledIfNeeded` skips any contract
/// already present at its predicted address.
/// @notice Every address the Defifa 2.0 deploy produces on a chain.
struct DefifaV2Addresses {
    address hookLib;
    address hookLib1155;
    address store;
    address tokenUriResolver;
    address hook;
    address governor;
    address deployer;
    address hook1155;
    address governor1155;
    address deployer1155;
    address referee;
}

abstract contract DefifaV2Base is LpSplitHookFixBase {
    error DefifaV2_ExistingAddressMismatch(address expected, address actual);
    error DefifaV2_ProjectIdMismatch(uint256 expected, uint256 actual);

    // ── Constants (mirror Deploy.s.sol) ──
    uint256 internal constant _FEE_PROJECT_ID = 1;
    uint256 internal constant _DEFIFA_REV_PROJECT_ID = 5;

    bytes32 internal constant _DEFIFA_HOOK_LIB_SALT = keccak256("_DefifaHookLibV6_");
    bytes32 internal constant _DEFIFA_1155_HOOK_LIB_SALT = keccak256("_Defifa1155HookLibV6_");
    bytes32 internal constant _DEFIFA_SALT = "_DEFIFA_SALTV6_";
    // The 1155 game type's governor has the same constructor args as the 721 one, so it needs its own salt.
    bytes32 internal constant _DEFIFA_1155_SALT = "_DEFIFA_1155_SALTV6_";

    // ── State ──
    // `_directory`, `_tokens` and `_addressRegistry` come from LpSplitHookFixBase.
    IJBController internal _controller;
    address internal _trustedForwarder;
    address internal _typeface;

    address internal _store;
    DefifaTokenUriResolver internal _tokenUriResolver;

    // ── Chain wiring ──
    /// @notice The Capsules typeface the token URI resolver renders with on this chain (mirrors Deploy.s.sol).
    function _setupDefifaChainAddresses() internal {
        if (block.chainid == 1) {
            _typeface = 0xA77b7D93E79f1E6B4f77FaB29d9ef85733A3D44A;
        } else if (block.chainid == 11_155_111) {
            _typeface = 0x8C420d3388C882F40d263714d7A6e2c8DB93905F;
        } else if (block.chainid == 10 || block.chainid == 11_155_420) {
            _typeface = 0xe160e47928907894F97a0DC025c61D64E862fEAa;
        } else if (block.chainid == 8453) {
            _typeface = 0x3DE45A14ea0fe24037D6363Ae71Ef18F336D1C27;
        } else if (block.chainid == 84_532) {
            _typeface = 0xEb269d9F0850CEf5e3aB0F9718fb79c466720784;
        } else if (block.chainid == 42_161 || block.chainid == 421_614) {
            _typeface = 0x431C35e9fA5152A906A38390910d0Cfcba0Fb43b;
        } else {
            revert LpSplitHookFix_UnsupportedChain(block.chainid);
        }
    }

    /// @notice Load what Defifa needs. Unlike the LP loader, this reads nothing V4-specific, so it works on chains
    /// without the LP stack.
    function _loadDefifaDeploymentAddresses() internal {
        _controller = IJBController(_deploymentAddressOf("JBController"));
        _directory = IJBDirectory(_deploymentAddressOf("JBDirectory"));
        _tokens = IJBTokens(_deploymentAddressOf("JBTokens"));
        _addressRegistry = IJBAddressRegistry(_deploymentAddressOf("JBAddressRegistry"));
        _trustedForwarder = _deploymentAddressOf("ERC2771Forwarder");
    }

    /// @notice Defifa deploys only where a typeface exists and both fee projects have an ERC-20 (mirrors
    /// Deploy.s.sol, which skips Defifa otherwise).
    function _shouldDeployDefifa() internal view returns (bool) {
        return _typeface != address(0) && address(_tokens.tokenOf(_DEFIFA_REV_PROJECT_ID)) != address(0)
            && address(_tokens.tokenOf(_FEE_PROJECT_ID)) != address(0);
    }

    /// @notice The predicted address of a precompiled contract, without deploying it.
    function _predicted(
        string memory artifactName,
        bytes32 salt,
        bytes memory ctorArgs
    )
        internal
        view
        returns (address addr)
    {
        (addr,) = _isDeployed({salt: salt, creationCode: _loadArtifact(artifactName), arguments: ctorArgs});
    }

    // ── Ctor args (mirror Deploy.s.sol) ──
    function _hookCtorArgs() internal view returns (bytes memory) {
        return abi.encode(_directory, _tokens, _DEFIFA_REV_PROJECT_ID, _FEE_PROJECT_ID);
    }

    function _governorCtorArgs(address safe) internal view returns (bytes memory) {
        return abi.encode(_controller, safe);
    }

    function _deployerCtorArgs(address hookCodeOrigin, address governor) internal view returns (bytes memory) {
        return abi.encode(
            hookCodeOrigin,
            _tokenUriResolver,
            governor,
            _controller,
            _addressRegistry,
            _DEFIFA_REV_PROJECT_ID,
            _FEE_PROJECT_ID,
            _store,
            _trustedForwarder
        );
    }

    function _refereeCtorArgs() internal view returns (bytes memory) {
        return abi.encode(_controller);
    }

    /// @notice Deploy the whole Defifa 2.0 stack as `safe`, the address the Sphinx run executes from.
    function _deployAll(address safe) internal {
        // 1. Libraries. Defifa1155HookLib links DefifaHookLib, so DefifaHookLib deploys first, at the address the
        //    build linker baked into every dependent artifact.
        _deployPrecompiledIfNeeded({artifactName: "DefifaHookLib", salt: _DEFIFA_HOOK_LIB_SALT, ctorArgs: ""});
        _deployPrecompiledIfNeeded({artifactName: "Defifa1155HookLib", salt: _DEFIFA_1155_HOOK_LIB_SALT, ctorArgs: ""});

        // 2. Shared tiers store and token URI resolver for both game types. The resolver's typeface is the one
        //    per-chain value, set once through its setter so the resolver's address is the same on every chain.
        _store = _deployPrecompiledIfNeeded({artifactName: "DefifaTiersHookStore", salt: _DEFIFA_SALT, ctorArgs: ""});
        _tokenUriResolver = DefifaTokenUriResolver(
            _deployPrecompiledIfNeeded({
                artifactName: "DefifaTokenUriResolver", salt: _DEFIFA_SALT, ctorArgs: abi.encode(safe)
            })
        );
        if (address(_tokenUriResolver.typeface()) == address(0)) {
            _tokenUriResolver.setChainSpecificConstants(ITypeface(_typeface));
        } else if (address(_tokenUriResolver.typeface()) != _typeface) {
            revert DefifaV2_ExistingAddressMismatch(_typeface, address(_tokenUriResolver.typeface()));
        }

        // 3. ERC-721 game type.
        address hook =
            _deployPrecompiledIfNeeded({artifactName: "DefifaHook", salt: _DEFIFA_SALT, ctorArgs: _hookCtorArgs()});
        _deployGame({hookCodeOrigin: hook, salt: _DEFIFA_SALT, safe: safe});

        // 4. ERC-1155 game type.
        address hook1155 = _deployPrecompiledIfNeeded({
            artifactName: "Defifa1155Hook", salt: _DEFIFA_1155_SALT, ctorArgs: _hookCtorArgs()
        });
        _deployGame({hookCodeOrigin: hook1155, salt: _DEFIFA_1155_SALT, safe: safe});

        // 5. The sample holder-vote referee. One deployment judges games of both types.
        _deployPrecompiledIfNeeded({
            artifactName: "DefifaVotingReferee", salt: _DEFIFA_SALT, ctorArgs: _refereeCtorArgs()
        });
    }

    /// @notice Deploy one game type's governor and deployer, check the deployer's wiring, and hand the governor to
    /// the deployer (only the governor's owner can initialize games on it).
    function _deployGame(address hookCodeOrigin, bytes32 salt, address safe) internal {
        DefifaGovernor governor = DefifaGovernor(
            _deployPrecompiledIfNeeded({artifactName: "DefifaGovernor", salt: salt, ctorArgs: _governorCtorArgs(safe)})
        );
        DefifaDeployer deployer = DefifaDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "DefifaDeployer",
                salt: salt,
                ctorArgs: _deployerCtorArgs({hookCodeOrigin: hookCodeOrigin, governor: address(governor)})
            })
        );

        // Catch a stale or mismatched factory on an idempotent re-run where the CREATE2 address already had code.
        if (deployer.HOOK_CODE_ORIGIN() != hookCodeOrigin) {
            revert DefifaV2_ExistingAddressMismatch(hookCodeOrigin, deployer.HOOK_CODE_ORIGIN());
        }
        if (address(deployer.GOVERNOR()) != address(governor)) {
            revert DefifaV2_ExistingAddressMismatch(address(governor), address(deployer.GOVERNOR()));
        }
        if (address(deployer.TOKEN_URI_RESOLVER()) != address(_tokenUriResolver)) {
            revert DefifaV2_ExistingAddressMismatch(address(_tokenUriResolver), address(deployer.TOKEN_URI_RESOLVER()));
        }
        if (address(deployer.HOOK_STORE()) != _store) {
            revert DefifaV2_ExistingAddressMismatch(_store, address(deployer.HOOK_STORE()));
        }
        if (deployer.DEFIFA_PROJECT_ID() != _DEFIFA_REV_PROJECT_ID) {
            revert DefifaV2_ProjectIdMismatch(_DEFIFA_REV_PROJECT_ID, deployer.DEFIFA_PROJECT_ID());
        }
        if (deployer.BASE_PROTOCOL_PROJECT_ID() != _FEE_PROJECT_ID) {
            revert DefifaV2_ProjectIdMismatch(_FEE_PROJECT_ID, deployer.BASE_PROTOCOL_PROJECT_ID());
        }

        if (governor.owner() == safe) {
            governor.transferOwnership(address(deployer));
        } else if (governor.owner() != address(deployer)) {
            revert DefifaV2_ExistingAddressMismatch(address(deployer), governor.owner());
        }
    }

    /// @notice The address of every contract the deploy produces when run as `safe`, without deploying.
    function _predictAll(address safe) internal returns (DefifaV2Addresses memory a) {
        a.hookLib = _predicted({artifactName: "DefifaHookLib", salt: _DEFIFA_HOOK_LIB_SALT, ctorArgs: ""});
        a.hookLib1155 = _predicted({artifactName: "Defifa1155HookLib", salt: _DEFIFA_1155_HOOK_LIB_SALT, ctorArgs: ""});
        a.store = _predicted({artifactName: "DefifaTiersHookStore", salt: _DEFIFA_SALT, ctorArgs: ""});
        a.tokenUriResolver =
            _predicted({artifactName: "DefifaTokenUriResolver", salt: _DEFIFA_SALT, ctorArgs: abi.encode(safe)});

        // The deployer ctor args read the shared store and resolver from state.
        _store = a.store;
        _tokenUriResolver = DefifaTokenUriResolver(a.tokenUriResolver);

        a.hook = _predicted({artifactName: "DefifaHook", salt: _DEFIFA_SALT, ctorArgs: _hookCtorArgs()});
        a.governor = _predicted({artifactName: "DefifaGovernor", salt: _DEFIFA_SALT, ctorArgs: _governorCtorArgs(safe)});
        a.deployer = _predicted({
            artifactName: "DefifaDeployer",
            salt: _DEFIFA_SALT,
            ctorArgs: _deployerCtorArgs({hookCodeOrigin: a.hook, governor: a.governor})
        });
        a.hook1155 = _predicted({artifactName: "Defifa1155Hook", salt: _DEFIFA_1155_SALT, ctorArgs: _hookCtorArgs()});
        a.governor1155 =
            _predicted({artifactName: "DefifaGovernor", salt: _DEFIFA_1155_SALT, ctorArgs: _governorCtorArgs(safe)});
        a.deployer1155 = _predicted({
            artifactName: "DefifaDeployer",
            salt: _DEFIFA_1155_SALT,
            ctorArgs: _deployerCtorArgs({hookCodeOrigin: a.hook1155, governor: a.governor1155})
        });
        a.referee = _predicted({artifactName: "DefifaVotingReferee", salt: _DEFIFA_SALT, ctorArgs: _refereeCtorArgs()});
    }
}

/// @notice Sphinx deploy for Defifa 2.0 and the LP split hook 1.5.0 in one proposal. Propose per
/// `deploy:propose:defifa-v2-lp-split-hook:*`.
contract DeployDefifaV2AndLpSplitHook is DefifaV2Base, Sphinx {
    /// @notice Whether this chain gets the LP split hook stack (it has a V4 PositionManager).
    bool internal _deployLp;

    /// @notice Whether this chain gets Defifa (it has a typeface and both fee tokens).
    bool internal _deployDefifa;

    function configureSphinx() public override {
        sphinxConfig.projectName = "v6-deployment";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        if (safeAddress() != _EXPECTED_SAFE) {
            revert LpSplitHookFix_UnexpectedSafe({expected: _EXPECTED_SAFE, actual: safeAddress()});
        }
        _loadChain();
        deploy();
    }

    function deploy() public sphinx {
        if (_deployLp) _deployLpStack();
        if (_deployDefifa) _deployAll(safeAddress());
    }

    /// @notice Post-deploy address dump (no broadcast) for the focused verify/emit/distribute pipeline. Writes only
    /// this release's contracts to `script/post-deploy/.cache/addresses-<chainId>.json` in the same
    /// `jb-v6-addresses-1` format as `Deploy.s.sol._dumpAddresses`, so `post-deploy.sh --skip-dump` verifies and
    /// emits exactly these. Addresses are the deterministic CREATE2 predictions off the current artifacts.
    function dumpAddresses() external {
        _loadChain();
        if (!_deployLp && !_deployDefifa) return;

        string memory j = "_releaseAddresses";
        if (_deployLp) _serializeLpAddresses(j);
        if (_deployDefifa) _serializeDefifaAddresses({j: j, a: _predictAll(_EXPECTED_SAFE)});
        vm.serializeString({objectKey: j, valueKey: "format", value: "jb-v6-addresses-1"});
        string memory out = vm.serializeUint({objectKey: j, valueKey: "chainId", value: block.chainid});

        vm.createDir({path: "script/post-deploy/.cache", recursive: true});
        vm.writeJson({
            json: out, path: string.concat("script/post-deploy/.cache/addresses-", vm.toString(block.chainid), ".json")
        });
    }

    /// @notice Read this chain's wiring and decide which stacks it gets.
    function _loadChain() internal {
        _setupChainAddresses();
        _setupDefifaChainAddresses();
        _deployLp = _shouldDeployLpStack();
        if (_deployLp) _loadExistingDeploymentAddresses();
        _loadDefifaDeploymentAddresses();
        _deployDefifa = _shouldDeployDefifa();
    }

    function _serializeDefifaAddresses(string memory j, DefifaV2Addresses memory a) internal {
        vm.serializeAddress({objectKey: j, valueKey: "DefifaHookLib", value: a.hookLib});
        vm.serializeAddress({objectKey: j, valueKey: "Defifa1155HookLib", value: a.hookLib1155});
        vm.serializeAddress({objectKey: j, valueKey: "DefifaTiersHookStore", value: a.store});
        vm.serializeAddress({objectKey: j, valueKey: "DefifaTokenUriResolver", value: a.tokenUriResolver});
        vm.serializeAddress({objectKey: j, valueKey: "DefifaHook", value: a.hook});
        vm.serializeAddress({objectKey: j, valueKey: "DefifaGovernor", value: a.governor});
        vm.serializeAddress({objectKey: j, valueKey: "DefifaDeployer", value: a.deployer});
        vm.serializeAddress({objectKey: j, valueKey: "Defifa1155Hook", value: a.hook1155});
        vm.serializeAddress({objectKey: j, valueKey: "Defifa1155Governor", value: a.governor1155});
        vm.serializeAddress({objectKey: j, valueKey: "Defifa1155Deployer", value: a.deployer1155});
        vm.serializeAddress({objectKey: j, valueKey: "DefifaVotingReferee", value: a.referee});
    }
}
