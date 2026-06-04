// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBRemoteToken} from "@bananapus/suckers-v6/src/structs/JBRemoteToken.sol";
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {JBSuckersPair} from "@bananapus/suckers-v6/src/structs/JBSuckersPair.sol";

contract SuckerManifestVerifierGapTest is Test {
    function test_suckerManifestVerifierRejectsMalformedPairsAndManifestDrift() public {
        _suckerManifestVerifierRejectsMalformedPairWithNoLocalSucker();
        _suckerManifestVerifierRejectsPairWithDisabledNativeTokenMapping();
        // M2-1: a correct USDC-only ART(6) pair must PASS the manifest checks (the inverse case).
        // Kept as an internal subcase (not a separate `test_`) because forge runs test functions in
        // parallel threads that share the OS process env; `vm.setEnv("VERIFY_SUCKER_PAIRS_*")` would
        // otherwise race a sibling test. Running it sequentially inside one test function avoids that.
        _suckerManifestAcceptsUsdcOnlyArtPair();
        _suckerManifestVerifierRejectsWrongPeerInExactManifest();
        _suckerManifestVerifierRejectsWrongRemoteChainIdInExactManifest();
    }

    function _suckerManifestVerifierRejectsMalformedPairWithNoLocalSucker() internal {
        _clearSuckerManifestEnv();

        MockSuckerRegistry registry = new MockSuckerRegistry();
        registry.setPairs(
            1,
            _singlePair({
                local: address(0), remote: bytes32(uint256(uint160(makeAddr("wrong remote sucker")))), remoteChainId: 0
            })
        );

        VerifySuckerManifestHarness harness = new VerifySuckerManifestHarness();
        harness.setSuckerRegistry(address(registry));

        vm.setEnv("VERIFY_SUCKER_PAIRS_1", "1");

        // Coverage: Category 19 now asserts the local sucker has code. The mock pair sets local to
        // address(0), so the verifier rejects.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "NANA(1) sucker pair 0 local sucker has code"
            )
        );
        harness.verifySuckerManifest();
    }

    function _suckerManifestVerifierRejectsPairWithDisabledNativeTokenMapping() internal {
        _clearSuckerManifestEnv();

        MockSucker local = new MockSucker({
            peer_: bytes32(uint256(uint160(makeAddr("remote sucker")))),
            peerChainId_: 10,
            remoteToken_: JBRemoteToken({
                enabled: false,
                emergencyHatch: false,
                minGas: 0,
                addr: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
            })
        });

        MockSuckerRegistry registry = new MockSuckerRegistry();
        registry.setPairs(1, _singlePair({local: address(local), remote: local.peer(), remoteChainId: 10}));

        VerifySuckerManifestHarness harness = new VerifySuckerManifestHarness();
        harness.setSuckerRegistry(address(registry));

        vm.setEnv("VERIFY_SUCKER_PAIRS_1", "1");

        JBRemoteToken memory remoteToken = local.remoteTokenFor(JBConstants.NATIVE_TOKEN);
        assertFalse(remoteToken.enabled, "native-token mapping is disabled");

        // Coverage: Category 19 reads remoteTokenFor(<accounting token>).enabled and rejects when
        // the mapping is disabled. NANA(1) bridges the native token, so the resolved accounting
        // token is the native sentinel.
        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "NANA(1) sucker pair 0 accounting-token remote mapping is enabled"
            )
        );
        harness.verifySuckerManifest();
    }

    /// @dev Coverage for MAY2.md M2-1 (the inverse of MAY.md H-1): ART(6) bridges USDC, not the native
    /// token, so the manifest mapping checks must resolve the project's USDC accounting token. Pre-fix,
    /// the loop hard-coded `remoteTokenFor(NATIVE_TOKEN)` and would flag a correct USDC-only ART pair
    /// (which has NO native mapping) as a critical failure. This asserts the post-fix behavior: an ART(6)
    /// pair whose sucker maps USDC (enabled) but has NO native mapping
    /// passes the verifier. Runs on Ethereum Sepolia so `_usdcTokenFor` resolves a non-zero USDC
    /// address and the chain is non-production (no mandatory per-project env).
    function _suckerManifestAcceptsUsdcOnlyArtPair() internal {
        _clearSuckerManifestEnv();
        vm.chainId(11_155_111);

        // Sepolia USDC — mirrors Deploy/Verify `_usdcTokenFor(11155111)`.
        address sepoliaUsdc = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

        // Sucker maps USDC (enabled) and returns a disabled/empty mapping for any other token
        // (notably the native sentinel) — exactly the shape of a correct USDC-only ART sucker.
        MockTokenAwareSucker local = new MockTokenAwareSucker({
            peer_: bytes32(uint256(uint160(makeAddr("remote art sucker")))),
            peerChainId_: 1,
            enabledToken_: sepoliaUsdc,
            enabledRemoteToken_: JBRemoteToken({
                enabled: true,
                emergencyHatch: false,
                minGas: 200_000,
                addr: bytes32(uint256(uint160(makeAddr("remote usdc"))))
            })
        });

        MockSuckerRegistry registry = new MockSuckerRegistry();
        registry.setPairs(6, _singlePair({local: address(local), remote: local.peer(), remoteChainId: 1}));

        VerifySuckerManifestHarness harness = new VerifySuckerManifestHarness();
        harness.setSuckerRegistry(address(registry));
        // The canonical set only includes ART(6) when `projects.count() >= 6`. Wire a mock so the
        // verifier's `_canonicalRevnetProjectIdsAndLabels` actually iterates project 6.
        harness.setProjects(address(new MockProjects(6)));

        // Sanity: a native-token lookup is disabled, but the USDC lookup is enabled — so the only way
        // the verifier passes is by resolving the USDC accounting token (the M2-1 fix).
        assertFalse(local.remoteTokenFor(JBConstants.NATIVE_TOKEN).enabled, "native mapping must be absent");
        assertTrue(local.remoteTokenFor(sepoliaUsdc).enabled, "USDC mapping must be present");

        // Forge env vars persist across subtests, so set EVERY canonical project's expected pair
        // count explicitly: 0 for the baseline four (the mock registry returns no pairs for them) and
        // 1 for ART(6) (the USDC pair). This isolates the assertion to the ART mapping check.
        vm.setEnv("VERIFY_SUCKER_PAIRS_1", "0");
        vm.setEnv("VERIFY_SUCKER_PAIRS_2", "0");
        vm.setEnv("VERIFY_SUCKER_PAIRS_3", "0");
        vm.setEnv("VERIFY_SUCKER_PAIRS_4", "0");
        vm.setEnv("VERIFY_SUCKER_PAIRS_5", "0");
        vm.setEnv("VERIFY_SUCKER_PAIRS_6", "1");

        // Must NOT revert. Pre-fix this reverted with
        // "ART(6) sucker pair 0 accounting-token remote mapping is enabled".
        harness.verifySuckerManifest();

        // Restore env so this test cannot leak `VERIFY_SUCKER_PAIRS_*` into sibling tests (forge
        // `setEnv` persists process-wide across test functions in undefined order).
        _clearSuckerManifestEnv();
    }

    /// @dev Coverage: when the operator declares the exact per-pair manifest via
    /// `VERIFY_SUCKER_PAIR_<projectId>_<idx>`, the verifier asserts each field matches. A wrong
    /// peer bytes32 must trip the new check. Uses project ID 2 to keep the env var key
    /// disjoint from the sequential subcase below.
    function _suckerManifestVerifierRejectsWrongPeerInExactManifest() internal {
        _clearSuckerManifestEnv();

        bytes32 actualPeer = bytes32(uint256(uint160(makeAddr("actual remote sucker"))));
        bytes32 expectedPeerInManifest = bytes32(uint256(uint160(makeAddr("expected canonical remote"))));
        assertNotEq(actualPeer, expectedPeerInManifest, "test must use a peer different from the manifest");

        MockSucker local = new MockSucker({
            peer_: actualPeer,
            peerChainId_: 10,
            remoteToken_: JBRemoteToken({
                enabled: true,
                emergencyHatch: false,
                minGas: 0,
                addr: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
            })
        });

        MockSuckerRegistry registry = new MockSuckerRegistry();
        registry.setPairs(2, _singlePair({local: address(local), remote: actualPeer, remoteChainId: 10}));

        VerifySuckerManifestHarness harness = new VerifySuckerManifestHarness();
        harness.setSuckerRegistry(address(registry));

        // Sibling tests in this contract also set `VERIFY_SUCKER_PAIRS_1`. The verifier loops
        // through all four canonical projects, so leftover env from a sibling would trip the
        // count check for project 1 first. Clear it explicitly to keep this test focused on
        // project 2 only.
        vm.setEnv("VERIFY_SUCKER_PAIRS_1", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_3", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_4", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_2", "1");
        // Manifest format: <peer>:<remoteChainId>:<remoteNativeToken>:<emergencyHatch>
        vm.setEnv(
            "VERIFY_SUCKER_PAIR_2_0",
            string.concat(
                vm.toString(expectedPeerInManifest),
                ":10:",
                vm.toString(bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))),
                ":0"
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "CPN(2) sucker pair 0 peer() == expected"
            )
        );
        harness.verifySuckerManifest();
    }

    /// @dev Coverage: a wrong remote-chain-id in the manifest must trip the registry-
    /// side remoteChainId check first. Uses project ID 3 to avoid env collision with sibling tests.
    function _suckerManifestVerifierRejectsWrongRemoteChainIdInExactManifest() internal {
        _clearSuckerManifestEnv();

        bytes32 peer = bytes32(uint256(uint160(makeAddr("remote sucker"))));

        MockSucker local = new MockSucker({
            peer_: peer,
            peerChainId_: 10, // local says 10
            remoteToken_: JBRemoteToken({
                enabled: true,
                emergencyHatch: false,
                minGas: 0,
                addr: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
            })
        });

        MockSuckerRegistry registry = new MockSuckerRegistry();
        registry.setPairs(3, _singlePair({local: address(local), remote: peer, remoteChainId: 10}));

        VerifySuckerManifestHarness harness = new VerifySuckerManifestHarness();
        harness.setSuckerRegistry(address(registry));

        vm.setEnv("VERIFY_SUCKER_PAIRS_1", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_2", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_4", "");
        vm.setEnv("VERIFY_SUCKER_PAIRS_3", "1");
        // Operator-declared remoteChainId = 8453 (Base) — disagrees with the pair's actual 10 (OP).
        vm.setEnv(
            "VERIFY_SUCKER_PAIR_3_0",
            string.concat(
                vm.toString(peer), ":8453:", vm.toString(bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))), ":0"
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "REV(3) sucker pair 0 registry-side remoteChainId == expected"
            )
        );
        harness.verifySuckerManifest();
    }

    /// @dev Source-level tripwire for MAY2.md M2-1: BOTH sucker-manifest mapping lookups (the
    /// main-loop enabled check in `_verifySuckerManifest` and the per-pair addr/emergencyHatch twin
    /// in `_checkSuckerPairAgainstManifest`) must resolve the project's bridged token via
    /// `_expectedTerminalTokenFor`, and neither may hard-code a native-token lookup — otherwise the
    /// USDC-only ART(6) pairs spuriously fail a correct deployment.
    function test_suckerManifestSourceUsesPerProjectBridgedToken() public view {
        string memory src = vm.readFile("script/Verify.s.sol");
        assertTrue(
            vm.contains(src, "remoteTokenFor(address)\", expectedLocalToken"),
            "sucker-manifest mapping checks must look up remoteTokenFor(expectedLocalToken) per project"
        );
        assertFalse(
            vm.contains(src, "remoteTokenFor(address)\", JBConstants.NATIVE_TOKEN"),
            "sucker-manifest checks must not hard-code remoteTokenFor(NATIVE_TOKEN) (breaks USDC ART)"
        );
    }

    function _clearSuckerManifestEnv() internal {
        for (uint256 projectId = 1; projectId <= 7; projectId++) {
            vm.setEnv(string.concat("VERIFY_SUCKER_PAIRS_", vm.toString(projectId)), "");
            vm.setEnv(string.concat("VERIFY_SUCKER_PAIR_", vm.toString(projectId), "_0"), "");
        }
    }

    function _singlePair(
        address local,
        bytes32 remote,
        uint256 remoteChainId
    )
        internal
        pure
        returns (JBSuckersPair[] memory pairs)
    {
        pairs = new JBSuckersPair[](1);
        pairs[0] = JBSuckersPair({local: local, remote: remote, remoteChainId: remoteChainId});
    }
}

contract VerifySuckerManifestHarness is Verify {
    function setSuckerRegistry(address suckerRegistry_) external {
        suckerRegistry = JBSuckerRegistry(suckerRegistry_);
    }

    function setProjects(address projects_) external {
        projects = JBProjects(projects_);
    }

    function verifySuckerManifest() external {
        _verifySuckerManifest();
    }
}

contract MockSuckerRegistry {
    mapping(uint256 projectId => JBSuckersPair[] pairs) internal _pairsOf;

    function setPairs(uint256 projectId, JBSuckersPair[] memory pairs) external {
        delete _pairsOf[projectId];
        for (uint256 i; i < pairs.length; i++) {
            _pairsOf[projectId].push(pairs[i]);
        }
    }

    function suckerPairsOf(uint256 projectId) external view returns (JBSuckersPair[] memory) {
        return _pairsOf[projectId];
    }
}

contract MockSucker {
    bytes32 internal immutable _peer;
    uint256 internal immutable _peerChainId;
    JBRemoteToken internal _remoteToken;

    constructor(bytes32 peer_, uint256 peerChainId_, JBRemoteToken memory remoteToken_) {
        _peer = peer_;
        _peerChainId = peerChainId_;
        _remoteToken = remoteToken_;
    }

    function peer() external view returns (bytes32) {
        return _peer;
    }

    function peerChainId() external view returns (uint256) {
        return _peerChainId;
    }

    function remoteTokenFor(address) external view returns (JBRemoteToken memory) {
        return _remoteToken;
    }
}

/// @dev A sucker mock that returns its configured (enabled) mapping ONLY for one token, and an
/// empty/disabled mapping for every other token. Used to prove the manifest verifier resolves the
/// correct per-project accounting token (USDC for ART) rather than a hard-coded native lookup.
contract MockTokenAwareSucker {
    bytes32 internal immutable _peer;
    uint256 internal immutable _peerChainId;
    address internal immutable _enabledToken;
    JBRemoteToken internal _enabledRemoteToken;

    constructor(bytes32 peer_, uint256 peerChainId_, address enabledToken_, JBRemoteToken memory enabledRemoteToken_) {
        _peer = peer_;
        _peerChainId = peerChainId_;
        _enabledToken = enabledToken_;
        _enabledRemoteToken = enabledRemoteToken_;
    }

    function peer() external view returns (bytes32) {
        return _peer;
    }

    function peerChainId() external view returns (uint256) {
        return _peerChainId;
    }

    function remoteTokenFor(address token) external view returns (JBRemoteToken memory) {
        if (token == _enabledToken) return _enabledRemoteToken;
        return JBRemoteToken({enabled: false, emergencyHatch: false, minGas: 0, addr: bytes32(0)});
    }
}

/// @dev Minimal JBProjects stand-in exposing only `count()`, so the verifier's canonical-set
/// builder includes the higher project IDs (DEFIFA(5)/ART(6)/MARKEE(7)) under test.
contract MockProjects {
    uint256 internal immutable _count;

    constructor(uint256 count_) {
        _count = count_;
    }

    function count() external view returns (uint256) {
        return _count;
    }
}
