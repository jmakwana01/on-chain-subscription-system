// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/core/SubscriptionManager.sol";
import "../../src/billing/MeteredBilling.sol";
import "../../src/chainlink/SubscriptionKeeper.sol";
import "../../src/chainlink/PriceFeedConsumer.sol";
import "../../src/bridge/CrossChainSubscriptionBridge.sol";
import "../../src/mock/MockERC20.sol";
import "../../src/mock/MockV3Aggregator.sol";
import "../../src/mock/MockCCIPRouter.sol";

contract SubscriptionSystemIntegrationTest is Test {
    // Core contracts
    SubscriptionManager public subscriptionManager;
    MeteredBilling public meteredBilling;
    SubscriptionKeeper public subscriptionKeeper;
    PriceFeedConsumer public priceFeedConsumer;
    CrossChainSubscriptionBridge public sourceBridge;
    CrossChainSubscriptionBridge public destinationBridge;
    
    // Mock contracts
    MockERC20 public paymentToken;
    MockERC20 public linkToken;
    MockV3Aggregator public tokenUsdPriceFeed;
    MockCCIPRouter public sourceRouter;
    MockCCIPRouter public destinationRouter;
    
    // Test parameters
    address public treasury;
    address public serviceProvider;
    address public user1;
    address public user2;
    
    // Chain selectors for cross-chain testing
    uint64 public constant SOURCE_CHAIN_SELECTOR = 1;
    uint64 public constant DESTINATION_CHAIN_SELECTOR = 2;
    
    function setUp() public {
        // Setup addresses
        treasury = makeAddr("treasury");
        serviceProvider = makeAddr("serviceProvider");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy mock tokens
        paymentToken = new MockERC20("USD Coin", "USDC", 6);
        linkToken = new MockERC20("Chainlink Token", "LINK", 18);
        
        // Mint tokens to users
        paymentToken.mint(user1, 10000 * 10**6);  // 10,000 USDC
        paymentToken.mint(user2, 10000 * 10**6);  // 10,000 USDC
        linkToken.mint(address(this), 1000 * 10**18); // 1,000 LINK
        
        // Deploy mock price feed
        tokenUsdPriceFeed = new MockV3Aggregator(8, 1 * 10**8); // $1 USD with 8 decimals
        
        // Deploy core subscription manager
        subscriptionManager = new SubscriptionManager(
            paymentToken,
            treasury,
            7 days // 7 days grace period
        );
        
        // Deploy metered billing
        meteredBilling = new MeteredBilling(
            address(subscriptionManager),
            paymentToken,
            treasury,
            30 days // 30 days billing cycle
        );
        
        // Deploy subscription keeper
        subscriptionKeeper = new SubscriptionKeeper(
            address(subscriptionManager),
            1 days // 1 day between renewal attempts
        );
        
        // Deploy price feed consumer
        priceFeedConsumer = new PriceFeedConsumer();
        priceFeedConsumer.setPriceFeed(address(paymentToken), address(tokenUsdPriceFeed));
        
        // Deploy mock CCIP routers for cross-chain testing
        sourceRouter = new MockCCIPRouter();
        destinationRouter = new MockCCIPRouter();
        
        // Deploy cross-chain bridges
        sourceBridge = new CrossChainSubscriptionBridge(
            address(subscriptionManager),
            address(sourceRouter),
            address(linkToken)
        );
        
        // Deploy a second subscription manager for destination chain
        SubscriptionManager destinationManager = new SubscriptionManager(
            paymentToken,
            treasury,
            7 days
        );
        
        destinationBridge = new CrossChainSubscriptionBridge(
            address(destinationManager),
            address(destinationRouter),
            address(linkToken)
        );
        
        // Setup cross-chain bridges to trust each other
        sourceBridge.setRemoteBridge(DESTINATION_CHAIN_SELECTOR, address(destinationBridge), true);
        destinationBridge.setRemoteBridge(SOURCE_CHAIN_SELECTOR, address(sourceBridge), true);
        
        // Fund bridges with LINK tokens
        linkToken.transfer(address(sourceBridge), 100 * 10**18);
        linkToken.transfer(address(destinationBridge), 100 * 10**18);
        
        // Configure mock routers to simulate cross-chain messaging
        sourceRouter.setRemoteRouter(DESTINATION_CHAIN_SELECTOR, address(destinationRouter));
        destinationRouter.setRemoteRouter(SOURCE_CHAIN_SELECTOR, address(sourceRouter));
    }

    function testEndToEndSubscriptionFlow() public {
        // 1. Create subscription plans
        string[] memory basicFeatures = new string[](2);
        basicFeatures[0] = "Limited API Access";
        basicFeatures[1] = "Email Support";
        
        string[] memory proFeatures = new string[](3);
        proFeatures[0] = "Unlimited API Access";
        proFeatures[1] = "Premium Support";
        proFeatures[2] = "Advanced Analytics";
        
        uint256 basicPlanId = subscriptionManager.createPlan(
            "Basic Plan",
            10 * 10**6, // 10 USDC
            30 days,
            basicFeatures
        );
        
        uint256 proPlanId = subscriptionManager.createPlan(
            "Pro Plan",
            50 * 10**6, // 50 USDC
            30 days,
            proFeatures
        );
        
        // 2. Register a metered service
        uint256 apiServiceId = meteredBilling.registerService(
            "API Calls",
            serviceProvider,
            50000, // 0.05 USDC per call
            10,    // Minimum 10 calls
            10000  // Maximum 10,000 calls
        );
        
        // 3. User subscribes to Basic Plan
        vm.startPrank(user1);
        paymentToken.approve(address(subscriptionManager), 100 * 10**6); // Approve for multiple payments
        subscriptionManager.subscribe(basicPlanId, true);
        vm.stopPrank();
        
        // 4. User approves tokens for metered billing
        vm.startPrank(user1);
        paymentToken.approve(address(meteredBilling), 100 * 10**6);
        vm.stopPrank();
        
        // 5. Service provider records usage
        meteredBilling.setUsageRecorder(serviceProvider, true);
        vm.startPrank(serviceProvider);
        meteredBilling.recordUsage(user1, apiServiceId, 100); // 100 API calls
        vm.stopPrank();
        
        // 6. Calculate current billing
        (uint256 billableUsage, uint256 billingAmount) = meteredBilling.calculateCurrentBilling(user1, apiServiceId);
        assertEq(billableUsage, 100, "Billable usage should be 100");
        assertEq(billingAmount, 100 * 50000, "Billing amount should be 5 USDC");
        
        // 7. Settle billing cycle
        vm.startPrank(serviceProvider);
        uint256 settledAmount = meteredBilling.settleBillingCycle(user1, apiServiceId);
        vm.stopPrank();
        
        assertEq(settledAmount, 100 * 50000, "Settled amount should be 5 USDC");
        
        // 8. Check treasury balance
        uint256 expectedTreasuryBalance = 10 * 10**6 + 5 * 10**6; // 10 USDC for subscription + 5 USDC for usage
        assertEq(paymentToken.balanceOf(treasury), expectedTreasuryBalance, "Treasury balance incorrect");
        
        // 9. Test subscription renewal via keeper
        // Register user with keeper
        subscriptionKeeper.addSubscribers(toArray(user1));
        
        // Fast forward to near end of subscription
        vm.warp(block.timestamp + 29 days);
        
        // Check upkeep should not be needed yet
        (bool upkeepNeeded, ) = subscriptionKeeper.checkUpkeep("");
        assertFalse(upkeepNeeded, "Upkeep should not be needed before subscription expires");
        
        // Fast forward past subscription end
        vm.warp(block.timestamp + 2 days);
        
        // Check upkeep should be needed now
        bytes memory performData;
        (upkeepNeeded, performData) = subscriptionKeeper.checkUpkeep("");
        assertTrue(upkeepNeeded, "Upkeep should be needed after subscription expires");
        
        // Perform upkeep
        subscriptionKeeper.performUpkeep(performData);
        
        // Check subscription was renewed
        assertTrue(subscriptionManager.isSubscribed(user1, basicPlanId), "Subscription should be renewed");
        
        // 10. Test upgrading subscription
        vm.startPrank(user1);
        paymentToken.approve(address(subscriptionManager), 50 * 10**6);
        subscriptionManager.subscribe(proPlanId, true);
        vm.stopPrank();
        
        assertTrue(subscriptionManager.isSubscribed(user1, proPlanId), "User should be subscribed to Pro plan");
        
        // 11. Test cross-chain subscription validation
        // Request validation from destination chain
        vm.prank(address(this));
        bytes32 messageId = sourceBridge.requestCrossChainValidation(
            DESTINATION_CHAIN_SELECTOR,
            user1,
            basicPlanId
        );
        
        // Check if cross-chain subscription is recognized
        bool hasSubscription = destinationBridge.hasCrossChainSubscription(user1, basicPlanId);
        assertTrue(hasSubscription, "User should have cross-chain subscription");
    }
    
    function testSubscriptionWithPriceConversion() public {
        // Create a subscription plan with price in USD
        string[] memory features = new string[](1);
        features[0] = "Full Access";
        
        uint256 planId = subscriptionManager.createPlan(
            "USD Plan",
            20 * 10**6, // 20 USDC
            30 days,
            features
        );
        
        // Get current USD price of token
        int256 tokenPrice = priceFeedConsumer.getLatestPrice(address(paymentToken));
        assertEq(tokenPrice, 1 * 10**8, "Token price should be $1");
        
        // Convert 20 USD to token amount
        uint256 tokenAmount = priceFeedConsumer.convertFromUSD(
            address(paymentToken),
            20 * 10**8, // 20 USD with 8 decimals
            6          // USDC has 6 decimals
        );
        
        assertEq(tokenAmount, 20 * 10**6, "Token amount should be 20 USDC");
        
        // User subscribes with the calculated token amount
        vm.startPrank(user1);
        paymentToken.approve(address(subscriptionManager), tokenAmount);
        subscriptionManager.subscribe(planId, true);
        vm.stopPrank();
        
        assertTrue(subscriptionManager.isSubscribed(user1, planId), "User should be subscribed");
    }
    
    function testCrossChainSubscriptionManager() public {
        // Setup: Create a plan on the source chain
        string[] memory features = new string[](1);
        features[0] = "Cross-Chain Access";
        
        uint256 planId = subscriptionManager.createPlan(
            "Cross-Chain Plan",
            30 * 10**6, // 30 USDC
            30 days,
            features
        );
        
        // User subscribes on the source chain
        vm.startPrank(user1);
        paymentToken.approve(address(subscriptionManager), 30 * 10**6);
        subscriptionManager.subscribe(planId, true);
        vm.stopPrank();
        
        // Request cross-chain validation
        bytes32 messageId = sourceBridge.requestCrossChainValidation(
            DESTINATION_CHAIN_SELECTOR,
            user1,
            planId
        );
        
        // Verify the message was processed on the destination chain
        bool hasSubscription = destinationBridge.hasCrossChainSubscription(user1, planId);
        assertTrue(hasSubscription, "User should have cross-chain subscription");
        
        // Cancel subscription on source chain
        vm.prank(user1);
        subscriptionManager.cancelSubscription(planId);
        
        // Send a status update to the destination chain
        sourceBridge.sendCrossChainStatusUpdate(
            DESTINATION_CHAIN_SELECTOR,
            user1,
            planId,
            false
        );
        
        // Verify the status was updated on the destination chain
        hasSubscription = destinationBridge.hasCrossChainSubscription(user1, planId);
        assertFalse(hasSubscription, "Cross-chain subscription should be canceled");
    }
    
    function testIntegratedMeteredBillingWithTiers() public {
        // 1. Create a subscription plan
        string[] memory features = new string[](1);
        features[0] = "API Access with Usage Tiers";
        
        uint256 planId = subscriptionManager.createPlan(
            "API Plan with Tiers",
            15 * 10**6, // 15 USDC base fee
            30 days,
            features
        );
        
        // 2. Register tiered metered services with different rates
        uint256 basicTierId = meteredBilling.registerService(
            "Basic API Calls",
            serviceProvider,
            100000, // 0.1 USDC per call
            0,      // No minimum
            1000    // Max 1000 calls
        );
        
        uint256 premiumTierId = meteredBilling.registerService(
            "Premium API Calls",
            serviceProvider,
            50000,  // 0.05 USDC per call for premium users
            0,      // No minimum
            10000  // Max 10,000 calls
        );
        
        // 3. User subscribes to plan
        vm.startPrank(user1);
        paymentToken.approve(address(subscriptionManager), 100 * 10**6);
        subscriptionManager.subscribe(planId, true);
        
        // 4. Approve metered billing payments
        paymentToken.approve(address(meteredBilling), 100 * 10**6);
        vm.stopPrank();
        
        // 5. Record usage in different tiers
        vm.startPrank(serviceProvider);
        meteredBilling.recordUsage(user1, basicTierId, 500);    // 500 basic API calls
        meteredBilling.recordUsage(user1, premiumTierId, 2000); // 2000 premium API calls
        vm.stopPrank();
        
        // 6. Settle both billing cycles
        vm.startPrank(serviceProvider);
        uint256 basicSettlement = meteredBilling.settleBillingCycle(user1, basicTierId);
        uint256 premiumSettlement = meteredBilling.settleBillingCycle(user1, premiumTierId);
        vm.stopPrank();
        
        // 7. Verify settlement amounts
        assertEq(basicSettlement, 500 * 100000, "Basic tier settlement should be 50 USDC");
        assertEq(premiumSettlement, 2000 * 50000, "Premium tier settlement should be 100 USDC");
        
        // 8. Check total payment to treasury
        // 15 USDC (subscription) + 50 USDC (basic tier) + 100 USDC (premium tier) = 165 USDC
        uint256 expectedTreasuryBalance = 15 * 10**6 + 50 * 10**6 + 100 * 10**6;
        assertEq(paymentToken.balanceOf(treasury), expectedTreasuryBalance, "Treasury balance incorrect");
    }
    
    // Helper function to convert a single address to an array
    function toArray(address addr) internal pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = addr;
        return array;
    }
}