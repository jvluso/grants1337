var Migrations = artifacts.require("./Migrations.sol");
var Subscription = artifacts.require("./Subscription.sol");


module.exports = function(deployer) {
  deployer.deploy(Subscription);
  deployer.deploy(Migrations);

};
