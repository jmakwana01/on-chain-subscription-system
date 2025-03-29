// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../core/SubscriptionManager.sol";

/**
 * @title SubscriptionKeeper
 * @author Jay Makwana
 * @notice Chainlink Automation (formerly Keepers) compatible contract for subscription renewals
 * @dev Manages automated subscription renewals using Chainlink Automation
 */
contract SubscriptionKeeper is AutomationCompatibleInterface, Ownable {
    /**
     * @notice Emitted when subscription renewal is attempted
     * @param user Address of the subscriber
     * @param planId ID of the subscription plan
     * @param success Whether the renewal was successful
     */
    event RenewalAttempted(address indexed user, uint256 indexed planId, bool success);

    /**
     * @dev Reference to the SubscriptionManager contract
     */
    SubscriptionManager public subscriptionManager;
    
    /**
     * @dev Tracking for subscription renewal attempts
     */
    mapping(address => mapping(uint256 => uint256)) public lastRenewalAttempt;
    
    /**
     * @dev Minimum time between renewal attempts in seconds
     */
    uint256 public renewalAttemptInterval;
    
    /**
     * @dev List of active subscribers to check
     */
    address[] public subscribers;
    
    /**
     * @dev Mapping to track subscriber indices in the subscribers array
     */
    mapping(address => uint256) private subscriberIndices;
    
    /**
     * @dev Counter for next subscriber to check in checkUpkeep
     */
    uint256 private nextSubscriberIndex;

    /**
     * @notice Initializes the keeper contract
     * @param _subscriptionManager Address of the subscription manager contract
     * @param _renewalAttemptInterval Minimum time between renewal attempts
     */
    constructor(
        address _subscriptionManager,
        uint256 _renewalAttemptInterval
    ) Ownable(msg.sender) {
        require(_subscriptionManager != address(0), "Invalid subscription manager");
        require(_renewalAttemptInterval > 0, "Invalid renewal interval");
        
        subscriptionManager = SubscriptionManager(_subscriptionManager);
        renewalAttemptInterval = _renewalAttemptInterval;
        nextSubscriberIndex = 0;
    }

    /**
     * @notice Sets the subscription manager contract address
     * @param _subscriptionManager New subscription manager address
     */
    function setSubscriptionManager(address _subscriptionManager) external onlyOwner {
        require(_subscriptionManager != address(0), "Invalid subscription manager");
        subscriptionManager = SubscriptionManager(_subscriptionManager);
    }

    /**
     * @notice Sets the renewal attempt interval
     * @param _interval New interval in seconds
     */
    function setRenewalAttemptInterval(uint256 _interval) external onlyOwner {
        require(_interval > 0, "Invalid renewal interval");
        renewalAttemptInterval = _interval;
    }

    /**
     * @notice Adds subscribers to be monitored for renewal
     * @param _subscribers Array of subscriber addresses
     */
    function addSubscribers(address[] calldata _subscribers) external onlyOwner {
        for (uint256 i = 0; i < _subscribers.length; i++) {
            address subscriber = _subscribers[i];
            if (subscriber != address(0) && subscriberIndices[subscriber] == 0) {
                subscribers.push(subscriber);
                subscriberIndices[subscriber] = subscribers.length;
            }
        }
    }

    /**
     * @notice Removes subscribers from monitoring
     * @param _subscribers Array of subscriber addresses to remove
     */
    function removeSubscribers(address[] calldata _subscribers) external onlyOwner {
        for (uint256 i = 0; i < _subscribers.length; i++) {
            address subscriber = _subscribers[i];
            uint256 index = subscriberIndices[subscriber];
            
            if (index > 0) {
                // Adjust for 1-based indexing
                index--;
                
                // Get the last subscriber
                address lastSubscriber = subscribers[subscribers.length - 1];
                
                // Replace the removed subscriber with the last one
                subscribers[index] = lastSubscriber;
                subscriberIndices[lastSubscriber] = index + 1;
                
                // Remove the last element
                subscribers.pop();
                
                // Clear the removed subscriber's index
                delete subscriberIndices[subscriber];
            }
        }
    }

    /**
     * @notice Register a subscriber when they create a subscription
     * @param _subscriber Address of the subscriber
     */
    function registerSubscriber(address _subscriber) external {
        require(
            msg.sender == address(subscriptionManager),
            "Only subscription manager can register"
        );
        
        if (_subscriber != address(0) && subscriberIndices[_subscriber] == 0) {
            subscribers.push(_subscriber);
            subscriberIndices[_subscriber] = subscribers.length;
        }
    }

    /**
     * @notice Chainlink Automation checkUpkeep function
     * @dev Checks if any subscriptions need renewal
     * @param checkData Additional data for the check (unused)
     * @return upkeepNeeded Whether upkeep is needed
     * @return performData Data to pass to performUpkeep
     */
    function checkUpkeep(
        bytes calldata checkData
    ) external  override returns (bool upkeepNeeded, bytes memory performData) {
        // Don't process if there are no subscribers
        if (subscribers.length == 0) {
            return (false, "");
        }
        
        // Determine how many subscribers to check in this upkeep
        uint256 maxChecks = 10; // Limit to prevent gas issues
        if (maxChecks > subscribers.length) {
            maxChecks = subscribers.length;
        }
        
        // Initialize array for eligible subscribers and their plans
        address[] memory eligibleUsers = new address[](maxChecks);
        uint256[] memory eligiblePlans = new uint256[](maxChecks);
        uint256 eligibleCount = 0;
        
        // Start from the next subscriber index
        uint256 startIndex = nextSubscriberIndex % subscribers.length;
        
        // Check subscribers for eligible renewals
        for (uint256 i = 0; i < maxChecks; i++) {
            uint256 checkIndex = (startIndex + i) % subscribers.length;
            address user = subscribers[checkIndex];
            
            // Get all active subscription plans for this user
            (uint256[] memory planIds, ) = subscriptionManager.getUserSubscriptions(user);
            
            // Check each plan for renewal eligibility
            for (uint256 j = 0; j < planIds.length; j++) {
                uint256 planId = planIds[j];
                
                // Get subscription details
                SubscriptionManager.Subscription memory sub = 
                    subscriptionManager.getSubscription(user, planId);
                
                // Check if renewal is needed and not attempted recently
                if (sub.autoRenew && 
                    !sub.canceled && 
                    block.timestamp > sub.endTime &&
                    block.timestamp <= sub.endTime + subscriptionManager.gracePeriod() &&
                    block.timestamp > lastRenewalAttempt[user][planId] + renewalAttemptInterval) {
                    
                    eligibleUsers[eligibleCount] = user;
                    eligiblePlans[eligibleCount] = planId;
                    eligibleCount++;
                    
                    // Stop if we found max eligible renewals
                    if (eligibleCount >= maxChecks) {
                        break;
                    }
                }
            }
            
            // Stop if we found max eligible renewals
            if (eligibleCount >= maxChecks) {
                break;
            }
        }
        
        // Prepare performData if any eligible renewals found
        if (eligibleCount > 0) {
            // Create fixed-size arrays with only the eligible entries
            address[] memory renewUsers = new address[](eligibleCount);
            uint256[] memory renewPlans = new uint256[](eligibleCount);
            
            for (uint256 i = 0; i < eligibleCount; i++) {
                renewUsers[i] = eligibleUsers[i];
                renewPlans[i] = eligiblePlans[i];
            }
            
            // Update the next subscriber index for the next checkUpkeep
            nextSubscriberIndex = (startIndex + maxChecks) % subscribers.length;
            
            // Encode the renewal data
            performData = abi.encode(renewUsers, renewPlans);
            upkeepNeeded = true;
        } else {
            // Update the next subscriber index for the next checkUpkeep
            nextSubscriberIndex = (startIndex + maxChecks) % subscribers.length;
            upkeepNeeded = false;
        }
        
        return (upkeepNeeded, performData);
    }

    /**
     * @notice Chainlink Automation performUpkeep function
     * @dev Processes subscription renewals
     * @param performData Data passed from checkUpkeep
     */
    function performUpkeep(bytes calldata performData) external override {
        // Decode the renewal data
        (address[] memory renewUsers, uint256[] memory renewPlans) = 
            abi.decode(performData, (address[], uint256[]));
        
        // Process each renewal
        for (uint256 i = 0; i < renewUsers.length; i++) {
            address user = renewUsers[i];
            uint256 planId = renewPlans[i];
            
            // Update last renewal attempt timestamp
            lastRenewalAttempt[user][planId] = block.timestamp;
            
            // Try to renew the subscription
            bool success = subscriptionManager.processAutomaticRenewal(user, planId);
            
            emit RenewalAttempted(user, planId, success);
        }
    }

    /**
     * @notice Manual trigger for renewal attempts
     * @param _user Address of the user
     * @param _planId ID of the plan
     * @return success Whether the renewal was successful
     */
    function manualRenewalAttempt(address _user, uint256 _planId) external onlyOwner returns (bool success) {
        // Update last renewal attempt timestamp
        lastRenewalAttempt[_user][_planId] = block.timestamp;
        
        // Try to renew the subscription
        success = subscriptionManager.processAutomaticRenewal(_user, _planId);
        
        emit RenewalAttempted(_user, _planId, success);
        return success;
    }

    /**
     * @notice Gets the total number of registered subscribers
     * @return count Number of subscribers
     */
    function getSubscriberCount() external view returns (uint256 count) {
        return subscribers.length;
    }

    /**
     * @notice Checks if an address is registered as a subscriber
     * @param _user Address to check
     * @return isRegistered Whether the address is registered
     */
    function isSubscriberRegistered(address _user) external view returns (bool isRegistered) {
        return subscriberIndices[_user] > 0;
    }
}