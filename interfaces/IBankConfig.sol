pragma solidity 0.5.16;

interface IBankConfig {

    // Return the bps rate for reserve pool.
    function getReserveBps() external view returns (uint256);

    // Return the bps rate for liquidation.
    function getLiquidateBps() external view returns (uint256);

    // Return the interest rate per second.
    function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256);

}

