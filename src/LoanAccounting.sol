// SPDX-License-Identifier: AGLP-3.0
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "src/interfaces/IVault.sol";

contract LoanAccounting {
    /// @notice Time of last adjustment of principal owed.
    uint256 lastRepaymentTime;

    /// @notice Total amount of crvUSD owed at the previous lastRepaymentTime
    uint256 lastRepaymentTotalOwed;

    /// @notice Amount of crvUSD that has been repaid via this contract.
    uint256 totalRepaid;

    /// @notice Starting principal borrowed from Yearn
    uint256 public immutable LOAN_PRINCIPAL;

    /// @notice crvUSD, repayment token
    IERC20 public immutable CRVUSD;

    /// @notice crvUSD-2 yearn vault
    IVault public constant VAULT =
        IVault(0xBF319dDC2Edc1Eb6FDf9910E39b37Be221C8805F);

    /// @notice Yearn's treasury
    address public constant YEARN_TREASURY =
        0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde;

    uint256 internal constant SECONDS_PER_YEAR = 31536000;
    uint256 internal constant DUST = 1e9;

    event Repayment(uint256 indexed amount);

    constructor(uint256 _loanPrincipal) {
        require(_loanPrincipal != 0, "!principal");
        CRVUSD = IERC20(VAULT.asset());
        CRVUSD.approve(address(VAULT), type(uint256).max);
        lastRepaymentTime = block.timestamp;
        LOAN_PRINCIPAL = _loanPrincipal;
        lastRepaymentTotalOwed = _loanPrincipal;
    }

    function repayBorrow(uint256 _amount) external {
        require(_amount > DUST, "!dust");
        // repay a set amount, add accrued interest to principal, update timestamp
        uint256 remainingToPay = remainingLoan();
        if (remainingToPay == 0) {
            return;
        } else if (_amount > remainingToPay) {
            _amount = remainingToPay;
        }
        if (_amount > DUST) {
            // transfer in repayment and deposit to treasury
            CRVUSD.transferFrom(msg.sender, address(this), _amount);
            VAULT.deposit(_amount, YEARN_TREASURY);

            // handle accounting and update repayment timestamp
            totalRepaid += _amount;
            lastRepaymentTotalOwed = remainingToPay - _amount;
            lastRepaymentTime = block.timestamp;
            emit Repayment(_amount);
        }
    }

    function remainingLoan() public view returns (uint256 remaining) {
        remaining = lastRepaymentTotalOwed + interestAccrued();
    }

    function interestAccrued() public view returns (uint256 interestOwed) {
        interestOwed =
            (lastRepaymentTotalOwed *
                (block.timestamp - lastRepaymentTime) *
                6) /
            (SECONDS_PER_YEAR * 100);
    }

    function recoverERC20(address _token) external {
        IERC20(_token).transfer(
            YEARN_TREASURY,
            IERC20(_token).balanceOf(address(this))
        );
    }
}
