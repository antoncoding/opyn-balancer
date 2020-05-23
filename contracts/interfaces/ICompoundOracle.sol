pragma solidity ^0.6.0;

interface ICompoundOracle {
  function getPrice(address asset) external view returns (uint);
}