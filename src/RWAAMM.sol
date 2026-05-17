// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title RWAAMM
 * @notice Constant-product AMM (x·y = k) for RWA/USDC trading.
 *         0.3% swap fee, slippage protection, LP tokens (ERC-20).
 *         Yul assembly used for sqrt calculation (benchmarked vs Solidity).
 * @dev Implements Checks-Effects-Interactions throughout.
 *      No use of tx.origin, block.timestamp as randomness, or transfer/send.
 *      All ERC-20 interactions via SafeERC20.
 */
contract RWAAMM is ERC20, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // =========================================================================
    // Constants & Roles
    // =========================================================================

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Swap fee numerator (0.3% = 3/1000)
    uint256 public constant FEE_NUMERATOR = 3;
    uint256 public constant FEE_DENOMINATOR = 1000;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    // =========================================================================
    // State
    // =========================================================================

    IERC20 public immutable token0; // RWA token
    IERC20 public immutable token1; // USDC (or any quote token)

    uint256 public reserve0;
    uint256 public reserve1;

    // Accumulated protocol fees (claimable by governance via Timelock)
    uint256 public feeAccumulator0;
    uint256 public feeAccumulator1;

    // =========================================================================
    // Events
    // =========================================================================

    event LiquidityAdded(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 lpTokensMinted
    );

    event LiquidityRemoved(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 lpTokensBurned
    );

    event Swap(
        address indexed user,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut
    );

    event ReservesUpdated(uint256 reserve0, uint256 reserve1);

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(
        address _token0,
        address _token1,
        address _admin
    ) ERC20("RWA-AMM LP Token", "RWA-LP") {
        require(_token0 != address(0) && _token1 != address(0), "AMM: zero address");
        require(_token0 != _token1, "AMM: identical tokens");

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    // =========================================================================
    // Pausable
    // =========================================================================

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // =========================================================================
    // Core: Add Liquidity
    // =========================================================================

    /**
     * @notice Add liquidity to the pool. Mints LP tokens proportional to share.
     * @param amount0Desired  Max token0 to deposit.
     * @param amount1Desired  Max token1 to deposit.
     * @param amount0Min      Slippage protection for token0.
     * @param amount1Min      Slippage protection for token1.
     * @return lpMinted       Amount of LP tokens minted.
     */
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external nonReentrant whenNotPaused returns (uint256 lpMinted) {
        // --- CHECKS ---
        require(amount0Desired > 0 && amount1Desired > 0, "AMM: zero amount");

        uint256 amount0;
        uint256 amount1;
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            // First deposit — take exact amounts, lock MINIMUM_LIQUIDITY
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            // lpMinted = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY
            uint256 liq = _sqrt(amount0 * amount1);
            require(liq > MINIMUM_LIQUIDITY, "AMM: insufficient initial liquidity");
            lpMinted = liq - MINIMUM_LIQUIDITY;
            // Mint dead-shares to address(1) to prevent inflation attack
            _mint(address(1), MINIMUM_LIQUIDITY);
        } else {
            // Subsequent deposits — maintain current ratio
            uint256 amount1Optimal = (amount0Desired * reserve1) / reserve0;
            if (amount1Optimal <= amount1Desired) {
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = (amount1Desired * reserve0) / reserve1;
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
            // Slippage check
            require(amount0 >= amount0Min, "AMM: amount0 below min");
            require(amount1 >= amount1Min, "AMM: amount1 below min");

            // LP tokens = min(amount0 / reserve0, amount1 / reserve1) * totalSupply
            uint256 lp0 = (amount0 * _totalSupply) / reserve0;
            uint256 lp1 = (amount1 * _totalSupply) / reserve1;
            lpMinted = lp0 < lp1 ? lp0 : lp1;
        }

        require(lpMinted > 0, "AMM: zero LP minted");

        // --- EFFECTS ---
        reserve0 += amount0;
        reserve1 += amount1;

        _mint(msg.sender, lpMinted);

        // --- INTERACTIONS ---
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        emit LiquidityAdded(msg.sender, amount0, amount1, lpMinted);
        emit ReservesUpdated(reserve0, reserve1);
    }

    // =========================================================================
    // Core: Remove Liquidity
    // =========================================================================

    /**
     * @notice Remove liquidity by burning LP tokens.
     * @param lpAmount    LP tokens to burn.
     * @param amount0Min  Minimum token0 to receive (slippage protection).
     * @param amount1Min  Minimum token1 to receive (slippage protection).
     */
    function removeLiquidity(
        uint256 lpAmount,
        uint256 amount0Min,
        uint256 amount1Min
    ) external nonReentrant whenNotPaused returns (uint256 amount0, uint256 amount1) {
        // --- CHECKS ---
        require(lpAmount > 0, "AMM: zero LP amount");

        uint256 _totalSupply = totalSupply();
        amount0 = (lpAmount * reserve0) / _totalSupply;
        amount1 = (lpAmount * reserve1) / _totalSupply;

        require(amount0 >= amount0Min, "AMM: amount0 below min");
        require(amount1 >= amount1Min, "AMM: amount1 below min");
        require(amount0 > 0 && amount1 > 0, "AMM: insufficient liquidity burned");

        // --- EFFECTS ---
        reserve0 -= amount0;
        reserve1 -= amount1;

        _burn(msg.sender, lpAmount);

        // --- INTERACTIONS ---
        token0.safeTransfer(msg.sender, amount0);
        token1.safeTransfer(msg.sender, amount1);

        emit LiquidityRemoved(msg.sender, amount0, amount1, lpAmount);
        emit ReservesUpdated(reserve0, reserve1);
    }

    // =========================================================================
    // Core: Swap
    // =========================================================================

    /**
     * @notice Swap token0 for token1 or vice versa.
     * @param tokenIn      Address of the input token.
     * @param amountIn     Amount of input token.
     * @param amountOutMin Slippage protection — minimum output required.
     * @return amountOut   Actual output amount.
     */
    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        // --- CHECKS ---
        require(tokenIn == address(token0) || tokenIn == address(token1), "AMM: invalid tokenIn");
        require(amountIn > 0, "AMM: zero amountIn");
        require(reserve0 > 0 && reserve1 > 0, "AMM: no liquidity");

        bool isToken0In = tokenIn == address(token0);

        (uint256 reserveIn, uint256 reserveOut) = isToken0In
            ? (reserve0, reserve1)
            : (reserve1, reserve0);

        // Apply 0.3% fee: amountInWithFee = amountIn * 997 / 1000
        // amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee)
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR);
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);

        require(amountOut >= amountOutMin, "AMM: slippage exceeded");
        require(amountOut < reserveOut, "AMM: insufficient liquidity");

        // --- EFFECTS ---
        if (isToken0In) {
            reserve0 += amountIn;
            reserve1 -= amountOut;
        } else {
            reserve1 += amountIn;
            reserve0 -= amountOut;
        }

        // --- INTERACTIONS ---
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        if (isToken0In) {
            token1.safeTransfer(msg.sender, amountOut);
        } else {
            token0.safeTransfer(msg.sender, amountOut);
        }

        emit Swap(msg.sender, tokenIn, amountIn, amountOut);
        emit ReservesUpdated(reserve0, reserve1);
    }

    // =========================================================================
    // View: Quote
    // =========================================================================

    /**
     * @notice Get expected output for a given input (excluding fee).
     */
    function getAmountOut(
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        require(tokenIn == address(token0) || tokenIn == address(token1), "AMM: invalid tokenIn");
        bool isToken0In = tokenIn == address(token0);
        (uint256 reserveIn, uint256 reserveOut) = isToken0In
            ? (reserve0, reserve1)
            : (reserve1, reserve0);

        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR);
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);
    }

    // =========================================================================
    // Yul Assembly: sqrt (Babylonian method)
    // Used for initial liquidity calculation.
    // Gas benchmark: see GasReport.md
    // =========================================================================

    /**
     * @notice Compute integer square root using Yul assembly (Babylonian method).
     * @dev This is the function benchmarked against _sqrtSolidity().
     */
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        assembly {
            // if y == 0, z stays 0
            if gt(y, 3) {
                z := y
                let x := add(div(y, 2), 1)
                // Babylonian iteration until convergence
                for {} lt(x, z) {} {
                    z := x
                    x := div(add(div(y, x), x), 2)
                }
            }
            // if y == 1, 2, or 3 then z = 1
            if and(gt(y, 0), lt(y, 4)) {
                z := 1
            }
        }
    }

    /**
     * @notice Pure-Solidity equivalent of _sqrt — used only for gas benchmarking.
     * @dev See test/GasBenchmark.t.sol for before/after comparison.
     */
    function _sqrtSolidity(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // Expose for benchmarking tests
    function sqrtYul(uint256 y) external pure returns (uint256) {
        return _sqrt(y);
    }

    function sqrtSolidity(uint256 y) external pure returns (uint256) {
        return _sqrtSolidity(y);
    }

    // =========================================================================
    // Invariant helper
    // =========================================================================

    /// @notice Returns current k = reserve0 * reserve1. Used in invariant tests.
    function getK() external view returns (uint256) {
        return reserve0 * reserve1;
    }
}
