// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {RWAYieldVault} from "../src/RWAYieldVault.sol";
import {RWAAMM} from "../src/RWAAMM.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title ForkTest
 * @notice Fork tests against real mainnet/testnet contracts.
 *
 * Run with:
 *   forge test --match-contract ForkTest --fork-url $ETH_RPC_URL -vvv
 *
 * Or for Sepolia:
 *   forge test --match-contract ForkTest --fork-url $SEPOLIA_RPC_URL -vvv
 *
 * Chainlink ETH/USD feed on Ethereum mainnet:
 *   0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
 *
 * Chainlink ETH/USD feed on Sepolia:
 *   0x694AA1769357215DE4FAC081bf1f309aDC325306
 */
contract ForkTest is Test {
    // =========================================================================
    // Mainnet Chainlink ETH/USD
    // =========================================================================

    address constant CHAINLINK_ETH_USD_MAINNET = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // =========================================================================
    // Fork 1: Real Chainlink price feed returns valid, fresh price
    // =========================================================================

    /**
     * @notice Fork mainnet and verify our oracle wrapper handles a real feed.
     * @dev Validates that:
     *      - The feed returns a positive price.
     *      - The price is within a reasonable range ($100–$100,000 for ETH).
     *      - Our staleness guard accepts a fresh live price.
     */
    function test_Fork_Chainlink_RealFeed_ValidPrice() public {
        // Fork from mainnet at a known recent block
        uint256 mainnetFork = vm.createFork(vm.envOr("ETH_RPC_URL", string("https://eth.llamarpc.com")));
        vm.selectFork(mainnetFork);

        address admin = makeAddr("admin");

        // Wrap the real Chainlink ETH/USD feed
        ChainlinkPriceOracle oracle = new ChainlinkPriceOracle(
            CHAINLINK_ETH_USD_MAINNET,
            address(0), // no PoR on mainnet for this test
            3600,       // 1 hour staleness
            admin
        );

        (uint256 price, uint256 updatedAt) = oracle.getPrice();

        console.log("ETH/USD price (18 dec):", price);
        console.log("Updated at:", updatedAt);

        // Sanity: ETH price should be between $100 and $100,000
        assertGt(price, 100e18, "Fork-1: price too low");
        assertLt(price, 100_000e18, "Fork-1: price too high");

        // updatedAt must be recent (within 1 hour of current block)
        assertGt(updatedAt, block.timestamp - 3600, "Fork-1: price is stale on mainnet");
    }

    // =========================================================================
    // Fork 2: Vault integrates with a real ERC-20 on mainnet (USDC-like)
    // =========================================================================

    // USDC on mainnet (6 decimals, well-established)
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /**
     * @notice Fork mainnet, deploy our Vault with real USDC as underlying,
     *         and verify deposit/redeem round-trips correctly.
     * @dev Uses vm.deal + deal (token gift) to fund a test user with USDC.
     */
    function test_Fork_Vault_WithRealUSDC() public {
        uint256 mainnetFork = vm.createFork(vm.envOr("ETH_RPC_URL", string("https://eth.llamarpc.com")));
        vm.selectFork(mainnetFork);

        address admin = makeAddr("admin");
        address alice = makeAddr("alice");

        // Give alice 10,000 USDC using foundry's deal cheatcode
        deal(USDC_MAINNET, alice, 10_000e6);

        // Deploy vault with real USDC as underlying
        // Note: USDC is 6 decimals — vault handles arbitrary decimals
        import_IERC20 usdc = import_IERC20(USDC_MAINNET);
        RWAYieldVault vault = new RWAYieldVault(
            usdc,
            admin,
            1_000_000e6 // 1M USDC cap
        );

        uint256 depositAmount = 1000e6; // 1000 USDC

        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        assertGt(shares, 0, "Fork-2: no shares minted");
        assertEq(vault.totalAssets(), depositAmount, "Fork-2: totalAssets mismatch");

        // Redeem
        vm.startPrank(alice);
        uint256 assetsBack = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        // Should get back approx depositAmount (rounding ≤ 1 unit)
        assertApproxEqAbs(assetsBack, depositAmount, 1, "Fork-2: round-trip loss too large");
    }

    // =========================================================================
    // Fork 3: Oracle staleness guard works against a real feed with warp
    // =========================================================================

    /**
     * @notice Fork mainnet, warp time forward beyond staleness threshold,
     *         confirm our oracle reverts with StalePrice.
     */
    function test_Fork_Oracle_StalenessGuard_Reverts_AfterTimeWarp() public {
        uint256 mainnetFork = vm.createFork(vm.envOr("ETH_RPC_URL", string("https://eth.llamarpc.com")));
        vm.selectFork(mainnetFork);

        address admin = makeAddr("admin");

        // Short staleness: 60 seconds
        ChainlinkPriceOracle oracle = new ChainlinkPriceOracle(
            CHAINLINK_ETH_USD_MAINNET,
            address(0),
            60, // 60 second threshold
            admin
        );

        // Warp forward 1 hour — price feed hasn't updated (forked state is frozen)
        vm.warp(block.timestamp + 3601);

        // Must revert due to staleness
        vm.expectRevert();
        oracle.getPrice();
    }
}

// Minimal interface for fork tests
interface import_IERC20 {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}
