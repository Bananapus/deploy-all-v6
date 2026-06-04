// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

contract DeployCanonicalConfiguredRevnetGuardTest is Test {
    function test_configuredRevnetReplayGuardsRequireExactCanonicalShape() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");

        string memory revSource = _section({
            haystack: deploySource,
            startNeedle: "function _deployRevFeeProject()",
            endNeedle: "function _deployCpnRevnet()"
        });
        string memory cpnSource = _section({
            haystack: deploySource,
            startNeedle: "function _deployCpnRevnet()",
            endNeedle: "function _deployNanaRevnet()"
        });
        string memory defifaSource = _section({
            haystack: deploySource, startNeedle: "function _deployDefifaRevnet()", endNeedle: "function _deployArt()"
        });
        string memory artSource = _section({
            haystack: deploySource, startNeedle: "function _deployArt()", endNeedle: "function _deployMarkee()"
        });
        string memory markeeSource = _section({
            haystack: deploySource,
            startNeedle: "function _deployMarkee()",
            endNeedle: "function _deployProjectHandles()"
        });
        string memory bannySource = _section({
            haystack: deploySource, startNeedle: "function _deployBanny()", endNeedle: "function _registerBannyDrop1()"
        });

        assertTrue(
            _contains(deploySource, '"https://jbm.infura-ipfs.io/ipfs/QmSVqxSQQqkNfDTArdrNRQVpPTvDjPHXBKavhFgUNVNfEn"'),
            "DEFIFA URI is pinned"
        );
        assertTrue(
            _contains(deploySource, '"https://jbm.infura-ipfs.io/ipfs/QmNaP7LAFYwUcFUQrext1tZmhCHkHDrfrbqXbt7MZqmM9S"'),
            "ART URI is pinned"
        );
        assertTrue(
            _contains(deploySource, '"https://jbm.infura-ipfs.io/ipfs/QmWgNJGFLZZdVCn5PuUEDBkSa7iL8jgFVKgJq93Aqub56E"'),
            "MARKEE URI is pinned"
        );

        _assertStrictConfiguredRevnetGuard({
            deployFunctionSource: revSource,
            projectIdName: "_revProjectId",
            expectedSymbol: "REV",
            expectedUri: '"ipfs://QmcCBD5fM927LjkLDSJWtNEU9FohcbiPSfqtGRHXFHzJ4W"'
        });
        _assertStrictConfiguredRevnetGuard({
            deployFunctionSource: cpnSource,
            projectIdName: "_cpnProjectId",
            expectedSymbol: "CPN",
            expectedUri: '"ipfs://QmUAFevoMn1iqSEQR8LogQYRxm39TNxQTPYnuLuq5BmfEi"'
        });
        _assertStrictConfiguredRevnetGuard({
            deployFunctionSource: defifaSource,
            projectIdName: "_DEFIFA_REV_PROJECT_ID",
            expectedSymbol: "DEFIFA",
            expectedUri: "DEFIFA_REV_URI"
        });
        _assertStrictConfiguredRevnetGuard({
            deployFunctionSource: artSource,
            projectIdName: "_ART_PROJECT_ID",
            expectedSymbol: "ART",
            expectedUri: "ART_URI"
        });
        _assertStrictConfiguredRevnetGuard({
            deployFunctionSource: markeeSource,
            projectIdName: "_MARKEE_PROJECT_ID",
            expectedSymbol: "MARKEE",
            expectedUri: "MARKEE_URI"
        });

        assertTrue(_contains(bannySource, "_encodedConfigurationHashOf"), "Banny computes expected config hash");
        assertTrue(_contains(bannySource, "_isCanonicalBannyProject"), "Banny uses strict canonical guard");

        string memory genericGuard = _section({
            haystack: deploySource,
            startNeedle: "function _isCanonicalRevnetProject(",
            endNeedle: "function _isCanonicalNanaRevnetProject("
        });
        assertTrue(
            _contains(genericGuard, "hashedEncodedConfigurationOf(projectId) != expectedConfigurationHash"),
            "generic guard checks exact config hash"
        );
        assertTrue(_contains(genericGuard, "isOperatorOf"), "generic guard checks expected operator");
        assertFalse(
            _contains(genericGuard, "_revnetOperatorCanSetSuckerPeer"),
            "generic guard must not require an unnecessary SET_SUCKER_PEER operator grant"
        );
        assertTrue(_contains(genericGuard, "uriOf(projectId)"), "generic guard checks project URI");
        assertTrue(_contains(genericGuard, "_reservedSplitIsCanonical"), "generic guard checks reserved split");
        assertTrue(_contains(genericGuard, "_terminalConfigIsCanonical"), "generic guard checks terminal setup");

        string memory hashHelper = _section({
            haystack: deploySource,
            startNeedle: "function _encodedConfigurationHashOf(",
            endNeedle: "function _reservedSplitIsCanonical("
        });
        assertFalse(_contains(hashHelper, "_routerTerminalRegistry"), "config hash must not encode router terminal");
        assertFalse(_contains(hashHelper, "_terminal"), "config hash must not encode multi terminal");

        // The terminal guard must be token-aware: ART(6) is USD-denominated and accepts USDC directly,
        // so the canonical replay/resume check must compare against USDC (not native ETH) for that project.
        // DEFIFA(5) uses native ETH like the other all-chain revnets.
        string memory expectedTokenHelper = _section({
            haystack: deploySource,
            startNeedle: "function _expectedTerminalTokenFor(",
            endNeedle: "function _terminalConfigIsCanonical("
        });
        assertFalse(_contains(expectedTokenHelper, "_DEFIFA_REV_PROJECT_ID"), "DEFIFA expected token must be native");
        assertTrue(_contains(expectedTokenHelper, "_ART_PROJECT_ID"), "expected terminal token must special-case ART");
        assertTrue(_contains(expectedTokenHelper, "_usdcToken"), "ART expected terminal token must be USDC");
        string memory terminalConfigGuard = _section({
            haystack: deploySource,
            startNeedle: "function _terminalConfigIsCanonical(",
            endNeedle: "function _projectTokenSymbolIs("
        });
        assertTrue(
            _contains(terminalConfigGuard, "_expectedTerminalTokenFor(projectId)"),
            "terminal guard resolves the per-project expected token"
        );
        assertFalse(
            _contains(terminalConfigGuard, "JBConstants.NATIVE_TOKEN"),
            "terminal guard must not hard-code the native token"
        );

        string memory bannyGuard = _section({
            haystack: deploySource,
            startNeedle: "function _isCanonicalBannyProject(",
            endNeedle: "function _isCanonicalRevnetProject("
        });
        assertTrue(_contains(bannyGuard, "_isCanonicalRevnetProjectShape"), "Banny checks exact revnet shape");
        assertTrue(_contains(bannyGuard, "_BAN_OPS_OPERATOR"), "Banny accepts finalized ops operator");
        assertFalse(
            _contains(bannyGuard, "_revnetOperatorCanSetSuckerPeer"),
            "Banny guard must not require an unnecessary SET_SUCKER_PEER operator grant"
        );
        assertTrue(
            _contains(bannySource, "partialResumeOperator: safeAddress()"), "Banny passes the deployment safe operator"
        );
        assertTrue(_contains(bannyGuard, "partialResumeOperator"), "Banny accepts partial-resume safe operator");
        assertTrue(_contains(bannyGuard, "BANNY"), "Banny checks tiered hook identity");
    }

    function test_revnetDeploymentsDoNotRequireExplicitSuckerPeerOperatorGrant() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");

        assertFalse(
            _contains(deploySource, "_requireRevnetOperatorCanSetSuckerPeer"),
            "revnet deployments must not require an unnecessary SET_SUCKER_PEER operator grant"
        );
        assertFalse(
            _contains(deploySource, "_revnetOperatorCanSetSuckerPeer"),
            "revnet replay guards must not require an unnecessary SET_SUCKER_PEER operator grant"
        );
        assertFalse(
            _contains(deploySource, "JBPermissionIds.SET_SUCKER_PEER"),
            "deploy script must not grant the revnet operator explicit peer-setting power"
        );
        assertFalse(
            _contains(deploySource, "Deploy_MissingPermission"),
            "deploy script no longer has a revnet peer-permission preflight"
        );
    }

    function test_banDefifaAndMarkeeUseNativeCcipSuckerConfigs() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory bannySource = _section({
            haystack: deploySource, startNeedle: "function _deployBanny()", endNeedle: "function _registerBannyDrop1()"
        });
        string memory defifaSource = _section({
            haystack: deploySource, startNeedle: "function _deployDefifaRevnet()", endNeedle: "function _deployArt()"
        });
        string memory markeeSource = _section({
            haystack: deploySource,
            startNeedle: "function _deployMarkee()",
            endNeedle: "function _deployProjectHandles()"
        });
        string memory ccipConfigSource = _section({
            haystack: deploySource,
            startNeedle: "function _buildCcipSuckerConfig(",
            endNeedle: "function _nativeCcipEdge("
        });
        string memory ccipEdgeSource = _section({
            haystack: deploySource, startNeedle: "function _nativeCcipEdge(", endNeedle: "function _currencyIdOf("
        });

        assertTrue(
            _contains(bannySource, "_buildCcipSuckerConfig(BAN_SUCKER_SALT)"), "BAN uses route-specific CCIP suckers"
        );
        assertFalse(
            _contains(bannySource, "_buildSuckerConfig(BAN_SUCKER_SALT)"),
            "BAN must not use standard OP/Base/Arb suckers"
        );
        assertTrue(
            _contains(defifaSource, "_buildCcipSuckerConfig(DEFIFA_REV_SUCKER_SALT)"),
            "DEFIFA uses route-specific CCIP suckers"
        );
        assertFalse(
            _contains(defifaSource, "_buildSuckerConfig(DEFIFA_REV_SUCKER_SALT)"),
            "DEFIFA must not use standard OP/Base/Arb suckers"
        );
        assertTrue(
            _contains(markeeSource, "_buildCcipSuckerConfig(MARKEE_SUCKER_SALT)"),
            "MARKEE uses route-specific CCIP suckers"
        );
        assertTrue(
            _contains(deploySource, "_ccipSuckerDeployerForRemoteChain[remoteChainId] = ccipDeployer"),
            "deploy indexes route-specific CCIP deployers"
        );
        assertTrue(_contains(ccipConfigSource, "CCIPHelper.OP_ID"), "mainnet CCIP config includes OP");
        assertTrue(_contains(ccipConfigSource, "CCIPHelper.BASE_ID"), "mainnet CCIP config includes Base");
        assertTrue(_contains(ccipConfigSource, "CCIPHelper.ARB_ID"), "mainnet CCIP config includes Arbitrum");
        assertTrue(
            _contains(ccipEdgeSource, "_ccipSuckerDeployerForRemoteChain[remoteChainId]"),
            "CCIP config resolves the per-route deployer"
        );
        assertTrue(_contains(ccipEdgeSource, "localToken: JBConstants.NATIVE_TOKEN"), "CCIP config maps native");
        assertTrue(
            _contains(ccipEdgeSource, "remoteToken: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))"),
            "CCIP config maps to remote native"
        );
    }

    function test_routerlessChainsDoNotRequireRouterTerminalInReplayGuard() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory terminalGuard = _section({
            haystack: deploySource,
            startNeedle: "function _terminalConfigIsCanonical(",
            endNeedle: "function _projectTokenSymbolIs("
        });

        assertTrue(
            _contains(terminalGuard, "address(_routerTerminalRegistry) != address(0)"),
            "guard branches on deployed router registry"
        );
        assertTrue(_contains(terminalGuard, "terminals.length != 1"), "routerless chains require only one terminal");
        assertTrue(_contains(terminalGuard, "terminals[0] != _terminal"), "routerless terminal must be JBMultiTerminal");
    }

    function test_defifaStartTimePinnedBeforeSphinxPerChainCollection() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory packageJson = vm.readFile("package.json");
        string memory anchorSource = _section({
            haystack: deploySource,
            startNeedle: "function _initializeDeploymentAnchors()",
            endNeedle: "function _setupChainAddresses()"
        });

        assertTrue(_contains(anchorSource, 'vm.envOr({name: "DEFIFA_REV_START_TIME"'), "deploy reads pinned anchor");
        assertTrue(
            _contains(packageJson, "DEFIFA_REV_START_TIME=$(($(date +%s) + 86400)) npx sphinx propose"),
            "proposal scripts pin one anchor before Sphinx loops chains"
        );
    }

    function test_reservedProjectDeploymentPathsUseExplicitIds() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");

        string memory reserveSource = _section({
            haystack: deploySource,
            startNeedle: "function _reserveCanonicalProjectIds()",
            endNeedle: "function _deployEthUsdFeed()"
        });
        string memory bannySource = _section({
            haystack: deploySource, startNeedle: "function _deployBanny()", endNeedle: "function _registerBannyDrop1()"
        });
        string memory defifaSource = _section({
            haystack: deploySource, startNeedle: "function _deployDefifaRevnet()", endNeedle: "function _deployArt()"
        });
        string memory artSource = _section({
            haystack: deploySource, startNeedle: "function _deployArt()", endNeedle: "function _deployMarkee()"
        });
        string memory markeeSource = _section({
            haystack: deploySource,
            startNeedle: "function _deployMarkee()",
            endNeedle: "function _deployProjectHandles()"
        });
        string memory ensureSource = _section({
            haystack: deploySource, startNeedle: "function _ensureProjectExists(", endNeedle: "function _isDeployed("
        });

        assertTrue(_contains(deploySource, "_reserveCanonicalProjectIds();"), "core deploy reserves project IDs");
        assertTrue(_contains(reserveSource, "_projects.count() < _MARKEE_PROJECT_ID"), "reservation runs through ID 7");
        assertTrue(_contains(reserveSource, "createFor{value: _projects.creationFee()}"), "reservations pay mint fee");
        assertFalse(_contains(bannySource, "deployFor{value:"), "Banny uses reserved project ID");
        assertFalse(_contains(defifaSource, "deployFor{value:"), "DEFIFA uses reserved project ID");
        assertFalse(_contains(artSource, "deployFor{value:"), "ART uses reserved project ID");
        assertFalse(_contains(markeeSource, "deployFor{value:"), "MARKEE uses reserved project ID");
        assertTrue(_contains(bannySource, "revnetId: _BAN_PROJECT_ID"), "Banny initializes reserved ID");
        assertTrue(_contains(defifaSource, "revnetId: _DEFIFA_REV_PROJECT_ID"), "DEFIFA initializes reserved ID");
        assertTrue(_contains(artSource, "revnetId: _ART_PROJECT_ID"), "ART initializes reserved ID");
        assertTrue(_contains(markeeSource, "revnetId: _MARKEE_PROJECT_ID"), "MARKEE initializes reserved ID");
        assertTrue(_contains(artSource, "createFor{value: _projects.creationFee()}"), "ART fallback pays mint fee");
        assertTrue(_contains(ensureSource, "createFor{value: _projects.creationFee()}"), "blank projects pay mint fee");
    }

    function test_directLaunchPackagesForwardCreationFee() public view {
        string memory hookSource =
            vm.readFile("node_modules/@bananapus/721-hook-v6/src/JB721TiersHookProjectDeployer.sol");
        string memory defifaSource = vm.readFile("node_modules/@ballkidz/defifa/src/DefifaDeployer.sol");

        assertTrue(_contains(hookSource, "external\n        payable\n        override"), "721 launch is payable");
        assertTrue(
            _contains(hookSource, "projects.createFor{value: msg.value}(address(this))"),
            "721 launch forwards creation fee"
        );
        assertTrue(_contains(defifaSource, "external\n        payable\n        override"), "Defifa launch is payable");
        assertTrue(
            _contains(defifaSource, "CONTROLLER.PROJECTS().createFor{value: msg.value}(address(this))"),
            "Defifa launch forwards creation fee"
        );
    }

    function test_defaultProjectCreationFeeRoutesToNanaPayer() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory verifySource = vm.readFile("script/Verify.s.sol");

        string memory deployFlow = _section({
            haystack: deploySource,
            startNeedle: "_deployProjectPayerDeployer();",
            endNeedle: "_finalizeCriticalOwnership();"
        });
        string memory feeConfig = _section({
            haystack: deploySource,
            startNeedle: "function _configureProjectCreationFee()",
            endNeedle: "function _projectCreationFeeReceiverIsCanonical("
        });
        string memory canonicalCheck = _section({
            haystack: deploySource,
            startNeedle: "function _projectCreationFeeReceiverIsCanonical(",
            endNeedle: "function _buildSuckerConfig("
        });

        assertTrue(_contains(deployFlow, "_configureProjectCreationFee();"), "fee is configured before handoff");
        assertTrue(_contains(deploySource, "PROJECT_CREATION_FEE = 0.0001 ether"), "fee constant is 0.0001 ETH");
        assertTrue(_contains(feeConfig, "deployProjectPayer"), "fee receiver is a project payer clone");
        assertTrue(_contains(feeConfig, "defaultProjectId: _FEE_PROJECT_ID"), "fee payer routes to NANA");
        assertTrue(_contains(feeConfig, "defaultAddToBalance: true"), "fee payer adds balance without minting");
        assertTrue(_contains(feeConfig, "_projects.setCreationFee"), "JBProjects fee is configured");
        assertTrue(_contains(canonicalCheck, "defaultProjectId()"), "canonical check pins payer project");
        assertTrue(_contains(canonicalCheck, "defaultAddToBalance()"), "canonical check pins add-to-balance");
        assertTrue(
            _contains(deploySource, "JBProjectPayer__ProjectCreationFeeReceiver"), "fee payer is emitted in dump"
        );
        assertTrue(_contains(verifySource, "_verifyProjectCreationFee();"), "post-deploy verifier checks fee");
        assertTrue(_contains(verifySource, "JBProjects creation fee == 0.0001 ETH"), "verifier checks amount");
        assertTrue(
            _contains(verifySource, "Creation fee payer default project == NANA"), "verifier checks payer routing"
        );
    }

    function _assertStrictConfiguredRevnetGuard(
        string memory deployFunctionSource,
        string memory projectIdName,
        string memory expectedSymbol,
        string memory expectedUri
    )
        internal
        pure
    {
        assertTrue(_contains(deployFunctionSource, "_encodedConfigurationHashOf"), "expected config hash is computed");
        assertTrue(_contains(deployFunctionSource, "_isCanonicalRevnetProject"), "strict guard is used");
        assertTrue(
            _contains(deployFunctionSource, string.concat("projectId: ", projectIdName)),
            "guard checks the intended project"
        );
        assertTrue(
            _contains(deployFunctionSource, string.concat('expectedSymbol: "', expectedSymbol, '"')),
            "guard checks token symbol"
        );
        assertTrue(
            _contains(deployFunctionSource, "expectedConfigurationHash: expectedConfigurationHash"),
            "guard passes exact config hash"
        );
        assertTrue(_contains(deployFunctionSource, "expectedOperator: operator"), "guard passes expected operator");
        assertFalse(
            _contains(deployFunctionSource, "_requireRevnetOperatorCanSetSuckerPeer"),
            "deploy must not require an unnecessary SET_SUCKER_PEER operator grant after launch"
        );
        assertTrue(
            _contains(deployFunctionSource, string.concat("expectedUri: ", expectedUri)), "guard passes expected URI"
        );
        assertTrue(
            _contains(deployFunctionSource, "expectedReservedSplitBeneficiary: payable(operator)"),
            "guard passes expected reserved split beneficiary"
        );
    }

    function _section(
        string memory haystack,
        string memory startNeedle,
        string memory endNeedle
    )
        internal
        pure
        returns (string memory)
    {
        bytes memory h = bytes(haystack);
        uint256 start = _indexOf(haystack, startNeedle);
        uint256 end = _indexOfFrom(haystack, endNeedle, start);
        require(end >= start, "invalid section");

        bytes memory out = new bytes(end - start);
        for (uint256 i; i < out.length; i++) {
            out[i] = h[start + i];
        }
        return string(out);
    }

    function _indexOf(string memory haystack, string memory needle) internal pure returns (uint256) {
        return _indexOfFrom(haystack, needle, 0);
    }

    function _indexOfFrom(string memory haystack, string memory needle, uint256 start) internal pure returns (uint256) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        require(n.length != 0, "empty needle");
        require(n.length <= h.length, "needle too long");

        for (uint256 i = start; i <= h.length - n.length; i++) {
            bool matched = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) return i;
        }

        revert("needle not found");
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
