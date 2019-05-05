pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
  constructor(address[] addresses) public{
    for(uint i=0;i<addresses.length;i++){
      super._mint(addresses[i],100000000000000000000);
    }
  }
}
