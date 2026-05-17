// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RWA Yield Vault
 * @dev Хранилище стандарта ERC-4626, куда пользователи стейкают RWA для получения доходности.
 */
contract RWAVault is ERC4626 {
    /**
     * @param asset_ Базовый токен (наш RWAToken), который будет стейкаться в хранилище.
     */
    constructor(IERC20 asset_) ERC4626(asset_) ERC20("RWA Yield Vault Share", "vRWA") {}

    /**
     * @dev ЗАЩИТА ОТ ИНФЛЯЦИОННЫХ АТАК (Inflation / Donation Attack).
     * Согласно требованиям ТЗ, мы обязаны защитить первых депозиторов.
     * Возвращая смещение (offset), контракт создает "виртуальные" шары и активы,
     * делая экономически невыгодным манипулирование ценой доли (share price)
     * путем прямой отправки токенов на контракт.
     */
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3; // Смещает точность на 10^3, защищая от проблемы первой пылинки (first deposit bug)
    }
}
