// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RWA AMM Pool
 * @dev Децентрализованный обменник с константой продукта (x * y = k).
 * Включает комиссию 0.3%, LP токены и оптимизацию на Yul согласно ТЗ.
 */
contract RWAAMM is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable TOKEN0; // Например, USDC
    IERC20 public immutable TOKEN1; // Твой RWAToken

    uint256 public reserve0;
    uint256 public reserve1;

    // События для The Graph
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    constructor(address _token0, address _token1) ERC20("RWA LP Token", "RLP") {
        TOKEN0 = IERC20(_token0);
        TOKEN1 = IERC20(_token1);
    }

    function _update(uint256 bal0, uint256 bal1) private {
        reserve0 = bal0;
        reserve1 = bal1;
    }

    function swap(address _tokenIn, uint256 _amountIn) external nonReentrant returns (uint256 amountOut) {
        require(_tokenIn == address(TOKEN0) || _tokenIn == address(TOKEN1), "RWAAMM: Invalid token");
        require(_amountIn > 0, "RWAAMM: Amount must be greater than 0");

        bool isToken0 = _tokenIn == address(TOKEN0);
        (IERC20 tokenIn, IERC20 tokenOut, uint256 reserveIn, uint256 reserveOut) =
            isToken0 ? (TOKEN0, TOKEN1, reserve0, reserve1) : (TOKEN1, TOKEN0, reserve1, reserve0);

        // Используем safeTransferFrom вместо обычного
        tokenIn.safeTransferFrom(msg.sender, address(this), _amountIn);

        uint256 amountInWithFee = _amountIn * 997;
        amountOut = (reserveOut * amountInWithFee) / (reserveIn * 1000 + amountInWithFee);

        require(amountOut > 0, "RWAAMM: Insufficient output amount");

        // Используем safeTransfer
        tokenOut.safeTransfer(msg.sender, amountOut);

        _update(TOKEN0.balanceOf(address(this)), TOKEN1.balanceOf(address(this)));

        if (isToken0) {
            emit Swap(msg.sender, _amountIn, 0, 0, amountOut, msg.sender);
        } else {
            emit Swap(msg.sender, 0, _amountIn, amountOut, 0, msg.sender);
        }
    }

    function addLiquidity(uint256 _amount0, uint256 _amount1) external nonReentrant returns (uint256 shares) {
        TOKEN0.safeTransferFrom(msg.sender, address(this), _amount0);
        TOKEN1.safeTransferFrom(msg.sender, address(this), _amount1);

        uint256 bal0 = TOKEN0.balanceOf(address(this));
        uint256 bal1 = TOKEN1.balanceOf(address(this));

        uint256 d0 = bal0 - reserve0;
        uint256 d1 = bal1 - reserve1;

        if (totalSupply() == 0) {
            shares = _sqrtYul(d0 * d1);
        } else {
            uint256 s0 = (d0 * totalSupply()) / reserve0;
            uint256 s1 = (d1 * totalSupply()) / reserve1;
            shares = s0 < s1 ? s0 : s1;
        }

        require(shares > 0, "RWAAMM: Shares minted = 0");
        _mint(msg.sender, shares);
        _update(bal0, bal1);

        emit Mint(msg.sender, _amount0, _amount1);
    }

    function removeLiquidity(uint256 _shares) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(_shares > 0, "RWAAMM: Shares = 0");

        uint256 bal0 = TOKEN0.balanceOf(address(this));
        uint256 bal1 = TOKEN1.balanceOf(address(this));

        amount0 = (_shares * bal0) / totalSupply();
        amount1 = (_shares * bal1) / totalSupply();

        require(amount0 > 0 && amount1 > 0, "RWAAMM: Insufficient liquidity burned");

        _burn(msg.sender, _shares);

        TOKEN0.safeTransfer(msg.sender, amount0);
        TOKEN1.safeTransfer(msg.sender, amount1);

        _update(TOKEN0.balanceOf(address(this)), TOKEN1.balanceOf(address(this)));

        emit Burn(msg.sender, amount0, amount1, msg.sender);
    }

    function _sqrtYul(uint256 y) internal pure returns (uint256 z) {
        assembly {
            if gt(y, 3) {
                z := y
                let x := add(div(y, 2), 1)
                for {} lt(x, z) {} {
                    z := x
                    x := div(add(div(y, x), x), 2)
                }
            }
            if iszero(iszero(y)) {
                if lt(y, 4) {
                    z := 1
                }
            }
        }
    }

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
}
