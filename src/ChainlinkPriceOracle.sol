// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

// Minimal Chainlink AggregatorV3 interface
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/**
 * @title ChainlinkPriceOracle
 * @notice Adapter around Chainlink AggregatorV3 with strict staleness check.
 *
 * @dev Security requirements met:
 *      - Reverts if price is older than `stalenessThreshold` seconds.
 *      - Reverts if answer <= 0 (invalid price).
 *      - Reverts if answeredInRound < roundId (incomplete round).
 *      - No use of block.timestamp as randomness.
 *      - Role-gated feed updates (only ORACLE_ADMIN_ROLE).
 *
 * Oracle attack mitigations (documented in audit report):
 *      - Staleness guard: rejects prices older than N seconds.
 *      - Negative/zero price guard: rejects invalid answers.
 *      - Round completeness guard: rejects data from incomplete rounds.
 */
contract ChainlinkPriceOracle is AccessControl {
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");

    // =========================================================================
    // State
    // =========================================================================

    /// @notice Chainlink price feed for RWA/USD
    AggregatorV3Interface public priceFeed;

    /// @notice Chainlink Proof of Reserve feed (verifies real-world collateral)
    AggregatorV3Interface public porFeed;

    /// @notice Max age (seconds) a price answer may have before being rejected
    uint256 public stalenessThreshold;

    // =========================================================================
    // Events
    // =========================================================================

    event PriceFeedUpdated(address oldFeed, address newFeed);
    event PoRFeedUpdated(address oldFeed, address newFeed);
    event StalenessThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // =========================================================================
    // Errors
    // =========================================================================

    error StalePrice(uint256 updatedAt, uint256 currentTime, uint256 threshold);
    error InvalidPrice(int256 answer);
    error IncompleteRound(uint80 roundId, uint80 answeredInRound);
    error ZeroAddress();

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(address _priceFeed, address _porFeed, uint256 _stalenessThreshold, address _admin) {
        if (_priceFeed == address(0) || _admin == address(0)) revert ZeroAddress();

        priceFeed = AggregatorV3Interface(_priceFeed);
        if (_porFeed != address(0)) {
            porFeed = AggregatorV3Interface(_porFeed);
        }
        stalenessThreshold = _stalenessThreshold;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ORACLE_ADMIN_ROLE, _admin);
    }

    // =========================================================================
    // Admin
    // =========================================================================

    function setPriceFeed(address newFeed) external onlyRole(ORACLE_ADMIN_ROLE) {
        if (newFeed == address(0)) revert ZeroAddress();
        emit PriceFeedUpdated(address(priceFeed), newFeed);
        priceFeed = AggregatorV3Interface(newFeed);
    }

    function setPoRFeed(address newFeed) external onlyRole(ORACLE_ADMIN_ROLE) {
        emit PoRFeedUpdated(address(porFeed), newFeed);
        porFeed = AggregatorV3Interface(newFeed);
    }

    function setStalenessThreshold(uint256 newThreshold) external onlyRole(ORACLE_ADMIN_ROLE) {
        emit StalenessThresholdUpdated(stalenessThreshold, newThreshold);
        stalenessThreshold = newThreshold;
    }

    // =========================================================================
    // Price queries
    // =========================================================================

    /**
     * @notice Get the latest RWA/USD price.
     * @return price   18-decimal normalised price.
     * @return updatedAt  Timestamp of the price update.
     */
    function getPrice() external view returns (uint256 price, uint256 updatedAt) {
        (price, updatedAt) = _getValidatedPrice(priceFeed);
    }

    /**
     * @notice Get the latest Proof of Reserve value.
     * @return reserve  18-decimal normalised reserve value.
     * @return updatedAt  Timestamp of the PoR update.
     */
    function getProofOfReserve() external view returns (uint256 reserve, uint256 updatedAt) {
        require(address(porFeed) != address(0), "Oracle: PoR feed not set");
        (reserve, updatedAt) = _getValidatedPrice(porFeed);
    }

    /**
     * @notice Convenience: get price and PoR in one call, verify collateral ratio.
     * @return price      RWA/USD price (18 dec).
     * @return reserve    Proof of Reserve (18 dec).
     * @return isCollateralised  True if reserve >= price (1:1 backing).
     */
    function getPriceAndReserve() external view returns (uint256 price, uint256 reserve, bool isCollateralised) {
        (price,) = _getValidatedPrice(priceFeed);
        if (address(porFeed) != address(0)) {
            (reserve,) = _getValidatedPrice(porFeed);
            isCollateralised = reserve >= price;
        }
    }

    // =========================================================================
    // Internal: validated price fetch
    // =========================================================================

    /**
     * @dev Fetches and validates a Chainlink round:
     *      1. answer > 0
     *      2. updatedAt is within stalenessThreshold
     *      3. answeredInRound >= roundId (round is complete)
     *      Returns price normalised to 18 decimals.
     */
    function _getValidatedPrice(AggregatorV3Interface feed) internal view returns (uint256 price18, uint256 updatedAt) {
        (uint80 roundId, int256 answer,, uint256 _updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        // Guard 1: valid answer
        if (answer <= 0) revert InvalidPrice(answer);

        // Guard 2: staleness
        if (block.timestamp - _updatedAt > stalenessThreshold) {
            revert StalePrice(_updatedAt, block.timestamp, stalenessThreshold);
        }

        // Guard 3: round completeness
        if (answeredInRound < roundId) revert IncompleteRound(roundId, answeredInRound);

        updatedAt = _updatedAt;

        // Normalise to 18 decimals
        uint8 dec = feed.decimals();
        if (dec < 18) {
            price18 = uint256(answer) * (10 ** (18 - dec));
        } else if (dec > 18) {
            price18 = uint256(answer) / (10 ** (dec - 18));
        } else {
            price18 = uint256(answer);
        }
    }

    // slither-disable-next-line timestamp
        if (block.timestamp - _updatedAt > stalenessThreshold) {
    revert StalePrice(_updatedAt, block.timestamp, stalenessThreshold);
}
}
