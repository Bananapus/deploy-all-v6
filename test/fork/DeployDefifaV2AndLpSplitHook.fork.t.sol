// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IJB721TokenUriResolver} from "@bananapus/721-hook-v6/src/interfaces/IJB721TokenUriResolver.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

import {JBUniswapV4LPSplitHook} from "@bananapus/univ4-lp-split-hook-v6/src/JBUniswapV4LPSplitHook.sol";

import {DefifaDeployer} from "@ballkidz/defifa/src/DefifaDeployer.sol";
import {DefifaGovernor} from "@ballkidz/defifa/src/DefifaGovernor.sol";
import {DefifaTokenUriResolver} from "@ballkidz/defifa/src/DefifaTokenUriResolver.sol";
import {DefifaLaunchProjectData} from "@ballkidz/defifa/src/structs/DefifaLaunchProjectData.sol";
import {DefifaTierParams} from "@ballkidz/defifa/src/structs/DefifaTierParams.sol";

import {
    DefifaV2Addresses,
    DefifaV2Base,
    DeployDefifaV2AndLpSplitHook
} from "../../script/DeployDefifaV2AndLpSplitHook.s.sol";

/// @notice Exposes the base's deploy and predictions for a fork run (no Sphinx harness). Etched over the Safe so the
/// deploy runs as the Safe exactly as the Sphinx proposal does: same ctor args, same CREATE2 addresses, and the
/// governors' `transferOwnership` calls come from their owner.
contract DefifaV2Harness is DefifaV2Base {
    function setupAndLoad() external returns (bool shouldDeployDefifa, bool shouldDeployLp) {
        _setupChainAddresses();
        _setupDefifaChainAddresses();
        shouldDeployLp = _shouldDeployLpStack();
        if (shouldDeployLp) _loadExistingDeploymentAddresses();
        _loadDefifaDeploymentAddresses();
        shouldDeployDefifa = _shouldDeployDefifa();
    }

    function deployLpStack() external returns (address mathLib, address hook) {
        _deployLpStack();
        (mathLib,) = _isDeployed({
            salt: _MATH_LIB_SALT, creationCode: _loadArtifact("JBUniswapV4LPSplitHookMath"), arguments: ""
        });
        hook = address(_lpSplitHook);
    }

    function lpInstance() external view returns (JBUniswapV4LPSplitHook) {
        return _predictLpSplitHookInstance();
    }

    function deployAll(address safe) external {
        _deployAll(safe);
    }

    function predictAll(address safe) external returns (DefifaV2Addresses memory) {
        return _predictAll(safe);
    }

    function typeface() external view returns (address) {
        return _typeface;
    }

    function terminal() external view returns (address) {
        return _deploymentAddressOf("JBMultiTerminal");
    }

    function projects() external view returns (IJBProjects) {
        return IJBProjects(_deploymentAddressOf("JBProjects"));
    }
}

/// @notice Fork-simulates the Defifa 2.0 + LP split hook 1.5.0 release deploy to guard the deploy mechanics:
/// deployment-JSON reads, constructor encoding, deterministic CREATE2 (the dump's predictions are where the contracts
/// land), library linking (each hook
/// calls the library deployed at the address baked into it), governor handoff, and a launchable game of each type.
/// Runs on `DEFIFA_V2_FORK` (default `base`). Requires `npm run artifacts` + that chain's RPC env var.
contract DeployDefifaV2ForkTest is Test {
    address internal constant _SAFE = 0x4dc161eF837fF1C4485b08DDFcDB182F2157bE18;

    DefifaV2Harness internal harness;
    bool internal shouldDeploy;
    bool internal shouldDeployLp;

    function setUp() public {
        vm.createSelectFork(vm.envOr({name: "DEFIFA_V2_FORK", defaultValue: string("base")}));

        // Run as the Safe: etch the harness's code at the Safe's address.
        DefifaV2Harness impl = new DefifaV2Harness();
        vm.etch(_SAFE, address(impl).code);
        // The harness reads deployment records and artifacts through cheatcodes, now from the Safe's address.
        vm.allowCheatcodes(_SAFE);
        harness = DefifaV2Harness(_SAFE);
        (shouldDeploy, shouldDeployLp) = harness.setupAndLoad();
    }

    /// @notice The LP split hook stack deploys as the Safe, and its hook calls the math library deployed at the
    /// address baked into it.
    function test_deploysLpStack() public {
        if (!shouldDeployLp) return;
        (address mathLib, address hook) = harness.deployLpStack();
        assertTrue(mathLib.code.length != 0, "math library deployed");
        assertTrue(_codeContains(hook, mathLib), "LP hook links the math library");

        // The shared instance takes the standard fee: 10% of collected LP fees to project 1.
        JBUniswapV4LPSplitHook instance = harness.lpInstance();
        assertTrue(address(instance).code.length != 0, "shared instance deployed");
        assertEq(instance.feeProjectId(), 1, "instance fee project");
        assertEq(instance.feePercent(), 1000, "instance fee percent");
    }

    /// @notice The real script's post-deploy dump lists exactly this release's contracts at the predicted addresses,
    /// and leaves out the LP stack on chains without a V4 PositionManager.
    function test_dumpListsPredictedAddresses() public {
        DeployDefifaV2AndLpSplitHook script = new DeployDefifaV2AndLpSplitHook();
        script.dumpAddresses();

        string memory path = string.concat("script/post-deploy/.cache/addresses-", vm.toString(block.chainid), ".json");
        if (!shouldDeploy && !shouldDeployLp) {
            return;
        }
        string memory json = vm.readFile(path);

        if (shouldDeploy) {
            DefifaV2Addresses memory a = harness.predictAll(_SAFE);
            assertEq(vm.parseJsonAddress(json, ".DefifaHookLib"), a.hookLib, "dump DefifaHookLib");
            assertEq(vm.parseJsonAddress(json, ".Defifa1155HookLib"), a.hookLib1155, "dump Defifa1155HookLib");
            assertEq(vm.parseJsonAddress(json, ".DefifaTiersHookStore"), a.store, "dump store");
            assertEq(vm.parseJsonAddress(json, ".DefifaTokenUriResolver"), a.tokenUriResolver, "dump resolver");
            assertEq(vm.parseJsonAddress(json, ".DefifaHook"), a.hook, "dump 721 hook");
            assertEq(vm.parseJsonAddress(json, ".DefifaGovernor"), a.governor, "dump 721 governor");
            assertEq(vm.parseJsonAddress(json, ".DefifaDeployer"), a.deployer, "dump 721 deployer");
            assertEq(vm.parseJsonAddress(json, ".Defifa1155Hook"), a.hook1155, "dump 1155 hook");
            assertEq(vm.parseJsonAddress(json, ".Defifa1155Governor"), a.governor1155, "dump 1155 governor");
            assertEq(vm.parseJsonAddress(json, ".Defifa1155Deployer"), a.deployer1155, "dump 1155 deployer");
            assertEq(vm.parseJsonAddress(json, ".DefifaVotingReferee"), a.referee, "dump referee");
        }

        // The LP stack's keys appear exactly when this chain gets the LP stack.
        assertEq(vm.keyExistsJson(json, ".JBUniswapV4LPSplitHook"), shouldDeployLp, "LP keys match the LP decision");
        assertEq(vm.keyExistsJson(json, ".JBP6FeeLPSplitHook"), shouldDeployLp, "LP instance key matches");
        assertEq(vm.parseJsonUint(json, ".chainId"), block.chainid, "dump chain");
    }

    function test_deploysPredictedStackAndLaunchesGames() public {
        // Chains without a typeface or fee tokens skip Defifa, as Deploy.s.sol does.
        if (!shouldDeploy) return;

        DefifaV2Addresses memory a = harness.predictAll(_SAFE);
        harness.deployAll(_SAFE);

        // Every predicted address now has code, so the post-deploy dump lists exactly what was deployed.
        address[11] memory all = [
            a.hookLib,
            a.hookLib1155,
            a.store,
            a.tokenUriResolver,
            a.hook,
            a.governor,
            a.deployer,
            a.hook1155,
            a.governor1155,
            a.deployer1155,
            a.referee
        ];
        for (uint256 i; i < all.length; i++) {
            assertTrue(all[i].code.length != 0, "predicted contract deployed");
        }

        // Each hook calls the libraries deployed at the addresses the build linker baked into it.
        assertTrue(_codeContains(a.hook, a.hookLib), "721 hook links DefifaHookLib");
        assertTrue(_codeContains(a.hook1155, a.hookLib1155), "1155 hook links Defifa1155HookLib");
        assertTrue(_codeContains(a.hookLib1155, a.hookLib), "Defifa1155HookLib links DefifaHookLib");
        assertTrue(_codeContains(a.governor, a.hookLib), "governor links DefifaHookLib");
        assertTrue(_codeContains(a.referee, a.hookLib), "referee links DefifaHookLib");

        // The resolver renders with this chain's typeface.
        assertEq(
            address(DefifaTokenUriResolver(a.tokenUriResolver).typeface()), harness.typeface(), "resolver typeface"
        );

        // Two game types, separate governors, each owned by its deployer, sharing one store and resolver.
        _assertGameType({deployer: a.deployer, hook: a.hook, governor: a.governor, a: a});
        _assertGameType({deployer: a.deployer1155, hook: a.hook1155, governor: a.governor1155, a: a});
        assertTrue(a.governor != a.governor1155, "separate governors");

        // Re-running is a no-op: every address is already deployed and the governors are already handed off.
        harness.deployAll(_SAFE);

        // A game of each type launches through its deployer and names its referee in its governor.
        _launchAndCheck({deployer: DefifaDeployer(a.deployer), governor: DefifaGovernor(a.governor)});
        _launchAndCheck({deployer: DefifaDeployer(a.deployer1155), governor: DefifaGovernor(a.governor1155)});
    }

    function _assertGameType(
        address deployer,
        address hook,
        address governor,
        DefifaV2Addresses memory a
    )
        internal
        view
    {
        DefifaDeployer d = DefifaDeployer(deployer);
        assertEq(d.HOOK_CODE_ORIGIN(), hook, "hook code origin");
        assertEq(address(d.GOVERNOR()), governor, "governor");
        assertEq(address(d.HOOK_STORE()), a.store, "shared store");
        assertEq(address(d.TOKEN_URI_RESOLVER()), a.tokenUriResolver, "shared resolver");
        assertEq(d.DEFIFA_PROJECT_ID(), 5, "DEFIFA fee project");
        assertEq(d.BASE_PROTOCOL_PROJECT_ID(), 1, "NANA base protocol project");
        assertEq(DefifaGovernor(governor).owner(), deployer, "governor owned by its deployer");
    }

    function _launchAndCheck(DefifaDeployer deployer, DefifaGovernor governor) internal {
        DefifaTierParams[] memory tiers = new DefifaTierParams[](2);
        tiers[0] = DefifaTierParams({
            name: "Team A",
            reservedRate: 0,
            reservedTokenBeneficiary: address(0),
            encodedIpfsUri: bytes32(0),
            shouldUseReservedTokenBeneficiaryAsDefault: false
        });
        tiers[1] = DefifaTierParams({
            name: "Team B",
            reservedRate: 0,
            reservedTokenBeneficiary: address(0),
            encodedIpfsUri: bytes32(0),
            shouldUseReservedTokenBeneficiaryAsDefault: false
        });

        // Launching creates a Juicebox project, which charges the protocol's project creation fee.
        uint256 creationFee = harness.projects().creationFee();
        vm.deal(address(this), creationFee);
        uint256 gameId = deployer.launchGameWith{value: creationFee}(
            DefifaLaunchProjectData({
                name: "Defifa 2.0 rehearsal",
                projectUri: "",
                contractUri: "",
                baseUri: "",
                tiers: tiers,
                tierPrice: uint104(1e15),
                token: JBAccountingContext({
                    token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                mintPeriodDuration: 1 days,
                refundPeriodDuration: 0,
                start: 0,
                splits: new JBSplit[](0),
                defaultAttestationDelegate: address(0),
                defaultTokenUriResolver: IJB721TokenUriResolver(address(0)),
                terminal: IJBTerminal(harness.terminal()),
                minParticipation: 0,
                scorecardTimeout: 7 days,
                timelockDuration: 1 days,
                referee: address(0xBEEF),
                refereeData: ""
            })
        );
        assertGt(gameId, 0, "game launched");
        assertEq(governor.refereeOf(gameId), address(0xBEEF), "referee named");
        assertEq(governor.timelockDurationOf(gameId), 1 days, "timelock set");
    }

    /// @notice Whether `account`'s runtime code embeds `target`'s 20 address bytes.
    function _codeContains(address account, address target) internal view returns (bool) {
        bytes memory code = account.code;
        bytes20 needle = bytes20(target);
        if (code.length < 20) return false;
        for (uint256 i; i <= code.length - 20; i++) {
            bytes20 window;
            assembly {
                window := mload(add(add(code, 0x20), i))
            }
            if (window == needle) return true;
        }
        return false;
    }
}
