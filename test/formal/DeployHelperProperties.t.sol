// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Deploy} from "../../script/Deploy.s.sol";
import {CREATE3} from "solady/src/utils/CREATE3.sol";

/// @title DeployHelperProperties
/// @notice Formal verification of the pure address/salt/truncation helpers in `Deploy.s.sol`.
/// @dev These helpers are the load-bearing, deterministic pieces of the deployment orchestrator:
///      salt namespacing, CREATE3 address prediction, and bounded-integer truncation. A bug in any of
///      them silently corrupts every counterfactual address or every packed timestamp/currency.
///
///      DUAL VERIFICATION (house convention):
///      - `testFuzz_*` (forge) call the REAL `Deploy` internal helpers via a harness that subclasses the
///        shipped `Deploy` script, so the fuzzer validates the deployed logic AND that the `check_`
///        replicas below are faithful to it.
///      - `check_*` (Halmos) call `internal pure` replicas of the EXACT one-line helper bodies (and the
///        real `DEPLOYMENT_NONCE`/`_CREATE2_FACTORY` constants). This is required because `Deploy is
///        Sphinx`, and the Sphinx constructor uses Foundry cheatcodes (`vm.makePersistent`, helper
///        deploys) that Halmos cannot symbolically execute — so a `Deploy` subclass cannot be deployed
///        inside a symbolic run. The replicas are trivial (truncation / keccak fold / Solady CREATE3),
///        and the fuzz layer pins them to the shipped code.
contract DeployHelperHarness is Deploy {
    function currencyIdOf(address token) external pure returns (uint32) {
        return _currencyIdOf(token);
    }

    function timestamp40(uint256 timestamp) external pure returns (uint40) {
        return _timestamp40(timestamp);
    }

    function timestamp48(uint256 timestamp) external pure returns (uint48) {
        return _timestamp48(timestamp);
    }

    function saltOf(bytes32 base) external pure returns (bytes32) {
        return _saltOf(base);
    }

    function create3Address(bytes32 salt) external pure returns (address) {
        return _create3Address(salt);
    }

    function chainIdToRouteSuffix(uint256 chainId) external pure returns (string memory) {
        return _chainIdToRouteSuffix(chainId);
    }
}

contract DeployHelperProperties is Test {
    DeployHelperHarness internal h;

    // Mirror of Deploy.s.sol constants (private there). Pinned to the shipped values; the fuzz layer
    // checks the replicas below against the real `Deploy` helpers, so any drift here surfaces as a fuzz
    // failure (testFuzz_replicasMatchShippedDeploy).
    uint256 private constant DEPLOYMENT_NONCE = 12;
    // CREATE2_FACTORY (the Arachnid deterministic-deployment proxy, the same address Deploy.s.sol uses)
    // is already declared by forge-std's CommonBase, so we reuse the inherited constant.

    // The supported chain ids the deployment targets (mainnets + sepolia testnets).
    uint256[8] internal SUPPORTED_CHAINS = [uint256(1), 11_155_111, 10, 11_155_420, 8453, 84_532, 42_161, 421_614];

    function setUp() public {
        h = new DeployHelperHarness();
    }

    // ---- internal pure replicas of the EXACT Deploy.s.sol helper bodies (for Halmos) ----

    function _currencyId(address token) internal pure returns (uint32) {
        return uint32(uint160(token));
    }

    function _salt(bytes32 base) internal pure returns (bytes32) {
        return keccak256(abi.encode(DEPLOYMENT_NONCE, base));
    }

    function _create3(bytes32 salt) internal pure returns (address) {
        return CREATE3.predictDeterministicAddress({salt: _salt(salt), deployer: CREATE2_FACTORY});
    }

    // Replicas of the bounded-truncation helper bodies (revert above bound, else lossless cast).
    function _ts40(uint256 timestamp) internal pure returns (uint40) {
        if (timestamp > type(uint40).max) revert Deploy.Deploy_TimestampOverflow(timestamp);
        return uint40(timestamp);
    }

    function _ts48(uint256 timestamp) internal pure returns (uint48) {
        if (timestamp > type(uint48).max) revert Deploy.Deploy_TimestampOverflow(timestamp);
        return uint48(timestamp);
    }

    // =========================================================================
    // Replica fidelity: the Halmos replicas equal the SHIPPED Deploy helpers
    // =========================================================================
    // This is what licenses `check_*` (which use the replicas) to speak for the real code.
    function testFuzz_replicasMatchShippedDeploy(address token, bytes32 a, uint256 ts) public view {
        assertEq(uint256(_currencyId(token)), uint256(h.currencyIdOf(token)), "currencyId replica == shipped");
        assertEq(_salt(a), h.saltOf(a), "salt replica == shipped");
        assertEq(_create3(a), h.create3Address(a), "create3 replica == shipped");
        uint256 ts40 = bound(ts, 0, type(uint40).max);
        assertEq(uint256(_ts40(ts40)), uint256(h.timestamp40(ts40)), "ts40 replica == shipped");
        uint256 ts48 = bound(ts, 0, type(uint48).max);
        assertEq(uint256(_ts48(ts48)), uint256(h.timestamp48(ts48)), "ts48 replica == shipped");
    }

    // =========================================================================
    // Property: _currencyIdOf isolates the low 32 bits of the token address
    // =========================================================================
    // Spec (Deploy.s.sol): "Juicebox price-feed currency IDs use the low 32 bits of ERC-20 token
    // addresses" => uint32(uint160(token)). The result must equal the address modulo 2^32.
    // forge-lint: disable-next-line(mixed-case-function)
    function check_currencyId_isLow32Bits(address token) public pure {
        uint32 id = _currencyId(token);
        assert(uint256(id) == uint256(uint160(token)) % (1 << 32));
        assert(uint256(id) < (1 << 32));
    }

    function testFuzz_currencyId_isLow32Bits(address token) public view {
        uint32 id = h.currencyIdOf(token);
        assertEq(uint256(id), uint256(uint160(token)) % (1 << 32), "currencyId must be low 32 bits of token");
    }

    // =========================================================================
    // Property: _currencyIdOf is injective on the low 32 bits
    // =========================================================================
    // Two tokens share a currency id iff they share their low 32 bits. This is the invariant that makes
    // the truncation safe for canonical tokens (whose low bits differ).
    // forge-lint: disable-next-line(mixed-case-function)
    function check_currencyId_collisionIffLowBitsEqual(address a, address b) public pure {
        bool sameId = _currencyId(a) == _currencyId(b);
        bool sameLow = (uint256(uint160(a)) % (1 << 32)) == (uint256(uint160(b)) % (1 << 32));
        assert(sameId == sameLow);
    }

    function testFuzz_currencyId_collisionIffLowBitsEqual(address a, address b) public view {
        bool sameId = h.currencyIdOf(a) == h.currencyIdOf(b);
        bool sameLow = (uint256(uint160(a)) % (1 << 32)) == (uint256(uint160(b)) % (1 << 32));
        assertEq(sameId, sameLow, "currency-id collision iff low 32 bits equal");
    }

    // =========================================================================
    // Property: _timestamp40 round-trips below the bound and reverts above
    // =========================================================================
    // forge-lint: disable-next-line(mixed-case-function)
    function check_timestamp40_roundTrip(uint256 ts) public pure {
        vm.assume(ts <= type(uint40).max);
        uint40 t = _ts40(ts);
        assert(uint256(t) == ts);
    }

    function testFuzz_timestamp40_roundTrip(uint256 ts) public view {
        ts = bound(ts, 0, type(uint40).max);
        assertEq(uint256(h.timestamp40(ts)), ts, "timestamp40 must be lossless within uint40");
    }

    function testFuzz_timestamp40_revertsAboveBound(uint256 ts) public {
        ts = bound(ts, uint256(type(uint40).max) + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Deploy.Deploy_TimestampOverflow.selector, ts));
        h.timestamp40(ts);
    }

    // =========================================================================
    // Property: _timestamp48 round-trips below the bound and reverts above
    // =========================================================================
    // forge-lint: disable-next-line(mixed-case-function)
    function check_timestamp48_roundTrip(uint256 ts) public pure {
        vm.assume(ts <= type(uint48).max);
        uint48 t = _ts48(ts);
        assert(uint256(t) == ts);
    }

    function testFuzz_timestamp48_roundTrip(uint256 ts) public view {
        ts = bound(ts, 0, type(uint48).max);
        assertEq(uint256(h.timestamp48(ts)), ts, "timestamp48 must be lossless within uint48");
    }

    function testFuzz_timestamp48_revertsAboveBound(uint256 ts) public {
        ts = bound(ts, uint256(type(uint48).max) + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Deploy.Deploy_TimestampOverflow.selector, ts));
        h.timestamp48(ts);
    }

    // =========================================================================
    // Property: _saltOf is injective in `base` (one nonce bump re-namespaces all)
    // =========================================================================
    // Spec: "Fold the single DEPLOYMENT_NONCE into every salt so one bump re-namespaces the entire
    // deployment." Distinct bases must produce distinct salts (otherwise two contracts collide at the
    // same CREATE2/CREATE3 address). Halmos models keccak256 as injective, so this is provable.
    // forge-lint: disable-next-line(mixed-case-function)
    function check_saltOf_injective(bytes32 a, bytes32 b) public pure {
        vm.assume(a != b);
        assert(_salt(a) != _salt(b));
    }

    function testFuzz_saltOf_injective(bytes32 a, bytes32 b) public view {
        vm.assume(a != b);
        assertTrue(h.saltOf(a) != h.saltOf(b), "distinct salt bases must yield distinct folded salts");
    }

    // =========================================================================
    // Property: _saltOf is deterministic (referential transparency)
    // =========================================================================
    // forge-lint: disable-next-line(mixed-case-function)
    function check_saltOf_deterministic(bytes32 base) public pure {
        assert(_salt(base) == _salt(base));
    }

    // =========================================================================
    // Property: _create3Address is injective in `salt` (no two salts collide)
    // =========================================================================
    // The counterfactual CREATE3 address is a function of `_saltOf(salt)`, which is injective in salt;
    // CREATE3.predictDeterministicAddress is injective in its salt (keccak-derived). So distinct salts
    // must map to distinct predicted addresses — the property the omnichain controller/deployer pair
    // relies on to avoid baking a colliding immutable.
    // forge-lint: disable-next-line(mixed-case-function)
    function check_create3Address_injective(bytes32 a, bytes32 b) public pure {
        vm.assume(a != b);
        assert(_create3(a) != _create3(b));
    }

    function testFuzz_create3Address_injective(bytes32 a, bytes32 b) public view {
        vm.assume(a != b);
        assertTrue(h.create3Address(a) != h.create3Address(b), "distinct salts must predict distinct CREATE3 addrs");
    }

    // =========================================================================
    // Property: _create3Address is deterministic
    // =========================================================================
    // forge-lint: disable-next-line(mixed-case-function)
    function check_create3Address_deterministic(bytes32 salt) public pure {
        assert(_create3(salt) == _create3(salt));
    }

    // =========================================================================
    // Property: _chainIdToRouteSuffix is injective over supported chains
    // =========================================================================
    // The suffix becomes the artifact KEY for a per-route CCIP deployer (`JBCCIPSuckerDeployer__<suffix>`).
    // If two distinct remote chains produced the same suffix, one route's artifact would silently
    // overwrite the other's during serialization, creating a verification gap. Distinct supported chains
    // must therefore produce distinct, non-empty suffixes.
    function test_routeSuffix_injectiveAndNonEmptyOverSupported() public view {
        for (uint256 i; i < SUPPORTED_CHAINS.length; i++) {
            bytes memory si = bytes(h.chainIdToRouteSuffix(SUPPORTED_CHAINS[i]));
            assertGt(si.length, 0, "suffix must be non-empty for supported chain");
            for (uint256 j = i + 1; j < SUPPORTED_CHAINS.length; j++) {
                assertTrue(
                    keccak256(si) != keccak256(bytes(h.chainIdToRouteSuffix(SUPPORTED_CHAINS[j]))),
                    "distinct supported chains must have distinct route suffixes"
                );
            }
        }
    }
}
