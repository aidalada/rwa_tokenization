// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseSetup} from "./BaseSetup.t.sol";
import {RWAAMM} from "../src/RWAAMM.sol";
import {RWAToken} from "../src/RWAToken.sol";

contract AMMHandler {
    RWAAMM public amm;
    RWAToken public token;

    constructor(RWAAMM _amm, RWAToken _token) {
        amm = _amm;
        token = _token;
    }

    function swapRandom(uint256 amount) public {
        amount = uint256(keccak256(abi.encodePacked(amount))) % (100 * 1e18);
        if (amount == 0) amount = 1e18;

        token.mint(address(this), amount);
        token.approve(address(amm), amount);

        try amm.swap(address(token), amount) {} catch {}
    }
}

contract InvariantTests is BaseSetup {
    AMMHandler public handler;

    function setUp() public override {
        super.setUp();
        handler = new AMMHandler(amm, token);
        targetContract(address(handler));
    }

    // ИНВАРИАНТ: Пул ликвидности никогда не должен быть полностью опустошен
    function invariant_AMMHasLiquidity() public view {
        uint256 balanceX = token.balanceOf(address(amm));
        assertTrue(balanceX > 0);
    }

    // ИНВАРИАНТ: Сумма балансов на ключевых контрактах не превышает общий саплай
    function invariant_TotalSupplyIntegrity() public view {
        uint256 calculatedSupply = token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(address(amm))
            + token.balanceOf(address(vault));

        assertTrue(calculatedSupply <= token.totalSupply());
    }
}
