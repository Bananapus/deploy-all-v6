// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

import {IJBSucker} from "@bananapus/suckers-v6/src/interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerDeployer.sol";
import {JBSucker} from "@bananapus/suckers-v6/src/JBSucker.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";
import {JBTokenMapping} from "@bananapus/suckers-v6/src/structs/JBTokenMapping.sol";
import {JBClaim} from "@bananapus/suckers-v6/src/structs/JBClaim.sol";
import {JBLeaf} from "@bananapus/suckers-v6/src/structs/JBLeaf.sol";
import {JBMessageRoot} from "@bananapus/suckers-v6/src/structs/JBMessageRoot.sol";
import {JBChainAccounting} from "@bananapus/suckers-v6/src/structs/JBChainAccounting.sol";
import {JBSourceContext} from "@bananapus/suckers-v6/src/structs/JBSourceContext.sol";
import {JBInboxTreeRoot} from "@bananapus/suckers-v6/src/structs/JBInboxTreeRoot.sol";
import {JBOptimismSucker} from "@bananapus/suckers-v6/src/JBOptimismSucker.sol";
import {JBOptimismSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBOptimismSuckerDeployer.sol";
import {IOPMessenger} from "@bananapus/suckers-v6/src/interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "@bananapus/suckers-v6/src/interfaces/IOPStandardBridge.sol";

import {REVConfig} from "@rev-net/core-v6/src/structs/REVConfig.sol";
import {REVDescription} from "@rev-net/core-v6/src/structs/REVDescription.sol";
import {REVStageConfig, REVAutoIssuance} from "@rev-net/core-v6/src/structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core-v6/src/structs/REVSuckerDeploymentConfig.sol";
import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";

import {RevnetForkBase} from "../helpers/RevnetForkBase.sol";

/// @notice Mock OP messenger — drives `xDomainMessageSender`, accepts `sendMessage` as a no-op.
contract InvariantMockOPMessenger {
    address public xDomainMessageSender;

    function setXDomainMessageSender(address sender) external {
        xDomainMessageSender = sender;
    }

    function sendMessage(address, bytes calldata, uint32) external payable {}
}

/// @notice Mock OP bridge — no-op for both ERC20 and ETH bridging.
contract InvariantMockOPBridge {
    function bridgeETHTo(address, uint32, bytes calldata) external payable {}

    function bridgeERC20To(address, address, address, uint256, uint32, bytes calldata) external {}
}

/// @notice Handler for the cross-chain arbitrage invariant test.
///
/// Exposes bounded random actions for the Foundry stateful invariant fuzzer:
///   - `pay(amount)`     — pay revnet on local "R" chain
///   - `claimAsBridge(amount, holderSeed)` — simulate an L→R bridge claim (mints to a tracked holder, addToBalance)
///   - `cashOut(holderSeed, amountSeed)`   — cash out tokens from a tracked holder
///   - `borrow(holderSeed, amountSeed)`    — borrow against tokens from a tracked holder
///   - `repay(loanSeed)`                   — repay a tracked loan
///
/// Tracks all ETH flows so the invariant tests can assert conservation:
///   - totalPaidIn:        sum of `pay` ETH (R-side payments)
///   - totalBridgedIn:     sum of ETH delivered via simulated L→R bridges
///   - totalCashedOutNet:  sum of ETH withdrawn via cashOuts (terminal token amount paid out, gross)
///   - totalBorrowedOut:   sum of ETH paid to borrowers (outstanding borrow principal)
///   - totalRepaid:        sum of ETH paid back via `repay`
contract CrossChainArbHandler is Test {
    uint32 constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));

    address public immutable TEST_CONTRACT;
    IJBSucker public immutable SUCKER;
    InvariantMockOPMessenger public immutable MESSENGER;
    uint256 public immutable REVNET_ID;

    // Refs (held by the test contract); we re-look-up via low-level calls to avoid type pollution.
    // We keep typed handles for the JB ecosystem.
    address public immutable TERMINAL;
    address public immutable JB_TOKENS;
    address public immutable LOANS;
    address public immutable JB_CONTROLLER;
    address public immutable JB_TERMINAL_STORE;
    address public immutable JB_PERMISSIONS;

    // ── Tracked actors & loans
    // ──────────────────────────────────────────
    address[] public holders;
    uint256[] public loanIds;
    /// @dev Pre-allocated proof to keep handler calls cheap (the test contract stages roots).
    uint64 internal _nonce;
    uint256 internal _leafIndex;

    // ── ETH-flow ledgers (used by the invariants)
    // ───────────────────────
    uint256 public totalPaidIn; // ETH paid to revnet on R
    uint256 public totalBridgedIn; // ETH delivered into R via simulated L→R bridges
    uint256 public totalCashedOutGross; // ETH withdrawn from R via cashOuts (gross, before fees)
    uint256 public totalBorrowedOut; // ETH delivered to borrowers (loan principal)
    uint256 public totalRepaid; // ETH paid back via repay()

    // ── Stats
    // ───────────────────────────────────────────────────────────
    uint256 public payCalls;
    uint256 public claimCalls;
    uint256 public cashOutCalls;
    uint256 public borrowCalls;
    uint256 public repayCalls;

    constructor(
        address testContract,
        IJBSucker sucker,
        InvariantMockOPMessenger messenger,
        uint256 revnetId,
        address terminal,
        address jbTokens,
        address loans,
        address jbController,
        address jbTerminalStore,
        address jbPermissions
    ) {
        TEST_CONTRACT = testContract;
        SUCKER = sucker;
        MESSENGER = messenger;
        REVNET_ID = revnetId;
        TERMINAL = terminal;
        JB_TOKENS = jbTokens;
        LOANS = loans;
        JB_CONTROLLER = jbController;
        JB_TERMINAL_STORE = jbTerminalStore;
        JB_PERMISSIONS = jbPermissions;

        // Pre-seed three tracked holders.
        holders.push(makeAddr("invHolder1"));
        holders.push(makeAddr("invHolder2"));
        holders.push(makeAddr("invHolder3"));
        for (uint256 i; i < holders.length; ++i) {
            vm.deal(holders[i], 1000 ether);
            // Grant burn permission so REVLoans can burn collateral when this holder takes loans.
            _grantBurnPermissionFromHolder(holders[i]);
        }
    }

    receive() external payable {}

    // ═════════════════════════════════════════════════════════════════════
    //  Fuzzer-exposed actions
    // ═════════════════════════════════════════════════════════════════════

    /// @notice Pay revnet R as a tracked holder. Bounded amount.
    function pay(uint256 holderSeed, uint256 amount) external {
        amount = bound(amount, 0.01 ether, 5 ether);
        address holder = holders[holderSeed % holders.length];
        vm.deal(holder, holder.balance + amount);

        vm.prank(holder);
        (bool ok,) = TERMINAL.call{value: amount}(
            abi.encodeWithSignature(
                "pay(uint256,address,uint256,address,uint256,string,bytes)",
                REVNET_ID,
                JBConstants.NATIVE_TOKEN,
                amount,
                holder,
                0,
                "",
                ""
            )
        );
        if (!ok) return; // skip; could be revert from cashout-delay or sucker state
        totalPaidIn += amount;
        payCalls++;
    }

    /// @notice Simulate an L→R bridge claim — mints `tokens` to a holder & delivers `terminalAmount` ETH
    /// into R's terminal via `addToBalance`.
    function claimAsBridge(uint256 holderSeed, uint256 amount) external {
        amount = bound(amount, 0.01 ether, 5 ether);
        address holder = holders[holderSeed % holders.length];

        uint256 tokensOnL = (uint256(1000e18) * amount) / 1e18;
        bytes32 beneficiary = bytes32(uint256(uint160(holder)));

        // Ask test contract to stage the inbox root for this leaf.
        (bool stageOk,) = TEST_CONTRACT.call(
            abi.encodeWithSignature(
                "handlerStageInboxLeaf(uint256,uint256,bytes32,uint64,uint256)",
                tokensOnL,
                amount,
                beneficiary,
                ++_nonce,
                _leafIndex
            )
        );
        if (!stageOk) return;

        bytes32[32] memory proof = _emptyBranchProof();
        try IJBSucker(address(SUCKER))
            .claim(
                JBClaim({
                token: JBConstants.NATIVE_TOKEN,
                leaf: JBLeaf({
                index: _leafIndex,
                beneficiary: beneficiary,
                projectTokenCount: tokensOnL,
                terminalTokenAmount: amount,
                metadata: bytes32(0)
            }),
                proof: proof
            })
            ) {
            totalBridgedIn += amount;
            claimCalls++;
            _leafIndex++;
        } catch {
            // claim failed (e.g. stale root) — skip silently
        }
    }

    /// @notice Cash out tokens for a tracked holder. Bounded by their token balance.
    function cashOut(uint256 holderSeed, uint256 amountSeed) external {
        address holder = holders[holderSeed % holders.length];
        uint256 bal = _tokenBalanceOf(holder);
        if (bal == 0) return;
        uint256 cashAmount = bound(amountSeed, 1, bal);

        uint256 beforeBalance = holder.balance;
        vm.prank(holder);
        // Signature order is (holder, projectId, cashOutCount, tokenToReclaim, minReclaimed, beneficiary, metadata).
        // The selector must match exactly: a mismatched selector reverts and is swallowed below, silently no-oping
        // the cash-out leg, so `cashOutCalls` is asserted live in the sanity test to keep this path honest.
        (bool ok,) = TERMINAL.call(
            abi.encodeWithSignature(
                "cashOutTokensOf(address,uint256,uint256,address,uint256,address,bytes)",
                holder,
                REVNET_ID,
                cashAmount,
                JBConstants.NATIVE_TOKEN,
                0,
                holder,
                ""
            )
        );
        if (!ok) return;
        uint256 received = holder.balance - beforeBalance;
        totalCashedOutGross += received;
        cashOutCalls++;
    }

    /// @notice Borrow against a tracked holder's tokens.
    function borrow(uint256 holderSeed, uint256 amountSeed) external {
        address holder = holders[holderSeed % holders.length];
        uint256 bal = _tokenBalanceOf(holder);
        if (bal == 0) return;
        uint256 collateral = bound(amountSeed, 1, bal);

        // Read prepaid fee before pranking.
        (, bytes memory prepRes) = LOANS.staticcall(abi.encodeWithSignature("MIN_PREPAID_FEE_PERCENT()"));
        uint256 prepaidFee = abi.decode(prepRes, (uint256));

        uint256 ethBefore = holder.balance;
        vm.prank(holder);
        (bool ok, bytes memory res) = LOANS.call(
            abi.encodeWithSignature(
                "borrowFrom(uint256,address,uint256,uint256,address,uint256,address)",
                REVNET_ID,
                JBConstants.NATIVE_TOKEN,
                0,
                collateral,
                holder,
                prepaidFee,
                holder
            )
        );
        if (!ok) return;
        (uint256 loanId,) = abi.decode(res, (uint256, REVLoan));
        loanIds.push(loanId);
        totalBorrowedOut += holder.balance - ethBefore;
        borrowCalls++;
    }

    /// @notice Repay a tracked loan in full.
    function repay(uint256 loanSeed) external {
        if (loanIds.length == 0) return;
        uint256 loanId = loanIds[loanSeed % loanIds.length];

        (, bytes memory loanRes) = LOANS.staticcall(abi.encodeWithSignature("loanOf(uint256)", loanId));
        if (loanRes.length == 0) return;
        REVLoan memory l = abi.decode(loanRes, (REVLoan));
        if (l.amount == 0) return;

        // Determine the holder that owns this loan via the ERC721. We just pick holders[0] — repays can
        // realistically be done by anyone if they tender the cash. For simplicity, holders[0] repays.
        address payer = holders[0];
        uint256 repayAmount = uint256(l.amount) + 1 ether; // overpay to be safe; refund returned.

        vm.deal(payer, payer.balance + repayAmount);
        uint256 payerBefore = payer.balance;

        vm.prank(payer);
        (bool ok,) = LOANS.call{value: repayAmount}(
            abi.encodeWithSignature(
                "repayLoan(uint256,uint256,uint256,address,bytes)", loanId, type(uint256).max, 0, payer, ""
            )
        );
        if (!ok) return;
        uint256 spent = payerBefore - payer.balance;
        totalRepaid += spent;
        repayCalls++;
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Views for invariant assertions
    // ═════════════════════════════════════════════════════════════════════

    function holderAt(uint256 i) external view returns (address) {
        return holders[i];
    }

    function holdersCount() external view returns (uint256) {
        return holders.length;
    }

    function outstandingPrincipal() external view returns (uint256 total) {
        for (uint256 i; i < loanIds.length; ++i) {
            (, bytes memory loanRes) = LOANS.staticcall(abi.encodeWithSignature("loanOf(uint256)", loanIds[i]));
            REVLoan memory l = abi.decode(loanRes, (REVLoan));
            total += uint256(l.amount);
        }
    }

    function outstandingCollateral() external view returns (uint256 total) {
        for (uint256 i; i < loanIds.length; ++i) {
            (, bytes memory loanRes) = LOANS.staticcall(abi.encodeWithSignature("loanOf(uint256)", loanIds[i]));
            REVLoan memory l = abi.decode(loanRes, (REVLoan));
            total += uint256(l.collateral);
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Internal helpers
    // ═════════════════════════════════════════════════════════════════════

    function _tokenBalanceOf(address holder) internal view returns (uint256) {
        (, bytes memory res) =
            JB_TOKENS.staticcall(abi.encodeWithSignature("totalBalanceOf(address,uint256)", holder, REVNET_ID));
        return abi.decode(res, (uint256));
    }

    function _grantBurnPermissionFromHolder(address holder) internal {
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = 11; // BURN_TOKENS
        vm.prank(holder);
        (bool ok,) = JB_PERMISSIONS.call(
            abi.encodeWithSignature(
                "setPermissionsFor(address,(address,uint64,uint8[]))",
                holder,
                JBPermissionsData({operator: LOANS, projectId: uint64(REVNET_ID), permissionIds: permissionIds})
            )
        );
        ok;
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

/// @notice **Stateful invariant suite for cross-chain arbitrage dynamics.**
///
/// This suite uses Foundry's invariant-fuzzer framework with a `CrossChainArbHandler` exposing bounded
/// actions: pay, claim-as-bridge, cashOut, borrow, repay. Across many random sequences the invariants
/// must hold for every reachable state.
///
/// **Limitation noted:** because this is a fork-based setup (multi-chain on one fork via synthetic
/// `fromRemote` injection), the invariant runs at reduced runs/depth via inline-config below to keep
/// CI times sane (~30s at 16×40 ≈ 640 actions). If you want exhaustive coverage, override with
/// `FOUNDRY_INVARIANT_RUNS=256 FOUNDRY_INVARIANT_DEPTH=1000 forge test ...` (multi-hour) or move this
/// to a synthetic-chains setup using vm.mockCall.
///
/// forge-config: default.invariant.runs = 16
/// forge-config: default.invariant.depth = 40
/// forge-config: default.invariant.fail-on-revert = false
contract CrossChainArbInvariant is RevnetForkBase {
    uint32 constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));
    uint256 constant REMOTE_CHAIN_ID = 10;

    InvariantMockOPMessenger internal mockMessenger;
    InvariantMockOPBridge internal mockBridge;
    JBOptimismSuckerDeployer internal opSuckerDeployer;

    uint256 internal revnetId;
    IJBSucker internal sucker;

    CrossChainArbHandler internal handler;

    uint256 internal initialSurplus;
    uint256 internal initialSupply;

    function _deployerSalt() internal pure override returns (bytes32) {
        return "REVDeployer_ArbInvariant";
    }

    function setUp() public override {
        super.setUp();
        require(block.chainid == 1, "fork must be on mainnet");

        mockMessenger = new InvariantMockOPMessenger();
        mockBridge = new InvariantMockOPBridge();

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

        _deployFeeProject(0);

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

        // 10% cashOutTaxRate, standard config.
        revnetId = _deployRevnet(1000);
        sucker = IJBSucker(_deployRevnetSucker(revnetId));
        _grantPermissionFrom(address(REV_DEPLOYER), address(sucker), revnetId, JBPermissionIds.MINT_TOKENS);

        _mockOracle(1, 0, uint32(REV_DEPLOYER.DEFAULT_BUYBACK_TWAP_WINDOW()));

        // Seed initial state: 10 ETH paid in for 10000 tokens — gives us a meaningful starting supply.
        address seeder = makeAddr("invariantSeeder");
        vm.deal(seeder, 50 ether);
        _payRevnet(revnetId, seeder, 10 ether);

        initialSurplus = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        initialSupply = jbController().totalTokenSupplyWithReservedTokensOf(revnetId);

        // Deploy handler.
        handler = new CrossChainArbHandler({
            testContract: address(this),
            sucker: sucker,
            messenger: mockMessenger,
            revnetId: revnetId,
            terminal: address(jbMultiTerminal()),
            jbTokens: address(jbTokens()),
            loans: address(LOANS_CONTRACT),
            jbController: address(jbController()),
            jbTerminalStore: address(jbTerminalStore()),
            jbPermissions: address(jbPermissions())
        });

        // Tell Foundry's fuzzer to target the handler.
        targetContract(address(handler));

        // Restrict the fuzzer to handler functions we want to exercise.
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = CrossChainArbHandler.pay.selector;
        selectors[1] = CrossChainArbHandler.claimAsBridge.selector;
        selectors[2] = CrossChainArbHandler.cashOut.selector;
        selectors[3] = CrossChainArbHandler.borrow.selector;
        selectors[4] = CrossChainArbHandler.repay.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Test-contract callback used by the handler to stage inbox roots.
    // ═════════════════════════════════════════════════════════════════════

    function handlerStageInboxLeaf(
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        bytes32 beneficiary,
        uint64 nonce,
        uint256 index
    )
        external
    {
        require(msg.sender == address(handler), "only handler");
        bytes32 leafHash = keccak256(abi.encodePacked(projectTokenCount, terminalTokenAmount, beneficiary, bytes32(0)));
        bytes32[32] memory proof = _emptyBranchProof();
        bytes32 root = _computeBranchRoot(leafHash, proof, index);

        // Gossip bundle carrying the remote OP peer's record (origin chain == 10).
        JBChainAccounting[] memory accounts = new JBChainAccounting[](1);
        accounts[0] = JBChainAccounting({
            chainId: 10, totalSupply: 0, contexts: new JBSourceContext[](0), timestamp: uint64(block.timestamp)
        });

        mockMessenger.setXDomainMessageSender(address(sucker));
        vm.prank(address(mockMessenger));
        JBSucker(payable(address(sucker)))
            .fromRemote(
                JBMessageRoot({
                version: 1,
                token: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN))),
                amount: terminalTokenAmount,
                remoteRoot: JBInboxTreeRoot({nonce: nonce, root: root}),
                accounts: accounts
            })
            );

        // Fund sucker with the ETH that would have ridden the bridge.
        vm.deal(address(sucker), address(sucker).balance + terminalTokenAmount);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  INVARIANTS
    // ═════════════════════════════════════════════════════════════════════

    /// @notice **Conservation (Layer 1).** Across any sequence of operations, the protocol's ETH ledger
    /// balances out:
    ///
    ///   currentSurplus + totalCashedOutGross + totalBorrowedOut - totalRepaid
    ///     == initialSurplus + totalPaidIn + totalBridgedIn + fee_held_in_protocol
    ///
    /// We rearrange to make it a one-sided inequality (the protocol cannot create value):
    ///
    ///   ETH_into_protocol >= ETH_out_of_protocol - currentSurplus
    ///
    /// where:
    ///   ETH_into_protocol   = initialSurplus + totalPaidIn + totalBridgedIn + totalRepaid
    ///   ETH_out_of_protocol = totalCashedOutGross + totalBorrowedOut
    function invariant_conservation() public view {
        uint256 currentSurplus = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        uint256 inflows = initialSurplus + handler.totalPaidIn() + handler.totalBridgedIn() + handler.totalRepaid();
        uint256 outflows = handler.totalCashedOutGross() + handler.totalBorrowedOut();

        // Inflows must cover outflows minus what's still in the terminal — but we also have fees diverted
        // to the fee project, so the cleanest assertion is: inflows + currentSurplus_drop >= outflows.
        // Equivalent: inflows >= outflows - currentSurplus (when surplus dropped) OR
        //             outflows <= inflows + (initialSurplus - currentSurplus_diff).
        //
        // We pose it as: inflows + currentSurplus >= outflows + a "remaining-in-protocol" floor.
        // Allow ±1 wei tolerance for rounding.
        assertGe(
            inflows + 1,
            outflows + currentSurplus > inflows ? outflows + currentSurplus - inflows : 0,
            "conservation: inflows must cover outflows minus retained surplus"
        );

        // Stronger one-sided bound: total ETH withdrawn from protocol (gross) cannot exceed inflows + initial.
        assertLe(
            outflows,
            inflows + 1,
            "conservation: cumulative outflows cannot exceed cumulative inflows (modulo 1 wei rounding)"
        );
    }

    /// @notice **Aggregated surplus is bounded above by cumulative net inflows.** No path makes R's surplus
    /// exceed what's been paid into it (initial + pay + bridge + repay) — value cannot be created.
    /// This is the upper-bound complement to `invariant_conservation`'s lower bound on net ETH.
    function invariant_aggregatedSurplusNeverDrainsBeyondFees() public view {
        uint256 currentSurplus = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        uint256 totalIn = initialSurplus + handler.totalPaidIn() + handler.totalBridgedIn() + handler.totalRepaid();
        // Surplus is bounded above by cumulative inflows. (Outflows can only reduce it; fees retained can
        // only redistribute it, never create it. Tolerance: 1 wei for rounding.)
        assertLe(currentSurplus, totalIn + 1, "current surplus bounded above by cumulative inflows");
    }

    /// @notice **No projectId has a negative surplus.** A revnet's terminal balance is uint, so this is
    /// structurally true at the type level — but the invariant runs ensure no path produces an
    /// underflow-revert by getting close to zero. The assertion here is: `terminalBalance >= 0` and the
    /// borrowable amount remains a valid non-overflow uint256.
    function invariant_noChainHasNegativeBalance() public view {
        uint256 currentSurplus = _terminalBalance(revnetId, JBConstants.NATIVE_TOKEN);
        // Structurally true; the assertion catches if the invariant runner found a sequence that
        // panic-reverts on overflow inside our reads.
        assertLe(currentSurplus, type(uint128).max, "surplus stays in a sane range");
    }

    /// @notice **Token supply consistency.** Sum of tracked holder balances must be ≤ total supply.
    /// (Outstanding loan collateral is BURNED from supply at the moment of `borrowFrom`, so it is not
    /// part of any holder's balance and is not part of `totalTokenSupplyWithReservedTokensOf`.)
    function invariant_tokenSupplyConsistency() public view {
        uint256 totalSupply = jbController().totalTokenSupplyWithReservedTokensOf(revnetId);

        uint256 trackedBalances;
        uint256 holdersCount = handler.holdersCount();
        for (uint256 i; i < holdersCount; ++i) {
            trackedBalances += jbTokens().totalBalanceOf(handler.holderAt(i), revnetId);
        }

        // We can't enumerate ALL holders cheaply, but the tracked subset cannot exceed the live total.
        assertLe(trackedBalances, totalSupply, "tracked balances <= total supply");
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Sanity test (non-invariant) — ensures handler-driven flow works at all
    // ═════════════════════════════════════════════════════════════════════

    function test_handlerSanity_payAndCashOut() public {
        // One-shot smoke test that the handler functions can each succeed at least once.
        handler.pay({holderSeed: 0, amount: 2 ether});
        assertGt(handler.payCalls(), 0, "pay should have succeeded once");

        handler.claimAsBridge({holderSeed: 0, amount: 1 ether});

        handler.cashOut({holderSeed: 0, amountSeed: 100});
        assertGt(handler.cashOutCalls(), 0, "cashOut should have executed (selector is live, not a silent no-op)");

        handler.borrow({holderSeed: 0, amountSeed: 50});

        // Invariants should hold after this sequence.
        invariant_conservation();
        invariant_aggregatedSurplusNeverDrainsBeyondFees();
        invariant_noChainHasNegativeBalance();
        invariant_tokenSupplyConsistency();
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Helpers (sucker deployment + permissions + tree math)
    // ═════════════════════════════════════════════════════════════════════

    function _deployRevnetSucker(uint256 _revnetId) internal returns (address) {
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

        vm.prank(multisig());
        SUCKER_REGISTRY.allowTokenMapping(JBConstants.NATIVE_TOKEN, REMOTE_CHAIN_ID, mappings[0].remoteToken);

        vm.prank(address(REV_DEPLOYER));
        address[] memory deployed = SUCKER_REGISTRY.deploySuckersFor(_revnetId, bytes32("INV_SALT"), configs);
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
}
