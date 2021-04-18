pragma solidity ^0.5.16;

import "./CErc20Delegate.sol";

/**
 * @title Compound's CDai Contract
 * @notice CToken which wraps Multi-Collateral DAI
 * @author Compound
 */
contract COhmDelegate is CErc20Delegate {

    IOlympus olympus;

    /**
     * @notice Delegate interface to become the implementation
     * @param data The encoded arguments for becoming
     */
    function _becomeImplementation(bytes memory data) public {
        require(hasAdminRights(), "only the admin may initialize the implementation");

        (address olympus_) = abi.decode(data, (address));
        return _becomeImplementation(olympus_);
    }

    /**
     * @notice Explicit interface to become the implementation
     * @param olympusStaking_ OlympusStaking address
     */
    function _becomeImplementation(address _olympus) internal {

        olympus = IOlympus(_olympus);

        address ohm = olympus.ohm();
        require(ohm == underlying, "OHM must be the same as underlying");
        require(IERC20(ohm).approve(address(this), uint(-1)), "Error approving ERC-20");


        // Transfer all OHM in (doTransferIn does this regardless of amount)
        doTransferIn(address(this), 0);
    }

    /**
     * @notice Delegate interface to resign the implementation
     */
    function _resignImplementation() public {
        require(hasAdminRights(), "only the admin may abandon the implementation");

        uint bal = IERC20(olympus.sOHM()).balanceOf(address(this));
        require(olympus.unstakeOHM(bal), "Failed to unstake OHM");
    }

    /*** CToken Overrides ***/

    /**
      * @notice Accrues DSR then applies accrued interest to total borrows and reserves
      * @dev This calculates interest accrued from the last checkpointed block
      *      up to the current block and writes new checkpoint to storage.
      */
    function accrueInterest() public returns (uint) {

        uint earned = sub(IERC20(olympus.sOHM()).balanceOf(address(this)), deposits);


        // Accumulate CToken interest
        return super.accrueInterest();
    }

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying tokens owned by this contract
     */
    function getCashPrior() internal view returns (uint) {

        // sOHM and OHM are 1:1
        return IERC20(olympus.sOHM()).balanceOf(address(this));
    }

    /**
     * @notice Transfer the underlying to this contract and stake
     * @param from Address to transfer funds from
     * @param amount Amount of underlying to transfer
     * @return The actual amount that is transferred
     */
    function doTransferIn(address from, uint amount) internal returns (uint) {
        // Perform the ERC-20 transfer in
        require(IERC20(underlying).transferFrom(from, address(this), amount), "unexpected ERC-20 transfer in return");

        require(olympus.stakeOHM(amount), "Failed to stake OHM");

        return amount;
    }

    /**
     * @notice Transfer the underlying from this contract, after unstaking
     * @param to Address to transfer funds to
     * @param amount Amount of underlying to transfer
     */
    function doTransferOut(address payable to, uint amount) internal {

        require(olympus.unstakeOHM(amount), "Failed to unstake OHM");

        require(IERC20(underlying).transfer(to, amount), "unexpected ERC-20 transfer in return");


    }

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "add-overflow");
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) >= 0, "sub-overflow");
    }

}

interface IERC20{
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IOlympus {
    function ohm() external view returns (address);
    function sOHM() external view returns (address);
    function stakeOHM(uint) external returns (bool);
    function unstakeOHM(uint) external returns (bool);
}
