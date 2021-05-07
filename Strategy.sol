pragma solidity 0.5.16;


interface Strategy {
  // Execute worker strategy. Take LP tokens + debt tokens. Return LP tokens + debt tokens.
  // user The original user that is interacting with the operator.
  // borrowToken The token user want borrow.
  // borrow The amount user borrow from bank.
  // debt The user's total debt, for better decision making context.
  // data Extra calldata information passed along to this strategy.
  function execute(
      address user,
      address borrowToken,
      uint256 borrow,
      uint256 debt,
      bytes calldata data
  ) external payable;
}
