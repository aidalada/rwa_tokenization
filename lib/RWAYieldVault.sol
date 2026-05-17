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
 * @dev Security measures:
 *      1. Virtual shares/assets offset (1e3) — defeats ERC-4626 inflation attack.
 *         See: https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack
 *      2. ReentrancyGuard on all state-changing functions.
 *      3. Pausable for emergency circuit-breaker.
 *      4. Checks-Effects-Interactions pattern throughout.
 *      5. SafeERC20 for all token interactions.
 *
 * Rounding: follows ERC-4626 spec —
 *   - deposit/mint: round DOWN (user gets fewer shares)
 *   - withdraw/redeem: round UP (user pays more assets)
 */
contract RWAYieldVault is ERC4626, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // =========================================================================
    // Roles & Constants
    // =========================================================================

    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Virtual offset to prevent inflation attack (OZ recommendation)
    uint256 private constant VIRTUAL_SHARES = 1e3;
    uint256 private constant VIRTUAL_ASSETS = 1;

    // =========================================================================
    // State
    // =========================================================================

    /// @notice Total yield accrued by the vault (injected by yield manager)
    uint256 public totalYieldAccrued;

    /// @notice Maximum total assets allowed in the vault (deposit cap)
    uint256 public depositCap;

    // =========================================================================
    // Events
    // =========================================================================

    event YieldInjected(address indexed manager, uint256 amount);
    event DepositCapUpdated(uint256 oldCap, uint256 newCap);

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(
        IERC20 _asset,
        address _admin,
        uint256 _depositCap
    )
        ERC4626(_asset)
        ERC20("RWA Yield Vault Share", "vRWA")
    {
        require(_admin != address(0), "Vault: zero admin");
        require(_depositCap > 0, "Vault: zero cap");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(YIELD_MANAGER_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        depositCap = _depositCap;
    }

    // =========================================================================
    // Admin functions
    // =========================================================================

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Inject yield into the vault. Increases totalAssets(), diluting
     *         share price upwards — share holders automatically benefit.
     * @param amount  Amount of underlying asset to inject as yield.
     */
    function injectYield(uint256 amount) external onlyRole(YIELD_MANAGER_ROLE) nonReentrant {
        require(amount > 0, "Vault: zero yield");

        // CEI: effects before interaction
        totalYieldAccrued += amount;

        // Pull yield from manager — uses SafeERC20
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        emit YieldInjected(msg.sender, amount);
    }

    /**
     * @notice Update the maximum deposit cap.
     */
    function setDepositCap(uint256 newCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit DepositCapUpdated(depositCap, newCap);
        depositCap = newCap;
    }

    // =========================================================================
    // ERC-4626 overrides — virtual offset (inflation attack protection)
    // =========================================================================

    /**
     * @dev Total assets include the virtual offset of 1 to prevent divide-by-zero
     *      and the inflation attack on first deposit.
     *      The VIRTUAL_SHARES / VIRTUAL_ASSETS offset shifts the exchange rate
     *      so a single wei deposit cannot manipulate the ratio.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /**
     * @dev convertToShares: round DOWN (favours vault, not depositor).
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return assets.mulDiv(
            totalSupply() + VIRTUAL_SHARES,
            totalAssets() + VIRTUAL_ASSETS,
            rounding
        );
    }

    /**
     * @dev convertToAssets: round DOWN by default, UP when used for withdraw/redeem.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return shares.mulDiv(
            totalAssets() + VIRTUAL_ASSETS,
            totalSupply() + VIRTUAL_SHARES,
            rounding
        );
    }

    // =========================================================================
    // Deposit cap enforcement
    // =========================================================================

    function maxDeposit(address) public view virtual override returns (uint256) {
        uint256 assets = totalAssets();
        if (assets >= depositCap) return 0;
        return depositCap - assets;
    }

    function maxMint(address) public view virtual override returns (uint256) {
        uint256 maxAssets = maxDeposit(address(0));
        return _convertToShares(maxAssets, Math.Rounding.Floor);
    }

    // =========================================================================
    // Pausable hooks
    // =========================================================================

    function deposit(uint256 assets, address receiver)
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver)
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner_)
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner_);
    }

    function redeem(uint256 shares, address receiver, address owner_)
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner_);
    }

    // =========================================================================
    // Interface support
    // =========================================================================

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
