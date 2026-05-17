// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {RWAAMM} from "../src/RWAAMM.sol";
import {RWAYieldVault} from "../src/RWAYieldVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title AMMHandler
 * @notice Handler for AMM invariant testing. Generates bounded valid actions.
 */
contract AMMHandler is Test {
    RWAAMM public amm;
    MockERC20 public token0;
    MockERC20 public token1;

    address[] public actors;
    uint256 public totalLPMinted;
    uint256 public totalLPBurned;

    constructor(RWAAMM _amm, MockERC20 _token0, MockERC20 _token1) {
        amm = _amm;
        token0 = _token0;
        token1 = _token1;

        // Create actors
        for (uint256 i = 0; i < 3; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            actors.push(actor);
            token0.mint(actor, 1_000_000e18);
            token1.mint(actor, 1_000_000e18);
        }

        // Seed initial liquidity
        address seeder = actors[0];
        vm.startPrank(seeder);
        token0.approve(address(amm), 100_000e18);
        token1.approve(address(amm), 100_000e18);
        amm.addLiquidity(100_000e18, 100_000e18, 0, 0);
        vm.stopPrank();
    }

    function addLiquidity(uint256 actorSeed, uint256 amt0, uint256 amt1) external {
        address actor = actors[actorSeed % actors.length];
        amt0 = bound(amt0, 1e15, 10_000e18);
        amt1 = bound(amt1, 1e15, 10_000e18);

        vm.startPrank(actor);
        token0.approve(address(amm), amt0);
        token1.approve(address(amm), amt1);
        try amm.addLiquidity(amt0, amt1, 0, 0) returns (uint256 lp) {
            totalLPMinted += lp;
        } catch {}
        vm.stopPrank();
    }

    function swap(uint256 actorSeed, bool zeroForOne, uint256 amountIn) external {
        address actor = actors[actorSeed % actors.length];
        amountIn = bound(amountIn, 1e15, 1000e18);

        vm.startPrank(actor);
        address tokenIn = zeroForOne ? address(token0) : address(token1);
        MockERC20(tokenIn).approve(address(amm), amountIn);
        try amm.swap(tokenIn, amountIn, 0) {}
        catch {}
        vm.stopPrank();
    }

    function removeLiquidity(uint256 actorSeed, uint256 lpFraction) external {
        address actor = actors[actorSeed % actors.length];
        uint256 lpBalance = amm.balanceOf(actor);
        if (lpBalance == 0) return;

        lpFraction = bound(lpFraction, 1, 100);
        uint256 lpAmount = (lpBalance * lpFraction) / 100;
        if (lpAmount == 0) return;

        vm.startPrank(actor);
        amm.approve(address(amm), lpAmount);
        try amm.removeLiquidity(lpAmount, 0, 0) returns (uint256, uint256) {
            totalLPBurned += lpAmount;
        } catch {}
        vm.stopPrank();
    }
}

/**
 * @title VaultHandler
 * @notice Handler for Vault invariant testing.
 */
contract VaultHandler is Test {
    RWAYieldVault public vault;
    MockERC20 public asset;

    address[] public actors;
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;

    constructor(RWAYieldVault _vault, MockERC20 _asset) {
        vault = _vault;
        asset = _asset;

        for (uint256 i = 0; i < 3; i++) {
            address actor = makeAddr(string(abi.encodePacked("vaultActor", i)));
            actors.push(actor);
            asset.mint(actor, 1_000_000e18);
        }
    }

    function deposit(uint256 actorSeed, uint256 assets) external {
        address actor = actors[actorSeed % actors.length];
        assets = bound(assets, 1e6, 100_000e18);

        uint256 maxDeposit = vault.maxDeposit(actor);
        if (maxDeposit == 0) return;
        if (assets > maxDeposit) assets = maxDeposit;

        vm.startPrank(actor);
        asset.approve(address(vault), assets);
        try vault.deposit(assets, actor) {
            totalDeposited += assets;
        } catch {}
        vm.stopPrank();
    }

    function redeem(uint256 actorSeed, uint256 sharesFraction) external {
        address actor = actors[actorSeed % actors.length];
        uint256 shares = vault.balanceOf(actor);
        if (shares == 0) return;

        sharesFraction = bound(sharesFraction, 1, 100);
        uint256 toRedeem = (shares * sharesFraction) / 100;
        if (toRedeem == 0) return;

        vm.startPrank(actor);
        try vault.redeem(toRedeem, actor, actor) returns (uint256 assets) {
            totalWithdrawn += assets;
        } catch {}
        vm.stopPrank();
    }
}

/**
 * @title InvariantTest
 * @notice Invariant test suite for RWAAMM and RWAYieldVault.
 *
 * Invariants tested:
 *   1. AMM: k = reserve0 * reserve1 never decreases after swap
 *   2. AMM: reserve0 == actual token0 balance, reserve1 == actual token1 balance
 *   3. AMM: Total LP supply - MINIMUM_LIQUIDITY == sum of user LP balances
 *   4. Vault: totalAssets() == actual underlying balance
 *   5. Vault: totalSupply conservation (deposit/redeem only change it proportionally)
 */
contract InvariantTest is StdInvariant, Test {
    RWAAMM public amm;
    RWAYieldVault public vault;
    MockERC20 public token0;
    MockERC20 public token1;

    AMMHandler public ammHandler;
    VaultHandler public vaultHandler;

    address public admin = makeAddr("admin");
    uint256 public initialK;

    function setUp() public {
        vm.startPrank(admin);

        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 18);

        amm = new RWAAMM(address(token0), address(token1), admin);
        vault = new RWAYieldVault(token0, admin, 10_000_000e18);

        vm.stopPrank();

        ammHandler = new AMMHandler(amm, token0, token1);
        vaultHandler = new VaultHandler(vault, token0);

        // After seeding, record initial k
        initialK = amm.getK();

        // Tell Foundry to fuzz the handlers
        targetContract(address(ammHandler));
        targetContract(address(vaultHandler));
    }

    // =========================================================================
    // Invariant 1: k = reserve0 * reserve1 must never decrease on swap
    // =========================================================================

    function invariant_AMM_K_NeverDecreases() public view {
        uint256 currentK = amm.getK();
        // k can only increase (fees accumulate) or stay equal
        assertGe(currentK, initialK, "INV-1: k decreased after swap");
    }

    // =========================================================================
    // Invariant 2: Reserves match actual contract token balances
    // =========================================================================

    function invariant_AMM_Reserves_MatchBalances() public view {
        uint256 actualBal0 = token0.balanceOf(address(amm));
        uint256 actualBal1 = token1.balanceOf(address(amm));

        assertEq(
            amm.reserve0(),
            actualBal0,
            "INV-2: reserve0 != actual token0 balance"
        );
        assertEq(
            amm.reserve1(),
            actualBal1,
            "INV-2: reserve1 != actual token1 balance"
        );
    }

    // =========================================================================
    // Invariant 3: Vault totalAssets matches actual token balance
    // =========================================================================

    function invariant_Vault_TotalAssets_MatchBalance() public view {
        uint256 vaultBal = token0.balanceOf(address(vault));
        assertEq(
            vault.totalAssets(),
            vaultBal,
            "INV-3: vault.totalAssets() != actual balance"
        );
    }

    // =========================================================================
    // Invariant 4: Vault totalSupply > 0 iff totalAssets > 0
    // =========================================================================

    function invariant_Vault_TotalSupply_Consistency() public view {
        if (vault.totalSupply() == 0) {
            // If no shares exist, no assets should be locked
            // (Some rounding dust may remain, allow up to 1 unit)
            assertLe(
                vault.totalAssets(),
                1,
                "INV-4: shares=0 but assets>1"
            );
        }
    }

    // =========================================================================
    // Invariant 5: AMM LP totalSupply == sum of all balances (ERC-20 invariant)
    // =========================================================================

    function invariant_AMM_LP_TotalSupply_Conservation() public view {
        // LP is an ERC-20: totalSupply = sum of all balances.
        // We check against the actors in the handler.
        uint256 sumBalances = amm.balanceOf(address(1)); // dead shares
        for (uint256 i = 0; i < 3; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            sumBalances += amm.balanceOf(actor);
        }
        assertEq(
            amm.totalSupply(),
            sumBalances,
            "INV-5: LP totalSupply != sum of balances"
        );
    }
}
