var Subscription = artifacts.require("./Subscription.sol");

module.exports = function(deployer) {
  deployer.deploy(Subscription,"0xcd20c1b8b1fe6ab8f40b3c3bcf2744f272e9c94b", 
      "0x4a5ff41edf09ab390a41d8431b563fe6153729bd",
      1,
      2629800,
      0,
      3600);
};
