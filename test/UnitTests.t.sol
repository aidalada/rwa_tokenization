// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseSetup} from "./BaseSetup.t.sol";

contract UnitTests is BaseSetup {
    function test_Mint_RevertIfNotOwner() public {
        vm.expectRevert();
        vm.prank(alice);
        token.mint(bob, 1000 * 1e18);
    }

    function test_Mint_SuccessAsOwner() public {
        vm.prank(owner);
        token.mint(bob, 1000 * 1e18);
        assertEq(token.balanceOf(bob), 11_000 * 1e18);
    }

    function test_Transfer_RevertIfInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 50_000 * 1e18); // Больше, чем есть у Элис
    }

    function test_Transfer_SuccessWithBalances() public {
        vm.prank(alice);
        token.transfer(bob, 500 * 1e18);
        assertEq(token.balanceOf(bob), 10_500 * 1e18);
    }

    function test_Vault_DepositRevertIfNoAllowance() public {
        vm.prank(alice);
        vm.expectRevert(); // Упадёт, так как нет approve для Vault
        vault.deposit(1000 * 1e18, alice);
    }

    function test_Vault_ShareCalculation() public {
        vm.startPrank(alice);
        token.approve(address(vault), 1000 * 1e18);
        uint256 shares = vault.deposit(1000 * 1e18, alice);
        vm.stopPrank();

        assertTrue(shares > 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_Governance_ProposeRevertBelowThreshold() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(0);
        values[0] = 0;
        calldatas[0] = "";

        vm.prank(charlie); // У Чарли 0 голосов, порог 5000 не пройден
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Proposal #1");
    }
}
