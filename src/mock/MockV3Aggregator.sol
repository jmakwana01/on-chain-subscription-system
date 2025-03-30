// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockV3Aggregator
 * @notice Mock implementation of Chainlink's Price Feed Aggregator for testing
 */
contract MockV3Aggregator is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _answer;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;
    uint80 private _roundId;
    string private _description;
    uint256 private _version;

    constructor(uint8 decimals_, int256 initialAnswer_) {
        _decimals = decimals_;
        _answer = initialAnswer_;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
        _answeredInRound = 1;
        _roundId = 1;
        _description = "Mock Price Feed";
        _version = 1;
    }

    function updateAnswer(int256 newAnswer) external {
        _roundId++;
        _answer = newAnswer;
        _updatedAt = block.timestamp;
        _answeredInRound = _roundId;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external view override returns (uint256) {
        return _version;
    }

    function getRoundData(uint80 roundId_) external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (roundId_, _answer, _startedAt, _updatedAt, _answeredInRound);
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }
}