// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import "lib/chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "lib/chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import "../core/SubscriptionManager.sol";

/**
 * @title CrossChainSubscriptionBridge
 * @author Jay Makwana
 * @notice Manages cross-chain subscription validations and status updates
 * @dev Uses Chainlink CCIP for secure cross-chain communication
 */
contract CrossChainSubscriptionBridge is Ownable, Pausable, ReentrancyGuard, CCIPReceiver {
    using SafeERC20 for IERC20;

    /**
     * @notice Event emitted when a cross-chain subscription validation request is sent
     * @param messageId CCIP message ID
     * @param destinationChainSelector The chain selector for the destination chain
     * @param receiver The address of the receiver on the destination chain
     * @param user The address of the subscriber
     * @param planId The ID of the subscription plan
     */
    event CrossChainValidationSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed receiver,
        address user,
        uint256 planId
    );

    /**
     * @notice Event emitted when a cross-chain subscription validation request is received
     * @param messageId CCIP message ID
     * @param sourceChainSelector The chain selector for the source chain
     * @param sender The address of the sender on the source chain
     * @param user The address of the subscriber
     * @param planId The ID of the subscription plan
     * @param isActive Whether the subscription is active
     */
    event CrossChainValidationReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address indexed sender,
        address user,
        uint256 planId,
        bool isActive
    );

    /**
     * @notice Event emitted when a cross-chain subscription status update is sent
     * @param messageId CCIP message ID
     * @param destinationChainSelector The chain selector for the destination chain
     * @param receiver The address of the receiver on the destination chain
     * @param user The address of the subscriber
     * @param planId The ID of the subscription plan
     * @param isActive Whether the subscription is active
     */
    event CrossChainStatusUpdateSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed receiver,
        address user,
        uint256 planId,
        bool isActive
    );

    /**
     * @notice Event emitted when a cross-chain subscription status update is received
     * @param messageId CCIP message ID
     * @param sourceChainSelector The chain selector for the source chain
     * @param sender The address of the sender on the source chain
     * @param user The address of the subscriber
     * @param planId The ID of the subscription plan
     * @param isActive Whether the subscription is active
     */
    event CrossChainStatusUpdateReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address indexed sender,
        address user,
        uint256 planId,
        bool isActive
    );

    /**
     * @dev Struct for a cross-chain message
     * @param messageType Type of message (1 = validation request, 2 = status update)
     * @param user Address of the subscriber
     * @param planId ID of the subscription plan
     * @param isActive Whether the subscription is active (only used for status updates)
     */
    struct CCIPMessage {
        uint256 messageType;
        address user;
        uint256 planId;
        bool isActive;
    }

    /**
     * @dev Reference to the local SubscriptionManager contract
     */
    SubscriptionManager public subscriptionManager;

    /**
     * @dev Token used for paying CCIP fees
     */
    IERC20 public linkToken;

    /**
     * @dev Mapping from chain selector to bridge contract address on that chain
     */
    mapping(uint64 => address) public remoteBridges;

    /**
     * @dev Mapping from chain selector + remote bridge address to whether it's trusted
     */
    mapping(uint64 => mapping(address => bool)) public trustedRemoteBridges;

    /**
     * @dev Mapping from user address + plan ID to whether they have a subscription on another chain
     */
    mapping(address => mapping(uint256 => bool)) public crossChainSubscriptions;

    /**
     * @notice Initializes the bridge contract
     * @param _subscriptionManager Address of the subscription manager contract
     * @param _router Address of the Chainlink CCIP router
     * @param _linkToken Address of the LINK token contract
     */
    constructor(
        address _subscriptionManager,
        address _router,
        address _linkToken
    ) CCIPReceiver(_router) Ownable(msg.sender) {
        require(_subscriptionManager != address(0), "Invalid subscription manager");
        require(_router != address(0), "Invalid router address");
        require(_linkToken != address(0), "Invalid LINK token address");
        
        subscriptionManager = SubscriptionManager(_subscriptionManager);
        linkToken = IERC20(_linkToken);
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
     * @notice Sets the LINK token address
     * @param _linkToken New LINK token address
     */
    function setLinkToken(address _linkToken) external onlyOwner {
        require(_linkToken != address(0), "Invalid LINK token address");
        linkToken = IERC20(_linkToken);
    }

    /**
     * @notice Adds or updates a remote bridge
     * @param _chainSelector Chain selector for the destination chain
     * @param _remoteBridge Address of the bridge on the destination chain
     * @param _trusted Whether the remote bridge is trusted
     */
    function setRemoteBridge(
        uint64 _chainSelector,
        address _remoteBridge,
        bool _trusted
    ) external onlyOwner {
        require(_chainSelector != 0, "Invalid chain selector");
        require(_remoteBridge != address(0), "Invalid remote bridge");
        
        remoteBridges[_chainSelector] = _remoteBridge;
        trustedRemoteBridges[_chainSelector][_remoteBridge] = _trusted;
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

    /**
     * @notice Withdraws LINK tokens from the contract
     * @param _amount Amount of LINK to withdraw
     */
    function withdrawLink(uint256 _amount) external onlyOwner {
        linkToken.safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice Sends a cross-chain subscription validation request
     * @param _chainSelector Chain selector for the destination chain
     * @param _user Address of the subscriber
     * @param _planId ID of the subscription plan
     * @return messageId CCIP message ID
     */
    function requestCrossChainValidation(
        uint64 _chainSelector,
        address _user,
        uint256 _planId
    ) external nonReentrant whenNotPaused returns (bytes32 messageId) {
        require(_chainSelector != 0, "Invalid chain selector");
        require(_user != address(0), "Invalid user address");
        require(_planId > 0, "Invalid plan ID");
        
        address remoteBridge = remoteBridges[_chainSelector];
        require(remoteBridge != address(0), "Remote bridge not configured");
        
        // Prepare the message data
        CCIPMessage memory message = CCIPMessage({
            messageType: 1, // Validation request
            user: _user,
            planId: _planId,
            isActive: false // Not used for validation requests
        });
        
        bytes memory data = abi.encode(message);
        
        // Calculate CCIP fees
        uint256 fees = IRouterClient(getRouter()).getFee(_chainSelector, buildCCIPMessage(remoteBridge, data));
        require(linkToken.balanceOf(address(this)) >= fees, "Insufficient LINK for fees");
        
        // Approve the router to spend LINK
        linkToken.approve(getRouter(), fees);
        
        // Send the CCIP message
        messageId = IRouterClient(getRouter()).ccipSend(
            _chainSelector,
            buildCCIPMessage(remoteBridge, data)
        );
        
        emit CrossChainValidationSent(
            messageId,
            _chainSelector,
            remoteBridge,
            _user,
            _planId
        );
        
        return messageId;
    }

    /**
     * @notice Sends a cross-chain subscription status update
     * @param _chainSelector Chain selector for the destination chain
     * @param _user Address of the subscriber
     * @param _planId ID of the subscription plan
     * @param _isActive Whether the subscription is active
     * @return messageId CCIP message ID
     */
    function sendCrossChainStatusUpdate(
        uint64 _chainSelector,
        address _user,
        uint256 _planId,
        bool _isActive
    )  public nonReentrant whenNotPaused returns (bytes32 messageId) {
        require(_chainSelector != 0, "Invalid chain selector");
        require(_user != address(0), "Invalid user address");
        require(_planId > 0, "Invalid plan ID");
        
        address remoteBridge = remoteBridges[_chainSelector];
        require(remoteBridge != address(0), "Remote bridge not configured");
        
        // If message sender is not the subscription manager, they must be the owner
        if (msg.sender != address(subscriptionManager)) {
            require(msg.sender == owner(), "Unauthorized");
        }
        
        // Prepare the message data
        CCIPMessage memory message = CCIPMessage({
            messageType: 2, // Status update
            user: _user,
            planId: _planId,
            isActive: _isActive
        });
        
        bytes memory data = abi.encode(message);
        
        // Calculate CCIP fees
        uint256 fees = IRouterClient(getRouter()).getFee(_chainSelector, buildCCIPMessage(remoteBridge, data));
        require(linkToken.balanceOf(address(this)) >= fees, "Insufficient LINK for fees");
        
        // Approve the router to spend LINK
        linkToken.approve(getRouter(), fees);
        
        // Send the CCIP message
        messageId = IRouterClient(getRouter()).ccipSend(
            _chainSelector,
            buildCCIPMessage(remoteBridge, data)
        );
        
        emit CrossChainStatusUpdateSent(
            messageId,
            _chainSelector,
            remoteBridge,
            _user,
            _planId,
            _isActive
        );
        
        return messageId;
    }

    /**
     * @notice Manually sets a cross-chain subscription status
     * @param _user Address of the subscriber
     * @param _planId ID of the subscription plan
     * @param _isActive Whether the subscription is active
     */
    function setManualCrossChainStatus(
        address _user,
        uint256 _planId,
        bool _isActive
    ) external onlyOwner {
        require(_user != address(0), "Invalid user address");
        require(_planId > 0, "Invalid plan ID");
        
        crossChainSubscriptions[_user][_planId] = _isActive;
    }

    /**
     * @notice Handles incoming CCIP messages
     * @param message The CCIP message
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override whenNotPaused {
        // Verify that the message is from a trusted source
        require(
            trustedRemoteBridges[message.sourceChainSelector][abi.decode(message.sender, (address))],
            "Sender not trusted"
        );
        
        // Decode the message data
        CCIPMessage memory ccipMessage = abi.decode(message.data, (CCIPMessage));
        
        if (ccipMessage.messageType == 1) {
            // Handle validation request
            handleValidationRequest(
                message.messageId,
                message.sourceChainSelector,
                abi.decode(message.sender, (address)),
                ccipMessage.user,
                ccipMessage.planId
            );
        } else if (ccipMessage.messageType == 2) {
            // Handle status update
            handleStatusUpdate(
                message.messageId,
                message.sourceChainSelector,
                abi.decode(message.sender, (address)),
                ccipMessage.user,
                ccipMessage.planId,
                ccipMessage.isActive
            );
        } else {
            revert("Unknown message type");
        }
    }

    /**
     * @notice Handles a validation request message
     * @param _messageId CCIP message ID
     * @param _sourceChainSelector Source chain selector
     * @param _sender Sender address on the source chain
     * @param _user User address to validate
     * @param _planId Plan ID to validate
     */
    function handleValidationRequest(
        bytes32 _messageId,
        uint64 _sourceChainSelector,
        address _sender,
        address _user,
        uint256 _planId
    ) internal {
        // Check if the user has an active subscription
        bool isActive = subscriptionManager.isSubscribed(_user, _planId);
        
        emit CrossChainValidationReceived(
            _messageId,
            _sourceChainSelector,
            _sender,
            _user,
            _planId,
            isActive
        );
        
        // Send the status back
        sendCrossChainStatusUpdate(
            _sourceChainSelector,
            _user,
            _planId,
            isActive
        );
    }

    /**
     * @notice Handles a status update message
     * @param _messageId CCIP message ID
     * @param _sourceChainSelector Source chain selector
     * @param _sender Sender address on the source chain
     * @param _user User address
     * @param _planId Plan ID
     * @param _isActive Whether the subscription is active
     */
    function handleStatusUpdate(
        bytes32 _messageId,
        uint64 _sourceChainSelector,
        address _sender,
        address _user,
        uint256 _planId,
        bool _isActive
    ) internal {
        // Update the cross-chain subscription status
        crossChainSubscriptions[_user][_planId] = _isActive;
        
        emit CrossChainStatusUpdateReceived(
            _messageId,
            _sourceChainSelector,
            _sender,
            _user,
            _planId,
            _isActive
        );
    }

    /**
     * @notice Checks if a user has an active cross-chain subscription
     * @param _user Address of the user
     * @param _planId ID of the plan
     * @return isSubscribed Whether the user has an active cross-chain subscription
     */
    function hasCrossChainSubscription(
        address _user,
        uint256 _planId
    ) external view returns (bool isSubscribed) {
        return crossChainSubscriptions[_user][_planId];
    }

    /**
     * @notice Builds a CCIP message
     * @param _receiver Address of the receiver
     * @param _data Message data
     * @return Client.EVM2AnyMessage CCIP message
     */
    function buildCCIPMessage(
        address _receiver,
        bytes memory _data
    ) internal view returns (Client.EVM2AnyMessage memory) {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: _data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000})
            ),
            feeToken: address(linkToken) // Use LINK token for fees
        });
    }
}