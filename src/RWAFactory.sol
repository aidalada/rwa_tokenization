// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RWAToken} from "./RWAToken.sol";

/**
 * @title RWA Factory
 * @dev Фабрика для деплоя новых RWA токенов.
 */
contract RWAFactory {
    event TokenCreated(address indexed tokenAddress, address indexed admin, bool isCreate2);

    /**
     * @dev Деплой токена с использованием стандартного CREATE.
     */
    function deployWithCreate(address defaultAdmin) external returns (address) {
        RWAToken newToken = new RWAToken(defaultAdmin);

        emit TokenCreated(address(newToken), defaultAdmin, false);
        return address(newToken);
    }

    /**
     * @dev Деплой токена с использованием CREATE2.
     */
    function deployWithCreate2(address defaultAdmin, bytes32 salt) external returns (address) {
        RWAToken newToken = new RWAToken{salt: salt}(defaultAdmin);

        emit TokenCreated(address(newToken), defaultAdmin, true);
        return address(newToken);
    }

    /**
     * @dev Вспомогательная функция для предвычисления адреса (только для CREATE2).
     */
    function predictTokenAddress(address defaultAdmin, bytes32 salt) public view returns (address) {
        bytes memory creationCode = type(RWAToken).creationCode;

        bytes memory constructorArgs = abi.encode(defaultAdmin);

        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));

        return address(uint160(uint256(hash)));
    }
}
