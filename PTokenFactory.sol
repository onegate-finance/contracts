pragma solidity ^0.5.16;
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "./PToken.sol";

contract PTokenFactory is Ownable {
    address public bankerAddress;

    modifier onlyBanker() {
        require(msg.sender == bankerAddress, 'not banker');
        _;
    }

    function setBanker(address _bankerAddress) external onlyOwner {
        require(_bankerAddress != address(0), "banker can not be zero address");
        bankerAddress = _bankerAddress;
    }

    function genPToken(string memory _symbol) public onlyBanker returns(address) {
        PToken token = new PToken(_symbol);
        token.transferOwnership(msg.sender);
        return address(token);
    }
}
