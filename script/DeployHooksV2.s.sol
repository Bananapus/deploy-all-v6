// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Sphinx} from "@sphinx-labs/contracts/contracts/foundry/SphinxPlugin.sol";
import {Script, stdJson} from "forge-std/Script.sol";

// ── Uniswap ──
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

// ── Buyback Hook ──
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";

// ── Router Terminal ──
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalGateway} from "@bananapus/router-terminal-v6/src/JBRouterTerminalGateway.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";

// ── Uniswap V4 Hook ──
import {JBUniswapV4Hook} from "@bananapus/univ4-router-v6/src/JBUniswapV4Hook.sol";

// ── Core ──
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";

// ── Math ──
import {mulDiv, sqrt} from "@prb/math/src/Common.sol";

/// @notice Rollout of buyback hook 2.0.0 and Uniswap V4 hook 2.0.0, with project 1 moved onto them.
///
/// Buyback hook 2.0.0 (nana-buyback-hook-v6 #181, #184) routes no-quote pays and cash-outs on the expected
/// settlement of the pool plus issuance or reclaim. V4 hook 2.0.0 (nana-univ4-router-v6 #145, #146) fills a direct
/// buy from the pool while it beats issuance and mints the rest, and sells through the best of the pool, a cash-out
/// or a split. A pool is bound to its V4 hook for life, and a buyback hook reads one oracle hook, so the new buyback
/// hook trades only against pools on the new V4 hook.
///
/// Run by the infra Safe, which owns both registries and is project 1's operator. Steps, on every chain with the
/// Uniswap stack (OP Sepolia has none and skips everything):
///   1. Deploy the V4 hook at a CREATE2 salt whose address carries its permission flags.
///   2. Deploy the buyback hook and point it at this chain's PoolManager and the new V4 hook.
///   3. Deploy a router bound to the new buyback hook (the router pins its hook as an immutable), copy the live
///      router's chain wiring into it with the new V4 hook, and put a gateway in front of it.
///   4. Make the new buyback hook and gateway the registry defaults. That allows them, and covers only projects
///      created afterwards.
///   5. Pin project 1 to both, and register its ETH pool on the new V4 hook. The pool is new and empty, so it starts
///      at the issuance weight, as `REVDeployer` seeds revnet pools, where a pay breaks even between swap and mint.
///   6. Disallow the outgoing buyback hook and gateway, so no project can newly select them.
///
/// Every other project keeps its current hook and router until its operator migrates it (`setHookFor`,
/// `setPoolFor` or `initializePoolFor`, `setTerminalFor`). Idempotent: each deploy skips a contract already at its
/// predicted address, and each registry step checks the current state first.
abstract contract HooksV2Base is Script {
    using stdJson for string;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    error HooksV2_FeeProjectHookLocked(uint256 projectId);
    error HooksV2_FeeProjectTerminalLocked(uint256 projectId);
    error HooksV2_MissingDeployment(string name);
    error HooksV2_MissingPoolPrice(uint256 projectId);
    error HooksV2_RouterPoolManagerMismatch(address expected, address actual);
    error HooksV2_UnexpectedSafe(address expected, address actual);
    error HooksV2_UnsupportedChain(uint256 chainId);

    // ── Constants (mirror Deploy.s.sol) ──
    address internal constant _CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address internal constant _EXPECTED_SAFE = 0x4dc161eF837fF1C4485b08DDFcDB182F2157bE18;
    address internal constant _PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint256 internal constant DEPLOYMENT_NONCE = 13;

    uint256 internal constant _FEE_PROJECT_ID = 1;

    /// @notice Project 1's pool on the new V4 hook: the fee tier, tick spacing and TWAP window its live pool uses.
    uint24 internal constant _FEE_PROJECT_POOL_FEE = 10_000;
    int24 internal constant _FEE_PROJECT_POOL_TICK_SPACING = 200;
    uint256 internal constant _FEE_PROJECT_TWAP_WINDOW = 30 minutes;

    bytes32 internal constant _BUYBACK_HOOK_SALT = keccak256("JBBuybackHookV6_2.0.0");
    bytes32 internal constant _ROUTER_TERMINAL_SALT = keccak256("JBRouterTerminalV6_BuybackHook2.0.0");
    bytes32 internal constant _ROUTER_TERMINAL_GATEWAY_SALT = keccak256("JBRouterTerminalGatewayV6_BuybackHook2.0.0");

    // ── State ──
    address internal _poolManager;

    address internal _trustedForwarder;
    IJBDirectory internal _directory;
    IJBPermissions internal _permissions;
    IJBPrices internal _prices;
    IJBProjects internal _projects;
    IJBTerminal internal _terminal;
    IJBTokens internal _tokens;

    JBBuybackHookRegistry internal _buybackRegistry;
    JBRouterTerminalRegistry internal _routerRegistry;

    JBBuybackHook internal _oldBuybackHook;
    JBRouterTerminal internal _oldRouterTerminal;
    JBRouterTerminalGateway internal _oldGateway;

    JBUniswapV4Hook internal _univ4Hook;
    JBBuybackHook internal _buybackHook;
    JBRouterTerminal internal _routerTerminal;
    JBRouterTerminalGateway internal _gateway;

    // ── Chain wiring ──
    function _setupChainAddresses() internal {
        if (block.chainid == 1) {
            _poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        } else if (block.chainid == 11_155_111) {
            _poolManager = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
        } else if (block.chainid == 10) {
            _poolManager = 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
        } else if (block.chainid == 11_155_420) {
            _poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        } else if (block.chainid == 8453) {
            _poolManager = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
        } else if (block.chainid == 84_532) {
            _poolManager = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
        } else if (block.chainid == 42_161) {
            _poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
        } else if (block.chainid == 421_614) {
            _poolManager = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
        } else {
            revert HooksV2_UnsupportedChain(block.chainid);
        }
    }

    /// @notice The Uniswap stack (and thus the buyback and router registries) was never deployed on OP Sepolia.
    function _shouldDeployUniswapStack() internal view returns (bool) {
        return block.chainid != 11_155_420;
    }

    /// @notice Reads the live protocol from the canonical deployment records. The outgoing hook, router and gateway
    /// come from the records, not from the registries: once this proposal runs, the registry defaults are the new
    /// contracts, and a rerun must still compare against what it replaced.
    function _loadDeploymentAddresses() internal {
        _trustedForwarder = _deploymentAddressOf("ERC2771Forwarder");
        _directory = IJBDirectory(_deploymentAddressOf("JBDirectory"));
        _permissions = IJBPermissions(_deploymentAddressOf("JBPermissions"));
        _prices = IJBPrices(_deploymentAddressOf("JBPrices"));
        _projects = IJBProjects(_deploymentAddressOf("JBProjects"));
        _terminal = IJBTerminal(_deploymentAddressOf("JBMultiTerminal"));
        _tokens = IJBTokens(_deploymentAddressOf("JBTokens"));

        _buybackRegistry = JBBuybackHookRegistry(_deploymentAddressOf("JBBuybackHookRegistry"));
        _routerRegistry = JBRouterTerminalRegistry(payable(_deploymentAddressOf("JBRouterTerminalRegistry")));

        _oldBuybackHook = JBBuybackHook(payable(_deploymentAddressOf("JBBuybackHook")));
        _oldRouterTerminal = JBRouterTerminal(payable(_deploymentAddressOf("JBRouterTerminal")));
        _oldGateway = JBRouterTerminalGateway(payable(_deploymentAddressOf("JBRouterTerminalGateway")));
    }

    function _deploymentAddressOf(string memory name) internal view returns (address addr) {
        string memory path = string.concat("deployments/", _chainFolder(), "/", name, ".json");
        string memory json = vm.readFile(path);
        addr = json.readAddress(".address");
        if (addr == address(0)) revert HooksV2_MissingDeployment(name);
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
        revert HooksV2_UnsupportedChain(block.chainid);
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

    // ── V4 hook address (mirror DeployTwapOracleUpgrade.s.sol) ──

    /// @notice The V4 hook's permissions, which V4 reads from the low bits of its address.
    function _univ4HookFlags() internal pure returns (uint160) {
        return uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );
    }

    /// @notice The first salt index whose folded CREATE2 address carries exactly the hook's flags. The search is
    /// deterministic over the artifact, so every chain lands on the same salt and address.
    function _findHookSalt(
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    )
        internal
        pure
        returns (bytes32 salt)
    {
        flags = flags & HookMiner.FLAG_MASK;
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);

        for (uint256 i; i < HookMiner.MAX_LOOP; i++) {
            address hookAddress = HookMiner.computeAddress({
                deployer: _CREATE2_FACTORY,
                salt: uint256(_saltOf(bytes32(i))),
                creationCodeWithArgs: creationCodeWithArgs
            });
            if (uint160(hookAddress) & HookMiner.FLAG_MASK == flags) return bytes32(i);
        }

        revert("HookMiner: could not find salt");
    }

    /// @notice The V4 hook's address and whether it exists yet.
    function _univ4HookAddress() internal view returns (address hook, bool isDeployed, bytes32 salt) {
        bytes memory code = _loadArtifact("JBUniswapV4Hook");
        bytes memory ctorArgs = _univ4HookCtorArgs();
        salt = _findHookSalt({flags: _univ4HookFlags(), creationCode: code, constructorArgs: ctorArgs});
        (hook, isDeployed) = _isDeployed({salt: salt, creationCode: code, arguments: ctorArgs});
    }

    // ── Ctor args (mirror Deploy.s.sol / the live contracts) ──
    function _univ4HookCtorArgs() internal view returns (bytes memory) {
        return abi.encode(IPoolManager(_poolManager), _tokens, _directory, _prices);
    }

    function _buybackHookCtorArgs() internal view returns (bytes memory) {
        return abi.encode(_directory, _permissions, _prices, _projects, _tokens, _EXPECTED_SAFE, _trustedForwarder);
    }

    /// @notice The router pins its buyback hook as an immutable, so its identity follows the hook it is bound to.
    function _routerTerminalCtorArgs(address buybackHook) internal view returns (bytes memory) {
        return abi.encode(_directory, _tokens, _PERMIT2, buybackHook, _trustedForwarder, _EXPECTED_SAFE);
    }

    function _routerTerminalGatewayCtorArgs(address routerTerminal) internal view returns (bytes memory) {
        return abi.encode(_directory, _PERMIT2, routerTerminal, _trustedForwarder);
    }

    // ── Project 1's pool price ──

    /// @notice The sqrt price at which project 1's new pool starts: its current issuance weight per ETH, the rule
    /// `REVDeployer` seeds every revnet pool with. That is the buyback hook's break-even: swapped tokens pass through
    /// the reserved split like minted ones, so the pool has to beat the full weight. The pool is empty, so the price
    /// only anchors the first liquidity added.
    /// @return ok False when the project has no ruleset, ETH accounting context or ERC-20.
    /// @return sqrtPriceX96 The starting sqrt price, as token1 per token0 in Q64.96.
    function _feeProjectPoolSqrtPriceX96() internal view returns (bool ok, uint160 sqrtPriceX96) {
        address controller = address(_directory.controllerOf(_FEE_PROJECT_ID));
        address projectToken = address(_tokens.tokenOf(_FEE_PROJECT_ID));
        if (controller == address(0) || projectToken == address(0)) return (false, 0);

        JBAccountingContext memory context =
            _terminal.accountingContextForTokenOf({projectId: _FEE_PROJECT_ID, token: JBConstants.NATIVE_TOKEN});
        if (context.token != JBConstants.NATIVE_TOKEN || context.decimals == 0) return (false, 0);

        (JBRuleset memory ruleset, JBRulesetMetadata memory metadata) =
            IJBController(controller).currentRulesetOf(_FEE_PROJECT_ID);
        if (ruleset.id == 0 || ruleset.weight == 0) return (false, 0);

        // Tokens issued for one whole unit of the base currency.
        uint256 issuance = ruleset.weight;

        // Price one ETH unit in the base currency when the accounting currency differs.
        uint256 unit = 10 ** context.decimals;
        if (context.currency != metadata.baseCurrency) {
            uint256 rate = _prices.pricePerUnitOf({
                projectId: _FEE_PROJECT_ID,
                pricingCurrency: context.currency,
                unitCurrency: metadata.baseCurrency,
                decimals: context.decimals
            });
            if (rate == 0) return (false, 0);
            issuance = mulDiv({x: issuance, y: unit, denominator: rate});
        }

        // Native ETH is address(0) in V4, so it is always currency0 and the price is project tokens per ETH.
        sqrtPriceX96 = uint160(sqrt(mulDiv({x: issuance, y: 1 << 192, denominator: unit})));
        ok = sqrtPriceX96 != 0;
    }

    /// @notice The whole proposal, Sphinx-free so a fork rehearsal can run it as the Safe.
    function _deployHooksV2() internal {
        if (!_shouldDeployUniswapStack()) return;

        // 1. The V4 hook, at the salt whose address carries its flags.
        {
            (address hook, bool already, bytes32 salt) = _univ4HookAddress();
            if (!already) {
                hook = _deployViaFactory({
                    salt: salt, creationCode: _loadArtifact("JBUniswapV4Hook"), constructorArgs: _univ4HookCtorArgs()
                });
            }
            _univ4Hook = JBUniswapV4Hook(payable(hook));
        }

        // 2. The buyback hook, reading the new V4 hook's pools and oracle.
        _buybackHook = JBBuybackHook(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBBuybackHook", salt: _BUYBACK_HOOK_SALT, ctorArgs: _buybackHookCtorArgs()
                }))
        );
        if (address(_buybackHook.poolManager()) == address(0)) {
            _buybackHook.setChainSpecificConstants({
                newPoolManager: IPoolManager(_poolManager), newOracleHook: IHooks(address(_univ4Hook))
            });
        }

        // 3. A router bound to the new buyback hook, wired like the live router but on the new V4 hook, behind a
        //    gateway. The PoolManager is cross-checked against the table above so a stale record cannot wire the
        //    router to a different V4.
        _routerTerminal = JBRouterTerminal(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBRouterTerminal",
                    salt: _ROUTER_TERMINAL_SALT,
                    ctorArgs: _routerTerminalCtorArgs(address(_buybackHook))
                }))
        );
        if (address(_routerTerminal.wrappedNativeToken()) == address(0)) {
            if (address(_oldRouterTerminal.poolManager()) != _poolManager) {
                revert HooksV2_RouterPoolManagerMismatch({
                    expected: _poolManager, actual: address(_oldRouterTerminal.poolManager())
                });
            }
            _routerTerminal.setChainSpecificConstants({
                newWrappedNativeToken: _oldRouterTerminal.wrappedNativeToken(),
                newFactory: _oldRouterTerminal.factory(),
                newPoolManager: IPoolManager(_poolManager),
                newUniv4Hook: address(_univ4Hook)
            });
        }
        _gateway = JBRouterTerminalGateway(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBRouterTerminalGateway",
                    salt: _ROUTER_TERMINAL_GATEWAY_SALT,
                    ctorArgs: _routerTerminalGatewayCtorArgs(address(_routerTerminal))
                }))
        );

        // 4. Registry defaults for projects created from here on. Setting a default allows it, which the pins below
        //    require, and must precede the disallows: a registry refuses to disallow its current default.
        if (address(_buybackRegistry.defaultHook()) != address(_buybackHook)) {
            _buybackRegistry.setDefaultHook({hook: IJBRulesetDataHook(address(_buybackHook))});
        }
        if (address(_routerRegistry.defaultTerminal()) != address(_gateway)) {
            _routerRegistry.setDefaultTerminal({terminal: IJBTerminal(address(_gateway))});
        }

        // 5. Project 1 onto both. The Safe holds its SET_BUYBACK_HOOK, SET_BUYBACK_POOL and SET_ROUTER_TERMINAL
        //    permissions as its operator.
        _migrateFeeProject();

        // 6. Retire the outgoing hook and gateway: no project can newly select them. Existing pins and default
        //    cohorts keep resolving to them by registry design. The raw outgoing router was never allowed.
        if (
            address(_oldBuybackHook) != address(_buybackHook)
                && _buybackRegistry.isHookAllowed(IJBRulesetDataHook(address(_oldBuybackHook)))
        ) {
            _buybackRegistry.disallowHook({hook: IJBRulesetDataHook(address(_oldBuybackHook))});
        }
        if (
            address(_oldGateway) != address(_gateway)
                && _routerRegistry.isTerminalAllowed(IJBTerminal(address(_oldGateway)))
        ) {
            _routerRegistry.disallowTerminal({terminal: IJBTerminal(address(_oldGateway))});
        }
    }

    function _migrateFeeProject() internal {
        if (address(_buybackRegistry.hookOf(_FEE_PROJECT_ID)) != address(_buybackHook)) {
            if (_buybackRegistry.hasLockedHook(_FEE_PROJECT_ID)) revert HooksV2_FeeProjectHookLocked(_FEE_PROJECT_ID);
            _buybackRegistry.setHookFor({projectId: _FEE_PROJECT_ID, hook: IJBRulesetDataHook(address(_buybackHook))});
        }

        if (address(_routerRegistry.terminalOf(_FEE_PROJECT_ID)) != address(_gateway)) {
            if (_routerRegistry.hasLockedTerminal(_FEE_PROJECT_ID)) {
                revert HooksV2_FeeProjectTerminalLocked(_FEE_PROJECT_ID);
            }
            _routerRegistry.setTerminalFor({projectId: _FEE_PROJECT_ID, terminal: IJBTerminal(address(_gateway))});
        }

        // Pool state lives per buyback hook, so the new hook starts with none.
        if (_buybackHook.twapWindowOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)}) != 0) return;

        // Anyone can initialize a V4 pool, and this pool's key is predictable. If it already exists, register it as
        // it is; `initializePoolFor` would reject its price.
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(_tokens.tokenOf(_FEE_PROJECT_ID))),
            fee: _FEE_PROJECT_POOL_FEE,
            tickSpacing: _FEE_PROJECT_POOL_TICK_SPACING,
            hooks: IHooks(address(_univ4Hook))
        });
        (uint160 livePrice,,,) = IPoolManager(_poolManager).getSlot0(key.toId());
        if (livePrice != 0) {
            _buybackRegistry.setPoolFor({
                projectId: _FEE_PROJECT_ID,
                fee: _FEE_PROJECT_POOL_FEE,
                tickSpacing: _FEE_PROJECT_POOL_TICK_SPACING,
                twapWindow: _FEE_PROJECT_TWAP_WINDOW,
                terminalToken: JBConstants.NATIVE_TOKEN
            });
            return;
        }

        (bool ok, uint160 sqrtPriceX96) = _feeProjectPoolSqrtPriceX96();
        if (!ok) revert HooksV2_MissingPoolPrice(_FEE_PROJECT_ID);
        _buybackRegistry.initializePoolFor({
            projectId: _FEE_PROJECT_ID,
            fee: _FEE_PROJECT_POOL_FEE,
            tickSpacing: _FEE_PROJECT_POOL_TICK_SPACING,
            twapWindow: _FEE_PROJECT_TWAP_WINDOW,
            terminalToken: JBConstants.NATIVE_TOKEN,
            sqrtPriceX96: sqrtPriceX96
        });
    }
}

/// @notice Sphinx deploy for the hooks 2.0.0 rollout. Propose per `deploy:propose:hooks-v2:*`.
contract DeployHooksV2 is HooksV2Base, Sphinx {
    function configureSphinx() public override {
        sphinxConfig.projectName = "v6-deployment";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        if (safeAddress() != _EXPECTED_SAFE) {
            revert HooksV2_UnexpectedSafe({expected: _EXPECTED_SAFE, actual: safeAddress()});
        }
        _setupChainAddresses();
        if (_shouldDeployUniswapStack()) _loadDeploymentAddresses();
        deploy();
    }

    function deploy() public sphinx {
        _deployHooksV2();
    }

    /// @notice Post-deploy address dump (no broadcast) for the focused verify, emit and distribute pipeline, in the
    /// `jb-v6-addresses-1` format of `Deploy.s.sol._dumpAddresses`. Writes the four contracts this script deploys to
    /// `script/post-deploy/.cache/addresses-<chainId>.json`, as their deterministic CREATE2 predictions off the
    /// current artifacts. No file is written on a chain without the Uniswap stack.
    function dumpAddresses() external {
        _setupChainAddresses();
        if (!_shouldDeployUniswapStack()) return;
        _loadDeploymentAddresses();

        string memory j = "_hooksV2Addresses";
        (address univ4Hook,,) = _univ4HookAddress();
        vm.serializeAddress({objectKey: j, valueKey: "JBUniswapV4Hook", value: univ4Hook});

        // The router's identity follows the buyback hook, and the gateway's follows the router.
        (address buybackHook,) = _isDeployed({
            salt: _BUYBACK_HOOK_SALT, creationCode: _loadArtifact("JBBuybackHook"), arguments: _buybackHookCtorArgs()
        });
        vm.serializeAddress({objectKey: j, valueKey: "JBBuybackHook", value: buybackHook});
        (address routerTerminal,) = _isDeployed({
            salt: _ROUTER_TERMINAL_SALT,
            creationCode: _loadArtifact("JBRouterTerminal"),
            arguments: _routerTerminalCtorArgs(buybackHook)
        });
        vm.serializeAddress({objectKey: j, valueKey: "JBRouterTerminal", value: routerTerminal});
        (address gateway,) = _isDeployed({
            salt: _ROUTER_TERMINAL_GATEWAY_SALT,
            creationCode: _loadArtifact("JBRouterTerminalGateway"),
            arguments: _routerTerminalGatewayCtorArgs(routerTerminal)
        });
        vm.serializeAddress({objectKey: j, valueKey: "JBRouterTerminalGateway", value: gateway});

        vm.serializeString({objectKey: j, valueKey: "format", value: "jb-v6-addresses-1"});
        string memory out = vm.serializeUint({objectKey: j, valueKey: "chainId", value: block.chainid});

        vm.createDir({path: "script/post-deploy/.cache", recursive: true});
        vm.writeJson({
            json: out, path: string.concat("script/post-deploy/.cache/addresses-", vm.toString(block.chainid), ".json")
        });
    }
}
