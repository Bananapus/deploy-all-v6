// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Deploy} from "../../script/Deploy.s.sol";
import {CREATE3} from "solady/src/utils/CREATE3.sol";

/// @title Create3OperatorFrontrunDefense
/// @notice Regression test pinning the CREATE3 pre-deployment (frontrun) defense in `Deploy.s.sol`.
///
/// The threat (multi-leaf-deploy-create3-prediction-frontrun): the JBController is deployed with
/// `OMNICHAIN_RULESET_OPERATOR = _create3Address(OMNICHAIN_DEPLOYER_SALT)` (a deterministic prediction).
/// The actual JBOmnichainDeployer is CREATE3-deployed in a *later* step. Both the CREATE3 proxy CREATE2
/// and the proxy's `call(initCode)` are PERMISSIONLESS, so a lone attacker who knows the (public) salt can
/// pre-deploy their OWN bytecode at the predicted address before the legitimate deploy runs.
///
/// If the deploy helper used only the old `if (addr.code.length != 0) return addr` shortcut, the attacker's
/// code would be silently accepted and baked into `JBController.OMNICHAIN_RULESET_OPERATOR` — a permanent,
/// un-fixable backdoor that BYPASSES permissions on `launchRulesetsFor`/`queueRulesetsOf` for every project
/// on the chain (JBController.sol:502-520, :678).
///
/// The shipped defense (`_deployCreate3PrecompiledIfNeeded`, Deploy.s.sol:4740-4780) computes the EXPECTED
/// runtime codehash via a sandbox CREATE and reverts (`Deploy_Create3CodehashMismatch`) on the early-return
/// path when foreign bytecode sits at the predicted address. This test was MISSING from the suite; it proves
/// the defense actually fires.
///
/// Run: forge test --match-contract Create3OperatorFrontrunDefense -vvv
contract DeployFrontrunHarness is Deploy {
    /// @dev Exposes the SHIPPED pure helper, proven faithful by DeployHelperProperties.
    function create3Address(bytes32 salt) external pure returns (address) {
        return _create3Address(salt);
    }

    /// @dev Exposes the SHIPPED proxy init code.
    function create3ProxyInitCode() external pure returns (bytes memory) {
        return _create3ProxyInitCode();
    }

    /// @dev Exposes the SHIPPED runtime-codehash-via-sandbox helper.
    function runtimeCodehashOf(bytes memory initCode, bytes32 salt) external returns (bytes32) {
        return _runtimeCodehashOf(initCode, salt);
    }

    /// @dev Exposes the SHIPPED salt-folding helper so the test predicts the same address the script uses.
    function saltOf(bytes32 base) external pure returns (bytes32) {
        return _saltOf(base);
    }

    /// @dev Byte-for-byte copy of the SHIPPED `_deployCreate3PrecompiledIfNeeded` ORCHESTRATION, with the
    ///      only change being that `initCode` is supplied by the caller instead of read from a disk artifact
    ///      via `_loadArtifact` (which is `internal` non-`virtual`, so it cannot be overridden, and which is
    ///      orthogonal to the frontrun defense). Every line that constitutes the defense — the sandbox
    ///      codehash derivation, the early-return codehash compare, and the post-deploy codehash compare —
    ///      is the SHIPPED code, invoked through the real internal helpers above.
    /// @dev `salt` is the RAW base salt, exactly as the shipped call site passes it. The internal helpers
    ///      (`_create3Address`, `_isDeployed`, `_deployViaFactory`, `_runtimeCodehashOf`) each fold it via
    ///      `_saltOf` consistently — matching the shipped code's salt handling.
    function deployCreate3PrecompiledIfNeeded(bytes memory initCode, bytes32 salt) external returns (address addr) {
        addr = _create3Address({salt: salt});

        bytes32 expectedCodehash = _runtimeCodehashOf({initCode: initCode, salt: salt});

        // Early-return path: code is already at `addr`. SHIPPED defense.
        if (addr.code.length != 0) {
            if (addr.codehash != expectedCodehash) {
                revert Deploy_Create3CodehashMismatch({addr: addr, expected: expectedCodehash, actual: addr.codehash});
            }
            return addr;
        }

        // Deploy the one-shot CREATE3 proxy at the canonical factory/salt address if this is the first run.
        (address proxy, bool proxyAlready) =
            _isDeployed({salt: salt, creationCode: _create3ProxyInitCode(), arguments: ""});
        if (!proxyAlready) {
            proxy = _deployViaFactory({
                factory: 0x4e59b44847b379578588920cA78FbF26c0B4956C,
                salt: salt,
                creationCode: _create3ProxyInitCode(),
                constructorArgs: ""
            });
        }

        (bool success,) = proxy.call(initCode);
        if (!success || addr.code.length == 0) revert Deploy_Create3DeploymentFailed({expected: addr});

        if (addr.codehash != expectedCodehash) {
            revert Deploy_Create3CodehashMismatch({addr: addr, expected: expectedCodehash, actual: addr.codehash});
        }
    }
}

/// @notice Stand-in for the legitimate JBOmnichainDeployer: a benign contract with no constructor side
/// effects so the test is self-contained (no fork required). The frontrun defense is about bytecode
/// IDENTITY at a predicted address — independent of what the real deployer's constructor does.
contract BenignOperator {
    address public immutable CONTROLLER;

    constructor(address controller) {
        CONTROLLER = controller;
    }
}

/// @notice The attacker's malicious operator. If this bytecode is silently accepted at the predicted
/// address, the attacker would own JBController.OMNICHAIN_RULESET_OPERATOR.
contract MaliciousOperator {
    address public immutable OWNER;

    constructor(address owner) {
        OWNER = owner;
    }
}

contract Create3OperatorFrontrunDefense is Test {
    // Local mirror of the shipped error so `vm.expectRevert` matches it via this contract's own ABI entry.
    error Deploy_Create3CodehashMismatch(address addr, bytes32 expected, bytes32 actual);

    // Canonical Arachnid CREATE2 factory (`CREATE2_FACTORY`) is inherited from forge-std's CommonBase.
    // The SHIPPED salt for the omnichain deployer (Deploy.s.sol:262).
    bytes32 internal constant OMNICHAIN_DEPLOYER_SALT = "JBOmnichainDeployerV6_";

    DeployFrontrunHarness internal h;
    address internal attacker = makeAddr("attacker");
    address internal legitController = makeAddr("legitController");

    function setUp() public {
        h = new DeployFrontrunHarness();
        // Foundry pre-etches the canonical Arachnid CREATE2 factory at `CREATE2_FACTORY`; assert it so the
        // CREATE3 address predictions below match the real chain behavior.
        assertGt(CREATE2_FACTORY.code.length, 0, "canonical CREATE2 factory must be present in the test VM");
    }

    /// @notice The predicted address is publicly derivable from the salt alone — the attacker needs no secret.
    function test_predictedAddressIsPublic() public view {
        address predicted = h.create3Address(OMNICHAIN_DEPLOYER_SALT);
        bytes32 foldedSalt = h.saltOf(OMNICHAIN_DEPLOYER_SALT);
        // Anyone can recompute it.
        address recomputed = CREATE3.predictDeterministicAddress({salt: foldedSalt, deployer: CREATE2_FACTORY});
        assertEq(predicted, recomputed, "predicted CREATE3 address is publicly derivable from the salt");
    }

    /// @notice CORE FINDING: if an attacker pre-deploys their own bytecode at the predicted CREATE3 address,
    /// the shipped helper's codehash check REVERTS instead of silently baking the attacker's operator in.
    function test_attackerPredeploy_isRejectedByCodehashCheck() public {
        bytes32 foldedSalt = h.saltOf(OMNICHAIN_DEPLOYER_SALT);
        address predicted = h.create3Address(OMNICHAIN_DEPLOYER_SALT);

        // --- ATTACKER STEP 1: deploy the permissionless CREATE3 proxy at its deterministic CREATE2 address. ---
        // The proxy itself is the CREATE2(factory, foldedSalt, keccak256(proxyInit)) contract; the final CREATE3
        // target is then CREATE(proxy, nonce=1). `predictDeterministicAddress` returns the TARGET, not the proxy.
        bytes memory proxyInit = h.create3ProxyInitCode();
        vm.prank(attacker);
        (bool ok,) = CREATE2_FACTORY.call(abi.encodePacked(foldedSalt, proxyInit));
        require(ok, "attacker could not deploy CREATE3 proxy");
        address proxy =
            vm.computeCreate2Address({salt: foldedSalt, initCodeHash: keccak256(proxyInit), deployer: CREATE2_FACTORY});
        require(proxy.code.length > 0, "proxy not deployed at expected CREATE2 address");

        // --- ATTACKER STEP 2: call the proxy with MALICIOUS init code → attacker bytecode at `predicted`. ---
        bytes memory maliciousInit = abi.encodePacked(type(MaliciousOperator).creationCode, abi.encode(attacker));
        vm.prank(attacker);
        (ok,) = proxy.call(maliciousInit);
        require(ok, "attacker proxy call failed");

        // Attacker's bytecode is now at the predicted address.
        assertGt(predicted.code.length, 0, "attacker bytecode is at the predicted address");
        assertEq(MaliciousOperator(predicted).OWNER(), attacker, "attacker owns the squatted operator");

        // --- LEGIT DEPLOY: runs the SHIPPED helper with the genuine operator init code. ---
        bytes memory legitInit = abi.encodePacked(type(BenignOperator).creationCode, abi.encode(legitController));

        // The early-return codehash check must REVERT with the SPECIFIC mismatch error — attacker code !=
        // expected genuine codehash. The helper takes the RAW salt (folds internally) per the shipped call site.
        // Assert the FULL shipped `Deploy_Create3CodehashMismatch(addr, expected, actual)` revert: predicted addr,
        // the genuine expected codehash (sandbox-derived), and the attacker's actual codehash now sitting at addr.
        bytes32 expectedCodehash = h.runtimeCodehashOf(legitInit, OMNICHAIN_DEPLOYER_SALT);
        bytes32 attackerCodehash = predicted.codehash;
        assertTrue(expectedCodehash != attackerCodehash, "expected vs attacker codehash must differ");
        vm.expectRevert(
            abi.encodeWithSelector(
                Deploy_Create3CodehashMismatch.selector, predicted, expectedCodehash, attackerCodehash
            )
        );
        h.deployCreate3PrecompiledIfNeeded(legitInit, OMNICHAIN_DEPLOYER_SALT);
    }

    /// @notice Sanity counterpart: with NO attacker, the genuine deploy succeeds and lands the genuine
    /// bytecode at the predicted address (the defense does not break the happy path).
    function test_genuineDeploy_succeeds() public {
        address predicted = h.create3Address(OMNICHAIN_DEPLOYER_SALT);

        bytes memory legitInit = abi.encodePacked(type(BenignOperator).creationCode, abi.encode(legitController));
        address deployed = h.deployCreate3PrecompiledIfNeeded(legitInit, OMNICHAIN_DEPLOYER_SALT);

        assertEq(deployed, predicted, "genuine deploy lands at the predicted address");
        assertEq(BenignOperator(deployed).CONTROLLER(), legitController, "genuine operator wired to controller");
    }

    /// @notice The idempotent early-return path ALSO validates: if the GENUINE bytecode is already present
    /// (e.g. a Sphinx resume re-running the leaf), the helper accepts it without redeploying.
    function test_idempotentResume_acceptsGenuineCode() public {
        bytes memory legitInit = abi.encodePacked(type(BenignOperator).creationCode, abi.encode(legitController));

        address first = h.deployCreate3PrecompiledIfNeeded(legitInit, OMNICHAIN_DEPLOYER_SALT);
        // Second run hits the early-return path; genuine codehash matches → no revert, same address.
        address second = h.deployCreate3PrecompiledIfNeeded(legitInit, OMNICHAIN_DEPLOYER_SALT);
        assertEq(first, second, "resume re-accepts genuine bytecode idempotently");
    }
}
