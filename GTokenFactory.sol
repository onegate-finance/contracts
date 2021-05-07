pragma solidity ^0.5.16;

import "./GToken.sol";

contract GTokenFactory {

    function genGToken(string memory _symbol) public onlyBanker returns(address) {
        GToken token = new GToken(_symbol);
        token.transferOwnership(msg.sender);
        return address(token);
    }
}
