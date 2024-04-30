// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {bremBadger} from "../src/bremBadger.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// forge test --fork-url <ALCHEMY_URL> --fork-block-number 19766396 --match-test testDeposit
contract bremBadgerForkTests is Test {
    ERC20 internal remBadgerToken;
    bremBadger internal bremBadgerToken;
    address internal testOwner;
    address[] internal testUsers;

    function setUp() public {
        testOwner = vm.addr(0x12345);
        remBadgerToken = ERC20(0x6aF7377b5009d7d154F36FE9e235aE1DA27Aea22);
        
        bremBadger impl = new bremBadger(address(remBadgerToken), testOwner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");

        bremBadgerToken = bremBadger(address(proxy));

        vm.prank(testOwner);
        bremBadgerToken.initialize();

        testUsers = new address[](1);
        testUsers[0] = 0x564B1a055D9caaaFF7435dcE6B5F6E522b27dE7d;
    }

    function testDeposit() public {
        vm.prank(testUsers[0]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        vm.prank(testOwner);
        bremBadgerToken.enableDeposits();

        uint256 remBal = remBadgerToken.balanceOf(testUsers[0]);

        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(remBal);

        assertEq(bremBadgerToken.balanceOf(testUsers[0]), remBal);
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
        assertEq(bremBadgerToken.numVestings(testUsers[0]), 5);

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
}