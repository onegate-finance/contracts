pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import 'openzeppelin-solidity-2.3.0/contracts/token/ERC20/IERC20.sol';

interface IHecoPool {

    // deposit lp token
    function deposit(uint256 pid, uint256 amount) external;

    // with draw lp token
    function withdraw(uint256 pid, uint256 amount) external;

    // fetch lp token amount to the address
    function userInfo(uint256, address) external view returns (uint256, uint256, uint256);

    // fetch pool info based on pool id
    function poolInfo(uint256) external view returns (IERC20 , uint256, uint256, uint256, uint256, uint256);
}
