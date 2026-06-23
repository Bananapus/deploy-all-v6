// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Sphinx} from "@sphinx-labs/contracts/contracts/foundry/SphinxPlugin.sol";
import {Script, stdJson} from "forge-std/Script.sol";

import {IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";

import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {JBFeelessAddresses} from "@bananapus/core-v6/src/JBFeelessAddresses.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBSplitGroupIds} from "@bananapus/core-v6/src/libraries/JBSplitGroupIds.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";
import {IWETH9} from "@bananapus/router-terminal-v6/src/interfaces/IWETH9.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";
import {JBUniswapV4LPSplitHookDeployer} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHookDeployer.sol";
import {JBUniswapV4Hook} from "@bananapus/univ4-router-v6/src/JBUniswapV4Hook.sol";
import {mulDiv, sqrt} from "@prb/math/src/Common.sol";

/// @notice Shared helpers for the post-launch TWAP oracle upgrade.
abstract contract TwapOracleUpgradeBase is Script {
    using stdJson for string;

    error TwapOracleUpgrade_MissingDeployment(string name);
    error TwapOracleUpgrade_MissingPoolPrice(uint256 projectId, address terminalToken);
    error TwapOracleUpgrade_UnsupportedChain(uint256 chainId);
    error TwapOracleUpgrade_UnexpectedSafe(address expected, address actual);

    IPermit2 internal constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    address internal constant DETERMINISTIC_CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address internal constant EXPECTED_SAFE = 0x4dc161eF837fF1C4485b08DDFcDB182F2157bE18;

    uint256 internal constant DEPLOYMENT_NONCE = 13;
    uint256 internal constant TWAP_UPGRADE_NONCE = 1;

    uint256 internal constant ART_PROJECT_ID = 6;
    uint256 internal constant BANNY_PROJECT_ID = 4;
    uint24 internal constant DEFAULT_BUYBACK_POOL_FEE = 10_000;
    int24 internal constant DEFAULT_BUYBACK_TICK_SPACING = 200;
    uint256 internal constant DEFAULT_BUYBACK_TWAP_WINDOW = 2 days;
    uint256 internal constant LP_SPLIT_HOOK_FEE_PERCENT = 2000;
    uint256 internal constant LP_SPLIT_HOOK_FEE_PROJECT_ID = 1;

    address internal constant BANNY_OPERATOR = 0x9E2a10aB3BD22831f19d02C648Bc2Cb49B127450;

    bytes32 internal constant BANNY_LP_SPLIT_HOOK_SALT = "_BAN_LP_SPLIT_HOOK_V6_";
    bytes32 internal constant BUYBACK_HOOK_SALT = keccak256("JBBuybackHookV6_TwapOracleUpgrade");
    bytes32 internal constant ROUTER_TERMINAL_SALT = keccak256("JBRouterTerminalV6_TwapOracleUpgrade");
    bytes32 internal constant LP_SPLIT_HOOK_SALT = keccak256("JBUniswapV4LPSplitHookV6_TwapOracleUpgrade");
    bytes32 internal constant LP_SPLIT_HOOK_DEPLOYER_SALT =
        keccak256("JBUniswapV4LPSplitHookDeployerV6_TwapOracleUpgrade");

    string internal constant DEPLOY_LP_SPLIT_HOOK_ABI =
        "[{\"type\":\"function\",\"name\":\"deployHookFor\",\"inputs\":[{\"name\":\"feeProjectId\",\"type\":\"uint256\"},{\"name\":\"feePercent\",\"type\":\"uint256\"},{\"name\":\"buybackHook\",\"type\":\"address\"},{\"name\":\"salt\",\"type\":\"bytes32\"}],\"outputs\":[{\"name\":\"hook\",\"type\":\"address\"}],\"stateMutability\":\"nonpayable\"}]";
    string internal constant INITIALIZE_POOL_ABI =
        "[{\"type\":\"function\",\"name\":\"initializePoolFor\",\"inputs\":[{\"name\":\"projectId\",\"type\":\"uint256\"},{\"name\":\"fee\",\"type\":\"uint24\"},{\"name\":\"tickSpacing\",\"type\":\"int24\"},{\"name\":\"twapWindow\",\"type\":\"uint256\"},{\"name\":\"terminalToken\",\"type\":\"address\"},{\"name\":\"sqrtPriceX96\",\"type\":\"uint160\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"}]";
    string internal constant SET_HOOK_ABI =
        "[{\"type\":\"function\",\"name\":\"setHookFor\",\"inputs\":[{\"name\":\"projectId\",\"type\":\"uint256\"},{\"name\":\"hook\",\"type\":\"address\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"}]";
    string internal constant SET_SPLIT_GROUPS_ABI =
        "[{\"type\":\"function\",\"name\":\"setSplitGroupsOf\",\"inputs\":[{\"name\":\"projectId\",\"type\":\"uint256\"},{\"name\":\"rulesetId\",\"type\":\"uint256\"},{\"name\":\"splitGroups\",\"type\":\"tuple[]\",\"components\":[{\"name\":\"groupId\",\"type\":\"uint256\"},{\"name\":\"splits\",\"type\":\"tuple[]\",\"components\":[{\"name\":\"percent\",\"type\":\"uint32\"},{\"name\":\"projectId\",\"type\":\"uint64\"},{\"name\":\"beneficiary\",\"type\":\"address\"},{\"name\":\"preferAddToBalance\",\"type\":\"bool\"},{\"name\":\"lockedUntil\",\"type\":\"uint48\"},{\"name\":\"hook\",\"type\":\"address\"}]}]}],\"outputs\":[],\"stateMutability\":\"nonpayable\"}]";
    string internal constant SET_TERMINAL_ABI =
        "[{\"type\":\"function\",\"name\":\"setTerminalFor\",\"inputs\":[{\"name\":\"projectId\",\"type\":\"uint256\"},{\"name\":\"terminal\",\"type\":\"address\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"}]";

    address internal trustedForwarder;
    address internal wrappedNativeToken;
    address internal v3Factory;
    address internal poolManager;
    address internal positionManager;
    address internal usdcToken;

    IJBAddressRegistry internal addressRegistry;
    IJBDirectory internal directory;
    IJBPermissions internal permissions;
    IJBPrices internal prices;
    IJBProjects internal projects;
    IJBTerminal internal multiTerminal;
    IJBTokens internal tokens;
    IJBSuckerRegistry internal suckerRegistry;
    JBFeelessAddresses internal feeless;
    JBBuybackHookRegistry internal buybackRegistry;
    JBRouterTerminalRegistry internal routerTerminalRegistry;
    JBBuybackHook internal oldBuybackHook;
    JBRouterTerminal internal oldRouterTerminal;

    JBUniswapV4Hook internal upgradeUniv4Hook;
    JBBuybackHook internal upgradeBuybackHook;
    JBRouterTerminal internal upgradeRouterTerminal;
    JBUniswapV4LPSplitHook internal upgradeLpSplitHook;
    JBUniswapV4LPSplitHookDeployer internal upgradeLpSplitHookDeployer;

    function _setupChainAddresses() internal {
        if (block.chainid == 1) {
            wrappedNativeToken = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            positionManager = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
        } else if (block.chainid == 11_155_111) {
            wrappedNativeToken = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
            v3Factory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
            poolManager = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
            positionManager = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
        } else if (block.chainid == 10) {
            wrappedNativeToken = 0x4200000000000000000000000000000000000006;
            v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            poolManager = 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
            positionManager = 0x3C3Ea4B57a46241e54610e5f022E5c45859A1017;
        } else if (block.chainid == 11_155_420) {
            wrappedNativeToken = 0x4200000000000000000000000000000000000006;
            v3Factory = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            positionManager = address(0);
        } else if (block.chainid == 8453) {
            wrappedNativeToken = 0x4200000000000000000000000000000000000006;
            v3Factory = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
            poolManager = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
            positionManager = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
        } else if (block.chainid == 84_532) {
            wrappedNativeToken = 0x4200000000000000000000000000000000000006;
            v3Factory = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
            poolManager = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
            positionManager = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
        } else if (block.chainid == 42_161) {
            wrappedNativeToken = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
            v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
            poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
            positionManager = 0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869;
        } else if (block.chainid == 421_614) {
            wrappedNativeToken = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
            v3Factory = 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e;
            poolManager = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
            positionManager = 0xAc631556d3d4019C95769033B5E719dD77124BAc;
        } else {
            revert TwapOracleUpgrade_UnsupportedChain(block.chainid);
        }

        usdcToken = _usdcTokenFor(block.chainid);
    }

    function _loadExistingDeploymentAddresses() internal {
        trustedForwarder = _deploymentAddressOf("ERC2771Forwarder");
        permissions = IJBPermissions(_deploymentAddressOf("JBPermissions"));
        projects = IJBProjects(_deploymentAddressOf("JBProjects"));
        directory = IJBDirectory(_deploymentAddressOf("JBDirectory"));
        prices = IJBPrices(_deploymentAddressOf("JBPrices"));
        tokens = IJBTokens(_deploymentAddressOf("JBTokens"));
        feeless = JBFeelessAddresses(_deploymentAddressOf("JBFeelessAddresses"));
        multiTerminal = IJBTerminal(_deploymentAddressOf("JBMultiTerminal"));
        addressRegistry = IJBAddressRegistry(_deploymentAddressOf("JBAddressRegistry"));
        buybackRegistry = JBBuybackHookRegistry(_deploymentAddressOf("JBBuybackHookRegistry"));
        routerTerminalRegistry = JBRouterTerminalRegistry(payable(_deploymentAddressOf("JBRouterTerminalRegistry")));
        suckerRegistry = IJBSuckerRegistry(_deploymentAddressOf("JBSuckerRegistry"));

        if (_shouldDeployUniswapStack()) {
            oldBuybackHook = JBBuybackHook(payable(_deploymentAddressOf("JBBuybackHook")));
            oldRouterTerminal = JBRouterTerminal(payable(_deploymentAddressOf("JBRouterTerminal")));
        }
    }

    function _deploymentAddressOf(string memory name) internal view returns (address addr) {
        string memory path = string.concat("deployments/", _chainFolder(), "/", name, ".json");
        string memory json = vm.readFile(path);
        addr = json.readAddress(".address");
        if (addr == address(0)) revert TwapOracleUpgrade_MissingDeployment(name);
    }

    function _chainFolder() internal view returns (string memory) {
        if (block.chainid == 1) return "ethereum";
        if (block.chainid == 11_155_111) return "ethereum_sepolia";
        if (block.chainid == 10) return "optimism";
        if (block.chainid == 11_155_420) return "optimism_sepolia";
        if (block.chainid == 8453) return "base";
        if (block.chainid == 84_532) return "base_sepolia";
        if (block.chainid == 42_161) return "arbitrum";
        if (block.chainid == 421_614) return "arbitrum_sepolia";
        revert TwapOracleUpgrade_UnsupportedChain(block.chainid);
    }

    function _shouldDeployUniswapStack() internal view returns (bool) {
        return block.chainid != 11_155_420;
    }

    function _usdcTokenFor(uint256 chainId) internal pure returns (address) {
        if (chainId == 1) return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (chainId == 11_155_111) return 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        if (chainId == 10) return 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
        if (chainId == 11_155_420) return 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;
        if (chainId == 8453) return 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        if (chainId == 84_532) return 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        if (chainId == 42_161) return 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        if (chainId == 421_614) return 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
        return address(0);
    }

    function _saltOf(bytes32 base) internal pure returns (bytes32) {
        return keccak256(abi.encode(DEPLOYMENT_NONCE, TWAP_UPGRADE_NONCE, base));
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
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)),
            deployer: DETERMINISTIC_CREATE2_FACTORY
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
        (bool success,) = DETERMINISTIC_CREATE2_FACTORY.call(abi.encodePacked(foldedSalt, initCode));
        require(success, "Factory CREATE2 failed");
        addr = vm.computeCreate2Address({
            salt: foldedSalt, initCodeHash: keccak256(initCode), deployer: DETERMINISTIC_CREATE2_FACTORY
        });
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

    function _predictPrecompiled(
        string memory artifactName,
        bytes32 salt,
        bytes memory ctorArgs
    )
        internal
        view
        returns (address addr, bool deployed)
    {
        return _isDeployed({salt: salt, creationCode: _loadArtifact(artifactName), arguments: ctorArgs});
    }

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
                deployer: DETERMINISTIC_CREATE2_FACTORY,
                salt: uint256(_saltOf(bytes32(i))),
                creationCodeWithArgs: creationCodeWithArgs
            });
            if (uint160(hookAddress) & HookMiner.FLAG_MASK == flags) return bytes32(i);
        }

        revert("HookMiner: could not find salt");
    }

    function _univ4HookFlags() internal pure returns (uint160) {
        return uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );
    }

    function _univ4HookCtorArgs() internal view returns (bytes memory) {
        return abi.encode(IPoolManager(poolManager), tokens, directory, prices);
    }

    function _buybackHookCtorArgs() internal view returns (bytes memory) {
        return abi.encode(directory, permissions, prices, projects, tokens, EXPECTED_SAFE, trustedForwarder);
    }

    function _routerTerminalCtorArgs() internal view returns (bytes memory) {
        return abi.encode(directory, tokens, PERMIT2, address(upgradeBuybackHook), trustedForwarder, EXPECTED_SAFE);
    }

    function _lpSplitHookCtorArgs() internal view returns (bytes memory) {
        return abi.encode(
            address(directory),
            permissions,
            address(tokens),
            IAllowanceTransfer(address(PERMIT2)),
            IJBSuckerRegistry(address(suckerRegistry))
        );
    }

    function _lpSplitHookDeployerCtorArgs() internal view returns (bytes memory) {
        return abi.encode(IJBAddressRegistry(address(addressRegistry)), upgradeLpSplitHook, EXPECTED_SAFE);
    }

    function _predictOrLoadUpgradeContracts() internal {
        address buybackOverride = vm.envOr({name: "TWAP_UPGRADE_BUYBACK_HOOK", defaultValue: address(0)});
        address routerOverride = vm.envOr({name: "TWAP_UPGRADE_ROUTER_TERMINAL", defaultValue: address(0)});

        bytes memory univ4HookCode = _loadArtifact("JBUniswapV4Hook");
        bytes memory univ4CtorArgs = _univ4HookCtorArgs();
        bytes32 hookSalt =
            _findHookSalt({flags: _univ4HookFlags(), creationCode: univ4HookCode, constructorArgs: univ4CtorArgs});
        (address univ4Hook,) = _isDeployed({salt: hookSalt, creationCode: univ4HookCode, arguments: univ4CtorArgs});
        upgradeUniv4Hook = JBUniswapV4Hook(payable(univ4Hook));

        if (buybackOverride != address(0)) {
            upgradeBuybackHook = JBBuybackHook(payable(buybackOverride));
        } else {
            (address buybackHook,) = _predictPrecompiled({
                artifactName: "JBBuybackHook", salt: BUYBACK_HOOK_SALT, ctorArgs: _buybackHookCtorArgs()
            });
            upgradeBuybackHook = JBBuybackHook(payable(buybackHook));
        }

        if (routerOverride != address(0)) {
            upgradeRouterTerminal = JBRouterTerminal(payable(routerOverride));
        } else {
            (address routerTerminal,) = _predictPrecompiled({
                artifactName: "JBRouterTerminal", salt: ROUTER_TERMINAL_SALT, ctorArgs: _routerTerminalCtorArgs()
            });
            upgradeRouterTerminal = JBRouterTerminal(payable(routerTerminal));
        }

        (address lpSplitHook,) = _predictPrecompiled({
            artifactName: "JBUniswapV4LPSplitHook", salt: LP_SPLIT_HOOK_SALT, ctorArgs: _lpSplitHookCtorArgs()
        });
        upgradeLpSplitHook = JBUniswapV4LPSplitHook(payable(lpSplitHook));

        (address lpSplitHookDeployer,) = _predictPrecompiled({
            artifactName: "JBUniswapV4LPSplitHookDeployer",
            salt: LP_SPLIT_HOOK_DEPLOYER_SALT,
            ctorArgs: _lpSplitHookDeployerCtorArgs()
        });
        upgradeLpSplitHookDeployer = JBUniswapV4LPSplitHookDeployer(lpSplitHookDeployer);
    }

    function _sqrtPriceX96From(uint256 numerator, uint256 denominator) internal pure returns (uint160 sqrtPriceX96) {
        uint256 q192 = 1 << 192;
        uint256 maxRatio = type(uint256).max / q192;
        uint256 maxNumerator = denominator > type(uint256).max / maxRatio ? type(uint256).max : maxRatio * denominator;
        if (denominator == 0 || numerator > maxNumerator) return 0;
        sqrtPriceX96 = uint160(sqrt(mulDiv({x: numerator, y: q192, denominator: denominator})));
    }

    function _poolInitSqrtPriceX96For(
        uint256 projectId,
        address terminalToken
    )
        internal
        view
        returns (bool ok, uint160 sqrtPriceX96)
    {
        address controllerAddress = address(directory.controllerOf(projectId));
        if (controllerAddress == address(0)) return (false, 0);

        JBAccountingContext memory context =
            multiTerminal.accountingContextForTokenOf({projectId: projectId, token: terminalToken});
        if (context.token != terminalToken || context.decimals == 0 || context.currency == 0) return (false, 0);

        (JBRuleset memory ruleset, JBRulesetMetadata memory metadata) =
            IJBController(controllerAddress).currentRulesetOf(projectId);
        if (ruleset.id == 0) return (false, 0);

        uint256 terminalTokenUnit = 10 ** context.decimals;
        uint256 adjustedIssuance;
        if (ruleset.weight == 0) {
            adjustedIssuance = 0;
        } else if (context.currency == metadata.baseCurrency) {
            adjustedIssuance = uint256(ruleset.weight);
        } else {
            try prices.pricePerUnitOf({
                projectId: projectId,
                pricingCurrency: context.currency,
                unitCurrency: metadata.baseCurrency,
                decimals: context.decimals
            }) returns (
                uint256 rate
            ) {
                if (rate == 0) return (false, 0);
                adjustedIssuance = mulDiv({x: uint256(ruleset.weight), y: terminalTokenUnit, denominator: rate});
            } catch {
                return (false, 0);
            }
        }

        if (adjustedIssuance == 0) return (true, uint160(1 << 96));

        address normalizedTerminalToken = _normalizeTerminalToken(terminalToken);
        address projectToken = address(tokens.tokenOf(projectId));
        if (projectToken == address(0) || projectToken == normalizedTerminalToken) return (true, uint160(1 << 96));

        if (normalizedTerminalToken < projectToken) {
            sqrtPriceX96 = _sqrtPriceX96From({numerator: adjustedIssuance, denominator: terminalTokenUnit});
        } else {
            sqrtPriceX96 = _sqrtPriceX96From({numerator: terminalTokenUnit, denominator: adjustedIssuance});
        }

        return (sqrtPriceX96 != 0, sqrtPriceX96);
    }

    function _terminalTokenFor(uint256 projectId) internal view returns (address) {
        address overrideToken = vm.envOr({
            name: string.concat("TWAP_UPGRADE_PROJECT_", vm.toString(projectId), "_TERMINAL_TOKEN"),
            defaultValue: address(0)
        });
        if (overrideToken != address(0)) return overrideToken;
        if (projectId == ART_PROJECT_ID && usdcToken != address(0)) return usdcToken;
        return JBConstants.NATIVE_TOKEN;
    }

    function _normalizeTerminalToken(address terminalToken) internal pure returns (address) {
        return terminalToken == JBConstants.NATIVE_TOKEN ? address(0) : terminalToken;
    }

    function _defaultProjectIds() internal pure returns (uint256[] memory projectIds) {
        projectIds = new uint256[](7);
        projectIds[0] = 1;
        projectIds[1] = 2;
        projectIds[2] = 3;
        projectIds[3] = 4;
        projectIds[4] = 5;
        projectIds[5] = 6;
        projectIds[6] = 7;
    }
}

/// @notice Infra Safe proposal: deploy the new TWAP-aware contracts and set future defaults.
/// @dev Rebuild `artifacts/` from package versions containing the TWAP oracle PRs before proposing.
contract DeployTwapOracleUpgrade is TwapOracleUpgradeBase, Sphinx {
    function configureSphinx() public override {
        sphinxConfig.projectName = "v6-deployment";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        if (safeAddress() != EXPECTED_SAFE) {
            revert TwapOracleUpgrade_UnexpectedSafe({expected: EXPECTED_SAFE, actual: safeAddress()});
        }

        _setupChainAddresses();
        _loadExistingDeploymentAddresses();
        deploy();
        _dumpUpgradeAddresses();
    }

    function deploy() public sphinx {
        if (!_shouldDeployUniswapStack()) return;

        _deployUniv4Hook();
        _deployBuybackHook();
        _deployRouterTerminal();
        _deployLpSplitHook();
        _setNewDefaults();
        _retireOldImplementations();
    }

    function _deployUniv4Hook() internal {
        bytes memory v4HookCode = _loadArtifact("JBUniswapV4Hook");
        bytes memory ctorArgs = _univ4HookCtorArgs();
        bytes32 salt = _findHookSalt({flags: _univ4HookFlags(), creationCode: v4HookCode, constructorArgs: ctorArgs});

        (address hook, bool already) = _isDeployed({salt: salt, creationCode: v4HookCode, arguments: ctorArgs});
        if (!already) hook = _deployViaFactory({salt: salt, creationCode: v4HookCode, constructorArgs: ctorArgs});
        upgradeUniv4Hook = JBUniswapV4Hook(payable(hook));
    }

    function _deployBuybackHook() internal {
        upgradeBuybackHook = JBBuybackHook(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBBuybackHook", salt: BUYBACK_HOOK_SALT, ctorArgs: _buybackHookCtorArgs()
                }))
        );

        if (address(upgradeBuybackHook.poolManager()) == address(0)) {
            upgradeBuybackHook.setChainSpecificConstants({
                newPoolManager: IPoolManager(poolManager), newOracleHook: IHooks(address(upgradeUniv4Hook))
            });
        }
    }

    function _deployRouterTerminal() internal {
        upgradeRouterTerminal = JBRouterTerminal(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBRouterTerminal", salt: ROUTER_TERMINAL_SALT, ctorArgs: _routerTerminalCtorArgs()
                }))
        );

        if (address(upgradeRouterTerminal.wrappedNativeToken()) == address(0)) {
            upgradeRouterTerminal.setChainSpecificConstants({
                newWrappedNativeToken: IWETH9(wrappedNativeToken),
                newFactory: IUniswapV3Factory(v3Factory),
                newPoolManager: IPoolManager(poolManager),
                newUniv4Hook: address(upgradeUniv4Hook)
            });
        }
    }

    function _deployLpSplitHook() internal {
        upgradeLpSplitHook = JBUniswapV4LPSplitHook(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBUniswapV4LPSplitHook", salt: LP_SPLIT_HOOK_SALT, ctorArgs: _lpSplitHookCtorArgs()
                }))
        );

        upgradeLpSplitHookDeployer = JBUniswapV4LPSplitHookDeployer(
            _deployPrecompiledIfNeeded({
                artifactName: "JBUniswapV4LPSplitHookDeployer",
                salt: LP_SPLIT_HOOK_DEPLOYER_SALT,
                ctorArgs: _lpSplitHookDeployerCtorArgs()
            })
        );

        if (address(upgradeLpSplitHookDeployer.poolManager()) == address(0)) {
            upgradeLpSplitHookDeployer.setChainSpecificConstants({
                newPoolManager: IPoolManager(poolManager),
                newPositionManager: IPositionManager(positionManager),
                newOracleHook: IHooks(address(upgradeUniv4Hook))
            });
        }
    }

    function _setNewDefaults() internal {
        if (address(buybackRegistry.defaultHook()) != address(upgradeBuybackHook)) {
            buybackRegistry.setDefaultHook({hook: IJBRulesetDataHook(address(upgradeBuybackHook))});
        }

        if (address(routerTerminalRegistry.defaultTerminal()) != address(upgradeRouterTerminal)) {
            routerTerminalRegistry.setDefaultTerminal({terminal: IJBTerminal(address(upgradeRouterTerminal))});
        }
    }

    function _retireOldImplementations() internal {
        if (
            address(oldBuybackHook) != address(0) && address(oldBuybackHook) != address(upgradeBuybackHook)
                && buybackRegistry.isHookAllowed(IJBRulesetDataHook(address(oldBuybackHook)))
        ) {
            buybackRegistry.disallowHook({hook: IJBRulesetDataHook(address(oldBuybackHook))});
        }

        if (
            address(oldRouterTerminal) != address(0) && address(oldRouterTerminal) != address(upgradeRouterTerminal)
                && routerTerminalRegistry.isTerminalAllowed(IJBTerminal(address(oldRouterTerminal)))
        ) {
            routerTerminalRegistry.disallowTerminal({terminal: IJBTerminal(address(oldRouterTerminal))});
        }

        if (
            address(oldRouterTerminal) != address(0) && address(oldRouterTerminal) != address(upgradeRouterTerminal)
                && feeless.isFeelessFor({addr: address(oldRouterTerminal), projectId: 0, caller: address(0)})
        ) {
            feeless.setFeelessAddress({addr: address(oldRouterTerminal), flag: false});
        }
    }

    function _dumpUpgradeAddresses() internal {
        string memory key = "_jbV6TwapOracleUpgrade";
        vm.serializeString({objectKey: key, valueKey: "format", value: "jb-v6-twap-oracle-upgrade-addresses-1"});
        vm.serializeUint({objectKey: key, valueKey: "chainId", value: block.chainid});
        string memory out =
            vm.serializeBool({objectKey: key, valueKey: "uniswapStackSkipped", value: !_shouldDeployUniswapStack()});

        if (address(upgradeUniv4Hook) != address(0)) {
            out = vm.serializeAddress({
                objectKey: key, valueKey: "JBUniswapV4Hook__TwapOracleUpgrade", value: address(upgradeUniv4Hook)
            });
        }
        if (address(upgradeBuybackHook) != address(0)) {
            out = vm.serializeAddress({
                objectKey: key, valueKey: "JBBuybackHook__TwapOracleUpgrade", value: address(upgradeBuybackHook)
            });
        }
        if (address(upgradeRouterTerminal) != address(0)) {
            out = vm.serializeAddress({
                objectKey: key, valueKey: "JBRouterTerminal__TwapOracleUpgrade", value: address(upgradeRouterTerminal)
            });
        }
        if (address(upgradeLpSplitHook) != address(0)) {
            out = vm.serializeAddress({
                objectKey: key,
                valueKey: "JBUniswapV4LPSplitHook__TwapOracleUpgrade",
                value: address(upgradeLpSplitHook)
            });
        }
        if (address(upgradeLpSplitHookDeployer) != address(0)) {
            out = vm.serializeAddress({
                objectKey: key,
                valueKey: "JBUniswapV4LPSplitHookDeployer__TwapOracleUpgrade",
                value: address(upgradeLpSplitHookDeployer)
            });
        }
        if (address(oldBuybackHook) != address(0)) {
            out = vm.serializeAddress({
                objectKey: key, valueKey: "JBBuybackHook__RetiredTwapOracleUpgrade", value: address(oldBuybackHook)
            });
        }
        if (address(oldRouterTerminal) != address(0)) {
            out = vm.serializeAddress({
                objectKey: key,
                valueKey: "JBRouterTerminal__RetiredTwapOracleUpgrade",
                value: address(oldRouterTerminal)
            });
        }

        vm.createDir({path: "script/post-deploy/.cache", recursive: true});
        vm.writeJson({
            json: out,
            path: string.concat(
                "script/post-deploy/.cache/twap-oracle-upgrade-addresses-", vm.toString(block.chainid), ".json"
            )
        });
    }
}

/// @notice Offline helper for revnet operators. It writes Safe-ready rows for projects 1-7 on the active chain.
contract GenerateTwapOracleUpgradeOperatorSafeTxs is TwapOracleUpgradeBase {
    function run() external {
        _setupChainAddresses();
        _loadExistingDeploymentAddresses();
        if (!_shouldDeployUniswapStack()) {
            _writeOperatorSafeRowsSkipped();
            return;
        }
        _predictOrLoadUpgradeContracts();
        _writeOperatorSafeRows(_defaultProjectIds());
    }

    function _bannyLpSplitHookForOperator() internal view returns (JBUniswapV4LPSplitHook) {
        return JBUniswapV4LPSplitHook(
            payable(LibClone.predictDeterministicAddress({
                    implementation: address(upgradeLpSplitHook),
                    salt: keccak256(abi.encode(BANNY_OPERATOR, BANNY_LP_SPLIT_HOOK_SALT)),
                    deployer: address(upgradeLpSplitHookDeployer)
                }))
        );
    }

    function _bannyLpSplitHookSplitGroups(JBUniswapV4LPSplitHook lpSplitHook)
        internal
        pure
        returns (JBSplitGroup[] memory splitGroups)
    {
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(lpSplitHook))
        });

        splitGroups = new JBSplitGroup[](1);
        splitGroups[0] = JBSplitGroup({groupId: JBSplitGroupIds.RESERVED_TOKENS, splits: splits});
    }

    function _writeBannyLpSplitHookRows(string memory path, address controller) internal {
        JBUniswapV4LPSplitHook lpSplitHook = _bannyLpSplitHookForOperator();

        _writeSafeRow({
            path: path,
            title: "4. Deploy Banny LP split hook",
            target: address(upgradeLpSplitHookDeployer),
            abiJson: DEPLOY_LP_SPLIT_HOOK_ABI,
            data: abi.encodeCall(
                JBUniswapV4LPSplitHookDeployer.deployHookFor,
                (
                    LP_SPLIT_HOOK_FEE_PROJECT_ID,
                    LP_SPLIT_HOOK_FEE_PERCENT,
                    IJBBuybackHookRegistry(address(buybackRegistry)),
                    BANNY_LP_SPLIT_HOOK_SALT
                )
            )
        });

        vm.writeLine({
            path: path,
            data: string.concat(
                "Expected Banny LP split hook: `",
                vm.toString(address(lpSplitHook)),
                "`\n\n",
                "LP fee args: `feeProjectId=",
                vm.toString(LP_SPLIT_HOOK_FEE_PROJECT_ID),
                "`, `feePercent=",
                vm.toString(LP_SPLIT_HOOK_FEE_PERCENT),
                "`\n"
            )
        });

        (JBRuleset memory ruleset,) = IJBController(controller).currentRulesetOf(BANNY_PROJECT_ID);
        _writeSafeRow({
            path: path,
            title: "5. Route Banny reserved split to LP split hook",
            target: controller,
            abiJson: SET_SPLIT_GROUPS_ABI,
            data: abi.encodeCall(
                IJBController.setSplitGroupsOf,
                (BANNY_PROJECT_ID, ruleset.id, _bannyLpSplitHookSplitGroups(lpSplitHook))
            )
        });

        vm.writeLine({
            path: path,
            data: string.concat(
                "Split args: `rulesetId=",
                vm.toString(ruleset.id),
                "`, `groupId=1`, `splitPercent=",
                vm.toString(JBConstants.SPLITS_TOTAL_PERCENT),
                "`, `hook=",
                vm.toString(address(lpSplitHook)),
                "`\n"
            )
        });
    }

    function _writeOperatorSafeRows(uint256[] memory projectIds) internal {
        string memory path = string.concat(
            "script/post-deploy/.cache/twap-oracle-upgrade-operator-safe-txs-", vm.toString(block.chainid), ".md"
        );
        vm.createDir({path: "script/post-deploy/.cache", recursive: true});
        vm.writeFile({
            path: path,
            data: string.concat(
                "# TWAP Oracle Upgrade Operator Safe Transactions - ",
                _chainFolder(),
                "\n\n",
                "Submit these from each revnet's operator Safe, after the infra Safe upgrade has executed.\n\n",
                "New buyback hook: `",
                vm.toString(address(upgradeBuybackHook)),
                "`\n\n",
                "New router terminal: `",
                vm.toString(address(upgradeRouterTerminal)),
                "`\n\n",
                "New LP split hook deployer: `",
                vm.toString(address(upgradeLpSplitHookDeployer)),
                "`\n\n"
            )
        });

        for (uint256 i; i < projectIds.length; i++) {
            _writeProjectRows({path: path, projectId: projectIds[i]});
        }
    }

    function _writeOperatorSafeRowsSkipped() internal {
        string memory path = string.concat(
            "script/post-deploy/.cache/twap-oracle-upgrade-operator-safe-txs-", vm.toString(block.chainid), ".md"
        );
        vm.createDir({path: "script/post-deploy/.cache", recursive: true});
        vm.writeFile({
            path: path,
            data: string.concat(
                "# TWAP Oracle Upgrade Operator Safe Transactions - ",
                _chainFolder(),
                "\n\nSkipped: this chain has no Uniswap V4 PositionManager configured in deploy-all-v6.\n"
            )
        });
    }

    function _writeProjectRows(string memory path, uint256 projectId) internal {
        address terminalToken = _terminalTokenFor(projectId);
        address controller = address(directory.controllerOf(projectId));
        if (controller == address(0)) {
            vm.writeLine({
                path: path,
                data: string.concat(
                    "## Project ", vm.toString(projectId), "\n\nSkipped: no controller on this chain.\n"
                )
            });
            return;
        }

        vm.writeLine({path: path, data: string.concat("## Project ", vm.toString(projectId), "\n")});
        _writeSafeRow({
            path: path,
            title: "1. Set buyback hook",
            target: address(buybackRegistry),
            abiJson: SET_HOOK_ABI,
            data: abi.encodeCall(
                JBBuybackHookRegistry.setHookFor, (projectId, IJBRulesetDataHook(address(upgradeBuybackHook)))
            )
        });

        _writeSafeRow({
            path: path,
            title: "2. Set router terminal",
            target: address(routerTerminalRegistry),
            abiJson: SET_TERMINAL_ABI,
            data: abi.encodeCall(
                JBRouterTerminalRegistry.setTerminalFor, (projectId, IJBTerminal(address(upgradeRouterTerminal)))
            )
        });

        (bool ok, uint160 sqrtPriceX96) = _poolInitSqrtPriceX96For({projectId: projectId, terminalToken: terminalToken});
        if (!ok) {
            vm.writeLine({
                path: path,
                data: string.concat(
                    "### 3. Initialize buyback pool\n\n",
                    "Skipped: could not compute a pool start price for terminal token `",
                    vm.toString(terminalToken),
                    "`. Check accounting context and price feeds.\n"
                )
            });
        } else {
            _writeSafeRow({
                path: path,
                title: "3. Initialize buyback pool",
                target: address(buybackRegistry),
                abiJson: INITIALIZE_POOL_ABI,
                data: abi.encodeCall(
                    JBBuybackHookRegistry.initializePoolFor,
                    (
                        projectId,
                        DEFAULT_BUYBACK_POOL_FEE,
                        DEFAULT_BUYBACK_TICK_SPACING,
                        DEFAULT_BUYBACK_TWAP_WINDOW,
                        terminalToken,
                        sqrtPriceX96
                    )
                )
            });

            vm.writeLine({
                path: path,
                data: string.concat(
                    "Pool args: `fee=10000`, `tickSpacing=200`, `twapWindow=172800`, `terminalToken=",
                    vm.toString(terminalToken),
                    "`, `sqrtPriceX96=",
                    vm.toString(uint256(sqrtPriceX96)),
                    "`\n"
                )
            });
        }

        if (projectId == BANNY_PROJECT_ID) _writeBannyLpSplitHookRows({path: path, controller: controller});
    }

    function _writeSafeRow(
        string memory path,
        string memory title,
        address target,
        string memory abiJson,
        bytes memory data
    )
        internal
    {
        vm.writeLine({path: path, data: string.concat("### ", title, "\n")});
        vm.writeLine({path: path, data: string.concat("Address: `", vm.toString(target), "`\n")});
        vm.writeLine({path: path, data: "ABI:\n```json"});
        vm.writeLine({path: path, data: abiJson});
        vm.writeLine({path: path, data: "```\n"});
        vm.writeLine({path: path, data: "Custom data:\n```text"});
        vm.writeLine({path: path, data: vm.toString(data)});
        vm.writeLine({path: path, data: "```\n"});
    }
}
