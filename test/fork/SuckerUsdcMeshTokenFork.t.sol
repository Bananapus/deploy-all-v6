// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../helpers/SuckerConservationBase.sol";

import {JBAccountingSnapshot} from "@bananapus/suckers-v6/src/structs/JBAccountingSnapshot.sol";
import {JBPeerChainContext} from "@bananapus/suckers-v6/src/structs/JBPeerChainContext.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";

/// @notice Ecosystem fork proof of the cross-chain accounting GOSSIP MESH **token normalization** across the real
/// Base <-> Mainnet <-> Arbitrum hub-and-spoke, where USDC has a DIFFERENT contract address on every chain:
///
///   - Mainnet (hub)  USDC = 0xA0b8…eB48
///   - Base (spoke)   USDC = 0x8335…2913
///   - Arbitrum (spoke) USDC = 0xaf88…5831
///
/// Base and Arbitrum bridge only THROUGH Mainnet (no direct Base<->Arbitrum sucker). The accounting of one spoke must
/// still convey to the other and fold under the receiver's OWN local USDC currency, even though no chain on the path
/// shares a USDC address and a receiver only ever maps its own USDC against the hub's.
///
/// The mechanism under test: a receiver RE-KEYS each incoming context's token to its own local token via its
/// remote->local token mapping at storage time. So the Mainnet hub stores each spoke's record under MAINNET USDC, and
/// the far spoke — which only maps `localUsdc <-> mainnetUsdc` — resolves the forwarded sibling record without ever
/// knowing the sibling's USDC address.
///
/// A single mainnet fork (block.chainid == 1 == the Mainnet hub) models the chains; the three USDC contracts are etched
/// at their real addresses; gossip is delivered by hand over the peer-gated OP accounting lane exactly as the bridge
/// would. The OP and CCIP receive paths share `_storeAccountingBundle`, so the OP lane covers the re-key + fold for
/// both bridge families; the modeled remote chain ids (1 / 8453 / 42161) ride in the gossip records, never colliding
/// with `block.chainid`.
///
/// Run with: forge test --match-contract SuckerUsdcMeshToken -vvv
contract SuckerUsdcMeshTokenForkTest is SuckerConservationBase {
    // Real chain ids and real USDC addresses — the whole point is that the three USDC addresses differ.
    uint256 internal constant CHAIN_MAINNET = 1; // the hub (this fork's block.chainid)
    uint256 internal constant CHAIN_BASE = 8453; // a spoke
    uint256 internal constant CHAIN_ARB = 42_161; // a spoke
    uint256 internal constant CHAIN_UNROUTED = 137; // a chain whose USDC the mesh cannot normalize (fail-closed case)

    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant ARB_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant POLY_USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359; // unrouted on this mesh

    // Sample per-spoke accounting (project tokens are 18-decimal; terminal amounts are 6-decimal USDC).
    uint256 internal constant BASE_SUPPLY = 500e18;
    uint128 internal constant BASE_SURPLUS = 45_000e6;
    uint128 internal constant BASE_BALANCE = 125_000e6;
    uint256 internal constant ARB_SUPPLY = 300e18;
    uint128 internal constant ARB_SURPLUS = 90_000e6;
    uint128 internal constant ARB_BALANCE = 170_000e6;

    // Hub (Mainnet) project + its two spoke lanes, all for one project so the registry aggregates them.
    uint256 internal hubRevnet;
    address internal hubBaseLane; // Mainnet's lane to Base.     maps MAINNET_USDC <-> BASE_USDC
    address internal hubArbLane; // Mainnet's lane to Arbitrum.  maps MAINNET_USDC <-> ARB_USDC

    // Edge (spoke) projects, each modeling a spoke that only knows its own USDC <-> the hub's USDC.
    uint256 internal baseEdgeRevnet;
    address internal baseEdgeSucker; // Base's lane to Mainnet.    maps BASE_USDC <-> MAINNET_USDC
    uint256 internal arbEdgeRevnet;
    address internal arbEdgeSucker; // Arbitrum's lane to Mainnet. maps ARB_USDC <-> MAINNET_USDC

    function _deployerSalt() internal pure override returns (bytes32) {
        return "UsdcMeshToken";
    }

    function setUp() public override {
        super.setUp();
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
        _deployFeeProject(0);
        _deployOpInfra();

        // Put a real 6-decimal USDC at each chain's real address.
        _etchUsdc(MAINNET_USDC);
        _etchUsdc(BASE_USDC);
        _etchUsdc(ARB_USDC);

        // The Mainnet hub project accounts in Mainnet USDC and has a lane to each spoke.
        hubRevnet = _deployUsdcRevnetAt(MAINNET_USDC, "MESH_HUB");
        hubBaseLane = _deploySucker(address(opDeployer), hubRevnet, "HUB_BASE_LANE", MAINNET_USDC, _b32(BASE_USDC));
        hubArbLane = _deploySucker(address(opDeployer), hubRevnet, "HUB_ARB_LANE", MAINNET_USDC, _b32(ARB_USDC));

        // Each spoke project accounts in its OWN USDC and only maps it against the hub's USDC.
        baseEdgeRevnet = _deployUsdcRevnetAt(BASE_USDC, "MESH_BASE");
        baseEdgeSucker = _deploySucker(address(opDeployer), baseEdgeRevnet, "BASE_EDGE", BASE_USDC, _b32(MAINNET_USDC));
        arbEdgeRevnet = _deployUsdcRevnetAt(ARB_USDC, "MESH_ARB");
        arbEdgeSucker = _deploySucker(address(opDeployer), arbEdgeRevnet, "ARB_EDGE", ARB_USDC, _b32(MAINNET_USDC));

        // Sanity: the three USDC addresses are genuinely distinct.
        assertTrue(MAINNET_USDC != BASE_USDC && BASE_USDC != ARB_USDC && MAINNET_USDC != ARB_USDC, "distinct USDC");
    }

    // ───────────────────────────────────────────────────────────────────
    //  Hub — Mainnet normalizes BOTH spokes' different-address USDC under its own currency.
    // ───────────────────────────────────────────────────────────────────

    /// @notice The Mainnet hub receives Base's record (in Base USDC) and Arbitrum's record (in Arbitrum USDC), stores
    /// each under MAINNET USDC, and its registry aggregate folds both spokes' surplus/balance under the hub's local
    /// USDC currency — three different USDC addresses converging to one currency.
    function test_hubNormalizesBothSpokeUsdcUnderMainnetCurrency() public {
        _gossip(hubBaseLane, _single(_acct(CHAIN_BASE, BASE_SUPPLY, _ctx(BASE_USDC, BASE_SURPLUS, BASE_BALANCE), 100)));
        _gossip(hubArbLane, _single(_acct(CHAIN_ARB, ARB_SUPPLY, _ctx(ARB_USDC, ARB_SURPLUS, ARB_BALANCE), 100)));

        // Each lane re-keyed the spoke's USDC to the hub's local USDC.
        (, JBChainAccounting memory baseRec) = _find(IJBSucker(hubBaseLane).peerChainAccountsOf(), CHAIN_BASE);
        assertEq(baseRec.contexts[0].token, _b32(MAINNET_USDC), "Base USDC re-keyed to Mainnet USDC at the hub");
        (, JBChainAccounting memory arbRec) = _find(IJBSucker(hubArbLane).peerChainAccountsOf(), CHAIN_ARB);
        assertEq(arbRec.contexts[0].token, _b32(MAINNET_USDC), "Arbitrum USDC re-keyed to Mainnet USDC at the hub");

        // The hub's registry aggregate folds both spokes at par under Mainnet USDC, and unions both chains' supply.
        uint32 mainnetCurrency = uint32(uint160(MAINNET_USDC));
        assertEq(
            _reg().totalRemoteSurplusOf(hubRevnet, mainnetCurrency, 6),
            uint256(BASE_SURPLUS) + ARB_SURPLUS,
            "hub folds Base + Arbitrum surplus under Mainnet USDC"
        );
        assertEq(
            _reg().totalRemoteBalanceOf(hubRevnet, mainnetCurrency, 6),
            uint256(BASE_BALANCE) + ARB_BALANCE,
            "hub folds Base + Arbitrum balance under Mainnet USDC"
        );
        assertEq(_reg().remoteTotalSupplyOf(hubRevnet), BASE_SUPPLY + ARB_SUPPLY, "hub unions both spokes' supply");
    }

    /// @notice When the hub gathers a project's records to forward to one spoke, it excludes that spoke and expresses
    /// every other spoke's record in MAINNET USDC — so the destination spoke needs only its own `localUsdc <->
    /// mainnet`
    /// mapping to resolve a sibling it has no direct bridge to.
    function test_hubForwardsEachSiblingInMainnetTermsExcludingDestination() public {
        _gossip(hubBaseLane, _single(_acct(CHAIN_BASE, BASE_SUPPLY, _ctx(BASE_USDC, BASE_SURPLUS, BASE_BALANCE), 100)));
        _gossip(hubArbLane, _single(_acct(CHAIN_ARB, ARB_SUPPLY, _ctx(ARB_USDC, ARB_SURPLUS, ARB_BALANCE), 100)));

        // Forwarding to Base: Arbitrum's record is included (in Mainnet USDC), Base's own is excluded.
        JBChainAccounting[] memory toBase = _reg().peerChainAccountsOf(hubRevnet, CHAIN_BASE);
        (bool hasArb, JBChainAccounting memory arbToBase) = _find(toBase, CHAIN_ARB);
        (bool hasBase,) = _find(toBase, CHAIN_BASE);
        assertTrue(hasArb && !hasBase, "forward-to-Base carries Arbitrum, excludes Base");
        assertEq(arbToBase.contexts[0].token, _b32(MAINNET_USDC), "Arbitrum forwarded to Base in Mainnet USDC");

        // Forwarding to Arbitrum: Base's record is included (in Mainnet USDC), Arbitrum's own is excluded.
        JBChainAccounting[] memory toArb = _reg().peerChainAccountsOf(hubRevnet, CHAIN_ARB);
        (bool hasBase2, JBChainAccounting memory baseToArb) = _find(toArb, CHAIN_BASE);
        (bool hasArb2,) = _find(toArb, CHAIN_ARB);
        assertTrue(hasBase2 && !hasArb2, "forward-to-Arbitrum carries Base, excludes Arbitrum");
        assertEq(baseToArb.contexts[0].token, _b32(MAINNET_USDC), "Base forwarded to Arbitrum in Mainnet USDC");
    }

    // ───────────────────────────────────────────────────────────────────
    //  Edges — a sibling spoke's USDC conveys end-to-end to the far edge, folded under the edge's own USDC.
    // ───────────────────────────────────────────────────────────────────

    /// @notice End-to-end Arbitrum -> Mainnet hub -> Base. Arbitrum's surplus, originating in Arbitrum USDC, transits
    /// the hub (re-keyed to Mainnet USDC) and lands on the Base edge folded under BASE USDC — across three different
    /// USDC addresses, with Base never mapping Arbitrum's USDC.
    function test_e2e_arbitrumUsdcReachesBaseEdgeUnderBaseCurrency() public {
        // Hop 1 — the hub re-keys Arbitrum USDC -> Mainnet USDC.
        _gossip(hubArbLane, _single(_acct(CHAIN_ARB, ARB_SUPPLY, _ctx(ARB_USDC, ARB_SURPLUS, ARB_BALANCE), 100)));
        (, JBChainAccounting memory forwarded) = _find(IJBSucker(hubArbLane).peerChainAccountsOf(), CHAIN_ARB);
        assertEq(forwarded.contexts[0].token, _b32(MAINNET_USDC), "precondition: hub forwards Arbitrum in Mainnet USDC");

        // Hop 2 — Base receives the hub's forwarded bundle and re-keys Mainnet USDC -> Base USDC.
        _gossip(baseEdgeSucker, _single(forwarded));

        uint32 baseCurrency = uint32(uint160(BASE_USDC));
        (JBPeerChainContext[] memory ctx,) = IJBSucker(baseEdgeSucker).peerChainContextsOf(CHAIN_ARB);
        assertEq(ctx.length, 1, "Arbitrum resolves to one Base-currency context");
        assertEq(ctx[0].currency, baseCurrency, "Arbitrum folds under BASE USDC at the Base edge");
        assertEq(ctx[0].decimals, 6, "USDC decimals preserved end to end");
        assertEq(ctx[0].surplus, ARB_SURPLUS, "Arbitrum surplus conveyed intact");
        assertEq(ctx[0].balance, ARB_BALANCE, "Arbitrum balance conveyed intact");

        (, JBChainAccounting memory stored) = _find(IJBSucker(baseEdgeSucker).peerChainAccountsOf(), CHAIN_ARB);
        assertEq(stored.contexts[0].token, _b32(BASE_USDC), "Base edge stores Arbitrum under BASE USDC");

        assertEq(
            _reg().totalRemoteSurplusOf(baseEdgeRevnet, baseCurrency, 6),
            ARB_SURPLUS,
            "Base edge remote surplus includes Arbitrum, folded under Base USDC"
        );
        assertEq(_reg().remoteTotalSupplyOf(baseEdgeRevnet), ARB_SUPPLY, "Base edge counts Arbitrum supply");

        // Base reached Arbitrum purely by gossip — it is a virtual peer, not a direct bridge peer.
        assertTrue(_has(IJBSucker(baseEdgeSucker).peerChainIds(true), CHAIN_ARB), "Arbitrum is a virtual peer of Base");
        assertFalse(_has(IJBSucker(baseEdgeSucker).peerChainIds(false), CHAIN_ARB), "Base has no direct bridge to Arb");
    }

    /// @notice The reverse edge: end-to-end Base -> Mainnet hub -> Arbitrum. Base's surplus lands on the Arbitrum edge
    /// folded under ARBITRUM USDC. Proves both far edges of the mesh receive the other's different-address USDC.
    function test_e2e_baseUsdcReachesArbitrumEdgeUnderArbitrumCurrency() public {
        _gossip(hubBaseLane, _single(_acct(CHAIN_BASE, BASE_SUPPLY, _ctx(BASE_USDC, BASE_SURPLUS, BASE_BALANCE), 100)));
        (, JBChainAccounting memory forwarded) = _find(IJBSucker(hubBaseLane).peerChainAccountsOf(), CHAIN_BASE);
        assertEq(forwarded.contexts[0].token, _b32(MAINNET_USDC), "precondition: hub forwards Base in Mainnet USDC");

        _gossip(arbEdgeSucker, _single(forwarded));

        uint32 arbCurrency = uint32(uint160(ARB_USDC));
        (JBPeerChainContext[] memory ctx,) = IJBSucker(arbEdgeSucker).peerChainContextsOf(CHAIN_BASE);
        assertEq(ctx.length, 1, "Base resolves to one Arbitrum-currency context");
        assertEq(ctx[0].currency, arbCurrency, "Base folds under ARBITRUM USDC at the Arbitrum edge");
        assertEq(ctx[0].surplus, BASE_SURPLUS, "Base surplus conveyed intact");
        assertEq(ctx[0].balance, BASE_BALANCE, "Base balance conveyed intact");

        assertEq(
            _reg().totalRemoteSurplusOf(arbEdgeRevnet, arbCurrency, 6),
            BASE_SURPLUS,
            "Arbitrum edge remote surplus includes Base, folded under Arbitrum USDC"
        );
    }

    // ───────────────────────────────────────────────────────────────────
    //  Fail-closed — a USDC the edge cannot normalize is dropped from surplus, never over-credited.
    // ───────────────────────────────────────────────────────────────────

    /// @notice A record reaches the Base edge carrying a USDC the edge cannot resolve to Base USDC (an unrouted chain's
    /// token, never re-keyed because no hop on the path bridged it). Its surplus does NOT fold into Base USDC (it
    /// resolves to a foreign currency with no price feed and is dropped), while its supply — currency-agnostic —
    /// still
    /// counts. The mesh under-reports rather than over-credits: the safe direction for cash-out pricing.
    function test_unnormalizableSiblingTokenFailsClosedOnSurplus() public {
        JBChainAccounting[] memory bundle = new JBChainAccounting[](2);
        // A normalized Arbitrum record (already in Mainnet USDC, which Base maps) folds.
        bundle[0] = _acct(CHAIN_ARB, ARB_SUPPLY, _ctx(MAINNET_USDC, ARB_SURPLUS, ARB_BALANCE), 100);
        // An unrouted chain's USDC the Base edge has no mapping for cannot fold.
        bundle[1] = _acct(CHAIN_UNROUTED, 111e18, _ctx(POLY_USDC, 50_000e6, 60_000e6), 100);
        _gossip(baseEdgeSucker, bundle);

        uint32 baseCurrency = uint32(uint160(BASE_USDC));
        assertEq(
            _reg().totalRemoteSurplusOf(baseEdgeRevnet, baseCurrency, 6),
            ARB_SURPLUS,
            "only normalizable surplus folds; the unrouted token's surplus is dropped (fail-closed)"
        );
        assertEq(_reg().totalRemoteBalanceOf(baseEdgeRevnet, baseCurrency, 6), ARB_BALANCE, "unrouted balance dropped");
        assertEq(
            _reg().remoteTotalSupplyOf(baseEdgeRevnet),
            ARB_SUPPLY + 111e18,
            "supply unions every gossiped chain regardless of token resolvability"
        );

        (, JBChainAccounting memory unrouted) = _find(IJBSucker(baseEdgeSucker).peerChainAccountsOf(), CHAIN_UNROUTED);
        assertEq(
            unrouted.contexts[0].token, _b32(POLY_USDC), "unmapped token stays verbatim, never aliased to Base USDC"
        );
    }

    // ───────────────────────────────────────────────────────────────────
    //  Helpers
    // ───────────────────────────────────────────────────────────────────

    /// @dev Place a real 6-decimal USDC contract at `at` (its real mainnet/base/arbitrum address).
    function _etchUsdc(address at) internal {
        MockERC20Token impl = new MockERC20Token("USD Coin", "USDC", 6);
        vm.etch(at, address(impl).code);
    }

    /// @dev Deploy a revnet whose terminal accepts the (already-etched) `usdc` token. Mirrors `_deployUsdcRevnet` but
    /// uses a caller-chosen token address so each chain's revnet accounts in that chain's real USDC.
    function _deployUsdcRevnetAt(address usdc, bytes32 descSalt) internal returns (uint256 id) {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: usdc, decimals: 6, currency: uint32(uint160(usdc))});

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0].beneficiary = payable(multisig());
        splits[0].percent = 10_000;

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 0,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: 0,
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("USDC Revnet", "USDCR", "ipfs://usdc-mesh", descSalt),
            baseCurrency: uint32(uint160(usdc)),
            operator: multisig(),
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked(descSalt))
        });

        (id,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, accountingContextsToAccept: acc, suckerDeploymentConfiguration: sdc
        });
    }

    /// @dev Deliver a gossip bundle to `sucker` over the peer-gated OP accounting path, exactly as the bridge would.
    function _gossip(address sucker, JBChainAccounting[] memory accounts) internal {
        opMessenger.setXDomainMessageSender(sucker);
        vm.prank(address(opMessenger));
        JBSucker(payable(sucker)).fromRemoteAccounting(JBAccountingSnapshot({version: 1, accounts: accounts}));
    }

    /// @dev One accounting record with a single surplus/balance context.
    function _acct(
        uint256 chainId,
        uint256 supply,
        JBSourceContext memory context,
        uint256 timestamp
    )
        internal
        pure
        returns (JBChainAccounting memory)
    {
        JBSourceContext[] memory ctx = new JBSourceContext[](1);
        ctx[0] = context;
        return JBChainAccounting({chainId: chainId, totalSupply: supply, contexts: ctx, timestamp: timestamp});
    }

    /// @dev A single 6-decimal USDC context keyed by `token`.
    function _ctx(address token, uint128 surplus, uint128 balance) internal pure returns (JBSourceContext memory) {
        return JBSourceContext({token: _b32(token), decimals: 6, surplus: surplus, balance: balance});
    }

    function _single(JBChainAccounting memory a) internal pure returns (JBChainAccounting[] memory arr) {
        arr = new JBChainAccounting[](1);
        arr[0] = a;
    }

    function _find(
        JBChainAccounting[] memory xs,
        uint256 chainId
    )
        internal
        pure
        returns (bool found, JBChainAccounting memory record)
    {
        for (uint256 i; i < xs.length; ++i) {
            if (xs[i].chainId == chainId) return (true, xs[i]);
        }
    }

    function _has(uint256[] memory xs, uint256 v) internal pure returns (bool) {
        for (uint256 i; i < xs.length; ++i) {
            if (xs[i] == v) return true;
        }
        return false;
    }

    function _b32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    function _reg() internal view returns (IJBSuckerRegistry) {
        return IJBSuckerRegistry(address(SUCKER_REGISTRY));
    }
}
