pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";
import "@uniswap/v2-core/contracts/libraries/Math.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/ILpStakingRewards.sol";
import './interfaces/IHecoPool.sol';


/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see `ERC20Detailed`.
 */
interface IERC20MintBurn {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a `Transfer` event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through `transferFrom`. This is
     * zero by default.
     *
     * This value changes when `approve` or `transferFrom` are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    function mint(address account, uint amount) external;

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * > Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an `Approval` event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a `Transfer` event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    function burn(address account, uint256 amount) external;

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to `approve`. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}



/**
 * @dev Optional functions from the ERC20 standard.
 */
contract ERC20Detailed is IERC20MintBurn {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @dev Sets the values for `name`, `symbol`, and `decimals`. All three of
     * these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name, string memory symbol, uint8 decimals) public {
        _name = name;
        _symbol = symbol;
        _decimals = decimals;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei.
     *
     * > Note that this information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * `IERC20.balanceOf` and `IERC20.transfer`.
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

}

/**
 * @dev Collection of functions related to the address type,
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * This test is non-exhaustive, and there may be false-negatives: during the
     * execution of a contract's constructor, its address will be reported as
     * not containing a contract.
     *
     * > It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }
}

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for ERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20MintBurn token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20MintBurn token, address from, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20MintBurn token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20MintBurn token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20MintBurn token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function callOptionalReturn(IERC20MintBurn token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves.

        // A Solidity high level call has three parts:
        //  1. The target address is checked to verify it contains contract code
        //  2. The call itself is made, and success asserted
        //  3. The return value is decoded, which in turn checks the size of the returned data.
        // solhint-disable-next-line max-line-length
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}




contract RewardsDistributionRecipient {
    address public rewardsDistribution;

    function notifyRewardAmount(uint256 reward) external;

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
        _;
    }
}


contract LpStakingRewards is ILpStakingRewards, RewardsDistributionRecipient, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20MintBurn;

    address public mdxAddress = 0x25D2e80cB6B86881Fd7e07dd263Fb79f4AbE033c; // dmx token address
    IERC20MintBurn public mdx = IERC20MintBurn(mdxAddress); // mdx

    /* ========== STATE VARIABLES ========== */

    address public operator;
    IERC20MintBurn public rewardsToken;
    IERC20MintBurn public lpToken;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public rewardsPaid = 0;
    uint256 public rewardsed = 0;

    uint256 public pid;
    IHecoPool public hecoPool;


    mapping(address => uint256) public userRewardPerSharePaid;
    mapping(address => uint256) public rewards;

    uint256 public totalShare;
    mapping(address => uint256) public shares;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _rewardsDistribution,
        address _rewardsToken,
        address _lpToken,
        address _hecoPool,
        uint256 _pid,
        uint256 _period
    ) public {
        rewardsDistribution = _rewardsDistribution;
        rewardsToken = IERC20MintBurn(_rewardsToken); // gate token
        lpToken = IERC20MintBurn(_lpToken);
        hecoPool = IHecoPool(_hecoPool);
        pid = _pid;
        rewardsDuration = _period;
        lpToken.approve(address(hecoPool), uint(-1)); // 100% trust in the staking pool
    }


    /* ========== VIEWS ========== */
    function lpTotalSupply() public view returns (uint256) {
        (uint256 totalBalance, , ) = hecoPool.userInfo(pid, address(this));
        return totalBalance;
    }

    // share to lp token balance.
    function shareToBalance(uint256 share) public view returns (uint256) {
        if (totalShare == 0) return share; // When there's no share, 1 share = 1 balance.
        (uint256 totalBalance, , ) = hecoPool.userInfo(pid, address(this));
        return share.mul(totalBalance).div(totalShare);
    }

    // lp token balance to share.
    function balanceToShare(uint256 balance) public view returns (uint256) {
        if (totalShare == 0) return balance; // When there's no share, 1 share = 1 balance.
        (uint256 totalBalance, , ) = hecoPool.userInfo(pid, address(this));
        return balance.mul(totalShare).div(totalBalance);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerShare() public view returns (uint256) {
        if (totalShare == 0) {
            return rewardPerTokenStored;
        }
        return
        rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(totalShare)
        );
    }

    function earned(address account) public view returns (uint256) {
        return shares[account].mul(rewardPerShare().sub(userRewardPerSharePaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        // rewardRate * rewardsDuration
        return rewardRate.mul(rewardsDuration);
    }

    function stake(
        uint256 amount,
        address user
    ) external onlyOperator nonReentrant updateReward(user) returns (uint256){
        require(amount > 0, "Cannot stake 0");
        require(user != address(0), "user cannot be 0");
        uint256 share = balanceToShare(amount);
        totalShare = totalShare.add(share);
        shares[user] = shares[user].add(share);
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        hecoPool.deposit(pid, amount);
        emit Staked(user, amount);
        return share;
    }

    function withdraw(
        uint256 withdrawShare,
        address user
    ) public onlyOperator nonReentrant updateReward(user) {
        require(withdrawShare > 0, "Cannot withdraw 0");
        require(user != address(0), "user cannot be 0");
        require(shares[user] >= withdrawShare, "not enough");
        uint256 balance = shareToBalance(withdrawShare);
        hecoPool.withdraw(pid, balance);
        totalShare = totalShare.sub(withdrawShare);
        shares[user] = shares[user].sub(withdrawShare);
        lpToken.safeTransfer(msg.sender, balance);
        emit Withdrawn(user, withdrawShare);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        require(msg.sender != address(0), "user cannot be 0");
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsPaid = rewardsPaid.add(reward);
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function claim() external onlyOperator nonReentrant {
        hecoPool.withdraw(pid, 0);
        uint256 amount = mdx.balanceOf(address(this));
        mdx.transfer(msg.sender, amount);
        emit Claim(amount);
    }

    function reinvest(uint256 amount) external onlyOperator {
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        hecoPool.deposit(pid, amount);
    }

    function burn(uint256 amount) external onlyRewardsDistribution {
        rewardsToken.burn(address(this), amount);
    }

    /* ========== MODIFIER ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerShare();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerSharePaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "require operator");
        _;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) external onlyRewardsDistribution updateReward(address(0)) {
        require(block.timestamp >= periodFinish, "time isn't up");
        rewardRate = reward.div(rewardsDuration);
        rewardsToken.mint(address(this),reward);
        rewardsed = rewardsed.add(reward);
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    function setOperator(address _operator) external onlyRewardsDistribution {
        operator = _operator;
        mdx.safeApprove(address(operator), uint(-1)); // 100% trust in the operator
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event Claim(uint256 amount);
}

