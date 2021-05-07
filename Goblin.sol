pragma solidity 0.5.16;


interface Goblin {

    // open position or close position.
    function work(
        uint256 id,
        address user,
        address borrowToken,
        uint256 borrow,
        uint256 debt,
        bytes calldata data
    ) external payable;

    // Re-invest whatever the goblin is working on.
    function reinvest() external;

    // Return the amount of borrowToken wei to get back if we are to liquidate the position.
    function health(uint256 id, address borrowToken) external view returns (uint256);

    // Liquidate the given position to borrowToken. Send all borrowToken back to Bank.
    function liquidate(uint256 id, address borrowToken, address user) external;

    // get LP Token Total supply
    function lpTotalSupply() external view returns (uint256);
}
