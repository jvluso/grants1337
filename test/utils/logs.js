const _ = require("lodash");
const ABIDecoder = require("abi-decoder");
const BigNumber = require("bignumber.js");
const Web3 = require("web3");




function LogNewSubscriptionContract(
    pollAddress,
    forumAddress,
    pollId,
    name
){
    return { name: name,
      events:
       [ { name: '_newPollAddress',
           type: 'address',
           value: pollAddress },
         { name: '_pollId', type: 'uint256', value: String(pollId) } ],
      address: forumAddress }
}





module.exports = {
  LogNewSubscriptionContract
}
