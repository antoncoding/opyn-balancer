pragma solidity 0.6.4;

import "../lib/SafeMath.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IERC20.sol";

contract Controller {
  using SafeMath for uint256;

  uint256 public iv;
  IBPool public pool;

  function init(IBPool _pool) public {
    pool = _pool;
  }

  /**
   * @dev Before each trade: calculate new spot price, adjust weight
   */
  function _pre() internal {

  }

  /**
   * @dev After each trade: calculate new IV base on new spot price.
   */
  function _post(uint _newSpotPrice) internal {
    
  }

  /**
   * @dev same interface as Balancer pool 
   */
  function swapExactAmountIn(
      address tokenIn,
      uint tokenAmountIn,
      address tokenOut,
      uint minAmountOut,
      uint maxPrice
    ) 
    external 
    returns ( uint tokenAmountOut, uint spotPriceAfter ) {
      _pre();
      pool.setPublicSwap(true);
      _pullToken(tokenIn, msg.sender, tokenAmountIn);
      _approve(tokenIn, address(pool), tokenAmountIn);
      (uint _tokenAmountOut, uint _spotPriceAfter) = pool.swapExactAmountIn(tokenIn, tokenAmountIn, tokenOut, minAmountOut, maxPrice);
      _pushToken(tokenOut, msg.sender, _tokenAmountOut);
      _post(_spotPriceAfter);
      pool.setPublicSwap(false);
      return (_tokenAmountOut, _spotPriceAfter);
    }

  /**
   * @dev approve erc20 transfer
   */
  function _approve(address erc20, address spender, uint amount) 
    internal 
  {
    bool success = IERC20(erc20).approve(spender, amount);
    require(success, "ERR_ERC20_FALSE");
  }

  /**
   * @dev pull erc20 token from user
   */
  function _pullToken(address erc20, address from, uint amount)
    internal
  {
    bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
    require(xfer, "ERR_ERC20_FALSE");
  }

  /**
   * @dev send erc20 token to user
   */
  function _pushToken(address erc20, address to, uint amount)
    internal
  {
    bool xfer = IERC20(erc20).transfer(to, amount);
    require(xfer, "ERR_ERC20_FALSE");
  }
}