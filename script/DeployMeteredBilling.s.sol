// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/billing/MeteredBilling.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployMeteredBilling is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address subscriptionManagerAddress = vm.envAddress("SUBSCRIPTION_MANAGER_ADDRESS");
        address paymentTokenAddress = vm.envAddress("PAYMENT_TOKEN_ADDRESS");
        address treasuryAddress = vm.envAddress("TREASURY_ADDRESS");
        uint256 billingCycleDuration = 30 days; // 30 days billing cycle

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MeteredBilling
        MeteredBilling meteredBilling = new MeteredBilling(
            subscriptionManagerAddress,
            IERC20(paymentTokenAddress),
            treasuryAddress,
            billingCycleDuration
        );

        console.log("MeteredBilling deployed at: ", address(meteredBilling));

        vm.stopBroadcast();
    }
}