var Subscription = artifacts.require("./Subscription.sol");

module.exports = function(deployer) {
  deployer.deploy(Subscription,"0xcd20c1b8b1fe6ab8f40b3c3bcf2744f272e9c94b", 
      "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
      1,
      2629800,
      0,
      3600);
};
