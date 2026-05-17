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
 *      All ERC-20 interactions via SafeERC20.
 */
contract RWAAMM is ERC20, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // =========================================================================
    // Constants & Roles
    // =========================================================================

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant FEE_NUMERATOR   = 3;
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    // =========================================================================
    // State
    // =========================================================================

    IERC20 public immutable token0; // RWA token
    IERC20 public immutable token1; // USDC (or any quote token)

    uint256 public reserve0;
    uint256 public reserve1;

    // =========================================================================
    // Events
    // =========================================================================

    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 lpTokensMinted);
    event LiquidityRemoved(address indexed provider, uint256 amount0, uint256 amount1, uint256 lpTokensBurned);
    event Swap(address indexed user, address indexed tokenIn, uint256 amountIn, uint256 amountOut);
    event ReservesUpdated(uint256 reserve0, uint256 reserve1);

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(address _token0, address _token1, address _admin)
        ERC20("RWA-AMM LP Token", "RWA-LP")
    {
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

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // =========================================================================
    // Core: Add Liquidity
    // =========================================================================

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
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            uint256 liq = _sqrt(amount0 * amount1);
            require(liq > MINIMUM_LIQUIDITY, "AMM: insufficient initial liquidity");
            lpMinted = liq - MINIMUM_LIQUIDITY;
            _mint(address(1), MINIMUM_LIQUIDITY);
        } else {
            uint256 amount1Optimal = (amount0Desired * reserve1) / reserve0;
            if (amount1Optimal <= amount1Desired) {
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = (amount1Desired * reserve0) / reserve1;
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
            require(amount0 >= amount0Min, "AMM: amount0 below min");
            require(amount1 >= amount1Min, "AMM: amount1 below min");

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

        // 0.3% fee: multiply first to avoid divide-before-multiply
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR);
        amountOut = (amountInWithFee * reserveOut) / ((reserveIn * FEE_DENOMINATOR) + amountInWithFee);

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

    function getAmountOut(address tokenIn, uint256 amountIn)
        external view returns (uint256 amountOut)
    {
        require(tokenIn == address(token0) || tokenIn == address(token1), "AMM: invalid tokenIn");
        bool isToken0In = tokenIn == address(token0);
        (uint256 reserveIn, uint256 reserveOut) = isToken0In
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR);
        amountOut = (amountInWithFee * reserveOut) / ((reserveIn * FEE_DENOMINATOR) + amountInWithFee);
    }

    // =========================================================================
    // Yul Assembly: sqrt (Babylonian method)
    // =========================================================================

    /**
     * @notice Integer sqrt via Yul assembly. Benchmarked vs sqrtSolidity().
     * @dev Used in initial LP calculation: lpMinted = sqrt(amount0 * amount1).
     *      Gas savings vs Solidity: see GasReport.md.
     */
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        assembly {
            if gt(y, 3) {
                z := y
                let x := add(div(y, 2), 1)
                for {} lt(x, z) {} {
                    z := x
                    x := div(add(div(y, x), x), 2)
                }
            }
            if and(gt(y, 0), lt(y, 4)) {
                z := 1
            }
        }
    }

    function _sqrtSolidity(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) { z = x; x = (y / x + x) / 2; }
        } else if (y != 0) {
            z = 1;
        }
    }

    /// @notice Public wrappers for gas benchmarking tests
    function sqrtYul(uint256 y) external pure returns (uint256) { return _sqrt(y); }
    function sqrtSolidity(uint256 y) external pure returns (uint256) { return _sqrtSolidity(y); }

    /// @notice Returns k = reserve0 * reserve1. Used in invariant tests.
    function getK() external view returns (uint256) { return reserve0 * reserve1; }
}
