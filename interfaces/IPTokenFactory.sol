pragma solidity 0.5.16;

interface IPTokenFactory {
    function genPToken(string calldata) external returns(address);
}
