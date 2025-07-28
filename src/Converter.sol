// SPDX-License-Identifier: AGLP-3.0
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract Converter {
    address public constant OWNER = 0xFE11a5009f2121622271e7dd0FD470264e076af6;
    IERC20 public constant CRVUSD = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    IERC4626 public constant SCRVUSD = IERC4626(0x0655977FEb2f289A4aB78af67BAB0d17aAb84367);
    IERC20 public constant REUSD = IERC20(0x57aB1E0003F623289CD798B1824Be09a793e4Bec);
    ICurvePool public constant POOL = ICurvePool(0xc522A6606BBA746d7960404F22a3DB936B6F4F50);
    IStaking public constant GOV_STAKER = IStaking(0x22222222E9fE38F6f1FC8C61b25228adB4D8B953);
    address public constant PERMA_STAKER_CONVEX = 0xCCCCCccc94bFeCDd365b4Ee6B86108fC91848901;
    address public constant PERMA_STAKER_YEARN = 0x12341234B35c8a48908c716266db79CAeA0100E8;
    ILoanAccounting public immutable repayer;
    mapping(address => bool) public approvedCallers;

    event CallerApproved(address indexed caller, bool approved);

    modifier onlyOwner() {
        require(msg.sender == OWNER, "!owner");
        _;
    }

    modifier onlyApproved() {
        require(approvedCallers[msg.sender], "!approved");
        _;
    }

    constructor(address _repayer) {
        repayer = ILoanAccounting(_repayer);
        CRVUSD.approve(address(_repayer), type(uint256).max);
        REUSD.approve(address(POOL), type(uint256).max);
        approvedCallers[OWNER] = true;
        emit CallerApproved(OWNER, true);
    }

    function convertAndRepay(bool doClaims, uint256 minOut) onlyApproved external {
        if (doClaims) _claimFromPermastakers();
        // 1. trade reusd for scrvusd
        POOL.exchange(0, 1, _reusdBalance(), minOut);
        // 2. unwarp to crvusd
        uint256 crvusdAmount = SCRVUSD.redeem(SCRVUSD.balanceOf(address(this)), address(this), address(this));
        // 3. call repay on repayer
        repayer.repayBorrow(crvusdAmount);
    }

    function _claimFromPermastakers() internal {
        GOV_STAKER.getReward(PERMA_STAKER_CONVEX);
        GOV_STAKER.getReward(PERMA_STAKER_YEARN);
    }

    function _reusdBalance() internal view returns (uint256) {
        return REUSD.balanceOf(address(this));
    }

    /**
     * @notice Allow owner to whitelist accounts to call `convertAndRepay`
     */
    function setApprovedCaller(address _caller, bool _approved) external onlyOwner {
        approvedCallers[_caller] = _approved;
        emit CallerApproved(_caller, _approved);
    }

    function recoverERC20(address token) external onlyOwner {
        IERC20(token).transfer(OWNER, IERC20(token).balanceOf(address(this)));
    }

    /**
     * @notice Get the expected SCRVUSD output from the curve pool given the REUSD balance + optional claims.
     */
    function getExpectedOut(bool _includeClaims) public view returns (uint256) {
        uint256 earned;
        if (_includeClaims) earned = claimableRewards();
        return _getExpectedOut(_reusdBalance() + earned);
    }

    /**
     * @notice Get the combined claimable REUSD from the permastakers.
     */
    function claimableRewards() public view returns (uint256) {
        return GOV_STAKER.earned(PERMA_STAKER_CONVEX, address(REUSD)) + GOV_STAKER.earned(PERMA_STAKER_YEARN, address(REUSD));
    }

    function _getExpectedOut(uint256 amount) internal view returns (uint256) {
        return POOL.get_dy(0, 1, amount);
    }

    /**
     * @notice Helper to check if the expected output is greater than the minimum repayment 
     * required by the loan accounting contract.
     */
    function canCall(bool _includeClaims) public view returns (bool) {
        uint256 earned;
        if (_includeClaims) earned = claimableRewards();
        uint256 expectedOut = _getExpectedOut(_reusdBalance() + earned);
        expectedOut = SCRVUSD.previewRedeem(expectedOut);
        return expectedOut > repayer.MIN_REPAYMENT();
    }
}

interface ICurvePool {
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);
}

interface ILoanAccounting {
    function repayBorrow(uint256 amount) external;
    function MIN_REPAYMENT() external view returns (uint256);
}

interface IStaking {
    function getReward(address user) external;
    function earned(address user, address token) external view returns (uint256);
}