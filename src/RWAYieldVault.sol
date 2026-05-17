// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title RWAYieldVault
 * @notice ERC-4626 tokenized vault. Users deposit RWA tokens to receive
 *         yield-bearing vault shares (vRWA).
 *
 * @dev Inflation-attack protection via _decimalsOffset() = 3.
 *      OZ ERC4626 internally uses virtual shares = 10^offset internally,
 *      which makes first-deposit manipulation unprofitable.
 *      See: https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack
 *
 *      Rounding follows ERC-4626 spec:
 *        - deposit/mint  → round DOWN (user gets fewer shares)
 *        - withdraw/redeem → round UP (user pays more assets, vault protected)
 */
contract RWAYieldVault is ERC4626, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // =========================================================================
    // Roles
    // =========================================================================

    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE        = keccak256("PAUSER_ROLE");

    // =========================================================================
    // State
    // =========================================================================

    /// @notice Total yield injected by yield manager (informational)
    uint256 public totalYieldAccrued;

    /// @notice Maximum total assets (deposit cap)
    uint256 public depositCap;

    // =========================================================================
    // Events
    // =========================================================================

    event YieldInjected(address indexed manager, uint256 amount);
    event DepositCapUpdated(uint256 oldCap, uint256 newCap);

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(IERC20 _asset, address _admin, uint256 _depositCap)
        ERC4626(_asset)
        ERC20("RWA Yield Vault Share", "vRWA")
    {
        require(_admin != address(0), "Vault: zero admin");
        require(_depositCap > 0,      "Vault: zero cap");

        _grantRole(DEFAULT_ADMIN_ROLE,  _admin);
        _grantRole(YIELD_MANAGER_ROLE,  _admin);
        _grantRole(PAUSER_ROLE,         _admin);

        depositCap = _depositCap;
    }

    // =========================================================================
    // Inflation-attack protection via decimals offset
    // =========================================================================

    /**
     * @dev Override _decimalsOffset to use virtual shares protection.
     *      OZ ERC4626 multiplies/divides by 10^offset internally, making
     *      the first-deposit inflation attack economically infeasible.
     *      offset = 3 → 1000x virtual shares buffer.
     */
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    // =========================================================================
    // Admin
    // =========================================================================

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    /**
     * @notice Inject yield. Increases totalAssets() → share price rises.
     * @dev CEI: effects (totalYieldAccrued) before interaction (safeTransferFrom).
     */
    function injectYield(uint256 amount) external onlyRole(YIELD_MANAGER_ROLE) nonReentrant {
        require(amount > 0, "Vault: zero yield");
        // EFFECTS
        totalYieldAccrued += amount;
        // INTERACTIONS
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        emit YieldInjected(msg.sender, amount);
    }

    function setDepositCap(uint256 newCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit DepositCapUpdated(depositCap, newCap);
        depositCap = newCap;
    }

    // =========================================================================
    // Deposit cap
    // =========================================================================

    function maxDeposit(address) public view virtual override returns (uint256) {
        uint256 current = totalAssets();
        if (current >= depositCap) return 0;
        return depositCap - current;
    }

    function maxMint(address) public view virtual override returns (uint256) {
        return convertToShares(maxDeposit(address(0)));
    }

    // =========================================================================
    // ERC-4626 overrides — add pause + reentrancy guards
    // =========================================================================

    function deposit(uint256 assets, address receiver)
        public override nonReentrant whenNotPaused returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver)
        public override nonReentrant whenNotPaused returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner_)
        public override nonReentrant whenNotPaused returns (uint256)
    {
        return super.withdraw(assets, receiver, owner_);
    }

    function redeem(uint256 shares, address receiver, address owner_)
        public override nonReentrant whenNotPaused returns (uint256)
    {
        return super.redeem(shares, receiver, owner_);
    }

    // =========================================================================
    // Interface support
    // =========================================================================

    function supportsInterface(bytes4 interfaceId)
        public view override(AccessControl) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
