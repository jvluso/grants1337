pragma solidity ^0.4.24;
/*
  Token Subscriptions With History

  This is an extension of the erc1337 token subscription to allow voting in an aragon vote based on subscription level

  the following should all hold once complete:
  calling balanceOfAt multiple times for past blocks must always return the same result given the same input
  calling totalSupplyAt multiple times for past blocks must always return the same result given the same input
  it should be possible to limit abuse of the grace period by adjusting the constants
  the sum of all balanceOfAt calls must be less than or equal to the totalSupplyAt in a single previous block
  after paying a subscription for a period of time, you must have that balance represented for at least that amount of time 

  Building on previous works:
    https://github.com/austintgriffith/token-subscription
    https://gist.github.com/androolloyd/0a62ef48887be00a5eff5c17f2be849a
    https://media.consensys.net/subscription-services-on-the-blockchain-erc-948-6ef64b083a36
    https://medium.com/gitcoin/technical-deep-dive-architecture-choices-for-subscriptions-on-the-blockchain-erc948-5fae89cabc7a
    https://github.com/ethereum/EIPs/pull/1337
    https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1077.md
    https://github.com/gnosis/safe-contracts

  Earlier Meta Transaction Demo:
    https://github.com/austintgriffith/bouncer-proxy

  Huge thanks, as always, to OpenZeppelin for the rad contracts:
 */

import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "./Checkpoint.sol";


contract Subscription {
    using ECDSA for bytes32;
    using SafeMath for uint256;
    using Checkpoint for Checkpoint.Data;

    //who deploys the contract
    address public author;

    // the publisher may optionally deploy requirements for the subscription
    // so only meta transactions that match the requirements can be relayed
    address public requiredToAddress;
    address public requiredTokenAddress;
    uint256 public requiredTokenAmount;
    uint256 public requiredPeriodSeconds;
    uint256 public requiredGasPrice;
    uint256 public gracePeriodSeconds;

    string constant public name = "Subscription";
    string constant public symbol = "SUB";
    uint8 constant public decimals = 18;
    bool constant public transferable = false;

    struct  User {
        Checkpoint.Data checkpoints;
        bytes32 activeSubscription;
    }

    // users keeps track of each user's subscription history
    mapping(address => User) users;

    // keeps track of the maximum subscriptions into the future
    mapping(uint => uint) expirations; // timestamp => value of expiring subscriptions
    Checkpoint.Data maximumSubscriptions;
    Checkpoint.Data blockNumbers; // timestamp => block number
    uint lastUpdate;


    // similar to a nonce that avoids replay attacks this allows a single execution
    // every x seconds for a given subscription
    // subscriptionHash  => next valid block number
    mapping(bytes32 => uint256) public nextValidTimestamp;

    //we'll use a nonce for each from but because transactions can go through
    //multiple times, we allow anything but users can use this as a signal for
    //uniqueness
    mapping(address => uint256) public extraNonce;

    // we need to keep track of hashes that have been pre-signed by smart contracts
    // If we allow offline signing there may be issues with the signature being 
    // frontrun-retracted. This might be worth adding anyway because the relayer can
    // validate the contract before relaying it.
    mapping(bytes32 => bool) public presigned;

    event ExecuteSubscription(
        address indexed from, //the subscriber
        address indexed to, //the publisher
        address tokenAddress, //the token address paid to the publisher
        uint256 tokenAmount, //the token amount paid to the publisher
        uint256 periodSeconds, //the period in seconds between payments
        uint256 gasPrice, //the amount of tokens to pay relayer (0 for free)
        uint256 nonce // to allow multiple subscriptions with the same parameters
    );

    event CancelSubscription(
        address indexed from, //the subscriber
        address indexed to, //the publisher
        address tokenAddress, //the token address paid to the publisher
        uint256 tokenAmount, //the token amount paid to the publisher
        uint256 periodSeconds, //the period in seconds between payments
        uint256 gasPrice, //the amount of tokens to pay relayer (0 for free)
        uint256 nonce // to allow multiple subscriptions with the same parameters
    );
    constructor(
        address _toAddress,
        address _tokenAddress,
        uint256 _tokenAmount,
        uint256 _periodSeconds,
        uint256 _gasPrice,
        uint256 _gracePeriodSeconds
    ) public {
        requiredToAddress=_toAddress;
        requiredTokenAddress=_tokenAddress;
        requiredTokenAmount=_tokenAmount;
        requiredPeriodSeconds=_periodSeconds;
        requiredGasPrice=_gasPrice;
        gracePeriodSeconds=_gracePeriodSeconds;
        author=msg.sender;
        lastUpdate=block.timestamp-(block.timestamp%_gracePeriodSeconds);
    }

    event ExecuteSubscription(
        address indexed from, //the subscriber
        address indexed to, //the publisher
        address tokenAddress, //the token address paid to the publisher
        uint256 tokenAmount, //the token amount paid to the publisher
        uint256 periodSeconds, //the period in seconds between payments
        uint256 gasPrice //the amount of tokens to pay relayer (0 for free)
    );


    // this allows smart contracts to create a subscription 
    function presignHash(
        address to, //the publisher
        address tokenAddress, //the token address paid to the publisher
        uint256 tokenAmount, //the token amount paid to the publisher
        uint256 periodSeconds, //the period in seconds between payments
        uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
        uint256 nonce // to allow multiple subscriptions with the same parameters
    )
        external
    {
        presigned[getSubscriptionHash(
            msg.sender, to, tokenAddress, tokenAmount, periodSeconds, gasPrice, nonce
        )] = true;
    }



    // this is used in the original subscription contract to verify that a
    // particular subscription is "paid" and "active"
    // on chain contracts should use isSubscriptionActiveAt to gaurentee 
    // consistancy.
    function isSubscriptionActive(
        bytes32 subscriptionHash,
        uint256 _gracePeriodSeconds
    )
        external
        view
        returns (bool)
    {
        return (block.timestamp <=
                nextValidTimestamp[subscriptionHash].add(_gracePeriodSeconds)
        );
    }

    // given the subscription details, generate a hash and try to kind of follow
    // the eip-191 standard and eip-1077 standard from my dude @avsa
    function getSubscriptionHash(
        address from, //the subscriber
        address to, //the publisher
        address tokenAddress, //the token address paid to the publisher
        uint256 tokenAmount, //the token amount paid to the publisher
        uint256 periodSeconds, //the period in seconds between payments
        uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
        uint256 nonce // to allow multiple subscriptions with the same parameters
    )
        public
        view
        returns (bytes32)
    {
        // if there are requirements from the deployer, let's make sure
        // those are met exactly
        require( requiredToAddress == address(0) || to == requiredToAddress, "requiredToAddress Failure" );
        require( requiredTokenAddress == address(0) || tokenAddress == requiredTokenAddress, "requiredTokenAddress Failure"  );
        require( requiredTokenAmount == 0 || tokenAmount == requiredTokenAmount, "requiredTokenAmount Failure"  );
        require( requiredPeriodSeconds == 0 || periodSeconds == requiredPeriodSeconds, "requiredPeriodSeconds Failure"  );
        require( requiredGasPrice == 0 || gasPrice == requiredGasPrice, "requiredGasPrice Failure"  );

        return keccak256(
            abi.encodePacked(
                byte(0x19),
                byte(0),
                address(this),
                from,
                to,
                tokenAddress,
                tokenAmount,
                periodSeconds,
                gasPrice,
                nonce
        ));
    }

    //ecrecover the signer from hash and the signature
    function isValidSignature(
        address from, //the subscriber
        bytes32 subscriptionHash, //hash of subscription
        bytes signature //proof the subscriber signed the meta trasaction
    )
        public
        view 
        returns (bool)
    {
        return (
          presigned[subscriptionHash] ||
          from == subscriptionHash.toEthSignedMessageHash().recover(signature)
        );
    }

    //check if a subscription is signed correctly and the timestamp is ready for
    // the next execution to happen
    function isSubscriptionReady(
        address from, //the subscriber
        address to, //the publisher
        address tokenAddress, //the token address paid to the publisher
        uint256 tokenAmount, //the token amount paid to the publisher
        uint256 periodSeconds, //the period in seconds between payments
        uint256 gasPrice, //the amount of the token to incentivize the relay network
        uint256 nonce,// to allow multiple subscriptions with the same parameters
        bytes signature //proof the subscriber signed the meta trasaction
    )
        public
        view
        returns (bool)
    {
        bytes32 subscriptionHash = getSubscriptionHash(
            from, to, tokenAddress, tokenAmount, periodSeconds, gasPrice, nonce
        );
        bool isValid = isValidSignature(from,subscriptionHash, signature);
        uint256 allowance = ERC20(tokenAddress).allowance(from, address(this));
        uint256 balance = ERC20(tokenAddress).balanceOf(from);
        return (
            isValid &&
            from != to &&
            block.timestamp >= nextValidTimestamp[subscriptionHash] &&
            allowance >= tokenAmount.add(gasPrice) &&
            balance >= tokenAmount.add(gasPrice) &&
            nonce >= extraNonce[from]
        );
    }

    // you don't really need this if you are using the approve/transferFrom method
    // because you control the flow of tokens by approving this contract address,
    // but to make the contract an extensible example for later user I'll add this
    function cancelSubscription(
        address from, //the subscriber
        address to, //the publisher
        address tokenAddress, //the token address paid to the publisher
        uint256 tokenAmount, //the token amount paid to the publisher
        uint256 periodSeconds, //the period in seconds between payments
        uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
        uint256 nonce, //to allow multiple subscriptions with the same parameters
        bytes signature //proof the subscriber signed the meta trasaction
    )
        public
        returns (bool success)
    {
        updateMaximums();
        bytes32 subscriptionHash = getSubscriptionHash(
            from, to, tokenAddress, tokenAmount, periodSeconds, gasPrice, nonce
        );
        address signer = subscriptionHash.toEthSignedMessageHash().recover(signature);

        //the signature must be valid
        require(signer == from, "Invalid Signature for subscription cancellation");

        //make sure it's the subscriber
        require(from == msg.sender, 'msg.sender is not the subscriber');


        //nextValidTimestamp should be a timestamp that will never
        //be reached during the brief window human existence
        nextValidTimestamp[subscriptionHash]=uint256(-1);

        emit CancelSubscription(
            from, to, tokenAddress, tokenAmount, periodSeconds, gasPrice, nonce
        );

        return true;
    }

    // execute the transferFrom to pay the publisher from the subscriber
    // the subscriber has full control by approving this contract an allowance
    function executeSubscription(
        address from, //the subscriber
        address to, //the publisher
        address tokenAddress, //the token address paid to the publisher
        uint256 tokenAmount, //the token amount paid to the publisher
        uint256 periodSeconds, //the period in seconds between payments
        uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
        uint256 nonce, //to allow multiple subscriptions with the same parameters
        bytes signature //proof the subscriber signed the meta trasaction
    )
        public
        returns (bool success)
    {
        updateMaximums();
        updateUser(from);

        bytes32 subscriptionHash = getSubscriptionHash(
            from, to, tokenAddress, tokenAmount, periodSeconds, gasPrice, nonce
        );

        // make sure the subscription is valid and ready
        require(isSubscriptionReady(from, to, tokenAddress, tokenAmount, periodSeconds, gasPrice, nonce, signature), "Subscription is not ready or conditions of transction are not met");

        //check to see if this nonce is larger than the current count and we'll set that for this 'from'
        if(nonce > extraNonce[from]){
          extraNonce[from] = nonce;
        }

        // if there is an active subscription, update the maximum expiration for it
        expirations[expirationTimestamp(nextValidTimestamp[subscriptionHash])] -= users[from].checkpoints.getValueAt(block.number);
        nextValidTimestamp[subscriptionHash] = block.timestamp.add(periodSeconds);
        expirations[expirationTimestamp(nextValidTimestamp[subscriptionHash])] += tokenAmount;
        if(users[from].checkpoints.getValueAt(block.number)!=tokenAmount){
          maximumSubscriptions.insert(block.number,maximumSubscriptions.getValueAt(block.number)+tokenAmount);
          users[from].activeSubscription=subscriptionHash;
        }
        users[from].checkpoints.insert(block.number,tokenAmount);

        // now, let make the transfer from the subscriber to the publisher
        uint256 startingBalance = ERC20(tokenAddress).balanceOf(to);
        require(
          ERC20(tokenAddress).transferFrom(from,to,tokenAmount),
          "Transfer Failed"
        );
        require(
          (startingBalance+tokenAmount) == ERC20(tokenAddress).balanceOf(to),
          "ERC20 Balance did not change correctly"
        );

        emit ExecuteSubscription(
            from, to, tokenAddress, tokenAmount, periodSeconds, gasPrice, nonce
        );

        // it is possible for the subscription execution to be run by a third party
        // incentivized in the terms of the subscription with a gasPrice of the tokens
        //  - pay that out now...
        if (gasPrice > 0) {
            //the relayer is incentivized by a little of the same token from
            // the subscriber ... as far as the subscriber knows, they are
            // just sending X tokens to the publisher, but the publisher can
            // choose to send Y of those X to a relayer to run their transactions
            // the publisher will receive X - Y tokens
            // this must all be setup in the constructor
            // if not, the subscriber chooses all the params including what goes
            // to the publisher and what goes to the relayer

            require(
                ERC20(tokenAddress).transferFrom(from, msg.sender, gasPrice),
                "Failed to pay gas as from account"
            );
        }

        return true;
    }

    function updateMaximums() internal {
        uint expirationCount = 0;
        while(lastUpdate + gracePeriodSeconds <= block.timestamp){
            lastUpdate = lastUpdate + gracePeriodSeconds;
            expirationCount += expirations[lastUpdate];
        }
        if(expirationCount > 0){
            maximumSubscriptions.insert(block.number,
                                        maximumSubscriptions.getValueAt(block.number)-expirationCount);
            blockNumbers.insert(lastUpdate,block.number);// TODO: should this be block.timestamp?
        }
    }


    function updateUser(address account) internal {
        // no update if the user has no expired subscription
        if(expirationTimestamp(nextValidTimestamp[users[account].activeSubscription]) > block.timestamp ||
           users[account].checkpoints.getValueAt(block.number) == 0){
            return;
        }

        // if it expired do the best you can without shorting them
        users[account].checkpoints.insert(blockNumbers.getValueAfter(nextValidTimestamp[users[account].activeSubscription]),0);

    }

    function expirationTimestamp(uint timestamp) internal view returns (uint){
        if(timestamp%gracePeriodSeconds == 0) return timestamp;
        return timestamp - (timestamp%gracePeriodSeconds) + gracePeriodSeconds;
        
    }

    function balanceOf(address account) public returns(uint supply){
        supply = balanceOfAt(account,block.number);
    }

    function totalSupply() public returns(uint supply){
        return totalSupplyAt(block.number);
    }

    function totalSupplyAt(uint snapshotBlock) public returns(uint supply){
        updateMaximums();
        return maximumSubscriptions.getValueAt(snapshotBlock);
    }

    function balanceOfAt(address account, uint snapshotBlock) public returns(uint supply){
        updateMaximums();
        updateUser(account);
        return users[account].checkpoints.getValueAt(snapshotBlock);
    }

}
