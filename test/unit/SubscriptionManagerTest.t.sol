// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/core/SubscriptionManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/mock/MockERC20.sol";

contract SubscriptionManagerTest is Test {
    SubscriptionManager public subscriptionManager;
    MockERC20 public paymentToken;
    address public treasury;
    address public user1;
    address public user2;
    uint256 public gracePeriod;
    uint256 public planId;

    function setUp() public {
        // Deploy mock payment token
        paymentToken = new MockERC20("USD Coin", "USDC", 6);
        
        // Setup treasury
        treasury = makeAddr("treasury");
        
        // Setup test users
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Mint tokens to users
        paymentToken.mint(user1, 1000 * 10**6); // 1000 USDC
        paymentToken.mint(user2, 1000 * 10**6); // 1000 USDC
        
        // Set grace period (7 days)
        gracePeriod = 7 days;
        
        // Deploy SubscriptionManager
        subscriptionManager = new SubscriptionManager(
            IERC20(address(paymentToken)),
            treasury,
            gracePeriod
        );
        
        // Create a subscription plan
        string[] memory features = new string[](2);
        features[0] = "Feature 1";
        features[1] = "Feature 2";
        
        planId = subscriptionManager.createPlan(
            "Basic Plan",
            10 * 10**6, // 10 USDC
            30 days,    // 30 days duration
            features
        );
    }

    function testCreatePlan() public {
        string[] memory features = new string[](1);
        features[0] = "Premium Feature";
        
        uint256 newPlanId = subscriptionManager.createPlan(
            "Premium Plan",
            50 * 10**6, // 50 USDC
            30 days,    // 30 days duration
            features
        );
        
        assertEq(newPlanId, 2, "Plan ID should be 2");
        
        (string memory name, uint256 price, uint256 duration, bool active) = subscriptionManager.plans(newPlanId);
        
        assertEq(name, "Premium Plan", "Plan name should match");
        assertEq(price, 50 * 10**6, "Plan price should match");
        assertEq(duration, 30 days, "Plan duration should match");
        assertTrue(active, "Plan should be active");
    }

    function testSubscribe() public {
        // Approve tokens for subscription
        vm.startPrank(user1);
        paymentToken.approve(address(subscriptionManager), 10 * 10**6);
        
        // Subscribe to plan
        subscriptionManager.subscribe(planId, true);
        vm.stopPrank();
        
        // Check subscription status
        assertTrue(subscriptionManager.isSubscribed(user1, planId), "User should be subscribed");
        assertTrue(subscriptionManager.hasActiveSubscription(user1), "User should have active subscription");
        
        // Check treasury balance
        assertEq(paymentToken.balanceOf(treasury), 10 * 10**6, "Treasury should have received payment");
    }

    function testRenewSubscription() public {
        // Setup: User subscribes to a plan
        vm.startPrank(user1);
        paymentToken.approve(address(subscriptionManager), 20 * 10**6); // Approve for initial + renewal
        subscriptionManager.subscribe(planId, true);
        
        // Fast forward to near the end of subscription
        uint256 almostEndTime = block.timestamp + 29 days;
        vm.warp(almostEndTime);
        
        // Renew subscription
        subscriptionManager.renewSubscription(planId);
        vm.stopPrank();
        
        // Check subscription end time is extended
        SubscriptionManager.Subscription memory subscription = subscriptionManager.getSubscription(user1, planId);
        uint256 endTime = subscription.endTime;
        assertEq(endTime, almostEndTime + 30 days, "Subscription end time should be extended by 30 days");
        
        // Check treasury balance
        assertEq(paymentToken.balanceOf(treasury), 20 * 10**6, "Treasury should have received two payments");
    }

    function testCancelSubscription() public {
        // Setup: User subscribes to a plan
        vm.startPrank(user1);
        paymentToken.approve(address(subscriptionManager), 10 * 10**6);
        subscriptionManager.subscribe(planId, true);
        
        // Cancel subscription
        subscriptionManager.cancelSubscription(planId);
        vm.stopPrank();
        
        // Check subscription status
        SubscriptionManager.Subscription memory subscription = subscriptionManager.getSubscription(user1, planId);
        bool autoRenew = subscription.autoRenew;
        bool canceled = subscription.canceled;
        assertFalse(autoRenew, "Auto-renew should be disabled");
        assertTrue(canceled, "Subscription should be canceled");
        
        // User should still have access until end of current period
        assertTrue(subscriptionManager.isSubscribed(user1, planId), "User should still be subscribed until end of period");
    }

    function testProcessAutomaticRenewal() public {
        // Setup: User subscribes to a plan with auto-renewal
        vm.startPrank(user1);
        paymentToken.approve(address(subscriptionManager), 20 * 10**6); // Approve for initial + renewal
        subscriptionManager.subscribe(planId, true);
        vm.stopPrank();
        
        // Fast forward to after subscription ends
        vm.warp(block.timestamp + 31 days);
        
        // Process automatic renewal
        bool success = subscriptionManager.processAutomaticRenewal(user1, planId);
        
        assertTrue(success, "Renewal should be successful");
        assertTrue(subscriptionManager.isSubscribed(user1, planId), "User should still be subscribed");
        
        // Check treasury balance
        assertEq(paymentToken.balanceOf(treasury), 20 * 10**6, "Treasury should have received two payments");
    }

    function test_RevertWhen_ProcessingRenewalAfterGracePeriod() public {
    // Setup: User subscribes to a plan with auto-renewal
    vm.startPrank(user1);
    paymentToken.approve(address(subscriptionManager), 20 * 10**6);
    subscriptionManager.subscribe(planId, true);
    vm.stopPrank();
    
    // Fast forward to after subscription ends + grace period
    vm.warp(block.timestamp + 30 days + gracePeriod + 1);
    
    // Process automatic renewal should fail
    bool success = subscriptionManager.processAutomaticRenewal(user1, planId);
    assertFalse(success, "Renewal should fail after grace period");
}

    function testOwnerFunctions() public {
        // Test pause and unpause
        subscriptionManager.pause();
        
        vm.startPrank(user2);
        paymentToken.approve(address(subscriptionManager), 10 * 10**6);
        
        vm.expectRevert("Pausable: paused");
        subscriptionManager.subscribe(planId, true);
        vm.stopPrank();
        
        subscriptionManager.unpause();
        
        // Test changing payment token
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        subscriptionManager.setPaymentToken(IERC20(address(newToken)));
        
        assertEq(address(subscriptionManager.paymentToken()), address(newToken), "Payment token should be updated");
        
        // Test changing treasury
        address newTreasury = makeAddr("newTreasury");
        subscriptionManager.setTreasury(newTreasury);
        
        assertEq(subscriptionManager.treasury(), newTreasury, "Treasury should be updated");
        
        // Test changing grace period
        uint256 newGracePeriod = 14 days;
        subscriptionManager.setGracePeriod(newGracePeriod);
        
        assertEq(subscriptionManager.gracePeriod(), newGracePeriod, "Grace period should be updated");
    }
}