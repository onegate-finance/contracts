pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "./LpStakingRewards.sol";


contract LpStakingRewardsFactory is Ownable {
    // immutables
    address public rewardsToken;

    // the staking tokens for which the rewards contract has been deployed
    address[] public stakingTokens;

    // info about rewards for a particular staking token
    struct LpStakingRewardsInfo {
        address lpStakingRewards;
        uint rewardAmount;
    }

    // rewards info by staking token
    mapping(address => LpStakingRewardsInfo) public lpStakingRewardsInfoByStakingToken;

    constructor(
        address _rewardsToken
    ) Ownable() public {
        rewardsToken = _rewardsToken;
    }

    // deploy a staking reward contract for the staking token, and store the total reward amount
    // hecoPoolId: set -1 if not stake lpToken to Heco
    function deploy(
        address stakingToken,
        address hecoPool,
        uint256 poolID,
        uint period
    ) public onlyOwner {
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards == address(0), 'LpStakingRewardsFactory::deploy: already deployed');
        info.lpStakingRewards = address(new LpStakingRewards(
                address(this),
                rewardsToken,
                stakingToken,
                hecoPool,
                poolID,
                period
            ));
        stakingTokens.push(stakingToken);
    }

    // notify initial reward amount for an individual staking token.
    function notifyRewardAmount(address stakingToken, uint256 rewardAmount) public onlyOwner {
        require(rewardAmount > 0, 'amount should > 0');
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards != address(0), 'LpStakingRewardsFactory::notifyRewardAmount: not deployed');
        info.rewardAmount = rewardAmount;
        LpStakingRewards(info.lpStakingRewards).notifyRewardAmount(rewardAmount);

    }

    function setOperator(address stakingToken, address operator) public onlyOwner {
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards != address(0), 'LpStakingRewardsFactory::setOperator: not deployed');
        LpStakingRewards(info.lpStakingRewards).setOperator(operator);
    }

    function burn(address stakingToken, uint256 amount) public onlyOwner {
        LpStakingRewardsInfo storage info = lpStakingRewardsInfoByStakingToken[stakingToken];
        require(info.lpStakingRewards != address(0), 'LpStakingRewardsFactory::burn: not deployed');
        LpStakingRewards(info.lpStakingRewards).burn(amount);
    }

}
