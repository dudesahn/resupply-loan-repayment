// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {console} from "forge-std/console.sol";
import {LoanAccounting} from "src/LoanAccounting.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "src/interfaces/IVault.sol";

contract OperationTest is Test {
    LoanAccounting public accounting;
    uint256 public loanPrincipal;
    IERC20 public CRVUSD;
    IVault public vaultToken;
    uint256 public MIN_FUZZ = 0;
    uint256 public MAX_FUZZ = 1e50;

    function setUp() public {
        loanPrincipal = 1_130_000e18;
        accounting = new LoanAccounting(loanPrincipal);
        CRVUSD = IERC20(accounting.CRVUSD());
        vaultToken = IVault(accounting.VAULT());
        CRVUSD.approve(address(accounting), type(uint256).max);
        deal(address(CRVUSD), address(this), 1_500_000e18);
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > MIN_FUZZ && _amount < MAX_FUZZ);

        // Earn Interest
        skip(10 days);

        // check that total owed is more than initial
        uint256 firstOwed = accounting.remainingLoan();
        assertGt(firstOwed, loanPrincipal, "!interest");

        skip(10 days);

        // check that total owed is still increasing
        uint256 secondOwed = accounting.remainingLoan();
        assertGt(secondOwed, firstOwed, "!interest");

        // check if we'll be repaying all of our loan or not
        bool shouldBeRepaid;
        if (_amount > accounting.remainingLoan()) {
            shouldBeRepaid = true;
        }

        uint256 treasuryBefore = vaultToken.balanceOf(
            accounting.YEARN_TREASURY()
        );

        // if dust repayment, should revert
        if (_amount <= accounting.MIN_REPAYMENT()) {
            vm.expectRevert("Payment too small");
        }

        // repay some amount
        accounting.repayBorrow(_amount);

        if (_amount > accounting.MIN_REPAYMENT()) {
            assertGt(
                vaultToken.balanceOf(accounting.YEARN_TREASURY()),
                treasuryBefore,
                "!treasury"
            );
        }

        if (shouldBeRepaid) {
            assertEq(accounting.remainingLoan(), 0, "!loan");
            assertGt(CRVUSD.balanceOf(address(this)), 0, "!balance");
        }
    }

    function test_PayAllAtOnce() public {
        accounting.repayBorrow(accounting.remainingLoan());
        assertEq(accounting.remainingLoan(), 0, "loan should be paid");
        skip(100 days);
        assertEq(accounting.remainingLoan(), 0, "loan should be paid");
        uint256 balanceBefore = CRVUSD.balanceOf(address(this));
        accounting.repayBorrow(1_000e18);
        assertEq(CRVUSD.balanceOf(address(this)), balanceBefore);
    }

    function test_AmountOwedInAYear() public {
        skip(365 days);
        uint256 amountOwed = accounting.remainingLoan();
        console.log("%18e", amountOwed, "Amount Owed in a year without repayment");
        assertGt(amountOwed, loanPrincipal, "interest accrued");
    }

    function test_AmountOwedInAYearWithDailyMinRepayment() public {
        uint256 dailyMinRepayment = accounting.MIN_REPAYMENT() + 1;
        uint256 daysToRepay = 365;
        for (uint256 i = 0; i < daysToRepay; i++) {
            accounting.repayBorrow(dailyMinRepayment);
            skip(1 days);
        }
        uint256 total = accounting.remainingLoan() + accounting.totalRepaid();
        console.log("%18e", total, "Amount Owed in a year with daily min repayment");
    }
}