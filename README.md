# On-Chain Subscription System

> **⚠️ WORK IN PROGRESS**: This project is currently under active development.

**A blockchain-native subscription infrastructure enabling businesses to launch, manage, and scale subscription services across multiple chains with built-in metered billing.**

## The Problem

Traditional subscription systems face several key challenges:

1. **Centralized Payment Processing** - Reliance on payment processors that charge high fees and can block or reverse transactions
2. **Geographic Limitations** - Inability to serve global customers due to banking restrictions
3. **Management Overhead** - Complex systems to track subscription status, renewals, and cancellations
4. **Cross-Border Complications** - Currency conversion issues and international payment friction
5. **Data Silos** - Subscription data locked in proprietary systems making cross-platform integration difficult


## Our Solution

This on-chain subscription system solves these challenges by providing a fully decentralized, trustless subscription management infrastructure with these core capabilities:

- **Sovereign Subscription Management** - Businesses can create and manage subscription plans without dependence on third-party processors
- **Programmable Billing Models** - Support for fixed-term subscriptions, usage-based billing, and hybrid approaches
- **Cross-Chain Compatibility** - Unified subscription experience across multiple blockchains
- **Automated Operations** - Chainlink-powered automation for renewals and billing cycles
- **Transparent Pricing** - Price feed integration for stable-value billing regardless of token volatility

## Key Components

### 1. SubscriptionManager

The backbone of the system handling:
- Plan creation and management with customizable features and tiers
- Secure subscription lifecycle (creation, renewal, cancellation)
- Flexible payment terms with configurable grace periods
- Subscription status verification for gating access to services

```solidity
// Create a new subscription plan
function createPlan(
    string memory _name,
    uint256 _price,
    uint256 _duration,
    string[] memory _features
) external onlyOwner returns (uint256 planId);

// User subscribes to a plan
function subscribe(uint256 _planId, bool _autoRenew) external nonReentrant;
```

### 2. MeteredBilling

Extends the core subscription system with pay-as-you-go functionality:
- Usage tracking per user and service
- Configurable usage tiers with minimum and maximum thresholds
- Automatic billing cycle settlement
- Batch operations for gas efficiency

```solidity
// Record usage for a service
function recordUsage(
    address _user,
    uint256 _serviceId,
    uint256 _amount
) external;

// Calculate and settle billing for a cycle
function settleBillingCycle(
    address _user,
    uint256 _serviceId
) external returns (uint256 billingAmount);
```

### 3. CrossChainSubscriptionBridge

Enables multi-chain subscription capabilities:
- Validate subscription status across different blockchains
- Synchronize subscription changes between chains
- Secure message passing using Chainlink CCIP
- Subscription portability for users across the blockchain ecosystem

```solidity
// Request validation from another chain
function requestCrossChainValidation(
    uint64 _chainSelector,
    address _user,
    uint256 _planId
) external returns (bytes32 messageId);

// Update subscription status across chains
function sendCrossChainStatusUpdate(
    uint64 _chainSelector,
    address _user,
    uint256 _planId,
    bool _isActive
) external returns (bytes32 messageId);
```

### 4. SubscriptionKeeper & PriceFeedConsumer

Chainlink integrations that enhance the system:
- Automated subscription renewals at predetermined intervals
- Token price conversion for stable value subscriptions
- Batch processing of renewals for multiple users
- Fail-safe mechanisms for failed renewals

## Technical Highlights

- **Full ERC20 Compatibility** - Works with any standard ERC20 token for payments
- **Gas Optimized** - Batch operations and efficient storage patterns
- **Robust Security** - ReentrancyGuard, access control, and circuit breaker patterns
- **Flexible Integration** - Easy to connect with existing dApps and services
- **Comprehensive Testing** - Extensive unit and integration test coverage

## Real-World Applications

### Web3 SaaS Platforms
Enable tiered access to decentralized applications with automatic renewals and usage tracking.

### API & Data Services
Monetize API endpoints or data feeds with consumption-based billing while tracking usage patterns.

### Content Platforms
Create premium content tiers with subscription-based access controls across multiple blockchain networks.

### Gaming & Metaverse
Implement subscription models for in-game benefits or metaverse access with cross-chain identity.

### DeFi Services
Offer premium features for DeFi platforms like reduced fees, advanced trading tools, or priority access.

## Implementation Example

Here's how a service might implement this system:

1. **Setup subscription plans** with different price points and feature sets
2. **Configure metered services** for usage-based components like API calls or storage
3. **Deploy across multiple chains** using the CrossChainSubscriptionBridge
4. **Connect the SubscriptionKeeper** to automate renewal processes
5. **Integrate PriceFeedConsumer** to maintain stable pricing despite token volatility

Users can then:
1. Subscribe to plans using supported tokens
2. Consume services that track usage automatically
3. Move between chains while maintaining subscription status
4. Enable auto-renewal for uninterrupted service
5. Upgrade, downgrade or cancel subscriptions as needed

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────────┐
│                        User / Client                           │
└─────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│                      Subscription Manager                      │
│                                                                │
│  ┌─────────────────┐   ┌─────────────────┐   ┌──────────────┐  │
│  │  Plan Registry  │   │ User Subscript. │   │ Payment Proc │  │
│  └─────────────────┘   └─────────────────┘   └──────────────┘  │
└────────────┬───────────────────┬──────────────────┬────────────┘
             │                   │                  │
             ▼                   ▼                  ▼
┌────────────────────┐ ┌─────────────────┐ ┌─────────────────────┐
│                    │ │                 │ │                     │
│   Metered Billing  │ │ Cross-Chain     │ │  Subscription       │
│                    │ │ Bridge          │ │  Keeper             │
│   ┌─────────────┐  │ │ ┌─────────────┐ │ │  ┌─────────────┐    │
│   │Usage Records│  │ │ │CCIP Messages│ │ │  │Auto Renewals│    │
│   └─────────────┘  │ │ └─────────────┘ │ │  └─────────────┘    │
└────────────────────┘ └─────────────────┘ └─────────────────────┘
```

## Development

### Prerequisites

- Foundry for development and testing
- Chainlink contracts for oracle and automation integration
- OpenZeppelin contracts for security and utility functions

### Project Structure

```
on-chain-subscription-system/
├── src/
│   ├── core/
│   │   ├── SubscriptionManager.sol  - Core subscription functionality
│   │   └── MeteredBilling.sol       - Usage-based billing extensions
│   ├── bridge/
│   │   └── CrossChainSubscriptionBridge.sol - Cross-chain logic
│   └── chainlink/
│       ├── SubscriptionKeeper.sol   - Automation integration
│       └── PriceFeedConsumer.sol    - Price oracle integration
├── test/
│   ├── unit/                        - Component-level tests
│   └── integration/                 - System-level tests
└── script/                          - Deployment scripts
```

## Why It Matters

The On-Chain Subscription System represents a fundamental building block for sustainable Web3 business models. By providing the infrastructure for recurring revenue, it enables:

- **Business Model Innovation** - New ways to monetize decentralized services
- **Global Accessibility** - Borderless subscription services for anyone with a wallet
- **Transparent Commerce** - Clear, immutable records of subscription terms and usage
- **Reduced Overhead** - Automated operations without payment processing intermediaries
- **Composable Economics** - Subscription components that can integrate with other DeFi and Web3 systems

This system bridges the gap between traditional subscription commerce and blockchain capabilities, creating possibilities for sustainable revenue models in the decentralized ecosystem.

