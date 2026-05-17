// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RWAToken} from "./RWAToken.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RWA Factory
 * @dev Деплоит новые RWA токены через CREATE и CREATE2.
 *
 * ИСПРАВЛЕНИЕ (Security): добавлен AccessControl — только FACTORY_OPERATOR_ROLE
 * может деплоить токены. Без этого любой мог создавать поддельные RWA токены.
 *
 * Паттерн: Factory (CREATE + CREATE2).
 */
contract RWAFactory is AccessControl {
    bytes32 public constant FACTORY_OPERATOR_ROLE = keccak256("FACTORY_OPERATOR_ROLE");

    event TokenDeployed(address indexed token, address indexed tokenAdmin, bool usedCreate2, bytes32 salt);

    constructor(address defaultAdmin) {
        require(defaultAdmin != address(0), "RWAFactory: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE,       defaultAdmin);
        _grantRole(FACTORY_OPERATOR_ROLE,    defaultAdmin);
    }

    /// @notice Деплой через CREATE (адрес недетерминирован).
    function deployWithCreate(address tokenAdmin)
        external onlyRole(FACTORY_OPERATOR_ROLE) returns (address deployed)
    {
        require(tokenAdmin != address(0), "RWAFactory: zero tokenAdmin");
        RWAToken t = new RWAToken(tokenAdmin);
        deployed = address(t);
        emit TokenDeployed(deployed, tokenAdmin, false, bytes32(0));
    }

    /// @notice Деплой через CREATE2 (адрес детерминирован по salt).
    function deployWithCreate2(address tokenAdmin, bytes32 salt)
        external onlyRole(FACTORY_OPERATOR_ROLE) returns (address deployed)
    {
        require(tokenAdmin != address(0), "RWAFactory: zero tokenAdmin");
        RWAToken t = new RWAToken{salt: salt}(tokenAdmin);
        deployed = address(t);
        emit TokenDeployed(deployed, tokenAdmin, true, salt);
    }

    /// @notice Предвычисление адреса CREATE2 до деплоя.
    function predictTokenAddress(address tokenAdmin, bytes32 salt) public view returns (address) {
        bytes32 initHash = keccak256(
            abi.encodePacked(type(RWAToken).creationCode, abi.encode(tokenAdmin))
        );
        return address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, initHash)
        ))));
    }
}
