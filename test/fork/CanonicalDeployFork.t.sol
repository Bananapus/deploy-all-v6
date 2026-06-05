// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./DeployFullStack.t.sol";

import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";
import {REVOwner} from "@rev-net/core-v6/src/REVOwner.sol";
import {REVDeployer} from "@rev-net/core-v6/src/REVDeployer.sol";
import {IREVDeployer} from "@rev-net/core-v6/src/interfaces/IREVDeployer.sol";
import {IREVLoans} from "@rev-net/core-v6/src/interfaces/IREVLoans.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";
import {IJBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/interfaces/IJBBuybackHookRegistry.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {CTPublisher} from "@croptop/core-v6/src/CTPublisher.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";

/// @notice Mints the CANONICAL project cohort (IDs 1-7) on a fresh, real Juicebox deployment using the actual
/// `REVDeployer`, at the real project IDs and currency denominations the production deploy uses — the structural
/// fidelity gap the synthetic per-test revnets miss. Sucker configs and auto-issuance premints are zeroed (the two
/// documented fork-deploy revert risks); ART (6) is the Base-only project, so on an Ethereum fork it is a bare
/// placeholder transferred to the ART operator (no revnet), exactly as `Deploy.s.sol` does off-Base.
///
/// Built on `DeployFullStackBase` (real Phase 01-05 deployment) + the real revnet infrastructure (REVLoans / REVOwner /
/// REVDeployer). This is the foundation future canonical-cohort tests can build on.
///
/// Run with: forge test --match-contract CanonicalDeployForkTest -vvv
contract CanonicalDeployForkTest is DeployFullStackBase {
    uint256 internal constant NANA = 1;
    uint256 internal constant CPN = 2;
    uint256 internal constant REV = 3;
    uint256 internal constant BAN = 4;
    uint256 internal constant DEFIFA = 5;
    uint256 internal constant ART = 6;
    uint256 internal constant MARKEE = 7;

    address internal constant ART_OPERATOR = 0xbB96A6D3D251dFDA76F96d1650f9Cfd53b41c8d1;

    REVLoans internal _revLoans;
    REVOwner internal _revOwner;
    REVDeployer internal _revDeployer;

    bool internal _deployed;

    function setUp() public {
        ChainConfig memory cfg = _ethereumConfig();
        if (!_tryCreateFork(cfg)) {
            return; // no RPC: tests vm.skip individually
        }
        _deployed = true;

        _runFullDeployment(cfg);
        _reserveCanonicalProjectIds();
        _deployRevnetInfrastructure();

        // Canonical projects in the script's deploy order.
        _deployEthRevnet(REV, "REV", "$REV");
        _deployEthRevnet(CPN, "CPN", "$CPN");
        _deployEthRevnet(NANA, "NANA", "$NANA");
        _deployEthRevnet(BAN, "BAN", "$BAN");
        _deployEthRevnet(DEFIFA, "DEFIFA", "$DEFIFA");
        _deployArtPlaceholder();
        _deployEthRevnet(MARKEE, "MARKEE", "$MARKEE");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Infrastructure + reservation
    // ═══════════════════════════════════════════════════════════════════

    function _reserveCanonicalProjectIds() internal {
        vm.deal(_deployer, 100 ether);
        vm.startPrank(_deployer);
        while (_projects.count() < MARKEE) {
            _projects.createFor{value: _projects.creationFee()}(_deployer);
        }
        vm.stopPrank();
    }

    function _deployRevnetInfrastructure() internal {
        vm.startPrank(_deployer);
        _revLoans = new REVLoans(
            _controller,
            _terminal,
            IJBSuckerRegistry(address(_suckerRegistry)),
            REV,
            _deployer,
            _PERMIT2,
            _trustedForwarder
        );
        _revOwner = new REVOwner(
            IJBBuybackHookRegistry(address(_buybackRegistry)),
            _directory,
            REV,
            IJBSuckerRegistry(address(_suckerRegistry)),
            _revLoans,
            _deployer
        );
        _revDeployer = new REVDeployer(
            _controller,
            _terminal,
            IJBTerminal(address(_routerTerminalRegistry)),
            IJBSuckerRegistry(address(_suckerRegistry)),
            REV,
            IJB721TiersHookDeployer(address(_hookDeployer)),
            CTPublisher(address(0)),
            IJBBuybackHookRegistry(address(_buybackRegistry)),
            _revLoans,
            _trustedForwarder,
            address(_revOwner)
        );
        _revOwner.setDeployer(IREVDeployer(address(_revDeployer)));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Per-project deployment
    // ═══════════════════════════════════════════════════════════════════

    function _emptySucker(bytes32 salt) internal pure returns (REVSuckerDeploymentConfig memory) {
        return REVSuckerDeploymentConfig({deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: salt});
    }

    function _oneStage(uint112 issuance, uint16 cashOutTaxRate) internal view returns (REVStageConfig[] memory stages) {
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(_deployer),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });
        stages = new REVStageConfig[](1);
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 0,
            splits: splits,
            initialIssuance: issuance,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: cashOutTaxRate,
            extraMetadata: 0
        });
    }

    function _deployEthRevnet(uint256 id, string memory name, string memory ticker) internal {
        REVConfig memory cfg = REVConfig({
            description: REVDescription(name, ticker, "ipfs://canonical", bytes32(id)),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            operator: _deployer,
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: _oneStage(uint112(1000e18), 2000)
        });
        JBAccountingContext[] memory tc = new JBAccountingContext[](1);
        tc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        _deployAt(id, cfg, tc);
    }

    function _deployAt(uint256 id, REVConfig memory cfg, JBAccountingContext[] memory tc) internal {
        vm.startPrank(_deployer);
        _projects.approve(address(_revDeployer), id);
        _revDeployer.deployFor(id, cfg, tc, _emptySucker(bytes32(id)));
        vm.stopPrank();
    }

    function _deployArtPlaceholder() internal {
        // ART is Base-only; on an Ethereum fork it is a bare project transferred to the ART operator (no revnet).
        vm.prank(_deployer);
        _projects.safeTransferFrom(_deployer, ART_OPERATOR, ART);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Assertions
    // ═══════════════════════════════════════════════════════════════════

    function test_canonical_cohortDeployed() public {
        if (!_deployed) {
            vm.skip(true);
            return;
        }

        // Revnet projects: owned by REVOwner, controlled by the controller, with a deployed ERC20.
        uint256[6] memory revnets = [NANA, CPN, REV, BAN, DEFIFA, MARKEE];
        for (uint256 i; i < revnets.length; ++i) {
            uint256 id = revnets[i];
            assertEq(_projects.ownerOf(id), address(_revOwner), "revnet owned by REVOwner");
            assertEq(address(_directory.controllerOf(id)), address(_controller), "revnet controlled by the controller");
            assertTrue(address(_tokens.tokenOf(id)) != address(0), "revnet has an ERC20 token");
        }

        // ART (6) is the Base-only placeholder: owned by the ART operator, no controller.
        assertEq(_projects.ownerOf(ART), ART_OPERATOR, "ART placeholder owned by the ART operator");
        assertEq(address(_directory.controllerOf(ART)), address(0), "ART has no controller on an Ethereum fork");
    }

    function test_canonical_denominationsAndInfra() public {
        if (!_deployed) {
            vm.skip(true);
            return;
        }

        // ETH revnets, including DEFIFA, price in native.
        assertEq(
            _terminal.accountingContextForTokenOf(NANA, JBConstants.NATIVE_TOKEN).decimals, 18, "NANA accepts native"
        );
        JBAccountingContext memory defifaCtx = _terminal.accountingContextForTokenOf(DEFIFA, JBConstants.NATIVE_TOKEN);
        assertEq(defifaCtx.token, JBConstants.NATIVE_TOKEN, "DEFIFA accepts native");
        assertEq(defifaCtx.decimals, 18, "DEFIFA native context is 18-decimal");

        // Revnet infrastructure is consistently wired.
        assertEq(address(_revOwner.deployer()), address(_revDeployer), "REVOwner bound to the deployer");
        assertEq(address(_revLoans.CONTROLLER()), address(_controller), "REVLoans bound to the controller");
    }
}
