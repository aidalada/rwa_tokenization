// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {RWAToken} from "../src/RWAToken.sol";
import {KYCPassport} from "../src/KYCPassport.sol";
import {RWAFactory} from "../src/RWAFactory.sol";
import {AssetManagerV1} from "../src/AssetManagerV1.sol";
import {AssetManagerV2} from "../src/AssetManagerV2.sol";

contract CoreContractsTest is Test {
    RWAToken public rwaToken;
    KYCPassport public kycPassport;
    RWAFactory public factory;

    AssetManagerV1 public managerV1;
    AssetManagerV2 public managerV2;
    AssetManagerV1 public proxyManager;

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        vm.startPrank(admin);

        rwaToken = new RWAToken(admin);
        kycPassport = new KYCPassport(admin);
        factory = new RWAFactory();

        managerV1 = new AssetManagerV1();

        bytes memory initData =
            abi.encodeWithSelector(AssetManagerV1.initialize.selector, admin, address(rwaToken), address(kycPassport));

        ERC1967Proxy proxy = new ERC1967Proxy(address(managerV1), initData);

        proxyManager = AssetManagerV1(address(proxy));

        vm.stopPrank();
    }

    // UNIT TESTS: RWAToken & KYCPassport

    function test_RWAToken_MintingAndPausing() public {
        vm.startPrank(admin);

        rwaToken.mint(alice, 1000 * 1e18);
        assertEq(rwaToken.balanceOf(alice), 1000 * 1e18);

        rwaToken.pause();
        assertTrue(rwaToken.paused());

        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert();
        rwaToken.transfer(bob, 100 * 1e18);
    }

    function test_KYCPassport_IssueAndSoulbound() public {
        vm.startPrank(admin);

        kycPassport.issuePassport(alice);
        assertEq(kycPassport.balanceOf(alice), 1);

        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert("KYCPassport: Token is Soulbound and non-transferable");
        kycPassport.transferFrom(alice, bob, 0);
    }

    // UNIT TESTS: RWAFactory (CREATE2)

    function test_Factory_DeployWithCreate2() public {
        bytes32 salt = keccak256(abi.encodePacked("test_salt"));

        address predictedAddress = factory.predictTokenAddress(admin, salt);

        address deployedAddress = factory.deployWithCreate2(admin, salt);

        assertEq(predictedAddress, deployedAddress);

        RWAToken newToken = RWAToken(deployedAddress);
        assertEq(newToken.hasRole(newToken.DEFAULT_ADMIN_ROLE(), admin), true);
    }

    // UNIT TESTS: UUPS Upgrade (V1 -> V2)

    function test_AssetManager_UpgradeToV2() public {
        vm.startPrank(admin);

        assertEq(proxyManager.rwaToken(), address(rwaToken));

        managerV2 = new AssetManagerV2();

        proxyManager.upgradeToAndCall(address(managerV2), "");

        AssetManagerV2 upgradedManager = AssetManagerV2(address(proxyManager));

        assertEq(upgradedManager.rwaToken(), address(rwaToken));

        assertEq(upgradedManager.version(), "V2");
        upgradedManager.setPlatformFee(500);
        assertEq(upgradedManager.platformFee(), 500);

        vm.stopPrank();
    }

    // FUZZ TESTS: Access Control

    /**
     * @dev Fuzz-тест: проверяем, что случайный адрес НЕ может сминтить токены.
     */
    function testFuzz_RWAToken_OnlyMinterCanMint(address randomUser, uint256 amount) public {
        vm.assume(randomUser != admin);

        vm.prank(randomUser);
        vm.expectRevert();
        rwaToken.mint(randomUser, amount);
    }

    /**
     * @dev Fuzz-тест: проверяем, что случайный адрес НЕ может выдать KYC.
     */
    function testFuzz_KYCPassport_OnlyIssuerCanIssue(address randomUser, address target) public {
        vm.assume(randomUser != admin);
        // Защита от минта на нулевой адрес (ERC721 запрещает это)
        vm.assume(target != address(0));

        vm.prank(randomUser);
        vm.expectRevert();
        kycPassport.issuePassport(target);
    }
}
