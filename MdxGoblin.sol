pragma solidity 0.5.16;

// Inheritance
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";
import './Goblin.sol';

// Libraries
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";
import 'openzeppelin-solidity-2.3.0/contracts/token/ERC20/IERC20.sol';
import './SafeToken.sol';

// Internal references
import "./PTokenFactory.sol";
import './Strategy.sol';
import "./interfaces/IMdexFactory.sol";
import "./interfaces/IMdexRouter.sol";
import "./interfaces/IMdexPair.sol";
import "./interfaces/IHecoPool.sol";
import "@uniswap/v2-core/contracts/libraries/Math.sol";
import "./interfaces/ILpStakingRewards.sol";
import 'hardhat/console.sol';


contract MdxGoblin is Ownable, ReentrancyGuard, Goblin {
    /* ========== LIBRARIES ========== */
    using SafeToken for address;
    using SafeMath for uint256;

    /* ========== EVENTS ========== */
    event AddPosition(uint256 indexed id, uint256 lpAmount);
    event RemovePosition(uint256 indexed id, uint256 lpAmount);
    event Liquidate(uint256 indexed id, address lpTokenAddress, uint256 lpAmount, address debtToken, uint256 liqAmount);
    event Reinvest(uint256 lpAmount);

    IHecoPool public hecoPool;
    ILpStakingRewards public staking; //
    IMdexFactory public factory;
    IMdexRouter public router;
    IMdexPair public lpToken;
    Strategy public liqStrat;
    Strategy public addStrat;

    address public wht;
    address public token0;
    address public token1;
    address public operator;
    address public mdx = 0x25D2e80cB6B86881Fd7e07dd263Fb79f4AbE033c;

    // Mutable state variables
    mapping(uint256 => uint256) public shares;
    mapping(address => bool) public okStrats;

    uint256 public pid;


    // Require that the caller must be an EOA account to avoid flash loans.
    modifier onlyEOA() {
        require(msg.sender == tx.origin, 'not eoa');
        _;
    }

    // Require that the caller must be the operator (the bank).
    modifier onlyOperator() {
        require(msg.sender == operator, 'not operator');
        _;
    }

    constructor(
        address _operator,
        IHecoPool _hecoPool,
        ILpStakingRewards _staking,
        IMdexRouter _router,
        uint256 _pid,
        Strategy _addStrat,
        Strategy _liqStrat
    ) public {
        operator = _operator;
        wht = _router.WHT();
        hecoPool = _hecoPool;
        staking = _staking;
        router = _router;
        factory = IMdexFactory(_router.factory());
        pid = _pid;
        (IERC20 _lpToken, , , , , ) = hecoPool.poolInfo(_pid);
        lpToken = IMdexPair(address(_lpToken));
        token0 = lpToken.token0();
        token1 = lpToken.token1();
        addStrat = _addStrat;
        liqStrat = _liqStrat;
        lpToken.approve(address(_staking), uint(-1)); // 100% trust in the staking pool
        mdx.safeApprove(address(router), uint(-1)); // 100% trust in the router
    }

    /* ========== PURE ========== */
    function getMktSellAmount(
        uint aIn,
        uint rIn,
        uint rOut
    ) public pure returns (uint256) {
        if (aIn == 0) return 0;
        require(rIn > 0 && rOut > 0, 'bad reserve values');
        uint aInWithFee = aIn.mul(997);
        uint numerator = aInWithFee.mul(rOut);
        uint denominator = rIn.mul(1000).add(aInWithFee);
        return numerator / denominator;
    }

    /* ========== VIEWS ========== */
    function lpTotalSupply() public view returns (uint256) {
        return staking.lpTotalSupply();
    }

    // share to lp token balance.
    function shareToBalance(uint256 share) public view returns (uint256) {
        uint256 totalShare = staking.totalShare();
        if (totalShare == 0) return share; // When there's no share, 1 share = 1 balance.
        uint256 totalBalance = lpTotalSupply();
        return share.mul(totalBalance).div(totalShare);
    }

    // Return the amount of HT to receive if we are to liquidate the given position.
    // id The position ID to perform health check.
    function health(uint256 id, address borrowToken) external view returns (uint256) {
        bool isDebtHT = borrowToken == address(0);
        require(borrowToken == token0 || borrowToken == token1 || isDebtHT, "borrowToken not token0 and token1");

        // 1. Get the position's LP balance and LP total supply.
        uint256 posBalance = shareToBalance(shares[id]);
        uint256 lpSupply = lpToken.totalSupply();
        // Ignore pending mintFee as it is insignificant
        // 2. Get the pool's total supply of token0 and token1.
        (uint256 totalAmount0, uint256 totalAmount1,) = lpToken.getReserves();

        // 3. Convert the position's LP tokens to the underlying assets.
        uint256 userToken0 = posBalance.mul(totalAmount0).div(lpSupply);
        uint256 userToken1 = posBalance.mul(totalAmount1).div(lpSupply);

        if (isDebtHT) {
            borrowToken = token0 == wht ? token0 : token1;
        }

        // 4. Convert all farming tokens to debtToken and return total amount.
        if (borrowToken == token0) {
            return getMktSellAmount(
                userToken1, totalAmount1.sub(userToken1), totalAmount0.sub(userToken0)
            ).add(userToken0);
        } else {
            return getMktSellAmount(
                userToken0, totalAmount0.sub(userToken0), totalAmount1.sub(userToken1)
            ).add(userToken1);
        }
    }

    /* ========== MODIFIERS ========== */

    // Re-invest whatever this worker has earned back to staked LP tokens.
    function reinvest() external nonReentrant {
        staking.claim();

        uint reward = mdx.balanceOf(address(this));
        if (reward == 0) return;

        address[] memory path = new address[](2);
        path[0] = address(mdx);
        path[1] = address(wht);
        router.swapExactTokensForETH(reward, 0, path, address(this), now);

        addStrat.execute.value(address(this).balance)(address(0), address(0), 0, 0, abi.encode(token0, token1, 0));

        // Mint more LP tokens and stake them for more rewards.
        uint256 lpAmount = lpToken.balanceOf(address(this));
        staking.reinvest(lpAmount);

        emit Reinvest(lpAmount);
    }

    // Work on the given position. Must be called by the operator.
    function work(
        uint id,
        address user,
        address borrowToken,
        uint256 borrow,
        uint256 debt,
        bytes calldata data
    ) external payable onlyOperator nonReentrant {

        require(borrowToken == token0 || borrowToken == token1 || borrowToken == address(0), "borrowToken not token0 and token1");

        // 1. Convert this position back to LP tokens.
        _removeShare(id, user);

        // 2. Perform the worker strategy; sending LP tokens + borrowToken; expecting LP tokens.
        (address strat, bytes memory ext) = abi.decode(data, (address, bytes));
        require(okStrats[strat], 'unapproved work strategy');
        lpToken.transfer(strat, lpToken.balanceOf(address(this)));

        // transfer the borrow token.
        if (borrow > 0 && borrowToken != address(0)) {
            borrowToken.safeTransferFrom(msg.sender, address(this), borrow);
            borrowToken.safeApprove(address(strat), 0);
            borrowToken.safeApprove(address(strat), uint256(-1));
        }

        Strategy(strat).execute.value(msg.value)(user, borrowToken, borrow, debt, ext);

        // 3. Add LP tokens back to the farming pool.
        _addShare(id, user);

        // 4. Return any any borrow token back to the operator.
        if (borrowToken == address(0)) {
            SafeToken.safeTransferETH(msg.sender, address(this).balance);
        } else {
            uint256 borrowTokenAmount = borrowToken.myBalance();
            if(borrowTokenAmount > 0){
                SafeToken.safeTransfer(borrowToken, msg.sender, borrowTokenAmount);
            }
        }
    }


    // Liquidate the given position by converting it to debtToken and return back to caller.
    function liquidate(uint256 id, address borrowToken, address user) external onlyOperator nonReentrant {
        bool isBorrowHT = borrowToken == address(0);
        require(borrowToken == token0 || borrowToken == token1 || isBorrowHT, "borrowToken not token0 and token1");

        _removeShare(id, user);

        uint256 lpTokenAmount = lpToken.balanceOf(address(this));
        lpToken.transfer(address(liqStrat), lpTokenAmount);

        liqStrat.execute(
                address(0),
                borrowToken,
                uint256(0),
                uint256(0),
                abi.encode(address(token0), address(token1))
        );

        uint256 tokenLiquidate;
        if (isBorrowHT){
            tokenLiquidate = address(this).balance;
            SafeToken.safeTransferETH(msg.sender, tokenLiquidate);
        } else {
            tokenLiquidate = borrowToken.myBalance();
            borrowToken.safeTransfer(msg.sender, tokenLiquidate);
        }

        emit Liquidate(id, address(lpToken), lpTokenAmount, borrowToken, tokenLiquidate);
    }

    /// Internal function to stake all outstanding LP tokens to the given position ID.
    function _addShare(uint256 id, address user) internal {
        uint balance = lpToken.balanceOf(address(this));
        if (balance > 0) {
            uint256 share = staking.stake(balance, user);
            shares[id] = shares[id].add(share);
            emit AddPosition(id, share);
        }
    }

    // Internal function to remove shares of the ID and convert to outstanding LP tokens.
    function _removeShare(uint256 id, address user) internal {
        uint share = shares[id];
        if (share > 0) {
            staking.withdraw(share, user);
            shares[id] = 0;
            emit RemovePosition(id, share);
        }
    }

    function recover(
        address token,
        address to,
        uint value
    ) external onlyOwner nonReentrant {
        token.safeTransfer(to, value);
    }

    function setStrategyOk(address[] calldata strats, bool isOk) external onlyOwner {
        uint len = strats.length;
        for (uint idx = 0; idx < len; idx++) {
          okStrats[strats[idx]] = isOk;
        }
    }

    function setCriticalStrategies(Strategy _addStrat, Strategy _liqStrat) external onlyOwner {
        addStrat = _addStrat;
        liqStrat = _liqStrat;
    }

    function setMdx(address _mdx) external onlyOwner {
        mdx = _mdx;
        mdx.safeApprove(address(router), uint(-1)); // 100% trust in the router
    }

    function() external payable {}
}
