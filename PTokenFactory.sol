pragma solidity ^0.5.16;
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "./PToken.sol";

contract PTokenFactory {
    function genPToken(string memory _symbol) public returns(address) {
        PToken token = new PToken(_symbol);
        token.transferOwnership(msg.sender);
        return address(token);
    }
}
