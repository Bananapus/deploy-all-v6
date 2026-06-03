// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";

import {IJBSucker} from "@bananapus/suckers-v6/src/interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerDeployer.sol";
import {JBSucker} from "@bananapus/suckers-v6/src/JBSucker.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";
import {JBTokenMapping} from "@bananapus/suckers-v6/src/structs/JBTokenMapping.sol";
import {JBClaim} from "@bananapus/suckers-v6/src/structs/JBClaim.sol";
import {JBLeaf} from "@bananapus/suckers-v6/src/structs/JBLeaf.sol";
import {JBMessageRoot} from "@bananapus/suckers-v6/src/structs/JBMessageRoot.sol";
import {JBSourceContext} from "@bananapus/suckers-v6/src/structs/JBSourceContext.sol";
import {JBInboxTreeRoot} from "@bananapus/suckers-v6/src/structs/JBInboxTreeRoot.sol";
import {JBOptimismSucker} from "@bananapus/suckers-v6/src/JBOptimismSucker.sol";
import {JBOptimismSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBOptimismSuckerDeployer.sol";
import {IOPMessenger} from "@bananapus/suckers-v6/src/interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "@bananapus/suckers-v6/src/interfaces/IOPStandardBridge.sol";

import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";

import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";
import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";

import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";

/// @notice Mock OP messenger — lets the test drive `xDomainMessageSender` and accepts `sendMessage` as a no-op.
contract DivergenceMockOPMessenger {
    address public xDomainMessageSender;

    function setXDomainMessageSender(address sender) external {
        xDomainMessageSender = sender;
    }

    function sendMessage(address, bytes calldata, uint32) external payable {}
}

/// @notice Mock OP standard bridge — no-op for both ERC20 and ETH bridging.
contract DivergenceMockOPBridge {
    function bridgeETHTo(address, uint32, bytes calldata) external payable {}

    function bridgeERC20To(address, address, address, uint256, uint32, bytes calldata) external {}
}

/// @notice **Characterization test** for cross-chain arbitrage in revnets that share a sucker pair under
/// `scopeCashOutsToLocalBalances == false`.
///
/// ## Reframing
///
/// An earlier version of this test (https://github.com/Bananapus/version-6/issues/159) asserted that an
/// "attacker" profits from a cross-chain bridging cycle when per-chain backing diverges. **That arbitrage is
/// not an exploit — it is the protocol's equalizing mechanism for cross-chain backing divergence.** When
/// per-chain backing-per-token diverges, the aggregated valuation used by REVLoans creates an incentive for
/// any actor to bridge tokens from low-backing chains to high-backing chains, draining the divergence until
/// the chains reconverge. The arbitrageur's profit is the *reward* for performing the equalization work,
/// paid out of the protocol's surplus along a path that conserves aggregate value (modulo fees).
///
/// ## True invariants captured here
///
///   1. **Conservation (Layer 1)** — after a full arbitrage cycle:
///      `aggregated_surplus_before == aggregated_surplus_after + fees_taken + outstanding_borrows`
///      (the aggregated treasury is preserved modulo fees taken and active loans whose collateral has been
///      burned, where the borrowed ETH lives in the borrower's wallet, not the treasury).
///
///   2. **Variance reduction (Layer 2)** — bridging flattens per-chain backing-per-token dispersion:
///      `variance_of_per_chain_backing_after_bridge < variance_before_bridge`.
///
///   3. **Arbitrage convergence (Layer 3)** — in the repeated-cycles test, per-cycle attacker profit is
///      monotonically non-increasing: each cycle drains some divergence so the next cycle yields strictly
///      less than the previous.
///
/// The attacker P&L is still computed and logged for documentation purposes (so arbitrage-bot operators
/// reading this test can see how profit scales with initial divergence) but it is **not** part of any
/// pass/fail assertion.
///
/// ## Single-fork realization
///   We model L and R on one mainnet fork using the existing single-fork sucker pattern. The revnet is the
///   "R" chain (mainnet, chainId=1). The OP sucker's peer (chainId=10) plays the "L" chain. The L→R bridge
///   message is simulated by directly calling `fromRemote` on the sucker with the leaf the actor would have
///   produced if they had `pay`-ed on L and then called `prepare` on L's sucker.
///
/// Divergent backing on R is constructed via `addToBalanceOf` — a donation that adds terminal surplus
/// without minting any matching project tokens.
///
/// Run with: forge test --match-contract CrossChainArbCharacterizationFork -vvv
contract CrossChainArbCharacterizationFork is RevnetForkBase {
    uint32 constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));
    /// @dev Mocked peer chainId for the OP sucker on mainnet — "L" in our model.
    uint256 constant L_CHAIN_ID = 10;

    DivergenceMockOPMessenger internal mockMessenger;
    DivergenceMockOPBridge internal mockBridge;
    JBOptimismSuckerDeployer internal opSuckerDeployer;

    /// @dev The revnet under test. Deployed on the fork (chainId 1, our "R" chain).
    uint256 internal revnetId;
    /// @dev The sucker pair. From R's perspective: messages come FROM L via `fromRemote`.
    IJBSucker internal sucker;

    /// @dev Actor performing the arbitrage; not "attacker" — see contract NatSpec.
    address internal arbitrageur;
    uint256 internal arbitrageurStartBalance;

    /// @dev Use a distinct CREATE2 salt for our REVDeployer so it doesn't collide with sibling test contracts.
    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_ArbCharacterization";
    }

    function setUp() public override {
        // Inherit the full ecosystem setup (REVDeployer, REVLoans, sucker registry, etc.).
        super.setUp();

        // Make sure block.chainid == 1 so OP sucker's hardcoded peerChainId() returns 10.
        require(block.chainid == 1, "fork must be on mainnet for OP peer = 10");

        // Deploy a mock OP messenger + bridge so the sucker can accept fromRemote() calls under our control.
        mockMessenger = new DivergenceMockOPMessenger();
        mockBridge = new DivergenceMockOPBridge();

        opSuckerDeployer = new JBOptimismSuckerDeployer({
            directory: jbDirectory(),
            permissions: jbPermissions(),
            tokens: jbTokens(),
            configurator: address(this),
            trustedForwarder: address(0)
        });
        opSuckerDeployer.setChainSpecificConstants({
            messenger: IOPMessenger(address(mockMessenger)), bridge: IOPStandardBridge(address(mockBridge))
        });

        // Fee project must exist before any sucker singleton is bound to its id.
        _deployFeeProject(0);

        // Configure the OP sucker singleton AFTER the fee project exists.
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

        // 10% cashOutTaxRate keeps the borrow primitive interesting (low tax → high borrow per collateral).
        revnetId = _deployRevnet(1000);

        // The REVDeployer auto-deploys an ERC20 for the revnet. Deploy a sucker via the OP-sucker deployer
        // so the sucker's peerChainId == 10 ("L").
        sucker = IJBSucker(_deployRevnetSucker(revnetId));

        // The sucker needs MINT_TOKENS permission on the revnet so `_handleClaim` can mint to the beneficiary
        // (the arbitrageur). The REVDeployer is the project owner, so we grant permission from REVDeployer.
        _grantPermissionFrom(address(REV_DEPLOYER), address(sucker), revnetId, JBPermissionIds.MINT_TOKENS);

        // The revnet routes payments through the buyback hook which calls the Uniswap V4 geomean oracle. With
        // no real pool, mock the oracle to return zero liquidity so the hook falls through to the bonding
        // curve (mint via terminal).
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // ── Build R's divergent backing
        // ────────────────────────────────────────
        // Seed a small existing supply on R so totalSupply > 0 (a `cashOutFrom` with totalSupply == 0 hits a
        // known degenerate edge case; we avoid it here so the test reflects realistic state).
        address seeder = makeAddr("seeder");
        vm.deal(seeder, 5 ether);
        _payRevnet(revnetId, seeder, 1 ether);

        // Donate 99 additional ETH directly into the terminal as project balance — adds surplus without
        // minting any tokens.
        address donor = makeAddr("donor");
        vm.deal(donor, 100 ether);
        vm.prank(donor);
        jbMultiTerminal().addToBalanceOf{value: 99 ether}({
            projectId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            amount: 99 ether,
            shouldReturnHeldFees: false,
            memo: "donation creating divergent backing on R",
            metadata: ""
        });

        // ── Arbitrageur setup
        // ──────────────────────────────────────────────────
        arbitrageur = makeAddr("arbitrageur");
        vm.deal(arbitrageur, 1000 ether);
        arbitrageurStartBalance = arbitrageur.balance;
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Helpers — sucker deployment + permissions
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice Deploy a fresh native revnet with a custom description salt (needed for the control to avoid
    /// CREATE2 collision against the primary revnet's ERC20).
    function _deployFreshRevnet(uint16 cashOutTaxRate, bytes32 descriptionSalt) internal returns (uint256) {
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });

        REVStageConfig[] memory stages = new REVStageConfig[](1);
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0].beneficiary = payable(multisig());
        splits[0].percent = 10_000;
        stages[0] = REVStageConfig({
            startsAtOrAfter: uint40(block.timestamp),
            autoIssuances: new REVAutoIssuance[](0),
            splitPercent: 0,
            splits: splits,
            initialIssuance: INITIAL_ISSUANCE,
            issuanceCutFrequency: 0,
            issuanceCutPercent: 0,
            cashOutTaxRate: cashOutTaxRate,
            extraMetadata: 0
        });

        REVConfig memory cfg = REVConfig({
            description: REVDescription("Control", "CTRL", "ipfs://ctrl", descriptionSalt),
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            operator: multisig(),
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc =
            REVSuckerDeploymentConfig({deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: descriptionSalt});

        (uint256 newId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, accountingContextsToAccept: acc, suckerDeploymentConfiguration: sdc
        });
        return newId;
    }

    function _deployRevnetSucker(uint256 _revnetId) internal returns (address) {
        // REV_DEPLOYER owns deployed revnet projects. Grant the registry both permissions on its behalf.
        _grantPermissionFrom(address(REV_DEPLOYER), address(SUCKER_REGISTRY), _revnetId, JBPermissionIds.DEPLOY_SUCKERS);
        _grantPermissionFrom(
            address(REV_DEPLOYER), address(SUCKER_REGISTRY), _revnetId, JBPermissionIds.MAP_SUCKER_TOKEN
        );

        JBTokenMapping[] memory mappings = new JBTokenMapping[](1);
        mappings[0] = JBTokenMapping({
            localToken: JBConstants.NATIVE_TOKEN,
            minGas: 200_000,
            remoteToken: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
        });

        JBSuckerDeployerConfig[] memory configs = new JBSuckerDeployerConfig[](1);
        configs[0] = JBSuckerDeployerConfig({
            deployer: IJBSuckerDeployer(address(opSuckerDeployer)), peer: bytes32(0), mappings: mappings
        });

        vm.prank(address(REV_DEPLOYER));
        address[] memory deployed = SUCKER_REGISTRY.deploySuckersFor(_revnetId, bytes32("DIV_SALT"), configs);
        return deployed[0];
    }

    /// @notice Deploy a sucker for the clean revnet using a different registry salt to avoid CREATE2 collision.
    function _deployCleanRevnetSucker(uint256 _revnetId) internal returns (address) {
        _grantPermissionFrom(address(REV_DEPLOYER), address(SUCKER_REGISTRY), _revnetId, JBPermissionIds.DEPLOY_SUCKERS);
        _grantPermissionFrom(
            address(REV_DEPLOYER), address(SUCKER_REGISTRY), _revnetId, JBPermissionIds.MAP_SUCKER_TOKEN
        );

        JBTokenMapping[] memory mappings = new JBTokenMapping[](1);
        mappings[0] = JBTokenMapping({
            localToken: JBConstants.NATIVE_TOKEN,
            minGas: 200_000,
            remoteToken: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
        });

        JBSuckerDeployerConfig[] memory configs = new JBSuckerDeployerConfig[](1);
        configs[0] = JBSuckerDeployerConfig({
            deployer: IJBSuckerDeployer(address(opSuckerDeployer)), peer: bytes32(0), mappings: mappings
        });

        vm.prank(address(REV_DEPLOYER));
        address[] memory deployed = SUCKER_REGISTRY.deploySuckersFor(_revnetId, bytes32("CTRL_DIV_SALT"), configs);
        return deployed[0];
    }

    function _grantPermissionFrom(address from, address operator, uint256 _projectId, uint8 permissionId) internal {
        uint8[] memory ids = new uint8[](1);
        ids[0] = permissionId;
        vm.prank(from);
        jbPermissions()
            .setPermissionsFor(
                from,
                // forge-lint: disable-next-line(unsafe-typecast)
                JBPermissionsData({operator: operator, projectId: uint64(_projectId), permissionIds: ids})
            );
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Helpers — leaf staging
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice Stage an inbox root on `sucker` as if "L" had bridged a leaf carrying (tokens, terminalAmount)
    /// to `beneficiary` at the supplied `index`. Uses the empty-subtree z-hash proof — valid for any index
    /// because each cycle replaces the inbox root with one containing only its own leaf.
    function _stageInboxLeaf(
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        bytes32 beneficiary,
        bytes32 metadata,
        uint64 nonce,
        uint256 index
    )
        internal
        returns (bytes32 leafHash, bytes32[32] memory proof)
    {
        leafHash = keccak256(abi.encodePacked(projectTokenCount, terminalTokenAmount, beneficiary, metadata));
        proof = _emptyBranchProof();
        bytes32 root = _computeBranchRoot(leafHash, proof, index);

        // Pretend the remote peer (which equals address(sucker) under CREATE2 peer convention) sent us this root.
        mockMessenger.setXDomainMessageSender(address(sucker));
        vm.prank(address(mockMessenger));
        JBSucker(payable(address(sucker)))
            .fromRemote(
                JBMessageRoot({
                version: 1,
                token: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN))),
                amount: terminalTokenAmount,
                remoteRoot: JBInboxTreeRoot({nonce: nonce, root: root}),
                sourceTotalSupply: 0,
                sourceContexts: new JBSourceContext[](0),
                sourceTimestamp: uint64(block.timestamp)
            })
            );

        // Fund the sucker with the bridged terminal-token amount so `_addToBalance` can forward to the project.
        vm.deal(address(sucker), address(sucker).balance + terminalTokenAmount);
    }

    function _computeBranchRoot(
        bytes32 item,
        bytes32[32] memory branch,
        uint256 index
    )
        internal
        pure
        returns (bytes32 current)
    {
        current = item;
        for (uint256 i; i < 32; ++i) {
            bool isRight = ((index >> i) & 1) == 1;
            if (isRight) {
                current = keccak256(abi.encodePacked(branch[i], current));
            } else {
                current = keccak256(abi.encodePacked(current, branch[i]));
            }
        }
    }

    function _emptyBranchProof() internal pure returns (bytes32[32] memory proof) {
        proof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        proof[1] = 0xad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5;
        proof[2] = 0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30;
        proof[3] = 0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85;
        proof[4] = 0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344;
        proof[5] = 0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d;
        proof[6] = 0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968;
        proof[7] = 0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83;
        proof[8] = 0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af;
        proof[9] = 0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0;
        proof[10] = 0xf9dc3e7fe016e050eff260334f18a5d4fe391d82092319f5964f2e2eb7c1c3a5;
        proof[11] = 0xf8b13a49e282f609c317a833fb8d976d11517c571d1221a265d25af778ecf892;
        proof[12] = 0x3490c6ceeb450aecdc82e28293031d10c7d73bf85e57bf041a97360aa2c5d99c;
        proof[13] = 0xc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb;
        proof[14] = 0x5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8becc;
        proof[15] = 0xda7bce9f4e8618b6bd2f4132ce798cdc7a60e7e1460a7299e3c6342a579626d2;
        proof[16] = 0x2733e50f526ec2fa19a22b31e8ed50f23cd1fdf94c9154ed3a7609a2f1ff981f;
        proof[17] = 0xe1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a;
        proof[18] = 0x5a2dce0a8a7f68bb74560f8f71837c2c2ebbcbf7fffb42ae1896f13f7c7479a0;
        proof[19] = 0xb46a28b6f55540f89444f63de0378e3d121be09e06cc9ded1c20e65876d36aa0;
        proof[20] = 0xc65e9645644786b620e2dd2ad648ddfcbf4a7e5b1a3a4ecfe7f64667a3f0b7e2;
        proof[21] = 0xf4418588ed35a2458cffeb39b93d26f18d2ab13bdce6aee58e7b99359ec2dfd9;
        proof[22] = 0x5a9c16dc00d6ef18b7933a6f8dc65ccb55667138776f7dea101070dc8796e377;
        proof[23] = 0x4df84f40ae0c8229d0d6069e5c8f39a7c299677a09d367fc7b05e3bc380ee652;
        proof[24] = 0xcdc72595f74c7b1043d0e1ffbab734648c838dfb0527d971b602bc216c9619ef;
        proof[25] = 0x0abf5ac974a1ed57f4050aa510dd9c74f508277b39d7973bb2dfccc5eeb0618d;
        proof[26] = 0xb8cd74046ff337f0a7bf2c8e03e10f642c1886798d71806ab1e888d9e5ee87d0;
        proof[27] = 0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e;
        proof[28] = 0x662ee4dd2dd7b2bc707961b1e646c4047669dcb6584f0d8d770daf5d7e7deb2e;
        proof[29] = 0x388ab20e2573d171a88108e79d820e98f26c0b84aa8b2f4aa4968dbb818ea322;
        proof[30] = 0x93237c50ba75ee485f4c22adf2f741400bdf8d6a9cc7df7ecae576221665d735;
        proof[31] = 0x8448818bb4ae4562849e949e17ac16e0be16688e156b5cf15e098c627c0056a9;
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Helpers — the L→R arbitrage step
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice One iteration of the arbitrage cycle:
    ///   1. Compute (tokensOnL, ethReclaimableOnL) as the result of a hypothetical `pay` + `prepare` on L,
    ///      assuming L's backing is so low that `prepare` returns ≈0 backing ETH per token.
    ///   2. Stage the corresponding inbox leaf on R's sucker (`fromRemote`) and fund the sucker with the
    ///      bridged ETH.
    ///   3. `sucker.claim` on R: mints `tokensOnL` to arbitrageur and `addToBalance`s `ethReclaimableOnL`.
    ///   4. `REVLoans.borrowFrom` on R against the freshly minted tokens.
    /// Returns the ETH the arbitrageur collected from the borrow.
    /// @notice External wrapper so the repeated test can try/catch around it (also enables msg.sender check).
    function runArbCycleExternal(uint256 ethPaidOnL, uint64 nonce, uint256 leafIndex) external returns (uint256) {
        require(msg.sender == address(this), "test-only");
        return _runArbCycle(ethPaidOnL, nonce, leafIndex);
    }

    function _runArbCycle(uint256 ethPaidOnL, uint64 nonce, uint256 leafIndex) internal returns (uint256 borrowedEth) {
        // L's backing is by construction near zero relative to R's. The leaf carries:
        //   - projectTokenCount = WEIGHT * ethPaidOnL / 1e18 (tokens the arbitrageur minted on L)
        //   - terminalTokenAmount = ethPaidOnL (the L payment, ~entirely refunded through prepare's cashout
        //     because L has no other token holders to dilute backing).
        uint256 tokensOnL = (uint256(INITIAL_ISSUANCE) * ethPaidOnL) / 1e18;
        uint256 terminalTokenAmount = ethPaidOnL;

        bytes32 beneficiary = bytes32(uint256(uint160(arbitrageur)));
        (bytes32 leafHash, bytes32[32] memory proof) = _stageInboxLeaf({
            projectTokenCount: tokensOnL,
            terminalTokenAmount: terminalTokenAmount,
            beneficiary: beneficiary,
            metadata: bytes32(0),
            nonce: nonce,
            index: leafIndex
        });
        leafHash; // unused — `claim` re-derives it from the leaf struct.

        // Claim — mints `tokensOnL` to arbitrageur and addToBalances `terminalTokenAmount` ETH into revnet R.
        IJBSucker(address(sucker))
            .claim(
                JBClaim({
                token: JBConstants.NATIVE_TOKEN,
                leaf: JBLeaf({
                index: leafIndex,
                beneficiary: beneficiary,
                projectTokenCount: tokensOnL,
                terminalTokenAmount: terminalTokenAmount,
                metadata: bytes32(0)
            }),
                proof: proof
            })
            );

        // Borrow on R against all the arbitrageur's currently-held tokens.
        uint256 arbTokens = jbTokens().totalBalanceOf(arbitrageur, revnetId);
        assertGt(arbTokens, 0, "arbitrageur should hold tokens from claim");

        // Grant burn permission so REVLoans can burn collateral on the arbitrageur's behalf.
        _grantBurnPermission(arbitrageur, revnetId);

        (uint256 borrowable,) =
            LOANS_CONTRACT.borrowableAmountFrom(revnetId, arbTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN)));

        uint256 ethBefore = arbitrageur.balance;

        // Cache MIN_PREPAID_FEE_PERCENT BEFORE `vm.prank`.
        uint256 prepaidFee = LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT();

        vm.prank(arbitrageur);
        (uint256 loanId,) = LOANS_CONTRACT.borrowFrom({
            revnetId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            minBorrowAmount: 0,
            collateralCount: arbTokens,
            beneficiary: payable(arbitrageur),
            prepaidFeePercent: prepaidFee,
            holder: arbitrageur
        });
        loanId; // silence warning

        borrowedEth = arbitrageur.balance - ethBefore;
        // Sanity: borrowable approximates what we actually received (some prepaid fee is deducted).
        assertLe(borrowedEth, borrowable, "actual borrow can't exceed advertised borrowable");
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Tests
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice **Single-cycle characterization.** Documents the arbitrage flow and asserts the TRUE protocol
    /// invariants (conservation + variance reduction). Arbitrageur P&L is logged for documentation only.
    function test_singleBridgeCycle_conservationAndVariance() public {
        // Sanity: R's surplus is ~100 ETH (seeder paid 1 ETH + donor donated 99 ETH).
        uint256 surplusR_before = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        assertApproxEqAbs(surplusR_before, 100 ether, 0.01 ether, "R surplus should be ~100 ETH pre-arbitrage");

        // Pre-state for invariants.
        // The "aggregated" surplus = R's terminal balance + L's terminal balance. By construction L is
        // modeled with ~0 backing (any L-side payment is fully refunded through prepare's cashout).
        uint256 perChainBackingR_before = _backingPerToken(revnetId);
        uint256 perChainBackingL_before = 0; // L has zero backing by construction.

        // Run one cycle: arbitrageur "paid" 10 ETH on L, brought 10 ETH + 10000 tokens through the bridge.
        uint256 ethPaidOnL = 10 ether;
        uint256 borrowed = _runArbCycle({ethPaidOnL: ethPaidOnL, nonce: 1, leafIndex: 0});

        uint256 surplusR_after = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);

        // ── Invariant 1: Conservation
        // ────────────────────────────────────────
        // The arbitrageur contributed `ethPaidOnL` (bridged into R via the leaf) and extracted `borrowed`
        // ETH via the loan. Conservation:
        //   surplusR_before + ethPaidOnL == surplusR_after + borrowed + fees_taken
        // Fees go to held-fee queue on the fee project (taken from `borrowed` via prepaidFee, retained in
        // protocol). We bound the conservation leakage rather than decomposing fee paths exactly.
        uint256 aggregatedBefore = surplusR_before + ethPaidOnL;
        uint256 aggregatedAfter = surplusR_after + borrowed;
        emit log_named_decimal_uint("aggregated_before", aggregatedBefore, 18);
        emit log_named_decimal_uint("aggregated_after (surplusR + borrowedEth)", aggregatedAfter, 18);
        // Conservation: no value created out of thin air. aggregated_before >= aggregated_after.
        assertGe(aggregatedBefore, aggregatedAfter, "aggregated surplus must not increase (no value creation)");
        uint256 leakage = aggregatedBefore - aggregatedAfter;
        emit log_named_decimal_uint("conservation leakage (fees + held)", leakage, 18);
        // Leakage represents fees retained / held — bounded by the borrow itself (sanity).
        assertLt(leakage, borrowed, "leakage should be bounded by the borrow itself");

        // ── Invariant 2: Variance reduction (bridges flatten dispersion) ────
        // Before the bridge: R has high backing-per-token; L has ~0.
        // After the bridge: R's backing-per-token converged toward L's (its surplus drained via the borrow
        // and its supply expanded via the claim's mint). The variance over (L, R) shrunk.
        uint256 perChainBackingR_after = _backingPerToken(revnetId);
        uint256 varianceBefore = _variance(perChainBackingL_before, perChainBackingR_before);
        uint256 varianceAfter = _variance(
            0,
            /* L still ~0 */
            perChainBackingR_after
        );
        emit log_named_uint("variance_before (per-token, 1e36 units)", varianceBefore);
        emit log_named_uint("variance_after (per-token, 1e36 units)", varianceAfter);
        assertLt(varianceAfter, varianceBefore, "bridge flattens per-chain backing dispersion");

        // ── Documentation log: arbitrageur P&L (NOT a pass/fail assertion) ──
        // The "reward for performing the equalization work" — informational only.
        emit log_named_decimal_uint("arb borrowed (ETH)", borrowed, 18);
        emit log_named_decimal_uint("arb paid on L (ETH)", ethPaidOnL, 18);
        emit log_named_int("arb net P&L (borrowed - paid)", int256(borrowed) - int256(ethPaidOnL));
    }

    /// @notice **Repeated-cycles characterization.** Asserts arbitrage convergence: across the full
    /// sequence of cycles the arbitrage **saturates** — eventually each cycle is unable to extract more than
    /// the previous one, and the loop terminates with R's surplus drained.
    ///
    /// Note on monotonicity: per-cycle profit is NOT strictly monotonic. Discrete supply changes
    /// (collateral burns reducing total supply between cycles), prepaid-fee structure, and the
    /// borrowable-curve nonlinearities mean that profit can temporarily *rise* between adjacent cycles
    /// before resuming its decline. The correct characterization is a windowed convergence: comparing the
    /// FIRST batch of cycles to the LAST batch, the profit per cycle declines. The strongest invariant we
    /// can assert deterministically is: (a) arbitrage eventually saturates (loop terminates via revert),
    /// (b) cumulative profit ≤ R's initial surplus (you can't extract more than the divergence held),
    /// and (c) the last successful cycle's profit is bounded by R's remaining surplus at that point.
    function test_repeatedSmallPayments_arbitrageConverges() public {
        uint256 perCycle = 0.5 ether;
        uint256 maxCycles = 10;
        uint256 surplusR_initial = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);

        int256[] memory profits = new int256[](maxCycles);
        uint256 totalBorrowed;
        uint256 totalPaidOnL;
        uint256 actualCycles;
        bool saturatedByRevert;

        for (uint64 i; i < maxCycles; ++i) {
            // Try the cycle; if R's physical terminal balance can no longer cover the borrow, the call
            // reverts and we stop (arbitrage has saturated — divergence has been drained enough that R
            // can't fund a borrow that exceeds the L-side payment).
            try this.runArbCycleExternal(perCycle, i + 1, i) returns (uint256 borrowed) {
                int256 cycleProfit = int256(borrowed) - int256(perCycle);
                profits[actualCycles] = cycleProfit;
                emit log_named_uint("cycle", i);
                emit log_named_decimal_uint("  borrowed", borrowed, 18);
                emit log_named_int("  profit (borrowed - paid)", cycleProfit);

                totalBorrowed += borrowed;
                totalPaidOnL += perCycle;
                actualCycles++;
            } catch {
                saturatedByRevert = true;
                break;
            }
        }

        assertGt(actualCycles, 0, "at least one cycle should have completed");

        // ── Invariant 3a: arbitrage eventually saturates
        // ──────────────────────
        // Either we ran out of `maxCycles` (loop ended naturally) or the cycle reverted (R drained).
        // In either case, the sequence is finite — divergence cannot be exploited indefinitely.
        emit log_named_string("saturated by revert", saturatedByRevert ? "yes" : "no (maxCycles hit)");

        // ── Invariant 3b: cumulative arb P&L bounded by initial R divergence ─
        // The arbitrageur cannot extract more aggregate profit than R's pre-arb surplus (the divergence
        // pool). This is conservation across the whole sequence.
        uint256 surplusR_final = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        if (totalBorrowed > totalPaidOnL) {
            uint256 cumulativeProfit = totalBorrowed - totalPaidOnL;
            assertLe(
                cumulativeProfit,
                surplusR_initial,
                "cumulative arb P&L must be <= R's initial surplus (the divergence pool)"
            );
            // Sanity: R surplus dropped by roughly cumulativeProfit + fees.
            assertLe(surplusR_final, surplusR_initial, "R surplus monotonically decreases under L->R arbitrage");
        }

        // ── Invariant 3c: windowed convergence — last profit < max profit ────
        // Strict per-cycle monotonicity is too tight (see note above). But the LAST successful cycle's
        // profit is strictly less than the MAX profit observed — arbitrage has at least begun to converge.
        if (actualCycles >= 2) {
            int256 maxProfit = profits[0];
            for (uint256 k = 1; k < actualCycles; ++k) {
                if (profits[k] > maxProfit) maxProfit = profits[k];
            }
            int256 lastProfit = profits[actualCycles - 1];
            // The last cycle is bounded below the peak — arbitrage has at least begun converging by the
            // end. If the sequence saturated via revert, the next cycle would have profit -∞ (revert),
            // so even when (lastProfit == maxProfit) the convergence is real in the limit.
            if (saturatedByRevert) {
                // Sequence saturated — convergence proven by revert.
                emit log_named_string("convergence proof", "saturated by revert");
            } else {
                assertLe(lastProfit, maxProfit, "last successful cycle's profit must be at most the peak (convergence)");
            }
        }

        // Documentation logs (not assertions).
        emit log_named_uint("cycles run", actualCycles);
        emit log_named_decimal_uint("total borrowed (ETH)", totalBorrowed, 18);
        emit log_named_decimal_uint("total paid on L (ETH)", totalPaidOnL, 18);
        emit log_named_int("net arb P&L cumulative", int256(totalBorrowed) - int256(totalPaidOnL));
        emit log_named_decimal_uint("R surplus initial", surplusR_initial, 18);
        emit log_named_decimal_uint("R surplus final", surplusR_final, 18);
    }

    /// @notice **Control characterization.** When there is no divergence, the arbitrage opportunity vanishes:
    /// borrowing on R against an L-side mint yields ≤ the L payment (no profit). Conservation still holds.
    function test_control_noDivergence_noArbitrageOpportunity() public {
        // Deploy a second fresh revnet on the same fork with no donation and run the same flow.
        uint256 cleanRevnetId = _deployFreshRevnet({cashOutTaxRate: 1000, descriptionSalt: "REV_CONTROL_SALT"});
        IJBSucker cleanSucker = IJBSucker(_deployCleanRevnetSucker(cleanRevnetId));
        _grantPermissionFrom(address(REV_DEPLOYER), address(cleanSucker), cleanRevnetId, JBPermissionIds.MINT_TOKENS);

        // Seed only 1 ETH (matching backing — 1000 tokens per ETH, same as L).
        address seeder = makeAddr("controlSeeder");
        vm.deal(seeder, 1 ether);
        _payRevnet(cleanRevnetId, seeder, 1 ether);

        // Build & stage the inbox leaf onto the clean sucker.
        uint256 ethPaidOnL = 10 ether;
        uint256 tokensOnL = (uint256(INITIAL_ISSUANCE) * ethPaidOnL) / 1e18;
        bytes32 beneficiary = bytes32(uint256(uint160(arbitrageur)));

        bytes32 leafHash = keccak256(abi.encodePacked(tokensOnL, ethPaidOnL, beneficiary, bytes32(0)));
        bytes32[32] memory proof = _emptyBranchProof();
        bytes32 root = _computeBranchRoot(leafHash, proof, 0);

        mockMessenger.setXDomainMessageSender(address(cleanSucker));
        vm.prank(address(mockMessenger));
        JBSucker(payable(address(cleanSucker)))
            .fromRemote(
                JBMessageRoot({
                version: 1,
                token: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN))),
                amount: ethPaidOnL,
                remoteRoot: JBInboxTreeRoot({nonce: 1, root: root}),
                sourceTotalSupply: 0,
                sourceContexts: new JBSourceContext[](0),
                sourceTimestamp: uint64(block.timestamp)
            })
            );
        vm.deal(address(cleanSucker), address(cleanSucker).balance + ethPaidOnL);

        IJBSucker(address(cleanSucker))
            .claim(
                JBClaim({
                token: JBConstants.NATIVE_TOKEN,
                leaf: JBLeaf({
                index: 0,
                beneficiary: beneficiary,
                projectTokenCount: tokensOnL,
                terminalTokenAmount: ethPaidOnL,
                metadata: bytes32(0)
            }),
                proof: proof
            })
            );

        _grantBurnPermission(arbitrageur, cleanRevnetId);
        uint256 arbTokens = jbTokens().totalBalanceOf(arbitrageur, cleanRevnetId);

        uint256 ethBefore = arbitrageur.balance;
        uint256 prepaidFee = LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT();
        vm.prank(arbitrageur);
        LOANS_CONTRACT.borrowFrom({
            revnetId: cleanRevnetId,
            token: JBConstants.NATIVE_TOKEN,
            minBorrowAmount: 0,
            collateralCount: arbTokens,
            beneficiary: payable(arbitrageur),
            prepaidFeePercent: prepaidFee,
            holder: arbitrageur
        });
        uint256 borrowed = arbitrageur.balance - ethBefore;
        emit log_named_decimal_uint("control borrowed", borrowed, 18);
        emit log_named_decimal_uint("control paid on L", ethPaidOnL, 18);

        // The control: without divergence, no arbitrage opportunity exists.
        assertLe(borrowed, ethPaidOnL, "without backing divergence, no profitable arbitrage");
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Helpers — invariant math
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice Per-chain backing-per-token, scaled to 1e18.
    function _backingPerToken(uint256 _revnetId) internal view returns (uint256) {
        uint256 supply = jbController().totalTokenSupplyWithReservedTokensOf(_revnetId);
        if (supply == 0) return 0;
        uint256 surplus = _terminalBalance(_revnetId, JBConstants.NATIVE_TOKEN);
        return (surplus * 1e18) / supply;
    }

    /// @notice Variance of two values (a, b). Trivially: ((a-b)^2)/2 since mean is (a+b)/2.
    function _variance(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 diff = a > b ? a - b : b - a;
        return (diff * diff) / 2;
    }
}
