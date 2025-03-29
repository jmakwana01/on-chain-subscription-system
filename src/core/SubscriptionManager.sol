// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SubscriptionManager
 * @author Jay Makwana
 * @notice Manages subscription plans, user subscriptions, and payment processing
 * @dev This contract forms the core of the on-chain subscription payment system
 */
contract SubscriptionManager is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ======== EVENTS ========

    /**
     * @notice Emitted when a new plan is created
     * @param planId Unique identifier for the plan
     * @param name Name of the subscription plan
     * @param price Price per billing cycle
     * @param duration Duration of each billing cycle in seconds
     */
    event PlanCreated(uint256 indexed planId, string name, uint256 price, uint256 duration);

    /**
     * @notice Emitted when a user subscribes to a plan
     * @param user Address of the subscriber
     * @param planId ID of the subscription plan
     * @param startTime Timestamp when the subscription starts
     * @param endTime Timestamp when the subscription ends
     */
    event SubscriptionCreated(
        address indexed user,
        uint256 indexed planId,
        uint256 startTime,
        uint256 endTime
    );

    /**
     * @notice Emitted when a subscription is renewed
     * @param user Address of the subscriber
     * @param planId ID of the subscription plan
     * @param newEndTime New end timestamp for the subscription
     */
    event SubscriptionRenewed(address indexed user, uint256 indexed planId, uint256 newEndTime);

    /**
     * @notice Emitted when a subscription is canceled
     * @param user Address of the subscriber
     * @param planId ID of the subscription plan
     * @param endTime Current end timestamp of the subscription
     */
    event SubscriptionCanceled(address indexed user, uint256 indexed planId, uint256 endTime);

    /**
     * @notice Emitted when payment is processed
     * @param user Address of the payer
     * @param planId ID of the subscription plan
     * @param amount Amount paid
     * @param token Address of the token used for payment
     */
    event PaymentProcessed(
        address indexed user,
        uint256 indexed planId,
        uint256 amount,
        address token
    );

    // ======== STATE VARIABLES ========

    /**
     * @notice Structure defining a subscription plan
     * @param name Human-readable name of the plan
     * @param price Cost per billing cycle in smallest token unit
     * @param duration Duration of billing cycle in seconds
     * @param active Whether the plan is currently available
     * @param features Array of feature flags enabled for this plan
     */
    struct Plan {
        string name;
        uint256 price;
        uint256 duration;
        bool active;
        string[] features;
    }

    /**
     * @notice Structure defining a user's subscription
     * @param planId ID of the subscribed plan
     * @param startTime Timestamp when subscription started
     * @param endTime Timestamp when subscription ends
     * @param autoRenew Whether subscription should automatically renew
     * @param canceled Whether subscription has been canceled
     */
    struct Subscription {
        uint256 planId;
        uint256 startTime;
        uint256 endTime;
        bool autoRenew;
        bool canceled;
    }

    /**
     * @dev Mapping of plan ID to Plan details
     */
    mapping(uint256 => Plan) public plans;

    /**
     * @dev Mapping of user address to plan ID to Subscription details
     */
    mapping(address => mapping(uint256 => Subscription)) public subscriptions;

    /**
     * @dev Mapping of user address to boolean indicating if they have any active subscription
     */
    mapping(address => bool) public hasActiveSubscription;

    /**
     * @dev Counter for generating unique plan IDs
     */
    uint256 public nextPlanId;

    /**
     * @dev Address of the accepted payment token (e.g., USDC)
     */
    IERC20 public paymentToken;

    /**
     * @dev Grace period in seconds after subscription expiry
     */
    uint256 public gracePeriod;

    /**
     * @dev Treasury address where fees are collected
     */
    address public treasury;

    // ======== CONSTRUCTOR ========

    /**
     * @notice Initializes the contract with required parameters
     * @param _paymentToken Address of the ERC20 token used for payments
     * @param _treasury Address where subscription fees will be sent
     * @param _gracePeriod Grace period in seconds for subscription renewals
     */
    constructor(IERC20 _paymentToken, address _treasury, uint256 _gracePeriod) Ownable(msg.sender) {
        require(address(_paymentToken) != address(0), "Invalid payment token");
        require(_treasury != address(0), "Invalid treasury address");

        paymentToken = _paymentToken;
        treasury = _treasury;
        gracePeriod = _gracePeriod;
        nextPlanId = 1;
    }

    // ======== ADMIN FUNCTIONS ========

    /**
     * @notice Creates a new subscription plan
     * @param _name Name of the plan
     * @param _price Price per billing cycle in token units
     * @param _duration Duration of billing cycle in seconds
     * @param _features Array of features available in this plan
     * @return planId Unique identifier for the new plan
     */
    function createPlan(
        string memory _name,
        uint256 _price,
        uint256 _duration,
        string[] memory _features
    ) external onlyOwner returns (uint256 planId) {
        require(bytes(_name).length > 0, "Plan name cannot be empty");
        require(_price > 0, "Price must be greater than zero");
        require(_duration > 0, "Duration must be greater than zero");

        planId = nextPlanId++;
        
        plans[planId] = Plan({
            name: _name,
            price: _price,
            duration: _duration,
            active: true,
            features: _features
        });

        emit PlanCreated(planId, _name, _price, _duration);
        return planId;
    }

    /**
     * @notice Updates an existing subscription plan
     * @param _planId ID of the plan to update
     * @param _name New name for the plan
     * @param _price New price per billing cycle
     * @param _duration New duration for billing cycle
     * @param _active Whether the plan should be active
     * @param _features New array of features for this plan
     */
    function updatePlan(
        uint256 _planId,
        string memory _name,
        uint256 _price,
        uint256 _duration,
        bool _active,
        string[] memory _features
    ) external onlyOwner {
        require(_planId > 0 && _planId < nextPlanId, "Invalid plan ID");
        require(bytes(_name).length > 0, "Plan name cannot be empty");
        require(_price > 0, "Price must be greater than zero");
        require(_duration > 0, "Duration must be greater than zero");

        Plan storage plan = plans[_planId];
        
        plan.name = _name;
        plan.price = _price;
        plan.duration = _duration;
        plan.active = _active;
        plan.features = _features;
    }

    /**
     * @notice Sets the payment token address
     * @param _paymentToken New token address
     */
    function setPaymentToken(IERC20 _paymentToken) external onlyOwner {
        require(address(_paymentToken) != address(0), "Invalid payment token");
        paymentToken = _paymentToken;
    }

    /**
     * @notice Sets the treasury address
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;
    }

    /**
     * @notice Sets the grace period for subscription renewals
     * @param _gracePeriod New grace period in seconds
     */
    function setGracePeriod(uint256 _gracePeriod) external onlyOwner {
        gracePeriod = _gracePeriod;
    }

    /**
     * @notice Pauses the contract
     * @dev Prevents new subscriptions and renewals
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ======== USER FUNCTIONS ========

    /**
     * @notice Allows a user to subscribe to a plan
     * @param _planId ID of the plan to subscribe to
     * @param _autoRenew Whether the subscription should automatically renew
     */
    function subscribe(uint256 _planId, bool _autoRenew) external nonReentrant whenNotPaused {
        require(_planId > 0 && _planId < nextPlanId, "Invalid plan ID");
        
        Plan memory plan = plans[_planId];
        require(plan.active, "Plan is not active");
        
        // Check if user already has this subscription
        Subscription storage subscription = subscriptions[msg.sender][_planId];
        require(subscription.endTime < block.timestamp, "Already subscribed to this plan");

        // Process payment
        uint256 amount = plan.price;
        paymentToken.safeTransferFrom(msg.sender, treasury, amount);
        
        // Calculate subscription period
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + plan.duration;
        
        // Create subscription
        subscription.planId = _planId;
        subscription.startTime = startTime;
        subscription.endTime = endTime;
        subscription.autoRenew = _autoRenew;
        subscription.canceled = false;
        
        // Mark user as having an active subscription
        hasActiveSubscription[msg.sender] = true;
        
        emit SubscriptionCreated(msg.sender, _planId, startTime, endTime);
        emit PaymentProcessed(msg.sender, _planId, amount, address(paymentToken));
    }

    /**
     * @notice Allows a user to manually renew their subscription
     * @param _planId ID of the plan to renew
     */
    function renewSubscription(uint256 _planId) external nonReentrant whenNotPaused {
        require(_planId > 0 && _planId < nextPlanId, "Invalid plan ID");
        
        Subscription storage subscription = subscriptions[msg.sender][_planId];
        require(subscription.startTime > 0, "No subscription found");
        require(!subscription.canceled, "Subscription is canceled");
        
        Plan memory plan = plans[_planId];
        require(plan.active, "Plan is not active");
        
        // Check if within grace period or still active
        require(
            block.timestamp <= subscription.endTime + gracePeriod,
            "Subscription expired beyond grace period"
        );
        
        // Process payment
        uint256 amount = plan.price;
        paymentToken.safeTransferFrom(msg.sender, treasury, amount);
        
        // Update subscription
        uint256 newEndTime;
        if (block.timestamp > subscription.endTime) {
            // If expired but within grace period, start from now
            newEndTime = block.timestamp + plan.duration;
        } else {
            // If still active, extend from current end time
            newEndTime = subscription.endTime + plan.duration;
        }
        
        subscription.endTime = newEndTime;
        
        // Ensure user is marked as having an active subscription
        hasActiveSubscription[msg.sender] = true;
        
        emit SubscriptionRenewed(msg.sender, _planId, newEndTime);
        emit PaymentProcessed(msg.sender, _planId, amount, address(paymentToken));
    }

    /**
     * @notice Allows a user to cancel auto-renewal for their subscription
     * @param _planId ID of the plan to cancel
     */
    function cancelSubscription(uint256 _planId) external nonReentrant {
        Subscription storage subscription = subscriptions[msg.sender][_planId];
        
        require(subscription.startTime > 0, "No subscription found");
        require(!subscription.canceled, "Subscription already canceled");
        require(subscription.endTime > block.timestamp, "Subscription already expired");
        
        subscription.autoRenew = false;
        subscription.canceled = true;
        
        emit SubscriptionCanceled(msg.sender, _planId, subscription.endTime);
    }

    /**
     * @notice Processes automatic renewal for a subscription
     * @dev This function is intended to be called by Chainlink Automation
     * @param _user Address of the user whose subscription to renew
     * @param _planId ID of the plan to renew
     * @return success Whether the renewal was successful
     */
    function processAutomaticRenewal(address _user, uint256 _planId) 
        external 
        nonReentrant 
        whenNotPaused 
        returns (bool success) 
    {
        if (_planId == 0 || _planId >= nextPlanId) {
            return false; // Invalid plan ID
        }
        
        Subscription storage subscription = subscriptions[_user][_planId];
        
        // Check if subscription exists and is eligible for auto-renewal
        if (subscription.startTime == 0 ||
            !subscription.autoRenew ||
            subscription.canceled ||
            block.timestamp < subscription.endTime ||
            block.timestamp > subscription.endTime + gracePeriod) {
            return false;
        }
        
        Plan memory plan = plans[_planId];
        if (!plan.active) {
            return false;
        }
        
        // Check if user has approved enough tokens
        if (paymentToken.allowance(_user, address(this)) < plan.price) {
            return false;
        }
        
        // Process payment
        // Attempt to transfer payment
        bool transfer = paymentToken.transferFrom(_user, treasury, plan.price);
        if (!transfer) {
            return false; // Payment transfer failed
        }

        // Update subscription end time
        uint256 newEndTime = block.timestamp + plan.duration;
        subscription.endTime = newEndTime;
        
        // Ensure user is marked as having an active subscription
        hasActiveSubscription[_user] = true;
        
        emit SubscriptionRenewed(_user, _planId, newEndTime);
        emit PaymentProcessed(_user, _planId, plan.price, address(paymentToken));
        
        return true;
    }

    // ======== VIEW FUNCTIONS ========

    /**
     * @notice Checks if a user has an active subscription to a specific plan
     * @param _user Address of the user to check
     * @param _planId ID of the plan to check
     * @return is_Subscribed Whether the user has an active subscription
     */
    function isSubscribed(address _user, uint256 _planId) public view returns (bool is_Subscribed) {
        Subscription memory subscription = subscriptions[_user][_planId];
        return subscription.endTime >= block.timestamp && !subscription.canceled;
    }

    /**
     * @notice Gets all subscription plans
     * @return planIds Array of plan IDs
     * @return planDetails Array of Plan structs
     */
    function getAllPlans() external view returns (uint256[] memory planIds, Plan[] memory planDetails) {
        uint256 planCount = nextPlanId - 1;
        
        planIds = new uint256[](planCount);
        planDetails = new Plan[](planCount);
        
        for (uint256 i = 1; i <= planCount; i++) {
            planIds[i-1] = i;
            planDetails[i-1] = plans[i];
        }
        
        return (planIds, planDetails);
    }

    /**
     * @notice Gets all active subscriptions for a user
     * @param _user Address of the user to check
     * @return activePlanIds Array of active plan IDs
     * @return subscriptionDetails Array of Subscription structs
     */
    function getUserSubscriptions(address _user) 
        external 
        view 
        returns (uint256[] memory activePlanIds, Subscription[] memory subscriptionDetails) 
    {
        // First count active subscriptions
        uint256 activeCount = 0;
        for (uint256 i = 1; i < nextPlanId; i++) {
            if (isSubscribed(_user, i)) {
                activeCount++;
            }
        }
        
        // Create arrays of appropriate size
        activePlanIds = new uint256[](activeCount);
        subscriptionDetails = new Subscription[](activeCount);
        
        // Fill arrays with active subscription data
        uint256 index = 0;
        for (uint256 i = 1; i < nextPlanId; i++) {
            if (isSubscribed(_user, i)) {
                activePlanIds[index] = i;
                subscriptionDetails[index] = subscriptions[_user][i];
                index++;
            }
        }
        
        return (activePlanIds, subscriptionDetails);
    }

    /**
     * @notice Gets subscription details for a specific user and plan
     * @param _user Address of the user
     * @param _planId ID of the plan
     * @return subscription Subscription details
     */
    function getSubscription(address _user, uint256 _planId) 
        external 
        view 
        returns (Subscription memory subscription) 
    {
        return subscriptions[_user][_planId];
    }

    /**
     * @notice Gets a specific plan's details
     * @param _planId ID of the plan
     * @return plan Plan details
     */
    function getPlan(uint256 _planId) external view returns (Plan memory plan) {
        require(_planId > 0 && _planId < nextPlanId, "Invalid plan ID");
        return plans[_planId];
    }
}