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

  function _pre() internal {

  }

  function _post(uint _newSpotPrice) internal {
    
  }

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
      _approvePool(tokenIn, address(pool), tokenAmountIn);
      (uint _tokenAmountOut, uint _spotPriceAfter) = pool.swapExactAmountIn(tokenIn, tokenAmountIn, tokenOut, minAmountOut, maxPrice);
      _pushToken(tokenOut, msg.sender, _tokenAmountOut);
      _post(_spotPriceAfter);
      pool.setPublicSwap(false);
      return (_tokenAmountOut, _spotPriceAfter);
    }

  function _approvePool(address erc20, address spender, uint amount) 
    internal 
  {
    bool success = IERC20(erc20).approve(spender, amount);
    require(success, "ERR_ERC20_FALSE");
  }

  function _pullToken(address erc20, address from, uint amount)
    internal
  {
    bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
    require(xfer, "ERR_ERC20_FALSE");
  }

  function _pushToken(address erc20, address to, uint amount)
    internal
  {
    bool xfer = IERC20(erc20).transfer(to, amount);
    require(xfer, "ERR_ERC20_FALSE");
  }
}