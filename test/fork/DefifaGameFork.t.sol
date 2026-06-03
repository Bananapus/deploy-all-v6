// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../helpers/RevnetForkBase.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";

import {DefifaDeployer} from "@ballkidz/defifa/src/DefifaDeployer.sol";
import {DefifaHook} from "@ballkidz/defifa/src/DefifaHook.sol";
import {DefifaTokenUriResolver} from "@ballkidz/defifa/src/DefifaTokenUriResolver.sol";
import {DefifaGovernor} from "@ballkidz/defifa/src/DefifaGovernor.sol";
import {IDefifaGovernor} from "@ballkidz/defifa/src/interfaces/IDefifaGovernor.sol";
import {DefifaLaunchProjectData} from "@ballkidz/defifa/src/structs/DefifaLaunchProjectData.sol";
import {DefifaTierParams} from "@ballkidz/defifa/src/structs/DefifaTierParams.sol";

/// @notice Verifies that a Defifa game can be launched with organizer/community splits when the DEFIFA fee project is a
/// revnet (owned by REVOwner) and the DefifaDeployer holds no `SET_SPLIT_GROUPS` permission on it. The commitment
/// splits (organizer/community cut + DEFIFA fee + base-protocol fee) are applied on the per-GAME project
/// (deployer-owned) by `_buildSplits`; the deployer never needs to set splits on the shared DEFIFA project.
///
/// This test stands up the Defifa stack exactly as `Deploy.s.sol` _deployDefifa does (DefifaHook over the DEFIFA
/// revnet token + the base/fee project token, resolver, governor handed to the deployer, no SET_SPLIT_GROUPS grant) and
/// pins that a game launched WITH splits launches successfully, and a no-splits game still launches.
///
/// Run with: forge test --match-contract DefifaGameForkTest -vvv
contract DefifaGameForkTest is RevnetForkBase {
    DefifaDeployer internal defifaDeployer;
    uint256 internal defifaRevnetId;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "Defifa_Splits";
    }

    function _setUpDefifaStack() internal {
        // BASE_PROTOCOL_PROJECT_ID = the fee project (project 1 analogue); DEFIFA_PROJECT_ID = a real revnet (project 5
        // analogue), owned by REVOwner — exactly the canonical ownership shape.
        _deployFeeProject(1000);
        defifaRevnetId = _deployRevnet(1000);
        assertEq(
            jbProjects().ownerOf(defifaRevnetId), address(REV_OWNER), "DEFIFA revnet owned by REVOwner (canonical)"
        );

        IERC20 defifaToken = IERC20(address(jbTokens().tokenOf(defifaRevnetId)));
        IERC20 baseToken = IERC20(address(jbTokens().tokenOf(FEE_PROJECT_ID)));
        assertTrue(address(defifaToken) != address(0) && address(baseToken) != address(0), "revnet tokens exist");

        DefifaHook hook = new DefifaHook(jbDirectory(), defifaToken, baseToken);
        DefifaTokenUriResolver resolver = new DefifaTokenUriResolver(address(this));
        DefifaGovernor governor = new DefifaGovernor(jbController(), address(this));

        defifaDeployer = new DefifaDeployer(
            address(hook),
            resolver,
            IDefifaGovernor(address(governor)),
            jbController(),
            ADDRESS_REGISTRY,
            defifaRevnetId,
            FEE_PROJECT_ID,
            HOOK_STORE
        );
        // Mirror Deploy.s.sol: governor ownership goes to the deployer so it can initialize games.
        governor.transferOwnership(address(defifaDeployer));

        // CRITICAL — mirror Deploy.s.sol: the DefifaDeployer is NEVER granted SET_SPLIT_GROUPS on the DEFIFA revnet.
        assertFalse(
            jbPermissions()
                .hasPermission({
                operator: address(defifaDeployer),
                account: address(REV_OWNER),
                projectId: defifaRevnetId,
                permissionId: JBPermissionIds.SET_SPLIT_GROUPS,
                includeRoot: true,
                includeWildcardProjectId: true
            }),
            "DefifaDeployer must NOT hold SET_SPLIT_GROUPS (canonical un-granted state)"
        );
    }

    function _launchData(bool withSplits) internal view returns (DefifaLaunchProjectData memory data) {
        JBSplit[] memory splits = new JBSplit[](withSplits ? 1 : 0);
        if (withSplits) {
            splits[0] = JBSplit({
                preferAddToBalance: false,
                percent: 1000, // 1% — an organizer/community cut
                projectId: 0,
                beneficiary: payable(address(0xBEEF)),
                lockedUntil: 0,
                hook: IJBSplitHook(address(0))
            });
        }

        DefifaTierParams[] memory tiers = new DefifaTierParams[](1);
        tiers[0] = DefifaTierParams({
            name: "Team A",
            reservedRate: 0,
            reservedTokenBeneficiary: address(0),
            encodedIpfsUri: bytes32(0),
            shouldUseReservedTokenBeneficiaryAsDefault: false
        });

        data = DefifaLaunchProjectData({
            name: "Splits Game",
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
            splits: splits,
            attestationStartTime: 0,
            attestationGracePeriod: 1 days,
            defaultAttestationDelegate: address(0),
            defaultTokenUriResolver: IJB721TokenUriResolver(address(0)),
            terminal: IJBTerminal(address(jbMultiTerminal())),
            minParticipation: 0,
            scorecardTimeout: 7 days,
            timelockDuration: 0
        });
    }

    /// @notice A Defifa game launched WITH splits launches successfully without any SET_SPLIT_GROUPS grant on the
    /// revnet-owned DEFIFA fee project. The organizer/community + fee splits are applied on the GAME project (which the
    /// deployer owns) by `_buildSplits`, so the launch must not revert with a permission error.
    function test_defifa_splitsGameLaunches() public {
        _setUpDefifaStack();

        // Sanity: still NO SET_SPLIT_GROUPS grant to the deployer — the fix must not depend on one.
        assertFalse(
            jbPermissions()
                .hasPermission({
                operator: address(defifaDeployer),
                account: address(REV_OWNER),
                projectId: defifaRevnetId,
                permissionId: JBPermissionIds.SET_SPLIT_GROUPS,
                includeRoot: true,
                includeWildcardProjectId: true
            }),
            "no SET_SPLIT_GROUPS grant exists"
        );

        uint256 gameId = defifaDeployer.launchGameWith(_launchData({withSplits: true}));
        assertGt(gameId, 0, "splits game launches without any SET_SPLIT_GROUPS grant");
        // The game project is owned by the deployer (created via createFor(address(this))).
        assertEq(jbProjects().ownerOf(gameId), address(defifaDeployer), "deployer owns the game project");
    }

    /// @notice A no-splits game still launches (unchanged path).
    function test_defifa_noSplitsGameLaunches() public {
        _setUpDefifaStack();
        uint256 gameId = defifaDeployer.launchGameWith(_launchData({withSplits: false}));
        assertGt(gameId, 0, "no-splits game launches");
    }
}
