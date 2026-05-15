// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RWA Token
 * @dev Реализация базового RWA токена с поддержкой Permit (gasless approvals) 
 * и Votes (checkpointing балансов для Governance).
 */
contract RWAToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address defaultAdmin)
        ERC20("Real World Asset", "RWA")
        ERC20Permit("Real World Asset")
    {
        // Назначаем deployer'а главным админом и даем ему право минта (пока для тестов)
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, defaultAdmin);
    }

    /**
     * @dev Функция для чеканки новых токенов. Вызвать может только аккаунт с MINTER_ROLE.
     * В будущем эта роль будет передана смарт-контракту, ответственному за эмиссию.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }


    /**
     * @dev Хук, который вызывается при любом перемещении токенов.
     * Нужен для правильной работы ERC20Votes (создание снапшотов балансов).
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    /**
     * @dev Переопределение nonces для совместной работы ERC20Permit и ERC20Votes.
     */
    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}