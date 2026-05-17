// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockAggregator
 * @notice Mock Chainlink AggregatorV3Interface for unit and fuzz tests.
 *         Allows setting arbitrary price, timestamp, and round data.
 */
contract MockAggregator {
    uint8 private _decimals;
    int256 private _answer;
    uint256 private _updatedAt;
    uint80 private _roundId;
    uint80 private _answeredInRound;

    constructor(uint8 dec, int256 initialAnswer) {
        _decimals = dec;
        _answer = initialAnswer;
        _updatedAt = block.timestamp;
        _roundId = 1;
        _answeredInRound = 1;
    }

    // =========================================================================
    // Test helpers
    // =========================================================================

    function setAnswer(int256 answer) external {
        _answer = answer;
        _updatedAt = block.timestamp;
        _roundId++;
        _answeredInRound = _roundId;
    }

    /// @dev Simulate a stale price by setting updatedAt in the past
    function setUpdatedAt(uint256 ts) external {
        _updatedAt = ts;
    }

    /// @dev Simulate an incomplete round
    function setAnsweredInRound(uint80 answeredInRound) external {
        _answeredInRound = answeredInRound;
    }

    function setRoundId(uint80 roundId) external {
        _roundId = roundId;
    }

    // =========================================================================
    // AggregatorV3Interface
    // =========================================================================

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }
}
