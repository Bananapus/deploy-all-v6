// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";

/// @notice CT residual closure — assert resolver custody, metadata, and tier-count manifest
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
}

contract MockBannyHookStore {
    mapping(address => uint256) internal _maxTierId;

    function setMaxTierId(address hook, uint256 max_) external {
        _maxTierId[hook] = max_;
    }

    function maxTierIdOf(address hook) external view returns (uint256) {
        return _maxTierId[hook];
    }
}
