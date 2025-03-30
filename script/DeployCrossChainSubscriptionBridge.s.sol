// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/bridge/CrossChainSubscriptionBridge.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployCrossChainSubscriptionBridge is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address subscriptionManagerAddress = vm.envAddress("SUBSCRIPTION_MANAGER_ADDRESS");
        address routerAddress = vm.envAddress("CCIP_ROUTER_ADDRESS");
        address linkTokenAddress = vm.envAddress("LINK_TOKEN_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy CrossChainSubscriptionBridge
        CrossChainSubscriptionBridge bridge = new CrossChainSubscriptionBridge(
            subscriptionManagerAddress,
            routerAddress,
            linkTokenAddress
        );

        console.log("CrossChainSubscriptionBridge deployed at: ", address(bridge));

        vm.stopBroadcast();
    }
}