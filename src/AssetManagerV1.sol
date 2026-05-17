// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title Asset Manager V1
 * @dev Главный контракт-менеджер платформы RWA. Использует паттерн UUPS.
 *
 * Storage layout (порядок НЕЛЬЗЯ менять при апгрейде):
 *   slot 0-49  : OZ gaps
 *   slot 50    : rwaToken
 *   slot 51    : kycPassport
 */
contract AssetManagerV1 is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    address public rwaToken;    // slot 50
    address public kycPassport; // slot 51

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address _rwaToken, address _kycPassport)
        public initializer
    {
        require(defaultAdmin  != address(0), "AssetManager: zero admin");
        require(_rwaToken     != address(0), "AssetManager: zero rwaToken");
        require(_kycPassport  != address(0), "AssetManager: zero kycPassport");

        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE,      defaultAdmin);

        rwaToken    = _rwaToken;
        kycPassport = _kycPassport;
    }

    /**
     * @notice Проверяет KYC-статус пользователя через баланс KYC Passport NFT.
     * @dev ИСПРАВЛЕНИЕ (Security bug): предыдущая версия возвращала
     *      `user != address(0)` — все считались верифицированными.
     *      Теперь проверяем реальный баланс ERC-721 Soulbound NFT.
     */
    function isUserVerified(address user) public view returns (bool) {
        if (user == address(0)) return false;
        return IERC721(kycPassport).balanceOf(user) > 0;
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}
}
