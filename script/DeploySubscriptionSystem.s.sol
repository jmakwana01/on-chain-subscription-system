// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/core/SubscriptionManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeploySubscriptionManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address paymentTokenAddress = vm.envAddress("PAYMENT_TOKEN_ADDRESS");
        address treasuryAddress = vm.envAddress("TREASURY_ADDRESS");
        uint256 gracePeriod = 7 days; // 7 days grace period

        vm.startBroadcast(deployerPrivateKey);

        // Deploy SubscriptionManager
        SubscriptionManager subscriptionManager = new SubscriptionManager(
            IERC20(paymentTokenAddress),
            treasuryAddress,
            gracePeriod
        );

        console.log("SubscriptionManager deployed at: ", address(subscriptionManager));

        vm.stopBroadcast();
    }
}