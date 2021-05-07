pragma solidity ^0.5.16;

// Libraries
import 'openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20.sol';
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";
import "@uniswap/v2-core/contracts/libraries/Math.sol";
import './SafeToken.sol';


contract GToken is ERC20, Ownable {
    using SafeToken for address;
    using SafeMath for uint256;

    string public name = "";
    string public symbol = "";
    uint8 public decimals = 18;

    event Mint(address sender, address account, uint amount);
    event Burn(address sender, address account, uint amount);

    constructor(string memory _symbol) public {
        name = _symbol;
        symbol = _symbol;
    }

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
        emit Mint(msg.sender, account, amount);
    }

    function burn(address account, uint256 value) public onlyOwner {
        _burn(account, value);
        emit Burn(msg.sender, account, value);
    }
}
