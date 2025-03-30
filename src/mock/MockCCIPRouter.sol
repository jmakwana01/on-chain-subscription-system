// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import "lib/chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

/**
 * @title MockCCIPRouter
 * @notice Mock implementation of Chainlink's CCIP Router for testing cross-chain functionality
 */
contract MockCCIPRouter is IRouterClient {
    mapping(uint64 => address) public remoteRouters;
    mapping(bytes32 => bool) public sentMessages;
    
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        bytes data,
        address feeToken,
        uint256 fees
    );
    
    /**
     * @notice Set up a remote router for testing
     * @param _chainSelector Chain selector for the destination chain
     * @param _router Address of the remote router
     */
    function setRemoteRouter(uint64 _chainSelector, address _router) external {
        remoteRouters[_chainSelector] = _router;
    }
    
    /**
     * @notice Mock implementation of ccipSend
     * @param _destinationChainSelector The chain selector of the destination chain
     * @param _message The message to be sent
     * @return messageId The ID of the message
     */
    function ccipSend(
        uint64 _destinationChainSelector,
        Client.EVM2AnyMessage memory _message
    ) external payable override returns (bytes32 messageId) {
        // Generate a unique message ID
        messageId = keccak256(
            abi.encode(
                _destinationChainSelector,
                abi.decode(_message.receiver, (address)),
                _message.data,
                block.timestamp,
                msg.sender
            )
        );
        
        // Mark message as sent
        sentMessages[messageId] = true;
        
        // Get remote router
        address remoteRouter = remoteRouters[_destinationChainSelector];
        require(remoteRouter != address(0), "Remote router not configured");
        
        // Extract receiver address
        address receiver = abi.decode(_message.receiver, (address));
        
        // Extract fee token (if any)
        address feeToken = _message.feeToken;
        
        // Emit event
        emit MessageSent(
            messageId,
            _destinationChainSelector,
            receiver,
            _message.data,
            feeToken,
            0 // Fees are mocked as 0
        );
        
        // Simulate the message receipt on the destination chain
        // This is for testing purposes only
        MockCCIPRouter(remoteRouter).receiveMessage(
            messageId,
            uint64(block.chainid), // Current chain ID as source
            msg.sender,            // Current sender
            receiver,              // Target receiver
            _message.data          // Message data
        );
        
        return messageId;
    }
    
    /**
     * @notice Mock function to simulate receiving a CCIP message
     * @param _messageId The ID of the message
     * @param _sourceChainSelector The chain selector of the source chain
     * @param _sender The address of the sender
     * @param _receiver The address of the receiver
     * @param _data The message data
     */
    function receiveMessage(
        bytes32 _messageId,
        uint64 _sourceChainSelector,
        address _sender,
        address _receiver,
        bytes memory _data
    ) external {
        // Create the Any2EVMMessage
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage(
            _messageId,
            _sourceChainSelector,
            abi.encode(_sender),
            _data,
            new Client.EVMTokenAmount[](0)
        );
        
        // Call the _ccipReceive function on the receiver contract
        // This will simulate the message being received on the destination chain
        bytes memory callData = abi.encodeWithSignature(
            "_ccipReceive((bytes32,uint64,bytes,bytes,(address,uint256)[]))",
            message
        );
        
        (bool success, ) = _receiver.call(callData);
        require(success, "Failed to deliver message");
    }
    
    /**
     * @notice Mock implementation of getFee
     * @param _destinationChainSelector The chain selector of the destination chain
     * @param _message The message to be sent
     * @return fee The calculated fee (always returns 0.01 LINK for testing)
     */
    function getFee(
        uint64 _destinationChainSelector,
        Client.EVM2AnyMessage memory _message
    ) external view override returns (uint256 fee) {
        // Return a small fixed fee for testing purposes
        return 0.01 * 10**18; // 0.01 LINK
    }
    
    /**
     * @notice Check if a chain selector is supported
     * @param _chainSelector The chain selector to check
     * @return supported Always returns true for testing
     */
    function isChainSupported(uint64 _chainSelector) external view override returns (bool supported) {
        return remoteRouters[_chainSelector] != address(0);
    }
    
    /**
     * @notice Get the authorized senders
     * @return senders Empty array for testing
     */
    function getAuthorizedSenders() external view returns (address[] memory senders) {
        // Return empty array for testing
        return new address[](0);
    }
    
    /**
     * @notice Check if a sender is authorized
     * @param _sender The sender to check
     * @return authorized Always returns true for testing
     */
    function isAuthorizedSender(address _sender) external pure returns (bool authorized) {
        // All senders are authorized for testing
        return true;
    }
}