// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Deploy} from "../../script/Deploy.s.sol";
import {Verify} from "../../script/Verify.s.sol";

import {CCIPHelper} from "@bananapus/suckers-v6/src/libraries/CCIPHelper.sol";

/// @title VerifyHelperProperties
/// @notice Formal verification of the pure helpers in `Verify.s.sol`, including cross-checks that the
///         verifier's hard-coded expectation tables agree with the canonical values the deployer uses.
/// @dev `Verify.s.sol` is "a deployment check, not a full runtime review" (README). Its correctness
///      depends on its hard-coded expectation tables (CCIP chain selectors, USDC token addresses,
///      currency-id derivation, bounded truncation) matching what `Deploy.s.sol` actually deploys. If the
///      verifier expects a different constant than the deployer wrote, it either passes a wrong deployment
///      or fails a correct one. These harnesses subclass the REAL `Verify`/`Deploy` scripts and prove the
///      tables agree.
contract VerifyHelperHarness is Verify {
    function currencyIdOf(address token) external pure returns (uint32) {
        return _currencyIdOf(token);
    }

    function projectId64(uint256 projectId) external pure returns (uint64) {
        return _projectId64(projectId);
    }

    function usdcTokenFor(uint256 chainId) external pure returns (address) {
        return _usdcTokenFor(chainId);
    }

    function expectedCcipSelectorFor(uint256 remoteChainId) external pure returns (uint64) {
        return _expectedCcipSelectorFor(remoteChainId);
    }
}

contract DeployCurrencyHarness is Deploy {
    function currencyIdOf(address token) external pure returns (uint32) {
        return _currencyIdOf(token);
    }
}

contract VerifyHelperProperties is Test {
    VerifyHelperHarness internal vh;
    DeployCurrencyHarness internal dh;

    // The supported chain ids the deployment targets (mainnets + sepolia testnets).
    uint256[8] internal SUPPORTED_CHAINS = [uint256(1), 11_155_111, 10, 11_155_420, 8453, 84_532, 42_161, 421_614];

    function setUp() public {
        vh = new VerifyHelperHarness();
        dh = new DeployCurrencyHarness();
    }

    // Internal pure replica of Deploy.s.sol's `_currencyIdOf` body. Used by `check_*` because a `Deploy`
    // (Sphinx) subclass cannot be deployed inside a Halmos symbolic run; the fuzz layer below pins both
    // shipped implementations (Deploy harness `dh`, Verify harness `vh`) to each other and to this replica.
    function _deployCurrencyId(address token) internal pure returns (uint32) {
        return uint32(uint160(token));
    }

    // =========================================================================
    // Property: Deploy and Verify derive currency ids IDENTICALLY
    // =========================================================================
    // Both scripts independently define `_currencyIdOf`. If they diverged, Verify would assert against a
    // currency id the deployment never wrote. They must be byte-for-byte equal for every token.
    //
    // Halmos: prove Verify's shipped `_currencyIdOf` equals the Deploy currency-id algorithm (replica).
    // forge-lint: disable-next-line(mixed-case-function)
    function check_currencyId_deployVerifyAgree(address token) public view {
        assert(vh.currencyIdOf(token) == _deployCurrencyId(token));
    }

    // Fuzz: prove the TWO shipped implementations (Verify's and Deploy's) agree directly, and that the
    // replica used by Halmos matches the shipped Deploy implementation.
    function testFuzz_currencyId_deployVerifyAgree(address token) public view {
        assertEq(
            uint256(vh.currencyIdOf(token)),
            uint256(dh.currencyIdOf(token)),
            "Deploy._currencyIdOf and Verify._currencyIdOf must agree"
        );
        assertEq(
            uint256(_deployCurrencyId(token)),
            uint256(dh.currencyIdOf(token)),
            "Halmos replica must match shipped Deploy._currencyIdOf"
        );
    }

    // =========================================================================
    // Property: Verify._currencyIdOf isolates the low 32 bits
    // =========================================================================
    // forge-lint: disable-next-line(mixed-case-function)
    function check_currencyId_isLow32Bits(address token) public view {
        uint32 id = vh.currencyIdOf(token);
        assert(uint256(id) == uint256(uint160(token)) % (1 << 32));
    }

    function testFuzz_currencyId_isLow32Bits(address token) public view {
        assertEq(uint256(vh.currencyIdOf(token)), uint256(uint160(token)) % (1 << 32), "low 32 bits");
    }

    // =========================================================================
    // Property: _projectId64 round-trips below bound and reverts above
    // =========================================================================
    // forge-lint: disable-next-line(mixed-case-function)
    function check_projectId64_roundTrip(uint256 id) public view {
        vm.assume(id <= type(uint64).max);
        assert(uint256(vh.projectId64(id)) == id);
    }

    function testFuzz_projectId64_roundTrip(uint256 id) public view {
        id = bound(id, 0, type(uint64).max);
        assertEq(uint256(vh.projectId64(id)), id, "projectId64 lossless within uint64");
    }

    function testFuzz_projectId64_revertsAboveBound(uint256 id) public {
        id = bound(id, uint256(type(uint64).max) + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Verify.Verify_ProjectIdOverflow.selector, id));
        vh.projectId64(id);
    }

    // =========================================================================
    // Property (CROSS-CHECK): Verify CCIP selector table == canonical CCIPHelper
    // =========================================================================
    // Deploy passes `CCIPHelper.selectorOfChain(remoteChainId)` as the real CCIP chain selector when
    // wiring suckers. Verify independently HARD-CODES `_expectedCcipSelectorFor`. For the verifier to be
    // meaningful, its table must equal the canonical library value for every supported chain. A mismatch
    // = the verifier checks the wrong selector.
    function testFuzz_ccipSelector_matchesCanonical(uint256 idx) public view {
        idx = bound(idx, 0, SUPPORTED_CHAINS.length - 1);
        uint256 chainId = SUPPORTED_CHAINS[idx];
        assertEq(
            uint256(vh.expectedCcipSelectorFor(chainId)),
            uint256(CCIPHelper.selectorOfChain(chainId)),
            "Verify CCIP selector table must match canonical CCIPHelper.selectorOfChain"
        );
    }

    // Enumerated (no fuzz) version so the cross-check is exhaustive over the supported set.
    function test_ccipSelector_matchesCanonical_allChains() public view {
        for (uint256 i; i < SUPPORTED_CHAINS.length; i++) {
            uint256 chainId = SUPPORTED_CHAINS[i];
            assertEq(
                uint256(vh.expectedCcipSelectorFor(chainId)),
                uint256(CCIPHelper.selectorOfChain(chainId)),
                "Verify CCIP selector must match canonical for every supported chain"
            );
        }
    }

    // =========================================================================
    // Property: _expectedCcipSelectorFor is injective over supported chains
    // =========================================================================
    // Distinct supported chains must map to distinct selectors; a collision would let a sucker accept a
    // bridge message addressed to the wrong chain.
    function test_ccipSelector_injectiveOverSupported() public view {
        for (uint256 i; i < SUPPORTED_CHAINS.length; i++) {
            for (uint256 j = i + 1; j < SUPPORTED_CHAINS.length; j++) {
                assertTrue(
                    vh.expectedCcipSelectorFor(SUPPORTED_CHAINS[i]) != vh.expectedCcipSelectorFor(SUPPORTED_CHAINS[j]),
                    "distinct supported chains must have distinct CCIP selectors"
                );
            }
        }
    }

    // =========================================================================
    // Property: _usdcTokenFor is defined and injective over supported chains
    // =========================================================================
    // Every supported chain must have a non-zero USDC token, and they must be distinct (no two chains
    // share a USDC address — the verifier keys per-chain USD accounting context on it).
    function test_usdcToken_definedAndInjectiveOverSupported() public view {
        for (uint256 i; i < SUPPORTED_CHAINS.length; i++) {
            assertTrue(vh.usdcTokenFor(SUPPORTED_CHAINS[i]) != address(0), "USDC must be defined for supported chain");
            for (uint256 j = i + 1; j < SUPPORTED_CHAINS.length; j++) {
                assertTrue(
                    vh.usdcTokenFor(SUPPORTED_CHAINS[i]) != vh.usdcTokenFor(SUPPORTED_CHAINS[j]),
                    "distinct supported chains must have distinct USDC tokens"
                );
            }
        }
    }
}
