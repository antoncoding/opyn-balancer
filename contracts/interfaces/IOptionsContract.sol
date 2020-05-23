pragma solidity ^0.6.0;

import "./IERC20.sol";

/**
 * @title Interface Opyn's Options Contract
 * @author Opyn
 */
abstract contract IOptionsContract is IERC20 {

    /* represents floting point numbers, where number = value * 10 ** exponent
    i.e 0.1 = 10 * 10 ** -3 */
    struct Number {
        uint256 value;
        int32 exponent;
    }

    // The amount of insurance promised per oToken
    Number public strikePrice;

    // The amount of underlying that 1 oToken protects.
    Number public oTokenExchangeRate;

    // The time of expiry of the options contract
    uint256 public expiry;
}
