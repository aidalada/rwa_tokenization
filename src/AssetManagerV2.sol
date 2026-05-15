// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetManagerV1} from "./AssetManagerV1.sol";

/**
 * @title Asset Manager V2
 * @dev Пример обновления (V1 -> V2).
 * Наследуем V1, чтобы гарантировать сохранение Storage Layout.
 */
contract AssetManagerV2 is AssetManagerV1 {
    // V2 Storage
    uint256 public platformFee;

    /**
     * @dev Новая функция, которая появилась только во второй версии.
     */
    function setPlatformFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        platformFee = _fee;
    }

    /**
     * @dev Переопределение логики (если нужно изменить старое поведение).
     */
    function version() external pure returns (string memory) {
        return "V2";
    }
}
