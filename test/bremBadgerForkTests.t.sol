// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {bremBadger} from "../src/bremBadger.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

interface IProxyAdmin {
    function owner() external view returns (address);
    function upgradeAndCall(address proxy, address implementation, bytes memory data) external payable;
}

// forge test --fork-url <ALCHEMY_URL> --fork-block-number 19766396 --match-test testDeposit
contract bremBadgerForkTests is Test {
    ERC20 internal remBadgerToken;
    bremBadger internal bremBadgerToken;
    address internal testOwner;
    address[] internal testUsers;
    IProxyAdmin internal proxyAdmin;

    function setUp() public {
        testOwner = vm.addr(0x12345);
        remBadgerToken = ERC20(0x6aF7377b5009d7d154F36FE9e235aE1DA27Aea22);
        proxyAdmin = IProxyAdmin(0x20Dce41Acca85E8222D6861Aa6D23B6C941777bF);
        
        bremBadger impl = new bremBadger(address(remBadgerToken), testOwner, address(proxyAdmin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");

        bremBadgerToken = bremBadger(address(proxy));

        vm.prank(testOwner);
        bremBadgerToken.initialize();

        testUsers = new address[](2);
        testUsers[0] = 0x564B1a055D9caaaFF7435dcE6B5F6E522b27dE7d;
        testUsers[1] = 0xeD5e679d74273Ca5C319DAc2229f2e87E20903Ea;
    }

    function testDeposit() public {
        vm.prank(testUsers[0]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        vm.prank(testOwner);
        bremBadgerToken.enableDeposits();

        uint256 remBal = remBadgerToken.balanceOf(testUsers[0]);

        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(remBal);

        assertEq(bremBadgerToken.totalDeposited(testUsers[0]), remBal);
        assertEq(remBadgerToken.balanceOf(testUsers[0]), 0);
    }

    function testWithdraw() public {
        vm.prank(testUsers[0]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        vm.prank(testOwner);
        bremBadgerToken.enableDeposits();

        uint256 remBal = remBadgerToken.balanceOf(testUsers[0]);
        uint256 remBalPerWeek = remBal / 12;
        uint256 remBalRemainder = remBal % 12;

        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(remBal);

        vm.expectRevert("Not yet");
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll(); 

        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 5 weeks);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), remBalPerWeek * 5);

        uint256 balBefore = remBadgerToken.balanceOf(testUsers[0]);
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll(); 
        uint256 balAfter = remBadgerToken.balanceOf(testUsers[0]);

        assertEq(balAfter - balBefore, remBalPerWeek * 5);
        assertEq(bremBadgerToken.totalClaimed(testUsers[0]), remBalPerWeek * 5);

        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 16 weeks);

        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), remBal - remBalPerWeek * 5);

        balBefore = remBadgerToken.balanceOf(testUsers[0]);
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll(); 
        balAfter = remBadgerToken.balanceOf(testUsers[0]);

        // Final amount equals to starting amount
        assertEq(balAfter - balBefore, remBalPerWeek * 7 + remBalRemainder);
        assertEq(remBadgerToken.balanceOf(testUsers[0]), remBal);        
    }

    function testWithdrawMultipleDepositors() public {
        vm.prank(testUsers[0]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);
        vm.prank(testUsers[1]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        vm.prank(testOwner);
        bremBadgerToken.enableDeposits();

        uint256 remBal1 = remBadgerToken.balanceOf(testUsers[0]);
        uint256 remBal2 = remBadgerToken.balanceOf(testUsers[1]);

        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(remBal1);
        vm.prank(testUsers[1]);
        bremBadgerToken.deposit(remBal2);

        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 1 weeks);
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();
        assertEq(remBadgerToken.balanceOf(testUsers[0]), remBal1 / 12);        
        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 2 weeks);
        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 3 weeks);
        vm.prank(testUsers[1]);
        bremBadgerToken.withdrawAll();
        assertEq(remBadgerToken.balanceOf(testUsers[1]), remBal2 / 12 * 3);        
        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 4 weeks);
        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 5 weeks);
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();
        assertEq(remBadgerToken.balanceOf(testUsers[0]), remBal1 / 12 * 5);        
        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 12 weeks);
        vm.prank(testUsers[1]);
        bremBadgerToken.withdrawAll();
        assertEq(remBadgerToken.balanceOf(testUsers[1]), remBal2 / 12 * 12 + remBal2 % 12);        
        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 13 weeks);
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();
        assertEq(remBadgerToken.balanceOf(testUsers[0]), remBal1 / 12 * 12 + remBal1 % 12);        

        assertEq(remBadgerToken.balanceOf(testUsers[0]), remBal1);        
        assertEq(remBadgerToken.balanceOf(testUsers[1]), remBal2);        
    }

    function testProxyUpgrade() public {
        // new owner used to verify the upgrade
        address newOwner = vm.addr(0x11111);
        bremBadger newImpl = new bremBadger(address(remBadgerToken), newOwner, address(proxyAdmin));

        vm.expectRevert("Only admin");
        vm.prank(testOwner);
        bremBadgerToken.upgradeToAndCall(address(newImpl), "");

        assertEq(bremBadgerToken.OWNER(), testOwner);

        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgradeAndCall(address(bremBadgerToken), address(newImpl), "");

        assertEq(bremBadgerToken.OWNER(), newOwner);
    }
}