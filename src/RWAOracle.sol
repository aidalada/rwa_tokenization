// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract RWAOracle {
    AggregatorV3Interface public immutable PRICE_FEED;
    AggregatorV3Interface public immutable RESERVE_FEED;

    uint256 public constant TIMEOUT = 1 hours;

    constructor(address _priceFeed, address _reserveFeed) {
        PRICE_FEED = AggregatorV3Interface(_priceFeed);
        RESERVE_FEED = AggregatorV3Interface(_reserveFeed);
    }

    function getLatestPrice() public view returns (int256) {
        (uint80 roundId, int256 price,, uint256 updatedAt, uint80 answeredInRound) = PRICE_FEED.latestRoundData();

        require(price > 0, "Oracle: Negative or zero price");
        require(updatedAt != 0, "Oracle: Incomplete round");
        require(answeredInRound >= roundId, "Oracle: Stale round");
        require(block.timestamp - updatedAt <= TIMEOUT, "Oracle: Price data is stale");

        return price;
    }

    function getProofOfReserve() public view returns (int256) {
        (, int256 reserve,, uint256 updatedAt,) = RESERVE_FEED.latestRoundData();

        require(reserve >= 0, "Oracle: Invalid reserve amount");
        require(block.timestamp - updatedAt <= TIMEOUT, "Oracle: Reserve data is stale");

        return reserve;
    }
}
