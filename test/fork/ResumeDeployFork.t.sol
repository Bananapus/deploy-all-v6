// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBPrices} from "@bananapus/core-v6/src/JBPrices.sol";
import {JBRulesets} from "@bananapus/core-v6/src/JBRulesets.sol";
import {JBDirectory} from "@bananapus/core-v6/src/JBDirectory.sol";
import {JBERC20} from "@bananapus/core-v6/src/JBERC20.sol";
import {JBTokens} from "@bananapus/core-v6/src/JBTokens.sol";
import {JBSplits} from "@bananapus/core-v6/src/JBSplits.sol";
import {JBFeelessAddresses} from "@bananapus/core-v6/src/JBFeelessAddresses.sol";
import {JBFundAccessLimits} from "@bananapus/core-v6/src/JBFundAccessLimits.sol";
import {JBController} from "@bananapus/core-v6/src/JBController.sol";
import {JBTerminalStore} from "@bananapus/core-v6/src/JBTerminalStore.sol";
import {JBMultiTerminal} from "@bananapus/core-v6/src/JBMultiTerminal.sol";
import {ERC2771Forwarder} from "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";

import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";

import {JBDeadline3Hours} from "@bananapus/core-v6/src/periphery/JBDeadline3Hours.sol";
import {JBDeadline1Day} from "@bananapus/core-v6/src/periphery/JBDeadline1Day.sol";
import {JBDeadline3Days} from "@bananapus/core-v6/src/periphery/JBDeadline3Days.sol";
import {JBDeadline7Days} from "@bananapus/core-v6/src/periphery/JBDeadline7Days.sol";
import {JBMatchingPriceFeed} from "@bananapus/core-v6/src/periphery/JBMatchingPriceFeed.sol";

import {JBChainlinkV3PriceFeed, AggregatorV3Interface} from "@bananapus/core-v6/src/JBChainlinkV3PriceFeed.sol";

import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHookProjectDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookProjectDeployer.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";
import {JB721CheckpointsDeployer} from "@bananapus/721-hook-v6/src/JB721CheckpointsDeployer.sol";
import {IJB721CheckpointsDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721CheckpointsDeployer.sol";

import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {JBUniswapV4Hook} from "@bananapus/univ4-router-v6/src/JBUniswapV4Hook.sol";
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";
import {JBUniswapV4LPSplitHookDeployer} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHookDeployer.sol";

import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";
import {IWETH9} from "@bananapus/router-terminal-v6/src/interfaces/IWETH9.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";

import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";

contract ResumeDeployHarness is IERC721Receiver {
    IPermit2 private constant _PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    string private constant TRUSTED_FORWARDER_NAME = "Juicebox";
    uint256 private constant CORE_DEPLOYMENT_NONCE = 6;
    uint256 private constant _CPN_PROJECT_ID = 2;
    uint256 private constant _REV_PROJECT_ID = 3;

    bytes32 private constant DEADLINES_SALT = keccak256("_JBDeadlinesV6_");
    bytes32 private constant ADDRESS_REGISTRY_SALT = "_JBAddressRegistryV6_";
    bytes32 private constant HOOK_721_STORE_SALT = "JB721TiersHookStoreV6_";
    bytes32 private constant HOOK_721_SALT = "JB721TiersHookV6_";
    bytes32 private constant HOOK_721_DEPLOYER_SALT = "JB721TiersHookDeployerV6_";
    bytes32 private constant HOOK_721_PROJECT_DEPLOYER_SALT = "JB721TiersHookProjectDeployerV6";
    bytes32 private constant HOOK_721_CHECKPOINTS_DEPLOYER_SALT = "JB721CheckpointsDeployerV6";
    bytes32 private constant BUYBACK_HOOK_SALT = "JBBuybackHookV6";
    bytes32 private constant ROUTER_TERMINAL_SALT = "JBRouterTerminalV6";
    bytes32 private constant ROUTER_TERMINAL_REGISTRY_SALT = "JBRouterTerminalRegistryV6";
    bytes32 private constant LP_SPLIT_HOOK_SALT = "JBUniswapV4LPSplitHookV6";
    bytes32 private constant LP_SPLIT_HOOK_DEPLOYER_SALT = "JBUniswapV4LPSplitHookDeployerV6";
    bytes32 private constant SUCKER_REGISTRY_SALT = "REGISTRYV6";
    bytes32 private constant OMNICHAIN_DEPLOYER_SALT = "JBOmnichainDeployerV6_";

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address private constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address private constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address private constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    address public trustedForwarder;
    JBPermissions public permissions;
    JBProjects public projects;
    JBDirectory public directory;
    JBSplits public splits;
    JBRulesets public rulesets;
    JBPrices public prices;
    JBTokens public tokens;
    JBFundAccessLimits public fundAccess;
    JBFeelessAddresses public feeless;
    JBTerminalStore public terminalStore;
    JBMultiTerminal public terminal;
    JBController public controller;

    JBAddressRegistry public addressRegistry;
    JB721TiersHookStore public hookStore;
    JB721CheckpointsDeployer public checkpointsDeployer;
    JB721TiersHook public hook721;
    JB721TiersHookDeployer public hookDeployer;
    JB721TiersHookProjectDeployer public hookProjectDeployer;
    JBUniswapV4Hook public uniswapV4Hook;
    JBBuybackHookRegistry public buybackRegistry;
    JBBuybackHook public buybackHook;
    JBRouterTerminalRegistry public routerTerminalRegistry;
    JBRouterTerminal public routerTerminal;
    JBUniswapV4LPSplitHook public lpSplitHook;
    JBUniswapV4LPSplitHookDeployer public lpSplitHookDeployer;
    JBSuckerRegistry public suckerRegistry;
    JBOmnichainDeployer public omnichainDeployer;

    uint256 public cpnProjectId;
    uint256 public revProjectId;
    bytes32 public uniswapV4HookSalt;

    function deployThroughRouterTerminal() external {
        _deployCore();
        _deployAddressRegistry();
        _deploy721Hook();
        _deployUniswapV4Hook();
        _deployBuybackHook();
        _deployRouterTerminal();
    }

    function deployInfrastructureAndReserveProjectIds() external {
        _deployCore();
        _deployAddressRegistry();
        _deploy721Hook();
        _deployUniswapV4Hook();
        _deployBuybackHook();
        _deployRouterTerminal();
        _deployLpSplitHook();
        _deploySuckers();
        _deployOmnichainDeployer();
        _deployPeriphery();
        cpnProjectId = _ensureProjectExists(_CPN_PROJECT_ID);
        revProjectId = _ensureProjectExists(_REV_PROJECT_ID);
    }

    function expectedUniswapV4HookAddress() external view returns (address) {
        return _create2Address(
            uniswapV4HookSalt,
            type(JBUniswapV4Hook).creationCode,
            abi.encode(IPoolManager(POOL_MANAGER), tokens, directory, prices)
        );
    }

    function expectedRouterTerminalAddress() external view returns (address) {
        return _create2Address(
            ROUTER_TERMINAL_SALT,
            type(JBRouterTerminal).creationCode,
            abi.encode(
                directory,
                tokens,
                _PERMIT2,
                IWETH9(WETH),
                IUniswapV3Factory(V3_FACTORY),
                IPoolManager(POOL_MANAGER),
                address(buybackHook),
                address(uniswapV4Hook),
                trustedForwarder
            )
        );
    }

    function expectedControllerAddress() external view returns (address) {
        return _create2Address(
            DEADLINES_SALT,
            type(JBController).creationCode,
            abi.encode(
                directory,
                fundAccess,
                permissions,
                prices,
                projects,
                rulesets,
                splits,
                tokens,
                address(omnichainDeployer),
                trustedForwarder
            )
        );
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _deployCore() internal {
        bytes32 coreSalt = keccak256(abi.encode(CORE_DEPLOYMENT_NONCE));
        (address trustedForwarderAddress, bool trustedForwarderDeployed) =
            _isDeployed(coreSalt, type(ERC2771Forwarder).creationCode, abi.encode(TRUSTED_FORWARDER_NAME));
        trustedForwarder = trustedForwarderDeployed
            ? trustedForwarderAddress
            : address(new ERC2771Forwarder{salt: coreSalt}(TRUSTED_FORWARDER_NAME));

        (address permissionsAddress, bool permissionsDeployed) =
            _isDeployed(coreSalt, type(JBPermissions).creationCode, abi.encode(trustedForwarder));
        permissions = permissionsDeployed
            ? JBPermissions(permissionsAddress)
            : new JBPermissions{salt: coreSalt}(trustedForwarder);

        (address projectsAddress, bool projectsDeployed) = _isDeployed(
            coreSalt, type(JBProjects).creationCode, abi.encode(address(this), address(this), trustedForwarder)
        );
        projects = projectsDeployed
            ? JBProjects(projectsAddress)
            : new JBProjects{salt: coreSalt}({
                owner: address(this), feeProjectOwner: address(this), trustedForwarder: trustedForwarder
            });

        (address directoryAddress, bool directoryDeployed) =
            _isDeployed(coreSalt, type(JBDirectory).creationCode, abi.encode(permissions, projects, address(this)));
        directory = directoryDeployed
            ? JBDirectory(directoryAddress)
            : new JBDirectory{salt: coreSalt}({permissions: permissions, projects: projects, owner: address(this)});

        (address splitsAddress, bool splitsDeployed) =
            _isDeployed(coreSalt, type(JBSplits).creationCode, abi.encode(directory));
        splits = splitsDeployed ? JBSplits(splitsAddress) : new JBSplits{salt: coreSalt}({directory: directory});

        (address rulesetsAddress, bool rulesetsDeployed) =
            _isDeployed(coreSalt, type(JBRulesets).creationCode, abi.encode(directory));
        rulesets =
            rulesetsDeployed ? JBRulesets(rulesetsAddress) : new JBRulesets{salt: coreSalt}({directory: directory});

        (address pricesAddress, bool pricesDeployed) = _isDeployed(
            coreSalt,
            type(JBPrices).creationCode,
            abi.encode(directory, permissions, projects, address(this), trustedForwarder)
        );
        prices = pricesDeployed
            ? JBPrices(pricesAddress)
            : new JBPrices{salt: coreSalt}({
                directory: directory,
                permissions: permissions,
                projects: projects,
                owner: address(this),
                trustedForwarder: trustedForwarder
            });

        (address erc20Address, bool erc20Deployed) =
            _isDeployed(coreSalt, type(JBERC20).creationCode, abi.encode(permissions, projects));
        JBERC20 erc20 = erc20Deployed ? JBERC20(erc20Address) : new JBERC20{salt: coreSalt}(permissions, projects);

        (address tokensAddress, bool tokensDeployed) =
            _isDeployed(coreSalt, type(JBTokens).creationCode, abi.encode(directory, erc20));
        tokens = tokensDeployed
            ? JBTokens(tokensAddress)
            : new JBTokens{salt: coreSalt}({directory: directory, token: erc20});

        (address fundAccessAddress, bool fundAccessDeployed) =
            _isDeployed(coreSalt, type(JBFundAccessLimits).creationCode, abi.encode(directory));
        fundAccess = fundAccessDeployed
            ? JBFundAccessLimits(fundAccessAddress)
            : new JBFundAccessLimits{salt: coreSalt}({directory: directory});

        (address feelessAddress, bool feelessDeployed) =
            _isDeployed(coreSalt, type(JBFeelessAddresses).creationCode, abi.encode(address(this)));
        feeless = feelessDeployed
            ? JBFeelessAddresses(feelessAddress)
            : new JBFeelessAddresses{salt: coreSalt}({owner: address(this)});

        (address terminalStoreAddress, bool terminalStoreDeployed) =
            _isDeployed(coreSalt, type(JBTerminalStore).creationCode, abi.encode(directory, prices, rulesets));
        terminalStore = terminalStoreDeployed
            ? JBTerminalStore(terminalStoreAddress)
            : new JBTerminalStore{salt: coreSalt}({directory: directory, rulesets: rulesets, prices: prices});

        (address terminalAddress, bool terminalDeployed) = _isDeployed(
            coreSalt,
            type(JBMultiTerminal).creationCode,
            abi.encode(feeless, permissions, projects, splits, terminalStore, tokens, _PERMIT2, trustedForwarder)
        );
        terminal = terminalDeployed
            ? JBMultiTerminal(terminalAddress)
            : new JBMultiTerminal{salt: coreSalt}({
                feelessAddresses: feeless,
                permissions: permissions,
                projects: projects,
                splits: splits,
                store: terminalStore,
                tokens: tokens,
                permit2: _PERMIT2,
                trustedForwarder: trustedForwarder
            });
    }

    function _deployAddressRegistry() internal {
        (address registryAddress, bool deployed) =
            _isDeployed(ADDRESS_REGISTRY_SALT, type(JBAddressRegistry).creationCode, "");
        addressRegistry =
            deployed ? JBAddressRegistry(registryAddress) : new JBAddressRegistry{salt: ADDRESS_REGISTRY_SALT}();
    }

    function _deploy721Hook() internal {
        (address hookStoreAddress, bool hookStoreDeployed) =
            _isDeployed(HOOK_721_STORE_SALT, type(JB721TiersHookStore).creationCode, "");
        hookStore = hookStoreDeployed
            ? JB721TiersHookStore(hookStoreAddress)
            : new JB721TiersHookStore{salt: HOOK_721_STORE_SALT}();

        (address checkpointsDeployerAddress, bool checkpointsDeployerDeployed) =
            _isDeployed(HOOK_721_CHECKPOINTS_DEPLOYER_SALT, type(JB721CheckpointsDeployer).creationCode, "");
        checkpointsDeployer = checkpointsDeployerDeployed
            ? JB721CheckpointsDeployer(checkpointsDeployerAddress)
            : new JB721CheckpointsDeployer{salt: HOOK_721_CHECKPOINTS_DEPLOYER_SALT}();

        (address hook721Address, bool hook721Deployed) = _isDeployed(
            HOOK_721_SALT,
            type(JB721TiersHook).creationCode,
            abi.encode(
                directory, permissions, prices, rulesets, hookStore, splits, checkpointsDeployer, trustedForwarder
            )
        );
        hook721 = hook721Deployed
            ? JB721TiersHook(hook721Address)
            : new JB721TiersHook{salt: HOOK_721_SALT}({
                directory: directory,
                permissions: permissions,
                prices: prices,
                rulesets: rulesets,
                store: hookStore,
                splits: splits,
                checkpointsDeployer: IJB721CheckpointsDeployer(checkpointsDeployer),
                trustedForwarder: trustedForwarder
            });

        (address hookDeployerAddress, bool hookDeployerDeployed) = _isDeployed(
            HOOK_721_DEPLOYER_SALT,
            type(JB721TiersHookDeployer).creationCode,
            abi.encode(hook721, hookStore, IJBAddressRegistry(address(addressRegistry)), trustedForwarder)
        );
        hookDeployer = hookDeployerDeployed
            ? JB721TiersHookDeployer(hookDeployerAddress)
            : new JB721TiersHookDeployer{salt: HOOK_721_DEPLOYER_SALT}({
                hook: hook721,
                store: hookStore,
                addressRegistry: IJBAddressRegistry(address(addressRegistry)),
                trustedForwarder: trustedForwarder
            });

        (address hookProjectDeployerAddress, bool hookProjectDeployerDeployed) = _isDeployed(
            HOOK_721_PROJECT_DEPLOYER_SALT,
            type(JB721TiersHookProjectDeployer).creationCode,
            abi.encode(directory, permissions, hookDeployer, trustedForwarder)
        );
        hookProjectDeployer = hookProjectDeployerDeployed
            ? JB721TiersHookProjectDeployer(hookProjectDeployerAddress)
            : new JB721TiersHookProjectDeployer{salt: HOOK_721_PROJECT_DEPLOYER_SALT}({
                directory: directory,
                permissions: permissions,
                hookDeployer: hookDeployer,
                trustedForwarder: trustedForwarder
            });
    }

    function _deployUniswapV4Hook() internal {
        (, bytes32 salt) = _hookSalt();
        uniswapV4HookSalt = salt;
        (address hookAddress, bool deployed) = _isDeployed(
            salt, type(JBUniswapV4Hook).creationCode, abi.encode(IPoolManager(POOL_MANAGER), tokens, directory, prices)
        );
        uniswapV4Hook = deployed
            ? JBUniswapV4Hook(payable(hookAddress))
            : new JBUniswapV4Hook{salt: salt}({
                poolManager: IPoolManager(POOL_MANAGER), tokens: tokens, directory: directory, prices: prices
            });
    }

    function _deployBuybackHook() internal {
        (address registryAddress, bool registryDeployed) = _isDeployed(
            BUYBACK_HOOK_SALT,
            type(JBBuybackHookRegistry).creationCode,
            abi.encode(permissions, projects, address(this), trustedForwarder)
        );
        buybackRegistry = registryDeployed
            ? JBBuybackHookRegistry(registryAddress)
            : new JBBuybackHookRegistry{salt: BUYBACK_HOOK_SALT}({
                permissions: permissions, projects: projects, owner: address(this), trustedForwarder: trustedForwarder
            });

        (address hookAddress, bool hookDeployed) = _isDeployed(
            BUYBACK_HOOK_SALT,
            type(JBBuybackHook).creationCode,
            abi.encode(
                directory,
                permissions,
                prices,
                projects,
                tokens,
                IPoolManager(POOL_MANAGER),
                IHooks(address(uniswapV4Hook)),
                trustedForwarder
            )
        );
        buybackHook = hookDeployed
            ? JBBuybackHook(payable(hookAddress))
            : new JBBuybackHook{salt: BUYBACK_HOOK_SALT}({
                directory: directory,
                permissions: permissions,
                prices: prices,
                projects: projects,
                tokens: tokens,
                poolManager: IPoolManager(POOL_MANAGER),
                oracleHook: IHooks(address(uniswapV4Hook)),
                trustedForwarder: trustedForwarder
            });

        if (address(buybackRegistry.defaultHook()) == address(0)) {
            buybackRegistry.setDefaultHook({hook: IJBRulesetDataHook(address(buybackHook))});
        }
    }

    function _deployRouterTerminal() internal {
        (address registryAddress, bool registryDeployed) = _isDeployed(
            ROUTER_TERMINAL_REGISTRY_SALT,
            type(JBRouterTerminalRegistry).creationCode,
            abi.encode(permissions, projects, _PERMIT2, address(this), trustedForwarder)
        );
        routerTerminalRegistry = registryDeployed
            ? JBRouterTerminalRegistry(payable(registryAddress))
            : new JBRouterTerminalRegistry{salt: ROUTER_TERMINAL_REGISTRY_SALT}({
                permissions: permissions,
                projects: projects,
                permit2: _PERMIT2,
                owner: address(this),
                trustedForwarder: trustedForwarder
            });

        (address terminalAddress, bool terminalDeployed) = _isDeployed(
            ROUTER_TERMINAL_SALT,
            type(JBRouterTerminal).creationCode,
            abi.encode(
                directory,
                tokens,
                _PERMIT2,
                IWETH9(WETH),
                IUniswapV3Factory(V3_FACTORY),
                IPoolManager(POOL_MANAGER),
                address(buybackHook),
                address(uniswapV4Hook),
                trustedForwarder
            )
        );
        routerTerminal = terminalDeployed
            ? JBRouterTerminal(payable(terminalAddress))
            : new JBRouterTerminal{salt: ROUTER_TERMINAL_SALT}({
                directory: directory,
                tokens: tokens,
                permit2: _PERMIT2,
                weth: IWETH9(WETH),
                factory: IUniswapV3Factory(V3_FACTORY),
                poolManager: IPoolManager(POOL_MANAGER),
                buybackHook: address(buybackHook),
                univ4Hook: address(uniswapV4Hook),
                trustedForwarder: trustedForwarder
            });

        if (address(routerTerminalRegistry.defaultTerminal()) == address(0)) {
            routerTerminalRegistry.setDefaultTerminal({terminal: IJBTerminal(address(routerTerminal))});
        }
        if (!feeless.isFeeless(address(routerTerminal))) {
            feeless.setFeelessAddress({addr: address(routerTerminal), flag: true});
        }
    }

    function _deployLpSplitHook() internal {
        (address hookAddress, bool hookDeployed) = _isDeployed(
            LP_SPLIT_HOOK_SALT,
            type(JBUniswapV4LPSplitHook).creationCode,
            abi.encode(
                address(directory),
                permissions,
                address(tokens),
                IPoolManager(POOL_MANAGER),
                IPositionManager(POSITION_MANAGER),
                IAllowanceTransfer(address(_PERMIT2)),
                IHooks(address(uniswapV4Hook))
            )
        );
        lpSplitHook = hookDeployed
            ? JBUniswapV4LPSplitHook(payable(hookAddress))
            : new JBUniswapV4LPSplitHook{salt: LP_SPLIT_HOOK_SALT}(
                address(directory),
                permissions,
                address(tokens),
                IPoolManager(POOL_MANAGER),
                IPositionManager(POSITION_MANAGER),
                IAllowanceTransfer(address(_PERMIT2)),
                IHooks(address(uniswapV4Hook))
            );

        (address deployerAddress, bool deployerDeployed) = _isDeployed(
            LP_SPLIT_HOOK_DEPLOYER_SALT,
            type(JBUniswapV4LPSplitHookDeployer).creationCode,
            abi.encode(lpSplitHook, IJBAddressRegistry(address(addressRegistry)))
        );
        lpSplitHookDeployer = deployerDeployed
            ? JBUniswapV4LPSplitHookDeployer(deployerAddress)
            : new JBUniswapV4LPSplitHookDeployer{salt: LP_SPLIT_HOOK_DEPLOYER_SALT}(
                lpSplitHook, IJBAddressRegistry(address(addressRegistry))
            );
    }

    function _deploySuckers() internal {
        (address registryAddress, bool registryDeployed) = _isDeployed(
            SUCKER_REGISTRY_SALT,
            type(JBSuckerRegistry).creationCode,
            abi.encode(directory, permissions, address(this), trustedForwarder)
        );
        suckerRegistry = registryDeployed
            ? JBSuckerRegistry(registryAddress)
            : new JBSuckerRegistry{salt: SUCKER_REGISTRY_SALT}(directory, permissions, address(this), trustedForwarder);

        address[2] memory preApproved = [address(0x1001), address(0x1002)];
        for (uint256 i; i < preApproved.length; i++) {
            if (!suckerRegistry.suckerDeployerIsAllowed(preApproved[i])) {
                address[] memory deployers = new address[](1);
                deployers[0] = preApproved[i];
                suckerRegistry.allowSuckerDeployers(deployers);
            }
        }
    }

    function _deployOmnichainDeployer() internal {
        (address deployerAddress, bool deployed) = _isDeployed(
            OMNICHAIN_DEPLOYER_SALT,
            type(JBOmnichainDeployer).creationCode,
            abi.encode(
                suckerRegistry,
                IJB721TiersHookDeployer(address(hookDeployer)),
                permissions,
                projects,
                directory,
                trustedForwarder
            )
        );
        omnichainDeployer = deployed
            ? JBOmnichainDeployer(deployerAddress)
            : new JBOmnichainDeployer{salt: OMNICHAIN_DEPLOYER_SALT}(
                suckerRegistry,
                IJB721TiersHookDeployer(address(hookDeployer)),
                permissions,
                projects,
                directory,
                trustedForwarder
            );
    }

    function _deployPeriphery() internal {
        IJBPriceFeed ethUsdFeed = _deployEthUsdFeed();
        _ensureDefaultPriceFeed(0, JBCurrencyIds.USD, uint32(uint160(JBConstants.NATIVE_TOKEN)), ethUsdFeed);
        _ensureDefaultPriceFeed(0, JBCurrencyIds.USD, JBCurrencyIds.ETH, ethUsdFeed);

        IJBPriceFeed nativeEthFeed =
            prices.priceFeedFor(0, JBCurrencyIds.ETH, uint32(uint160(JBConstants.NATIVE_TOKEN)));
        if (address(nativeEthFeed) == address(0)) {
            nativeEthFeed = IJBPriceFeed(address(new JBMatchingPriceFeed()));
        }
        _ensureDefaultPriceFeed(0, JBCurrencyIds.ETH, uint32(uint160(JBConstants.NATIVE_TOKEN)), nativeEthFeed);

        _deployUsdcFeed();

        (, bool deadlineDeployed) = _isDeployed(DEADLINES_SALT, type(JBDeadline3Hours).creationCode, "");
        if (!deadlineDeployed) new JBDeadline3Hours{salt: DEADLINES_SALT}();
        (, deadlineDeployed) = _isDeployed(DEADLINES_SALT, type(JBDeadline1Day).creationCode, "");
        if (!deadlineDeployed) new JBDeadline1Day{salt: DEADLINES_SALT}();
        (, deadlineDeployed) = _isDeployed(DEADLINES_SALT, type(JBDeadline3Days).creationCode, "");
        if (!deadlineDeployed) new JBDeadline3Days{salt: DEADLINES_SALT}();
        (, deadlineDeployed) = _isDeployed(DEADLINES_SALT, type(JBDeadline7Days).creationCode, "");
        if (!deadlineDeployed) new JBDeadline7Days{salt: DEADLINES_SALT}();

        (address controllerAddress, bool controllerDeployed) = _isDeployed(
            DEADLINES_SALT,
            type(JBController).creationCode,
            abi.encode(
                directory,
                fundAccess,
                permissions,
                prices,
                projects,
                rulesets,
                splits,
                tokens,
                address(omnichainDeployer),
                trustedForwarder
            )
        );
        controller = controllerDeployed
            ? JBController(controllerAddress)
            : new JBController{salt: DEADLINES_SALT}({
                directory: directory,
                fundAccessLimits: fundAccess,
                prices: prices,
                permissions: permissions,
                projects: projects,
                rulesets: rulesets,
                splits: splits,
                tokens: tokens,
                omnichainRulesetOperator: address(omnichainDeployer),
                trustedForwarder: trustedForwarder
            });

        if (!directory.isAllowedToSetFirstController(address(controller))) {
            directory.setIsAllowedToSetFirstController(address(controller), true);
        }
    }

    function _deployEthUsdFeed() internal returns (IJBPriceFeed) {
        return IJBPriceFeed(address(new JBChainlinkV3PriceFeed(AggregatorV3Interface(ETH_USD_FEED), 3600)));
    }

    function _deployUsdcFeed() internal {
        IJBPriceFeed existing =
            prices.priceFeedFor(0, JBCurrencyIds.USD, uint32(uint160(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)));
        if (address(existing) == address(0)) {
            IJBPriceFeed usdcFeed = IJBPriceFeed(
                address(
                    new JBChainlinkV3PriceFeed(
                        AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6), 86_400
                    )
                )
            );
            _ensureDefaultPriceFeed(
                0, JBCurrencyIds.USD, uint32(uint160(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)), usdcFeed
            );
        }
    }

    function _ensureDefaultPriceFeed(
        uint256 projectId,
        uint256 pricingCurrency,
        uint256 unitCurrency,
        IJBPriceFeed expectedFeed
    )
        internal
    {
        IJBPriceFeed existing = prices.priceFeedFor(projectId, pricingCurrency, unitCurrency);
        if (address(existing) == address(0)) {
            prices.addPriceFeedFor(projectId, pricingCurrency, unitCurrency, expectedFeed);
        }
    }

    function _ensureProjectExists(uint256 expectedProjectId) internal returns (uint256) {
        uint256 count = projects.count();
        if (count >= expectedProjectId) return expectedProjectId;
        return projects.createFor(address(this));
    }

    function _hookSalt() internal view returns (uint160, bytes32 salt) {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );
        bytes memory constructorArgs = abi.encode(IPoolManager(POOL_MANAGER), tokens, directory, prices);
        salt = _findHookSalt(address(this), flags, type(JBUniswapV4Hook).creationCode, constructorArgs);
        return (flags, salt);
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
        deployedTo = _create2Address(salt, creationCode, arguments);
        isDeployed = deployedTo.code.length != 0;
    }

    function _create2Address(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(this), salt, keccak256(abi.encodePacked(creationCode, arguments))
                        )
                    )
                )
            )
        );
    }

    function _findHookSalt(
        address deployer,
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
            address hookAddress = HookMiner.computeAddress(deployer, i, creationCodeWithArgs);
            if (uint160(hookAddress) & HookMiner.FLAG_MASK == flags) {
                return bytes32(i);
            }
        }

        revert("HookMiner: could not find salt");
    }
}

contract ResumeDeployForkTest is Test {
    function test_resumeDeploy_reusesAddressesAndProjectIds() public {
        try vm.createSelectFork("ethereum", 21_700_000) {}
        catch {
            vm.skip(true);
            return;
        }

        bytes32 harnessSalt = keccak256("resume-deploy-harness");
        ResumeDeployHarness harness = new ResumeDeployHarness{salt: harnessSalt}();

        harness.deployThroughRouterTerminal();

        address trustedForwarder = harness.trustedForwarder();
        address permissions = address(harness.permissions());
        address projects = address(harness.projects());
        address directory = address(harness.directory());
        address prices = address(harness.prices());
        address addressRegistry = address(harness.addressRegistry());
        address hookStore = address(harness.hookStore());
        address hook721 = address(harness.hook721());
        address hookDeployer = address(harness.hookDeployer());
        address hookProjectDeployer = address(harness.hookProjectDeployer());
        address uniswapV4Hook = address(harness.uniswapV4Hook());
        address buybackRegistry = address(harness.buybackRegistry());
        address buybackHook = address(harness.buybackHook());
        address routerTerminalRegistry = address(harness.routerTerminalRegistry());
        address routerTerminal = address(harness.routerTerminal());

        _assertPartialReplayState(harness);

        harness.deployInfrastructureAndReserveProjectIds();

        assertEq(harness.trustedForwarder(), trustedForwarder, "trustedForwarder changed");
        assertEq(address(harness.permissions()), permissions, "permissions changed");
        assertEq(address(harness.projects()), projects, "projects changed");
        assertEq(address(harness.directory()), directory, "directory changed");
        assertEq(address(harness.prices()), prices, "prices changed");
        assertEq(address(harness.addressRegistry()), addressRegistry, "addressRegistry changed");
        assertEq(address(harness.hookStore()), hookStore, "hookStore changed");
        assertEq(address(harness.hook721()), hook721, "hook721 changed");
        assertEq(address(harness.hookDeployer()), hookDeployer, "hookDeployer changed");
        assertEq(address(harness.hookProjectDeployer()), hookProjectDeployer, "hookProjectDeployer changed");
        assertEq(address(harness.uniswapV4Hook()), uniswapV4Hook, "uniswapV4Hook changed");
        assertEq(address(harness.buybackRegistry()), buybackRegistry, "buybackRegistry changed");
        assertEq(address(harness.buybackHook()), buybackHook, "buybackHook changed");
        assertEq(address(harness.routerTerminalRegistry()), routerTerminalRegistry, "routerTerminalRegistry changed");
        assertEq(address(harness.routerTerminal()), routerTerminal, "routerTerminal changed");

        assertEq(address(harness.controller()), harness.expectedControllerAddress(), "controller address drifted");
        assertTrue(
            harness.directory().isAllowedToSetFirstController(address(harness.controller())),
            "controller not allowlisted"
        );
        assertEq(harness.projects().count(), 3, "unexpected project count");
        assertEq(harness.cpnProjectId(), 2, "cpn project id");
        assertEq(harness.revProjectId(), 3, "rev project id");
        assertEq(harness.projects().ownerOf(1), address(harness), "project 1 owner");
        assertEq(harness.projects().ownerOf(2), address(harness), "project 2 owner");
        assertEq(harness.projects().ownerOf(3), address(harness), "project 3 owner");
        assertTrue(harness.suckerRegistry().suckerDeployerIsAllowed(address(0x1001)), "deployer 1 not allowlisted");
        assertTrue(harness.suckerRegistry().suckerDeployerIsAllowed(address(0x1002)), "deployer 2 not allowlisted");
        assertTrue(harness.feeless().isFeeless(address(harness.routerTerminal())), "router terminal not feeless");
        assertTrue(
            address(harness.prices().priceFeedFor(0, JBCurrencyIds.USD, uint32(uint160(JBConstants.NATIVE_TOKEN))))
                != address(0),
            "missing native USD feed"
        );
        assertTrue(
            address(harness.prices().priceFeedFor(0, JBCurrencyIds.USD, JBCurrencyIds.ETH)) != address(0),
            "missing eth USD feed"
        );
        assertTrue(
            address(harness.prices().priceFeedFor(0, JBCurrencyIds.ETH, uint32(uint160(JBConstants.NATIVE_TOKEN))))
                != address(0),
            "missing native eth feed"
        );
        assertTrue(
            address(
                harness.prices()
                    .priceFeedFor(0, JBCurrencyIds.USD, uint32(uint160(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)))
            ) != address(0),
            "missing usdc usd feed"
        );
    }

    function _assertPartialReplayState(ResumeDeployHarness harness) internal view {
        assertEq(
            address(harness.buybackRegistry().defaultHook()),
            address(harness.buybackHook()),
            "buyback hook not preserved"
        );
        assertEq(
            address(harness.routerTerminalRegistry().defaultTerminal()),
            address(harness.routerTerminal()),
            "router terminal not preserved"
        );
        assertTrue(harness.feeless().isFeeless(address(harness.routerTerminal())), "router terminal not feeless");
        assertEq(address(harness.uniswapV4Hook()), harness.expectedUniswapV4HookAddress(), "hook address drifted");
        assertEq(
            address(harness.routerTerminal()),
            harness.expectedRouterTerminalAddress(),
            "router terminal address drifted"
        );
    }
}
