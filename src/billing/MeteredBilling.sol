    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.20;

    import "@openzeppelin/contracts/access/Ownable.sol";
    import "@openzeppelin/contracts/utils/Pausable.sol";
    import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
    import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
    import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
    import "../core/SubscriptionManager.sol";

    /**
     * @title MeteredBilling
     * @author Your Name
     * @notice Manages usage-based billing for subscription services
     * @dev Extends the subscription system with pay-as-you-go functionality
     */
    contract MeteredBilling is Ownable, Pausable, ReentrancyGuard {
        using SafeERC20 for IERC20;

        /**
         * @notice Emitted when usage is recorded for a user
         * @param user Address of the user
         * @param serviceId ID of the service
         * @param amount Usage amount
         * @param totalUsage Updated total usage
         */
        event UsageRecorded(
            address indexed user,
            uint256 indexed serviceId,
            uint256 amount,
            uint256 totalUsage
        );

        /**
         * @notice Emitted when a service provider is registered
         * @param provider Address of the service provider
         * @param serviceId ID of the service
         */
        event ServiceProviderRegistered(
            address indexed provider,
            uint256 indexed serviceId
        );

        /**
         * @notice Emitted when a billing cycle is settled
         * @param user Address of the user
         * @param serviceId ID of the service
         * @param usageAmount Total usage amount
         * @param billingAmount Amount billed
         */
        event BillingCycleSettled(
            address indexed user,
            uint256 indexed serviceId,
            uint256 usageAmount,
            uint256 billingAmount
        );

        /**
         * @dev Struct defining a metered service
         * @param name Human-readable name of the service
         * @param provider Address of the service provider
         * @param ratePerUnit Cost per unit of usage
         * @param minUsage Minimum usage to bill
         * @param maxUsage Maximum usage to bill
         * @param active Whether the service is currently active
         */
        struct MeteredService {
            string name;
            address provider;
            uint256 ratePerUnit;
            uint256 minUsage;
            uint256 maxUsage;
            bool active;
        }

        /**
         * @dev Struct for tracking user usage
         * @param totalUsage Total accumulated usage
         * @param billedUsage Usage that has been billed
         * @param lastRecordTime Timestamp of last usage record
         * @param billingCycleStart Start timestamp of current billing cycle
         * @param billingCycleEnd End timestamp of current billing cycle
         */
        struct UserUsage {
            uint256 totalUsage;
            uint256 billedUsage;
            uint256 lastRecordTime;
            uint256 billingCycleStart;
            uint256 billingCycleEnd;
        }

        /**
         * @dev Reference to the subscription manager contract
         */
        SubscriptionManager public subscriptionManager;

        /**
         * @dev Token used for payments
         */
        IERC20 public paymentToken;

        /**
         * @dev Treasury address where fees are collected
         */
        address public treasury;

        /**
         * @dev Mapping of service ID to MeteredService details
         */
        mapping(uint256 => MeteredService) public services;

        /**
         * @dev Mapping of provider address to service IDs they control
         */
        mapping(address => uint256[]) public providerServices;

        /**
         * @dev Mapping of user address to service ID to usage details
         */
        mapping(address => mapping(uint256 => UserUsage)) public userUsage;

        /**
         * @dev Counter for generating unique service IDs
         */
        uint256 public nextServiceId;

        /**
         * @dev Mapping of addresses authorized to record usage
         */
        mapping(address => bool) public usageRecorders;

        /**
         * @dev Default billing cycle duration in seconds (30 days)
         */
        uint256 public defaultBillingCycleDuration;

        /**
         * @notice Initializes the metered billing contract
         * @param _subscriptionManager Address of the subscription manager contract
         * @param _paymentToken Address of the ERC20 token used for payments
         * @param _treasury Address where fees are collected
         * @param _billingCycleDuration Duration of billing cycle in seconds
         */
        constructor(
            address _subscriptionManager,
            IERC20 _paymentToken,
            address _treasury,
            uint256 _billingCycleDuration
        ) Ownable(msg.sender) {
            require(_subscriptionManager != address(0), "Invalid subscription manager");
            require(address(_paymentToken) != address(0), "Invalid payment token");
            require(_treasury != address(0), "Invalid treasury address");
            require(_billingCycleDuration > 0, "Invalid billing cycle duration");
            
            subscriptionManager = SubscriptionManager(_subscriptionManager);
            paymentToken = _paymentToken;
            treasury = _treasury;
            defaultBillingCycleDuration = _billingCycleDuration;
            nextServiceId = 1;
            
            // Owner is authorized to record usage by default
            usageRecorders[msg.sender] = true;
        }

        // ======== ADMIN FUNCTIONS ========

        /**
         * @notice Sets the subscription manager contract
         * @param _subscriptionManager New subscription manager address
         */
        function setSubscriptionManager(address _subscriptionManager) external onlyOwner {
            require(_subscriptionManager != address(0), "Invalid subscription manager");
            subscriptionManager = SubscriptionManager(_subscriptionManager);
        }

        /**
         * @notice Sets the payment token
         * @param _paymentToken New payment token address
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
         * @notice Sets the default billing cycle duration
         * @param _duration New duration in seconds
         */
        function setDefaultBillingCycleDuration(uint256 _duration) external onlyOwner {
            require(_duration > 0, "Invalid duration");
            defaultBillingCycleDuration = _duration;
        }

        /**
         * @notice Authorizes or revokes an address to record usage
         * @param _recorder Address to authorize/revoke
         * @param _authorized Whether the address is authorized
         */
        function setUsageRecorder(address _recorder, bool _authorized) external onlyOwner {
            require(_recorder != address(0), "Invalid recorder address");
            usageRecorders[_recorder] = _authorized;
        }

        /**
         * @notice Pauses the contract
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

        // ======== SERVICE PROVIDER FUNCTIONS ========

        /**
         * @notice Registers a new metered service
         * @param _name Name of the service
         * @param _provider Address of the service provider
         * @param _ratePerUnit Cost per unit of usage
         * @param _minUsage Minimum usage to bill
         * @param _maxUsage Maximum usage to bill
         * @return serviceId ID of the new service
         */
        function registerService(
            string memory _name,
            address _provider,
            uint256 _ratePerUnit,
            uint256 _minUsage,
            uint256 _maxUsage
        ) external onlyOwner returns (uint256 serviceId) {
            require(bytes(_name).length > 0, "Service name cannot be empty");
            require(_provider != address(0), "Invalid provider address");
            require(_ratePerUnit > 0, "Rate must be greater than zero");
            require(_maxUsage > _minUsage, "Max usage must be greater than min usage");
            
            serviceId = nextServiceId++;
            
            services[serviceId] = MeteredService({
                name: _name,
                provider: _provider,
                ratePerUnit: _ratePerUnit,
                minUsage: _minUsage,
                maxUsage: _maxUsage,
                active: true
            });
            
            providerServices[_provider].push(serviceId);
            
            emit ServiceProviderRegistered(_provider, serviceId);
            
            return serviceId;
        }

        /**
         * @notice Updates an existing metered service
         * @param _serviceId ID of the service to update
         * @param _name New name for the service
         * @param _provider New provider address
         * @param _ratePerUnit New rate per unit
         * @param _minUsage New minimum usage
         * @param _maxUsage New maximum usage
         * @param _active Whether the service is active
         */
        function updateService(
            uint256 _serviceId,
            string memory _name,
            address _provider,
            uint256 _ratePerUnit,
            uint256 _minUsage,
            uint256 _maxUsage,
            bool _active
        ) external onlyOwner {
            require(_serviceId > 0 && _serviceId < nextServiceId, "Invalid service ID");
            require(bytes(_name).length > 0, "Service name cannot be empty");
            require(_provider != address(0), "Invalid provider address");
            require(_ratePerUnit > 0, "Rate must be greater than zero");
            require(_maxUsage > _minUsage, "Max usage must be greater than min usage");
            
            MeteredService storage service = services[_serviceId];
            
            // If provider is changing, update the provider service mappings
            if (service.provider != _provider) {
                // Add to new provider's services
                providerServices[_provider].push(_serviceId);
                
                // Remove from old provider's services
                uint256[] storage oldProviderServices = providerServices[service.provider];
                for (uint256 i = 0; i < oldProviderServices.length; i++) {
                    if (oldProviderServices[i] == _serviceId) {
                        // Replace with the last element and pop
                        oldProviderServices[i] = oldProviderServices[oldProviderServices.length - 1];
                        oldProviderServices.pop();
                        break;
                    }
                }
            }
            
            // Update the service
            service.name = _name;
            service.provider = _provider;
            service.ratePerUnit = _ratePerUnit;
            service.minUsage = _minUsage;
            service.maxUsage = _maxUsage;
            service.active = _active;
        }

        // ======== USAGE RECORDING FUNCTIONS ========

        /**
         * @notice Records usage for a user
         * @param _user Address of the user
         * @param _serviceId ID of the service
         * @param _amount Usage amount to record
         */
        function recordUsage(
            address _user,
            uint256 _serviceId,
            uint256 _amount
        ) external whenNotPaused {
            require(usageRecorders[msg.sender] || msg.sender == services[_serviceId].provider, "Not authorized");
            require(_user != address(0), "Invalid user address");
            require(_serviceId > 0 && _serviceId < nextServiceId, "Invalid service ID");
            require(_amount > 0, "Amount must be greater than zero");
            require(services[_serviceId].active, "Service is not active");
            
            // Check if user has a valid subscription
            require(subscriptionManager.hasActiveSubscription(_user), "No active subscription");
            
            UserUsage storage usage = userUsage[_user][_serviceId];
            
            // Initialize billing cycle if first usage
            if (usage.billingCycleStart == 0) {
                usage.billingCycleStart = block.timestamp;
                usage.billingCycleEnd = block.timestamp + defaultBillingCycleDuration;
            }
            
            // If we're past the billing cycle end, reset the cycle
            if (block.timestamp > usage.billingCycleEnd) {
                // Auto-settle the previous cycle
                _settleBillingCycle(_user, _serviceId);
                
                // Start a new cycle
                usage.billingCycleStart = block.timestamp;
                usage.billingCycleEnd = block.timestamp + defaultBillingCycleDuration;
                usage.totalUsage = 0;
                usage.billedUsage = 0;
            }
            
            // Record the usage
            usage.totalUsage += _amount;
            usage.lastRecordTime = block.timestamp;
            
            emit UsageRecorded(_user, _serviceId, _amount, usage.totalUsage);
        }

        /**
         * @notice Records usage for multiple users
         * @param _users Array of user addresses
         * @param _serviceId ID of the service
         * @param _amounts Array of usage amounts
         */
        function batchRecordUsage(
            address[] calldata _users,
            uint256 _serviceId,
            uint256[] calldata _amounts
        ) external whenNotPaused {
            require(usageRecorders[msg.sender] || msg.sender == services[_serviceId].provider, "Not authorized");
            require(_users.length == _amounts.length, "Arrays length mismatch");
            require(_serviceId > 0 && _serviceId < nextServiceId, "Invalid service ID");
            require(services[_serviceId].active, "Service is not active");
            
            for (uint256 i = 0; i < _users.length; i++) {
                address user = _users[i];
                uint256 amount = _amounts[i];
                
                if (user != address(0) && amount > 0 && subscriptionManager.hasActiveSubscription(user)) {
                    UserUsage storage usage = userUsage[user][_serviceId];
                    
                    // Initialize billing cycle if first usage
                    if (usage.billingCycleStart == 0) {
                        usage.billingCycleStart = block.timestamp;
                        usage.billingCycleEnd = block.timestamp + defaultBillingCycleDuration;
                    }
                    
                    // If we're past the billing cycle end, reset the cycle
                    if (block.timestamp > usage.billingCycleEnd) {
                        // Auto-settle the previous cycle
                        _settleBillingCycle(user, _serviceId);
                        
                        // Start a new cycle
                        usage.billingCycleStart = block.timestamp;
                        usage.billingCycleEnd = block.timestamp + defaultBillingCycleDuration;
                        usage.totalUsage = 0;
                        usage.billedUsage = 0;
                    }
                    
                    // Record the usage
                    usage.totalUsage += amount;
                    usage.lastRecordTime = block.timestamp;
                    
                    emit UsageRecorded(user, _serviceId, amount, usage.totalUsage);
                }
            }
        }

        // ======== BILLING FUNCTIONS ========

        /**
         * @notice Settles the current billing cycle for a user's service
         * @param _user Address of the user
         * @param _serviceId ID of the service
         * @return billingAmount Amount billed
         */
        function settleBillingCycle(
            address _user,
            uint256 _serviceId
        ) external nonReentrant whenNotPaused returns (uint256 billingAmount) {
            require(_user != address(0), "Invalid user address");
            require(_serviceId > 0 && _serviceId < nextServiceId, "Invalid service ID");
            
            // Only owner, service provider, or authorized recorder can settle
            require(
                msg.sender == owner() || 
                msg.sender == services[_serviceId].provider || 
                usageRecorders[msg.sender],
                "Not authorized"
            );
            
            return _settleBillingCycle(_user, _serviceId);
        }

        /**
         * @notice Internal function to settle a billing cycle
         * @param _user Address of the user
         * @param _serviceId ID of the service
         * @return billingAmount Amount billed
         */
        function _settleBillingCycle(
            address _user,
            uint256 _serviceId
        ) internal returns (uint256 billingAmount) {
            UserUsage storage usage = userUsage[_user][_serviceId];
            MeteredService memory service = services[_serviceId];
            
            // Calculate billable usage (new usage since last billing)
            uint256 billableUsage = usage.totalUsage - usage.billedUsage;
            
            // If no new usage, return 0
            if (billableUsage == 0) {
                return 0;
            }
            
            // Apply minimum and maximum usage constraints
            if (billableUsage < service.minUsage) {
                billableUsage = service.minUsage;
            } else if (billableUsage > service.maxUsage) {
                billableUsage = service.maxUsage;
            }
            
            // Calculate billing amount
            billingAmount = billableUsage * service.ratePerUnit;
            
            // Update billed usage
            usage.billedUsage = usage.totalUsage;
            
            // Transfer payment from user to treasury
            // Note: User must have pre-approved this contract to spend their tokens
            // Attempt to transfer payment from user to treasury
            bool success = paymentToken.transferFrom(_user, treasury, billingAmount);
            require(success, "Payment failed - insufficient allowance or balance");

            // Emit event and return billing amount
            emit BillingCycleSettled(_user, _serviceId, billableUsage, billingAmount);
            return billingAmount;
        }

        /**
         * @notice Batch settles billing cycles for multiple users
         * @param _users Array of user addresses
         * @param _serviceId ID of the service
         * @return successCount Number of successful settlements
         * @return totalBilled Total amount billed
         */
        function batchSettleBillingCycles(
            address[] calldata _users,
            uint256 _serviceId
        ) external nonReentrant whenNotPaused returns (uint256 successCount, uint256 totalBilled) {
            require(_serviceId > 0 && _serviceId < nextServiceId, "Invalid service ID");
            
            // Only owner, service provider, or authorized recorder can settle
            require(
                msg.sender == owner() || 
                msg.sender == services[_serviceId].provider || 
                usageRecorders[msg.sender],
                "Not authorized"
            );
            
            successCount = 0;
            totalBilled = 0;
            
            for (uint256 i = 0; i < _users.length; i++) {
                address user = _users[i];
                
                if (user != address(0)) {
                    try this.settleBillingCycle(user, _serviceId) returns (uint256 billingAmount) {
                        successCount++;
                        totalBilled += billingAmount;
                    } catch {
                        // Skip failures and continue with next user
                    }
                }
            }
            
            return (successCount, totalBilled);
        }

        // ======== VIEW FUNCTIONS ========

        /**
         * @notice Gets the current usage for a user's service
         * @param _user Address of the user
         * @param _serviceId ID of the service
         * @return usage Usage details
         */
        function getUserUsage(address _user, uint256 _serviceId) 
            external 
            view 
            returns (UserUsage memory usage) 
        {
            return userUsage[_user][_serviceId];
        }

        /**
         * @notice Gets a service's details
         * @param _serviceId ID of the service
         * @return service Service details
         */
        function getService(uint256 _serviceId) 
            external 
            view 
            returns (MeteredService memory service) 
        {
            require(_serviceId > 0 && _serviceId < nextServiceId, "Invalid service ID");
            return services[_serviceId];
        }

        /**
         * @notice Gets all services for a provider
         * @param _provider Address of the provider
         * @return serviceIds Array of service IDs
         */
        function getProviderServices(address _provider) 
            external 
            view 
            returns (uint256[] memory serviceIds) 
        {
            return providerServices[_provider];
        }

        /**
         * @notice Calculates the current billing amount for a user's service
         * @param _user Address of the user
         * @param _serviceId ID of the service
         * @return billableUsage Billable usage units
         * @return billingAmount Amount to be billed
         */
        function calculateCurrentBilling(address _user, uint256 _serviceId) 
            external 
            view 
            returns (uint256 billableUsage, uint256 billingAmount) 
        {
            require(_serviceId > 0 && _serviceId < nextServiceId, "Invalid service ID");
            
            UserUsage storage usage = userUsage[_user][_serviceId];
            MeteredService memory service = services[_serviceId];
            
            // Calculate billable usage
            billableUsage = usage.totalUsage - usage.billedUsage;
            
            // Apply minimum and maximum usage constraints
            if (billableUsage < service.minUsage) {
                billableUsage = service.minUsage;
            } else if (billableUsage > service.maxUsage) {
                billableUsage = service.maxUsage;
            }
            
            // Calculate billing amount
            billingAmount = billableUsage * service.ratePerUnit;
            
            return (billableUsage, billingAmount);
        }

        /**
         * @notice Gets time until next billing cycle
         * @param _user Address of the user
         * @param _serviceId ID of the service
         * @return timeRemaining Time in seconds until next billing cycle
         */
        function getTimeUntilNextBillingCycle(address _user, uint256 _serviceId) 
            external 
            view 
            returns (uint256 timeRemaining) 
        {
            UserUsage storage usage = userUsage[_user][_serviceId];
            
            // If no billing cycle started or already ended
            if (usage.billingCycleStart == 0 || block.timestamp >= usage.billingCycleEnd) {
                return 0;
            }
            
            return usage.billingCycleEnd - block.timestamp;
        }

        /**
         * @notice Checks if a user's billing cycle needs settlement
         * @param _user Address of the user
         * @param _serviceId ID of the service
         * @return _needsSettlement Whether the cycle needs settlement
         */
        function needsSettlement(address _user, uint256 _serviceId) 
            external 
            view 
            returns (bool _needsSettlement) 
        {
            UserUsage storage usage = userUsage[_user][_serviceId];
            
            // Needs settlement if has unbilled usage or past billing cycle end
            return (usage.totalUsage > usage.billedUsage) || 
                (usage.billingCycleEnd > 0 && block.timestamp > usage.billingCycleEnd);
        }

    }