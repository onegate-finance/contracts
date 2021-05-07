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

contract StrategyLiquidate is Ownable, ReentrancyGuard, Strategy {
    using SafeToken for address;

    IMdexFactory public factory;
    IMdexRouter public router;
    address public wht;
    address public goblin;

    // Create a new liquidate strategy instance.
    // _router The Uniswap router smart contract.
    constructor(
        IMdexRouter _router,
        address _goblin
    ) public {
        factory = IMdexFactory(_router.factory());
        router = _router;
        wht = _router.WHT();
        goblin = _goblin;
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

    /// Execute worker strategy. Take LP tokens. Return borrow token.
    /// data Extra calldata information passed along to this strategy.
    function execute(
        address, /* user */
        address borrowToken,
        uint256 /* borrow */,
        uint256, /* debt */
        bytes calldata data
    ) external payable onlyGoblin nonReentrant {
        (address token0, address token1) = abi.decode(data, (address, address));

        // is borrowToken is ht.
        bool isBorrowHT = borrowToken == address(0);
        require(borrowToken == token0 || borrowToken == token1 || isBorrowHT, "borrowToken not token0 and token1");

        // the relative token when token0 or token1 is ht.
        address HTRelative;
        {
            if (token0 == address(0)){
                token0 = wht;
                HTRelative = token1;
            }
            if (token1 == address(0)){
                token1 = wht;
                HTRelative = token0;
            }
        }

        IMdexPair lpToken = IMdexPair(factory.getPair(token0, token1));
        token0 = lpToken.token0();
        token1 = lpToken.token1();

        {
            lpToken.approve(address(router), uint256(-1));
            router.removeLiquidity(token0, token1, lpToken.balanceOf(address(this)), 0, 0, address(this), now);
        }

        {
            borrowToken = isBorrowHT ? wht : borrowToken;
            address tokenRelative = borrowToken == token0 ? token1 : token0;
            uint256 relativeTokenAmount = tokenRelative.myBalance();
            tokenRelative.safeApprove(address(router), 0);
            tokenRelative.safeApprove(address(router), uint256(-1));

            address[] memory path = new address[](2);
            path[0] = tokenRelative;
            path[1] = borrowToken;
            router.swapExactTokensForTokens(relativeTokenAmount, 0, path, address(this), now);

            safeUnWrapperAndAllSend(borrowToken, msg.sender);
        }

    }

    function safeUnWrapperAndAllSend(address token, address to) internal {
        uint256 total = SafeToken.myBalance(token);
        if (total > 0) {
            if (token == wht) {
                IWHT(wht).withdraw(total);
                SafeToken.safeTransferETH(to, total);
            } else {
                SafeToken.safeTransfer(token, to, total);
            }
        }
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

    /// Recover ERC20 tokens that were accidentally sent to this smart contract.
    /// token The token contract. Can be anything. This contract should not hold ERC20 tokens.
    /// to The address to send the tokens to.
    /// value The number of tokens to transfer to `to`.
    function recover(
        address token,
        address to,
        uint value
    ) external onlyOwner nonReentrant {
        token.safeTransfer(to, value);
    }

    function() external payable {}
}
