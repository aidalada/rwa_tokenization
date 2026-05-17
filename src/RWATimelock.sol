// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title RWA Timelock Controller
 * @dev Временной замок, который будет выступать в роли владельца (Owner) всех контрактов платформы.
 * Обеспечивает задержку выполнения решений DAO в 2 дня по требованиям ТЗ.
 */
contract RWATimelock is TimelockController {
    /**
     * @param minDelay Минимальное время задержки (для ТЗ передадим 2 days = 172800 секунд)
     * @param proposers Список адресов, имеющих право вносить предложения (здесь будет адрес Governor)
     * @param executors Список адресов, имеющих право исполнять предложения (обычно address(0) — кто угодно)
     * @param admin Администратор таймлока (DAO передаст управление самой себе, убрав EOA админов)
     */
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}
}
