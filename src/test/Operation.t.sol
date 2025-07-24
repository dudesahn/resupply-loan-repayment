// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract OperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Earn Interest
        skip(10 days);

        // check that total owed is more than initial
        uint256 firstOwed = accounting.remainingLoan();
        assertGt(firstOwed, loanPrincipal, "!interest");

        skip(10 days);

        // check that total owed is still increasing
        uint256 secondOwed = accounting.remainingLoan();
        assertGt(secondOwed, firstOwed, "!interest");

        // deal crvUSD to our user
        airdrop(asset, user, _amount);
        vm.startPrank(user);
        asset.approve(address(accounting), type(uint256).max);

        // check if we'll be repaying all of our loan or not
        bool shouldBeRepaid;
        if (_amount > accounting.remainingLoan()) {
            shouldBeRepaid = true;
        }

        uint256 treasuryBefore = vaultToken.balanceOf(
            accounting.YEARN_TREASURY()
        );

        // if dust repayment, should revert
        if (_amount <= 1e9) {
            vm.expectRevert("!dust");
        }

        // repay some amount
        accounting.repayBorrow(_amount);

        if (_amount > 1e9) {
            assertGt(
                vaultToken.balanceOf(accounting.YEARN_TREASURY()),
                treasuryBefore,
                "!treasury"
            );
        }

        if (shouldBeRepaid) {
            assertEq(accounting.remainingLoan(), 0, "!loan");
            assertGt(asset.balanceOf(user), 0);
        }

        // end prank
        vm.stopPrank();
    }
}
