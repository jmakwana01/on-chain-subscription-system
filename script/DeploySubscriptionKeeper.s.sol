// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/chainlink/SubscriptionKeeper.sol";

contract DeploySubscriptionKeeper is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address subscriptionManagerAddress = vm.envAddress("SUBSCRIPTION_MANAGER_ADDRESS");
        uint256 renewalAttemptInterval = 1 days; // 1 day between renewal attempts

        vm.startBroadcast(deployerPrivateKey);

        // Deploy SubscriptionKeeper
        SubscriptionKeeper subscriptionKeeper = new SubscriptionKeeper(
            subscriptionManagerAddress,
            renewalAttemptInterval
        );

        console.log("SubscriptionKeeper deployed at: ", address(subscriptionKeeper));

        vm.stopBroadcast();
    }
}