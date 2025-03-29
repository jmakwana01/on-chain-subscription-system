// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "../src/core/SubscriptionManager.sol";
import "../src/chainlink/PriceFeedConsumer.sol";
import "../src/core/SubscriptionKeeper.sol";
import "../src/core/MeteredBilling.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeploySubscriptionSystem
 * @notice Deploys all contracts for the subscription system
 * @dev Run with: forge script script/DeploySubscriptionSystem.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
 */
contract DeploySubscriptionSystem is Script {
    // Contract instances
    SubscriptionManager public subscriptionManager;
    PriceFeedConsumer public priceFeedConsumer;
    SubscriptionKeeper public subscriptionKeeper;
    MeteredBilling public meteredBilling;

    // Configuration parameters
    address public treasury;
    address public paymentToken;
    address public linkToken;
    address public chainlinkRouter;
    uint256 public gracePeriod = 7 days; // 7 days grace period
    uint256 public renewalAttemptInterval = 1 days; // 1 day between renewal attempts
    uint256 public billingCycleDuration = 30 days; // 30 days billing cycle

    /**
     * @notice Run the deployment script
     */
    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Load configuration from environment or use defaults
        treasury = vm.envOr("TREASURY_ADDRESS", address(0x1234567890123456789012345678901234567890));
        paymentToken = vm.envOr("PAYMENT_TOKEN_ADDRESS", address(0x2345678901234567890123456789012345678901));
        linkToken = vm.envOr("LINK_TOKEN_ADDRESS", address(0x3456789012345678901234567890123456789012));
        chainlinkRouter = vm.envOr("CHAINLINK_ROUTER_ADDRESS", address(0x4567890123456789012345678901234567890123));

        console.log("Deploying with parameters:");
        console.log("Treasury:", treasury);
        console.log("Payment Token:", paymentToken);
        console.log("LINK Token:", linkToken);
        console.log("Chainlink Router:", chainlinkRouter);

        // 1. Deploy SubscriptionManager
        console.log("Deploying SubscriptionManager...");
        subscriptionManager = new SubscriptionManager(
            IERC20(paymentToken),
            treasury,
            gracePeriod
        );
        console.log("SubscriptionManager deployed at:", address(subscriptionManager));

        // 2. Deploy PriceFeedConsumer
        console.log("Deploying PriceFeedConsumer...");
        priceFeedConsumer = new PriceFeedConsumer();
        console.log("PriceFeedConsumer deployed at:", address(priceFeedConsumer));

        // 3. Deploy SubscriptionKeeper
        console.log("Deploying SubscriptionKeeper...");
        subscriptionKeeper = new SubscriptionKeeper(
            address(subscriptionManager),
            renewalAttemptInterval
        );
        console.log("SubscriptionKeeper deployed at:", address(subscriptionKeeper));

        // 4. Deploy MeteredBilling
        console.log("Deploying MeteredBilling...");
        meteredBilling = new MeteredBilling(
            address(subscriptionManager),
            IERC20(paymentToken),
            treasury,
            billingCycleDuration
        );
        console.log("MeteredBilling deployed at:", address(meteredBilling));

        // Configure initial subscription plans
        console.log("Creating initial subscription plans...");
        
        // Create Basic Plan
        string[] memory basicFeatures = new string[](3);
        basicFeatures[0] = "Access to basic API endpoints";
        basicFeatures[1] = "5 requests per minute rate limit";
        basicFeatures[2] = "Standard support";
        uint256 basicPlanId = subscriptionManager.createPlan(
            "Basic Plan",
            10 * 10**18, // 10 tokens (assuming 18 decimals)
            30 days,
            basicFeatures
        );
        console.log("Basic Plan created with ID:", basicPlanId);
        
        // Create Pro Plan
        string[] memory proFeatures = new string[](5);
        proFeatures[0] = "Access to all API endpoints";
        proFeatures[1] = "50 requests per minute rate limit";
        proFeatures[2] = "Priority support";
        proFeatures[3] = "Advanced analytics";
        proFeatures[4] = "Custom integrations";
        uint256 proPlanId = subscriptionManager.createPlan(
            "Pro Plan",
            50 * 10**18, // 50 tokens
            30 days,
            proFeatures
        );
        console.log("Pro Plan created with ID:", proPlanId);
        
        // Create Enterprise Plan
        string[] memory enterpriseFeatures = new string[](6);
        enterpriseFeatures[0] = "Unlimited API access";
        enterpriseFeatures[1] = "200 requests per minute rate limit";
        enterpriseFeatures[2] = "24/7 dedicated support";
        enterpriseFeatures[3] = "Advanced analytics and reporting";
        enterpriseFeatures[4] = "Custom integrations and solutions";
        enterpriseFeatures[5] = "Dedicated infrastructure";
        uint256 enterprisePlanId = subscriptionManager.createPlan(
            "Enterprise Plan",
            200 * 10**18, // 200 tokens
            30 days,
            enterpriseFeatures
        );
        console.log("Enterprise Plan created with ID:", enterprisePlanId);

        // Register metered services
        console.log("Creating initial metered services...");
        
        // API Calls Service
        uint256 apiServiceId = meteredBilling.registerService(
            "API Calls",
            treasury, // Provider is treasury for now
            0.001 * 10**18, // 0.001 tokens per API call
            100, // Minimum 100 calls per billing cycle
            1000000, // Maximum 1,000,000 calls per billing cycle
            true // Active
        );
        console.log("API Calls service created with ID:", apiServiceId);
        
        // Data Storage Service
        uint256 storageServiceId = meteredBilling.registerService(
            "Data Storage",
            treasury, // Provider is treasury for now
            0.01 * 10**18, // 0.01 tokens per GB stored
            1, // Minimum 1 GB
            10000, // Maximum 10,000 GB
            true // Active
        );
        console.log("Data Storage service created with ID:", storageServiceId);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Output deployment summary
        console.log("\nDeployment Summary:");
        console.log("==================");
        console.log("SubscriptionManager:", address(subscriptionManager));
        console.log("PriceFeedConsumer:", address(priceFeedConsumer));
        console.log("SubscriptionKeeper:", address(subscriptionKeeper));
        console.log("MeteredBilling:", address(meteredBilling));
        console.log("\nPlans Created:");
        console.log("Basic Plan ID:", basicPlanId);
        console.log("Pro Plan ID:", proPlanId);
        console.log("Enterprise Plan ID:", enterprisePlanId);
        console.log("\nMetered Services Created:");
        console.log("API Calls Service ID:", apiServiceId);
        console.log("Data Storage Service ID:", storageServiceId);
    }
}