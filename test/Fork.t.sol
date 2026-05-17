// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
 * Chainlink ETH/USD (mainnet): 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
 * USDC (mainnet):              0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
 */
contract ForkTest is Test {
    address constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_WHALE = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

    string constant RPC = "ETH_RPC_URL";

    // =========================================================================
    // Fork 1: Real Chainlink feed returns valid, fresh price
    // =========================================================================

    /**
     * @notice Верифицируем что наш OracleAdapter корректно читает реальный
     *         Chainlink ETH/USD feed: цена разумная, staleness не срабатывает.
     */
    function test_Fork_Chainlink_RealFeed_ValidPrice() public {
        vm.createSelectFork(vm.envOr(RPC, string("https://eth.llamarpc.com")));

        address admin = makeAddr("admin");
        ChainlinkPriceOracle oracle = new ChainlinkPriceOracle(
            CHAINLINK_ETH_USD,
            address(0), // PoR не нужен для этого теста
            3600, // 1 час staleness
            admin
        );

        (uint256 price, uint256 updatedAt) = oracle.getPrice();

        console.log("ETH/USD price (18 dec):", price);
        console.log("Updated at:", updatedAt);
        console.log("Age (sec):", block.timestamp - updatedAt);

        assertGt(price, 100e18, "Fork-1: price < $100");
        assertLt(price, 100_000e18, "Fork-1: price > $100k");
        assertGt(updatedAt, block.timestamp - 3600, "Fork-1: price stale on mainnet");
    }

    // =========================================================================
    // Fork 2: Staleness guard reverts after time warp
    // =========================================================================

    /**
     * @notice Мотаем время вперёд — staleness check должен сработать.
     */
    function test_Fork_Oracle_StalenessGuard_Reverts_AfterTimeWarp() public {
        vm.createSelectFork(vm.envOr(RPC, string("https://eth.llamarpc.com")));

        address admin = makeAddr("admin");
        ChainlinkPriceOracle oracle = new ChainlinkPriceOracle(
            CHAINLINK_ETH_USD,
            address(0),
            60, // 60 сек threshold
            admin
        );

        // Сначала работает
        (uint256 price,) = oracle.getPrice();
        assertGt(price, 0);

        // Мотаем время на 1 час — feed "устаревает"
        vm.warp(block.timestamp + 3601);

        vm.expectRevert();
        oracle.getPrice();
    }

    // =========================================================================
    // Fork 3: Vault + real USDC deposit/redeem round-trip
    // =========================================================================

    /**
     * @notice Деплоим RWAYieldVault с реальным USDC как underlying.
     *         Проверяем ERC-4626 round-trip и совместимость с 6-decimal токеном.
     */
    function test_Fork_Vault_WithRealUSDC() public {
        vm.createSelectFork(vm.envOr(RPC, string("https://eth.llamarpc.com")));

        address admin = makeAddr("admin");
        address alice = makeAddr("alice");

        // Даём alice 10,000 USDC через foundry deal
        deal(USDC, alice, 10_000e6);

        RWAYieldVault vault = new RWAYieldVault(
            IERC20(USDC),
            admin,
            1_000_000e6 // 1M USDC cap
        );

        uint256 depositAmount = 1_000e6; // 1000 USDC

        // Deposit
        vm.startPrank(alice);
        IERC20(USDC).approve(address(vault), depositAmount);
        uint256 previewShares = vault.previewDeposit(depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        console.log("Deposited USDC:", depositAmount / 1e6);
        console.log("Shares received:", shares);

        assertGt(shares, 0, "Fork-3: no shares minted");
        assertLe(shares, previewShares + 1, "Fork-3: ERC-4626 preview mismatch");
        assertEq(vault.totalAssets(), depositAmount, "Fork-3: totalAssets mismatch");

        // Redeem
        vm.startPrank(alice);
        uint256 assetsBack = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        console.log("Assets back:", assetsBack / 1e6, "USDC");
        assertApproxEqAbs(assetsBack, depositAmount, 1, "Fork-3: round-trip loss > 1 unit");
    }
}
