var Migrations = artifacts.require("./Migrations.sol");
var Checkpoint = artifacts.require("./Checkpoint.sol");
var Subscription = artifacts.require("./Subscription.sol");

module.exports = function(deployer) {
  deployer.deploy(Migrations);
  deployer.deploy(Checkpoint);
  deployer.link(Checkpoint,Subscription);
};
