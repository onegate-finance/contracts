pragma solidity 0.5.16;

// Libraries
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";

contract InterestRateModel {
    using SafeMath for uint256;

    // Return the interest rate per second, using 1e18 as denom.
    function getInterestRate(uint256 debt, uint256 total) external pure returns (uint256) {
        uint utilization = total == 0 ? 0 : debt.mul(100e18).div(total);
        if (utilization < 50e18) {
            // less than 50% utilization - 10% APY
            return uint(10e16) / 365 days;
        } else if (utilization < 80e18) {
            // Between 50% and 80% - 10%-20% APY
            return (10e16 + utilization.sub(50e18).mul(10e16).div(30e18)) / 365 days;
        } else if (utilization < 90e18) {
            // Between 80% and 90% - 20%-30% APY
            return (20e16 + utilization.sub(80e18).mul(10e16).div(10e18)) / 365 days;
        } else if (utilization < 100e18) {
            // Between 90% and 100% - 30%-200% APY
            return (30e16 + utilization.sub(90e18).mul(170e16).div(10e18)) / 365 days;
        } else {
            // Not possible, but just in case - 200% APY
            return uint(200e16) / 365 days;
        }
    }
}
