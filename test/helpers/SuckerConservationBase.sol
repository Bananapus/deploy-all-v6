// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./RevnetForkBase.sol";

import {MockERC20Token} from "./MockTokens.sol";

import {IJBSucker} from "@bananapus/suckers-v6/src/interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerDeployer.sol";
import {JBSucker} from "@bananapus/suckers-v6/src/JBSucker.sol";
import {JBOptimismSucker} from "@bananapus/suckers-v6/src/JBOptimismSucker.sol";
import {JBOptimismSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBOptimismSuckerDeployer.sol";
import {JBCCIPSucker} from "@bananapus/suckers-v6/src/JBCCIPSucker.sol";
import {JBCCIPSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBCCIPSuckerDeployer.sol";
import {IOPMessenger} from "@bananapus/suckers-v6/src/interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "@bananapus/suckers-v6/src/interfaces/IOPStandardBridge.sol";
import {ICCIPRouter} from "@bananapus/suckers-v6/src/interfaces/ICCIPRouter.sol";
import {IWrappedNativeToken} from "@bananapus/suckers-v6/src/interfaces/IWrappedNativeToken.sol";
import {CCIPHelper} from "@bananapus/suckers-v6/src/libraries/CCIPHelper.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";
import {JBTokenMapping} from "@bananapus/suckers-v6/src/structs/JBTokenMapping.sol";
import {JBMessageRoot} from "@bananapus/suckers-v6/src/structs/JBMessageRoot.sol";
import {JBChainAccounting} from "@bananapus/suckers-v6/src/structs/JBChainAccounting.sol";
import {JBInboxTreeRoot} from "@bananapus/suckers-v6/src/structs/JBInboxTreeRoot.sol";
import {JBSourceContext} from "@bananapus/suckers-v6/src/structs/JBSourceContext.sol";
import {JBClaim} from "@bananapus/suckers-v6/src/structs/JBClaim.sol";
import {JBLeaf} from "@bananapus/suckers-v6/src/structs/JBLeaf.sol";

import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ═══════════════════════════════════════════════════════════════════════════
//  Mock bridge infrastructure (one fork simulates two chains; relays by hand)
// ═══════════════════════════════════════════════════════════════════════════

/// @notice Mock OP messenger: spoofs `xDomainMessageSender` and accepts `sendMessage` as a payable no-op.
contract MockOPMessenger {
    address public xDomainMessageSender;

    function setXDomainMessageSender(address sender) external {
        xDomainMessageSender = sender;
    }

    function sendMessage(address, bytes calldata, uint32) external payable {}
}

/// @notice Mock OP standard bridge: no-op for both native and ERC20 bridging.
contract MockOPBridge {
    function bridgeETHTo(address, uint32, bytes calldata) external payable {}

    function bridgeERC20To(address, address, address, uint256, uint32, bytes calldata) external {}
}

/// @notice Minimal WETH used by the CCIP sucker's native wrap/unwrap path.
contract MockWETH is IWrappedNativeToken {
    string public name = "Wrapped Native";
    string public symbol = "WETH";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable override {
        totalSupply += msg.value;
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external override {
        balanceOf[msg.sender] -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "weth withdraw failed");
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

/// @notice Mock CCIP router: zero-fee, records nothing, returns the mock WETH. Incoming messages are delivered by the
/// test by pranking this address and calling `destSucker.ccipReceive`.
contract MockCCIPRouter {
    IWrappedNativeToken internal immutable WETH;

    constructor(IWrappedNativeToken weth) {
        WETH = weth;
    }

    function getWrappedNative() external view returns (IWrappedNativeToken) {
        return WETH;
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external pure returns (uint256) {
        return 0;
    }

    function ccipSend(uint64, Client.EVM2AnyMessage calldata) external payable returns (bytes32) {
        return bytes32("mockCcipMsgId");
    }

    function isChainSupported(uint64) external pure returns (bool) {
        return true;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Base: deploy OP/CCIP suckers, relay leaves by hand, assert conservation
// ═══════════════════════════════════════════════════════════════════════════

/// @notice Shared harness for cross-chain sucker conservation tests. Provides OP and CCIP sucker deployment, a hand
/// relay of `prepare -> bridge -> claim` round trips (over both AMBs, for native and ERC20/USDC terminal tokens), and
/// assertion helpers that pin balance / surplus / totalSupply conveyance and conservation.
///
/// A single mainnet fork models "two chains": the real `prepare` path burns project tokens + drains the terminal into
/// the sucker's outbox (source side); a synthetic `fromRemote`/`ccipReceive` + `claim` re-mints those tokens + deposits
/// the bridged terminal tokens back (remote side). On one project this is an exact round trip — what the sucker
/// conveys out it conveys back, proving the contract's `prepare`/`claim` accounting (burn==mint, drain==deposit) is
/// self-consistent: a claim that minted or deposited the wrong amount would break the supply/terminal equalities.
///
/// LIMITATION (by design of a one-fork sim): the AMB itself is mocked — the harness constructs the inbox root and
/// credits the sucker the "bridged" tokens, so these tests do NOT prove the bridge actually delivered, nor (on the
/// happy path) that the merkle/peer GATES reject bad input. Those security gates are proven SEPARATELY and
/// non-tautologically in `test/fork/SuckerSecurityGatesFork.t.sol` (forged leaves, non-peer/non-router messages, and
/// spoofed senders all revert).
abstract contract SuckerConservationBase is RevnetForkBase {
    // The remote chain modeled by the suckers (OP, chainId 10).
    uint256 internal constant REMOTE_CHAIN_ID = 10;

    MockOPMessenger internal opMessenger;
    MockOPBridge internal opBridge;
    JBOptimismSuckerDeployer internal opDeployer;

    MockWETH internal weth;
    MockCCIPRouter internal ccipRouter;
    JBCCIPSuckerDeployer internal ccipDeployer;

    // Per (sucker, token) relay counters so callers never mismanage nonce/index.
    mapping(address => uint64) internal _relayNonce;
    mapping(address => mapping(address => uint256)) internal _relayLeafIndex;

    // ═══════════════════════════════════════════════════════════════════
    //  Infra deployment (call from setUp)
    // ═══════════════════════════════════════════════════════════════════

    function _deployOpInfra() internal {
        opMessenger = new MockOPMessenger();
        opBridge = new MockOPBridge();
        opDeployer = new JBOptimismSuckerDeployer(jbDirectory(), jbPermissions(), jbTokens(), address(this), address(0));
        opDeployer.setChainSpecificConstants(IOPMessenger(address(opMessenger)), IOPStandardBridge(address(opBridge)));
        JBOptimismSucker opSingleton = new JBOptimismSucker(
            opDeployer, jbDirectory(), jbPermissions(), jbTokens(), FEE_PROJECT_ID, SUCKER_REGISTRY, address(0)
        );
        opDeployer.configureSingleton(opSingleton);
        vm.prank(multisig());
        SUCKER_REGISTRY.allowSuckerDeployer(address(opDeployer));
    }

    function _deployCcipInfra() internal {
        weth = new MockWETH();
        ccipRouter = new MockCCIPRouter(IWrappedNativeToken(address(weth)));
        ccipDeployer = new JBCCIPSuckerDeployer(jbDirectory(), jbPermissions(), jbTokens(), address(this), address(0));
        ccipDeployer.setChainSpecificConstants(REMOTE_CHAIN_ID, CCIPHelper.OP_SEL, ICCIPRouter(address(ccipRouter)));
        JBCCIPSucker ccipSingleton = new JBCCIPSucker(
            ccipDeployer, jbDirectory(), jbPermissions(), jbTokens(), FEE_PROJECT_ID, SUCKER_REGISTRY, address(0)
        );
        ccipDeployer.configureSingleton(ccipSingleton);
        vm.prank(multisig());
        SUCKER_REGISTRY.allowSuckerDeployer(address(ccipDeployer));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Sucker deployment for a revnet (native or arbitrary-token mapping)
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Deploy a sucker (via `deployerAddr`) for `revnetId`, mapping `localToken -> remoteToken`, and grant it
    /// MINT_TOKENS so `claim` can mint on this chain.
    function _deploySucker(
        address deployerAddr,
        uint256 revnetId,
        bytes32 salt,
        address localToken,
        bytes32 remoteToken
    )
        internal
        returns (address sucker)
    {
        _grantFrom(address(REV_DEPLOYER), address(SUCKER_REGISTRY), revnetId, JBPermissionIds.DEPLOY_SUCKERS);
        _grantFrom(address(REV_DEPLOYER), address(SUCKER_REGISTRY), revnetId, JBPermissionIds.MAP_SUCKER_TOKEN);

        JBTokenMapping[] memory mappings = new JBTokenMapping[](1);
        mappings[0] = JBTokenMapping({localToken: localToken, minGas: 200_000, remoteToken: remoteToken});

        JBSuckerDeployerConfig[] memory configs = new JBSuckerDeployerConfig[](1);
        configs[0] =
            JBSuckerDeployerConfig({deployer: IJBSuckerDeployer(deployerAddr), peer: bytes32(0), mappings: mappings});

        vm.prank(address(REV_DEPLOYER));
        address[] memory deployed = SUCKER_REGISTRY.deploySuckersFor(revnetId, salt, configs);
        sucker = deployed[0];
        _grantFrom(address(REV_DEPLOYER), sucker, revnetId, JBPermissionIds.MINT_TOKENS);
    }

    function _deployOpSuckerNative(uint256 revnetId, bytes32 salt) internal returns (address) {
        return _deploySucker(
            address(opDeployer),
            revnetId,
            salt,
            JBConstants.NATIVE_TOKEN,
            bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
        );
    }

    function _deployCcipSuckerNative(uint256 revnetId, bytes32 salt) internal returns (address) {
        return _deploySucker(
            address(ccipDeployer),
            revnetId,
            salt,
            JBConstants.NATIVE_TOKEN,
            bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  USDC revnet (6-decimal terminal token)
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Deploy a revnet whose terminal accepts a fresh 6-decimal mock USDC (currency == baseCurrency, so no price
    /// feed is consulted for issuance).
    function _deployUsdcRevnet(
        uint16 cashOutTaxRate,
        bytes32 descSalt
    )
        internal
        returns (uint256 id, MockERC20Token usdc)
    {
        usdc = new MockERC20Token("Mock USDC", "USDC", 6);

        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: address(usdc), decimals: 6, currency: uint32(uint160(address(usdc)))});

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0].beneficiary = payable(multisig());
        splits[0].percent = 10_000;

        REVStageConfig[] memory stages = new REVStageConfig[](1);
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
            description: REVDescription("USDC Revnet", "USDCR", "ipfs://usdc", descSalt),
            baseCurrency: uint32(uint160(address(usdc))),
            operator: multisig(),
            scopeCashOutsToLocalBalances: false,
            stageConfigurations: stages
        });

        REVSuckerDeploymentConfig memory sdc = REVSuckerDeploymentConfig({
            deployerConfigurations: new JBSuckerDeployerConfig[](0), salt: keccak256(abi.encodePacked(descSalt))
        });

        (id,) = REV_DEPLOYER.deployFor({
            revnetId: 0, configuration: cfg, accountingContextsToAccept: acc, suckerDeploymentConfiguration: sdc
        });
    }

    function _payRevnetUsdc(
        uint256 id,
        MockERC20Token usdc,
        address payer,
        uint256 amount
    )
        internal
        returns (uint256 tokens)
    {
        usdc.mint(payer, amount);
        vm.startPrank(payer);
        usdc.approve(address(jbMultiTerminal()), amount);
        tokens = jbMultiTerminal()
            .pay({
            projectId: id,
            token: address(usdc),
            amount: amount,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  prepare (real source-side: burn project tokens, drain terminal)
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Holder approves + prepares `tokenCount` project tokens into the sucker's outbox; returns the terminal-token
    /// amount the cash-out reclaimed (the leaf's `terminalTokenAmount`).
    function _prepare(
        uint256 revnetId,
        address sucker,
        address holder,
        address token,
        uint256 tokenCount
    )
        internal
        returns (uint256 reclaimed)
    {
        address projectToken = address(jbTokens().tokenOf(revnetId));
        uint256 before = _suckerTokenBalance(sucker, token);
        vm.startPrank(holder);
        IERC20(projectToken).approve(sucker, tokenCount);
        IJBSucker(sucker).prepare(tokenCount, bytes32(uint256(uint160(holder))), 0, token, bytes32(0));
        vm.stopPrank();
        reclaimed = _suckerTokenBalance(sucker, token) - before;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Relay (synthetic remote-side inbox injection) + claim
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Inject one leaf into an OP sucker's inbox via `fromRemote`, conveying `sourceTotalSupply`, and credit the
    /// sucker the bridged terminal tokens. Returns the leaf index to claim against.
    function _opRelay(
        address sucker,
        address token,
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        bytes32 beneficiary,
        uint256 sourceTotalSupply,
        uint256 sourceTimestamp
    )
        internal
        returns (uint256 index)
    {
        uint64 nonce = ++_relayNonce[sucker];
        index = _relayLeafIndex[sucker][token];
        bytes32 root = _leafRoot(projectTokenCount, terminalTokenAmount, beneficiary, index);

        // Gossip bundle carrying the remote peer's own record (origin chain == REMOTE_CHAIN_ID).
        JBChainAccounting[] memory accounts = new JBChainAccounting[](1);
        accounts[0] = JBChainAccounting({
            chainId: REMOTE_CHAIN_ID,
            totalSupply: sourceTotalSupply,
            contexts: new JBSourceContext[](0),
            timestamp: sourceTimestamp
        });

        opMessenger.setXDomainMessageSender(sucker);
        vm.prank(address(opMessenger));
        JBSucker(payable(sucker))
            .fromRemote(
                JBMessageRoot({
                version: 1,
                token: bytes32(uint256(uint160(token))),
                amount: terminalTokenAmount,
                remoteRoot: JBInboxTreeRoot({nonce: nonce, root: root}),
                accounts: accounts
            })
            );
        _creditSuckerBridged(sucker, token, terminalTokenAmount, false);
        _relayLeafIndex[sucker][token] = index + 1;
    }

    /// @dev Inject one leaf into a CCIP sucker's inbox via `ccipReceive`, conveying `sourceTotalSupply`. Native rides
    /// as WETH (unwrapped on receive); ERC20 rides as itself. Returns the leaf index to claim against.
    function _ccipRelay(
        address sucker,
        address token,
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        bytes32 beneficiary,
        uint256 sourceTotalSupply,
        uint256 sourceTimestamp
    )
        internal
        returns (uint256 index)
    {
        uint64 nonce = ++_relayNonce[sucker];
        index = _relayLeafIndex[sucker][token];
        bytes32 root = _leafRoot(projectTokenCount, terminalTokenAmount, beneficiary, index);

        bool isNative = token == JBConstants.NATIVE_TOKEN;
        address bridged = isNative ? address(weth) : token;
        _creditSuckerBridged(sucker, token, terminalTokenAmount, true);

        Client.EVMTokenAmount[] memory dta = new Client.EVMTokenAmount[](terminalTokenAmount == 0 ? 0 : 1);
        if (terminalTokenAmount != 0) dta[0] = Client.EVMTokenAmount({token: bridged, amount: terminalTokenAmount});

        // Gossip bundle carrying the remote peer's own record (origin chain == REMOTE_CHAIN_ID).
        JBChainAccounting[] memory accounts = new JBChainAccounting[](1);
        accounts[0] = JBChainAccounting({
            chainId: REMOTE_CHAIN_ID,
            totalSupply: sourceTotalSupply,
            contexts: new JBSourceContext[](0),
            timestamp: sourceTimestamp
        });

        Client.Any2EVMMessage memory inbound = Client.Any2EVMMessage({
            messageId: bytes32("mockCcipMsgId"),
            sourceChainSelector: CCIPHelper.OP_SEL,
            sender: abi.encode(sucker),
            data: abi.encode(
                uint8(0),
                abi.encode(
                    JBMessageRoot({
                        version: 1,
                        token: bytes32(uint256(uint160(token))),
                        amount: terminalTokenAmount,
                        remoteRoot: JBInboxTreeRoot({nonce: nonce, root: root}),
                        accounts: accounts
                    })
                )
            ),
            destTokenAmounts: dta
        });

        vm.prank(address(ccipRouter));
        JBCCIPSucker(payable(sucker)).ccipReceive(inbound);
        _relayLeafIndex[sucker][token] = index + 1;
    }

    function _claim(
        address sucker,
        address token,
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        bytes32 beneficiary,
        uint256 index
    )
        internal
    {
        IJBSucker(sucker)
            .claim(
                JBClaim({
                token: token,
                leaf: JBLeaf({
                index: index,
                beneficiary: beneficiary,
                projectTokenCount: projectTokenCount,
                terminalTokenAmount: terminalTokenAmount,
                metadata: bytes32(0)
            }),
                proof: _emptyBranchProof()
            })
            );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Internal helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Credit the sucker the terminal tokens the bridge "delivered". For CCIP native, WETH is credited (the sucker
    /// unwraps it in `ccipReceive`); for OP native, raw ETH; ERC20 is minted directly.
    function _creditSuckerBridged(address sucker, address token, uint256 amount, bool ccip) internal {
        if (amount == 0) return;
        if (token == JBConstants.NATIVE_TOKEN) {
            if (ccip) {
                vm.deal(address(this), amount);
                weth.deposit{value: amount}();
                weth.transfer(sucker, amount);
            } else {
                vm.deal(sucker, sucker.balance + amount);
            }
        } else {
            MockERC20Token(token).mint(sucker, amount);
        }
    }

    function _suckerTokenBalance(address sucker, address token) internal view returns (uint256) {
        if (token == JBConstants.NATIVE_TOKEN) return sucker.balance;
        return IERC20(token).balanceOf(sucker);
    }

    function _leafRoot(
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        bytes32 beneficiary,
        uint256 index
    )
        internal
        pure
        returns (bytes32)
    {
        bytes32 leafHash = keccak256(abi.encodePacked(projectTokenCount, terminalTokenAmount, beneficiary, bytes32(0)));
        return _computeBranchRoot(leafHash, _emptyBranchProof(), index);
    }

    function _grantFrom(address from, address operator, uint256 projectId, uint8 permissionId) internal {
        uint8[] memory ids = new uint8[](1);
        ids[0] = permissionId;
        vm.prank(from);
        jbPermissions()
            .setPermissionsFor(
                from,
                // forge-lint: disable-next-line(unsafe-typecast)
                JBPermissionsData({operator: operator, projectId: uint64(projectId), permissionIds: ids})
            );
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
            if (isRight) current = keccak256(abi.encodePacked(branch[i], current));
            else current = keccak256(abi.encodePacked(current, branch[i]));
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
}
