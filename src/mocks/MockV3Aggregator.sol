// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockV3Aggregator
 * @dev Имитация оракула Chainlink для локального тестирования.
 * Позволяет вручную менять цену и время обновления (для проверки staleness).
 */
contract MockV3Aggregator {
    uint8 public decimals;
    int256 public latestAnswer;
    uint256 public latestTimestamp;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        latestAnswer = _initialAnswer;
        latestTimestamp = block.timestamp;
    }

    // Изменить текущую цену (имитация изменения рынка)
    function updateAnswer(int256 _answer) public {
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
    }

    // Искусственно состарить данные (для тестирования revert'а на staleness)
    function updateTimestamp(uint256 _timestamp) public {
        latestTimestamp = _timestamp;
    }

    // Стандартная функция интерфейса AggregatorV3
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, latestAnswer, latestTimestamp, latestTimestamp, 1);
    }
}
