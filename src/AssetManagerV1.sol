// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title Asset Manager V1
 * @dev Главный контракт-менеджер платформы RWA. Использует паттерн UUPS.
 */
contract AssetManagerV1 is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // V1 Storage
    address public rwaToken;
    address public kycPassport;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Запрещаем инициализацию логического контракта (implementation) напрямую
        _disableInitializers();
    }

    /**
     * @dev Функция инициализации (заменяет constructor для прокси).
     * Вызывается только один раз при деплое прокси-контракта.
     */
    function initialize(address defaultAdmin, address _rwaToken, address _kycPassport) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, defaultAdmin);

        rwaToken = _rwaToken;
        kycPassport = _kycPassport;
    }

    /**
     * @dev Функция, разрешающая обновление контракта.
     * Критически важно: только адреса с ролью UPGRADER_ROLE могут накатить новую версию.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @dev Пример функции V1: проверка, есть ли у юзера KYC-паспорт.
     */
    function isUserVerified(address user) public pure returns (bool) {
        return user != address(0);
    }
}
