// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RWAToken} from "../src/RWAToken.sol";
import {KYCPassport} from "../src/KYCPassport.sol";
import {RWAVault} from "../src/RWAVault.sol";
import {RWAAMM} from "../src/RWAAMM.sol";
import {RWAOracle} from "../src/RWAOracle.sol";
import {RWAGovernor} from "../src/RWAGovernor.sol";
import {RWATimelock} from "../src/RWATimelock.sol";

abstract contract BaseSetup is Test {
    RWAToken public token;
    KYCPassport public passport;
    RWAVault public vault;
    RWAAMM public amm;
    RWAOracle public oracle;
    RWAGovernor public governor;
    RWATimelock public timelock;

    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);

    address[] public proposers;
    address[] public executors;

    function setUp() public virtual {
        vm.startPrank(owner);

        token = new RWAToken(owner);
        passport = new KYCPassport(owner);

        oracle = new RWAOracle(address(0), address(0));
        vault = new RWAVault(token);
        amm = new RWAAMM(address(token), address(0));

        proposers.push(owner);
        executors.push(address(0));
        timelock = new RWATimelock(1 days, proposers, executors, owner);

        // Установили порог 5000 * 1e18, чтобы адреса с 0 балансом гарантированно получали revert
        governor = new RWAGovernor(token, timelock, 1 days, 1 weeks, 5000 * 1e18);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        timelock.grantRole(proposerRole, address(governor));

        token.mint(alice, 10_000 * 1e18);
        token.mint(bob, 10_000 * 1e18);
        token.mint(address(amm), 50_000 * 1e18);

        vm.stopPrank();
    }
}
