pragma solidity 0.6.4;

import "../lib/SafeMath.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ICompoundOracle.sol";
// import "../interfaces/IOptionsContract.sol";

contract Controller {
  using SafeMath for uint256;

  uint256 public iv;

  uint256 public tokenDecimals;
  uint256 public usdcDecimals = 6;
  uint256 public ethDecimals = 18;
  uint256 public ivDecimals = 10;

  address public USDC;
  address public oToken;

  uint256 public strikePrice;
  uint256 public expiry;
  
  IBPool public pool;
  ICompoundOracle public oracle;

  function init(IBPool _pool, 
      ICompoundOracle _oracle, 
      uint256 _strikePrice, 
      uint256 _expiry, 
      address _usdc_address,
      address _oToken,
      uint256 _tokenDecimals
    ) public {
    pool = _pool;
    oracle = _oracle;
    strikePrice = _strikePrice;
    expiry = _expiry;
    USDC = _usdc_address;
    oToken = _oToken;
    tokenDecimals = _tokenDecimals;
  }

  /**
   * @dev Before each trade: calculate new spot price, adjust weight
   */
  function _pre() internal {
    // calculate target price
    uint256 targetSpotPrice = _calculateOptionPrice();

    // calculate new weights
    _updateWeights(targetSpotPrice);

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
      uint256 ethPrice = uint256(10**(ethDecimals + usdcDecimals)).div(usdcPrice); // 206120000

      uint256 timeTilExpiry = expiry.sub(block.timestamp); //
      optionPrice = _approximatePutPrice( strikePrice,  ethPrice, timeTilExpiry, iv);
  }

  /**
   * @dev price = 0.4 * (s - ((x-s)/2) ) * iv * t**(1/2) + (x-s)/2
   * @param x strke price
   * @param spot spot price of eth
   * @param t time til expiry in sec
   * @param v implied volatility
   */
  function _approximatePutPrice(uint256 x, uint256 spot, uint256 t, uint256 v) 
    public
    view
    // internal 
    returns ( uint256 price ) {
      uint256 sqrtT = _nthRoot(t, 2, 0, 100);
      uint256 divider = uint256(14040 * 10**(ivDecimals));
      
      if (x > spot) {
          uint256 d = x.sub(spot).div(2); 
          uint256 avg = spot.sub(d);
          return avg.mul(v).mul(sqrtT).div(divider).add(d);    
      } else {
          uint256 d = spot.sub(x).div(2); 
          uint256 avg = x.sub(d);
          return avg.mul(v).mul(sqrtT).div(divider).sub(d); 
      }
  }
  
  /**
   * @dev calculate implied v based on new price
   */
  function _calculateImpliedVolatility()
    // internal
    public
    view 
    returns ( uint256 _iv ) {
      uint256 spot = pool.getSpotPrice(USDC, oToken);
      uint256 usdcPrice = oracle.getPrice(USDC); // usdc price in wei
      uint256 ethPrice = uint256(10**(ethDecimals + usdcDecimals)).div(usdcPrice); // 206120000
      uint256 timeTilExpiry = expiry.sub(block.timestamp); //
      _iv = _approximatePutIV(spot, strikePrice, ethPrice, timeTilExpiry);
  }

  /**
   * @dev reverse engineer put option iv from price
   * @param p price of option
   * @param x strke price
   * @param spot spot price of eth
   * @param t time til expiry in sec
   */
  function _approximatePutIV(uint256 p, uint256 x, uint256 spot, uint256 t) 
    public
    // internal 
    view
    returns ( uint256 )
    {
      uint256 sqrtT = _nthRoot(t, 2, 0, 100);
      if (x > spot ){
          uint256 d = x.sub(spot).div(2);
          uint256 avg = spot.sub(d);
          uint256 divider = sqrtT.mul(avg).div(uint256(14040));
          return p
            .sub(d)
            .mul(10**ivDecimals)
            .div(divider);    
      } else {
          uint256 d = spot.sub(x).div(2);
          uint256 avg = x.sub(d);
          uint256 divider = sqrtT.mul(avg).div(uint256(14040));
          return p
            .add(d)
            .mul(10**ivDecimals)
            .div(divider);    
      }
  }

  function _calculateFee() 
    internal
    pure
    returns ( uint256 newFee ) {
      newFee = 1000000000000000000; // 1%
  }

  /**
   * @dev Update weight to fit new option price.
   */
  function _updateWeights(uint256 _targetSpot) 
    // internal
    public
  {
    uint256 poolUSDC = pool.getBalance(USDC);
    uint256 poolToken = pool.getBalance(oToken);

    (uint256 newTokenW, uint256 newUSDCW) = _getNewWeights(_targetSpot, poolUSDC, poolToken);

    uint256 oldTokenW = pool.getDenormalizedWeight(oToken);
    
    if (newTokenW < oldTokenW) {
      // update new oToken weight first
      pool.rebind(oToken, poolToken, newTokenW);
      pool.rebind(USDC, poolUSDC, newUSDCW);
    } else {
      // update USDC weight first
      pool.rebind(USDC, poolUSDC, newUSDCW);
      pool.rebind(oToken, poolToken, newTokenW);
    }
  }

  /**
    * @dev  Calculate new weights
    * Wo = ( Bu * 10^(oTokenD)  + spot * Bo ) / ( spot * Bo * 10^19 ) 
    * Wu = 10 ^ 19 - Wo
    **/
  function _getNewWeights(uint256 newPrice, uint256 usdcBalance, uint256 oTokenBalance) 
    public 
    // internal
    view 
    returns (uint256 tokenWeight, uint256 usdcWeight) 
    {
      uint256 weightSum = 10**19;
      uint256 denominator = usdcBalance.mul(10**(tokenDecimals)).add(newPrice.mul(oTokenBalance)) ;
      uint256 numerator = newPrice.mul(oTokenBalance).mul(weightSum);
      uint256 oTokenWeight = numerator.div(denominator);
      return ( oTokenWeight, weightSum.sub(oTokenWeight) );
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