pragma solidity ^0.5.16;

// Inheritance
interface ILpStakingRewards {


    // Views
    function totalShare() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerShare() external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function claim() external;

    function reinvest(uint256 amount) external;

    function lpTotalSupply() external view returns (uint256);


    // Mutative

    function stake(uint256 amount, address user) external returns (uint256);

    function withdraw(uint256 amount, address user) external;

    function getReward() external;
}
