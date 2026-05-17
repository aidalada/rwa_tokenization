// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {RWAToken} from "../src/RWAToken.sol";
import {KYCPassport} from "../src/KYCPassport.sol";
import {RWAFactory} from "../src/RWAFactory.sol";
import {AssetManagerV1} from "../src/AssetManagerV1.sol";
import {AssetManagerV2} from "../src/AssetManagerV2.sol";

/**
 * @title CoreContractsTest — Participant 1
 * @notice Полное покрытие: RWAToken, KYCPassport, RWAFactory, AssetManager UUPS.
 *         Unit тесты: все public/external функции включая revert-пути.
 *         Fuzz тесты: access control, votes, factory.
 */
contract CoreContractsTest is Test {

    RWAToken       public rwaToken;
    KYCPassport    public kycPassport;
    RWAFactory     public factory;
    AssetManagerV1 public proxyManager;

    address public admin   = makeAddr("admin");
    address public alice   = makeAddr("alice");
    address public bob     = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    function setUp() public {
        vm.startPrank(admin);

        rwaToken    = new RWAToken(admin);
        kycPassport = new KYCPassport(admin);
        factory     = new RWAFactory(admin); // ИСПРАВЛЕНО: передаём admin

        AssetManagerV1 impl = new AssetManagerV1();
        bytes memory initData = abi.encodeWithSelector(
            AssetManagerV1.initialize.selector,
            admin, address(rwaToken), address(kycPassport)
        );
        proxyManager = AssetManagerV1(address(new ERC1967Proxy(address(impl), initData)));

        vm.stopPrank();
    }

    // =========================================================================
    // RWAToken
    // =========================================================================

    function test_Token_InitialState() public view {
        assertEq(rwaToken.name(), "Real World Asset");
        assertEq(rwaToken.symbol(), "RWA");
        assertEq(rwaToken.totalSupply(), 0);
        assertTrue(rwaToken.hasRole(rwaToken.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(rwaToken.hasRole(rwaToken.MINTER_ROLE(), admin));
        assertTrue(rwaToken.hasRole(rwaToken.PAUSER_ROLE(), admin));
    }

    function test_Token_Mint_Success() public {
        vm.prank(admin);
        rwaToken.mint(alice, 1000e18);
        assertEq(rwaToken.balanceOf(alice), 1000e18);
        assertEq(rwaToken.totalSupply(), 1000e18);
    }

    function test_Token_Mint_RevertNotMinter() public {
        vm.prank(alice);
        vm.expectRevert();
        rwaToken.mint(alice, 1000e18);
    }

    function test_Token_Mint_RevertToZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        rwaToken.mint(address(0), 1000e18);
    }

    function test_Token_Transfer_Success() public {
        vm.prank(admin);
        rwaToken.mint(alice, 1000e18);
        vm.prank(alice);
        rwaToken.transfer(bob, 400e18);
        assertEq(rwaToken.balanceOf(alice), 600e18);
        assertEq(rwaToken.balanceOf(bob), 400e18);
    }

    function test_Token_Transfer_RevertInsufficientBalance() public {
        vm.prank(admin);
        rwaToken.mint(alice, 100e18);
        vm.prank(alice);
        vm.expectRevert();
        rwaToken.transfer(bob, 200e18);
    }

    function test_Token_Pause_BlocksTransfer() public {
        vm.prank(admin);
        rwaToken.mint(alice, 1000e18);
        vm.prank(admin);
        rwaToken.pause();
        assertTrue(rwaToken.paused());
        vm.prank(alice);
        vm.expectRevert();
        rwaToken.transfer(bob, 100e18);
    }

    function test_Token_Pause_BlocksMint() public {
        vm.prank(admin);
        rwaToken.pause();
        vm.prank(admin);
        vm.expectRevert();
        rwaToken.mint(alice, 100e18);
    }

    function test_Token_Unpause_AllowsTransfer() public {
        vm.prank(admin);
        rwaToken.mint(alice, 1000e18);
        vm.prank(admin); rwaToken.pause();
        vm.prank(admin); rwaToken.unpause();
        assertFalse(rwaToken.paused());
        vm.prank(alice);
        rwaToken.transfer(bob, 100e18);
        assertEq(rwaToken.balanceOf(bob), 100e18);
    }

    function test_Token_Pause_RevertNotPauser() public {
        vm.prank(alice);
        vm.expectRevert();
        rwaToken.pause();
    }

    function test_Token_Votes_DelegateAndCheck() public {
        vm.prank(admin);
        rwaToken.mint(alice, 1000e18);
        vm.prank(alice);
        rwaToken.delegate(alice);
        assertEq(rwaToken.getVotes(alice), 1000e18);
    }

    function test_Token_Votes_TransferReducesPower() public {
        vm.prank(admin);
        rwaToken.mint(alice, 1000e18);
        vm.prank(alice);
        rwaToken.delegate(alice);
        vm.prank(alice);
        rwaToken.transfer(bob, 300e18);
        assertEq(rwaToken.getVotes(alice), 700e18);
    }

    function test_Token_Permit_Works() public {
        uint256 pk = 0xA11CE;
        address owner = vm.addr(pk);
        vm.prank(admin);
        rwaToken.mint(owner, 1000e18);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _permitDigest(address(rwaToken), owner, alice, 500e18, 0, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        rwaToken.permit(owner, alice, 500e18, deadline, v, r, s);
        assertEq(rwaToken.allowance(owner, alice), 500e18);
    }

    function test_Token_GrantRole() public {
        vm.prank(admin);
        rwaToken.grantRole(rwaToken.MINTER_ROLE(), alice);
        vm.prank(alice);
        rwaToken.mint(bob, 500e18);
        assertEq(rwaToken.balanceOf(bob), 500e18);
    }

    function test_Token_RevokeRole() public {
        vm.startPrank(admin);
        rwaToken.grantRole(rwaToken.MINTER_ROLE(), alice);
        rwaToken.revokeRole(rwaToken.MINTER_ROLE(), alice);
        vm.stopPrank();
        vm.prank(alice);
        vm.expectRevert();
        rwaToken.mint(alice, 100e18);
    }

    // =========================================================================
    // KYCPassport
    // =========================================================================

    function test_KYC_InitialState() public view {
        assertEq(kycPassport.name(), "KYC Passport");
        assertTrue(kycPassport.hasRole(kycPassport.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(kycPassport.hasRole(kycPassport.KYC_ISSUER_ROLE(), admin));
    }

    function test_KYC_Issue_Success() public {
        vm.prank(admin);
        kycPassport.issuePassport(alice);
        assertEq(kycPassport.balanceOf(alice), 1);
        assertEq(kycPassport.ownerOf(0), alice);
    }

    function test_KYC_Issue_RevertNotIssuer() public {
        vm.prank(alice);
        vm.expectRevert();
        kycPassport.issuePassport(bob);
    }

    function test_KYC_Issue_RevertDuplicate() public {
        vm.startPrank(admin);
        kycPassport.issuePassport(alice);
        vm.expectRevert("KYCPassport: Address already has a passport");
        kycPassport.issuePassport(alice);
        vm.stopPrank();
    }

    function test_KYC_Issue_RevertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        kycPassport.issuePassport(address(0));
    }

    function test_KYC_Soulbound_TransferReverts() public {
        vm.prank(admin);
        kycPassport.issuePassport(alice);
        vm.prank(alice);
        vm.expectRevert("KYCPassport: Token is Soulbound and non-transferable");
        kycPassport.transferFrom(alice, bob, 0);
    }

    function test_KYC_Revoke_Burns() public {
        vm.startPrank(admin);
        kycPassport.issuePassport(alice);
        kycPassport.revokePassport(0);
        assertEq(kycPassport.balanceOf(alice), 0);
        vm.stopPrank();
    }

    function test_KYC_Revoke_RevertNotIssuer() public {
        vm.prank(admin);
        kycPassport.issuePassport(alice);
        vm.prank(alice);
        vm.expectRevert();
        kycPassport.revokePassport(0);
    }

    function test_KYC_MultipleUsers_SequentialIds() public {
        vm.startPrank(admin);
        kycPassport.issuePassport(alice);
        kycPassport.issuePassport(bob);
        kycPassport.issuePassport(charlie);
        vm.stopPrank();
        assertEq(kycPassport.ownerOf(0), alice);
        assertEq(kycPassport.ownerOf(1), bob);
        assertEq(kycPassport.ownerOf(2), charlie);
    }

    function test_KYC_GrantIssuerRole() public {
        vm.prank(admin);
        kycPassport.grantRole(kycPassport.KYC_ISSUER_ROLE(), alice);
        vm.prank(alice);
        kycPassport.issuePassport(bob);
        assertEq(kycPassport.balanceOf(bob), 1);
    }

    function test_KYC_SupportsInterface_ERC721() public view {
        assertTrue(kycPassport.supportsInterface(0x80ac58cd));
    }

    // =========================================================================
    // RWAFactory
    // =========================================================================

    function test_Factory_DeployWithCreate_Success() public {
        vm.prank(admin);
        address deployed = factory.deployWithCreate(admin);
        assertNotEq(deployed, address(0));
        assertTrue(RWAToken(deployed).hasRole(RWAToken(deployed).DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_Factory_DeployWithCreate_RevertNotOperator() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.deployWithCreate(admin);
    }

    function test_Factory_DeployWithCreate2_PredictAddress() public {
        bytes32 salt = keccak256("salt_test");
        address predicted = factory.predictTokenAddress(admin, salt);
        vm.prank(admin);
        address deployed = factory.deployWithCreate2(admin, salt);
        assertEq(predicted, deployed, "Predicted != deployed");
    }

    function test_Factory_DeployWithCreate2_RevertNotOperator() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.deployWithCreate2(admin, bytes32(0));
    }

    function test_Factory_DeployWithCreate2_DifferentSalts() public {
        vm.startPrank(admin);
        address a = factory.deployWithCreate2(admin, keccak256("salt_a"));
        address b = factory.deployWithCreate2(admin, keccak256("salt_b"));
        vm.stopPrank();
        assertNotEq(a, b);
    }

    function test_Factory_DeployWithCreate2_SameSaltReverts() public {
        bytes32 salt = keccak256("reused");
        vm.startPrank(admin);
        factory.deployWithCreate2(admin, salt);
        vm.expectRevert();
        factory.deployWithCreate2(admin, salt);
        vm.stopPrank();
    }

    function test_Factory_GrantOperatorRole() public {
        vm.prank(admin);
        factory.grantRole(factory.FACTORY_OPERATOR_ROLE(), alice);
        vm.prank(alice);
        address deployed = factory.deployWithCreate(admin);
        assertNotEq(deployed, address(0));
    }

    // =========================================================================
    // AssetManager UUPS
    // =========================================================================

    function test_Manager_Initialize_StorageCorrect() public view {
        assertEq(proxyManager.rwaToken(), address(rwaToken));
        assertEq(proxyManager.kycPassport(), address(kycPassport));
        assertTrue(proxyManager.hasRole(proxyManager.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_Manager_IsUserVerified_WithKYC() public {
        assertFalse(proxyManager.isUserVerified(alice));
        vm.prank(admin);
        kycPassport.issuePassport(alice);
        assertTrue(proxyManager.isUserVerified(alice));
    }

    function test_Manager_IsUserVerified_ZeroAddress() public view {
        assertFalse(proxyManager.isUserVerified(address(0)));
    }

    function test_Manager_IsUserVerified_AfterRevoke() public {
        vm.startPrank(admin);
        kycPassport.issuePassport(alice);
        assertTrue(proxyManager.isUserVerified(alice));
        kycPassport.revokePassport(0);
        assertFalse(proxyManager.isUserVerified(alice));
        vm.stopPrank();
    }

    function test_Manager_IsUserVerified_NoKYC() public view {
        assertFalse(proxyManager.isUserVerified(bob));
    }

    function test_Manager_UpgradeToV2_Success() public {
        vm.startPrank(admin);
        AssetManagerV2 implV2 = new AssetManagerV2();
        proxyManager.upgradeToAndCall(address(implV2), "");
        AssetManagerV2 v2 = AssetManagerV2(address(proxyManager));
        assertEq(v2.version(), "V2");
        assertEq(v2.rwaToken(), address(rwaToken));
        v2.setPlatformFee(500);
        assertEq(v2.platformFee(), 500);
        vm.stopPrank();
    }

    function test_Manager_UpgradeToV2_StoragePreserved() public {
        vm.startPrank(admin);
        AssetManagerV2 implV2 = new AssetManagerV2();
        proxyManager.upgradeToAndCall(address(implV2), "");
        AssetManagerV2 v2 = AssetManagerV2(address(proxyManager));
        assertEq(v2.rwaToken(), address(rwaToken));
        assertEq(v2.kycPassport(), address(kycPassport));
        vm.stopPrank();
    }

    function test_Manager_Upgrade_RevertNotUpgrader() public {
        AssetManagerV2 implV2 = new AssetManagerV2();
        vm.prank(alice);
        vm.expectRevert();
        proxyManager.upgradeToAndCall(address(implV2), "");
    }

    function test_Manager_Initialize_RevertDoubleInit() public {
        vm.prank(alice);
        vm.expectRevert();
        proxyManager.initialize(alice, address(rwaToken), address(kycPassport));
    }

    function test_Manager_Initialize_RevertZeroAdmin() public {
        AssetManagerV1 impl = new AssetManagerV1();
        vm.expectRevert("AssetManager: zero admin");
        new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(AssetManagerV1.initialize.selector, address(0), address(rwaToken), address(kycPassport))
        );
    }

    // =========================================================================
    // Fuzz
    // =========================================================================

    function testFuzz_Token_OnlyMinterCanMint(address randomUser, uint256 amount) public {
        vm.assume(randomUser != admin && randomUser != address(0));
        vm.prank(randomUser);
        vm.expectRevert();
        rwaToken.mint(randomUser, amount);
    }

    function testFuzz_KYC_OnlyIssuerCanIssue(address randomUser, address target) public {
        vm.assume(randomUser != admin && target != address(0));
        vm.prank(randomUser);
        vm.expectRevert();
        kycPassport.issuePassport(target);
    }

    function testFuzz_Factory_OnlyOperatorCanDeploy(address randomUser) public {
        vm.assume(randomUser != admin && randomUser != address(0));
        vm.prank(randomUser);
        vm.expectRevert();
        factory.deployWithCreate(admin);
    }

    function testFuzz_Manager_IsUserVerified_AlwaysFalseWithoutKYC(address user) public view {
        vm.assume(user != address(0));
        assertFalse(proxyManager.isUserVerified(user));
    }

    function testFuzz_Token_VotesMatchBalance(uint256 amount) public {
        amount = bound(amount, 1, 1e30);
        vm.prank(admin);
        rwaToken.mint(alice, amount);
        vm.prank(alice);
        rwaToken.delegate(alice);
        assertEq(rwaToken.getVotes(alice), amount);
    }

    // =========================================================================
    // Helper
    // =========================================================================

    function _permitDigest(
        address token, address owner, address spender,
        uint256 value, uint256 nonce, uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        return keccak256(abi.encodePacked(
            "\x19\x01",
            RWAToken(token).DOMAIN_SEPARATOR(),
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline))
        ));
    }
}
