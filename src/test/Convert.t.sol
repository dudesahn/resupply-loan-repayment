// SPDX-License-Identifier: AGLP-3.0
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Converter} from "../Converter.sol";
import {LoanAccounting} from "../LoanAccounting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IStaking {
    function notifyRewardAmount(address token, uint256 amount) external;
    function setRewardRedirect(address target) external;
}

contract ConverterTest is Test {
    Converter public converter;
    LoanAccounting public loanAccounting;
    
    // Real mainnet addresses
    address public constant OWNER = 0xFE11a5009f2121622271e7dd0FD470264e076af6;
    IERC20 public constant CRVUSD = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    IERC4626 public constant SCRVUSD = IERC4626(0x0655977FEb2f289A4aB78af67BAB0d17aAb84367);
    IERC20 public constant REUSD = IERC20(0x57aB1E0003F623289CD798B1824Be09a793e4Bec);
    address public constant CURVE_POOL = 0xc522A6606BBA746d7960404F22a3DB936B6F4F50;
    address public constant REWARD_HANDLER = 0xdBF41092e1E310a2B48B0895095EfF6d341D8F00;
    IStaking public constant GOV_STAKER = IStaking(0x22222222E9fE38F6f1FC8C61b25228adB4D8B953);
    address public constant PERMA_STAKER_CONVEX = 0xCCCCCccc94bFeCDd365b4Ee6B86108fC91848901;
    address public constant PERMA_STAKER_YEARN = 0x12341234B35c8a48908c716266db79CAeA0100E8;
    
    address public user = address(0x123);
    address public approvedCaller = address(0x456);
    
    event CallerApproved(address indexed caller, bool approved);
    
    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("MAINNET_URL"));
        
        // Deploy LoanAccounting with a loan principal
        uint256 loanPrincipal = 1000e18; // 1000 crvUSD
        loanAccounting = new LoanAccounting(loanPrincipal);
        
        // Deploy converter with the loan accounting contract as repayer
        vm.prank(OWNER);
        converter = new Converter(address(loanAccounting));
        
        vm.prank(PERMA_STAKER_CONVEX);
        GOV_STAKER.setRewardRedirect(address(converter));
        vm.prank(PERMA_STAKER_YEARN);
        GOV_STAKER.setRewardRedirect(address(converter));
        
        // Set up approved caller
        vm.prank(OWNER);
        converter.setApprovedCaller(approvedCaller, true);

        queueStakingRewards();
    }
    
    function test_Constructor() public view {
        assertEq(address(converter.repayer()), address(loanAccounting));
        assertEq(converter.OWNER(), OWNER);
        assertEq(address(converter.CRVUSD()), address(CRVUSD));
        assertEq(address(converter.SCRVUSD()), address(SCRVUSD));
        assertEq(address(converter.REUSD()), address(REUSD));
        assertEq(address(converter.POOL()), CURVE_POOL);
    }
    
    function test_SetApprovedCaller() public {
        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit CallerApproved(user, true);
        converter.setApprovedCaller(user, true);
        
        assertTrue(converter.approvedCallers(user));
    }
    
    function test_SetApprovedCaller_RevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("!owner");
        converter.setApprovedCaller(user, true);
    }
    
    function test_ConvertAndRepay_WithoutClaims() public {
        uint256 initialReusdBalance = REUSD.balanceOf(address(converter));
        uint256 initialRepaidAmount = loanAccounting.totalRepaid();
        uint256 initialRemainingLoan = loanAccounting.remainingLoan();
        
        console2.log("Initial REUSD balance:", initialReusdBalance);
        console2.log("Initial total repaid:", initialRepaidAmount);
        console2.log("Initial remaining loan:", initialRemainingLoan);
        
        deal(address(REUSD), address(converter), 1000e18);
        
        // Get expected output from curve pool
        uint256 expectedOut = converter.getExpectedOut(false);
        uint256 minOut = (expectedOut * 90) / 100;
        console2.log("Expected output from curve:", expectedOut);

        vm.prank(approvedCaller);
        converter.convertAndRepay(false, minOut);
        
        // Check that REUSD was consumed
        uint256 finalReusdBalance = REUSD.balanceOf(address(converter));
        console2.log("Final REUSD balance:", finalReusdBalance);
        assertEq(finalReusdBalance, 0);
        
        // Check that loan was repaid
        uint256 finalRepaidAmount = loanAccounting.totalRepaid();
        console2.log("Final total repaid:", finalRepaidAmount);
        assertGt(finalRepaidAmount, initialRepaidAmount);
    }
    
    function test_ConvertAndRepay_WithClaims() public {
        uint256 initialReusdBalance = REUSD.balanceOf(address(converter));
        uint256 initialRepaidAmount = loanAccounting.totalRepaid();
        
        console2.log("Initial REUSD balance:", initialReusdBalance);
        console2.log("Initial total repaid:", initialRepaidAmount);
        
        // Get expected output from curve pool
        uint256 expectedOut = converter.getExpectedOut(true);
        console2.log("Expected output from curve:", expectedOut);
        
        // Use a reasonable minOut (90% of expected to account for slippage)
        uint256 minOut = (expectedOut * 90) / 100;
        
        vm.prank(approvedCaller);
        converter.convertAndRepay(true, minOut);
        
        // Check that REUSD was consumed
        uint256 finalReusdBalance = REUSD.balanceOf(address(converter));
        console2.log("Final REUSD balance:", finalReusdBalance);
        assertEq(finalReusdBalance, 0);
        
        // Check that loan was repaid
        uint256 finalRepaidAmount = loanAccounting.totalRepaid();
        console2.log("Final total repaid:", finalRepaidAmount);
        assertGt(finalRepaidAmount, initialRepaidAmount);
    }
    
    function test_ConvertAndRepay_RevertIfNotApproved() public {
        vm.prank(user);
        vm.expectRevert("!approved");
        converter.convertAndRepay(false, 0);
    }
    
    function test_ConvertAndRepay_RevertIfSlippageTooHigh() public {
        // Set a very high minOut that won't be met
        uint256 highMinOut = 10000e18;
        
        vm.prank(approvedCaller);
        vm.expectRevert();
        converter.convertAndRepay(false, highMinOut);
    }
    
    function test_GetExpectedOut() public view {
        uint256 expectedOut = converter.getExpectedOut(true);
        uint256 reusdBalance = REUSD.balanceOf(address(converter));
        
        console2.log("REUSD balance:", reusdBalance);
        console2.log("Expected output:", expectedOut);
        
        // Should return a reasonable amount (not necessarily 1:1 due to curve math)
        assertGt(expectedOut, 0);
    }
    
    function test_RecoverERC20() public {
        // Fund converter with some CRVUSD
        uint256 amount = 100e18;
        deal(address(CRVUSD), address(converter), amount);
        
        uint256 initialOwnerBalance = CRVUSD.balanceOf(OWNER);

        vm.expectRevert("!owner");
        converter.recoverERC20(address(CRVUSD));
        
        vm.prank(OWNER);
        converter.recoverERC20(address(CRVUSD));
        
        // Check that tokens were transferred to owner
        assertEq(CRVUSD.balanceOf(OWNER), initialOwnerBalance + amount);
        assertEq(CRVUSD.balanceOf(address(converter)), 0);
    }
    
    function test_ApprovedCallersPermissions() public {
        assertTrue(converter.approvedCallers(approvedCaller));
        assertFalse(converter.approvedCallers(user));
        
        // Remove approval
        vm.prank(OWNER);
        converter.setApprovedCaller(approvedCaller, false);
        assertFalse(converter.approvedCallers(approvedCaller));

        vm.expectRevert("!owner");
        converter.setApprovedCaller(approvedCaller, true);

        vm.expectRevert("!approved");
        converter.convertAndRepay(false, 0);
    }
    
    function test_LoanAccountingIntegration() public view {
        // Test that the loan accounting contract is properly set up
        assertEq(address(loanAccounting.CRVUSD()), address(CRVUSD));
        assertGt(loanAccounting.LOAN_PRINCIPAL(), 0);
        assertGt(loanAccounting.remainingLoan(), 0);
        
        console2.log("Loan principal:", loanAccounting.LOAN_PRINCIPAL());
        console2.log("Remaining loan:", loanAccounting.remainingLoan());
        console2.log("Interest rate:", loanAccounting.INTEREST_RATE());
    }
    
    function test_Constants() public view {
        assertEq(converter.OWNER(), OWNER);
        assertEq(address(converter.CRVUSD()), address(CRVUSD));
        assertEq(address(converter.SCRVUSD()), address(SCRVUSD));
        assertEq(address(converter.REUSD()), address(REUSD));
        assertEq(address(converter.POOL()), CURVE_POOL);
    }
    
    function test_ClaimsFunctionality() public {
        // Test that the claims functionality can be called
        // This will test the permastaker claims when doClaims is true
        uint256 initialReusdBalance = REUSD.balanceOf(address(converter));
        
        uint256 expectedOut = converter.getExpectedOut(true);
        uint256 minOut = (expectedOut * 90) / 100;
        
        vm.prank(approvedCaller);
        converter.convertAndRepay(true, minOut);
        
        // Verify the conversion still works with claims enabled
        uint256 finalReusdBalance = REUSD.balanceOf(address(converter));
        assertLt(finalReusdBalance, initialReusdBalance + 200e18);
    }

    function queueStakingRewards() public {
        // queue staking rewards
        uint256 amount = 50_000e18;
        deal(address(REUSD), address(REWARD_HANDLER), amount);
        vm.prank(REWARD_HANDLER);
        GOV_STAKER.notifyRewardAmount(address(REUSD), amount);
        skip(7 days);
    }
}