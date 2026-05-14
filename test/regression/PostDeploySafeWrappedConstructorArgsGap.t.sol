// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

contract PostDeploySafeWrappedConstructorArgsGapTest is Test {
    address internal constant DETERMINISTIC_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function test_postDeployConstructorArgRecoveryUsesFactoryInternalCall() public view {
        string memory artifactsSource = vm.readFile("script/post-deploy/lib/artifacts.mjs");
        string memory verifySource = vm.readFile("script/post-deploy/lib/verify.mjs");

        // artifacts.mjs prefers the deterministic-factory's internal-call input over the outer
        // Safe-wrapped tx input.
        assertTrue(
            _contains(artifactsSource, "getFactoryCallInput"), "artifact emitter declares the factory-call helper"
        );
        assertTrue(
            _contains(artifactsSource, "const factoryInput = await getFactoryCallInput"),
            "artifact emitter calls the factory-call helper to recover args"
        );
        assertTrue(
            _contains(artifactsSource, "factoryInput || await getTxInput"),
            "artifact emitter falls back to outer tx input when the internal call is missing"
        );
        assertTrue(
            _contains(artifactsSource, "0x4e59b44847b379578588920ca78fbf26c0b4956c"),
            "factory-call helper targets the canonical deterministic factory"
        );
        assertTrue(
            _contains(artifactsSource, "action=txlistinternal"),
            "factory-call helper queries Etherscan's internal-tx API"
        );
        assertTrue(
            _contains(
                artifactsSource, "sliceConstructorArgs({txInput, creationCodeHex: forgeArtifact.bytecode.object})"
            ),
            "slicer is still used (now against the clean factory-call input)"
        );

        // verify.mjs MUST use the same factory-call recovery — otherwise Etherscan verification
        // still resolves constructor args from the Safe wrapper and mismatches the artifact.
        assertTrue(_contains(verifySource, "getFactoryCallInput"), "verifier declares the factory-call helper");
        assertTrue(
            _contains(verifySource, "const factoryInput = await getFactoryCallInput"),
            "verifier calls the factory-call helper to recover args"
        );
        assertTrue(
            _contains(verifySource, "factoryInput || await getTxInput"),
            "verifier falls back to outer tx input when the internal call is missing"
        );
        assertTrue(
            _contains(verifySource, "0x4e59b44847b379578588920ca78fbf26c0b4956c"),
            "verifier factory-call helper targets the canonical deterministic factory"
        );
        assertTrue(
            _contains(verifySource, "action=txlistinternal"),
            "verifier factory-call helper queries Etherscan's internal-tx API"
        );
    }

    function test_slicerOverSlicesSafeWrappedFactoryCalldata() public pure {
        bytes32 salt = keccak256("_ExampleV6_");
        bytes memory creationCode = hex"6080604052348015600f57600080fd5b5060aa80601d6000396000f3fe";
        bytes memory constructorArgs = abi.encode(address(0x1234567890123456789012345678901234567890), uint256(42));
        bytes memory factoryInput = bytes.concat(salt, creationCode, constructorArgs);

        bytes memory directFactorySlice =
            _sliceConstructorArgsLikePostDeployScripts({txInput: factoryInput, creationCode: creationCode});
        assertEq(keccak256(directFactorySlice), keccak256(constructorArgs), "direct factory input slices correctly");

        bytes memory safeModuleInput = abi.encodeWithSignature(
            "execTransactionFromModule(address,uint256,bytes,uint8)",
            DETERMINISTIC_FACTORY,
            uint256(0),
            factoryInput,
            uint8(0)
        );

        bytes memory wrappedSlice =
            _sliceConstructorArgsLikePostDeployScripts({txInput: safeModuleInput, creationCode: creationCode});

        assertTrue(_startsWith(wrappedSlice, constructorArgs), "fallback finds creation code inside wrapped calldata");
        assertGt(wrappedSlice.length, constructorArgs.length, "wrapper ABI tail is included as fake constructor args");
        assertNotEq(
            keccak256(wrappedSlice), keccak256(constructorArgs), "Safe-wrapped calldata does not recover exact args"
        );
    }

    function _sliceConstructorArgsLikePostDeployScripts(
        bytes memory txInput,
        bytes memory creationCode
    )
        internal
        pure
        returns (bytes memory)
    {
        if (txInput.length >= 32 + creationCode.length && _matchesAt(txInput, 32, creationCode)) {
            return _slice(txInput, 32 + creationCode.length, txInput.length);
        }

        if (_matchesAt(txInput, 0, creationCode)) {
            return _slice(txInput, creationCode.length, txInput.length);
        }

        (bool found, uint256 idx) = _indexOf(txInput, creationCode);
        if (found) return _slice(txInput, idx + creationCode.length, txInput.length);

        return "";
    }

    function _indexOf(bytes memory haystack, bytes memory needle) internal pure returns (bool found, uint256 idx) {
        if (needle.length == 0 || needle.length > haystack.length) return (false, 0);

        for (uint256 i; i <= haystack.length - needle.length; i++) {
            if (_matchesAt(haystack, i, needle)) return (true, i);
        }

        return (false, 0);
    }

    function _matchesAt(bytes memory haystack, uint256 offset, bytes memory needle) internal pure returns (bool) {
        if (offset + needle.length > haystack.length) return false;

        for (uint256 i; i < needle.length; i++) {
            if (haystack[offset + i] != needle[i]) return false;
        }

        return true;
    }

    function _startsWith(bytes memory data, bytes memory prefix) internal pure returns (bool) {
        return _matchesAt(data, 0, prefix);
    }

    function _slice(bytes memory data, uint256 start, uint256 end) internal pure returns (bytes memory) {
        require(start <= end && end <= data.length, "invalid slice");

        bytes memory out = new bytes(end - start);
        for (uint256 i; i < out.length; i++) {
            out[i] = data[start + i];
        }
        return out;
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
