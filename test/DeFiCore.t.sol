// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {RWAAMM} from "../src/RWAAMM.sol";
import {RWAYieldVault} from "../src/RWAYieldVault.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {MockAggregator} from "../src/mocks/MockAggregator.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title DeFiCoreTest
 * @notice Unit + Fuzz tests for RWAAMM, RWAYieldVault, ChainlinkPriceOracle.
 *         Covers every public/external function including revert paths.
 */
contract DeFiCoreTest is Test {
    // =========================================================================
    // Contracts
    // =========================================================================

    RWAAMM public amm;
    RWAYieldVault public vault;
    ChainlinkPriceOracle public oracle;

    MockERC20 public rwa;
    MockERC20 public usdc;
    MockAggregator public priceFeed;
    MockAggregator public porFeed;

    // =========================================================================
    // Actors
    // =========================================================================

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public yieldManager = makeAddr("yieldManager");

    // =========================================================================
    // Constants
    // =========================================================================

    uint256 constant INITIAL_MINT = 1_000_000e18;
    uint256 constant STALENESS = 3600; // 1 hour
    uint256 constant DEPOSIT_CAP = 10_000_000e18;

    // =========================================================================
    // Setup
    // =========================================================================

    function setUp() public {
        vm.startPrank(admin);

        // Deploy mock tokens
        rwa = new MockERC20("Real World Asset", "RWA", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Deploy AMM
        amm = new RWAAMM(address(rwa), address(usdc), admin);

        // Deploy Vault (uses RWA as underlying)
        vault = new RWAYieldVault(rwa, admin, DEPOSIT_CAP);

        // Grant yield manager role
        vault.grantRole(vault.YIELD_MANAGER_ROLE(), yieldManager);

        // Deploy oracle mocks (8 decimal like Chainlink)
        priceFeed = new MockAggregator(8, 100e8); // RWA = $100
        porFeed = new MockAggregator(8, 100e8);   // PoR = $100

        // Deploy oracle adapter
        oracle = new ChainlinkPriceOracle(
            address(priceFeed),
            address(porFeed),
            STALENESS,
            admin
        );

        vm.stopPrank();

        // Mint tokens to actors
        rwa.mint(alice, INITIAL_MINT);
        rwa.mint(bob, INITIAL_MINT);
        usdc.mint(alice, INITIAL_MINT);
        usdc.mint(bob, INITIAL_MINT);
        rwa.mint(yieldManager, INITIAL_MINT);
    }

    // =========================================================================
    // AMM — Unit Tests
    // =========================================================================

    function test_AMM_AddInitialLiquidity() public {
        _addLiquidity(alice, 1000e18, 100_000e18);

        assertEq(amm.reserve0(), 1000e18);
        assertEq(amm.reserve1(), 100_000e18);
        // LP tokens minted = sqrt(1000e18 * 100_000e18) - MINIMUM_LIQUIDITY
        uint256 k = 1000e18 * 100_000e18;
        uint256 sqrtK = amm.sqrtYul(k);
        uint256 expectedLP = sqrtK - 1000; // MINIMUM_LIQUIDITY
        assertEq(amm.balanceOf(alice), expectedLP);
    }

    function test_AMM_AddSubsequentLiquidity_MaintainsRatio() public {
        _addLiquidity(alice, 1000e18, 100_000e18);

        uint256 lpBefore = amm.balanceOf(bob);
        _addLiquidity(bob, 500e18, 50_000e18);
        uint256 lpAfter = amm.balanceOf(bob);

        assertTrue(lpAfter > lpBefore);
        // Ratio preserved: reserve0/reserve1 = 1000/100000 = 1/100
        assertEq(amm.reserve0() * 100, amm.reserve1());
    }

    function test_AMM_AddLiquidity_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("AMM: zero amount");
        amm.addLiquidity(0, 100e18, 0, 0);
    }

    function test_AMM_AddLiquidity_SlippageProtection() public {
        _addLiquidity(alice, 1000e18, 100_000e18);

        // Try to add with very high minimum → should revert
        vm.startPrank(bob);
        rwa.approve(address(amm), type(uint256).max);
        usdc.approve(address(amm), type(uint256).max);
        vm.expectRevert("AMM: amount0 below min");
        amm.addLiquidity(500e18, 50_000e18, 600e18, 0); // amount0Min too high
        vm.stopPrank();
    }

    function test_AMM_Swap_Token0ForToken1() public {
        _addLiquidity(alice, 1000e18, 100_000e18);

        uint256 amountIn = 10e18;
        uint256 expectedOut = amm.getAmountOut(address(rwa), amountIn);

        uint256 bobUsdc0 = usdc.balanceOf(bob);

        vm.startPrank(bob);
        rwa.approve(address(amm), amountIn);
        uint256 amountOut = amm.swap(address(rwa), amountIn, 0);
        vm.stopPrank();

        assertEq(amountOut, expectedOut);
        assertEq(usdc.balanceOf(bob), bobUsdc0 + amountOut);
    }

    function test_AMM_Swap_Token1ForToken0() public {
        _addLiquidity(alice, 1000e18, 100_000e18);

        uint256 amountIn = 1000e18;
        uint256 expectedOut = amm.getAmountOut(address(usdc), amountIn);

        uint256 bobRwa0 = rwa.balanceOf(bob);

        vm.startPrank(bob);
        usdc.approve(address(amm), amountIn);
        uint256 amountOut = amm.swap(address(usdc), amountIn, 0);
        vm.stopPrank();

        assertEq(amountOut, expectedOut);
        assertEq(rwa.balanceOf(bob), bobRwa0 + amountOut);
    }

    function test_AMM_Swap_RevertSlippage() public {
        _addLiquidity(alice, 1000e18, 100_000e18);

        uint256 amountIn = 10e18;
        uint256 expectedOut = amm.getAmountOut(address(rwa), amountIn);

        vm.startPrank(bob);
        rwa.approve(address(amm), amountIn);
        vm.expectRevert("AMM: slippage exceeded");
        amm.swap(address(rwa), amountIn, expectedOut + 1); // impossible minimum
        vm.stopPrank();
    }

    function test_AMM_Swap_RevertInvalidToken() public {
        _addLiquidity(alice, 1000e18, 100_000e18);

        vm.prank(bob);
        vm.expectRevert("AMM: invalid tokenIn");
        amm.swap(address(0xdead), 10e18, 0);
    }

    function test_AMM_Swap_RevertNoLiquidity() public {
        vm.startPrank(bob);
        rwa.approve(address(amm), 10e18);
        vm.expectRevert("AMM: no liquidity");
        amm.swap(address(rwa), 10e18, 0);
        vm.stopPrank();
    }

    function test_AMM_RemoveLiquidity() public {
        _addLiquidity(alice, 1000e18, 100_000e18);

        uint256 lpBalance = amm.balanceOf(alice);
        uint256 rwaBeforeAlice = rwa.balanceOf(alice);
        uint256 usdcBeforeAlice = usdc.balanceOf(alice);

        vm.startPrank(alice);
        amm.approve(address(amm), lpBalance);
        (uint256 a0, uint256 a1) = amm.removeLiquidity(lpBalance, 0, 0);
        vm.stopPrank();

        assertGt(a0, 0);
        assertGt(a1, 0);
        assertEq(rwa.balanceOf(alice), rwaBeforeAlice + a0);
        assertEq(usdc.balanceOf(alice), usdcBeforeAlice + a1);
    }

    function test_AMM_RemoveLiquidity_RevertZero() public {
        _addLiquidity(alice, 1000e18, 100_000e18);

        vm.prank(alice);
        vm.expectRevert("AMM: zero LP amount");
        amm.removeLiquidity(0, 0, 0);
    }

    function test_AMM_RemoveLiquidity_SlippageProtection() public {
        _addLiquidity(alice, 1000e18, 100_000e18);

        uint256 lpBalance = amm.balanceOf(alice);

        vm.startPrank(alice);
        amm.approve(address(amm), lpBalance);
        vm.expectRevert("AMM: amount0 below min");
        amm.removeLiquidity(lpBalance, type(uint256).max, 0);
        vm.stopPrank();
    }

    function test_AMM_Pausable() public {
        _addLiquidity(alice, 1000e18, 100_000e18);

        vm.prank(admin);
        amm.pause();

        vm.startPrank(bob);
        rwa.approve(address(amm), 10e18);
        vm.expectRevert();
        amm.swap(address(rwa), 10e18, 0);
        vm.stopPrank();

        vm.prank(admin);
        amm.unpause();

        // Should work again
        vm.startPrank(bob);
        amm.swap(address(rwa), 10e18, 0);
        vm.stopPrank();
    }

    function test_AMM_YulSqrt_MatchesSoliditySqrt() public view {
        uint256[] memory inputs = new uint256[](5);
        inputs[0] = 0;
        inputs[1] = 1;
        inputs[2] = 4;
        inputs[3] = 100e18;
        inputs[4] = 1_000_000e36;

        for (uint256 i = 0; i < inputs.length; i++) {
            assertEq(amm.sqrtYul(inputs[i]), amm.sqrtSolidity(inputs[i]));
        }
    }

    function test_AMM_FeeApplied() public {
        _addLiquidity(alice, 1000e18, 100_000e18);

        // Constant-product without fee would give more out
        uint256 amountIn = 10e18;
        uint256 reserveIn = amm.reserve0();
        uint256 reserveOut = amm.reserve1();

        // No-fee formula: (amountIn * reserveOut) / (reserveIn + amountIn)
        uint256 noFeeOut = (amountIn * reserveOut) / (reserveIn + amountIn);
        uint256 withFeeOut = amm.getAmountOut(address(rwa), amountIn);

        // With fee, output must be less
        assertLt(withFeeOut, noFeeOut);
    }

    // =========================================================================
    // Vault — Unit Tests
    // =========================================================================

    function test_Vault_Deposit_ReceivesShares() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        rwa.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), depositAmount);
    }

    function test_Vault_Withdraw_ReturnsAssets() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        rwa.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);

        uint256 rwaBeforeWithdraw = rwa.balanceOf(alice);
        vault.redeem(shares, alice, alice);
        vm.stopPrank();

        // Should get back approximately depositAmount (minus rounding)
        assertApproxEqAbs(rwa.balanceOf(alice), rwaBeforeWithdraw + depositAmount, 1);
    }

    function test_Vault_YieldInjection_IncreasesShareValue() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        rwa.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 shareValueBefore = vault.convertToAssets(1e18);

        // Inject yield
        uint256 yieldAmount = 100e18;
        vm.startPrank(yieldManager);
        rwa.approve(address(vault), yieldAmount);
        vault.injectYield(yieldAmount);
        vm.stopPrank();

        uint256 shareValueAfter = vault.convertToAssets(1e18);

        // Share value should increase after yield injection
        assertGt(shareValueAfter, shareValueBefore);
    }

    function test_Vault_DepositCap_Enforced() public {
        uint256 smallCap = 500e18;

        vm.prank(admin);
        vault.setDepositCap(smallCap);

        vm.startPrank(alice);
        rwa.approve(address(vault), INITIAL_MINT);
        vm.expectRevert(); // ERC4626: deposit more than max
        vault.deposit(smallCap + 1, alice);
        vm.stopPrank();
    }

    function test_Vault_Pausable() public {
        vm.prank(admin);
        vault.pause();

        vm.startPrank(alice);
        rwa.approve(address(vault), 1000e18);
        vm.expectRevert();
        vault.deposit(1000e18, alice);
        vm.stopPrank();
    }

    function test_Vault_InflationAttack_Protection() public {
        // Classic inflation attack: attacker deposits 1 wei, then donates directly
        // to vault before victim deposits, trying to grief their shares to 0.
        // Virtual shares offset prevents this.

        address attacker = makeAddr("attacker");
        address victim = makeAddr("victim");
        rwa.mint(attacker, 1_000e18);
        rwa.mint(victim, 1_000e18);

        // Attacker deposits 1 wei
        vm.startPrank(attacker);
        rwa.approve(address(vault), 1);
        vault.deposit(1, attacker);
        vm.stopPrank();

        // Attacker donates 1000e18 directly to vault (front-running victim)
        vm.prank(attacker);
        rwa.transfer(address(vault), 1000e18);

        // Victim deposits 1000e18
        vm.startPrank(victim);
        rwa.approve(address(vault), 1000e18);
        uint256 victimShares = vault.deposit(1000e18, victim);
        vm.stopPrank();

        // Victim should receive shares > 0 (not griefed to 0)
        assertGt(victimShares, 0);
    }

    function test_Vault_RevertYieldManagerOnly() public {
        vm.startPrank(alice);
        rwa.approve(address(vault), 1000e18);
        vm.expectRevert();
        vault.injectYield(1000e18);
        vm.stopPrank();
    }

    function test_Vault_Mint_And_Redeem() public {
        vm.startPrank(alice);
        rwa.approve(address(vault), INITIAL_MINT);

        uint256 sharesToMint = 500e18;
        uint256 assetsNeeded = vault.previewMint(sharesToMint);
        vault.mint(sharesToMint, alice);
        assertApproxEqAbs(vault.balanceOf(alice), sharesToMint, 1);

        vault.redeem(sharesToMint, alice, alice);
        assertEq(vault.balanceOf(alice), 0);
        vm.stopPrank();

        _ = assetsNeeded; // suppress warning
    }

    function test_Vault_WithdrawByAsset() public {
        vm.startPrank(alice);
        rwa.approve(address(vault), 1000e18);
        vault.deposit(1000e18, alice);

        uint256 withdrawAmount = 500e18;
        uint256 sharesBurned = vault.withdraw(withdrawAmount, alice, alice);
        assertGt(sharesBurned, 0);
        vm.stopPrank();
    }

    // =========================================================================
    // Oracle — Unit Tests
    // =========================================================================

    function test_Oracle_GetPrice_Valid() public view {
        (uint256 price, ) = oracle.getPrice();
        // Feed: 100e8 (8 dec) → normalized to 18 dec = 100e18
        assertEq(price, 100e18);
    }

    function test_Oracle_GetPrice_RevertStale() public {
        // Simulate stale price: set updatedAt to past
        priceFeed.setUpdatedAt(block.timestamp - STALENESS - 1);

        vm.expectRevert();
        oracle.getPrice();
    }

    function test_Oracle_GetPrice_RevertNegative() public {
        priceFeed.setAnswer(-1);
        vm.expectRevert();
        oracle.getPrice();
    }

    function test_Oracle_GetPrice_RevertZero() public {
        priceFeed.setAnswer(0);
        vm.expectRevert();
        oracle.getPrice();
    }

    function test_Oracle_GetPrice_RevertIncompleteRound() public {
        priceFeed.setRoundId(5);
        priceFeed.setAnsweredInRound(4); // answeredInRound < roundId
        vm.expectRevert();
        oracle.getPrice();
    }

    function test_Oracle_GetProofOfReserve() public view {
        (uint256 reserve, ) = oracle.getProofOfReserve();
        assertEq(reserve, 100e18);
    }

    function test_Oracle_GetPriceAndReserve_Collateralised() public view {
        (uint256 price, uint256 reserve, bool ok) = oracle.getPriceAndReserve();
        assertEq(price, 100e18);
        assertEq(reserve, 100e18);
        assertTrue(ok);
    }

    function test_Oracle_GetPriceAndReserve_NotCollateralised() public {
        porFeed.setAnswer(50e8); // PoR < price
        (uint256 price, uint256 reserve, bool ok) = oracle.getPriceAndReserve();
        assertGt(price, reserve);
        assertFalse(ok);
    }

    function test_Oracle_UpdatePriceFeed() public {
        MockAggregator newFeed = new MockAggregator(8, 200e8);
        vm.prank(admin);
        oracle.setPriceFeed(address(newFeed));

        (uint256 price, ) = oracle.getPrice();
        assertEq(price, 200e18);
    }

    function test_Oracle_UpdatePriceFeed_RevertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        oracle.setPriceFeed(address(0));
    }

    function test_Oracle_UpdatePriceFeed_RevertUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.setPriceFeed(address(priceFeed));
    }

    function test_Oracle_UpdateStalenessThreshold() public {
        vm.prank(admin);
        oracle.setStalenessThreshold(7200);
        assertEq(oracle.stalenessThreshold(), 7200);
    }

    function test_Oracle_Normalises8Decimals() public {
        // Feed with 8 decimals, answer = 1234e8
        MockAggregator feed8 = new MockAggregator(8, 1234e8);
        vm.prank(admin);
        oracle.setPriceFeed(address(feed8));
        (uint256 price, ) = oracle.getPrice();
        assertEq(price, 1234e18);
    }

    function test_Oracle_Normalises6Decimals() public {
        // Feed with 6 decimals, answer = 1234e6
        MockAggregator feed6 = new MockAggregator(6, 1234e6);
        vm.prank(admin);
        oracle.setPriceFeed(address(feed6));
        (uint256 price, ) = oracle.getPrice();
        assertEq(price, 1234e18);
    }

    function test_Oracle_PoRFeed_NotSet_Reverts() public {
        // Deploy oracle with no PoR feed
        ChainlinkPriceOracle oracleNoPoR = new ChainlinkPriceOracle(
            address(priceFeed),
            address(0),
            STALENESS,
            admin
        );
        vm.expectRevert("Oracle: PoR feed not set");
        oracleNoPoR.getProofOfReserve();
    }

    // =========================================================================
    // Fuzz Tests
    // =========================================================================

    /**
     * @notice Fuzz: AMM swap must never output more than reserveOut.
     */
    function testFuzz_AMM_Swap_NeverExceedsReserve(uint256 amountIn) public {
        _addLiquidity(alice, 1_000_000e18, 100_000_000e18);

        // Bound to reasonable range (avoid overflow)
        amountIn = bound(amountIn, 1, 100_000e18);

        uint256 reserveOut = amm.reserve1();
        uint256 amountOut = amm.getAmountOut(address(rwa), amountIn);

        assertLt(amountOut, reserveOut);
    }

    /**
     * @notice Fuzz: Vault — depositing and redeeming must never lose more than 1 wei.
     */
    function testFuzz_Vault_DepositRedeem_Roundtrip(uint256 assets) public {
        assets = bound(assets, 1e6, DEPOSIT_CAP / 2);

        rwa.mint(alice, assets);

        vm.startPrank(alice);
        rwa.approve(address(vault), assets);
        uint256 shares = vault.deposit(assets, alice);

        uint256 rwaBalBefore = rwa.balanceOf(alice);
        vault.redeem(shares, alice, alice);
        uint256 rwaBalAfter = rwa.balanceOf(alice);
        vm.stopPrank();

        // Should get back at most assets (never more due to rounding)
        assertLe(rwaBalAfter - rwaBalBefore, assets);
        // Should not lose more than 1 wei
        assertApproxEqAbs(rwaBalAfter - rwaBalBefore, assets, 1);
    }

    /**
     * @notice Fuzz: Vault convertToShares(convertToAssets(x)) ≤ x.
     *         Demonstrates correct rounding direction.
     */
    function testFuzz_Vault_ConversionRounding(uint256 shares) public view {
        shares = bound(shares, 1, 1e30);
        uint256 assets = vault.convertToAssets(shares);
        uint256 sharesBack = vault.convertToShares(assets);
        // Due to floor rounding: sharesBack <= shares
        assertLe(sharesBack, shares);
    }

    /**
     * @notice Fuzz: AMM sqrt(x) via Yul must equal Solidity sqrt(x).
     */
    function testFuzz_AMM_YulSqrt_EqualsSolidity(uint256 x) public view {
        x = bound(x, 0, type(uint128).max); // avoid overflow in x*x
        assertEq(amm.sqrtYul(x), amm.sqrtSolidity(x));
    }

    /**
     * @notice Fuzz: Oracle — any positive price must not revert.
     */
    function testFuzz_Oracle_ValidPrice(int256 rawPrice) public {
        vm.assume(rawPrice > 0);
        priceFeed.setAnswer(rawPrice);
        (uint256 price, ) = oracle.getPrice();
        assertGt(price, 0);
    }

    /**
     * @notice Fuzz: Only ORACLE_ADMIN_ROLE can update staleness threshold.
     */
    function testFuzz_Oracle_OnlyAdminCanSetThreshold(address randomUser, uint256 threshold) public {
        vm.assume(randomUser != admin);
        vm.prank(randomUser);
        vm.expectRevert();
        oracle.setStalenessThreshold(threshold);
    }

    /**
     * @notice Fuzz: swap output decreases monotonically as pool drains.
     *         Large swaps should get worse prices (slippage).
     */
    function testFuzz_AMM_LargerSwap_WorsePriceImpact(uint256 small, uint256 large) public {
        _addLiquidity(alice, 1_000_000e18, 100_000_000e18);

        small = bound(small, 1e18, 1000e18);
        large = bound(large, small + 1, 10_000e18);

        uint256 outSmall = amm.getAmountOut(address(rwa), small);
        uint256 outLarge = amm.getAmountOut(address(rwa), large);

        // Price impact: outLarge/large < outSmall/small
        // ↔ outLarge * small < outSmall * large
        assertLt(outLarge * small, outSmall * large);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _addLiquidity(address who, uint256 amt0, uint256 amt1) internal {
        vm.startPrank(who);
        rwa.approve(address(amm), amt0);
        usdc.approve(address(amm), amt1);
        amm.addLiquidity(amt0, amt1, 0, 0);
        vm.stopPrank();
    }
}
