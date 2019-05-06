// import BigNumber from "bignumber.js";
const BigNumber = require("bignumber.js");

const chai = require("chai");
const ChaiAsPromised = require("chai-as-promised");
const ChaiBigNumber = require("chai-bignumber");
const Web3 = require("web3");
const ABIDecoder = require("abi-decoder");
const timestamp = require("unix-timestamp");
const timekeeper = require('timekeeper');


const INVALID_OPCODE = "invalid opcode";
const REVERT_ERROR = "revert";

const EMPTY_BYTES32_HASH = "0x" + web3._extend.utils.padRight("0", 64)

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

const expect = chai.expect;
chai.config.includeStack = true;
chai.use(ChaiBigNumber());
chai.use(ChaiAsPromised);
chai.should();

BigNumber.config({  EXPONENTIAL_AT: 1000  });


const LogNewSubscriptionContract = require("./utils/logs").LogNewSubscriptionContract;

const SubscriptionContract = artifacts.require("./Subscription.sol");
const CheckpointContract = artifacts.require("./Checkpoint.sol");
const ERC20Contract = artifacts.require("./TestERC20.sol");

// Initialize ABI Decoder for deciphering log receipts
ABIDecoder.addABI(SubscriptionContract.abi);

contract("Subscription Contract", (ACCOUNTS) => {
    let Subscription;

    const OWNER = ACCOUNTS[0];
    const USER_1 = ACCOUNTS[1];
    const USER_2 = ACCOUNTS[2];
    const USER_3 = ACCOUNTS[3];

    const PERIOD = 2;
    const PAYMENT = 10;
    const GASPRICE = 1;
    const GRACEPERIOD = 1;
    const NONCE = 0;



    const NULL_ADDRESS = "0x0000000000000000000000000000000000000000";

    const TX_DEFAULTS = { from: OWNER, gas: 4000000 };


    before(async () => {

        const ercInstance =
            await ERC20Contract.new( [OWNER,USER_1,USER_2,USER_3],  { from: OWNER, gas: 40000000 });

        DAI = ercInstance.address;

        const ercContractInstance =
            web3.eth.contract(ercInstance.abi).at(ercInstance.address);

        ERC20 = new ERC20Contract(
            ercContractInstance, { from: OWNER, gas: 40000000 });
    });
    beforeEach(async () => {
        const instance =
            await SubscriptionContract.new( USER_1, DAI, PAYMENT, PERIOD, GASPRICE, GRACEPERIOD,  { from: OWNER, gas: 40000000 });

        const web3ContractInstance =
            web3.eth.contract(instance.abi).at(instance.address);

        Subscription = new SubscriptionContract(
            web3ContractInstance, { from: OWNER, gas: 40000000 });

    });

    describe("Create Subscription Contract", () => {


      it("should return correct requiredToAddress", async () => {

        await expect(Subscription.requiredToAddress.call()).to.eventually.equal(USER_1);

      });

      it("should return correct requiredTokenAddress", async () => {

        await expect(Subscription.requiredTokenAddress.call()).to.eventually.equal(DAI);

      });

      it("should return correct requiredTokenAmount", async () => {

        await expect(Subscription.requiredTokenAmount.call()).to.eventually.bignumber.equal(PAYMENT);

      });

      it("should return correct requiredPeriodSeconds", async () => {

        await expect(Subscription.requiredPeriodSeconds.call()).to.eventually.bignumber.equal(PERIOD);

      });

      it("should return correct requiredGasPrice", async () => {

        await expect(Subscription.requiredGasPrice.call()).to.eventually.bignumber.equal(GASPRICE);

      });

    });

    describe("Test Full Flow", () => {


      it("should complete use flow without errors", async () => {

        let result = await Subscription.getSubscriptionHash.call(USER_2, USER_1, DAI, PAYMENT, PERIOD, GASPRICE, NONCE)

        let sig = web3.eth.sign(USER_2,result);

        await ERC20.approve(Subscription.address,PAYMENT * 10000000, {from:USER_2});

        await Subscription.executeSubscription(USER_2, USER_1, DAI, PAYMENT, PERIOD, GASPRICE, NONCE, sig);

        await expect(Subscription.balanceOf.call(USER_2)).to.eventually.bignumber.equal(PAYMENT);
        await expect(Subscription.totalSupply.call()).to.eventually.bignumber.equal(PAYMENT);

        await sleep(5500);

        await expect(Subscription.balanceOf.call(USER_2)).to.eventually.bignumber.equal(0);
        await expect(Subscription.totalSupply.call()).to.eventually.bignumber.equal(0);
 
        await Subscription.executeSubscription(USER_2, USER_1, DAI, PAYMENT, PERIOD, GASPRICE, NONCE, sig);

        await expect(Subscription.balanceOf.call(USER_2)).to.eventually.bignumber.equal(PAYMENT);
        await expect(Subscription.totalSupply.call()).to.eventually.bignumber.equal(PAYMENT);

        await sleep(5500);

        await expect(Subscription.balanceOf.call(USER_2)).to.eventually.bignumber.equal(0);
        await expect(Subscription.totalSupply.call()).to.eventually.bignumber.equal(0);
      });



    });

});
