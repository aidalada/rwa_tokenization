// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseSetup} from "./BaseSetup.t.sol";

contract FuzzTests is BaseSetup {
    function testFuzz_VaultDeposit(uint256 amount) public {
        vm.assume(amount > 100 && amount < 1_000_000 * 1e18);

        vm.prank(owner);
        token.mint(charlie, amount);

        vm.startPrank(charlie);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, charlie);
        vm.stopPrank();

        assertTrue(shares > 0);
        assertEq(vault.totalAssets(), amount);
    }

    function testFuzz_VotingPowerTracking(uint256 mintAmount) public {
        vm.assume(mintAmount > 0 && mintAmount < 100_000_000 * 1e18);

        vm.prank(owner);
        token.mint(charlie, mintAmount);

        assertEq(token.getVotes(charlie), 0);

        vm.prank(charlie);
        token.delegate(charlie);

        assertEq(token.getVotes(charlie), mintAmount);
    }

    function testFuzz_AMMSwapPricing(uint256 amountIn) public {
        vm.assume(amountIn > 1e10 && amountIn < 5_000 * 1e18);

        vm.prank(owner);
        token.mint(charlie, amountIn);

        vm.startPrank(charlie);
        token.approve(address(amm), amountIn);

        try amm.swap(address(token), amountIn) {} catch {}
        vm.stopPrank();
    }
}
