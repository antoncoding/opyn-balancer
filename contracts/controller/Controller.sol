pragma solidity 0.6.4;

import "../lib/SafeMath.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ICompoundOracle.sol";
// import "../interfaces/IOptionsContract.sol";

contract Controller {
  using SafeMath for uint256;

  uint256 public iv;
  uint256 public usdcDecimals;

  address public USDC;
  uint256 public strikePrice;
  uint256 public expiry;
  
  IBPool public pool;
  ICompoundOracle public oracle;

  function init(IBPool _pool, ICompoundOracle _oracle, uint256 _strikePrice, uint256 _expiry, address _usdc_address) public {
    pool = _pool;
    oracle = _oracle;
    strikePrice = _strikePrice;
    expiry = _expiry;
    USDC = _usdc_address;
    usdcDecimals = 6;
  }

  /**
   * @dev Before each trade: calculate new spot price, adjust weight
   */
  function _pre() internal {
    // calculate target price
    uint256 newPrice = _calculateOptionPrice();


    // update fee
    uint256 newSwapFee = _calculateFee();
    pool.setSwapFee(newSwapFee);
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
   * @dev calculate option price based on timestamp and current eth price.
   */
  function _calculateOptionPrice()
    // internal
    public
    view 
    returns ( uint256 optionPrice ) {
      uint256 usdcPrice = oracle.getPrice(USDC); // usdc price in wei
      uint256 ethPrice = uint256(10**18).mul(10**usdcDecimals).div(usdcPrice);

      uint256 timeTilExpiry = expiry.sub(block.timestamp); //
      optionPrice = _approximatePrice(strikePrice, ethPrice, timeTilExpiry, iv);
  }

  /**
   * @dev calculate implied v based on new price
   */
  function _calculateImpliedVolatility()
    // internal
    public
    view 
    returns ( uint256 _iv ) {
      uint256 usdcPrice = oracle.getPrice(USDC); // get price again after the trade
      uint256 ethPrice = uint256(10**18).div(usdcPrice);
      uint256 timeTilExpiry = expiry.sub(block.timestamp); //
      _iv = _approximateIV(strikePrice, ethPrice, timeTilExpiry, iv);
  }

  function _calculateFee() 
    internal
    pure
    returns ( uint256 newFee ) {
      newFee = 1000000000000000000; // 1%
  }

  /**
   * @dev price = 0.4 * (s - ((s-x)/2) ) * iv * t**(1/2) + (s-x)/2
   * @param x strke price
   * @param spot spot price of eth
   * @param t time til expiry in sec
   * @param v implied volatility
   */
  function _approximatePrice(uint256 x, uint256 spot, uint256 t, uint256 v) 
    public
    // internal 
    pure
    returns ( uint256 price ) {
      uint256 d = spot.sub(x).div(2);
      uint256 sqrtT = _nthRoot(t, 2, 0, 100);
      return spot.sub(d).mul(v).mul(sqrtT).div(uint256(14040)).add(d);
      // return uint256(0.4).mul(spot.sub(d)).mul(v).mul(sqrtT).div(uint256(5616)) + d;
  }

  /**
   * @dev reverse engineer iv from price
   * @param p price of option
   * @param x strke price
   * @param spot spot price of eth
   * @param t time til expiry in sec
   */
  function _approximateIV(uint256 p, uint256 x, uint256 spot, uint256 t) 
    public
    // internal 
    pure
    returns ( uint256 price ) {
      uint256 d = spot.sub(x).div(2);
      uint256 sqrtT = _nthRoot(t, 2, 0, 100);
      uint256 divider = sqrtT.mul(spot.sub(d)).div(uint256(14040));
      return p.sub(d).div(divider);
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

  /**
   * @dev The scale factor is a crude way to turn everything into integer calcs.
   * Actually do (a * (10 ^ ((dp + 1) * n))) ^ (1/n)
   * We calculate to one extra dp and round at the end
   */
  function _nthRoot(uint _a, uint _n, uint _dp, uint _maxIts) 
    internal
    pure
    returns(uint)
    {
      assert (_n > 1);

      uint one = 10 ** (1 + _dp);
      uint a0 = one ** _n * _a;

      // Initial guess: 1.0
      uint xNew = one;
      uint x;

      uint iter = 0;
      while (xNew != x && iter < _maxIts) {
          x = xNew;
          uint t0 = x ** (_n - 1);
          if (x * t0 > a0) {
              xNew = x - (x - a0 / t0) / _n;

          } else {
              xNew = x + (a0 / t0 - x) / _n;
          }
          ++iter;
      }

      // Round to nearest in the last dp.
      return (xNew + 5) / 10;
    }
}