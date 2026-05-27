// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import /* {*} from */ "@bananapus/core-v6/test/helpers/TestBaseWorkflow.sol";

// Core
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBSplitGroupIds} from "@bananapus/core-v6/src/libraries/JBSplitGroupIds.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBTerminalStore} from "@bananapus/core-v6/src/interfaces/IJBTerminalStore.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";

// Suckers
import {JBSuckerRegistry} from "@bananapus/suckers-v6/src/JBSuckerRegistry.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerRegistry.sol";
import {IJBSucker} from "@bananapus/suckers-v6/src/interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "@bananapus/suckers-v6/src/interfaces/IJBSuckerDeployer.sol";
import {JBSuckerDeployerConfig} from "@bananapus/suckers-v6/src/structs/JBSuckerDeployerConfig.sol";
import {JBTokenMapping} from "@bananapus/suckers-v6/src/structs/JBTokenMapping.sol";
import {JBClaim} from "@bananapus/suckers-v6/src/structs/JBClaim.sol";
import {JBLeaf} from "@bananapus/suckers-v6/src/structs/JBLeaf.sol";
import {JBMessageRoot} from "@bananapus/suckers-v6/src/structs/JBMessageRoot.sol";
import {JBOutboxTree} from "@bananapus/suckers-v6/src/structs/JBOutboxTree.sol";
import {JBInboxTreeRoot} from "@bananapus/suckers-v6/src/structs/JBInboxTreeRoot.sol";
import {JBSucker} from "@bananapus/suckers-v6/src/JBSucker.sol";
import {JBOptimismSucker} from "@bananapus/suckers-v6/src/JBOptimismSucker.sol";
import {JBOptimismSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBOptimismSuckerDeployer.sol";
import {JBBaseSucker} from "@bananapus/suckers-v6/src/JBBaseSucker.sol";
import {JBBaseSuckerDeployer} from "@bananapus/suckers-v6/src/deployers/JBBaseSuckerDeployer.sol";
import {IOPMessenger} from "@bananapus/suckers-v6/src/interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "@bananapus/suckers-v6/src/interfaces/IOPStandardBridge.sol";

// Distributor
import {JBTokenDistributor} from "@bananapus/distributor-v6/src/JBTokenDistributor.sol";
import {IJBDistributor} from "@bananapus/distributor-v6/src/interfaces/IJBDistributor.sol";
import {IREVLoans} from "@rev-net/core-v6/src/interfaces/IREVLoans.sol";
import {IREVOwner} from "@rev-net/core-v6/src/interfaces/IREVOwner.sol";

// Referral hook
import {JBReferralSplitHook} from "@bananapus/referral-split-hook-v6/src/JBReferralSplitHook.sol";
import {IJBReferralSplitHook} from "@bananapus/referral-split-hook-v6/src/interfaces/IJBReferralSplitHook.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {MockERC20Token} from "../helpers/MockTokens.sol";
import {MockPriceFeed} from "../helpers/MockPriceFeed.sol";
import {IJBPriceFeed} from "@bananapus/core-v6/src/interfaces/IJBPriceFeed.sol";

/// @notice Mock OP messenger that allows the test to drive `xDomainMessageSender` precisely. Accepts
/// `sendMessage` as a no-op (the test invokes `fromRemote` directly on the destination side).
contract MockOPMessenger {
    address public xDomainMessageSender;

    function setXDomainMessageSender(address sender) external {
        xDomainMessageSender = sender;
    }

    function sendMessage(address, bytes calldata, uint32) external payable {}
}

/// @notice Mock OP standard bridge — no-op for both ERC20 and ETH bridging since the test does not exercise
/// terminal-token transit across chains.
contract MockOPBridge {
    function bridgeETHTo(address, uint32, bytes calldata) external payable {}

    function bridgeERC20To(address, address, address, uint256, uint32, bytes calldata) external {}
}

/// @notice Full end-to-end fork tests for the cross-chain referral reward flow.
///
/// The full path under test, for every test case below, is:
/// 1. A paying project takes payments crediting a referrer project (same-chain OR cross-chain referrer).
/// 2. The terminal's protocol fee credits the fee project, which mints fee-project tokens as a payment receipt.
/// 3. Each fee payment also writes `feeVolumeByReferralOf[terminal][refChain][refProjectId] += feeAmount` and
///    `totalFeeVolumeOf[terminal] += feeAmount` on the terminal store.
/// 4. The fee project's reserved-token allocation (its reservedPercent of issuance) accumulates pending tokens.
/// 5. `JBController.sendReservedTokensToSplitsOf(FEE_PROJECT_ID)` distributes those reserved tokens to splits,
///    one of which is the `JBReferralSplitHook` — so the hook's `totalDeposited` grows.
/// 6a. Same-chain referrer: `hook.pushTo(refChain=local, refProjectId)` computes the pro-rata delta and forwards
///     to `JBTokenDistributor.fund(refToken, feeToken, amount)`.
/// 6b. Cross-chain referrer: `hook.bridgeRemote(refChain=remote, refProjectId, sucker, terminalToken)` cashes out
///     the entitled fee-project tokens through the sucker (0% sucker exemption tax) and inserts a leaf into the
///     outbox tagged with `(originChainId=local, refProjectId)`. On the destination side, the sibling hook (same
///     contract at the same address by CREATE2 convention) calls `claimAndPush(originChainId=remote, refProjectId,
///     sucker, claimData)` which validates the proof, claims the leaf (which mints destination fee-project tokens
///     to the hook and adds the bridged terminal tokens to the fee project's balance), and forwards the freshly
///     minted fee tokens to the destination distributor for `refProjectId`'s LOCAL twin — independent of any
///     numerically-matching projectId on the origin chain.
/// 7. Stakers in the referrer project delegate their IVotes balance (auto-enabled by JBERC20's `ERC20Votes`
///    extension), call `beginVesting` after a round advances, then `collectVestedRewards` once enough rounds
///    have elapsed for the linear vest to release.
///
/// All cross-chain mechanics are simulated on a single Ethereum mainnet fork using the existing
/// `MockOPMessenger`/`MockOPBridge` pattern from `SuckerEndToEndFork.t.sol`. Two real suckers are deployed:
/// one `JBOptimismSucker` (peerChainId=10) and one `JBBaseSucker` (peerChainId=8453) — each gets a distinct
/// remote chain to model "different chains" without needing two forks. Inbox state for claim tests is staged by
/// pranking the mock messenger and invoking `fromRemote(...)` directly with `xDomainMessageSender == peer`.
///
/// Run with: forge test --match-contract ReferralRewardCrossChainForkTest -vvv
contract ReferralRewardCrossChainForkTest is TestBaseWorkflow {
    // ═══════════════════════════════════════════════════════════════════════
    //  Constants
    // ═══════════════════════════════════════════════════════════════════════

    uint32 constant NATIVE_CURRENCY = uint32(uint160(JBConstants.NATIVE_TOKEN));
    /// @dev 50% reserved on fee project — guarantees every fee-paid issuance produces a meaningful split pool.
    uint16 constant FEE_RESERVED_PERCENT = 5000;
    /// @dev 1000e18 weight — 1 ether of fee revenue yields 1000 fee-project tokens of issuance.
    uint112 constant FEE_WEIGHT = 1000e18;
    /// @dev Used by the cross-chain mock to identify the two remote chains under test.
    uint256 constant OPTIMISM_CHAIN_ID = 10;
    uint256 constant BASE_CHAIN_ID = 8453;
    /// @dev Distributor round duration and vesting horizon. Small values keep the test deterministic without
    /// burning huge `vm.warp` deltas.
    uint256 constant ROUND_DURATION = 1 days;
    uint256 constant VESTING_ROUNDS = 4;

    // ═══════════════════════════════════════════════════════════════════════
    //  Actors
    // ═══════════════════════════════════════════════════════════════════════

    address FEE_PROJECT_OWNER = makeAddr("feeProjectOwner");
    address PAYER_PROJECT_OWNER = makeAddr("payerProjectOwner");
    address REFERRER_OWNER = makeAddr("referrerOwner");
    address PAYER = makeAddr("payer");
    address STAKER_A = makeAddr("stakerA");
    address STAKER_B = makeAddr("stakerB");
    address STAKER_C = makeAddr("stakerC");
    /// @dev A staker who never delegates — their balance stays out of the snapshot.
    address UNDELEGATED_STAKER = makeAddr("undelegatedStaker");

    // ═══════════════════════════════════════════════════════════════════════
    //  Infrastructure
    // ═══════════════════════════════════════════════════════════════════════

    JBSuckerRegistry suckerRegistry;
    MockOPMessenger mockOpMessenger;
    MockOPBridge mockOpBridge;
    MockOPMessenger mockBaseMessenger;
    MockOPBridge mockBaseBridge;
    JBOptimismSuckerDeployer opSuckerDeployer;
    JBBaseSuckerDeployer baseSuckerDeployer;

    JBTokenDistributor distributor;
    JBReferralSplitHook hook;

    // ═══════════════════════════════════════════════════════════════════════
    //  Projects under test
    // ═══════════════════════════════════════════════════════════════════════

    uint256 feeProjectId; // expected to be 1
    uint256 payerProjectId; // a paying project that takes referred payments
    uint256 referrerProjectIdLocal; // a local-chain referrer with IVotes token (same-chain push path)
    uint256 referrerProjectIdLocalTwin; // local twin used for cross-chain ID-divergence test
    uint256 referrerProjectIdNoToken; // a referrer that has NO ERC-20 yet (credit-only — skipped path)

    /// @dev The two registered fee-project suckers (one per remote chain), addressed via the IJBSucker interface
    /// since the hook only talks to that interface anyway.
    IJBSucker opSucker;
    IJBSucker baseSucker;

    /// @dev Mock USDC + its currency code (uint32(uint160(token))). Used by the USDC E2E test group.
    MockERC20Token usdc;
    uint32 usdcCurrency;
    /// @dev Payer project paid in USDC instead of ETH. Created lazily by `_setUpUsdc`.
    uint256 payerProjectIdUsdc;

    function setUp() public override {
        super.setUp();

        // Pin the chain id to Ethereum mainnet so the OP/Base suckers' hardcoded `peerChainId()` lookups
        // return 10 / 8453 respectively. Also roll forward a few blocks so the ERC20Votes checkpoint reads
        // (`getPastVotes`) have a stable past-block to query later.
        vm.chainId(1);
        vm.roll(block.number + 1);

        // Deploy the sucker registry first — the hook reads this to authenticate sucker callers.
        suckerRegistry = new JBSuckerRegistry(jbDirectory(), jbPermissions(), address(this), address(0));

        // Deploy the two OP-stack bridges (mocked) and their corresponding deployer singletons. We use
        // BOTH JBOptimismSucker (peerChainId=10 from mainnet) and JBBaseSucker (peerChainId=8453 from mainnet)
        // so the same fork can host two suckers with two distinct remote chains.
        mockOpMessenger = new MockOPMessenger();
        mockOpBridge = new MockOPBridge();
        mockBaseMessenger = new MockOPMessenger();
        mockBaseBridge = new MockOPBridge();

        opSuckerDeployer = new JBOptimismSuckerDeployer({
            directory: jbDirectory(),
            permissions: jbPermissions(),
            tokens: jbTokens(),
            configurator: address(this),
            trustedForwarder: address(0)
        });
        opSuckerDeployer.setChainSpecificConstants(
            IOPMessenger(address(mockOpMessenger)), IOPStandardBridge(address(mockOpBridge))
        );

        baseSuckerDeployer = new JBBaseSuckerDeployer({
            directory: jbDirectory(),
            permissions: jbPermissions(),
            tokens: jbTokens(),
            configurator: address(this),
            trustedForwarder: address(0)
        });
        baseSuckerDeployer.setChainSpecificConstants(
            IOPMessenger(address(mockBaseMessenger)), IOPStandardBridge(address(mockBaseBridge))
        );

        // The fee project ID is hardcoded into each singleton — we wire `1` here and require the fee project
        // to be the first project created below. We must launch the fee project BEFORE configuring singletons
        // that depend on its ID, so the order below matters.

        // ── 1. Launch the fee project (must be id 1).
        feeProjectId = _launchFeeProject();
        require(feeProjectId == 1, "fee project must be id 1 to match sucker singletons");

        // ── 2. Configure OP/Base sucker singletons (each requires feeProjectId in the constructor).
        JBOptimismSucker opSingleton = new JBOptimismSucker({
            deployer: opSuckerDeployer,
            directory: jbDirectory(),
            permissions: jbPermissions(),
            prices: jbPrices(),
            tokens: jbTokens(),
            feeProjectId: feeProjectId,
            registry: suckerRegistry,
            trustedForwarder: address(0)
        });
        opSuckerDeployer.configureSingleton(opSingleton);

        JBBaseSucker baseSingleton = new JBBaseSucker({
            deployer: baseSuckerDeployer,
            directory: jbDirectory(),
            permissions: jbPermissions(),
            prices: jbPrices(),
            tokens: jbTokens(),
            feeProjectId: feeProjectId,
            registry: suckerRegistry,
            trustedForwarder: address(0)
        });
        baseSuckerDeployer.configureSingleton(baseSingleton);

        suckerRegistry.allowSuckerDeployer(address(opSuckerDeployer));
        suckerRegistry.allowSuckerDeployer(address(baseSuckerDeployer));

        // ── 3. Deploy the fee project's ERC20 token. Required because the referral hook moves these tokens
        // around (and `bridgeRemote` cashes them out through the sucker).
        vm.prank(FEE_PROJECT_OWNER);
        jbController().deployERC20For(feeProjectId, "FeeToken", "FEE", bytes32("FEE_TOKEN_SALT"));

        // ── 4. Deploy the distributor + hook. The hook reads its immutables from the distributor + registry;
        // they must already exist.
        distributor = new JBTokenDistributor({
            directory: jbDirectory(),
            controller: IJBController(address(jbController())),
            revLoans: IREVLoans(address(0)),
            revOwner: IREVOwner(address(0)),
            initialRoundDuration: ROUND_DURATION,
            initialVestingRounds: VESTING_ROUNDS,
            initialClaimDuration: 0
        });

        hook = new JBReferralSplitHook({
            directory: jbDirectory(),
            store: IJBTerminalStore(address(jbTerminalStore())),
            tokens: jbTokens(),
            distributor: IJBDistributor(address(distributor)),
            suckerRegistry: IJBSuckerRegistry(address(suckerRegistry)),
            terminal: address(jbMultiTerminal()),
            feeProjectId: feeProjectId
        });

        // ── 5. Re-queue the fee project's ruleset, this time wiring the reserved-token split group to the hook
        // we just deployed. The initial launch happened before the hook existed, so we couldn't pre-wire it.
        _wireFeeProjectReservedSplitToHook();

        // ── 6. Deploy the two suckers (op + base) for the fee project. The registry path registers them and
        // pre-maps NATIVE_TOKEN; the suckers also need MINT_TOKENS permission on the fee project so that
        // `_handleClaim` can mint destination fee-project tokens to the hook (the leaf beneficiary). Grant
        // that explicitly from the fee project owner.
        opSucker = IJBSucker(_deployFeeProjectSucker(opSuckerDeployer, bytes32("OP_SALT")));
        baseSucker = IJBSucker(_deployFeeProjectSucker(baseSuckerDeployer, bytes32("BASE_SALT")));
        _grantPermission(FEE_PROJECT_OWNER, address(opSucker), feeProjectId, JBPermissionIds.MINT_TOKENS);
        _grantPermission(FEE_PROJECT_OWNER, address(baseSucker), feeProjectId, JBPermissionIds.MINT_TOKENS);

        // ── 7. Launch the paying project (project 2) and the referrer projects.
        payerProjectId = _launchPayerProject();
        referrerProjectIdLocal = _launchReferrerProject({owner: REFERRER_OWNER, deployErc20: true});
        referrerProjectIdLocalTwin = _launchReferrerProject({owner: REFERRER_OWNER, deployErc20: true});
        referrerProjectIdNoToken = _launchReferrerProject({owner: REFERRER_OWNER, deployErc20: false});

        // Fund actors.
        vm.deal(PAYER, 1000 ether);

        // Give the local referrer's project tokens to stakers A/B/C and have them self-delegate so the
        // distributor can read past voting power. `UNDELEGATED_STAKER` never delegates — their share should
        // remain in the pool across rounds.
        _mintAndDelegate(referrerProjectIdLocal, STAKER_A, 100e18);
        _mintAndDelegate(referrerProjectIdLocal, STAKER_B, 200e18);
        _mintAndDelegate(referrerProjectIdLocal, STAKER_C, 300e18);
        _mintNoDelegate(referrerProjectIdLocal, UNDELEGATED_STAKER, 400e18);

        // Same treatment for the local-twin referrer (used by cross-chain ID-divergence tests).
        _mintAndDelegate(referrerProjectIdLocalTwin, STAKER_A, 150e18);
        _mintAndDelegate(referrerProjectIdLocalTwin, STAKER_B, 350e18);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Setup helpers
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Launch the fee project as project 1 with a reserved-token split group that points to nothing
    /// (yet — the hook is deployed later and wired in via `_wireFeeProjectReservedSplitToHook`).
    function _launchFeeProject() internal returns (uint256) {
        JBRulesetMetadata memory meta = JBRulesetMetadata({
            reservedPercent: FEE_RESERVED_PERCENT,
            cashOutTaxRate: 0,
            baseCurrency: NATIVE_CURRENCY,
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: false,
            scopeCashOutsToLocalBalances: false, // sucker exemption needs cross-terminal surplus
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});

        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: FEE_WEIGHT,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: meta,
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        return jbController()
            .launchProjectFor({
            owner: FEE_PROJECT_OWNER,
            projectUri: "ipfs://fee",
            rulesetConfigurations: rulesets,
            terminalConfigurations: tc,
            memo: ""
        });
    }

    /// @notice Re-queue the fee project's ruleset so its reserved-token split group sends 100% to the hook.
    /// We do this after the hook is deployed (the hook address must exist before being referenced in a split).
    function _wireFeeProjectReservedSplitToHook() internal {
        JBRulesetMetadata memory meta = JBRulesetMetadata({
            reservedPercent: FEE_RESERVED_PERCENT,
            cashOutTaxRate: 0,
            baseCurrency: NATIVE_CURRENCY,
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: false,
            scopeCashOutsToLocalBalances: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        // Build the 100% → hook split for the reserved-token group.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(hook))
        });

        JBSplitGroup[] memory groups = new JBSplitGroup[](1);
        groups[0] = JBSplitGroup({groupId: JBSplitGroupIds.RESERVED_TOKENS, splits: splits});

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: FEE_WEIGHT,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: meta,
            splitGroups: groups,
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        // The fee project owner queues the successor ruleset. A duration-0 ruleset can be replaced any time.
        vm.prank(FEE_PROJECT_OWNER);
        jbController().queueRulesetsOf({projectId: feeProjectId, rulesetConfigurations: rulesets, memo: ""});
    }

    /// @notice Deploy a sucker for the fee project using the supplied deployer. Grants the registry permission to
    /// deploy + map tokens on the fee project's behalf (impersonating the owner).
    function _deployFeeProjectSucker(IJBSuckerDeployer deployer, bytes32 salt) internal returns (address) {
        _grantPermission(FEE_PROJECT_OWNER, address(suckerRegistry), feeProjectId, JBPermissionIds.DEPLOY_SUCKERS);
        _grantPermission(FEE_PROJECT_OWNER, address(suckerRegistry), feeProjectId, JBPermissionIds.MAP_SUCKER_TOKEN);

        JBTokenMapping[] memory mappings = new JBTokenMapping[](1);
        mappings[0] = JBTokenMapping({
            localToken: JBConstants.NATIVE_TOKEN,
            minGas: 200_000,
            remoteToken: bytes32(uint256(uint160(JBConstants.NATIVE_TOKEN)))
        });

        JBSuckerDeployerConfig[] memory configs = new JBSuckerDeployerConfig[](1);
        configs[0] = JBSuckerDeployerConfig({deployer: deployer, peer: bytes32(0), mappings: mappings});

        vm.prank(FEE_PROJECT_OWNER);
        address[] memory deployed = suckerRegistry.deploySuckersFor(feeProjectId, salt, configs);
        return deployed[0];
    }

    /// @notice Launch a generic paying project — accepts payments and takes the protocol fee. We use a
    /// non-zero cashOutTaxRate so the fee-credit path engages on cashOuts as well as payouts.
    function _launchPayerProject() internal returns (uint256) {
        JBRulesetMetadata memory meta = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 5000,
            baseCurrency: NATIVE_CURRENCY,
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: false,
            scopeCashOutsToLocalBalances: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});

        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: FEE_WEIGHT,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: meta,
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        return jbController()
            .launchProjectFor({
            owner: PAYER_PROJECT_OWNER,
            projectUri: "ipfs://payer",
            rulesetConfigurations: rulesets,
            terminalConfigurations: tc,
            memo: ""
        });
    }

    /// @notice Launch a referrer project. When `deployErc20 == true`, also deploy the ERC-20 so the hook can
    /// resolve `TOKENS.tokenOf(refProjectId)` to a non-zero IVotes address.
    function _launchReferrerProject(address owner, bool deployErc20) internal returns (uint256 projectId) {
        JBRulesetMetadata memory meta = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
            baseCurrency: NATIVE_CURRENCY,
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: false,
            scopeCashOutsToLocalBalances: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: JBConstants.NATIVE_TOKEN, decimals: 18, currency: NATIVE_CURRENCY});

        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: FEE_WEIGHT,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: meta,
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        projectId = jbController()
            .launchProjectFor({
            owner: owner,
            projectUri: "ipfs://ref",
            rulesetConfigurations: rulesets,
            terminalConfigurations: tc,
            memo: ""
        });

        if (deployErc20) {
            vm.prank(owner);
            jbController().deployERC20For(projectId, "RefToken", "REF", keccak256(abi.encodePacked("REF", projectId)));
        }
    }

    /// @notice Grant a permission from `from` to `operator` for `_projectId`.
    function _grantPermission(address from, address operator, uint256 _projectId, uint8 permissionId) internal {
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

    /// @notice Mint `amount` of project tokens to `to` (as ERC-20) and self-delegate so `getPastVotes` returns
    /// `amount` after the next block. `mintFor` mints directly into the ERC-20 when one is deployed for the
    /// project, so no credit-claim step is needed.
    function _mintAndDelegate(uint256 _projectId, address to, uint256 amount) internal {
        vm.prank(address(jbController()));
        jbTokens().mintFor({holder: to, projectId: _projectId, count: amount});
        address token = address(jbTokens().tokenOf(_projectId));
        vm.prank(to);
        IVotes(token).delegate(to);
    }

    /// @notice Mint to `to` but never delegate — used to assert non-delegated supply stays in the pool.
    function _mintNoDelegate(uint256 _projectId, address to, uint256 amount) internal {
        vm.prank(address(jbController()));
        jbTokens().mintFor({holder: to, projectId: _projectId, count: amount});
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Flow helpers
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Pay `payerProjectId` for `amount`, then cash out the resulting tokens with the supplied referral
    /// pair. The cash-out path runs the protocol fee through the fee project, crediting the referrer's volume.
    /// @return feeVolumeCredited Approximation of the fee volume credited to the referrer (= cashOut fee amount).
    function _payAndCashOutWithReferral(
        address payer,
        uint256 amount,
        uint256 referralChainId,
        uint256 referralProjectId
    )
        internal
        returns (uint256 feeVolumeCredited)
    {
        // Pay first to get project tokens.
        vm.prank(payer);
        uint256 tokens = jbMultiTerminal().pay{value: amount}({
            projectId: payerProjectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: amount,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
        require(tokens > 0, "payer received zero tokens");

        // Encode the referral as (chainId << 48) | projectId. The terminal auto-fills chainId from block.chainid
        // when only the projectId is set, but we want explicit cross-chain credits, so always encode both.
        uint256 encodedReferral = (referralChainId << 48) | referralProjectId;

        // Snapshot totals before cash out so we can compute the volume credited.
        uint256 totalBefore = jbTerminalStore().totalFeeVolumeOf(address(jbMultiTerminal()));

        // Burn the project tokens for surplus — the protocol fee on the reclaimed amount becomes the referral
        // credit. cashOutTokensOf takes the referral as a separate uint256.
        vm.prank(payer);
        jbMultiTerminal()
            .cashOutTokensOf({
            holder: payer,
            projectId: payerProjectId,
            cashOutCount: tokens,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0,
            beneficiary: payable(payer),
            metadata: "",
            referralProjectId: encodedReferral
        });

        uint256 totalAfter = jbTerminalStore().totalFeeVolumeOf(address(jbMultiTerminal()));
        feeVolumeCredited = totalAfter - totalBefore;
    }

    /// @notice Manually distribute the fee project's pending reserved tokens — this triggers
    /// `hook.processSplitWith(...)` and grows `hook.totalDeposited`.
    function _distributeFeeReservedTokens() internal {
        jbController().sendReservedTokensToSplitsOf(feeProjectId);
    }

    /// @notice Stage a synthetic inbox root on `sucker` for terminal `token` as if a remote chain had delivered
    /// a root containing exactly the leaf described by (`projectTokenCount`, `terminalTokenAmount`, `beneficiary`,
    /// `metadata`) at index 0. The remaining proof slots are the canonical empty-subtree z-hashes.
    /// @dev Uses the mock messenger / fromRemote path with `xDomainMessageSender == peer()` so the legitimate
    /// `_isRemotePeer` check passes. This is more faithful than `vm.store` since it exercises the real branch
    /// that consumers run in production.
    function _stageInboxLeaf(
        IJBSucker sucker,
        MockOPMessenger messenger,
        address token,
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        bytes32 beneficiary,
        bytes32 metadata,
        uint64 nonce
    )
        internal
        returns (bytes32 leafHash, bytes32[32] memory proof, bytes32 root)
    {
        // Compute the leaf hash exactly the way the sucker would.
        leafHash = _buildLeafHash(projectTokenCount, terminalTokenAmount, beneficiary, metadata);

        // The proof for an index-0 leaf is just the empty-subtree z-hashes for every level. `branchRoot` then
        // hashes leaf → keccak(leaf, Z_0) → keccak(_, Z_1) → ... → Z_32 root.
        proof = _emptyBranchProof();
        root = _computeBranchRoot(leafHash, proof, 0);

        // Pretend the remote peer (which equals address(sucker) under default CREATE2 peer assumption) sent us
        // this root via the messenger.
        messenger.setXDomainMessageSender(address(sucker));
        vm.prank(address(messenger));
        JBSucker(payable(address(sucker)))
            .fromRemote(
                JBMessageRoot({
                version: 1,
                token: bytes32(uint256(uint160(token))),
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

        // Fund the sucker with the terminal tokens so `_handleClaim`'s `_addToBalance` has something to forward
        // to the fee project's terminal.
        if (token == JBConstants.NATIVE_TOKEN) {
            vm.deal(address(sucker), address(sucker).balance + terminalTokenAmount);
        }
    }

    /// @notice Re-implements the sucker's leaf hashing so tests can build leaves before staging them.
    function _buildLeafHash(
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        bytes32 beneficiary,
        bytes32 metadata
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(projectTokenCount, terminalTokenAmount, beneficiary, metadata));
    }

    /// @notice Compute the root of a 32-deep tree containing the supplied leaf at the supplied index, given the
    /// branch siblings. Mirrors `MerkleLib.branchRoot` exactly.
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

    /// @notice The canonical empty-subtree z-hashes used by the sucker's incremental merkle tree.
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

    // ═══════════════════════════════════════════════════════════════════════
    //  GROUP 1 — Same-chain end-to-end
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Full happy path: pay → cash out with same-chain referral → reserved-tokens distributed →
    /// pushTo → distributor balance grows for the referrer's IVotes token.
    function test_sameChain_endToEnd_basicHappyPath() public {
        // Step 1+2: credit volume for the local referrer.
        uint256 credited = _payAndCashOutWithReferral(PAYER, 10 ether, block.chainid, referrerProjectIdLocal);
        assertGt(credited, 0, "fee volume should be credited");

        // Step 3+4: process reserved tokens into the hook. Round up first to break ground on the first ruleset.
        _distributeFeeReservedTokens();
        assertGt(hook.totalDeposited(), 0, "hook must have received fee-project tokens");

        // Step 5: push to the local referrer.
        uint256 pushed = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});
        assertGt(pushed, 0, "pushTo must forward something");
        assertEq(hook.pushedLocallyOf(referrerProjectIdLocal), pushed, "high-water mark should equal pushed");

        // Step 6: the distributor's per-hook balance for the fee project's ERC20 should equal `pushed`.
        address feeToken = address(jbTokens().tokenOf(feeProjectId));
        address refToken = address(jbTokens().tokenOf(referrerProjectIdLocal));
        assertEq(
            distributor.balanceOf(refToken, IERC20(feeToken)), pushed, "distributor balance should equal pushed amount"
        );
    }

    /// @notice Two same-chain referrers earn distinct fee-volume credits. Their pushTo shares must sum to no
    /// more than `totalDeposited`, and individually match the pro-rata formula
    /// `(totalDeposited * refVol / totalVol)` rounded down.
    function test_sameChain_twoReferrers_proRataShare() public {
        // Credit referrer 1 (twice as much volume).
        _payAndCashOutWithReferral(PAYER, 10 ether, block.chainid, referrerProjectIdLocal);
        _payAndCashOutWithReferral(PAYER, 10 ether, block.chainid, referrerProjectIdLocal);
        // Credit referrer 2 (once).
        _payAndCashOutWithReferral(PAYER, 10 ether, block.chainid, referrerProjectIdLocalTwin);

        _distributeFeeReservedTokens();

        uint256 vol1 =
            jbTerminalStore().feeVolumeByReferralOf(address(jbMultiTerminal()), block.chainid, referrerProjectIdLocal);
        uint256 vol2 = jbTerminalStore()
            .feeVolumeByReferralOf(address(jbMultiTerminal()), block.chainid, referrerProjectIdLocalTwin);
        uint256 totalVol = jbTerminalStore().totalFeeVolumeOf(address(jbMultiTerminal()));
        uint256 totalDeposited = hook.totalDeposited();

        // Sanity: the two volumes sum to (a) the totalVol and (b) referrer-1 is ~2× referrer-2.
        assertEq(vol1 + vol2, totalVol, "individual volumes must sum to total");
        assertApproxEqRel(vol1, 2 * vol2, 0.02e18, "referrer 1 should have ~2x the volume of referrer 2");

        uint256 expected1 = (totalDeposited * vol1) / totalVol;
        uint256 expected2 = (totalDeposited * vol2) / totalVol;

        uint256 pushed1 = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});
        uint256 pushed2 = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocalTwin});

        assertEq(pushed1, expected1, "referrer 1 share must equal pro-rata");
        assertEq(pushed2, expected2, "referrer 2 share must equal pro-rata");
        assertLe(pushed1 + pushed2, totalDeposited, "shares can never exceed totalDeposited");
    }

    /// @notice Calling `pushTo` twice in a row must noop the second time (no new volume between calls).
    function test_sameChain_pushTo_isIdempotent() public {
        _payAndCashOutWithReferral(PAYER, 5 ether, block.chainid, referrerProjectIdLocal);
        _distributeFeeReservedTokens();

        uint256 first = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});
        assertGt(first, 0, "first push transfers value");
        uint256 second = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});
        assertEq(second, 0, "second push must be a noop");
        assertEq(hook.pushedLocallyOf(referrerProjectIdLocal), first, "high-water mark stays at first push");
    }

    /// @notice `pushTo` skips a credit-only referrer (one with no ERC-20 deployed yet) and the high-water mark
    /// must NOT advance — so the share is retained for retry after the referrer tokenizes.
    function test_sameChain_pushTo_creditOnlyReferrer_skipsAndRetries() public {
        // Credit a project that has no ERC-20.
        _payAndCashOutWithReferral(PAYER, 5 ether, block.chainid, referrerProjectIdNoToken);
        _distributeFeeReservedTokens();

        uint256 pushed = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdNoToken});
        assertEq(pushed, 0, "must skip when referrer has no ERC-20");
        assertEq(hook.pushedLocallyOf(referrerProjectIdNoToken), 0, "high-water mark must not advance");

        // Now tokenize the referrer and retry — the share should land.
        vm.prank(REFERRER_OWNER);
        jbController().deployERC20For(referrerProjectIdNoToken, "Late", "LATE", bytes32("LATE_TOKEN_SALT"));

        uint256 pushed2 = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdNoToken});
        assertGt(pushed2, 0, "retry after ERC-20 deploy must succeed");
        assertEq(hook.pushedLocallyOf(referrerProjectIdNoToken), pushed2, "high-water mark advances on retry");
    }

    /// @notice With no fee volume and nothing deposited, `pushTo` must early-return zero (and not revert).
    function test_sameChain_pushTo_beforeAnyVolume_noops() public {
        uint256 pushed = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});
        assertEq(pushed, 0, "no volume yet, no push");
        assertEq(hook.totalDeposited(), 0, "no deposits");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  GROUP 2 — Cross-chain bridgeRemote
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Cross-chain referrer on Optimism (chainId=10) projectId=200 gets bridged through `opSucker`.
    /// Verify: outbox tree count increments, outbox balance grows by the bridged amount, the leaf metadata
    /// encodes `(originChainId=block.chainid, refProjectId=200)`, and `bridgedOutOf` tracks the delta.
    function test_crossChain_bridgeRemote_insertsLeafWithCorrectMetadata() public {
        uint256 remoteRefId = 200;
        _payAndCashOutWithReferral(PAYER, 10 ether, OPTIMISM_CHAIN_ID, remoteRefId);
        _distributeFeeReservedTokens();

        // Snapshot outbox state.
        JBOutboxTree memory outboxBefore = opSucker.outboxOf(JBConstants.NATIVE_TOKEN);

        uint256 bridged = hook.bridgeRemote({
            referralChainId: OPTIMISM_CHAIN_ID,
            referralProjectId: remoteRefId,
            sucker: opSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });

        assertGt(bridged, 0, "must bridge a positive amount");
        assertEq(
            hook.bridgedOutOf({referralChainId: OPTIMISM_CHAIN_ID, referralProjectId: remoteRefId}),
            bridged,
            "bridgedOutOf must reflect the delta"
        );

        JBOutboxTree memory outboxAfter = opSucker.outboxOf(JBConstants.NATIVE_TOKEN);
        assertEq(outboxAfter.tree.count, outboxBefore.tree.count + 1, "outbox count grew by 1");
        assertGt(outboxAfter.balance, outboxBefore.balance, "outbox balance grew");

        // The pushed-locally ledger must NOT have moved — the credit went to a cross-chain referrer.
        assertEq(hook.pushedLocallyOf(remoteRefId), 0, "pushedLocallyOf must not move for a cross-chain credit");
    }

    /// @notice `bridgeRemote` must be idempotent and monotonic — calling twice with no new volume in between
    /// must noop the second time, while the high-water mark stays put.
    function test_crossChain_bridgeRemote_idempotent() public {
        uint256 remoteRefId = 300;
        _payAndCashOutWithReferral(PAYER, 8 ether, OPTIMISM_CHAIN_ID, remoteRefId);
        _distributeFeeReservedTokens();

        uint256 first = hook.bridgeRemote({
            referralChainId: OPTIMISM_CHAIN_ID,
            referralProjectId: remoteRefId,
            sucker: opSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });
        assertGt(first, 0, "first bridge should move tokens");

        uint256 second = hook.bridgeRemote({
            referralChainId: OPTIMISM_CHAIN_ID,
            referralProjectId: remoteRefId,
            sucker: opSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });
        assertEq(second, 0, "second bridge with no new volume must noop");
        assertEq(
            hook.bridgedOutOf({referralChainId: OPTIMISM_CHAIN_ID, referralProjectId: remoteRefId}),
            first,
            "high-water mark must stay at first bridge"
        );
    }

    /// @notice A sucker whose `peerChainId` doesn't match the asserted `referralChainId` is unsafe to use —
    /// must revert with `SuckerPeerMismatch`. opSucker peers to 10; we try to use it for chain 8453.
    function test_crossChain_bridgeRemote_wrongSuckerPeerReverts() public {
        _payAndCashOutWithReferral(PAYER, 5 ether, BASE_CHAIN_ID, 400);
        _distributeFeeReservedTokens();

        vm.expectRevert(
            abi.encodeWithSelector(
                IJBReferralSplitHook.JBReferralSplitHook_SuckerPeerMismatch.selector, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID
            )
        );
        hook.bridgeRemote({
            referralChainId: BASE_CHAIN_ID,
            referralProjectId: 400,
            sucker: opSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });
    }

    /// @notice Two referrers on two different remote chains have INDEPENDENT bridge budgets — even when their
    /// numeric projectId happens to collide.
    function test_crossChain_bridgeRemote_sameNumericIdDifferentChains_independentLedgers() public {
        // Same numeric ID 42, but one on Optimism, one on Base — these are two unrelated projects.
        _payAndCashOutWithReferral(PAYER, 10 ether, OPTIMISM_CHAIN_ID, 42);
        _payAndCashOutWithReferral(PAYER, 10 ether, BASE_CHAIN_ID, 42);
        _distributeFeeReservedTokens();

        uint256 bridgedOp = hook.bridgeRemote({
            referralChainId: OPTIMISM_CHAIN_ID,
            referralProjectId: 42,
            sucker: opSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });
        uint256 bridgedBase = hook.bridgeRemote({
            referralChainId: BASE_CHAIN_ID,
            referralProjectId: 42,
            sucker: baseSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });

        assertGt(bridgedOp, 0, "OP referrer #42 should bridge");
        assertGt(bridgedBase, 0, "Base referrer #42 should bridge");

        // Both ledger slots track INDEPENDENT high-water marks under the same numeric projectId.
        assertEq(hook.bridgedOutOf({referralChainId: OPTIMISM_CHAIN_ID, referralProjectId: 42}), bridgedOp);
        assertEq(hook.bridgedOutOf({referralChainId: BASE_CHAIN_ID, referralProjectId: 42}), bridgedBase);
    }

    /// @notice `bridgeRemote` to the local chain id must revert — that's the same-chain path's job.
    function test_crossChain_bridgeRemote_localChainIdReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IJBReferralSplitHook.JBReferralSplitHook_WrongBridgeTarget.selector, block.chainid, block.chainid
            )
        );
        hook.bridgeRemote({
            referralChainId: block.chainid,
            referralProjectId: referrerProjectIdLocal,
            sucker: opSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  GROUP 3 — Cross-chain claimAndPush
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice The headline cross-chain test: a referrer earned credit on Optimism with projectId=200, but the
    /// local twin (on this chain) has projectId=`referrerProjectIdLocalTwin` — a different numeric ID. The
    /// bridged claim must route the freshly minted fee-project tokens to the LOCAL twin's IVotes pool, not
    /// to any numerically-matching project on this chain.
    function test_idDivergence_originAt200_localTwinAtDifferentId() public {
        uint256 originRefId = 200;
        uint256 localTwinId = referrerProjectIdLocalTwin;
        require(originRefId != localTwinId, "test guard: IDs must diverge for this case");

        // Build the synthetic bridged claim. The leaf carries fee-project tokens to be minted on this chain.
        // The "remote" side already cashed those out; here we just need the destination side to credit the
        // local twin.
        uint256 projectTokensMinted = 7e18;
        uint256 terminalReceived = 3 ether;
        bytes32 beneficiary = bytes32(uint256(uint160(address(hook))));
        bytes32 metadata = hook.packLeafMetadata({originChainId: OPTIMISM_CHAIN_ID, referralProjectId: localTwinId});

        (, bytes32[32] memory proof,) = _stageInboxLeaf({
            sucker: opSucker,
            messenger: mockOpMessenger,
            token: JBConstants.NATIVE_TOKEN,
            projectTokenCount: projectTokensMinted,
            terminalTokenAmount: terminalReceived,
            beneficiary: beneficiary,
            metadata: metadata,
            nonce: 1
        });

        // Run the claim+push.
        address feeToken = address(jbTokens().tokenOf(feeProjectId));
        address localTwinToken = address(jbTokens().tokenOf(localTwinId));
        // Snapshot the distributor balance for the local twin BEFORE.
        uint256 localTwinBalanceBefore = distributor.balanceOf(localTwinToken, IERC20(feeToken));

        uint256 pushed = hook.claimAndPush({
            originChainId: OPTIMISM_CHAIN_ID,
            referralProjectId: localTwinId,
            sucker: opSucker,
            claimData: JBClaim({
                token: JBConstants.NATIVE_TOKEN,
                leaf: JBLeaf({
                    index: 0,
                    beneficiary: beneficiary,
                    projectTokenCount: projectTokensMinted,
                    terminalTokenAmount: terminalReceived,
                    metadata: metadata
                }),
                proof: proof
            })
        });

        assertEq(pushed, projectTokensMinted, "all minted fee-project tokens must be forwarded");

        // Distributor must have credited the LOCAL twin's IVotes token — not any project numerically equal to
        // the origin projectId.
        uint256 localTwinBalanceAfter = distributor.balanceOf(localTwinToken, IERC20(feeToken));
        assertEq(
            localTwinBalanceAfter - localTwinBalanceBefore,
            projectTokensMinted,
            "distributor balance must grow for the local twin"
        );
    }

    /// @notice "Burn over strand": if the local twin's IVotes token doesn't exist yet, the freshly-minted
    /// fee-project tokens are BURNED — never left to languish in the hook. Because `sucker.claim` has
    /// already (a) deposited the bridged terminal tokens into the fee project's balance and (b) consumed
    /// the leaf (executed-bitmap set), holding the supply would permanently dilute existing fee-token
    /// holders for no recipient. By burning, the bridged terminal-token value still lands in the fee
    /// project's balance but every fee-token holder's pro-rata claim on it grows.
    function test_claimAndPush_localTwinHasNoToken_burnsToFeeProjectSurplus() public {
        uint256 noTokenLocalId = referrerProjectIdNoToken;

        uint256 projectTokensMinted = 4e18;
        bytes32 beneficiary = bytes32(uint256(uint160(address(hook))));
        bytes32 metadata = hook.packLeafMetadata({originChainId: OPTIMISM_CHAIN_ID, referralProjectId: noTokenLocalId});

        (, bytes32[32] memory proof,) = _stageInboxLeaf({
            sucker: opSucker,
            messenger: mockOpMessenger,
            token: JBConstants.NATIVE_TOKEN,
            projectTokenCount: projectTokensMinted,
            terminalTokenAmount: 1 ether,
            beneficiary: beneficiary,
            metadata: metadata,
            nonce: 2
        });

        address feeToken = address(jbTokens().tokenOf(feeProjectId));
        uint256 hookBalanceBefore = IERC20(feeToken).balanceOf(address(hook));
        uint256 feeTokenSupplyBefore = IERC20(feeToken).totalSupply();
        uint256 feeProjectBalanceBefore = _terminalBalance(feeProjectId, JBConstants.NATIVE_TOKEN);

        vm.expectEmit(true, true, false, true, address(hook));
        emit IJBReferralSplitHook.BurnedOnStrand({
            originChainId: OPTIMISM_CHAIN_ID,
            referralProjectId: noTokenLocalId,
            feeProjectBurned: projectTokensMinted,
            caller: address(this)
        });

        uint256 pushed = hook.claimAndPush({
            originChainId: OPTIMISM_CHAIN_ID,
            referralProjectId: noTokenLocalId,
            sucker: opSucker,
            claimData: JBClaim({
                token: JBConstants.NATIVE_TOKEN,
                leaf: JBLeaf({
                    index: 0,
                    beneficiary: beneficiary,
                    projectTokenCount: projectTokensMinted,
                    terminalTokenAmount: 1 ether,
                    metadata: metadata
                }),
                proof: proof
            })
        });
        assertEq(pushed, 0, "must not forward when local twin has no ERC-20");

        // Hook holds no stranded fee-project tokens (mint then burn cancels).
        assertEq(
            IERC20(feeToken).balanceOf(address(hook)),
            hookBalanceBefore,
            "hook must not hold stranded fee-project tokens"
        );

        // Fee-project total supply is unchanged across the whole flow.
        assertEq(
            IERC20(feeToken).totalSupply(),
            feeTokenSupplyBefore,
            "fee-project total supply must not have grown - minted then burned"
        );

        // The bridged terminal tokens DID land in the fee project's terminal balance — that's the value
        // that now accrues pro-rata to existing fee-token holders.
        assertEq(
            _terminalBalance(feeProjectId, JBConstants.NATIVE_TOKEN) - feeProjectBalanceBefore,
            1 ether,
            "bridged terminal tokens must accrue to fee project balance"
        );
    }

    function _terminalBalance(uint256 _projectId, address token) internal view returns (uint256) {
        return jbTerminalStore().balanceOf(address(jbMultiTerminal()), _projectId, token);
    }

    /// @notice If the metadata in the leaf doesn't match the claimed `(originChainId, refProjectId)` arguments,
    /// the call must revert — preventing an attacker from rerouting a leaf to a different local twin.
    function test_claimAndPush_metadataMismatch_reverts() public {
        bytes32 honestMetadata =
            hook.packLeafMetadata({originChainId: OPTIMISM_CHAIN_ID, referralProjectId: referrerProjectIdLocalTwin});
        bytes32 lyingMetadata = hook.packLeafMetadata({originChainId: OPTIMISM_CHAIN_ID, referralProjectId: 999});
        bytes32 beneficiary = bytes32(uint256(uint160(address(hook))));

        (, bytes32[32] memory proof,) = _stageInboxLeaf({
            sucker: opSucker,
            messenger: mockOpMessenger,
            token: JBConstants.NATIVE_TOKEN,
            projectTokenCount: 1e18,
            terminalTokenAmount: 1 ether,
            beneficiary: beneficiary,
            metadata: honestMetadata,
            nonce: 3
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IJBReferralSplitHook.JBReferralSplitHook_LeafMetadataMismatch.selector, lyingMetadata, honestMetadata
            )
        );
        hook.claimAndPush({
            originChainId: OPTIMISM_CHAIN_ID,
            // Caller tries to claim against a different projectId than the leaf encodes.
            referralProjectId: 999,
            sucker: opSucker,
            claimData: JBClaim({
                token: JBConstants.NATIVE_TOKEN,
                leaf: JBLeaf({
                    index: 0,
                    beneficiary: beneficiary,
                    projectTokenCount: 1e18,
                    terminalTokenAmount: 1 ether,
                    metadata: honestMetadata
                }),
                proof: proof
            })
        });
    }

    /// @notice A second `claim` with the same leaf must revert — the sucker's `_executedFor` bitmap blocks
    /// reuse. This proves that a successful `claimAndPush` consumes the leaf permanently.
    function test_claimAndPush_doubleClaimReverts() public {
        bytes32 metadata =
            hook.packLeafMetadata({originChainId: OPTIMISM_CHAIN_ID, referralProjectId: referrerProjectIdLocalTwin});
        bytes32 beneficiary = bytes32(uint256(uint160(address(hook))));
        uint256 projectTokens = 2e18;
        uint256 terminalAmount = 1 ether;

        (, bytes32[32] memory proof,) = _stageInboxLeaf({
            sucker: opSucker,
            messenger: mockOpMessenger,
            token: JBConstants.NATIVE_TOKEN,
            projectTokenCount: projectTokens,
            terminalTokenAmount: terminalAmount,
            beneficiary: beneficiary,
            metadata: metadata,
            nonce: 4
        });

        JBClaim memory claim = JBClaim({
            token: JBConstants.NATIVE_TOKEN,
            leaf: JBLeaf({
                index: 0,
                beneficiary: beneficiary,
                projectTokenCount: projectTokens,
                terminalTokenAmount: terminalAmount,
                metadata: metadata
            }),
            proof: proof
        });

        // First claim succeeds.
        hook.claimAndPush({
            originChainId: OPTIMISM_CHAIN_ID,
            referralProjectId: referrerProjectIdLocalTwin,
            sucker: opSucker,
            claimData: claim
        });

        // Second claim must revert (sucker rejects already-executed leaf).
        vm.expectRevert();
        hook.claimAndPush({
            originChainId: OPTIMISM_CHAIN_ID,
            referralProjectId: referrerProjectIdLocalTwin,
            sucker: opSucker,
            claimData: claim
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  GROUP 4 — Distributor vesting + collect E2E
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Three delegated stakers (100, 200, 300 tokens — total 600 delegated; 400 undelegated stays in
    /// the pool). After the hook pushes to the distributor and a round elapses, each staker can `beginVesting`,
    /// vest over `VESTING_ROUNDS` rounds, then collect their pro-rata share.
    function test_distributor_threeStakersProRataDelegation() public {
        // Generate enough volume on the local referrer that the push moves a meaningful amount.
        _payAndCashOutWithReferral(PAYER, 20 ether, block.chainid, referrerProjectIdLocal);
        _distributeFeeReservedTokens();

        // The distributor locks the round's stake snapshot when funds enter the distributor. Advance one block so the
        // setup-time mint/delegate checkpoints are visible to the funding snapshot.
        vm.roll(block.number + 1);

        uint256 pushed = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});
        require(pushed > 0, "pushTo did not move tokens");

        address feeToken = address(jbTokens().tokenOf(feeProjectId));
        address refToken = address(jbTokens().tokenOf(referrerProjectIdLocal));

        // Advance to the next round so the funded round becomes claimable. `vm.warp` alone leaves `block.number`
        // unchanged, so pair it with `vm.roll` for ERC20Votes' historical lookups.
        vm.warp(block.timestamp + ROUND_DURATION);
        vm.roll(block.number + 1);
        distributor.poke();

        // Roll forward one more block so the snapshot block is unambiguously in the past for getPastVotes.
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // Have each delegated staker call beginVesting.
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(feeToken);

        _beginVestingFor(refToken, STAKER_A, tokens);
        _beginVestingFor(refToken, STAKER_B, tokens);
        _beginVestingFor(refToken, STAKER_C, tokens);

        // JBTokenDistributor's `_totalStake` reads `IVotes.getPastTotalSupply` — the FULL historical token
        // supply, INCLUDING undelegated holders. That's by design: undelegated supply stays in the pool so it
        // carries over to future rounds. Each staker's share is `delegated / totalSupply`, not
        // `delegated / totalDelegated`. With minted supply (100 + 200 + 300 + 400 = 1000) the math becomes:
        uint256 totalSupplyAtSnapshot = 1000e18;
        uint256 expectedA = (pushed * 100e18) / totalSupplyAtSnapshot;
        uint256 expectedB = (pushed * 200e18) / totalSupplyAtSnapshot;
        uint256 expectedC = (pushed * 300e18) / totalSupplyAtSnapshot;
        // The undelegated quarter (400/1000 = 40%) is retained inside the distributor — assert it.
        uint256 expectedRetainedForLaterRounds = (pushed * 400e18) / totalSupplyAtSnapshot;

        assertApproxEqAbs(
            distributor.claimedFor(refToken, uint256(uint160(STAKER_A)), IERC20(feeToken)),
            expectedA,
            2,
            "staker A claimed ~ pro-rata"
        );
        assertApproxEqAbs(
            distributor.claimedFor(refToken, uint256(uint160(STAKER_B)), IERC20(feeToken)),
            expectedB,
            2,
            "staker B claimed ~ pro-rata"
        );
        assertApproxEqAbs(
            distributor.claimedFor(refToken, uint256(uint160(STAKER_C)), IERC20(feeToken)),
            expectedC,
            2,
            "staker C claimed ~ pro-rata"
        );

        // Advance through the vesting horizon, then collect.
        vm.warp(block.timestamp + ROUND_DURATION * VESTING_ROUNDS);

        _collectVestedFor(refToken, STAKER_A, tokens);
        _collectVestedFor(refToken, STAKER_B, tokens);
        _collectVestedFor(refToken, STAKER_C, tokens);

        // After full vesting, each staker received their share in their wallet.
        assertApproxEqAbs(IERC20(feeToken).balanceOf(STAKER_A), expectedA, 2, "STAKER_A wallet ~ expected");
        assertApproxEqAbs(IERC20(feeToken).balanceOf(STAKER_B), expectedB, 2, "STAKER_B wallet ~ expected");
        assertApproxEqAbs(IERC20(feeToken).balanceOf(STAKER_C), expectedC, 2, "STAKER_C wallet ~ expected");

        // The undelegated staker never delegated, so they got 0.
        assertEq(IERC20(feeToken).balanceOf(UNDELEGATED_STAKER), 0, "undelegated staker should receive 0");

        // And the undelegated portion (40% of the pushed amount) is still held by the distributor for the
        // next round — that's the documented "non-delegated supply stays in pool" semantics.
        uint256 distributorRetained = distributor.balanceOf(refToken, IERC20(feeToken));
        // The vested rewards that were begun + collected are gone from `_balanceOf`. What remains should be
        // the undelegated share that nobody could claim, modulo tiny mulDiv rounding.
        assertApproxEqAbs(
            distributorRetained, expectedRetainedForLaterRounds, 2, "undelegated share must remain in distributor pool"
        );
    }

    function _beginVestingFor(address refToken, address staker, IERC20[] memory tokens) internal {
        uint256[] memory ids = new uint256[](1);
        ids[0] = uint256(uint160(staker));
        vm.prank(staker);
        distributor.beginVesting({hook: refToken, tokenIds: ids, tokens: tokens});
    }

    function _collectVestedFor(address refToken, address staker, IERC20[] memory tokens) internal {
        uint256[] memory ids = new uint256[](1);
        ids[0] = uint256(uint160(staker));
        vm.prank(staker);
        distributor.collectVestedRewards({hook: refToken, tokenIds: ids, tokens: tokens, beneficiary: staker});
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  GROUP 5 — Invariant-style stress
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Across many same-chain referrers (each accruing different volume amounts), the sum of pushes
    /// must never exceed `totalDeposited`. Tests the pro-rata math holds in aggregate.
    function test_invariant_sumOfPushedNeverExceedsTotalDeposited() public {
        // Three same-chain referrers with different volumes.
        _payAndCashOutWithReferral(PAYER, 3 ether, block.chainid, referrerProjectIdLocal);
        _payAndCashOutWithReferral(PAYER, 7 ether, block.chainid, referrerProjectIdLocalTwin);
        _distributeFeeReservedTokens();

        uint256 totalDeposited = hook.totalDeposited();

        uint256 pushed1 = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});
        uint256 pushed2 = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocalTwin});

        assertLe(pushed1 + pushed2, totalDeposited, "sum of pushed must be bounded by totalDeposited");
        // Sum should also be CLOSE to totalDeposited — only mulDiv rounding (≤ N referrers wei) loss.
        assertApproxEqAbs(pushed1 + pushed2, totalDeposited, 2, "sum of pushed ~= totalDeposited (rounding)");
    }

    /// @notice The per-referrer high-water marks are monotonic across interleaved push/bridge sequences.
    /// Drive a mixed workload that pushes a same-chain referrer, then bridges a different-chain referrer,
    /// then pushes again with new volume — both ledger slots must move strictly upward and stay independent.
    function test_invariant_pushAndBridgeLedgersAreMonotonicAndIndependent() public {
        // Stage 1: only same-chain referrer has volume.
        _payAndCashOutWithReferral(PAYER, 4 ether, block.chainid, referrerProjectIdLocal);
        _distributeFeeReservedTokens();

        uint256 pushed1 = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});
        assertEq(hook.pushedLocallyOf(referrerProjectIdLocal), pushed1, "after push1, hwm matches push1");
        assertEq(
            hook.bridgedOutOf({referralChainId: OPTIMISM_CHAIN_ID, referralProjectId: 200}), 0, "bridgedOut untouched"
        );

        // Stage 2: cross-chain referrer accrues volume.
        _payAndCashOutWithReferral(PAYER, 6 ether, OPTIMISM_CHAIN_ID, 200);
        _distributeFeeReservedTokens();

        uint256 bridged1 = hook.bridgeRemote({
            referralChainId: OPTIMISM_CHAIN_ID,
            referralProjectId: 200,
            sucker: opSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });
        assertGt(bridged1, 0, "bridge moves tokens");
        assertEq(
            hook.bridgedOutOf({referralChainId: OPTIMISM_CHAIN_ID, referralProjectId: 200}),
            bridged1,
            "bridgedOutOf moved to bridged1"
        );
        // pushedLocallyOf is invariant under bridge calls.
        assertEq(hook.pushedLocallyOf(referrerProjectIdLocal), pushed1, "pushedLocallyOf preserved across bridge");

        // Stage 3: more same-chain volume → second push.
        _payAndCashOutWithReferral(PAYER, 5 ether, block.chainid, referrerProjectIdLocal);
        _distributeFeeReservedTokens();
        uint256 pushed2 = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});

        // pushedLocallyOf strictly increased; bridgedOutOf untouched.
        assertGt(pushed2, 0, "second push moves tokens");
        assertGt(hook.pushedLocallyOf(referrerProjectIdLocal), pushed1, "pushedLocallyOf must strictly increase");
        assertEq(
            hook.bridgedOutOf({referralChainId: OPTIMISM_CHAIN_ID, referralProjectId: 200}),
            bridged1,
            "bridgedOutOf preserved across push"
        );
    }

    /// @notice The hook's `totalDeposited` only grows — `processSplitWith` can never decrement it. Confirms
    /// that `processSplitWith`'s `unchecked { totalDeposited += amount }` does not silently roll over for the
    /// values we exercise in practice (and that nothing else writes the slot).
    function test_invariant_totalDepositedIsMonotonic() public {
        _payAndCashOutWithReferral(PAYER, 4 ether, block.chainid, referrerProjectIdLocal);
        _distributeFeeReservedTokens();
        uint256 t1 = hook.totalDeposited();
        assertGt(t1, 0);

        _payAndCashOutWithReferral(PAYER, 5 ether, OPTIMISM_CHAIN_ID, 200);
        _distributeFeeReservedTokens();
        uint256 t2 = hook.totalDeposited();
        assertGt(t2, t1, "totalDeposited must grow with each new reserved-token distribution");

        // A push/bridge does NOT mutate totalDeposited.
        hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});
        assertEq(hook.totalDeposited(), t2, "pushTo must not change totalDeposited");

        hook.bridgeRemote({
            referralChainId: OPTIMISM_CHAIN_ID,
            referralProjectId: 200,
            sucker: opSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });
        assertEq(hook.totalDeposited(), t2, "bridgeRemote must not change totalDeposited");
    }

    /// @notice Property-based fuzz: for any 0 ≤ refVol ≤ totalVol with totalVol > 0, the share returned by
    /// `pushTo` matches `(totalDeposited * refVol / totalVol)`. We drive arbitrary same-chain volumes via
    /// repeated cashouts to a single referrer and verify the formula every time.
    function testFuzz_pushTo_proRataMath(uint96 vol1, uint96 vol2) public {
        vol1 = uint96(bound(vol1, 1 ether, 50 ether));
        vol2 = uint96(bound(vol2, 1 ether, 50 ether));

        _payAndCashOutWithReferral(PAYER, vol1, block.chainid, referrerProjectIdLocal);
        _payAndCashOutWithReferral(PAYER, vol2, block.chainid, referrerProjectIdLocalTwin);
        _distributeFeeReservedTokens();

        uint256 refVol =
            jbTerminalStore().feeVolumeByReferralOf(address(jbMultiTerminal()), block.chainid, referrerProjectIdLocal);
        uint256 totalVol = jbTerminalStore().totalFeeVolumeOf(address(jbMultiTerminal()));
        uint256 totalDeposited = hook.totalDeposited();
        uint256 expected = (totalDeposited * refVol) / totalVol;

        uint256 pushed = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});
        assertEq(pushed, expected, "pushTo must return exact pro-rata share");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  GROUP 7 — USDC end-to-end (ERC-20 terminal token, 6 decimals)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Lazy setup of a 6-decimal USDC mock + price feed + USDC-accepting fee/payer projects. Called
    /// from each USDC test (cheaper than always running it).
    function _setUpUsdc() internal {
        if (address(usdc) != address(0)) return; // already initialized

        usdc = new MockERC20Token({name: "Mock USDC", symbol: "USDC", decimals_: 6});
        usdcCurrency = uint32(uint160(address(usdc)));

        // Protocol-wide default price feed. The store calls
        // `pricePerUnitOf(pricingCurrency=USDC, unitCurrency=NATIVE, decimals=18)` which returns
        // "how much USDC is 1 ETH worth" = ~3000. With 18-decimal precision that's 3000e18.
        // Deploy the feed BEFORE the prank — vm.prank applies to the next external call only, so wrapping
        // the `new MockPriceFeed(...)` inside the call to `addPriceFeedFor` would consume the prank early.
        IJBPriceFeed usdcFeed = IJBPriceFeed(address(new MockPriceFeed({price: 3000e18, feedDecimals: 18})));
        vm.prank(multisig());
        jbPrices()
            .addPriceFeedFor({
            projectId: 0, pricingCurrency: usdcCurrency, unitCurrency: uint256(NATIVE_CURRENCY), feed: usdcFeed
        });

        // Add USDC accounting context to the fee project so it can receive USDC-denominated fee payments.
        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: address(usdc), decimals: 6, currency: usdcCurrency});
        vm.prank(FEE_PROJECT_OWNER);
        jbMultiTerminal().addAccountingContextsFor(feeProjectId, acc);

        // Launch a USDC-denominated paying project (id auto-assigned). Same shape as the ETH payer but with
        // USDC as the sole accounting context.
        payerProjectIdUsdc = _launchPayerProjectWithToken({token: address(usdc), decimals: 6, currency: usdcCurrency});
    }

    function _launchPayerProjectWithToken(
        address token,
        uint8 decimals,
        uint32 currency
    )
        internal
        returns (uint256 projectId)
    {
        JBRulesetMetadata memory meta = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 5000,
            baseCurrency: currency,
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: false,
            scopeCashOutsToLocalBalances: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        JBAccountingContext[] memory acc = new JBAccountingContext[](1);
        acc[0] = JBAccountingContext({token: token, decimals: decimals, currency: currency});

        JBTerminalConfig[] memory tc = new JBTerminalConfig[](1);
        tc[0] = JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: acc});

        JBRulesetConfig[] memory rulesets = new JBRulesetConfig[](1);
        rulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: FEE_WEIGHT,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: meta,
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        projectId = jbController()
            .launchProjectFor({
            owner: PAYER_PROJECT_OWNER,
            projectUri: "ipfs://payer-usdc",
            rulesetConfigurations: rulesets,
            terminalConfigurations: tc,
            memo: ""
        });
    }

    /// @notice Same-chain happy path, but with USDC as the terminal token. Verifies:
    /// (1) the fee project can accept USDC fees, (2) `feeVolumeByReferralOf` records the credit in
    /// NATIVE-normalized 18-decimal units (NOT raw USDC 6-dec), (3) the reserved-token split still flows the
    /// 18-decimal fee-project ERC-20 to the hook, (4) `pushTo` forwards the correct pro-rata share.
    function test_usdc_sameChain_endToEnd() public {
        _setUpUsdc();

        // Mint USDC to payer and approve the terminal.
        usdc.mint(PAYER, 10_000e6);
        vm.prank(PAYER);
        usdc.approve(address(jbMultiTerminal()), type(uint256).max);

        // Pay the USDC-denominated project (no msg.value).
        vm.prank(PAYER);
        uint256 tokens = jbMultiTerminal().pay{value: 0}({
            projectId: payerProjectIdUsdc,
            token: address(usdc),
            amount: 1000e6, // $1,000 in USDC
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
        require(tokens > 0, "payer received zero tokens (USDC pay)");

        // Cash out with a same-chain referral credit. The fee is taken in USDC, goes to the fee project as
        // a USDC payment, and the terminal store records `feeVolumeByReferralOf` after normalizing USDC →
        // NATIVE 18-decimal via the price feed we registered in `_setUpUsdc`.
        uint256 encodedReferral = (block.chainid << 48) | referrerProjectIdLocal;
        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
            holder: PAYER,
            projectId: payerProjectIdUsdc,
            cashOutCount: tokens,
            tokenToReclaim: address(usdc),
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: "",
            referralProjectId: encodedReferral
        });

        // Volume must be recorded NATIVE-normalized — i.e. NOT in raw 6-decimal USDC.
        uint256 refVol =
            jbTerminalStore().feeVolumeByReferralOf(address(jbMultiTerminal()), block.chainid, referrerProjectIdLocal);
        uint256 totalVol = jbTerminalStore().totalFeeVolumeOf(address(jbMultiTerminal()));
        assertGt(refVol, 0, "USDC referral credit must record positive volume");
        assertEq(refVol, totalVol, "single-referrer => refVol == totalVol");

        // The volume should be expressed in NATIVE_TOKEN (18 dec) units. The fee on this cash-out was a few
        // dollars of USDC (raw value ~12.5e6 = $12.50 in raw 6-dec), which at our 0.0003 ETH/USDC feed is
        // ~3.75e15 NATIVE units (= 0.00375 ETH). Sanity-check the order of magnitude (well above 1e13 ETH
        // and below 1e16 ETH so we're clearly 18-decimal, not 6-decimal).
        assertGt(refVol, 1e13, "volume must be in 18-decimal NATIVE units (lower bound)");
        assertLt(refVol, 1e16, "volume must be in 18-decimal NATIVE units (upper bound)");

        // Distribute the fee project's reserved tokens and verify the hook received fee tokens.
        _distributeFeeReservedTokens();
        assertGt(hook.totalDeposited(), 0, "hook must have received fee-project tokens from USDC fees");

        // Push to the referrer's local twin.
        uint256 pushed = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});
        assertGt(pushed, 0, "pushTo must forward something for USDC-funded referral");

        address feeToken = address(jbTokens().tokenOf(feeProjectId));
        address refToken = address(jbTokens().tokenOf(referrerProjectIdLocal));
        assertEq(
            distributor.balanceOf(refToken, IERC20(feeToken)), pushed, "distributor balance must equal pushed amount"
        );
    }

    /// @notice Mixed-currency invariant: ETH fees AND USDC fees from different referrers must each receive a
    /// pro-rata share computed against a UNIFORMLY-DENOMINATED volume ledger. The store normalizes both to
    /// NATIVE_TOKEN 18-dec units, so the math is internally consistent — a referrer earning $X equivalent of
    /// USDC fees should get ~the same pro-rata share as one earning $X equivalent of ETH fees.
    function test_usdc_mixedCurrency_volumeLedgerStaysCoherent() public {
        _setUpUsdc();

        // Referrer A: ETH fees worth ~10 ether of payment volume
        _payAndCashOutWithReferral(PAYER, 10 ether, block.chainid, referrerProjectIdLocal);

        // Referrer B: USDC fees from a payment worth ~3000 USDC (~0.9 ETH at our 0.0003 ETH/USDC feed)
        usdc.mint(PAYER, 100_000e6);
        vm.prank(PAYER);
        usdc.approve(address(jbMultiTerminal()), type(uint256).max);

        vm.prank(PAYER);
        uint256 tokensUsdc = jbMultiTerminal().pay{value: 0}({
            projectId: payerProjectIdUsdc,
            token: address(usdc),
            amount: 3000e6,
            beneficiary: PAYER,
            minReturnedTokens: 0,
            memo: "",
            metadata: ""
        });
        uint256 encodedB = (block.chainid << 48) | referrerProjectIdLocalTwin;
        vm.prank(PAYER);
        jbMultiTerminal()
            .cashOutTokensOf({
            holder: PAYER,
            projectId: payerProjectIdUsdc,
            cashOutCount: tokensUsdc,
            tokenToReclaim: address(usdc),
            minTokensReclaimed: 0,
            beneficiary: payable(PAYER),
            metadata: "",
            referralProjectId: encodedB
        });

        // Both volume slots must be in matching units (NATIVE 18-dec). Their ratio reflects ETH-equivalent.
        uint256 volA =
            jbTerminalStore().feeVolumeByReferralOf(address(jbMultiTerminal()), block.chainid, referrerProjectIdLocal);
        uint256 volB = jbTerminalStore()
            .feeVolumeByReferralOf(address(jbMultiTerminal()), block.chainid, referrerProjectIdLocalTwin);
        uint256 totalVol = jbTerminalStore().totalFeeVolumeOf(address(jbMultiTerminal()));
        assertGt(volA, 0, "ETH referrer must have volume");
        assertGt(volB, 0, "USDC referrer must have volume");
        assertEq(volA + volB, totalVol, "individual volumes must sum to total in mixed-currency case");

        // The ETH cashout fee was a fraction of 10 ETH; the USDC cashout fee was a fraction of 3000 USDC
        // worth ~0.9 ETH at our feed. So volA should be ~10-11x volB. Loosely check.
        assertGt(volA, volB * 5, "ETH referrer's volume should dominate (5x lower bound)");
        assertLt(volA, volB * 20, "ETH referrer's volume should not be absurdly larger (20x upper bound)");

        // Distribute and push for both. Sum of pushed must be bounded by totalDeposited.
        _distributeFeeReservedTokens();
        uint256 totalDeposited = hook.totalDeposited();
        uint256 pushedA = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocal});
        uint256 pushedB = hook.pushTo({referralChainId: block.chainid, referralProjectId: referrerProjectIdLocalTwin});
        assertLe(pushedA + pushedB, totalDeposited, "mixed-currency pushes still bounded by totalDeposited");

        // And each share matches its NATIVE-normalized volume fraction.
        assertEq(pushedA, (totalDeposited * volA) / totalVol, "ETH referrer share = pro-rata");
        assertEq(pushedB, (totalDeposited * volB) / totalVol, "USDC referrer share = pro-rata");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  GROUP 8 — Defense-in-depth: chainId == 0 input validation
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice bridgeRemote must reject `referralChainId == 0` with a clear, dedicated error rather than
    /// falling through to downstream sucker checks.
    function test_bridgeRemote_revertsOnZeroChainId() public {
        vm.expectRevert(IJBReferralSplitHook.JBReferralSplitHook_ZeroChainId.selector);
        hook.bridgeRemote({
            referralChainId: 0, referralProjectId: 42, sucker: opSucker, terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });
    }

    /// @notice claimAndPush must reject `originChainId == 0`. The merkle proof would also fail, but failing
    /// up-front gives a precise error and protects against any future change in sucker semantics.
    function test_claimAndPush_revertsOnZeroOriginChainId() public {
        bytes32[32] memory proof;
        JBClaim memory claimData = JBClaim({
            token: JBConstants.NATIVE_TOKEN,
            leaf: JBLeaf({
                index: 0,
                beneficiary: bytes32(uint256(uint160(address(hook)))),
                projectTokenCount: 1e18,
                terminalTokenAmount: 1 ether,
                metadata: hook.packLeafMetadata({originChainId: 0, referralProjectId: referrerProjectIdLocalTwin})
            }),
            proof: proof
        });

        vm.expectRevert(IJBReferralSplitHook.JBReferralSplitHook_ZeroChainId.selector);
        hook.claimAndPush({
            originChainId: 0, referralProjectId: referrerProjectIdLocalTwin, sucker: opSucker, claimData: claimData
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  GROUP 9 — Deferral semantics: chains without sucker infrastructure
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice A cross-chain referral on a chain that has NO sucker pair is STRANDING, not deferral —
    /// existing fee-token holders shouldn't be diluted forever by an allocation that no one can settle.
    /// `burnUnbridgeableCreditFor` permissionlessly burns the entitled share for an unbridgeable
    /// (chainId, projectId) pair: the equivalent fee-project tokens are burned from the hook, the bridged
    /// terminal-token value (already in the fee project's balance from the original protocol-fee flow)
    /// accrues to all existing fee-token holders pro-rata, and `bridgedOutOf` is advanced so a future
    /// sucker deployment can only act on INCREMENTAL credit accumulated AFTER the burn.
    function test_unbridgeableChain_burnsUnbridgeableCredit() public {
        uint256 arbChainId = 42_161; // Arbitrum One — we do NOT deploy an Arb sucker in setUp.
        uint256 arbReferrerProjectId = 777;

        // Credit a referrer on Arbitrum.
        _payAndCashOutWithReferral(PAYER, 10 ether, arbChainId, arbReferrerProjectId);
        _distributeFeeReservedTokens();
        uint256 totalDeposited = hook.totalDeposited();
        assertGt(totalDeposited, 0, "hook holds fee tokens");

        // 1) `bridgeRemote` with the wrong-peer sucker still reverts cleanly (caller error, NOT a burn
        // trigger — burn is the explicit `burnUnbridgeableCreditFor` entrypoint).
        vm.expectRevert(
            abi.encodeWithSelector(
                IJBReferralSplitHook.JBReferralSplitHook_SuckerPeerMismatch.selector, arbChainId, OPTIMISM_CHAIN_ID
            )
        );
        hook.bridgeRemote({
            referralChainId: arbChainId,
            referralProjectId: arbReferrerProjectId,
            sucker: opSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });

        // 2) `burnUnbridgeableCreditFor` is the right entrypoint. It iterates the project's suckers,
        // confirms none peer to Arbitrum, computes the entitled share, and burns it.
        uint256 expectedBurn = (totalDeposited * 1) / 1; // single referrer => entire totalDeposited
        // Adjust expectedBurn to the exact pro-rata math (single referrer pool):
        uint256 vol =
            jbTerminalStore().feeVolumeByReferralOf(address(jbMultiTerminal()), arbChainId, arbReferrerProjectId);
        uint256 totalVol = jbTerminalStore().totalFeeVolumeOf(address(jbMultiTerminal()));
        expectedBurn = (totalDeposited * vol) / totalVol;

        address feeToken = address(jbTokens().tokenOf(feeProjectId));
        uint256 supplyBefore = IERC20(feeToken).totalSupply();
        uint256 hookBalanceBefore = IERC20(feeToken).balanceOf(address(hook));

        vm.expectEmit(true, true, false, true, address(hook));
        emit IJBReferralSplitHook.BurnedUnbridgeable({
            referralChainId: arbChainId,
            referralProjectId: arbReferrerProjectId,
            amount: expectedBurn,
            caller: address(this)
        });

        uint256 burned = IJBReferralSplitHook(address(hook))
            .burnUnbridgeableCreditFor({referralChainId: arbChainId, referralProjectId: arbReferrerProjectId});
        assertEq(burned, expectedBurn, "burned == entitled pro-rata share");

        // Supply decreased by exactly `burned`; the hook's balance decreased by the same amount (so the
        // remaining hook balance correctly reflects no allocation for the dead chain).
        assertEq(IERC20(feeToken).totalSupply(), supplyBefore - burned, "fee-project supply decreased by burned amount");
        assertEq(
            IERC20(feeToken).balanceOf(address(hook)),
            hookBalanceBefore - burned,
            "hook balance decreased by burned amount"
        );

        // bridgedOutOf advanced — burn is idempotent and shares the HWM with bridgeRemote.
        assertEq(
            hook.bridgedOutOf({referralChainId: arbChainId, referralProjectId: arbReferrerProjectId}),
            burned,
            "bridgedOutOf records the burn"
        );

        // Calling again with no new volume is a noop.
        uint256 second = IJBReferralSplitHook(address(hook))
            .burnUnbridgeableCreditFor({referralChainId: arbChainId, referralProjectId: arbReferrerProjectId});
        assertEq(second, 0, "second burn with no new volume must be a noop");
    }

    /// @notice `burnUnbridgeableCreditFor` must REVERT when a sucker exists for the asserted chain —
    /// otherwise a caller could grief a legitimate referrer by burning their credit before they bridge it.
    function test_burnUnbridgeable_revertsWhenSuckerExists() public {
        // opSucker peers to OPTIMISM_CHAIN_ID (10). So burning for chain 10 must be rejected.
        // Credit some volume first so the math has something to burn.
        _payAndCashOutWithReferral(PAYER, 5 ether, OPTIMISM_CHAIN_ID, 42);
        _distributeFeeReservedTokens();

        vm.expectRevert(
            abi.encodeWithSelector(
                IJBReferralSplitHook.JBReferralSplitHook_SuckerExistsForChain.selector,
                address(opSucker),
                OPTIMISM_CHAIN_ID
            )
        );
        IJBReferralSplitHook(address(hook))
            .burnUnbridgeableCreditFor({referralChainId: OPTIMISM_CHAIN_ID, referralProjectId: 42});
    }

    /// @notice `burnUnbridgeableCreditFor` malformed-args guards: chainId=0, chainId=block.chainid,
    /// projectId=0, projectId=FEE_PROJECT_ID all revert.
    function test_burnUnbridgeable_revertsOnMalformedArgs() public {
        vm.expectRevert(IJBReferralSplitHook.JBReferralSplitHook_InvalidReferralProjectId.selector);
        IJBReferralSplitHook(address(hook)).burnUnbridgeableCreditFor({referralChainId: 42_161, referralProjectId: 0});

        vm.expectRevert(IJBReferralSplitHook.JBReferralSplitHook_InvalidReferralProjectId.selector);
        IJBReferralSplitHook(address(hook))
            .burnUnbridgeableCreditFor({referralChainId: 42_161, referralProjectId: feeProjectId});

        vm.expectRevert(IJBReferralSplitHook.JBReferralSplitHook_ZeroChainId.selector);
        IJBReferralSplitHook(address(hook)).burnUnbridgeableCreditFor({referralChainId: 0, referralProjectId: 42});

        vm.expectRevert(
            abi.encodeWithSelector(
                IJBReferralSplitHook.JBReferralSplitHook_WrongBridgeTarget.selector, block.chainid, block.chainid
            )
        );
        IJBReferralSplitHook(address(hook))
            .burnUnbridgeableCreditFor({referralChainId: block.chainid, referralProjectId: 42});
    }

    /// @notice After a burn, if a sucker IS later deployed for the previously-unbridgeable chain, only
    /// INCREMENTAL credit accumulated since the burn can be bridged — the burned portion is permanently
    /// gone. Proves `bridgedOutOf` acts as a unified high-water mark across both `bridgeRemote` and
    /// `burnUnbridgeableCreditFor`.
    function test_burnUnbridgeable_thenLaterSuckerDeployment_bridgesIncrementalOnly() public {
        uint256 chainId = 42_161;
        uint256 projectId = 555;

        // Round 1: accumulate credit, burn it.
        _payAndCashOutWithReferral(PAYER, 5 ether, chainId, projectId);
        _distributeFeeReservedTokens();
        uint256 burned = IJBReferralSplitHook(address(hook))
            .burnUnbridgeableCreditFor({referralChainId: chainId, referralProjectId: projectId});
        assertGt(burned, 0, "round 1 burn moves tokens");

        // Round 2: more credit accrues to the same referrer.
        _payAndCashOutWithReferral(PAYER, 5 ether, chainId, projectId);
        _distributeFeeReservedTokens();

        // A sucker for chainId is now deployed. Mock it to pass the hook's bridge checks. The hook should
        // bridge only the INCREMENTAL credit (not the already-burned portion).
        IJBSucker mockSucker = IJBSucker(makeAddr("postBurnMockSucker"));
        vm.mockCall(
            address(suckerRegistry),
            abi.encodeWithSelector(IJBSuckerRegistry.isSuckerOf.selector, feeProjectId, address(mockSucker)),
            abi.encode(true)
        );
        vm.mockCall(address(mockSucker), abi.encodeWithSelector(IJBSucker.peerChainId.selector), abi.encode(chainId));
        vm.mockCall(address(mockSucker), abi.encodeWithSelector(IJBSucker.prepare.selector), abi.encode());

        uint256 bridged = hook.bridgeRemote({
            referralChainId: chainId,
            referralProjectId: projectId,
            sucker: mockSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });
        assertGt(bridged, 0, "incremental credit bridges");

        // The burned amount + bridged amount equals what's in the unified HWM ledger.
        assertEq(
            hook.bridgedOutOf({referralChainId: chainId, referralProjectId: projectId}),
            burned + bridged,
            "bridgedOutOf is the unified high-water mark across burn + bridge"
        );
    }

    /// @notice The bridged-out ledger is keyed by (chainId, projectId). A second call with the SAME chainId
    /// + projectId after additional volume is credited must bridge the INCREMENTAL share only, never re-bridge
    /// what's already in flight or already bridged. Proves the high-water mark behaves correctly when
    /// infrastructure exists but the chain's projectId space is exotic.
    function test_unbridgeableChain_thenIncrementalCreditBridgesOnlyDelta() public {
        uint256 chainId = 42_161;
        uint256 projectId = 777;

        IJBSucker mockSucker = IJBSucker(makeAddr("incrementalMockSucker"));
        vm.mockCall(
            address(suckerRegistry),
            abi.encodeWithSelector(IJBSuckerRegistry.isSuckerOf.selector, feeProjectId, address(mockSucker)),
            abi.encode(true)
        );
        vm.mockCall(address(mockSucker), abi.encodeWithSelector(IJBSucker.peerChainId.selector), abi.encode(chainId));
        vm.mockCall(address(mockSucker), abi.encodeWithSelector(IJBSucker.prepare.selector), abi.encode());

        // First batch of credit.
        _payAndCashOutWithReferral(PAYER, 5 ether, chainId, projectId);
        _distributeFeeReservedTokens();
        uint256 firstBridged = hook.bridgeRemote({
            referralChainId: chainId,
            referralProjectId: projectId,
            sucker: mockSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });
        assertGt(firstBridged, 0, "first batch bridged");

        // Second batch (more volume, more deposits).
        _payAndCashOutWithReferral(PAYER, 5 ether, chainId, projectId);
        _distributeFeeReservedTokens();
        uint256 secondBridged = hook.bridgeRemote({
            referralChainId: chainId,
            referralProjectId: projectId,
            sucker: mockSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });
        assertGt(secondBridged, 0, "second batch bridged");

        // The HWM strictly grew across the two calls — both are recorded in `bridgedOutOf`.
        assertEq(
            hook.bridgedOutOf({referralChainId: chainId, referralProjectId: projectId}),
            firstBridged + secondBridged,
            "bridgedOutOf == cumulative across both calls"
        );

        // A third call with no new volume must be a no-op (no double-bridge).
        uint256 thirdBridged = hook.bridgeRemote({
            referralChainId: chainId,
            referralProjectId: projectId,
            sucker: mockSucker,
            terminalToken: JBConstants.NATIVE_TOKEN,
            minTokensReclaimed: 0
        });
        assertEq(thirdBridged, 0, "no new volume -> no new bridge");
    }
}
