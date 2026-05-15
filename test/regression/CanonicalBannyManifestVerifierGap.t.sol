// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JB721Tier} from "@bananapus/721-hook-v6/src/structs/JB721Tier.sol";
import {JB721TierFlags} from "@bananapus/721-hook-v6/src/structs/JB721TierFlags.sol";

/// @notice Coverage — assert resolver custody, metadata, and tier-count manifest
/// match the canonical Banny launch. Without these, a code-bearing resolver with nonempty
/// `contractURI` still passes the prior verifier even if `owner`, `trustedForwarder`,
/// `svgDescription` / `svgExternalUrl` / `svgBaseUri`, or the 68-tier Drop 1/Drop 2 manifest
/// are wrong.
contract CanonicalBannyManifestVerifierGapTest is Test {
    address internal constant CANONICAL_BAN_OPS = 0x9E2a10aB3BD22831f19d02C648Bc2Cb49B127450;
    string internal constant CANONICAL_DESCRIPTION = "A piece of Banny Retail.";
    string internal constant CANONICAL_EXTERNAL_URL = "https://retail.banny.eth.shop";
    string internal constant CANONICAL_BASE_URI = "https://bannyverse.infura-ipfs.io/ipfs/";
    uint256 internal constant CANONICAL_TIER_COUNT = 68;

    function setUp() public {
        // forge runs sibling tests in this contract concurrently and `vm.setEnv` is process-wide,
        // so explicitly clear every Banny env var this suite reads. Without this, the per-tier
        // manifest hash and tier-count env values leak between tests and trip earlier verifier
        // gates before each test reaches the assertion it targets.
        vm.setEnv("VERIFY_BAN_OPS_OPERATOR", "");
        vm.setEnv("VERIFY_BANNY_SVG_DESCRIPTION", "");
        vm.setEnv("VERIFY_BANNY_SVG_EXTERNAL_URL", "");
        vm.setEnv("VERIFY_BANNY_SVG_BASE_URI", "");
        vm.setEnv("VERIFY_BANNY_TIER_COUNT", "");
        vm.setEnv("VERIFY_BANNY_TIER_MANIFEST_HASH", "");
    }

    function test_bannyManifestVerifierRejectsWrongResolverOwner() public {
        vm.chainId(1);

        address forwarder = makeAddr("trusted forwarder");
        address wrongOwner = makeAddr("attacker");
        assertTrue(wrongOwner != CANONICAL_BAN_OPS, "test must use a noncanonical owner");

        MockBannyResolver resolver = new MockBannyResolver({
            owner_: wrongOwner,
            trustedForwarder_: forwarder,
            svgDescription_: CANONICAL_DESCRIPTION,
            svgExternalUrl_: CANONICAL_EXTERNAL_URL,
            svgBaseUri_: CANONICAL_BASE_URI
        });
        MockBannyHookStore store = new MockBannyHookStore();
        store.setMaxTierId(address(0xBA), CANONICAL_TIER_COUNT);

        VerifyBannyManifestHarness harness = new VerifyBannyManifestHarness();
        harness.setHookStore(address(store));
        harness.setExpectedTrustedForwarder(forwarder);

        vm.setEnv("VERIFY_BAN_OPS_OPERATOR", vm.toString(CANONICAL_BAN_OPS));
        vm.setEnv("VERIFY_BANNY_SVG_DESCRIPTION", CANONICAL_DESCRIPTION);
        vm.setEnv("VERIFY_BANNY_SVG_EXTERNAL_URL", CANONICAL_EXTERNAL_URL);
        vm.setEnv("VERIFY_BANNY_SVG_BASE_URI", CANONICAL_BASE_URI);
        vm.setEnv("VERIFY_BANNY_TIER_COUNT", vm.toString(CANONICAL_TIER_COUNT));

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "Banny resolver owner == VERIFY_BAN_OPS_OPERATOR"
            )
        );
        harness.verifyBannyResolverManifest(address(resolver), address(0xBA));
    }

    function test_bannyManifestVerifierRejectsWrongSvgBaseUri() public {
        vm.chainId(1);

        address forwarder = makeAddr("trusted forwarder");
        string memory wrongBaseUri = "https://attacker.example/ipfs/";

        MockBannyResolver resolver = new MockBannyResolver({
            owner_: CANONICAL_BAN_OPS,
            trustedForwarder_: forwarder,
            svgDescription_: CANONICAL_DESCRIPTION,
            svgExternalUrl_: CANONICAL_EXTERNAL_URL,
            svgBaseUri_: wrongBaseUri
        });
        MockBannyHookStore store = new MockBannyHookStore();
        store.setMaxTierId(address(0xBA), CANONICAL_TIER_COUNT);

        VerifyBannyManifestHarness harness = new VerifyBannyManifestHarness();
        harness.setHookStore(address(store));
        harness.setExpectedTrustedForwarder(forwarder);

        vm.setEnv("VERIFY_BAN_OPS_OPERATOR", vm.toString(CANONICAL_BAN_OPS));
        vm.setEnv("VERIFY_BANNY_SVG_DESCRIPTION", CANONICAL_DESCRIPTION);
        vm.setEnv("VERIFY_BANNY_SVG_EXTERNAL_URL", CANONICAL_EXTERNAL_URL);
        vm.setEnv("VERIFY_BANNY_SVG_BASE_URI", CANONICAL_BASE_URI);
        vm.setEnv("VERIFY_BANNY_TIER_COUNT", vm.toString(CANONICAL_TIER_COUNT));

        vm.expectRevert(
            abi.encodeWithSelector(Verify.Verify_CriticalCheckFailed.selector, "Banny resolver svgBaseUri == expected")
        );
        harness.verifyBannyResolverManifest(address(resolver), address(0xBA));
    }

    function test_bannyManifestVerifierRejectsWrongTierCount() public {
        vm.chainId(1);

        address forwarder = makeAddr("trusted forwarder");

        MockBannyResolver resolver = new MockBannyResolver({
            owner_: CANONICAL_BAN_OPS,
            trustedForwarder_: forwarder,
            svgDescription_: CANONICAL_DESCRIPTION,
            svgExternalUrl_: CANONICAL_EXTERNAL_URL,
            svgBaseUri_: CANONICAL_BASE_URI
        });
        MockBannyHookStore store = new MockBannyHookStore();
        // Only 4 baseline tiers — Drop 1 / Drop 2 registration was missing.
        store.setMaxTierId(address(0xBA), 4);

        VerifyBannyManifestHarness harness = new VerifyBannyManifestHarness();
        harness.setHookStore(address(store));
        harness.setExpectedTrustedForwarder(forwarder);

        vm.setEnv("VERIFY_BAN_OPS_OPERATOR", vm.toString(CANONICAL_BAN_OPS));
        vm.setEnv("VERIFY_BANNY_SVG_DESCRIPTION", CANONICAL_DESCRIPTION);
        vm.setEnv("VERIFY_BANNY_SVG_EXTERNAL_URL", CANONICAL_EXTERNAL_URL);
        vm.setEnv("VERIFY_BANNY_SVG_BASE_URI", CANONICAL_BASE_URI);
        vm.setEnv("VERIFY_BANNY_TIER_COUNT", vm.toString(CANONICAL_TIER_COUNT));

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector, "Banny hook maxTierIdOf == VERIFY_BANNY_TIER_COUNT"
            )
        );
        harness.verifyBannyResolverManifest(address(resolver), address(0xBA));
    }

    function test_bannyManifestVerifierRejectsWrongPerTierManifest() public {
        vm.chainId(1);

        address forwarder = makeAddr("trusted forwarder");
        address bannyHook = address(0xBA);

        MockBannyResolver resolver = new MockBannyResolver({
            owner_: CANONICAL_BAN_OPS,
            trustedForwarder_: forwarder,
            svgDescription_: CANONICAL_DESCRIPTION,
            svgExternalUrl_: CANONICAL_EXTERNAL_URL,
            svgBaseUri_: CANONICAL_BASE_URI
        });
        MockBannyHookStore store = new MockBannyHookStore();

        // Reduce the canonical surface to a single tier so the test can model the canonical
        // manifest hash explicitly. The verifier walks `1..maxTierIdOf` — set both to 1 here.
        uint256 tierCount = 1;
        store.setMaxTierId(bannyHook, tierCount);

        JB721Tier memory canonicalTier = _stubCanonicalTier(1);
        store.setTier(bannyHook, 1, canonicalTier);

        bytes32 canonicalSvgHash = keccak256(bytes("canonical-svg-hash-tier-1"));
        string memory canonicalProductName = "Background Original";
        resolver.setSvgHash(1, canonicalSvgHash);
        resolver.setProductName(1, canonicalProductName);

        bytes32 expectedManifestHash =
            _expectedDigest({tier: canonicalTier, svgHash: canonicalSvgHash, productName: canonicalProductName});

        // Sanity: with the canonical manifest committed, the verifier passes the per-tier check.
        VerifyBannyManifestHarness happyHarness = new VerifyBannyManifestHarness();
        happyHarness.setHookStore(address(store));
        happyHarness.setExpectedTrustedForwarder(forwarder);
        _writeCanonicalEnv(tierCount);
        vm.setEnv("VERIFY_BANNY_TIER_MANIFEST_HASH", vm.toString(expectedManifestHash));
        happyHarness.verifyBannyResolverManifest(address(resolver), bannyHook);

        // Now flip the resolver's SVG hash for tier 1. Every other field is canonical, but the
        // per-tier digest no longer matches `VERIFY_BANNY_TIER_MANIFEST_HASH` — the new gate
        // rejects with the per-tier label, which the older verifier never surfaced.
        resolver.setSvgHash(1, keccak256(bytes("forked-svg-hash")));

        VerifyBannyManifestHarness divergentHarness = new VerifyBannyManifestHarness();
        divergentHarness.setHookStore(address(store));
        divergentHarness.setExpectedTrustedForwarder(forwarder);

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "Banny per-tier manifest hash == VERIFY_BANNY_TIER_MANIFEST_HASH"
            )
        );
        divergentHarness.verifyBannyResolverManifest(address(resolver), bannyHook);
    }

    function test_bannyManifestVerifierFailsClosedWhenPerTierEnvUnsetOnProduction() public {
        vm.chainId(1);

        address forwarder = makeAddr("trusted forwarder");
        address bannyHook = address(0xBA);

        MockBannyResolver resolver = new MockBannyResolver({
            owner_: CANONICAL_BAN_OPS,
            trustedForwarder_: forwarder,
            svgDescription_: CANONICAL_DESCRIPTION,
            svgExternalUrl_: CANONICAL_EXTERNAL_URL,
            svgBaseUri_: CANONICAL_BASE_URI
        });
        MockBannyHookStore store = new MockBannyHookStore();
        store.setMaxTierId(bannyHook, CANONICAL_TIER_COUNT);

        VerifyBannyManifestHarness harness = new VerifyBannyManifestHarness();
        harness.setHookStore(address(store));
        harness.setExpectedTrustedForwarder(forwarder);

        _writeCanonicalEnv(CANONICAL_TIER_COUNT);
        // Explicit clear in case a sibling test leaked the value via forge's process env.
        vm.setEnv("VERIFY_BANNY_TIER_MANIFEST_HASH", "");

        vm.expectRevert(
            abi.encodeWithSelector(
                Verify.Verify_CriticalCheckFailed.selector,
                "VERIFY_BANNY_TIER_MANIFEST_HASH MUST be set on production for per-tier identity"
            )
        );
        harness.verifyBannyResolverManifest(address(resolver), bannyHook);
    }

    /// @notice Shared canonical-env setup mirroring the production-chain expectation. Each test
    /// targeting an earlier verifier check still produces a canonical view here so the test only
    /// trips the specific assertion it targets.
    function _writeCanonicalEnv(uint256 tierCount) internal {
        vm.setEnv("VERIFY_BAN_OPS_OPERATOR", vm.toString(CANONICAL_BAN_OPS));
        vm.setEnv("VERIFY_BANNY_SVG_DESCRIPTION", CANONICAL_DESCRIPTION);
        vm.setEnv("VERIFY_BANNY_SVG_EXTERNAL_URL", CANONICAL_EXTERNAL_URL);
        vm.setEnv("VERIFY_BANNY_SVG_BASE_URI", CANONICAL_BASE_URI);
        vm.setEnv("VERIFY_BANNY_TIER_COUNT", vm.toString(tierCount));
    }

    /// @notice Build a `JB721Tier` whose committed fields exercise every field the verifier hashes
    /// (price, initialSupply, category, reserveFrequency, encodedIPFSUri). Fields outside the
    /// digest (votingUnits, reserveBeneficiary, splitPercent, discountPercent, flags, etc.) are
    /// left at default — they don't influence the digest and a real deployment doesn't pin them.
    function _stubCanonicalTier(uint256 id) internal pure returns (JB721Tier memory tier) {
        tier.id = uint32(id);
        tier.price = 1e16; // 0.01 ETH
        tier.remainingSupply = 100;
        tier.initialSupply = 100;
        tier.category = 1;
        tier.reserveFrequency = 0;
        tier.encodedIPFSUri = bytes32(uint256(0xCAFE));
    }

    /// @notice Compute the expected per-tier digest exactly the way the verifier accumulates it,
    /// so the test owns one canonical hash that can be flipped per-field to surface regressions
    /// without re-hashing across multiple call sites.
    function _expectedDigest(
        JB721Tier memory tier,
        bytes32 svgHash,
        string memory productName
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                bytes32(0),
                uint256(tier.id),
                uint256(tier.price),
                uint256(tier.initialSupply),
                uint256(tier.category),
                uint256(tier.reserveFrequency),
                tier.encodedIPFSUri,
                svgHash,
                keccak256(bytes(productName))
            )
        );
    }
}

contract VerifyBannyManifestHarness is Verify {
    function setHookStore(address store_) external {
        hookStore = JB721TiersHookStore(store_);
    }

    function setExpectedTrustedForwarder(address forwarder) external {
        expectedTrustedForwarder = forwarder;
    }

    function verifyBannyResolverManifest(address resolver, address bannyHook) external {
        _verifyBannyResolverManifest(resolver, bannyHook);
    }
}

contract MockBannyResolver {
    address internal _owner;
    address internal _trustedForwarder;
    string internal _svgDescription;
    string internal _svgExternalUrl;
    string internal _svgBaseUri;
    mapping(uint256 upc => bytes32) internal _svgHashOf;
    mapping(uint256 upc => string) internal _productNameOf;

    constructor(
        address owner_,
        address trustedForwarder_,
        string memory svgDescription_,
        string memory svgExternalUrl_,
        string memory svgBaseUri_
    ) {
        _owner = owner_;
        _trustedForwarder = trustedForwarder_;
        _svgDescription = svgDescription_;
        _svgExternalUrl = svgExternalUrl_;
        _svgBaseUri = svgBaseUri_;
    }

    function setSvgHash(uint256 upc, bytes32 hash) external {
        _svgHashOf[upc] = hash;
    }

    function setProductName(uint256 upc, string memory name) external {
        _productNameOf[upc] = name;
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function trustedForwarder() external view returns (address) {
        return _trustedForwarder;
    }

    function svgDescription() external view returns (string memory) {
        return _svgDescription;
    }

    function svgExternalUrl() external view returns (string memory) {
        return _svgExternalUrl;
    }

    function svgBaseUri() external view returns (string memory) {
        return _svgBaseUri;
    }

    function svgHashOf(uint256 upc) external view returns (bytes32) {
        return _svgHashOf[upc];
    }

    function productNameOf(uint256 upc) external view returns (string memory) {
        return _productNameOf[upc];
    }
}

contract MockBannyHookStore {
    mapping(address => uint256) internal _maxTierId;
    mapping(address hook => mapping(uint256 id => JB721Tier)) internal _tierOf;

    function setMaxTierId(address hook, uint256 max_) external {
        _maxTierId[hook] = max_;
    }

    function setTier(address hook, uint256 id, JB721Tier memory tier) external {
        _tierOf[hook][id] = tier;
    }

    function maxTierIdOf(address hook) external view returns (uint256) {
        return _maxTierId[hook];
    }

    function tierOf(address hook, uint256 id, bool) external view returns (JB721Tier memory) {
        return _tierOf[hook][id];
    }
}
