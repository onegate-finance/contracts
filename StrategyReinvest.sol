pragma solidity 0.5.16;

// Inheritance
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";

// Libraries
import 'openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol';
import "@uniswap/v2-core/contracts/libraries/Math.sol";
import './Strategy.sol';
import './SafeToken.sol';

// Internal references
import "./interfaces/IWHT.sol";
import "./interfaces/IMdexFactory.sol";
import "./interfaces/IMdexRouter.sol";
import "./interfaces/IMdexPair.sol";
import "./interfaces/ISwapMining.sol";

import 'hardhat/console.sol';


contract StrategyReinvest is Ownable, ReentrancyGuard, Strategy {
    using SafeToken for address;
    using SafeMath for uint256;

    /* ========== EVENTS ========== */
    event BountyAddressChanded(address bountyAddress, address newBountyAddress);

    IMdexFactory public factory;
    IMdexRouter public router;
    address public wht;
    address public goblin;

    address bountyAdd;
    uint public reinvestBountyBps;

    // Create a new add two-side optimal strategy instance for mdex.
    // _router The Uniswap router smart contract.
    // _goblin The goblin can execute the smart contract.
    constructor(
        IMdexRouter _router,
        address _goblin,
        uint _reinvestBountyBps, // TODO reinvest
        address _bountyAddress // TODO reinvest
    ) public {
        factory = IMdexFactory(_router.factory());
        router = _router;
        wht = _router.WHT();
        goblin = _goblin;
        reinvestBountyBps = _reinvestBountyBps;
        bountyAdd = _bountyAddress;
    }

    /// @dev Throws if called by any account other than the goblin.
    modifier onlyGoblin() {
        require(isGoblin(), 'caller is not the goblin');
        _;
    }

    /// @dev Returns true if the caller is the current goblin.
    function isGoblin() public view returns (bool) {
        return msg.sender == goblin;
    }

    // Execute worker strategy. Take LP tokens + debtToken. Return LP tokens.
    // user User address
    // data Extra calldata information passed along to this strategy.
    function execute(
        address /* user */,
        address /* borrow token */,
        uint256 /* borrow */,
        uint256 /* debt */,
        bytes calldata data
    ) external payable onlyGoblin nonReentrant {

        require(bountyAdd != address(0), "set bounty address first!");
        address token0;
        address token1;
        uint256 minLPAmount;

        // 1、decode
        {
            (address _token0, address _token1, uint256 _minLPAmount) = abi.decode(data, (address, address, uint256));
            token0 = _token0;
            token1 = _token1;
            minLPAmount = _minLPAmount;
        }
        uint256 reward = address(this).balance;

        {
            uint256 bounty = reward.mul(reinvestBountyBps) / 10000;
            SafeToken.safeTransferETH(bountyAdd, bounty);
        }

        {
            uint256 HTBalance = address(this).balance.div(2);
            if (token0 == address(0)){
                token0 = wht;
            } else if (token0 != wht) {
                address[] memory path = new address[](2);
                path[0] = wht;
                path[1] = token0;
                router.swapExactETHForTokens.value(HTBalance)(0, path, address(this), now);
            }

            if (token1 == address(0)){
                token1 = wht;
            } else if (token1 != wht){
                address[] memory path = new address[](2);
                path[0] = wht;
                path[1] = token1;
                router.swapExactETHForTokens.value(HTBalance)(0, path, address(this), now);
            }
        }

        // 4、get lp token
        IMdexPair lpToken = IMdexPair(factory.getPair(token0, token1));
        {
            token0 = lpToken.token0();
            token1 = lpToken.token1();

            token0.safeApprove(address(router), 0);
            token0.safeApprove(address(router), uint256(-1));

            token1.safeApprove(address(router), 0);
            token1.safeApprove(address(router), uint256(-1));

            (,, uint256 moreLPAmount) = router.addLiquidity(token0, token1, token0.myBalance(), token1.myBalance(), 0, 0, address(this), now);
            require(moreLPAmount >= minLPAmount, "insufficient LP tokens received");
        }

        // send lpToken and borrowToken back to the sender.
        // LP token send back
        lpToken.transfer(msg.sender, lpToken.balanceOf(address(this)));
    }

    function getSwapReward(address minter, uint256 pid) public view returns (uint256, uint256) {
        ISwapMining swapMining = ISwapMining(minter);
        return swapMining.getUserReward(pid);
    }

    function swapMiningReward(address minter, address token) external onlyOwner{
        ISwapMining swapMining = ISwapMining(minter);
        swapMining.takerWithdraw();
        token.safeTransfer(msg.sender, token.myBalance());
    }

    function recover(
        address token,
        address to,
        uint value
    ) external onlyOwner nonReentrant {
        token.safeTransfer(to, value);
    }

    function setReinvestBountyBps(uint256 _reinvestBountyBps) external onlyOwner {
        reinvestBountyBps = _reinvestBountyBps;
    }

    function setBountyAdd(address _bountyAddress) external onlyOwner {
        require(_bountyAddress != address(0), "new bounty address is the zero address");
        emit BountyAddressChanded(bountyAdd, _bountyAddress);
        bountyAdd = _bountyAddress;
    }



    function() external payable {}
}
