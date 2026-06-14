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
            _contains(deploySource, '"ipfs://Qmb3Fo96jFFEj4jGJPXn5uNMTS6s21Kzq7cjbzpRdAoGCq"'), "DEFIFA URI is pinned"
        );
        assertTrue(
            _contains(deploySource, '"ipfs://QmNaP7LAFYwUcFUQrext1tZmhCHkHDrfrbqXbt7MZqmM9S"'), "ART URI is pinned"
        );
        assertTrue(
            _contains(deploySource, '"ipfs://QmWgNJGFLZZdVCn5PuUEDBkSa7iL8jgFVKgJq93Aqub56E"'), "MARKEE URI is pinned"
        );

        _assertStrictConfiguredRevnetGuard({
            deployFunctionSource: revSource,
            projectIdName: "_revProjectId",
            expectedSymbol: "REV",
            expectedUri: '"ipfs://QmS4bAGss85An49HmoYKKdD16YJyoz5JDPQQEgwbzuBBdz"'
        });
        _assertStrictConfiguredRevnetGuard({
            deployFunctionSource: cpnSource,
            projectIdName: "_cpnProjectId",
            expectedSymbol: "CPN",
            expectedUri: '"ipfs://QmPsD6FVrvAxsXYzNMyR6pHHa6wiJ9vrfe4YRU8ZhPcXHA"'
        });
        _assertStrictConfiguredRevnetGuard({
            deployFunctionSource: defifaSource,
            projectIdName: "_DEFIFA_REV_PROJECT_ID",
            expectedSymbol: "DGN",
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

    function test_opSepoliaUsesCurrentUniswapV3Factory() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory verifySource = vm.readFile("script/Verify.s.sol");
        string memory deployOpSepolia =
            _section({haystack: deploySource, startNeedle: "// Optimism Sepolia", endNeedle: "// Base"});
        string memory verifyV3Factory = _section({
            haystack: verifySource,
            startNeedle: "function _expectedV3Factory()",
            endNeedle: "function _expectedV4PoolManager()"
        });
        string memory verifyOpSepolia = _section({
            haystack: verifyV3Factory,
            startNeedle: "if (block.chainid == 11_155_420)",
            endNeedle: "if (block.chainid == 8453)"
        });
        string memory verifyBaseSepolia = _section({
            haystack: verifyV3Factory,
            startNeedle: "if (block.chainid == 84_532)",
            endNeedle: "if (block.chainid == 42_161)"
        });

        assertTrue(
            _contains(deployOpSepolia, "_v3Factory = 0x8CE191193D15ea94e11d327b4c7ad8bbE520f6aF"),
            "OP Sepolia deploy constant must use the current Uniswap V3 factory"
        );
        assertFalse(
            _contains(deployOpSepolia, "_v3Factory = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24"),
            "OP Sepolia must not use the SDK-core fallback V3 factory"
        );
        assertTrue(
            _contains(verifyOpSepolia, "return 0x8CE191193D15ea94e11d327b4c7ad8bbE520f6aF"),
            "verifier OP Sepolia V3 factory must match deploy"
        );
        assertFalse(
            _contains(verifyOpSepolia, "return 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24"),
            "verifier OP Sepolia V3 factory must not use the Base Sepolia value"
        );
        assertTrue(
            _contains(verifyBaseSepolia, "return 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24"),
            "Base Sepolia still uses its own canonical V3 factory"
        );
    }

    function test_defifaStartTimePinnedBeforeSphinxPerChainCollection() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory packageJson = vm.readFile("package.json");
        string memory anchorSource = _section({
            haystack: deploySource,
            startNeedle: "function _initializeDeploymentAnchors()",
            endNeedle: "function _setupChainAddresses()"
        });
        string memory defifaSource = _section({
            haystack: deploySource, startNeedle: "function _deployDefifaRevnet()", endNeedle: "function _deployArt()"
        });

        assertTrue(_contains(anchorSource, 'vm.envOr({name: "DEFIFA_REV_START_TIME"'), "deploy reads pinned anchor");
        assertTrue(
            _contains(anchorSource, "require(scriptedStartTime != 0"),
            "deploy fails closed when the anchor env var is unset"
        );
        assertFalse(
            _contains(anchorSource, "block.timestamp + 1 days"),
            "deploy must not fall back to a per-chain timestamp (it diverges the cross-chain sucker config hash)"
        );
        assertTrue(
            _contains(packageJson, "bash script/propose-deploy.sh testnets"),
            "testnet proposal script uses the anchor-persisting helper"
        );
        assertTrue(
            _contains(packageJson, "bash script/propose-deploy.sh mainnets"),
            "mainnet proposal script uses the anchor-persisting helper"
        );

        string memory proposeScript = vm.readFile("script/propose-deploy.sh");
        assertTrue(_contains(proposeScript, "DEFIFA_REV_START_TIME"), "proposal helper pins the DEFIFA anchor");
        assertTrue(
            _contains(proposeScript, "DEFAULT_DEFIFA_REV_START_DELAY_SECONDS=604800"),
            "proposal helper defaults the DEFIFA anchor to a seven-day lead"
        );
        assertTrue(
            _contains(proposeScript, "MIN_DEFIFA_REV_START_LEAD_SECONDS=259200"),
            "proposal helper rejects too-short DEFIFA start leads"
        );
        assertTrue(
            _contains(proposeScript, "defifa-rev-start-time-${NETWORKS}.env"),
            "proposal helper persists the anchor for post-deploy"
        );
        assertTrue(
            _contains(deploySource, "DEFIFA_REV_MIN_START_LEAD = 3 days"),
            "deploy script encodes the DEFIFA proposal lead-time floor"
        );
        assertTrue(
            _contains(defifaSource, "defifaStage0Start >= block.timestamp + DEFIFA_REV_MIN_START_LEAD"),
            "new DEFIFA configs require a material lead time during proposal collection"
        );

        string memory postDeployScript = vm.readFile("script/post-deploy.sh");
        assertTrue(
            _contains(postDeployScript, "load_defifa_rev_start_time"), "post-deploy loads the persisted DEFIFA anchor"
        );
        assertTrue(
            _contains(postDeployScript, "DEFIFA_REV_START_TIME is required for address dumping"),
            "post-deploy fails closed when the exact anchor is unavailable"
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

    function test_finalOwnershipHandoffFailsClosedOnUnexpectedOwners() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory finalizer = _section({
            haystack: deploySource,
            startNeedle: "function _finalizeCriticalOwnership()",
            endNeedle: "function _ownableOwnerOf("
        });

        assertTrue(
            _contains(deploySource, "Deploy_OwnershipHandoffUnexpectedOwner"),
            "deploy exposes an unexpected Ownable owner error"
        );
        assertTrue(
            _contains(deploySource, "Deploy_ProjectOwnershipHandoffUnexpectedOwner"),
            "deploy exposes an unexpected project owner error"
        );
        assertTrue(_contains(finalizer, "currentOwner == newOwner"), "handoff is idempotent once finalized");
        assertTrue(
            _contains(finalizer, "currentOwner != safeAddress()"),
            "handoff rejects a third-party owner instead of silently skipping"
        );
        assertTrue(
            _contains(finalizer, "_ownableOwnerOf(target) != newOwner"), "handoff confirms Ownable transfer success"
        );
        assertTrue(
            _contains(finalizer, "_projects.ownerOf(projectId) != newOwner"),
            "handoff confirms project transfer success"
        );
    }

    function test_bannyDropResumeRepairsMetadataAndFinalizerChecksOperator() public view {
        string memory deploySource = vm.readFile("script/Deploy.s.sol");
        string memory drop1 = _section({
            haystack: deploySource, startNeedle: "function _registerBannyDrop1()", endNeedle: "function _drop1Tier("
        });
        string memory drop2 = _section({
            haystack: deploySource,
            startNeedle: "function _registerBannyDrop2()",
            endNeedle: "function _finalizeBannyOwnership()"
        });
        string memory metadataHelper = _section({
            haystack: deploySource,
            startNeedle: "function _ensureBannyProductMetadata(",
            endNeedle: "function _sequentialIds("
        });
        string memory bannyFinalizer = _section({
            haystack: deploySource,
            startNeedle: "function _finalizeBannyOwnership()",
            endNeedle: "function _finalizeCriticalOwnership()"
        });

        assertFalse(_contains(drop1, "if (maxBefore >= 51) return;"), "Drop 1 must not skip metadata repair");
        assertFalse(_contains(drop2, "if (maxBefore >= 68) return;"), "Drop 2 must not skip metadata repair");
        assertTrue(
            _contains(drop1, "_ensureBannyProductMetadata"), "Drop 1 reruns metadata verification after tiers exist"
        );
        assertTrue(
            _contains(drop2, "_ensureBannyProductMetadata"), "Drop 2 reruns metadata verification after tiers exist"
        );
        assertTrue(_contains(metadataHelper, "resolver.svgHashOf"), "metadata helper reads committed SVG hashes");
        assertTrue(
            _contains(metadataHelper, "existingHash != svgHashes[i]"), "metadata helper rejects wrong committed hashes"
        );
        assertTrue(
            _contains(metadataHelper, "resolver.setSvgHashesOf"), "metadata helper writes only missing SVG hashes"
        );
        assertTrue(
            _contains(metadataHelper, "resolver.setProductNames"),
            "metadata helper can repair product names while the safe owns the resolver"
        );
        assertTrue(
            _contains(bannyFinalizer, "resolverOwner == _BAN_OPS_OPERATOR"),
            "Banny finalizer recognizes completed resolver ownership"
        );
        assertTrue(
            _contains(bannyFinalizer, "isOperatorOf({revnetId: _BAN_PROJECT_ID, addr: _BAN_OPS_OPERATOR})"),
            "Banny finalizer proves the operator handoff too"
        );
        assertTrue(
            _contains(bannyFinalizer, "Deploy_BannyOperatorHandoffIncomplete"),
            "Banny finalizer fails closed on partial operator handoff"
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
