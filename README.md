# On-Chain Subscription Payment System

A decentralized SaaS subscription management system built on blockchain technology, leveraging Foundry, Solidity, Chainlink, and cross-chain interoperability to create a fully on-chain alternative to traditional subscription services like Stripe.

## Overview

This project implements a comprehensive on-chain subscription payment system that allows service providers to offer recurring subscription plans with features like automated renewals, usage-based billing, cross-chain subscriptions, and dynamic pricing. The system is designed to be modular, secure, and extensible.

## Features

### Core Subscription Management
- Multiple subscription tiers and plans (Basic, Pro, Enterprise)
- Configurable billing cycles (monthly, quarterly, yearly)
- Subscription cancellation and management
- Subscription status verification
- Grace periods for renewals

### Chainlink Integration
- **Price Feeds**: Get real-time token/USD pricing for dynamic subscription costs
- **Automation**: Automate subscription renewals using Chainlink Automation (formerly Keepers)
- **Cross-Chain**: Enable cross-chain subscriptions using Chainlink CCIP

### Advanced Features
- **Metered Billing**: Pay-as-you-go functionality for usage-based services
- **Cross-Chain Verification**: Validate subscriptions across different blockchains
- Usage thresholds and automatic tier upgrades

## Architecture

The system consists of the following main components:

### SubscriptionManager
The core contract that manages subscription plans, user subscriptions, and payment processing. It allows service providers to create different subscription tiers and users to subscribe to these plans.

Key responsibilities:
- Create and manage subscription plans
- Process user subscriptions and renewals
- Track subscription status
- Handle subscription cancellations

### PriceFeedConsumer
Integrates with Chainlink Price Feeds to get real-time token pricing. This enables:
- Dynamic subscription pricing based on token volatility
- Conversion between token amounts and USD values
- Support for multiple payment tokens

### SubscriptionKeeper
Utilizes Chainlink Automation to handle automated subscription renewals:
- Monitors subscriptions approaching expiration
- Processes renewal payments when due
- Handles failed renewals and retry logic

### CrossChainSubscriptionBridge
Enables cross-chain subscription management using Chainlink CCIP:
- Verifies subscription status across different chains
- Synchronizes subscription state between chains
- Allows subscribing on one chain and using services on another

### MeteredBilling
Extends subscription functionality with pay-as-you-go metered billing:
- Tracks resource usage for subscribers
- Processes usage-based billing alongside fixed subscriptions
- Supports minimum and maximum usage thresholds
- Allows for batch operations for efficient gas usage

## Technical Implementation

### Smart Contract Architecture

The system follows a modular design pattern where each contract handles a specific responsibility:

```
├── core/
│   ├── SubscriptionManager.sol     # Core subscription logic
├── chainlink/
│   ├── PriceFeedConsumer.sol       # Chainlink Price Feeds integration
│   ├── SubscriptionKeeper.sol      # Chainlink Automation integration
├── bridge/
│   ├── CrossChainSubscriptionBridge.sol  # CCIP integration
├── billing/
│   ├── MeteredBilling.sol          # Usage-based billing
```

### Security Considerations

The system implements several security measures:
- Reentrancy guards on all sensitive functions
- Access control using OpenZeppelin's Ownable pattern
- Circuit breakers using Pausable pattern
- Safe token transfers using SafeERC20
- Non-custodial design where possible

### Integration Flow

1. **Subscription Creation**: 
   - Service provider creates plans in SubscriptionManager
   - Users subscribe by paying for their desired plan

2. **Automation**:
   - SubscriptionKeeper monitors subscription expirations
   - Automatic renewals are processed if enabled

3. **Cross-Chain Usage**:
   - User subscribes on Chain A
   - CrossChainSubscriptionBridge verifies subscription status on Chain B
   - Service can be accessed on Chain B without additional payment

4. **Metered Billing**:
   - Service providers record usage through MeteredBilling
   - Billing is processed at the end of billing cycles
   - Users are charged based on actual usage

## Use Cases

This system can be used for various applications, including:

1. **SaaS Access Management**
   - Subscription-based access to API endpoints and web services
   - Usage-based billing for computing resources

2. **Content Platforms**
   - Subscription-based access to premium content
   - Creator payment distribution
   - Pay-per-view alongside subscription models

3. **DeFi Service Bundles**
   - Bundle access to multiple DeFi protocols
   - Single subscription for multiple services
   - Cross-chain access to various DeFi ecosystems

4. **Infrastructure and Resources**
   - Subscription-based access to decentralized computing
   - Storage billing based on actual usage
   - Network bandwidth consumption tracking

## Development Guide

### Prerequisites
- Foundry toolchain
- Solidity 0.8.20+
- OpenZeppelin Contracts
- Chainlink Contracts

### Project Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/on-chain-subscription-system.git
cd on-chain-subscription-system

# Install dependencies
forge install

# Build the project
forge build

# Run tests
forge test

# Deploy to testnet
forge script script/DeploySubscriptionSystem.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

### Key Configuration Options

The system can be configured in various ways:

- Payment tokens (ERC20 tokens for subscription payments)
- Grace periods for subscription renewals
- Treasury addresses for fee collection
- Billing cycle durations
- Price feed sources for different tokens
- Cross-chain selectors and CCIP router addresses

## Future Enhancements

The system can be extended with the following features:

1. **DAO Governance**
   - Allow subscribers to vote on platform features
   - Treasury management for protocol fees

2. **NFT-based Subscription Tiers**
   - Transferable subscription NFTs
   - Special subscriber benefits based on NFT holdings

3. **AI Integration**
   - Dynamic pricing based on service quality and demand
   - Predictive analytics for subscription management

4. **zkProof-based Privacy**
   - Private subscription verification
   - Anonymous usage tracking

## License

This project is licensed under the MIT License.

##
# Contract Documentation

## Core Contracts

### SubscriptionManager

The heart of the subscription system, responsible for managing subscription plans, processing payments, and tracking user subscriptions.

#### Key Features:
- **Plan Management**: Create, update, and manage subscription plans with different pricing and durations
- **Subscription Processing**: Handle user subscriptions, renewals, and cancellations
- **Payment Handling**: Process subscription payments using ERC20 tokens
- **Grace Periods**: Configurable grace periods for subscription renewals
- **Subscription Verification**: Check if users have active subscriptions

#### Example Usage:
```solidity
// Create a subscription plan
string[] memory features = new string[](2);
features[0] = "Feature 1";
features[1] = "Feature 2";
uint256 planId = subscriptionManager.createPlan(
    "Premium Plan",
    10 * 10**18, // 10 tokens
    30 days,
    features
);

// Subscribe to a plan
subscriptionManager.subscribe(planId, true); // With auto-renewal

// Check subscription status
bool isActive = subscriptionManager.isSubscribed(userAddress, planId);
```

### PriceFeedConsumer

Integrates with Chainlink Price Feeds to provide real-time token pricing information for dynamic subscription costs.

#### Key Features:
- **Real-time Pricing**: Fetch the latest price data for tokens
- **USD Conversion**: Convert between token amounts and USD values
- **Multiple Token Support**: Configure price feeds for various tokens

#### Example Usage:
```solidity
// Set price feed for a token
priceFeedConsumer.setPriceFeed(
    tokenAddress,
    priceFeedAddress
);

// Get latest price
int256 price = priceFeedConsumer.getLatestPrice(tokenAddress);

// Convert token amount to USD
uint256 usdValue = priceFeedConsumer.convertToUSD(
    tokenAddress,
    tokenAmount,
    18 // Token decimals
);
```

### SubscriptionKeeper

Utilizes Chainlink Automation to automate subscription renewals and management tasks.

#### Key Features:
- **Automated Renewals**: Process subscription renewals automatically when they're due
- **Batch Processing**: Handle multiple subscriptions in a single transaction
- **Failure Handling**: Retry logic for failed renewal attempts
- **Subscriber Management**: Register and manage subscribers to monitor

#### Example Usage:
```solidity
// The keeper checks which subscriptions need renewal
(bool upkeepNeeded, bytes memory performData) = subscriptionKeeper.checkUpkeep("0x");

// If upkeep is needed, perform the renewal
if (upkeepNeeded) {
    subscriptionKeeper.performUpkeep(performData);
}

// Manually attempt a renewal
bool success = subscriptionKeeper.manualRenewalAttempt(userAddress, planId);
```

### CrossChainSubscriptionBridge

Enables cross-chain subscription verification and management using Chainlink CCIP.

#### Key Features:
- **Cross-Chain Verification**: Verify subscription status across different chains
- **Status Synchronization**: Keep subscription status in sync between chains
- **Trusted Communication**: Secure message passing between trusted contracts

#### Example Usage:
```solidity
// Request validation of a subscription on another chain
bytes32 messageId = crossChainBridge.requestCrossChainValidation(
    destinationChainSelector,
    userAddress,
    planId
);

// Check if user has a subscription on another chain
bool hasSubscription = crossChainBridge.hasCrossChainSubscription(
    userAddress,
    planId
);
```

### MeteredBilling

Provides pay-as-you-go functionality for usage-based services alongside fixed subscriptions.

#### Key Features:
- **Usage Tracking**: Record and track usage for subscribers
- **Flexible Billing**: Bill users based on actual resource consumption
- **Min/Max Thresholds**: Configure minimum and maximum usage limits
- **Billing Cycles**: Manage recurring billing cycles for usage-based services

#### Example Usage:
```solidity
// Register a service
uint256 serviceId = meteredBilling.registerService(
    "API Calls",
    providerAddress,
    0.001 * 10**18, // Rate per unit
    100, // Minimum usage
    1000000, // Maximum usage
    true // Active
);

// Record usage for a user
meteredBilling.recordUsage(
    userAddress,
    serviceId,
    50 // 50 units used
);

// Settle billing cycle
uint256 billingAmount = meteredBilling.settleBillingCycle(
    userAddress,
    serviceId
);
```

## Development and Integration

### Subscription Flow

1. **Plan Creation**:
   Service providers create subscription plans using the SubscriptionManager.

2. **User Subscription**:
   Users subscribe to plans by calling the `subscribe` function and making a payment.

3. **Subscription Management**:
   Users can renew or cancel their subscriptions at any time.

4. **Automated Renewals**:
   The SubscriptionKeeper automatically processes renewals for subscriptions with auto-renewal enabled.

5. **Cross-Chain Access**:
   Users can verify their subscription status across different chains using the CrossChainSubscriptionBridge.

6. **Usage Tracking**:
   Service providers record user resource usage through the MeteredBilling contract.

7. **Billing Settlement**:
   Usage-based billing is settled at the end of billing cycles or when triggered manually.

### Integration Example

Here's how these contracts work together in a typical scenario:

```solidity
// 1. Create a subscription plan
uint256 planId = subscriptionManager.createPlan("Premium", 10 * 10**18, 30 days, features);

// 2. User subscribes to the plan
subscriptionManager.subscribe(planId, true);

// 3. Service provider registers a metered service
uint256 serviceId = meteredBilling.registerService("API Calls", provider, rate, min, max, true);

// 4. User consumes the service, and provider records usage
meteredBilling.recordUsage(userAddress, serviceId, amountUsed);

// 5. At the end of billing cycle, settle the usage-based charges
meteredBilling.settleBillingCycle(userAddress, serviceId);

// 6. When subscription nears expiration, the keeper automatically renews it
// (This happens in the Chainlink Automation network)

// 7. User wants to access service on another chain
crossChainBridge.requestCrossChainValidation(destinationChain, userAddress, planId);
```

### Security Considerations

- **Access Control**: Only authorized addresses can perform administrative functions
- **Payment Security**: All payments use SafeERC20 to prevent token transfer exploits
- **Reentrancy Protection**: Critical functions have reentrancy guards
- **Emergency Stops**: Pausable pattern allows for emergency contract freezing
- **Cross-Chain Trust**: Only trusted bridges can communicate cross-chain information

## Testing and Deployment

The system includes comprehensive tests and deployment scripts:

- Unit tests for individual contract functionality
- Integration tests for contract interactions
- Deployment scripts for various networks
- Configuration templates for different environments

## Best Practices

When extending or modifying the system:

1. Always run the full test suite before deploying changes
2. Use the `whenNotPaused` modifier for critical functions that should be stoppable
3. Add new features through extension rather than modification when possible
4. Verify all cross-chain interactions carefully
5. Implement proper error handling for external calls
6. Monitor Chainlink feed health for price consistency

##
# Chainlink Integration

This document explains how our on-chain subscription system leverages Chainlink's technology stack for enhanced functionality.

## Chainlink Price Feeds

### Overview
Our system uses Chainlink Price Feeds to access reliable, decentralized price data for various tokens. This enables dynamic subscription pricing and accurate conversion between cryptocurrencies and stable values.

### Implementation Details

The `PriceFeedConsumer` contract interfaces with Chainlink's Price Feed aggregators:

```solidity
// Import Chainlink interfaces
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// Get the latest price from a feed
function getLatestPrice(address _token) public view returns (int256 price) {
    AggregatorV3Interface priceFeed = priceFeeds[_token];
    
    // Get the latest round data
    (
        /* uint80 roundId */,
        int256 answer,
        /* uint256 startedAt */,
        /* uint256 updatedAt */,
        /* uint80 answeredInRound */
    ) = priceFeed.latestRoundData();
    
    return answer;
}
```

### Use Cases

1. **Dynamic Pricing**: Adjust subscription costs based on token value fluctuations
2. **Multi-Currency Support**: Allow payments in various tokens with consistent value
3. **Price Protection**: Set minimum USD-equivalent values for subscriptions

### Configuration

For each supported token, you need to set up the appropriate price feed:

| Network | Token | Price Feed Address |
|---------|-------|-------------------|
| Ethereum Mainnet | USDC | 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6 |
| Ethereum Mainnet | DAI | 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9 |
| Polygon | USDC | 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7 |

## Chainlink Automation

### Overview
We use Chainlink Automation (formerly Keepers) to automate subscription renewal processes. This ensures timely renewals without requiring manual intervention.

### Implementation Details

The `SubscriptionKeeper` contract implements the Chainlink Automation interface:

```solidity
// Import Automation interface
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

// Check if any subscriptions need renewal
function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
    // Logic to find subscriptions needing renewal
    // ...
    
    return (upkeepNeeded, performData);
}

// Process subscription renewals
function performUpkeep(bytes calldata performData) external override {
    // Logic to process renewals
    // ...
}
```

### Registration Process

To use Chainlink Automation:

1. Deploy the `SubscriptionKeeper` contract
2. Register it on the Chainlink Automation Network
3. Fund the upkeep with LINK tokens

### Monitoring and Maintenance

Monitor upkeep performance through:
- Chainlink Automation dashboard
- On-chain events emitted during renewal attempts
- Logs of successful and failed renewals

## Chainlink CCIP (Cross-Chain Interoperability Protocol)

### Overview
Our system leverages Chainlink CCIP to enable cross-chain subscription verification, allowing users to subscribe on one chain and access services on another.

### Implementation Details

The `CrossChainSubscriptionBridge` contract uses CCIP for secure message passing:

```solidity
// Import CCIP interfaces
import "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import "@chainlink/contracts/src/v0.8/ccip/CCIPReceiver.sol";

// Send a cross-chain validation request
function requestCrossChainValidation(
    uint64 _chainSelector,
    address _user,
    uint256 _planId
) external returns (bytes32 messageId) {
    // Prepare message data
    // ...
    
    // Send the CCIP message
    messageId = IRouterClient(getRouter()).ccipSend(
        _chainSelector,
        buildCCIPMessage(remoteBridge, data)
    );
    
    return messageId;
}

// Receive and process incoming CCIP messages
function _ccipReceive(
    Client.Any2EVMMessage memory message
) internal override {
    // Verify message source
    // Process message based on type
    // ...
}
```

### Supported Chains

CCIP supports several chains with these selectors:

| Chain | Selector |
|-------|----------|
| Ethereum | 5009297550715157269 |
| Polygon | 4051577828743386545 |
| Arbitrum | 4949039107694359620 |
| Optimism | 3734403246176062136 |
| Avalanche | 6433500567565415381 |

### Security Considerations

For secure cross-chain operations:

1. **Trusted Sources**: Only accept messages from trusted bridge contracts
2. **Message Verification**: Validate all incoming message data
3. **Rate Limiting**: Prevent spamming of cross-chain requests
4. **Fallback Mechanisms**: Handle failed cross-chain communications

## Best Practices for Chainlink Integration

1. **Redundancy**: For critical data, consider using multiple price feeds
2. **Heartbeat Checks**: Verify price feed data is recent and not stale
3. **Gas Optimization**: Batch operations when possible in Automation functions
4. **Link Funding**: Maintain adequate LINK balances for Automation and CCIP operations
5. **Monitoring**: Set up alerts for failed operations or unusual activity
6. **Testing**: Thoroughly test all Chainlink integrations on testnets before mainnet deployment

## Troubleshooting Common Issues

### Price Feeds
- **Stale Data**: Check the `updatedAt` timestamp from `latestRoundData()`
- **Feed Deviations**: Compare data with alternative sources if values seem incorrect

### Automation
- **Failed Upkeeps**: Check gas limits and contract state
- **Missed Renewals**: Verify the checkUpkeep logic correctly identifies all eligible subscriptions

### CCIP
- **Dropped Messages**: Monitor message status and implement retry mechanisms
- **Fee Issues**: Ensure sufficient LINK is available for cross-chain operations

## Resources

- [Chainlink Documentation](https://docs.chain.link/)
- [Price Feed Addresses](https://docs.chain.link/data-feeds/price-feeds/addresses)
- [Chainlink Automation Documentation](https://docs.chain.link/chainlink-automation)
- [CCIP Documentation](https://docs.chain.link/ccip)# on-chain-subscription-system
