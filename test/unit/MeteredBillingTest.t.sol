// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/billing/MeteredBilling.sol";
import "../../src/core/SubscriptionManager.sol";
import "../../src/mock/MockERC20.sol";

contract MeteredBillingTest is Test {
    MeteredBilling public meteredBilling;
    SubscriptionManager public subscriptionManager;
    MockERC20 public paymentToken;
    address public treasury;
    address public user1;
    address public provider;
    uint256 public serviceId;
    uint256 public planId;

    function setUp() public {
        // Deploy mock payment token
        paymentToken = new MockERC20("USD Coin", "USDC", 6);
        
        // Setup treasury and other addresses
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        provider = makeAddr("provider");
        
        // Mint tokens to users
        paymentToken.mint(user1, 1000 * 10**6); // 1000 USDC
        
        // Deploy SubscriptionManager
        subscriptionManager = new SubscriptionManager(
            paymentToken,
            treasury,
            7 days // 7 days grace period
        );
        
        // Create a subscription plan
        string[] memory features = new string[](1);
        features[0] = "API Access";
        
        planId = subscriptionManager.createPlan(
            "API Plan",
            10 * 10**6, // 10 USDC
            30 days,    // 30 days duration
            features
        );
        
        // Deploy MeteredBilling
        meteredBilling = new MeteredBilling(
            address(subscriptionManager),
            paymentToken,
            treasury,
            30 days // 30 days billing cycle
        );
        
        // Register a metered service
        serviceId = meteredBilling.registerService(
            "API Calls",
            provider,
            100000, // 0.1 USDC per unit (with 6 decimals)
            10,     // Min 10 units
            1000    // Max 1000 units
        );
        
        // Subscribe user to the plan
        vm.startPrank(user1);
        paymentToken.approve(address(subscriptionManager), 10 * 10**6);
        subscriptionManager.subscribe(planId, true);
        
        // Approve payment token for metered billing
        paymentToken.approve(address(meteredBilling), 100 * 10**6); // 100 USDC
        vm.stopPrank();
    }

    function testRegisterService() public {
        // Create a new service
        uint256 newServiceId = meteredBilling.registerService(
            "Data Storage",
            provider,
            500000, // 0.5 USDC per unit
            5,      // Min 5 units
            500 // Max 500 units
        );
        
        assertEq(newServiceId, 2, "Service ID should be 2");
        
        // Verify service details
        (
            string memory name,
            address serviceProvider,
            uint256 ratePerUnit,
            uint256 minUsage,
            uint256 maxUsage,
            bool active
        ) = meteredBilling.services(newServiceId);
        
        assertEq(name, "Data Storage", "Service name should match");
        assertEq(serviceProvider, provider, "Provider should match");
        assertEq(ratePerUnit, 500000, "Rate should match");
        assertEq(minUsage, 5, "Min usage should match");
        assertEq(maxUsage, 500, "Max usage should match");
        assertTrue(active, "Service should be active");
    }

    function testRecordUsage() public {
        // Set provider as recorder
        meteredBilling.setUsageRecorder(provider, true);
        
        // Record usage for user
        vm.prank(provider);
        meteredBilling.recordUsage(user1, serviceId, 50);
        
        // Check usage was recorded
        MeteredBilling.UserUsage memory usage = meteredBilling.getUserUsage(user1, serviceId);
        assertEq(usage.totalUsage, 50, "Total usage should be 50");
        assertEq(usage.billedUsage, 0, "Billed usage should be 0");
        assertTrue(usage.lastRecordTime > 0, "Last record time should be set");
    }

    function testBatchRecordUsage() public {
        // Setup multiple users
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        
        // Subscribe users to the plan
        vm.startPrank(user2);
        paymentToken.mint(user2, 1000 * 10**6);
        paymentToken.approve(address(subscriptionManager), 10 * 10**6);
        subscriptionManager.subscribe(planId, true);
        vm.stopPrank();
        
        vm.startPrank(user3);
        paymentToken.mint(user3, 1000 * 10**6);
        paymentToken.approve(address(subscriptionManager), 10 * 10**6);
        subscriptionManager.subscribe(planId, true);
        vm.stopPrank();
        
        // Set provider as recorder
        meteredBilling.setUsageRecorder(provider, true);
        
        // Prepare batch data
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10;
        amounts[1] = 20;
        amounts[2] = 30;
        
        // Record batch usage
        vm.prank(provider);
        meteredBilling.batchRecordUsage(users, serviceId, amounts);
        
        // Check usage was recorded for each user
        MeteredBilling.UserUsage memory usage1 = meteredBilling.getUserUsage(user1, serviceId);
        MeteredBilling.UserUsage memory usage2 = meteredBilling.getUserUsage(user2, serviceId);
        MeteredBilling.UserUsage memory usage3 = meteredBilling.getUserUsage(user3, serviceId);
        
        assertEq(usage1.totalUsage, 10, "User1 total usage should be 10");
        assertEq(usage2.totalUsage, 20, "User2 total usage should be 20");
        assertEq(usage3.totalUsage, 30, "User3 total usage should be 30");
    }

    function testSettleBillingCycle() public {
        // Record usage
        vm.startPrank(provider);
        meteredBilling.setUsageRecorder(provider, true);
        meteredBilling.recordUsage(user1, serviceId, 50);
        
        // Settle billing cycle
        uint256 billingAmount = meteredBilling.settleBillingCycle(user1, serviceId);
        vm.stopPrank();
        
        // Check results
        assertEq(billingAmount, 50 * 100000, "Billing amount should be 5 USDC (50 units * 0.1 USDC)");
        
        // Check user's billed usage is updated
        MeteredBilling.UserUsage memory usage = meteredBilling.getUserUsage(user1, serviceId);
        assertEq(usage.billedUsage, 50, "Billed usage should be 50");
        
        // Check treasury received payment
        uint256 expectedPayment = 5 * 10**6; // 5 USDC
        assertApproxEqAbs(paymentToken.balanceOf(treasury), 10 * 10**6 + expectedPayment, 100, "Treasury should have received payment");
    }

    function testSettleBillingCycleWithMinimumUsage() public {
        // Record usage below minimum
        vm.startPrank(provider);
        meteredBilling.setUsageRecorder(provider, true);
        meteredBilling.recordUsage(user1, serviceId, 5); // Below minimum of 10
        
        // Settle billing cycle
        uint256 billingAmount = meteredBilling.settleBillingCycle(user1, serviceId);
        vm.stopPrank();
        
        // Check minimum usage was applied
        assertEq(billingAmount, 10 * 100000, "Billing amount should be 1 USDC (min 10 units * 0.1 USDC)");
    }

    function testSettleBillingCycleWithMaximumUsage() public {
        // Record usage above maximum
        vm.startPrank(provider);
        meteredBilling.setUsageRecorder(provider, true);
        meteredBilling.recordUsage(user1, serviceId, 1500); // Above maximum of 1000
        
        // Settle billing cycle
        uint256 billingAmount = meteredBilling.settleBillingCycle(user1, serviceId);
        vm.stopPrank();
        
        // Check maximum usage was applied
        assertEq(billingAmount, 1000 * 100000, "Billing amount should be 100 USDC (max 1000 units * 0.1 USDC)");
    }

    function testBatchSettleBillingCycles() public {
        // Setup multiple users with usage
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        
        // Subscribe users to the plan and record usage
        vm.startPrank(user2);
        paymentToken.mint(user2, 1000 * 10**6);
        paymentToken.approve(address(subscriptionManager), 10 * 10**6);
        subscriptionManager.subscribe(planId, true);
        paymentToken.approve(address(meteredBilling), 100 * 10**6);
        vm.stopPrank();
        
        vm.startPrank(user3);
        paymentToken.mint(user3, 1000 * 10**6);
        paymentToken.approve(address(subscriptionManager), 10 * 10**6);
        subscriptionManager.subscribe(planId, true);
        paymentToken.approve(address(meteredBilling), 100 * 10**6);
        vm.stopPrank();
        
        // Record usage for all users
        vm.startPrank(provider);
        meteredBilling.setUsageRecorder(provider, true);
        meteredBilling.recordUsage(user1, serviceId, 30);
        meteredBilling.recordUsage(user2, serviceId, 50);
        meteredBilling.recordUsage(user3, serviceId, 70);
        
        // Prepare batch data
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        // Batch settle billing cycles
        (uint256 successCount, uint256 totalBilled) = meteredBilling.batchSettleBillingCycles(users, serviceId);
        vm.stopPrank();
        
        // Check results
        assertEq(successCount, 3, "All 3 settlements should succeed");
        assertEq(totalBilled, (30 + 50 + 70) * 100000, "Total billing amount should be sum of all users' usage");
    }

    function testCalculateCurrentBilling() public {
        // Record usage
        vm.prank(provider);
        meteredBilling.recordUsage(user1, serviceId, 75);
        
        // Calculate current billing
        (uint256 billableUsage, uint256 billingAmount) = meteredBilling.calculateCurrentBilling(user1, serviceId);
        
        // Check calculation
        assertEq(billableUsage, 75, "Billable usage should be 75");
        assertEq(billingAmount, 75 * 100000, "Billing amount should be 7.5 USDC");
    }

    function testTimeUntilNextBillingCycle() public {
        // Record usage to start billing cycle
        vm.prank(provider);
        meteredBilling.recordUsage(user1, serviceId, 50);
        
        // Get user usage to get the billing cycle end time
        MeteredBilling.UserUsage memory usage = meteredBilling.getUserUsage(user1, serviceId);
        uint256 cycleEndTime = usage.billingCycleEnd;
        
        // Fast forward to halfway through billing cycle
        vm.warp(block.timestamp + 15 days);
        
        // Check time until next billing cycle
        uint256 timeRemaining = meteredBilling.getTimeUntilNextBillingCycle(user1, serviceId);
        assertApproxEqAbs(timeRemaining, 15 days, 10, "Time remaining should be about 15 days");
    }

    function testPauseAndUnpause() public {
        // Pause the contract
        meteredBilling.pause();
        
        // Try to record usage
        vm.prank(provider);
        vm.expectRevert("Pausable: paused");
        meteredBilling.recordUsage(user1, serviceId, 50);
        
        // Unpause and try again
        meteredBilling.unpause();
        vm.prank(provider);
        meteredBilling.recordUsage(user1, serviceId, 50);
        
        // Check usage was recorded
        MeteredBilling.UserUsage memory usage = meteredBilling.getUserUsage(user1, serviceId);
        assertEq(usage.totalUsage, 50, "Total usage should be 50");
    }
}