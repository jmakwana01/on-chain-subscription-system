// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
/**
 * @title PriceFeedConsumer
 * @author Jay Makwana
 * @notice Contract for interacting with Chainlink Price Feeds to get token pricing
 * @dev Integrates with Chainlink oracles to obtain real-time price data
 */
contract PriceFeedConsumer is Ownable {
    /**
     * @notice Event emitted when a new price feed is set for a token
     * @param token Address of the token
     * @param priceFeed Address of the Chainlink price feed
     */
    event PriceFeedSet(address indexed token, address indexed priceFeed);

    /**
     * @dev Mapping from token address to its corresponding Chainlink price feed
     */
    mapping(address => AggregatorV3Interface) public priceFeeds;

    /**
     * @dev Mapping to track decimal places for each price feed
     */
    mapping(address => uint8) public priceFeedDecimals;

    /**
     * @notice Initializes the contract with the contract owner
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Sets or updates the price feed for a token
     * @param _token Address of the token
     * @param _priceFeed Address of the Chainlink price feed contract
     */
    function setPriceFeed(address _token, address _priceFeed) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(_priceFeed != address(0), "Invalid price feed address");
        
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeed);
        priceFeeds[_token] = priceFeed;
        priceFeedDecimals[_token] = priceFeed.decimals();
        
        emit PriceFeedSet(_token, _priceFeed);
    }

    /**
     * @notice Retrieves the latest price for a token in USD
     * @param _token Address of the token
     * @return price Latest price in USD with 8 decimals
     */
    function getLatestPrice(address _token) public view returns (int256 price) {
        AggregatorV3Interface priceFeed = priceFeeds[_token];
        require(address(priceFeed) != address(0), "Price feed not set for token");
        
        // Get the latest round data
        (
            /* uint80 roundId */,
            int256 answer,
            /* uint256 startedAt */,
            /* uint256 updatedAt */,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();
        
        require(answer > 0, "Invalid price feed response");
        
        return answer;
    }

    /**
     * @notice Converts an amount of tokens to USD value
     * @param _token Address of the token
     * @param _amount Amount of tokens (in token's smallest unit)
     * @param _tokenDecimals Decimal places of the token
     * @return usdValue Value in USD with 8 decimal places
     */
    function convertToUSD(
        address _token,
        uint256 _amount,
        uint8 _tokenDecimals
    ) public view returns (uint256 usdValue) {
        int256 price = getLatestPrice(_token);
        require(price > 0, "Price must be positive");
        
        // Handle decimal adjustment
        uint8 priceFeedDecimal = priceFeedDecimals[_token];
        
        // Convert amount to USD
        // Formula: (amount * price) / 10^tokenDecimals
        usdValue = ((_amount * uint256(price)) / (10**_tokenDecimals));
        
        return usdValue;
    }

    /**
     * @notice Converts a USD value to an amount of tokens
     * @param _token Address of the token
     * @param _usdAmount Amount in USD with 8 decimal places
     * @param _tokenDecimals Decimal places of the token
     * @return tokenAmount Amount of tokens in token's smallest unit
     */
    function convertFromUSD(
        address _token,
        uint256 _usdAmount,
        uint8 _tokenDecimals
    ) public view returns (uint256 tokenAmount) {
        int256 price = getLatestPrice(_token);
        require(price > 0, "Price must be positive");
        
        // Convert USD to token amount
        // Formula: (usdAmount * 10^tokenDecimals) / price
        tokenAmount = ((_usdAmount * (10**_tokenDecimals)) / uint256(price));
        
        return tokenAmount;
    }

    /**
     * @notice Gets information about a price feed
     * @param _token Address of the token
     * @return feed Address of the price feed
     * @return decimals Number of decimals used in the price feed
     * @return description Human-readable description of the price feed
     */
    function getPriceFeedInfo(address _token) 
        external 
        view 
        returns (
            address feed, 
            uint8 decimals, 
            string memory description
        ) 
    {
        AggregatorV3Interface priceFeed = priceFeeds[_token];
        require(address(priceFeed) != address(0), "Price feed not set for token");
        
        return (
            address(priceFeed),
            priceFeed.decimals(),
            priceFeed.description()
        );
    }
}