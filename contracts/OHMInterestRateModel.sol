pragma solidity ^0.5.16;

import "./JumpRateModel.sol";
import "./SafeMath.sol";

/**
  * @title Compound's DAIInterestRateModel Contract (version 2)
  * @author Compound (modified by Dharma Labs)
  * @notice The parameterized model described in section 2.4 of the original Compound Protocol whitepaper.
  * Version 2 modifies the original interest rate model by increasing the "gap" or slope of the model prior
  * to the "kink" from 0.05% to 2% with the goal of "smoothing out" interest rate changes as the utilization
  * rate increases.
  */
contract OHMInterestRateModel is JumpRateModel {
    using SafeMath for uint;


    ICToken token;
    IStaking staking;

    /**
     * @notice Construct an interest rate model
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     * @param token_ The address of the CToken
     * @param staking_ The address of OlympusStaking
     */
    constructor(uint jumpMultiplierPerYear, uint kink_, address token_, address staking_) JumpRateModel(0, 0, jumpMultiplierPerYear, kink_) public {
        token = ICToken(token_);
        staking = IStaking(staking_);
        multiplierPerBlock = (2e16 / blocksPerYear).mul(1e18).div(kink);
        poke();
    }

    /**
     * @notice Calculates the current supply interest rate per block including the Ohm staking rate
     * @param cash The total amount of cash the market has
     * @param borrows The total amount of borrows the market has outstanding
     * @param reserves The total amnount of reserves the market has
     * @param reserveFactorMantissa The current reserve factor the market has
     * @return The supply rate per block (as a percentage, and scaled by 1e18)
     */
    function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa) public view returns (uint) {
        uint protocolRate = super.getSupplyRate(cash, borrows, reserves, reserveFactorMantissa);

        uint underlying = cash.add(borrows).sub(reserves);
        if (underlying == 0) {
            return protocolRate;
        } else {
            uint cashRate = cash.mul(stakingRatePerBlock()).div(underlying);
            return cashRate.add(protocolRate);
        }
    }

    /**
     * @notice Calculates the Ohm staking rate per block
     * @return The Ohm staking rate per block (as a percentage, and scaled by 1e18)
     */
    function stakingRatePerBlock() public view returns (uint) {

        // Rebase is current epoch staking rate
        uint stakingBalance = IERC20(token.underlying()).balanceOf(address(staking));
        require(stakingBalance != 0, "There is currently no staked token balance");
        uint rebase = staking.ohmToDistributeNextEpoch().div(stakingBalance);
        return rebase.div(staking.epochLengthInBlocks()).mul(1e18);
    }

    /**
     * @notice Resets the baseRate and multiplier per block based on the Ohm staking rate
     */
    function poke() public {

        // We ensure the minimum borrow rate >= stakingRate / (1 - reserve factor)
        baseRatePerBlock = stakingRatePerBlock().mul(1e18).div(1e18 - token.reserveFactorMantissa());


        emit NewInterestParams(baseRatePerBlock, multiplierPerBlock, jumpMultiplierPerBlock, kink);
    }
}


interface ICToken {
    function reserveFactorMantissa() external view returns (uint);
    function underlying() external view returns (address);
}

interface IERC20{
    function balanceOf(address account) external view returns (uint256);
}

interface IStaking {
    function epochLengthInBlocks() external view returns (uint);
    function ohmToDistributeNextEpoch() external view returns (uint);
}
