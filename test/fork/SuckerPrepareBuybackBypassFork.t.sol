// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";

import {IJBSucker} from "@bananapus/suckers-v6/src/interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerDeployer.sol";
import {IOPMessenger} from "@bananapus/suckers-v6/src/interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "@bananapus/suckers-v6/src/interfaces/IOPStandardBridge.sol";
import {JBOptimismSucker} from "@bananapus/suckers-v6/src/JBOptimismSucker.sol";
import {JBOptimismSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBOptimismSuckerDeployer.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";
import {JBTokenMapping} from "@bananapus/suckers-v6/src/structs/JBTokenMapping.sol";

import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";

contract SuckerPrepareBypassMockOPMessenger {
    address public xDomainMessageSender;

    function setXDomainMessageSender(address sender) external {
        xDomainMessageSender = sender;
    }

    function sendMessage(address, bytes calldata, uint32) external payable {}
}

contract SuckerPrepareBypassMockOPBridge {
    function bridgeETHTo(address, uint32, bytes calldata) external payable {}

    function bridgeERC20To(address, address, address, uint256, uint32, bytes calldata) external {}
}

/// @notice Proves real sucker prepare() cash-outs bypass the sell-side buyback hook path.
contract SuckerPrepareBuybackBypassForkTest is RevnetForkBase {
    error BuybackHookWasCalled();

    address internal TOKEN_HOLDER = makeAddr("tokenHolder");
    address internal REGULAR_HOLDER = makeAddr("regularHolder");

    JBOptimismSuckerDeployer internal opSuckerDeployer;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_SuckerPrepareBypass";
    }

    function setUp() public override {
        super.setUp();

        vm.deal(TOKEN_HOLDER, 100 ether);
        vm.deal(REGULAR_HOLDER, 100 ether);

        SuckerPrepareBypassMockOPMessenger messenger = new SuckerPrepareBypassMockOPMessenger();
        SuckerPrepareBypassMockOPBridge bridge = new SuckerPrepareBypassMockOPBridge();

        opSuckerDeployer = new JBOptimismSuckerDeployer({
            directory: jbDirectory(),
            permissions: jbPermissions(),
            tokens: jbTokens(),
            configurator: address(this),
            trustedForwarder: address(0)
        });
        opSuckerDeployer.setChainSpecificConstants({
            messenger: IOPMessenger(address(messenger)), bridge: IOPStandardBridge(address(bridge))
        });

        JBOptimismSucker singleton = new JBOptimismSucker({
            deployer: opSuckerDeployer,
            directory: jbDirectory(),
            permissions: jbPermissions(),
            tokens: jbTokens(),
            feeProjectId: FEE_PROJECT_ID,
            registry: SUCKER_REGISTRY,
            trustedForwarder: address(0)
        });
        opSuckerDeployer.configureSingleton(singleton);

        vm.prank(multisig());
        SUCKER_REGISTRY.allowSuckerDeployer(address(opSuckerDeployer));
    }

    function _suckerDeploymentConfig() internal view returns (REVSuckerDeploymentConfig memory config) {
        JBTokenMapping[] memory mappings = new JBTokenMapping[](1);
        mappings[0] = JBTokenMapping({
            localToken: JBConstants.NATIVE_TOKEN,
            minGas: 200_000,
            remoteToken: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
        });

        JBSuckerDeployerConfig[] memory deployerConfigs = new JBSuckerDeployerConfig[](1);
        deployerConfigs[0] = JBSuckerDeployerConfig({
            deployer: IJBSuckerDeployer(address(opSuckerDeployer)), peer: bytes32(0), mappings: mappings
        });

        config = REVSuckerDeploymentConfig({deployerConfigurations: deployerConfigs, salt: keccak256("PREPARE_BYPASS")});
    }

    function _deployRevnetWithSucker(uint16 cashOutTaxRate) internal returns (uint256 revnetId, address sucker) {
        (REVConfig memory cfg, JBAccountingContext[] memory terminals,) = _buildNativeConfig(cashOutTaxRate);

        (revnetId,) = REV_DEPLOYER.deployFor({
            revnetId: 0,
            configuration: cfg,
            accountingContextsToAccept: terminals,
            suckerDeploymentConfiguration: _suckerDeploymentConfig()
        });

        address[] memory suckers = SUCKER_REGISTRY.suckersOf(revnetId);
        assertEq(suckers.length, 1, "revnet should deploy one sucker");
        sucker = suckers[0];
        assertTrue(SUCKER_REGISTRY.isSuckerOf(revnetId, sucker), "sucker should be registered");
    }

    function test_suckerPrepareBypassesSellSideBuybackHook() public {
        _deployFeeProject(5000);
        (uint256 revnetId, address sucker) = _deployRevnetWithSucker(7000);

        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        uint256 tokenHolderTokens = _payRevnet(revnetId, TOKEN_HOLDER, 10 ether);
        uint256 regularHolderTokens = _payRevnet(revnetId, REGULAR_HOLDER, 1 ether);
        address projectToken = address(jbTokens().tokenOf(revnetId));

        vm.mockCallRevert(
            address(BUYBACK_HOOK),
            abi.encodeWithSelector(IJBRulesetDataHook.beforeCashOutRecordedWith.selector),
            abi.encodeWithSelector(BuybackHookWasCalled.selector)
        );

        vm.prank(REGULAR_HOLDER);
        vm.expectRevert(BuybackHookWasCalled.selector);
        jbMultiTerminal()
            .cashOutTokensOf({
            holder: REGULAR_HOLDER,
            projectId: revnetId,
            cashOutCount: regularHolderTokens / 2,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(REGULAR_HOLDER),
            metadata: ""
        });

        uint256 prepareCount = tokenHolderTokens / 2;
        uint256 localSurplusBefore = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        uint256 totalSupplyBefore = jbTokens().totalSupplyOf(revnetId);
        uint256 suckerEthBefore = sucker.balance;

        vm.prank(TOKEN_HOLDER);
        IERC20(projectToken).approve(sucker, prepareCount);

        vm.prank(TOKEN_HOLDER);
        IJBSucker(sucker)
            .prepare({
            projectTokenCount: prepareCount,
            beneficiary: bytes32(uint256(uint160(TOKEN_HOLDER))),
            minTokensReclaimed: 0,
            token: JBConstants.NATIVE_TOKEN,
            metadata: bytes32(0)
        });

        uint256 bridgedBacking = sucker.balance - suckerEthBefore;
        uint256 expectedBacking = localSurplusBefore * prepareCount / totalSupplyBefore;

        assertApproxEqAbs(bridgedBacking, expectedBacking, 10, "sucker should receive direct pro-rata backing");
        assertEq(
            IERC20(projectToken).balanceOf(TOKEN_HOLDER),
            tokenHolderTokens - prepareCount,
            "prepare should transfer holder tokens to the sucker"
        );
        assertEq(IERC20(projectToken).balanceOf(address(BUYBACK_HOOK)), 0, "buyback hook should not receive tokens");

        vm.clearMockedCalls();
    }
}
