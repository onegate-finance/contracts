pragma solidity 0.5.16;

interface IGTokenFactory {
    function genPToken(string calldata) external returns(address);
}
