// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBController} from "@bananapus/core-v6/src/JBController.sol";
import {JBDirectory} from "@bananapus/core-v6/src/JBDirectory.sol";
import {JBMultiTerminal} from "@bananapus/core-v6/src/JBMultiTerminal.sol";
import {JBTokens} from "@bananapus/core-v6/src/JBTokens.sol";
import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {DefifaDeployer} from "@ballkidz/defifa/src/DefifaDeployer.sol";
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {JBOmnichainDeployer} from "@bananapus/omnichain-deployers-v6/src/JBOmnichainDeployer.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";

contract ExternalAddressVerifierGapTest is Test {
    address internal constant CANONICAL_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant CANONICAL_MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CANONICAL_MAINNET_TYPEFACE = 0xA77b7D93E79f1E6B4f77FaB29d9ef85733A3D44A;

    function test_externalAddressVerifierRejectsWrongNonzeroPermit2OnMainnet() public {
        // BA fix engages on production chains. Set chain id to mainnet so the canonical Permit2
        // manifest is consulted.
        vm.chainId(1);

        address wrongPermit2 = makeAddr("wrong permit2");
        address wrongWeth = makeAddr("wrong weth");
        address directory = makeAddr("directory");

        assertTrue(wrongPermit2 != CANONICAL_PERMIT2, "test must use non-canonical permit2");
        assertTrue(wrongWeth != CANONICAL_MAINNET_WETH, "test must use non-canonical weth");

        VerifyExternalAddressHarness harness = new VerifyExternalAddressHarness();
        harness.setExternalAddressMocks({
            directory_: directory,
            terminal_: address(new MockTerminal(wrongPermit2)),
            routerTerminal_: address(new MockRouterTerminal(wrongPermit2, wrongWeth)),
            revLoans_: address(new MockRevLoans(wrongPermit2)),
            omnichainDeployer_: address(new MockOmnichainDeployer(directory))
        });

        // BA fix: Terminal.PERMIT2 is the first canonical check; a non-canonical Permit2 rejects.
        vm.expectRevert(
            abi.encodeWithSelector(Verify.Verify_CriticalCheckFailed.selector, "Terminal.PERMIT2 == canonical Permit2")
        );
        harness.verifyExternalAddresses();
    }

    function test_externalAddressVerifierRejectsWrongWethOnMainnet() public {
        vm.chainId(1);

        address directory = makeAddr("directory");
        address wrongWeth = makeAddr("wrong weth");

        assertTrue(wrongWeth != CANONICAL_MAINNET_WETH, "test must use non-canonical weth");

        VerifyExternalAddressHarness harness = new VerifyExternalAddressHarness();
        harness.setExternalAddressMocks({
            directory_: directory,
            terminal_: address(new MockTerminal(CANONICAL_PERMIT2)),
            routerTerminal_: address(new MockRouterTerminal(CANONICAL_PERMIT2, wrongWeth)),
            revLoans_: address(new MockRevLoans(CANONICAL_PERMIT2)),
            omnichainDeployer_: address(new MockOmnichainDeployer(directory))
        });

        // BA fix: when Permit2 is canonical, the next check is WRAPPED_NATIVE_TOKEN against WETH.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "RouterTerminal.WRAPPED_NATIVE_TOKEN == canonical WETH"
            )
        );
        harness.verifyExternalAddresses();
    }

    function test_defifaVerifierAcceptsWrongTypefaceResolver() public {
        address wrongTypeface = makeAddr("wrong typeface");
        address directory = makeAddr("directory");
        address controller = makeAddr("controller");
        address revToken = makeAddr("rev token");
        address nanaToken = makeAddr("nana token");

        assertTrue(wrongTypeface != CANONICAL_MAINNET_TYPEFACE, "test must use non-canonical typeface");

        MockDefifaGovernor governor = new MockDefifaGovernor(controller);
        MockDefifaDeployer deployer = new MockDefifaDeployer({
            controller_: controller,
            addressRegistry_: address(new MockCode()),
            hookStore_: address(new MockCode()),
            hookCodeOrigin_: address(
                new MockDefifaHook({revToken_: revToken, nanaToken_: nanaToken, directory_: directory})
            ),
            tokenUriResolver_: address(new MockDefifaTokenUriResolver(wrongTypeface)),
            governor_: address(governor)
        });
        governor.setOwner(address(deployer));

        VerifyExternalAddressHarness harness = new VerifyExternalAddressHarness();
        harness.setDefifaMocks({
            directory_: directory,
            controller_: controller,
            tokens_: address(new MockTokens({revToken_: revToken, nanaToken_: nanaToken})),
            addressRegistry_: deployer.REGISTRY(),
            defifaHookStore_: deployer.HOOK_STORE(),
            defifaDeployer_: address(deployer)
        });

        assertEq(MockDefifaTokenUriResolver(address(deployer.TOKEN_URI_RESOLVER())).TYPEFACE(), wrongTypeface);

        // Current Verify.s.sol only checks that TOKEN_URI_RESOLVER has code. It does not
        // authenticate DefifaTokenUriResolver.TYPEFACE(), so the wrong immutable passes.
        harness.verifyAddressRegistryAndDefifa();
    }

    /// @dev BA residual: the LP split hook deployer's `POSITION_MANAGER` immutable is the
    /// canonical V4 PositionManager every clone delegates against. A noncanonical address there
    /// must trip the new check.
    function test_externalAddressVerifierRejectsWrongV4PositionManagerOnMainnet() public {
        vm.chainId(1);

        address wrongPositionManager = makeAddr("wrong position manager");
        address canonicalPositionManager = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
        assertTrue(wrongPositionManager != canonicalPositionManager, "test must use a noncanonical PositionManager");

        address directory = makeAddr("directory");

        VerifyExternalAddressHarness harness = new VerifyExternalAddressHarness();
        harness.setExternalAddressMocks({
            directory_: directory,
            terminal_: address(new MockTerminal(CANONICAL_PERMIT2)),
            routerTerminal_: address(new MockRouterTerminal(CANONICAL_PERMIT2, CANONICAL_MAINNET_WETH)),
            revLoans_: address(new MockRevLoans(CANONICAL_PERMIT2)),
            omnichainDeployer_: address(new MockOmnichainDeployer(directory))
        });
        harness.setLpSplitHookDeployer(address(new MockLpSplitHookDeployer(wrongPositionManager)));

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "JBUniswapV4LPSplitHookDeployer.POSITION_MANAGER == canonical V4 PositionManager"
            )
        );
        harness.verifyExternalAddresses();
    }

    /// @dev BA residual: same deployer also stores POOL_MANAGER (V4) and ORACLE_HOOK
    /// (JBUniswapV4Hook). A noncanonical V4 PoolManager baked into the deployer must trip
    /// its dedicated check even after PositionManager identity passes.
    function test_externalAddressVerifierRejectsWrongLpSplitPoolManagerOnMainnet() public {
        vm.chainId(1);

        address canonicalPositionManager = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
        address canonicalV4PoolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        address wrongPoolManager = makeAddr("wrong v4 pool manager");
        assertTrue(wrongPoolManager != canonicalV4PoolManager, "test must use a noncanonical V4 PoolManager");

        address directory = makeAddr("directory");

        VerifyExternalAddressHarness harness = new VerifyExternalAddressHarness();
        harness.setExternalAddressMocks({
            directory_: directory,
            terminal_: address(new MockTerminal(CANONICAL_PERMIT2)),
            routerTerminal_: address(new MockRouterTerminal(CANONICAL_PERMIT2, CANONICAL_MAINNET_WETH)),
            revLoans_: address(new MockRevLoans(CANONICAL_PERMIT2)),
            omnichainDeployer_: address(new MockOmnichainDeployer(directory))
        });
        // ORACLE_HOOK is sourced via `_uniswapV4Hook()` which reads buybackRegistry.defaultHook().
        // Leave the buyback registry unloaded so the ORACLE_HOOK assertion is skipped — this test
        // focuses on the POOL_MANAGER branch.
        harness.setLpSplitHookDeployer(
            address(
                new MockLpSplitHookDeployerFull({
                    positionManager: canonicalPositionManager, poolManager: wrongPoolManager, oracleHook: address(0)
                })
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "JBUniswapV4LPSplitHookDeployer.POOL_MANAGER == canonical V4 PoolManager"
            )
        );
        harness.verifyExternalAddresses();
    }

    /// @dev BA residual: on production chains the LP split hook deployer env var is required.
    /// Without it the verifier must fail closed so the V4 PositionManager identity cannot
    /// silently drop out of the launch gate.
    function test_externalAddressVerifierFailsClosedWhenLpSplitHookDeployerUnsetOnMainnet() public {
        vm.chainId(1);

        address directory = makeAddr("directory");

        VerifyExternalAddressHarness harness = new VerifyExternalAddressHarness();
        harness.setExternalAddressMocks({
            directory_: directory,
            terminal_: address(new MockTerminal(CANONICAL_PERMIT2)),
            routerTerminal_: address(new MockRouterTerminal(CANONICAL_PERMIT2, CANONICAL_MAINNET_WETH)),
            revLoans_: address(new MockRevLoans(CANONICAL_PERMIT2)),
            omnichainDeployer_: address(new MockOmnichainDeployer(directory))
        });
        // Intentionally leave `lpSplitHookDeployer` unset (defaults to address(0)).

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "VERIFY_LP_SPLIT_HOOK_DEPLOYER MUST be set on production for V4 PositionManager identity"
            )
        );
        harness.verifyExternalAddresses();
    }
}

contract VerifyExternalAddressHarness is Verify {
    function setExternalAddressMocks(
        address directory_,
        address terminal_,
        address routerTerminal_,
        address revLoans_,
        address omnichainDeployer_
    )
        external
    {
        directory = JBDirectory(directory_);
        terminal = JBMultiTerminal(payable(terminal_));
        routerTerminal = JBRouterTerminal(payable(routerTerminal_));
        revLoans = REVLoans(payable(revLoans_));
        omnichainDeployer = JBOmnichainDeployer(omnichainDeployer_);
    }

    function verifyExternalAddresses() external {
        _verifyExternalAddresses();
    }

    function setDefifaMocks(
        address directory_,
        address controller_,
        address tokens_,
        address addressRegistry_,
        address defifaHookStore_,
        address defifaDeployer_
    )
        external
    {
        directory = JBDirectory(directory_);
        controller = JBController(controller_);
        tokens = JBTokens(tokens_);
        addressRegistry = addressRegistry_;
        defifaHookStore = JB721TiersHookStore(defifaHookStore_);
        defifaDeployer = DefifaDeployer(defifaDeployer_);
    }

    function verifyAddressRegistryAndDefifa() external {
        _verifyAddressRegistryAndDefifa();
    }

    function setLpSplitHookDeployer(address deployer_) external {
        lpSplitHookDeployer = deployer_;
    }
}

contract MockLpSplitHookDeployer {
    address internal immutable _positionManager;
    address internal immutable _poolManager;
    address internal immutable _oracleHook;

    constructor(address positionManager) {
        _positionManager = positionManager;
        _poolManager = address(0);
        _oracleHook = address(0);
    }

    function POSITION_MANAGER() external view returns (address) {
        return _positionManager;
    }

    function POOL_MANAGER() external view returns (address) {
        return _poolManager;
    }

    function ORACLE_HOOK() external view returns (address) {
        return _oracleHook;
    }
}

contract MockLpSplitHookDeployerFull {
    address internal immutable _positionManager;
    address internal immutable _poolManager;
    address internal immutable _oracleHook;

    constructor(address positionManager, address poolManager, address oracleHook) {
        _positionManager = positionManager;
        _poolManager = poolManager;
        _oracleHook = oracleHook;
    }

    function POSITION_MANAGER() external view returns (address) {
        return _positionManager;
    }

    function POOL_MANAGER() external view returns (address) {
        return _poolManager;
    }

    function ORACLE_HOOK() external view returns (address) {
        return _oracleHook;
    }
}

contract MockTerminal {
    address internal immutable _permit2;

    constructor(address permit2) {
        _permit2 = permit2;
    }

    function PERMIT2() external view returns (address) {
        return _permit2;
    }
}

contract MockRouterTerminal {
    address internal immutable _permit2;
    address internal immutable _wrappedNativeToken;

    constructor(address permit2, address wrappedNativeToken) {
        _permit2 = permit2;
        _wrappedNativeToken = wrappedNativeToken;
    }

    function PERMIT2() external view returns (address) {
        return _permit2;
    }

    function WRAPPED_NATIVE_TOKEN() external view returns (address) {
        return _wrappedNativeToken;
    }
}

contract MockRevLoans {
    address internal immutable _permit2;

    constructor(address permit2) {
        _permit2 = permit2;
    }

    function PERMIT2() external view returns (address) {
        return _permit2;
    }
}

contract MockOmnichainDeployer {
    address internal immutable _directory;

    constructor(address directory) {
        _directory = directory;
    }

    function DIRECTORY() external view returns (address) {
        return _directory;
    }
}

contract MockCode {}

contract MockTokens {
    address internal immutable _revToken;
    address internal immutable _nanaToken;

    constructor(address revToken_, address nanaToken_) {
        _revToken = revToken_;
        _nanaToken = nanaToken_;
    }

    function tokenOf(uint256 projectId) external view returns (address) {
        if (projectId == 3) return _revToken;
        if (projectId == 1) return _nanaToken;
        return address(0);
    }
}

contract MockDefifaHook {
    address internal immutable _revToken;
    address internal immutable _nanaToken;
    address internal immutable _directory;

    constructor(address revToken_, address nanaToken_, address directory_) {
        _revToken = revToken_;
        _nanaToken = nanaToken_;
        _directory = directory_;
    }

    function DEFIFA_TOKEN() external view returns (address) {
        return _revToken;
    }

    function BASE_PROTOCOL_TOKEN() external view returns (address) {
        return _nanaToken;
    }

    function DIRECTORY() external view returns (address) {
        return _directory;
    }
}

contract MockDefifaTokenUriResolver {
    address internal immutable _typeface;

    constructor(address typeface_) {
        _typeface = typeface_;
    }

    function TYPEFACE() external view returns (address) {
        return _typeface;
    }
}

contract MockDefifaGovernor {
    address internal immutable _controller;
    address internal _owner;

    constructor(address controller_) {
        _controller = controller_;
    }

    function setOwner(address owner_) external {
        _owner = owner_;
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function CONTROLLER() external view returns (address) {
        return _controller;
    }
}

contract MockDefifaDeployer {
    address internal immutable _controller;
    address internal immutable _addressRegistry;
    address internal immutable _hookStore;
    address internal immutable _hookCodeOrigin;
    address internal immutable _tokenUriResolver;
    address internal immutable _governor;

    constructor(
        address controller_,
        address addressRegistry_,
        address hookStore_,
        address hookCodeOrigin_,
        address tokenUriResolver_,
        address governor_
    ) {
        _controller = controller_;
        _addressRegistry = addressRegistry_;
        _hookStore = hookStore_;
        _hookCodeOrigin = hookCodeOrigin_;
        _tokenUriResolver = tokenUriResolver_;
        _governor = governor_;
    }

    function DEFIFA_PROJECT_ID() external pure returns (uint256) {
        return 3;
    }

    function BASE_PROTOCOL_PROJECT_ID() external pure returns (uint256) {
        return 1;
    }

    function CONTROLLER() external view returns (address) {
        return _controller;
    }

    function REGISTRY() external view returns (address) {
        return _addressRegistry;
    }

    function HOOK_STORE() external view returns (address) {
        return _hookStore;
    }

    function HOOK_CODE_ORIGIN() external view returns (address) {
        return _hookCodeOrigin;
    }

    function TOKEN_URI_RESOLVER() external view returns (address) {
        return _tokenUriResolver;
    }

    function GOVERNOR() external view returns (address) {
        return _governor;
    }
}
