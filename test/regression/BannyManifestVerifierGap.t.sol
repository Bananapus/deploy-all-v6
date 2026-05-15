// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Verify} from "../../script/Verify.s.sol";

import {JB721TiersHookStore} from "@bananapus/721-hook-v6/src/JB721TiersHookStore.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBTokens} from "@bananapus/core-v6/src/JBTokens.sol";
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";

contract BannyManifestVerifierGapTest is Test {
    function test_canonicalBannyVerifierIgnoresResolverOwnerMetadataAndDropManifest() public {
        // Clear the per-project config-hash env vars in case a sibling test leaked them via
        // forge's shared process environment.
        vm.setEnv("VERIFY_CONFIG_HASH_1", "");
        vm.setEnv("VERIFY_CONFIG_HASH_2", "");
        vm.setEnv("VERIFY_CONFIG_HASH_3", "");
        vm.setEnv("VERIFY_CONFIG_HASH_4", "");
        vm.setEnv("VERIFY_CONFIG_HASHES", "");

        MockRevDeployer revDeployer = new MockRevDeployer();
        MockProjects projects = new MockProjects(address(revDeployer));
        MockTokens tokens = new MockTokens();

        tokens.setTokenOf(1, address(new MockToken("NANA")));
        tokens.setTokenOf(2, address(new MockToken("CPN")));
        tokens.setTokenOf(3, address(new MockToken("REV")));
        tokens.setTokenOf(4, address(new MockToken("BAN")));

        address wrongOwner = makeAddr("wrong resolver owner");
        address wrongForwarder = makeAddr("wrong trusted forwarder");
        MockBannyResolver resolver = new MockBannyResolver({
            owner_: wrongOwner,
            trustedForwarder_: wrongForwarder,
            description_: "wrong description",
            externalUrl_: "https://wrong.example",
            baseUri_: "https://wrong.example/ipfs/"
        });
        MockHookStore hookStore = new MockHookStore({resolver_: address(resolver), maxTierId_: 4});
        MockBannyHook bannyHook =
            new MockBannyHook({hookStore_: address(hookStore), contractUri_: "wrong-contract-uri"});
        MockRevOwner revOwner = new MockRevOwner(address(bannyHook));
        // The verifier now requires the CPN hook to be wired with PROJECT_ID==2 /
        // STORE==hookStore / symbol=="CPN". This test targets Banny manifest behaviour, so satisfy
        // that gate with a minimal mock so we reach the Banny assertions.
        revOwner.setCpnHook(address(new MockCpnHookForCpn(address(hookStore))));

        assertEq(resolver.owner(), wrongOwner, "test uses wrong resolver owner");
        assertEq(resolver.trustedForwarder(), wrongForwarder, "test uses wrong forwarder");
        assertEq(hookStore.maxTierIdOf(address(bannyHook)), 4, "test leaves Drop 1 and Drop 2 tiers absent");
        assertEq(resolver.svgDescription(), "wrong description", "test uses wrong metadata");

        VerifyBannyManifestHarness harness = new VerifyBannyManifestHarness();
        harness.setMocks({
            projects_: address(projects),
            tokens_: address(tokens),
            revDeployer_: address(revDeployer),
            revOwner_: address(revOwner),
            hookStore_: address(hookStore)
        });

        // Categories 1 and 18 accept the BAN/Banny surface because the project
        // owner, token symbol, hook project id/store/symbol, resolver code, and
        // contractURI are plausible. They never authenticate resolver custody,
        // trusted-forwarder/metadata fields, or the 68-tier deployed drop
        // manifest that Deploy.s.sol registers before final ownership handoff.
        harness.verifyCanonicalBannySurfaces();
    }
}

contract VerifyBannyManifestHarness is Verify {
    function setMocks(
        address projects_,
        address tokens_,
        address revDeployer_,
        address revOwner_,
        address hookStore_
    )
        external
    {
        projects = JBProjects(projects_);
        tokens = JBTokens(tokens_);
        revDeployer = REVDeployer(revDeployer_);
        revOwner = REVOwner(revOwner_);
        hookStore = JB721TiersHookStore(hookStore_);
    }

    function verifyCanonicalBannySurfaces() external {
        _verifyCanonicalProjectIdentities();
        _verifyCanonicalProjectEconomics();
    }
}

contract MockProjects {
    address internal immutable _revDeployer;

    constructor(address revDeployer_) {
        _revDeployer = revDeployer_;
    }

    function ownerOf(uint256) external view returns (address) {
        return _revDeployer;
    }
}

contract MockTokens {
    mapping(uint256 projectId => address token) internal _tokenOf;

    function setTokenOf(uint256 projectId, address token) external {
        _tokenOf[projectId] = token;
    }

    function tokenOf(uint256 projectId) external view returns (address) {
        return _tokenOf[projectId];
    }
}

contract MockRevDeployer {
    function hashedEncodedConfigurationOf(uint256 projectId) external pure returns (bytes32) {
        return keccak256(abi.encodePacked("some-nonzero-config", projectId));
    }
}

contract MockRevOwner {
    address internal immutable _bannyHook;
    address internal _cpnHook;

    constructor(address bannyHook_) {
        _bannyHook = bannyHook_;
    }

    /// @notice The CPN hook is required by the verifier; tests that target Banny-only behaviour
    /// set a satisfying CPN mock through this so they don't trip the CPN gate.
    function setCpnHook(address cpnHook_) external {
        _cpnHook = cpnHook_;
    }

    function tiered721HookOf(uint256 projectId) external view returns (address) {
        if (projectId == 4) return _bannyHook;
        if (projectId == 2) return _cpnHook;
        return address(0);
    }
}

contract MockToken {
    string internal _symbol;

    constructor(string memory symbol_) {
        _symbol = symbol_;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }
}

contract MockHookStore {
    address internal immutable _resolver;
    uint256 internal immutable _maxTierId;

    constructor(address resolver_, uint256 maxTierId_) {
        _resolver = resolver_;
        _maxTierId = maxTierId_;
    }

    function tokenUriResolverOf(address) external view returns (address) {
        return _resolver;
    }

    function maxTierIdOf(address) external view returns (uint256) {
        return _maxTierId;
    }
}

contract MockBannyHook is MockToken {
    address internal immutable _hookStore;
    string internal _contractUri;

    constructor(address hookStore_, string memory contractUri_) MockToken("BANNY") {
        _hookStore = hookStore_;
        _contractUri = contractUri_;
    }

    function PROJECT_ID() external pure returns (uint256) {
        return 4;
    }

    function STORE() external view returns (address) {
        return _hookStore;
    }

    function contractURI() external view returns (string memory) {
        return _contractUri;
    }
}

/// @notice CPN hook mock matching the canonical-economics gate (PROJECT_ID == 2, canonical store,
/// "CPN" symbol). Used by sibling tests that target Banny manifest behaviour but need a CPN hook
/// in place to reach the Banny assertions.
contract MockCpnHookForCpn is MockToken {
    address internal immutable _hookStore;

    constructor(address hookStore_) MockToken("CPN") {
        _hookStore = hookStore_;
    }

    function PROJECT_ID() external pure returns (uint256) {
        return 2;
    }

    function STORE() external view returns (address) {
        return _hookStore;
    }
}

contract MockBannyResolver {
    address internal immutable _owner;
    address internal immutable _trustedForwarder;
    string internal _svgDescription;
    string internal _svgExternalUrl;
    string internal _svgBaseUri;

    constructor(
        address owner_,
        address trustedForwarder_,
        string memory description_,
        string memory externalUrl_,
        string memory baseUri_
    ) {
        _owner = owner_;
        _trustedForwarder = trustedForwarder_;
        _svgDescription = description_;
        _svgExternalUrl = externalUrl_;
        _svgBaseUri = baseUri_;
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
