// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Sphinx} from "@sphinx-labs/contracts/contracts/foundry/SphinxPlugin.sol";
import {console, Script, stdJson} from "forge-std/Script.sol";

// ── Uniswap ──
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

// ── Buyback Hook ──
import {JBBuybackHook} from "@bananapus/buyback-hook-v6/src/JBBuybackHook.sol";
import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";

// ── Core ──
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBCurrencyIds} from "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";

// ── Deploy script helpers ──
import {JBChainTokens} from "./libraries/JBChainTokens.sol";

/// @notice Focused redeploy of the buyback hook for the derived-floor fix in buyback-hook-v6 1.3.0
/// (nana-buyback-hook-v6 PR #173): a buy-side swap that fills below the oracle-derived TWAP floor now unwinds
/// inside the unlock and the full payment falls back to minting at the issuance rate, instead of hard-reverting
/// the pay. This keeps no-quote programmatic payments (REVLoans fees, split pays, project payers) alive on thin
/// trending pools and closes the fee-evasion vector where a payer with a forgiven fee could nudge the pool to
/// make their own fee pay revert. Explicit caller minima still hard-revert.
///
/// It also closes an unrelated JBPrices gap, because this Safe is the only address that can: `pricePerUnitOf` looks a
/// pair up directly and then inverted, but never COMPOSES two feeds. The project-0 defaults registered at launch are
/// {USD←NATIVE}, {USD←ETH}, {ETH←NATIVE} and {USD←uint32(usdc)}, which leaves {NATIVE←uint32(usdc)} and
/// {ETH←uint32(usdc)} unresolvable — so a project holding BOTH an ETH and a USDC accounting context reverts on USDC
/// pays under an ETH base currency, and on mixed-balance cash outs under any base. For a revnet, whose accounting
/// contexts are immutable, that is permanent; one such project is already live on four chains.
///
/// Run by the infra Safe, which owns JBPrices and the buyback hook registry and is the operator of project 1. Steps:
///   1. Deploy a `JBRatioPriceFeed(usdcUsdFeed, ethUsdFeed)` — USD-per-USDC over USD-per-NATIVE, i.e. NATIVE per USDC
///      — over the LIVE project-0 feeds read back from JBPrices, and register it as the project-0 default for both
///      {NATIVE←uint32(usdc)} and {ETH←uint32(usdc)}. A direct Chainlink USDC/ETH feed exists only on Ethereum
///      mainnet, so the ratio feed is used uniformly everywhere and the ETH-base and USD-base paths on a chain stay
///      consistent with each other. Price feeds have nothing to do with Uniswap, so this step runs on EVERY chain —
///      including OP Sepolia, which has no Uniswap stack and skips every step below.
///   2. Deploy the 1.3.0 JBBuybackHook (same ctor args as the live one, fresh CREATE2 salt) and wire the
///      chain-specific PoolManager + the LIVE JBUniswapV4Hook oracle (reused, not redeployed — same pools).
///   3. Set it as the registry's default hook (auto-allows it; only affects projects created after this call).
///   4. Pin project 1 to the new hook and re-register its existing warm pool on the new hook via `setPoolFor`
///      (pool state lives per-hook; the V4 pool itself is untouched, so TWAP history and liquidity carry over),
///      with a fresh 30-minute TWAP window in place of the outgoing hook's 2-day one.
///   5. Disallow the outgoing default so no new project can select it.
///
/// Projects 2-7 keep resolving to the outgoing hook (their pins/history are sovereign by registry design);
/// their operators migrate with their own `setHookFor` + `setPoolFor` Safe transactions when ready.
///
/// Idempotent: both deploys skip if the contract already exists at its predicted address, every registry step is
/// guarded by a current-state check, and a price-feed pair is only written when it is currently empty (a pair already
/// pointing somewhere else reverts rather than being silently overwritten). Rebuild `artifacts/` (`npm run artifacts`)
/// from buyback-hook-v6 1.3.0 and a core-v6 release containing `JBRatioPriceFeed` before proposing.
abstract contract BuybackFloorFixBase is Script {
    using stdJson for string;

    error BuybackFloorFix_FeeProjectHookLocked(uint256 projectId);
    error BuybackFloorFix_MissingDeployment(string name);
    error BuybackFloorFix_PriceFeedMismatch(uint256 pricingCurrency, uint256 unitCurrency);
    error BuybackFloorFix_UnexpectedSafe(address expected, address actual);
    error BuybackFloorFix_UnsupportedChain(uint256 chainId);

    // ── Constants (mirror Deploy.s.sol) ──
    address internal constant _CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address internal constant _EXPECTED_SAFE = 0x4dc161eF837fF1C4485b08DDFcDB182F2157bE18;
    uint256 internal constant DEPLOYMENT_NONCE = 13;

    /// @notice The project ID JBPrices stores protocol default feeds under.
    uint256 internal constant _DEFAULT_PROJECT_ID = 0;

    uint256 internal constant _FEE_PROJECT_ID = 1;

    /// @notice The TWAP window project 1 gets on the new hook. Deliberately NOT the 2-day window carried by the
    /// outgoing hook: with the 1.3.0 mint fallback, a long window no longer buys liveness — it only makes the
    /// derived floor lag a trending pool so no-quote pays systematically miss the AMM route. Same-block sandwiches
    /// never enter a TWAP at any window; 30 minutes still forces a sustained, arb-exposed displacement to bend the
    /// floor, and the operator can retune per pool via `setTwapWindowOf` at any time.
    uint256 internal constant _FEE_PROJECT_TWAP_WINDOW = 30 minutes;

    bytes32 internal constant _BUYBACK_HOOK_SALT = keccak256("JBBuybackHookV6_DerivedFloorFix");

    /// @notice Salt for the NATIVE-per-USDC ratio feed. The feed's constructor arguments are the chain's own two
    /// live feeds, so the CREATE2 address differs per chain — that is expected and correct.
    bytes32 internal constant _NATIVE_PER_USDC_FEED_SALT = keccak256("JBRatioPriceFeedV6_NativePerUsdc");

    // ── State ──
    address internal _poolManager;

    address internal _trustedForwarder;
    IJBDirectory internal _directory;
    IJBPermissions internal _permissions;
    IJBPrices internal _prices;
    IJBProjects internal _projects;
    IJBTokens internal _tokens;
    JBBuybackHookRegistry internal _buybackRegistry;
    address internal _oracleHook; // the live JBUniswapV4Hook the buyback pools already trade against

    JBBuybackHook internal _oldBuybackHook;
    JBBuybackHook internal _newBuybackHook;

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
            revert BuybackFloorFix_UnsupportedChain(block.chainid);
        }
    }

    /// @notice The Uniswap stack (and thus a buyback hook) was never deployed on OP Sepolia.
    function _shouldDeployUniswapStack() internal view returns (bool) {
        return block.chainid != 11_155_420;
    }

    /// @notice Addresses every supported chain has, OP Sepolia included. The price-feed step needs only these.
    function _loadCoreDeploymentAddresses() internal {
        _prices = IJBPrices(_deploymentAddressOf("JBPrices"));
    }

    /// @notice Addresses that only exist on chains carrying the Uniswap/buyback stack. Kept out of the core loader
    /// so OP Sepolia — which has no `JBUniswapV4Hook` deployment file — can still run the price-feed step.
    function _loadBuybackDeploymentAddresses() internal {
        _trustedForwarder = _deploymentAddressOf("ERC2771Forwarder");
        _permissions = IJBPermissions(_deploymentAddressOf("JBPermissions"));
        _projects = IJBProjects(_deploymentAddressOf("JBProjects"));
        _directory = IJBDirectory(_deploymentAddressOf("JBDirectory"));
        _tokens = IJBTokens(_deploymentAddressOf("JBTokens"));
        _buybackRegistry = JBBuybackHookRegistry(_deploymentAddressOf("JBBuybackHookRegistry"));
        _oracleHook = _deploymentAddressOf("JBUniswapV4Hook");

        // The outgoing hook is whatever the registry currently serves as its default — the live source of truth.
        _oldBuybackHook = JBBuybackHook(payable(address(_buybackRegistry.defaultHook())));
    }

    function _deploymentAddressOf(string memory name) internal view returns (address addr) {
        string memory path = string.concat("deployments/", _chainFolder(), "/", name, ".json");
        string memory json = vm.readFile(path);
        addr = json.readAddress(".address");
        if (addr == address(0)) revert BuybackFloorFix_MissingDeployment(name);
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
        revert BuybackFloorFix_UnsupportedChain(block.chainid);
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

    // ── Ctor args (mirror Deploy.s.sol / the live hook) ──
    function _buybackHookCtorArgs() internal view returns (bytes memory) {
        return abi.encode(_directory, _permissions, _prices, _projects, _tokens, _EXPECTED_SAFE, _trustedForwarder);
    }

    // ── JBPrices: the missing NATIVE↔USDC defaults ──

    /// @notice The `JBRatioPriceFeed(numerator, denominator)` arguments for this chain. The numerator is the chain's
    /// live USDC/USD feed and the denominator its live ETH/USD feed, so the quotient is NATIVE per USDC. Both are read
    /// back out of JBPrices at the exact pairs `Deploy.s.sol` registered them under: the live registry, not a
    /// re-derived address, is the source of truth.
    /// @return ctorArgs The abi-encoded constructor arguments.
    /// @return available False when this chain has no canonical USDC or either leg is unregistered, in which case the
    /// chain is skipped rather than reverting the whole deploy.
    function _nativePerUsdcFeedCtorArgs() internal view returns (bytes memory ctorArgs, bool available) {
        address usdc = JBChainTokens.usdcTokenFor(block.chainid);
        if (usdc == address(0)) return ("", false);

        IJBPriceFeed usdcUsdFeed = _prices.priceFeedFor({
            projectId: _DEFAULT_PROJECT_ID,
            pricingCurrency: JBCurrencyIds.USD,
            unitCurrency: JBChainTokens.currencyIdOf(usdc)
        });
        IJBPriceFeed ethUsdFeed = _prices.priceFeedFor({
            projectId: _DEFAULT_PROJECT_ID,
            pricingCurrency: JBCurrencyIds.USD,
            unitCurrency: JBChainTokens.currencyIdOf(JBConstants.NATIVE_TOKEN)
        });
        if (address(usdcUsdFeed) == address(0) || address(ethUsdFeed) == address(0)) return ("", false);

        return (abi.encode(usdcUsdFeed, ethUsdFeed), true);
    }

    /// @notice Deploy the NATIVE-per-USDC ratio feed and register it as the project-0 default for the two pairs
    /// `pricePerUnitOf` cannot otherwise resolve.
    /// @return feed The ratio feed, or the zero address when this chain was skipped.
    function _ensureNativePerUsdcDefaultFeeds() internal returns (address feed) {
        (bytes memory ctorArgs, bool available) = _nativePerUsdcFeedCtorArgs();
        if (!available) return address(0);

        feed = _deployPrecompiledIfNeeded({
            artifactName: "JBRatioPriceFeed", salt: _NATIVE_PER_USDC_FEED_SALT, ctorArgs: ctorArgs
        });

        uint32 usdcCurrency = JBChainTokens.currencyIdOf(JBChainTokens.usdcTokenFor(block.chainid));
        _ensureDefaultPriceFeed({
            pricingCurrency: JBChainTokens.currencyIdOf(JBConstants.NATIVE_TOKEN),
            unitCurrency: usdcCurrency,
            expectedFeed: IJBPriceFeed(feed)
        });
        _ensureDefaultPriceFeed({
            pricingCurrency: JBCurrencyIds.ETH, unitCurrency: usdcCurrency, expectedFeed: IJBPriceFeed(feed)
        });
    }

    /// @notice Mirror of `Deploy.s.sol._ensureDefaultPriceFeed`, scoped to project 0: write only into an empty pair,
    /// and refuse to run at all if a pair already points at a different feed. Price feeds are a money path, so a
    /// surprise there is a stop condition, not something to silently overwrite (`addPriceFeedFor` is append-only, so
    /// an extra registration would sit behind the incumbent and be invisible in the common lookup).
    function _ensureDefaultPriceFeed(
        uint256 pricingCurrency,
        uint256 unitCurrency,
        IJBPriceFeed expectedFeed
    )
        internal
    {
        IJBPriceFeed existing = _prices.priceFeedFor({
            projectId: _DEFAULT_PROJECT_ID, pricingCurrency: pricingCurrency, unitCurrency: unitCurrency
        });
        if (address(existing) == address(0)) {
            _prices.addPriceFeedFor({
                projectId: _DEFAULT_PROJECT_ID,
                pricingCurrency: pricingCurrency,
                unitCurrency: unitCurrency,
                feed: expectedFeed
            });
        } else if (address(existing) != address(expectedFeed)) {
            revert BuybackFloorFix_PriceFeedMismatch({pricingCurrency: pricingCurrency, unitCurrency: unitCurrency});
        }
    }
}

/// @notice Sphinx deploy for the buyback derived-floor fix. Propose per `deploy:propose:buyback-floor-fix:*`.
contract DeployBuybackFloorFix is BuybackFloorFixBase, Sphinx {
    function configureSphinx() public override {
        sphinxConfig.projectName = "v6-deployment";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        if (safeAddress() != _EXPECTED_SAFE) {
            revert BuybackFloorFix_UnexpectedSafe({expected: _EXPECTED_SAFE, actual: safeAddress()});
        }
        _setupChainAddresses();
        _loadCoreDeploymentAddresses();
        if (_shouldDeployUniswapStack()) _loadBuybackDeploymentAddresses();

        // Surface a skipped price-feed chain here rather than inside the broadcast body, which stays free of
        // non-broadcast calls.
        (, bool feedAvailable) = _nativePerUsdcFeedCtorArgs();
        if (!feedAvailable) {
            console.log("SKIP NATIVE-per-USDC price feed: no canonical USDC or leg feed on chain", block.chainid);
        }

        deploy();
    }

    function deploy() public sphinx {
        // 1. The two missing project-0 price feed defaults. Nothing here involves Uniswap, so it runs on every
        //    supported chain; the buyback steps below are the ones OP Sepolia has no stack for.
        _ensureNativePerUsdcDefaultFeeds();

        if (!_shouldDeployUniswapStack()) return;

        // 2. New hook implementation from the rebuilt 1.3.0 artifact, wired to the LIVE oracle hook so the new
        //    hook quotes and swaps against the exact pools (and TWAP history) the outgoing hook already uses.
        _newBuybackHook = JBBuybackHook(
            payable(_deployPrecompiledIfNeeded({
                    artifactName: "JBBuybackHook", salt: _BUYBACK_HOOK_SALT, ctorArgs: _buybackHookCtorArgs()
                }))
        );
        if (address(_newBuybackHook.poolManager()) == address(0)) {
            _newBuybackHook.setChainSpecificConstants({
                newPoolManager: IPoolManager(_poolManager), newOracleHook: IHooks(_oracleHook)
            });
        }

        // 3. Registry default for projects created from here on. Auto-allows the new hook, which `setHookFor`
        //    below requires. Must precede the disallow: the registry refuses to disallow its current default.
        if (address(_buybackRegistry.defaultHook()) != address(_newBuybackHook)) {
            _buybackRegistry.setDefaultHook({hook: IJBRulesetDataHook(address(_newBuybackHook))});
        }

        // 4. Pin project 1 to the new hook and carry its pool registration over. The Safe holds project 1's
        //    SET_BUYBACK_HOOK / SET_BUYBACK_POOL permissions as its operator.
        _migrateFeeProject();

        // 5. Retire the outgoing hook: no new project can select it. Existing pins and default-history cohorts
        //    keep resolving to it by design — each project's operator migrates on their own schedule.
        if (
            address(_oldBuybackHook) != address(0) && address(_oldBuybackHook) != address(_newBuybackHook)
                && _buybackRegistry.isHookAllowed(IJBRulesetDataHook(address(_oldBuybackHook)))
        ) {
            _buybackRegistry.disallowHook({hook: IJBRulesetDataHook(address(_oldBuybackHook))});
        }
    }

    function _migrateFeeProject() internal {
        if (address(_buybackRegistry.hookOf(_FEE_PROJECT_ID)) != address(_newBuybackHook)) {
            if (_buybackRegistry.hasLockedHook(_FEE_PROJECT_ID)) {
                revert BuybackFloorFix_FeeProjectHookLocked(_FEE_PROJECT_ID);
            }
            _buybackRegistry.setHookFor({
                projectId: _FEE_PROJECT_ID, hook: IJBRulesetDataHook(address(_newBuybackHook))
            });
        }

        // Pool state lives per-hook, so the fresh hook starts with none. Re-register project 1's existing pool
        // on the new hook with the exact key the outgoing hook used — the V4 pool itself (liquidity, oracle
        // history) is untouched, so `setPoolFor` (which requires an already-initialized pool) is the right call,
        // NOT `initializePoolFor` (which would reject the drifted live price). The fee/tickSpacing MUST match the
        // live pool key; only the window is per-hook state and free to improve here.
        if (address(_oldBuybackHook) == address(0)) return;

        uint256 oldWindow = _oldBuybackHook.twapWindowOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)});
        uint256 newWindow = _newBuybackHook.twapWindowOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)});
        if (oldWindow == 0 || newWindow != 0) return; // nothing to carry over, or already carried over

        PoolKey memory key = _oldBuybackHook.poolKeyOf({projectId: _FEE_PROJECT_ID, terminalToken: address(0)});
        _buybackRegistry.setPoolFor({
            projectId: _FEE_PROJECT_ID,
            fee: key.fee,
            tickSpacing: key.tickSpacing,
            twapWindow: _FEE_PROJECT_TWAP_WINDOW,
            terminalToken: JBConstants.NATIVE_TOKEN
        });
    }

    /// @notice Post-deploy address dump (no broadcast) for the focused verify/emit/distribute pipeline. Writes only
    /// the contracts this script deploys — the new buyback hook, and the NATIVE-per-USDC ratio feed where the chain
    /// can compose one — to `script/post-deploy/.cache/addresses-<chainId>.json` in the same `jb-v6-addresses-1`
    /// format as `Deploy.s.sol._dumpAddresses`, so `post-deploy.sh --skip-dump` verifies and emits exactly these
    /// contracts. The addresses are the deterministic CREATE2 predictions off the current artifacts. No file is
    /// written when a chain gets neither, which the focused post-deploy script reads as "nothing to do here".
    function dumpAddresses() external {
        _setupChainAddresses();
        _loadCoreDeploymentAddresses();

        string memory j = "_buybackFloorFixAddresses";
        bool anyDeployed;

        if (_shouldDeployUniswapStack()) {
            _loadBuybackDeploymentAddresses();
            (address hook,) = _isDeployed({
                salt: _BUYBACK_HOOK_SALT,
                creationCode: _loadArtifact("JBBuybackHook"),
                arguments: _buybackHookCtorArgs()
            });
            vm.serializeAddress({objectKey: j, valueKey: "JBBuybackHook", value: hook});
            anyDeployed = true;
        }

        (bytes memory feedCtorArgs, bool feedAvailable) = _nativePerUsdcFeedCtorArgs();
        if (feedAvailable) {
            (address feed,) = _isDeployed({
                salt: _NATIVE_PER_USDC_FEED_SALT,
                creationCode: _loadArtifact("JBRatioPriceFeed"),
                arguments: feedCtorArgs
            });
            vm.serializeAddress({objectKey: j, valueKey: "JBRatioPriceFeed", value: feed});
            anyDeployed = true;
        }

        if (!anyDeployed) return;

        vm.serializeString({objectKey: j, valueKey: "format", value: "jb-v6-addresses-1"});
        string memory out = vm.serializeUint({objectKey: j, valueKey: "chainId", value: block.chainid});

        vm.createDir({path: "script/post-deploy/.cache", recursive: true});
        vm.writeJson({
            json: out, path: string.concat("script/post-deploy/.cache/addresses-", vm.toString(block.chainid), ".json")
        });
    }
}
