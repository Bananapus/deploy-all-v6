// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Sphinx} from "@sphinx-labs/contracts/contracts/foundry/SphinxPlugin.sol";
import {Script, console} from "forge-std/Script.sol";

import {JBPermissions} from "@bananapus/core-v6/src/JBPermissions.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import {JBMultiTerminal} from "@bananapus/core-v6/src/JBMultiTerminal.sol";
import {JBTokens} from "@bananapus/core-v6/src/JBTokens.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBCashOutHookSpecification} from "@bananapus/core-v6/src/structs/JBCashOutHookSpecification.sol";
import {JBPayHookSpecification} from "@bananapus/core-v6/src/structs/JBPayHookSpecification.sol";
import {JBPermissionsData} from "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";
import {JBSingleAllowance} from "@bananapus/core-v6/src/structs/JBSingleAllowance.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";

import {JBBuybackHookRegistry} from "@bananapus/buyback-hook-v6/src/JBBuybackHookRegistry.sol";

import {REVLoan} from "@rev-net/core-v6/src/structs/REVLoan.sol";
import {REVLoans} from "@rev-net/core-v6/src/REVLoans.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title LivePostDeploySmoke
/// @notice Sphinx proposal for post-deploy smoke checks that exercise production payment, buyback, and loan paths.
/// @dev This script makes small live transactions from the V6 deployment Safe. It is intentionally separate from
/// read-only `Verify.s.sol`.
contract LivePostDeploySmoke is Script, Sphinx {
    error LivePostDeploySmoke_InvalidBudget(string budgetName, uint256 amount, uint256 budget);
    error LivePostDeploySmoke_MissingAddress(string envVar);
    error LivePostDeploySmoke_NoNativeTerminal(uint256 projectId);
    error LivePostDeploySmoke_NoSmokeProjects();
    error LivePostDeploySmoke_NoTokensMinted(uint256 projectId);
    error LivePostDeploySmoke_PermissionMutationDisabled(uint256 projectId);
    error LivePostDeploySmoke_UnexpectedAddress(string label, address expected, address actual);
    error LivePostDeploySmoke_UnexpectedHook(uint256 projectId, address expectedHook, address actualHook);
    error LivePostDeploySmoke_UnexpectedSafe(address expected, address actual);
    error LivePostDeploySmoke_UnexpectedValue(string label, uint256 expected, uint256 actual);

    /// @dev Sphinx Safe used to execute the deployment and live smoke proposals.
    address private constant _EXPECTED_SAFE = 0x4dc161eF837fF1C4485b08DDFcDB182F2157bE18;

    uint256 private constant _NANA_PROJECT_ID = 1;
    uint256 private constant _CPN_PROJECT_ID = 2;
    uint256 private constant _REV_PROJECT_ID = 3;
    uint256 private constant _BAN_PROJECT_ID = 4;
    uint256 private constant _DEFIFA_PROJECT_ID = 5;
    uint256 private constant _ART_PROJECT_ID = 6;
    uint256 private constant _MARKEE_PROJECT_ID = 7;

    uint256 private constant _DEFAULT_BUYBACK_BUDGET = 0.05 ether;
    uint256 private constant _DEFAULT_BUYBACK_PAYMENT = 0.005 ether;
    uint256 private constant _DEFAULT_LOAN_BUDGET = 0;
    uint256 private constant _DEFAULT_LOAN_PAYMENT = 0;
    uint256 private constant _DEFAULT_CASH_OUT_DIVISOR = 4;

    JBProjects private _projects;
    JBMultiTerminal private _terminal;
    JBTokens private _tokens;
    JBPermissions private _permissions;
    JBBuybackHookRegistry private _buybackRegistry;
    REVLoans private _revLoans;

    address private _account;
    address private _expectedBuybackHook;
    uint256 private _buybackBudget;
    uint256 private _buybackPayment;
    uint256 private _loanBudget;
    uint256 private _loanPayment;
    uint256 private _loanProjectId;
    uint256 private _cashOutDivisor;
    bool private _allowPermissionMutation;

    function configureSphinx() public override {
        sphinxConfig.projectName = "V6";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        _requireExpectedSafe();
        _load();

        console.log("========================================");
        console.log("  Juicebox V6 Live Post-Deploy Smoke");
        console.log("========================================");
        console.log("Chain ID", block.chainid);
        console.log("Smoke account", _account);
        console.log("Buyback budget", _buybackBudget);
        console.log("Loan budget", _loanBudget);

        execute();
    }

    function execute() public sphinx {
        if (_buybackBudget != 0) _exerciseBuybackProjects();
        if (_loanBudget != 0) _exerciseLoanRoundTrip();
    }

    function _load() internal {
        _account = safeAddress();

        _projects = JBProjects(_requiredAddress("VERIFY_PROJECTS"));
        _terminal = JBMultiTerminal(payable(_requiredAddress("VERIFY_TERMINAL")));
        _tokens = JBTokens(_requiredAddress("VERIFY_TOKENS"));
        _permissions = JBPermissions(_requiredAddress("VERIFY_PERMISSIONS"));
        _buybackRegistry = JBBuybackHookRegistry(vm.envOr({name: "VERIFY_BUYBACK_REGISTRY", defaultValue: address(0)}));
        _revLoans = REVLoans(payable(vm.envOr({name: "VERIFY_REV_LOANS", defaultValue: address(0)})));

        _expectedBuybackHook = vm.envOr({name: "VERIFY_BUYBACK_HOOK", defaultValue: address(0)});
        _buybackBudget = vm.envOr({name: "SMOKE_BUYBACK_BUDGET", defaultValue: _DEFAULT_BUYBACK_BUDGET});
        _buybackPayment = vm.envOr({name: "SMOKE_BUYBACK_PAYMENT_AMOUNT", defaultValue: _DEFAULT_BUYBACK_PAYMENT});
        _loanBudget = vm.envOr({name: "SMOKE_LOAN_BUDGET", defaultValue: _DEFAULT_LOAN_BUDGET});
        _loanPayment = vm.envOr({name: "SMOKE_LOAN_PAYMENT_AMOUNT", defaultValue: _DEFAULT_LOAN_PAYMENT});
        _loanProjectId = vm.envOr({name: "SMOKE_LOAN_PROJECT_ID", defaultValue: _REV_PROJECT_ID});
        _cashOutDivisor = vm.envOr({name: "SMOKE_BUYBACK_CASH_OUT_DIVISOR", defaultValue: _DEFAULT_CASH_OUT_DIVISOR});
        _allowPermissionMutation = vm.envOr({name: "SMOKE_ALLOW_PERMISSION_MUTATION", defaultValue: false});

        if (_buybackBudget != 0 && _buybackPayment == 0) {
            revert LivePostDeploySmoke_InvalidBudget("SMOKE_BUYBACK_PAYMENT_AMOUNT", _buybackPayment, _buybackBudget);
        }
        if (_buybackPayment > _buybackBudget) {
            revert LivePostDeploySmoke_InvalidBudget("SMOKE_BUYBACK_PAYMENT_AMOUNT", _buybackPayment, _buybackBudget);
        }
        if (_loanBudget != 0 && _loanPayment == 0) {
            revert LivePostDeploySmoke_InvalidBudget("SMOKE_LOAN_PAYMENT_AMOUNT", _loanPayment, _loanBudget);
        }
        if (_loanPayment > _loanBudget) {
            revert LivePostDeploySmoke_InvalidBudget("SMOKE_LOAN_PAYMENT_AMOUNT", _loanPayment, _loanBudget);
        }
    }

    function _exerciseBuybackProjects() internal {
        if (address(_buybackRegistry) == address(0)) {
            if (!_chainSupportsUniswapDependentStack()) {
                console.log("");
                console.log("--- Buyback/pay/cash-out smoke skipped: unsupported chain ---");
                return;
            }
            revert LivePostDeploySmoke_MissingAddress("VERIFY_BUYBACK_REGISTRY");
        }

        console.log("");
        console.log("--- Buyback/pay/cash-out smoke ---");

        uint256[] memory projectIds = _defaultBuybackProjectIds();
        uint256 remainingBudget = _buybackBudget;
        uint256 exercised;

        for (uint256 i; i < projectIds.length; ++i) {
            uint256 projectId = projectIds[i];
            if (remainingBudget < _buybackPayment) break;
            if (!_projectExists(projectId)) continue;
            if (!_hasNativeAccountingContext(projectId)) {
                console.log("  [SKIP] project has no native terminal context", projectId);
                continue;
            }

            _requireBuybackHook(projectId);
            _payProjectAndMaybeCashOut({projectId: projectId, amount: _buybackPayment});
            remainingBudget -= _buybackPayment;
            ++exercised;
        }

        if (exercised == 0) {
            if (!_chainSupportsUniswapDependentStack()) {
                console.log("  [SKIP] no buyback projects on unsupported chain");
                return;
            }
            revert LivePostDeploySmoke_NoSmokeProjects();
        }
        console.log("  [PASS] buyback project payments exercised", exercised);
    }

    function _payProjectAndMaybeCashOut(uint256 projectId, uint256 amount) internal {
        uint256 balanceBefore = _tokens.totalBalanceOf({holder: _account, projectId: projectId});

        (, uint256 previewTokens,, JBPayHookSpecification[] memory paySpecs) = _terminal.previewPayFor({
            projectId: projectId, token: JBConstants.NATIVE_TOKEN, amount: amount, beneficiary: _account, metadata: ""
        });
        console.log("  preview project", projectId);
        console.log("    pay amount", amount);
        console.log("    preview tokens", previewTokens);
        console.log("    pay hook specs", paySpecs.length);

        uint256 returnedTokens = _terminal.pay{value: amount}({
            projectId: projectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: amount,
            beneficiary: _account,
            minReturnedTokens: 0,
            memo: "deploy-all-v6 live smoke: pay",
            metadata: ""
        });

        uint256 balanceAfter = _tokens.totalBalanceOf({holder: _account, projectId: projectId});
        if (balanceAfter <= balanceBefore) revert LivePostDeploySmoke_NoTokensMinted(projectId);

        uint256 minted = balanceAfter - balanceBefore;
        console.log("    returned tokens", returnedTokens);
        console.log("    observed balance delta", minted);

        _maybeCashOutProject({projectId: projectId, tokenCount: minted});
    }

    function _maybeCashOutProject(uint256 projectId, uint256 tokenCount) internal {
        if (_cashOutDivisor == 0 || tokenCount < _cashOutDivisor) {
            console.log("    cash-out skipped");
            return;
        }

        uint256 cashOutCount = tokenCount / _cashOutDivisor;
        try _terminal.previewCashOutFrom({
            holder: _account,
            projectId: projectId,
            cashOutCount: cashOutCount,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            beneficiary: payable(_account),
            metadata: ""
        }) returns (
            JBRuleset memory, uint256 reclaimAmount, uint256, JBCashOutHookSpecification[] memory cashOutSpecs
        ) {
            console.log("    preview cash-out count", cashOutCount);
            console.log("    preview reclaim", reclaimAmount);
            console.log("    cash-out hook specs", cashOutSpecs.length);
            if (reclaimAmount == 0 && cashOutSpecs.length == 0) return;

            uint256 reclaimed = _terminal.cashOutTokensOf({
                holder: _account,
                projectId: projectId,
                cashOutCount: cashOutCount,
                tokenToReclaim: JBConstants.NATIVE_TOKEN,
                minTokensReclaimed: 0,
                beneficiary: payable(_account),
                metadata: ""
            });
            console.log("    reclaimed", reclaimed);
        } catch {
            console.log("    cash-out skipped: preview reverted");
        }
    }

    function _exerciseLoanRoundTrip() internal {
        if (address(_revLoans) == address(0)) {
            if (!_chainSupportsUniswapDependentStack()) {
                console.log("");
                console.log("--- Loan smoke skipped: unsupported chain ---");
                return;
            }
            revert LivePostDeploySmoke_MissingAddress("VERIFY_REV_LOANS");
        }
        if (!_hasNativeAccountingContext(_loanProjectId)) {
            if (!_chainSupportsUniswapDependentStack()) {
                console.log("");
                console.log("--- Loan smoke skipped: no native terminal context ---");
                return;
            }
            revert LivePostDeploySmoke_NoNativeTerminal(_loanProjectId);
        }

        console.log("");
        console.log("--- Loan smoke ---");
        console.log("  project", _loanProjectId);
        console.log("  seed payment", _loanPayment);

        _requireBuybackHook(_loanProjectId);

        uint256 balanceBefore = _tokens.totalBalanceOf({holder: _account, projectId: _loanProjectId});
        _terminal.pay{value: _loanPayment}({
            projectId: _loanProjectId,
            token: JBConstants.NATIVE_TOKEN,
            amount: _loanPayment,
            beneficiary: _account,
            minReturnedTokens: 0,
            memo: "deploy-all-v6 live smoke: loan collateral seed",
            metadata: ""
        });
        uint256 minted = _tokens.totalBalanceOf({holder: _account, projectId: _loanProjectId}) - balanceBefore;
        if (minted == 0) revert LivePostDeploySmoke_NoTokensMinted(_loanProjectId);

        uint256 collateral = minted / 2;
        if (collateral == 0) collateral = minted;

        (uint256 borrowable,) = _revLoans.borrowableAmountFrom({
            revnetId: _loanProjectId,
            collateralCount: collateral,
            decimals: 18,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
        if (borrowable == 0) revert LivePostDeploySmoke_UnexpectedValue("borrowable", 1, 0);
        if (borrowable > _loanBudget) {
            revert LivePostDeploySmoke_InvalidBudget("borrowable", borrowable, _loanBudget);
        }

        (uint256 priorPermissions, bool restorePermissions) = _grantBurnPermission();

        uint256 totalCollateralBefore = _revLoans.totalCollateralOf(_loanProjectId);
        (uint256 loanId, REVLoan memory loan) = _revLoans.borrowFrom({
            revnetId: _loanProjectId,
            token: JBConstants.NATIVE_TOKEN,
            minBorrowAmount: 0,
            collateralCount: collateral,
            beneficiary: payable(_account),
            prepaidFeePercent: _revLoans.MIN_PREPAID_FEE_PERCENT(),
            holder: _account
        });

        if (loan.amount == 0) revert LivePostDeploySmoke_UnexpectedValue("loan.amount", 1, 0);
        if (loan.collateral != collateral) {
            revert LivePostDeploySmoke_UnexpectedValue("loan.collateral", collateral, loan.collateral);
        }
        address loanOwner = IERC721(address(_revLoans)).ownerOf(loanId);
        if (loanOwner != _account) {
            revert LivePostDeploySmoke_UnexpectedAddress("loan owner", _account, loanOwner);
        }

        console.log("  borrowed loan id", loanId);
        console.log("  borrowed amount", uint256(loan.amount));
        console.log("  collateral", uint256(loan.collateral));

        JBSingleAllowance memory emptyAllowance;
        _revLoans.repayLoan{value: loan.amount}({
            loanId: loanId,
            maxRepayBorrowAmount: loan.amount,
            collateralCountToReturn: collateral,
            beneficiary: payable(_account),
            allowance: emptyAllowance
        });

        uint256 totalCollateralAfter = _revLoans.totalCollateralOf(_loanProjectId);
        if (totalCollateralAfter != totalCollateralBefore) {
            revert LivePostDeploySmoke_UnexpectedValue(
                "total collateral restored", totalCollateralBefore, totalCollateralAfter
            );
        }
        if (restorePermissions) _restoreBurnPermission(priorPermissions);

        console.log("  [PASS] loan opened and repaid");
    }

    function _grantBurnPermission() internal returns (uint256 packed, bool shouldRestore) {
        packed =
            _permissions.permissionsOf({operator: address(_revLoans), account: _account, projectId: _loanProjectId});
        if (_hasPackedPermission({packed: packed, permissionId: JBPermissionIds.BURN_TOKENS})) return (packed, false);
        if (!_allowPermissionMutation) revert LivePostDeploySmoke_PermissionMutationDisabled(_loanProjectId);

        uint8[] memory permissionIds = _permissionIdsFromPacked({packed: packed, extraCount: 1});
        uint256 index = permissionIds.length - 1;
        permissionIds[index] = JBPermissionIds.BURN_TOKENS;

        _setRevLoansPermissions(permissionIds);
        console.log("  burn permission granted to REVLoans");
        return (packed, true);
    }

    function _restoreBurnPermission(uint256 packed) internal {
        _setRevLoansPermissions(_permissionIdsFromPacked({packed: packed, extraCount: 0}));
        console.log("  burn permission restored");
    }

    function _setRevLoansPermissions(uint8[] memory permissionIds) internal {
        _permissions.setPermissionsFor({
            account: _account,
            permissionsData: JBPermissionsData({
                operator: address(_revLoans), projectId: uint64(_loanProjectId), permissionIds: permissionIds
            })
        });
    }

    function _requireBuybackHook(uint256 projectId) internal view {
        if (address(_buybackRegistry) == address(0)) {
            revert LivePostDeploySmoke_MissingAddress("VERIFY_BUYBACK_REGISTRY");
        }

        address actualHook = address(_buybackRegistry.hookOf(projectId));
        if (actualHook == address(0)) {
            revert LivePostDeploySmoke_UnexpectedHook({
                projectId: projectId, expectedHook: address(1), actualHook: actualHook
            });
        }
        if (_expectedBuybackHook != address(0) && actualHook != _expectedBuybackHook) {
            revert LivePostDeploySmoke_UnexpectedHook({
                projectId: projectId, expectedHook: _expectedBuybackHook, actualHook: actualHook
            });
        }
    }

    function _hasNativeAccountingContext(uint256 projectId) internal view returns (bool) {
        try _terminal.accountingContextForTokenOf({projectId: projectId, token: JBConstants.NATIVE_TOKEN}) returns (
            JBAccountingContext memory context
        ) {
            return context.token == JBConstants.NATIVE_TOKEN;
        } catch {
            return false;
        }
    }

    function _projectExists(uint256 projectId) internal view returns (bool) {
        return _projects.count() >= projectId;
    }

    function _defaultBuybackProjectIds() internal view returns (uint256[] memory projectIds) {
        if (block.chainid == 8453 || block.chainid == 84_532) {
            projectIds = new uint256[](7);
            projectIds[0] = _NANA_PROJECT_ID;
            projectIds[1] = _CPN_PROJECT_ID;
            projectIds[2] = _REV_PROJECT_ID;
            projectIds[3] = _BAN_PROJECT_ID;
            projectIds[4] = _DEFIFA_PROJECT_ID;
            projectIds[5] = _ART_PROJECT_ID;
            projectIds[6] = _MARKEE_PROJECT_ID;
        } else {
            projectIds = new uint256[](6);
            projectIds[0] = _NANA_PROJECT_ID;
            projectIds[1] = _CPN_PROJECT_ID;
            projectIds[2] = _REV_PROJECT_ID;
            projectIds[3] = _BAN_PROJECT_ID;
            projectIds[4] = _DEFIFA_PROJECT_ID;
            projectIds[5] = _MARKEE_PROJECT_ID;
        }
    }

    function _chainSupportsUniswapDependentStack() internal view returns (bool) {
        return block.chainid != 11_155_420;
    }

    function _requiredAddress(string memory envVar) internal view returns (address addr) {
        addr = vm.envAddress(envVar);
        if (addr == address(0) || addr.code.length == 0) revert LivePostDeploySmoke_MissingAddress(envVar);
    }

    function _requireExpectedSafe() internal {
        address actualSafe = safeAddress();
        if (actualSafe != _EXPECTED_SAFE) revert LivePostDeploySmoke_UnexpectedSafe(_EXPECTED_SAFE, actualSafe);
    }

    function _permissionIdsFromPacked(uint256 packed, uint256 extraCount) internal pure returns (uint8[] memory ids) {
        uint256 count = extraCount;
        for (uint256 permissionId = 1; permissionId < 255; ++permissionId) {
            if (_hasPackedPermission({packed: packed, permissionId: permissionId})) ++count;
        }

        ids = new uint8[](count);
        uint256 index;
        for (uint256 permissionId = 1; permissionId < 255; ++permissionId) {
            if (_hasPackedPermission({packed: packed, permissionId: permissionId})) {
                ids[index++] = uint8(permissionId);
            }
        }
    }

    function _hasPackedPermission(uint256 packed, uint256 permissionId) internal pure returns (bool) {
        return ((packed >> permissionId) & 1) == 1;
    }
}
