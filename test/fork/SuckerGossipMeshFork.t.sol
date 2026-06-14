// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../helpers/SuckerConservationBase.sol";

import {JBAccountingSnapshot} from "@bananapus/suckers-v6/src/structs/JBAccountingSnapshot.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";

/// @notice System-level stress tests for the cross-chain accounting GOSSIP MESH.
///
/// The conservation suite (`SuckerConservationMatrix`) drives single-peer round trips. These tests drive the part the
/// gossip release actually adds: a sucker receives a bundle of records for MANY source chains (its direct peer plus
/// sibling chains it has no direct bridge to), stores the freshest per chain, and the registry aggregates the union
/// across every sucker a project has — deduping each chain to one freshest value. That aggregate is what `REVLoans`,
/// `REVOwner`, and the LP hook read for cross-chain cash-out pricing, so it must be correct under realistic project
/// diversity.
///
/// Each scenario runs once per project type via a concrete cell (native ETH, 6-decimal USDC, 8-decimal WBTC), proving
/// the gossip accounting is independent of the terminal token while the surplus/balance fold respects each token's
/// currency and decimals.
///
/// A single mainnet fork models the mesh: a sucker's `fromRemoteAccounting` is delivered by hand (the OP messenger
/// path, peer-gated exactly as production), carrying a `JBChainAccounting[]` for chains the local chain has no direct
/// bridge to. `_storeAccountingBundle` is shared by the OP and CCIP receive paths, so exercising it through the OP
/// lane covers the storage + aggregation logic of both.
///
/// Run with: forge test --match-contract SuckerGossipMesh -vvv
abstract contract SuckerGossipMeshBase is SuckerConservationBase {
    // Source chains modeled in the mesh. CHAIN_OP (10) is the suckers' direct peer; ARB/BASE are siblings reachable
    // only by gossip (no direct sucker between the local chain and them).
    uint256 internal constant CHAIN_OP = 10;
    uint256 internal constant CHAIN_ARB = 42_161;
    uint256 internal constant CHAIN_BASE = 8453;
    uint256 internal constant CHAIN_LOCAL = 1; // the fork's block.chainid — a record for it must be skipped.

    // Sample remote supplies (project tokens are always 18-decimal, independent of the terminal token).
    uint256 internal constant SUP_OP = 7000e18;
    uint256 internal constant SUP_ARB = 3000e18;
    uint256 internal constant SUP_BASE = 5000e18;

    uint256 internal revnetId;
    address internal suckerA;
    address internal token; // the project's terminal token (native or ERC20)

    // ── Per-cell hooks
    // ──────────────────────────────────────────────────
    /// @dev Deploy the project of this cell's type and return its id; set `token` to its terminal token.
    function _deployMeshProject() internal virtual returns (uint256 id);
    /// @dev The currency id the terminal token values into (token-keyed for ERC20, native sentinel for ETH).
    function _meshCurrency() internal view virtual returns (uint256);
    /// @dev The terminal token's decimals.
    function _meshDecimals() internal view virtual returns (uint256);
    /// @dev A representative surplus/balance amount in the terminal token's decimals (fits uint128).
    function _meshContextAmount() internal view virtual returns (uint128);

    function setUp() public virtual override {
        super.setUp();
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));
        _deployFeeProject(0);
        _deployOpInfra();
        revnetId = _deployMeshProject();
        suckerA = _deployMeshSucker(bytes32("MESH_A"));
    }

    // ── Mesh helpers
    // ────────────────────────────────────────────────────

    /// @dev Deploy one OP sucker for the mesh project, mapping `token -> token` (identity remote token).
    function _deployMeshSucker(bytes32 salt) internal returns (address) {
        return _deploySucker(address(opDeployer), revnetId, salt, token, bytes32(uint256(uint160(token))));
    }

    /// @dev A supply-only accounting record (no contexts) for one source chain.
    function _acct(uint256 chainId, uint256 supply, uint256 timestamp)
        internal
        pure
        returns (JBChainAccounting memory)
    {
        return JBChainAccounting({
            chainId: chainId, totalSupply: supply, contexts: new JBSourceContext[](0), timestamp: timestamp
        });
    }

    /// @dev An accounting record carrying one surplus/balance context in this cell's terminal token + decimals.
    function _acctWithContext(
        uint256 chainId,
        uint256 supply,
        uint256 timestamp,
        uint128 surplus,
        uint128 balance
    )
        internal
        view
        returns (JBChainAccounting memory)
    {
        JBSourceContext[] memory ctx = new JBSourceContext[](1);
        ctx[0] = JBSourceContext({
            token: bytes32(uint256(uint160(token))),
            decimals: uint8(_meshDecimals()),
            surplus: surplus,
            balance: balance
        });
        return JBChainAccounting({chainId: chainId, totalSupply: supply, contexts: ctx, timestamp: timestamp});
    }

    /// @dev Deliver a gossip bundle to `sucker` over the (peer-gated) OP accounting path, exactly as the bridge would.
    function _gossip(address sucker, JBChainAccounting[] memory accounts) internal {
        opMessenger.setXDomainMessageSender(sucker);
        vm.prank(address(opMessenger));
        JBSucker(payable(sucker)).fromRemoteAccounting(JBAccountingSnapshot({version: 1, accounts: accounts}));
    }

    function _registry() internal view returns (IJBSuckerRegistry) {
        return IJBSuckerRegistry(address(SUCKER_REGISTRY));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Scenarios (run once per project-type cell)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice A bundle of records for three source chains is stored per chain, enumerated as virtual peers, and summed
    /// by the registry — the core sibling-spoke propagation: a sucker learns about chains it has no direct bridge to.
    function test_mesh_multiChainBundle_storesAndAggregates() public {
        JBChainAccounting[] memory accounts = new JBChainAccounting[](3);
        accounts[0] = _acct(CHAIN_OP, SUP_OP, 100);
        accounts[1] = _acct(CHAIN_ARB, SUP_ARB, 100);
        accounts[2] = _acct(CHAIN_BASE, SUP_BASE, 100);
        _gossip(suckerA, accounts);

        assertEq(IJBSucker(suckerA).peerChainTotalSupplyOf(CHAIN_OP), SUP_OP, "OP supply stored");
        assertEq(IJBSucker(suckerA).peerChainTotalSupplyOf(CHAIN_ARB), SUP_ARB, "ARB supply stored");
        assertEq(IJBSucker(suckerA).peerChainTotalSupplyOf(CHAIN_BASE), SUP_BASE, "BASE supply stored");
        assertEq(IJBSucker(suckerA).snapshotTimestampOf(CHAIN_ARB), 100, "ARB freshness stored");

        // Virtual peer set enumerates every gossiped chain (the direct peer 10 is already among them).
        uint256[] memory chains = IJBSucker(suckerA).peerChainIds(true);
        assertTrue(
            _contains(chains, CHAIN_OP) && _contains(chains, CHAIN_ARB) && _contains(chains, CHAIN_BASE),
            "all chains enumerated"
        );

        // Registry sums the union across all (deduped) chains.
        assertEq(
            _registry().remoteTotalSupplyOf(revnetId), SUP_OP + SUP_ARB + SUP_BASE, "registry sums all peer chains"
        );
    }

    /// @notice Each chain is gated on its own strictly-newer freshness key: a stale record for one chain is ignored
    /// while a fresh record for another in the SAME bundle is applied. No cross-chain rollback.
    function test_mesh_perChainFreshnessIsIndependent() public {
        JBChainAccounting[] memory first = new JBChainAccounting[](2);
        first[0] = _acct(CHAIN_OP, SUP_OP, 100);
        first[1] = _acct(CHAIN_ARB, SUP_ARB, 100);
        _gossip(suckerA, first);

        JBChainAccounting[] memory second = new JBChainAccounting[](2);
        second[0] = _acct(CHAIN_OP, 1, 50); // stale for OP (50 <= 100) — must be ignored
        second[1] = _acct(CHAIN_ARB, 9999e18, 200); // fresh for ARB (200 > 100) — must apply
        _gossip(suckerA, second);

        assertEq(IJBSucker(suckerA).peerChainTotalSupplyOf(CHAIN_OP), SUP_OP, "stale OP record ignored");
        assertEq(IJBSucker(suckerA).snapshotTimestampOf(CHAIN_OP), 100, "OP freshness not rolled back");
        assertEq(IJBSucker(suckerA).peerChainTotalSupplyOf(CHAIN_ARB), 9999e18, "fresh ARB record applied");
        assertEq(IJBSucker(suckerA).snapshotTimestampOf(CHAIN_ARB), 200, "ARB freshness advanced");
        assertEq(_registry().remoteTotalSupplyOf(revnetId), SUP_OP + 9999e18, "aggregate reflects per-chain freshest");
    }

    /// @notice A record describing the local chain (block.chainid) or chain 0 is dropped; valid records in the same
    /// bundle still land. Defends the self-read invariant and rejects the malformed chain-0 sentinel.
    function test_mesh_selfAndZeroChainRecordsSkipped() public {
        JBChainAccounting[] memory accounts = new JBChainAccounting[](3);
        accounts[0] = _acct(CHAIN_LOCAL, 1234e18, 100); // self — must be skipped
        accounts[1] = _acct(0, 5678e18, 100); // chain 0 — must be skipped
        accounts[2] = _acct(CHAIN_ARB, SUP_ARB, 100); // valid
        _gossip(suckerA, accounts);

        assertEq(IJBSucker(suckerA).peerChainTotalSupplyOf(CHAIN_LOCAL), 0, "self record not stored");
        assertEq(IJBSucker(suckerA).peerChainTotalSupplyOf(0), 0, "chain-0 record not stored");
        assertEq(IJBSucker(suckerA).peerChainTotalSupplyOf(CHAIN_ARB), SUP_ARB, "valid record stored");

        uint256[] memory chains = IJBSucker(suckerA).peerChainIds(true);
        assertFalse(_contains(chains, CHAIN_LOCAL), "local chain not a virtual peer");
        assertFalse(_contains(chains, 0), "chain 0 not a virtual peer");
        // Only ARB carries supply; the direct peer 10 is an empty sentinel and contributes nothing.
        assertEq(_registry().remoteTotalSupplyOf(revnetId), SUP_ARB, "aggregate excludes skipped chains");
    }

    /// @notice Many suckers for the SAME chain pair: two suckers both hold a record for chain 10. The registry dedups
    /// the chain to ONE freshest value — it is NOT double-counted across the suckers.
    function test_mesh_multiSucker_sameChainPair_dedupsToFreshest() public {
        address suckerB = _deployMeshSucker(bytes32("MESH_B"));

        _gossip(suckerA, _single(_acct(CHAIN_OP, SUP_OP, 100))); // older
        _gossip(suckerB, _single(_acct(CHAIN_OP, 9000e18, 200))); // fresher

        // Both suckers report chain 10, but the registry keeps only the freshest — counted once.
        assertEq(_registry().remoteTotalSupplyOf(revnetId), 9000e18, "same chain deduped to freshest, not summed");
    }

    /// @notice Many suckers covering DIFFERENT chains: the registry unions every distinct chain across suckers. One
    /// sucker's direct + gossiped chains plus a second sucker's gossiped chain all contribute exactly once.
    function test_mesh_multiSucker_unionAcrossChains() public {
        address suckerB = _deployMeshSucker(bytes32("MESH_B"));

        JBChainAccounting[] memory aBundle = new JBChainAccounting[](2);
        aBundle[0] = _acct(CHAIN_OP, SUP_OP, 100);
        aBundle[1] = _acct(CHAIN_ARB, SUP_ARB, 100);
        _gossip(suckerA, aBundle);
        _gossip(suckerB, _single(_acct(CHAIN_BASE, SUP_BASE, 100)));

        assertEq(IJBSucker(suckerA).peerChainTotalSupplyOf(CHAIN_ARB), SUP_ARB, "A holds ARB");
        assertEq(IJBSucker(suckerB).peerChainTotalSupplyOf(CHAIN_BASE), SUP_BASE, "B holds BASE");
        assertEq(
            _registry().remoteTotalSupplyOf(revnetId),
            SUP_OP + SUP_ARB + SUP_BASE,
            "registry unions chains across suckers"
        );
    }

    /// @notice A gossiped record's surplus/balance context, carried in this cell's terminal token + decimals, folds
    /// into the registry's remote surplus/balance views AT PAR when queried in the same currency/decimals. Proves the
    /// aggregation respects each project type's token and precision.
    function test_mesh_sameCurrencyContext_foldsAtPar() public {
        uint128 amt = _meshContextAmount();
        _gossip(suckerA, _single(_acctWithContext(CHAIN_ARB, SUP_ARB, 100, amt, amt)));

        uint256 cur = _meshCurrency();
        uint256 dec = _meshDecimals();
        assertEq(_registry().totalRemoteSurplusOf(revnetId, cur, dec), amt, "remote surplus folds context at par");
        assertEq(_registry().totalRemoteBalanceOf(revnetId, cur, dec), amt, "remote balance folds context at par");
        // Supply view still aggregates the supply alongside the valued context.
        assertEq(_registry().remoteTotalSupplyOf(revnetId), SUP_ARB, "supply aggregated alongside context");
    }

    // ── small array utilities
    // ───────────────────────────────────────────
    function _single(JBChainAccounting memory a) internal pure returns (JBChainAccounting[] memory arr) {
        arr = new JBChainAccounting[](1);
        arr[0] = a;
    }

    function _contains(uint256[] memory xs, uint256 v) internal pure returns (bool) {
        for (uint256 i; i < xs.length; ++i) {
            if (xs[i] == v) return true;
        }
        return false;
    }

    /// @dev Deploy an ERC20 revnet with `decimals`-decimal terminal token (currency == baseCurrency, no price feed).
    function _deployErc20MeshRevnet(
        uint8 decimals,
        string memory symbol,
        bytes32 descSalt
    )
        internal
        returns (uint256 id, MockERC20Token erc20)
    {
        erc20 = new MockERC20Token(symbol, symbol, decimals);

        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] =
            JBAccountingContext({token: address(erc20), decimals: decimals, currency: uint32(uint160(address(erc20)))});

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
            description: REVDescription(symbol, symbol, "ipfs://mesh", descSalt),
            baseCurrency: uint32(uint160(address(erc20))),
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
}

/// @notice Gossip mesh over a NATIVE ETH (18-decimal) revnet.
contract SuckerGossipMeshNativeTest is SuckerGossipMeshBase {
    function _deployerSalt() internal pure override returns (bytes32) {
        return "GossipMesh_Native";
    }

    function _deployMeshProject() internal override returns (uint256 id) {
        id = _deployRevnet(0);
        token = JBConstants.NATIVE_TOKEN;
    }

    function _meshCurrency() internal pure override returns (uint256) {
        return uint32(uint160(JBConstants.NATIVE_TOKEN));
    }

    function _meshDecimals() internal pure override returns (uint256) {
        return 18;
    }

    function _meshContextAmount() internal pure override returns (uint128) {
        return 5 ether;
    }
}

/// @notice Gossip mesh over a 6-decimal USDC revnet.
contract SuckerGossipMeshUsdcTest is SuckerGossipMeshBase {
    MockERC20Token internal usdc;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "GossipMesh_Usdc";
    }

    function _deployMeshProject() internal override returns (uint256 id) {
        (id, usdc) = _deployErc20MeshRevnet(6, "USDC", bytes32("MESH_USDC"));
        token = address(usdc);
    }

    function _meshCurrency() internal view override returns (uint256) {
        return uint32(uint160(address(usdc)));
    }

    function _meshDecimals() internal pure override returns (uint256) {
        return 6;
    }

    function _meshContextAmount() internal pure override returns (uint128) {
        return 5000e6;
    }
}

/// @notice Gossip mesh over an 8-decimal WBTC-like revnet (decimal diversity).
contract SuckerGossipMeshWbtcTest is SuckerGossipMeshBase {
    MockERC20Token internal wbtc;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "GossipMesh_Wbtc";
    }

    function _deployMeshProject() internal override returns (uint256 id) {
        (id, wbtc) = _deployErc20MeshRevnet(8, "WBTC", bytes32("MESH_WBTC"));
        token = address(wbtc);
    }

    function _meshCurrency() internal view override returns (uint256) {
        return uint32(uint160(address(wbtc)));
    }

    function _meshDecimals() internal pure override returns (uint256) {
        return 8;
    }

    function _meshContextAmount() internal pure override returns (uint128) {
        return 3e8;
    }
}
