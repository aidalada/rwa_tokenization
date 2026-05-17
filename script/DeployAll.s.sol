// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RWAToken} from "../src/RWAToken.sol";
import {KYCPassport} from "../src/KYCPassport.sol";
import {RWATimelock} from "../src/RWATimelock.sol";
import {RWAGovernor} from "../src/RWAGovernor.sol";

contract DeployAll is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        require(deployerPrivateKey != 0, "Error: DEPLOYER_PRIVATE_KEY not set");

        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log(">>> Deployer wallet address derived:", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        // --- 1. ИДЕМПОТЕНТНЫЙ ДЕПЛОЙ RWATOKEN ---
        RWAToken rwaToken;
        {
            address tokenAddr = vm.envOr("DEPLOYED_RWA_TOKEN", address(0));
            if (tokenAddr != address(0) && tokenAddr.code.length > 0) {
                console.log(">>> [SKIP] RWAToken already deployed at:", tokenAddr);
                rwaToken = RWAToken(tokenAddr);
            } else {
                rwaToken = new RWAToken(deployerAddress);
                console.log(">>> [DEPLOYED] RWAToken address:", address(rwaToken));
            }
        }

        // --- 2. ИДЕМПОТЕНТНЫЙ ДЕПЛОЙ KYC PASSPORT ---
        {
            address kycAddr = vm.envOr("DEPLOYED_KYC_PASSPORT", address(0));
            if (kycAddr != address(0) && kycAddr.code.length > 0) {
                console.log(">>> [SKIP] KYCPassport already deployed at:", kycAddr);
            } else {
                KYCPassport kycPassport = new KYCPassport(deployerAddress);
                console.log(">>> [DEPLOYED] KYCPassport address:", address(kycPassport));
            }
        }

        // --- 3. ИДЕМПОТЕНТНЫЙ ДЕПЛОЙ TIMELOCK ---
        RWATimelock timelock;
        {
            address timelockAddr = vm.envOr("DEPLOYED_TIMELOCK", address(0));
            if (timelockAddr != address(0) && timelockAddr.code.length > 0) {
                console.log(">>> [SKIP] RWATimelock already deployed at:", timelockAddr);
                timelock = RWATimelock(payable(timelockAddr));
            } else {
                address[] memory proposers = new address[](0);
                address[] memory executors = new address[](0);
                uint256 minDelay = vm.envOr("TIMELOCK_MIN_DELAY", uint256(2 days));
                timelock = new RWATimelock(minDelay, proposers, executors, deployerAddress);
                console.log(">>> [DEPLOYED] RWATimelock address:", address(timelock));
            }
        }

        // --- 4. ИДЕМПОТЕНТНЫЙ ДЕПЛОЙ GOVERNOR & НАСТРОЙКА ПРАВ ---
        {
            address govAddr = vm.envOr("DEPLOYED_GOVERNOR", address(0));
            if (govAddr != address(0) && govAddr.code.length > 0) {
                console.log(">>> [SKIP] RWAGovernor already deployed at:", govAddr);
            } else {
                RWAGovernor governor = new RWAGovernor(
                    rwaToken,
                    timelock,
                    uint48(vm.envOr("GOVERNOR_VOTING_DELAY", uint256(1 days))),
                    uint32(vm.envOr("GOVERNOR_VOTING_PERIOD", uint256(1 weeks))),
                    vm.envOr("GOVERNOR_THRESHOLD", uint256(10_000 * 1e18))
                );
                console.log(">>> [DEPLOYED] RWAGovernor address:", address(governor));

                if (address(timelock) != address(0) && timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployerAddress))
                {
                    console.log(">>> Configuring DAO Roles and transferring ownership...");
                    timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
                    timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
                    timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployerAddress);
                    console.log(">>> Access rights successfully transferred to Governor DAO!");
                }
            }
        }

        vm.stopBroadcast();
    }
}
