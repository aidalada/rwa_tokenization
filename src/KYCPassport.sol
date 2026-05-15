// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title KYC Passport NFT○​ Создание ERC-721/1155 (для Role-gated доступа/KYC).
 * @dev Soulbound ERC-721 токен для подтверждения KYC.
 * Только адреса с ролью KYC_ISSUER_ROLE могут выдавать паспорта.
 * Токены нельзя передавать (transfer) после минта.
 */
contract KYCPassport is ERC721, AccessControl {
    bytes32 public constant KYC_ISSUER_ROLE = keccak256("KYC_ISSUER_ROLE");
    uint256 private _nextTokenId;

    constructor(address defaultAdmin) ERC721("KYC Passport", "KYCP") {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(KYC_ISSUER_ROLE, defaultAdmin);
    }

    /**
     * @dev Выдача KYC-паспорта пользователю.
     * @param to Адрес пользователя, прошедшего KYC.
     */
    function issuePassport(address to) public onlyRole(KYC_ISSUER_ROLE) {
        require(balanceOf(to) == 0, "KYCPassport: Address already has a passport");
        
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }

    /**
     * @dev Аннулирование KYC-паспорта (сжигание), если юзер нарушил правила.
     */
    function revokePassport(uint256 tokenId) public onlyRole(KYC_ISSUER_ROLE) {
        _burn(tokenId);
    }

    // =========================================================================
    // Обязательные переопределения (overrides)
    // =========================================================================

    /**
     * @dev Блокируем любые переводы токена, делая его Soulbound (SBT).
     * Разрешены только минт (from == address(0)) и сжигание (to == address(0)).
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        require(
            from == address(0) || to == address(0),
            "KYCPassport: Token is Soulbound and non-transferable"
        );
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Переопределение supportsInterface из-за множественного наследования.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}