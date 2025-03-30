// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/chainlink/PriceFeedConsumer.sol";

contract DeployPriceFeedConsumer is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy PriceFeedConsumer
        PriceFeedConsumer priceFeedConsumer = new PriceFeedConsumer();

        console.log("PriceFeedConsumer deployed at: ", address(priceFeedConsumer));

        vm.stopBroadcast();
    }
}