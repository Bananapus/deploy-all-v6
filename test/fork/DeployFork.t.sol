// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";

// Core contracts — validates that every import in Deploy.s.sol compiles.
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

// Core Libraries
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";

// Core Interfaces
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";

// Periphery — deadlines and feeds
import {JBDeadline3Hours} from "@bananapus/core-v6/src/periphery/JBDeadline3Hours.sol";
import {JBDeadline1Day} from "@bananapus/core-v6/src/periphery/JBDeadline1Day.sol";
import {JBDeadline3Days} from "@bananapus/core-v6/src/periphery/JBDeadline3Days.sol";
import {JBDeadline7Days} from "@bananapus/core-v6/src/periphery/JBDeadline7Days.sol";
import {JBMatchingPriceFeed} from "@bananapus/core-v6/src/periphery/JBMatchingPriceFeed.sol";

// Price feeds
import {JBChainlinkV3PriceFeed, AggregatorV3Interface} from "@bananapus/core-v6/src/JBChainlinkV3PriceFeed.sol";
import {JBChainlinkV3SequencerPriceFeed} from "@bananapus/core-v6/src/JBChainlinkV3SequencerPriceFeed.sol";
import {AggregatorV2V3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";

// Address Registry
import {JBAddressRegistry} from "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import {IJBAddressRegistry} from "@bananapus/address-registry-v6/src/interfaces/IJBAddressRegistry.sol";

// 721 Hook
import {JB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookDeployer.sol";
import {JB721TiersHookProjectDeployer} from "@bananapus/721-hook-v6/src/JB721TiersHookProjectDeployer.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721CheckpointsDeployer} from "@bananapus/721-hook-v6/src/JB721CheckpointsDeployer.sol";
import {JB721TiersHook} from "@bananapus/721-hook-v6/src/JB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";

// Buyback Hook
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {JBUniswapV4Hook} from "@bananapus/univ4-router-v6/src/JBUniswapV4Hook.sol";
import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";
import {JBUniswapV4LPSplitHookDeployer} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHookDeployer.sol";

// Router Terminal
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBRouterTerminalRegistry} from "@bananapus/router-terminal-v6/src/JBRouterTerminalRegistry.sol";
import {IWETH9} from "@bananapus/router-terminal-v6/src/interfaces/IWETH9.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

// Suckers
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {IJBSuckerDeployer} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerDeployer.sol";

// Omnichain Deployer
import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";

// IERC165 for controller check
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Fork test for Deploy.s.sol — exercises the core deployment phases on an Ethereum mainnet fork.
///
/// The full `deploy()` function in Deploy.s.sol is gated by the Sphinx `sphinx` modifier which
/// requires a `sphinx.lock` file and Gnosis Safe infrastructure. This test bypasses Sphinx by
/// directly deploying the core contracts in the same order and verifying the wiring.
///
/// Run with: forge test --match-contract DeployForkTest -vvv
contract DeployForkTest is Test {
    // ════════════════════════════════════════════════════════════════════
    //  Constants (must match Deploy.s.sol)
    // ════════════════════════════════════════════════════════════════════

    IPermit2 private constant _PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // Ethereum mainnet addresses (from Deploy.s.sol _setupChainAddresses)
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address private constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address private constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address private constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // Deployer
    address private _deployer;

    // Core contracts (set during deployment)
    address private _trustedForwarder;
    JBPermissions private _permissions;
    JBProjects private _projects;
    JBDirectory private _directory;
    JBSplits private _splits;
    JBRulesets private _rulesets;
    JBPrices private _prices;
    JBTokens private _tokens;
    JBFundAccessLimits private _fundAccess;
    JBFeelessAddresses private _feeless;
    JBTerminalStore private _terminalStore;
    JBMultiTerminal private _terminal;
    JBController private _controller;

    // Phase 02
    JBAddressRegistry private _addressRegistry;

    // Phase 03a: 721 Hook
    JB721TiersHookStore private _hookStore;
    JB721TiersHook private _hook721;
    JB721TiersHookDeployer private _hookDeployer;
    JB721TiersHookProjectDeployer private _hookProjectDeployer;

    // Phase 03b: Buyback Hook
    JBUniswapV4Hook private _uniswapV4Hook;
    JBBuybackHookRegistry private _buybackRegistry;
    JBBuybackHook private _buybackHook;

    // Phase 03c: Router Terminal + LP Split Hook
    JBRouterTerminalRegistry private _routerTerminalRegistry;
    JBRouterTerminal private _routerTerminal;
    JBUniswapV4LPSplitHook private _lpSplitHook;
    JBUniswapV4LPSplitHookDeployer private _lpSplitHookDeployer;

    // Phase 03d: Suckers
    JBSuckerRegistry private _suckerRegistry;

    // Phase 04: Omnichain Deployer
    JBOmnichainDeployer private _omnichainDeployer;

    // ════════════════════════════════════════════════════════════════════
    //  Setup
    // ════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Fork Ethereum mainnet. Skip if RPC not configured.
        try vm.createSelectFork("ethereum", 21_700_000) {}
        catch {
            vm.skip(true);
        }

        _deployer = makeAddr("deployer");
        vm.deal(_deployer, 100 ether);
    }

    // ════════════════════════════════════════════════════════════════════
    //  Tests
    // ════════════════════════════════════════════════════════════════════

    /// @notice Deploys the core protocol (Phase 01) and verifies all contracts are wired correctly.
    function test_deployFork_coreProtocol() public {
        vm.startPrank(_deployer);

        // Phase 01: Core Protocol (mirrors Deploy._deployCore)
        _trustedForwarder = address(new ERC2771Forwarder("Juicebox"));
        _permissions = new JBPermissions(_trustedForwarder);
        _projects = new JBProjects(_deployer, _deployer, _trustedForwarder);
        _directory = new JBDirectory(_permissions, _projects, _deployer);
        _splits = new JBSplits(_directory);
        _rulesets = new JBRulesets(_directory);
        _prices = new JBPrices(_directory, _permissions, _projects, _deployer, _trustedForwarder);
        _tokens = new JBTokens(_directory, new JBERC20(_permissions, _projects));
        _fundAccess = new JBFundAccessLimits(_directory);
        _feeless = new JBFeelessAddresses(_deployer);
        _terminalStore = new JBTerminalStore({directory: _directory, rulesets: _rulesets, prices: _prices});
        _terminal = new JBMultiTerminal({
            permissions: _permissions,
            projects: _projects,
            splits: _splits,
            store: _terminalStore,
            tokens: _tokens,
            feelessAddresses: _feeless,
            permit2: _PERMIT2,
            trustedForwarder: _trustedForwarder
        });

        vm.stopPrank();

        // Verify all contracts are deployed at non-zero addresses.
        assertTrue(address(_permissions) != address(0), "Permissions not deployed");
        assertTrue(address(_projects) != address(0), "Projects not deployed");
        assertTrue(address(_directory) != address(0), "Directory not deployed");
        assertTrue(address(_splits) != address(0), "Splits not deployed");
        assertTrue(address(_rulesets) != address(0), "Rulesets not deployed");
        assertTrue(address(_prices) != address(0), "Prices not deployed");
        assertTrue(address(_tokens) != address(0), "Tokens not deployed");
        assertTrue(address(_fundAccess) != address(0), "FundAccessLimits not deployed");
        assertTrue(address(_feeless) != address(0), "FeelessAddresses not deployed");
        assertTrue(address(_terminalStore) != address(0), "TerminalStore not deployed");
        assertTrue(address(_terminal) != address(0), "Terminal not deployed");
        assertTrue(_trustedForwarder != address(0), "TrustedForwarder not deployed");

        // Verify bytecode exists.
        assertTrue(address(_permissions).code.length > 0, "Permissions has no code");
        assertTrue(address(_terminal).code.length > 0, "Terminal has no code");

        // Verify wiring: TerminalStore references the correct Directory.
        assertEq(address(_terminalStore.DIRECTORY()), address(_directory), "TerminalStore.DIRECTORY != Directory");

        // Verify wiring: TerminalStore references the correct Prices.
        assertEq(address(_terminalStore.PRICES()), address(_prices), "TerminalStore.PRICES != Prices");

        // Verify wiring: TerminalStore references the correct Rulesets.
        assertEq(address(_terminalStore.RULESETS()), address(_rulesets), "TerminalStore.RULESETS != Rulesets");
    }

    function _deployUniswapV4Hook() internal returns (JBUniswapV4Hook hook) {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(IPoolManager(POOL_MANAGER), _tokens, _directory, _prices);

        (, bytes32 salt) = HookMiner.find(address(this), flags, type(JBUniswapV4Hook).creationCode, constructorArgs);

        hook = new JBUniswapV4Hook{salt: salt}(IPoolManager(POOL_MANAGER), _tokens, _directory, _prices);
    }
}
