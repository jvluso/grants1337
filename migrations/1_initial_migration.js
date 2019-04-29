var Migrations = artifacts.require("./Migrations.sol");
var Checkpoint = artifacts.require("./Checkpoint.sol");
var Subscription = artifacts.require("./Subscription.sol");

module.exports = function(deployer) {
  console.log("dfsadsfas")
  deployer.deploy(Migrations);
  deployer.deploy(Checkpoint);
  deployer.link(Checkpoint,Subscription);
};
