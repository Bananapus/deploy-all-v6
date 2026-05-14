// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

contract PostDeployDynamicConstructorArgsGapTest is Test {
    function test_dynamicConstructorArgsAreInPublishedArtifactScope() public view {
        string memory deployDocs = vm.readFile("DEPLOY.md");
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory manifest = vm.readFile("artifacts/artifacts.manifest.json");
        string memory artifactsSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");
        string memory bannyArtifact = vm.readFile("artifacts/Banny721TokenUriResolver.json");
        string memory forwarderArtifact = vm.readFile("artifacts/ERC2771Forwarder.json");

        assertTrue(
            _contains(deployDocs, "Produces v5-compatible `sphinx-sol-ct-artifact-1` JSON per contract"),
            "runbook advertises v5-compatible artifacts"
        );
        assertTrue(_contains(deployDocs, "`abi`, `args`, `solcInputHash`"), "runbook advertises artifact args");
        assertTrue(
            _contains(artifactsSource, "format: 'sphinx-sol-ct-artifact-1'"),
            "artifact emitter writes the advertised schema"
        );
        assertTrue(_contains(artifactsSource, "args: argsDecoded"), "artifact emitter publishes decoded args");

        assertTrue(_contains(manifest, "Banny721TokenUriResolver"), "Banny resolver is in the artifact manifest");
        assertTrue(_contains(manifest, "ERC2771Forwarder"), "forwarder is in the artifact manifest");
        assertTrue(
            _contains(
                deploySource,
                'artifactName: "Banny721TokenUriResolver", salt: BAN_RESOLVER_SALT, ctorArgs: resolverArgs'
            ),
            "Banny resolver is deployed with constructor args"
        );
        assertTrue(
            _contains(deploySource, '_serializeIfSet({key: j, name: "Banny721TokenUriResolver"'),
            "Banny resolver is emitted into the post-deploy address map"
        );
        assertTrue(
            _contains(deploySource, 'artifactName: "ERC2771Forwarder", salt: coreSalt, ctorArgs: abi.encode'),
            "forwarder is deployed with constructor args"
        );
        assertTrue(
            _contains(deploySource, '_serializeIfSet({key: j, name: "ERC2771Forwarder"'),
            "forwarder is emitted into the post-deploy address map"
        );

        assertTrue(_contains(bannyArtifact, '"type":"constructor"'), "Banny artifact has a constructor ABI");
        assertTrue(_contains(bannyArtifact, '"type":"string"'), "Banny constructor includes dynamic strings");
        assertTrue(_contains(forwarderArtifact, '"type":"constructor"'), "forwarder artifact has a constructor ABI");
        assertTrue(_contains(forwarderArtifact, '"type":"string"'), "forwarder constructor includes a dynamic string");

        // Post-fix: the head-only decoder is gone. ethers AbiCoder handles dynamic types properly.
        assertTrue(
            _contains(artifactsSource, "ethersUtils.defaultAbiCoder.decode"),
            "decoder delegates to ethers AbiCoder for tail-following"
        );
        assertTrue(
            _contains(artifactsSource, "import { utils as ethersUtils } from 'ethers'"),
            "decoder imports ethers utils"
        );
        assertFalse(_contains(artifactsSource, "Minimal head-only ABI decoder"), "old head-only decoder removed");
        assertFalse(
            _contains(artifactsSource, "decodePrimitivesAbi"), "old head-only decoder helper removed"
        );
    }

    function test_headOnlyDecoderEmitsOffsetsForStringConstructorArgs() public pure {
        string[] memory forwarderTypes = new string[](1);
        forwarderTypes[0] = "string";

        bytes memory forwarderArgs = abi.encode("Juicebox V6 Forwarder");
        bytes32[] memory forwarderDecoded =
            _decodeWordsLikeArtifactEmitter({types: forwarderTypes, data: forwarderArgs});

        assertEq(forwarderDecoded.length, 1, "forwarder has one decoded output");
        assertEq(forwarderDecoded[0], bytes32(uint256(32)), "string arg is emitted as ABI offset");
        assertEq(_wordAt(forwarderArgs, 32), bytes32(uint256(bytes("Juicebox V6 Forwarder").length)), "tail has length");
        assertNotEq(forwarderDecoded[0], _wordAt(forwarderArgs, 64), "decoded value is not the string payload");

        string[] memory bannyTypes = new string[](7);
        bannyTypes[0] = "string";
        bannyTypes[1] = "string";
        bannyTypes[2] = "string";
        bannyTypes[3] = "string";
        bannyTypes[4] = "string";
        bannyTypes[5] = "address";
        bannyTypes[6] = "address";

        address owner = 0x1111111111111111111111111111111111111111;
        address trustedForwarder = 0x2222222222222222222222222222222222222222;
        bytes memory bannyArgs =
            abi.encode("body", "necklace", "mouth", "standard-eyes", "alien-eyes", owner, trustedForwarder);

        bytes32[] memory bannyDecoded = _decodeWordsLikeArtifactEmitter({types: bannyTypes, data: bannyArgs});

        assertEq(bannyDecoded[0], bytes32(uint256(0xe0)), "first Banny string is emitted as offset");
        assertEq(bannyDecoded[1], bytes32(uint256(0x120)), "second Banny string is emitted as offset");
        assertEq(bannyDecoded[2], bytes32(uint256(0x160)), "third Banny string is emitted as offset");
        assertEq(bannyDecoded[3], bytes32(uint256(0x1a0)), "fourth Banny string is emitted as offset");
        assertEq(bannyDecoded[4], bytes32(uint256(0x1e0)), "fifth Banny string is emitted as offset");
        assertEq(bannyDecoded[5], bytes32(uint256(uint160(owner))), "static owner address still decodes");
        assertEq(
            bannyDecoded[6], bytes32(uint256(uint160(trustedForwarder))), "static trusted forwarder address decodes"
        );
        assertNotEq(bannyDecoded[0], _wordAt(bannyArgs, 0xe0 + 32), "first decoded string is not its payload");
    }

    function _decodeWordsLikeArtifactEmitter(
        string[] memory types,
        bytes memory data
    )
        internal
        pure
        returns (bytes32[] memory)
    {
        bytes32[] memory out = new bytes32[](types.length);
        uint256 offset;

        for (uint256 i; i < types.length; i++) {
            if (offset + 32 > data.length) break;

            bytes32 word = _wordAt(data, offset);
            offset += 32;

            if (_eq(types[i], "address")) {
                out[i] = bytes32(uint256(uint160(address(uint160(uint256(word))))));
            } else {
                out[i] = word;
            }
        }

        return out;
    }

    function _wordAt(bytes memory data, uint256 offset) internal pure returns (bytes32 word) {
        require(offset + 32 <= data.length, "word out of bounds");

        assembly {
            word := mload(add(add(data, 0x20), offset))
        }
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0) return true;
        if (n.length > h.length) return false;

        for (uint256 i; i <= h.length - n.length; i++) {
            bool matched = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) return true;
        }

        return false;
    }
}
