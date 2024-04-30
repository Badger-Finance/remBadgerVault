// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {bremBadger} from "../src/bremBadger.sol";
import {remBadgerMock} from "./remBadgerMock.sol";
import {BadgerMock} from "./badgerMock.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract bremBadgerTests is Test {

    address internal testOwner;
    address[] internal testUsers;
    BadgerMock public badgerToken;
    remBadgerMock public remBadgerToken;
    bremBadger public bremBadgerToken;

    function setUp() public {
        testOwner = vm.addr(0x12345);
        badgerToken = new BadgerMock();
        remBadgerToken = new remBadgerMock(address(badgerToken));
        
        bremBadger impl = new bremBadger(address(remBadgerToken), testOwner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");

        bremBadgerToken = bremBadger(address(proxy));

        vm.prank(testOwner);
        bremBadgerToken.initialize();

        testUsers = new address[](10);
        for (uint256 i; i < 10; i++) {
            testUsers[i] = vm.addr(0x100000000 + i);
            badgerToken.mint(testUsers[i], 100000e18);
            vm.startPrank(testUsers[i]);
            badgerToken.approve(address(remBadgerToken), type(uint256).max);
            remBadgerToken.deposit(100000e18);
            vm.stopPrank();
        }
    }

    function testDeposit() public {
        vm.prank(testUsers[0]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        // Cannot deposit before deposit period
        vm.expectRevert("No more deposits");
        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(100e18);

        // Only owner can enable deposits
        vm.expectRevert("Only owner");
        vm.prank(testUsers[0]);
        bremBadgerToken.enableDeposits();

        // Enable deposits
        assertEq(bremBadgerToken.depositStart(), 0);
        assertEq(bremBadgerToken.depositEnd(), 0);
        vm.prank(testOwner);
        bremBadgerToken.enableDeposits();
        assertEq(bremBadgerToken.depositStart(), block.timestamp);
        assertEq(bremBadgerToken.depositEnd(), block.timestamp + 2 weeks);

        // Deposit 100 remBadger
        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(100e18);  
        assertEq(bremBadgerToken.balanceOf(testUsers[0]), 100e18);
        assertEq(bremBadgerToken.getPricePerFullShare(), 1e18); 

        // Cannot deposit after 2 weeks
        vm.warp(block.timestamp + 2 weeks);
        vm.expectRevert("No more deposits");
        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(100e18);
    }

    function testWithdraw() public {
        vm.prank(testOwner);
        bremBadgerToken.enableDeposits();

        vm.prank(testUsers[0]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(100e18);

        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), 0);

        // Cannot withdraw before unlock period
        vm.expectRevert("Not yet");
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();

        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP());
        uint256 vestingPerWeek = 100e18 / uint256(12);
        uint256 totalVesting;
        for (uint256 i; i < 12; i++) {
            assertEq(bremBadgerToken.vestedAmount(testUsers[0]), totalVesting);
            vm.warp(block.timestamp + 1 weeks);
            totalVesting += vestingPerWeek;
        }
        // Total should match underlying amount
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), 100e18);

        // Cannot withdraw unless user has deposits
        vm.expectRevert("zero shares");
        vm.prank(testUsers[1]);
        bremBadgerToken.withdrawAll();

        uint256 balBefore = remBadgerToken.balanceOf(testUsers[0]);
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();
        uint256 balAfter = remBadgerToken.balanceOf(testUsers[0]);
        assertEq(balAfter - balBefore, 100e18);
    }

    function testWithdrawPartially() public {
        vm.prank(testOwner);
        bremBadgerToken.enableDeposits();

        vm.prank(testUsers[0]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        uint256 depositAmount = 100e18;
        uint256 vestingPerWeek = depositAmount / 12;
        uint256 residualAmount = depositAmount % 12;

        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(depositAmount);

        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 1 weeks - 1);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), 0);
        vm.warp(block.timestamp + 1);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), vestingPerWeek);

        uint256 balBefore = remBadgerToken.balanceOf(testUsers[0]);
        uint256 initBalance = balBefore;
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();   

        assertEq(remBadgerToken.balanceOf(testUsers[0]) - balBefore, vestingPerWeek);
        assertEq(bremBadgerToken.numVestings(testUsers[0]), 1);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), 0);

        vm.warp(block.timestamp + 2 weeks - 1);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), vestingPerWeek);
        vm.warp(block.timestamp + 1);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), vestingPerWeek * 2);

        balBefore = remBadgerToken.balanceOf(testUsers[0]);
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();

        assertEq(remBadgerToken.balanceOf(testUsers[0]) - balBefore, vestingPerWeek * 2);
        assertEq(bremBadgerToken.numVestings(testUsers[0]), 3);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), 0);

        vm.warp(block.timestamp + 6 weeks - 1);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), vestingPerWeek * 5);
        vm.warp(block.timestamp + 1);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), vestingPerWeek * 6);

        balBefore = remBadgerToken.balanceOf(testUsers[0]);
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();

        assertEq(remBadgerToken.balanceOf(testUsers[0]) - balBefore, vestingPerWeek * 6);
        assertEq(bremBadgerToken.numVestings(testUsers[0]), 9);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), 0);

        vm.warp(block.timestamp + 3 weeks - 1);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), vestingPerWeek * 2);
        // Residual amount added to final week
        vm.warp(block.timestamp + 1);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), vestingPerWeek * 3 + residualAmount);
        // Vesting amount doesn't change after final week
        vm.warp(block.timestamp + 1);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), vestingPerWeek * 3 + residualAmount);

        vm.warp(block.timestamp + 100);
        balBefore = remBadgerToken.balanceOf(testUsers[0]);
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();

        assertEq(remBadgerToken.balanceOf(testUsers[0]) - balBefore, vestingPerWeek * 3 + residualAmount);
        assertEq(remBadgerToken.balanceOf(testUsers[0]) - initBalance, depositAmount);
        assertEq(bremBadgerToken.numVestings(testUsers[0]), 12);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), 0);

        vm.expectRevert("zero shares");
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();
    }

    function testMultipleUsers() public {
        vm.prank(testOwner);
        bremBadgerToken.enableDeposits();

        vm.prank(testUsers[0]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        vm.prank(testUsers[1]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        uint256 depositAmount = 467e18;
        uint256 vestingPerWeek1 = depositAmount / 12;
        uint256 vestingPerWeek2 = depositAmount * 2 / 12;
        uint256 residualAmount = depositAmount % 12;

        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(depositAmount);

        vm.prank(testUsers[1]);
        bremBadgerToken.deposit(depositAmount * 2);

        uint256 initBal1 = remBadgerToken.balanceOf(testUsers[0]);
        uint256 initBal2 = remBadgerToken.balanceOf(testUsers[1]);

        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 5 weeks);

        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), vestingPerWeek1 * 5);
        assertEq(bremBadgerToken.vestedAmount(testUsers[1]), vestingPerWeek2 * 5);

        uint256 balBefore = remBadgerToken.balanceOf(testUsers[0]);
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();

        assertEq(remBadgerToken.balanceOf(testUsers[0]) - balBefore, vestingPerWeek1 * 5);

        balBefore = remBadgerToken.balanceOf(testUsers[1]);
        vm.prank(testUsers[1]);
        bremBadgerToken.withdrawAll();

        assertEq(remBadgerToken.balanceOf(testUsers[1]) - balBefore, vestingPerWeek2 * 5);

        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), 0);
        assertEq(bremBadgerToken.vestedAmount(testUsers[1]), 0);

        vm.warp(block.timestamp + 10 weeks);

        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), depositAmount - vestingPerWeek1 * 5);
        assertEq(bremBadgerToken.vestedAmount(testUsers[1]), depositAmount * 2 - vestingPerWeek2 * 5);

        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();

        assertEq(remBadgerToken.balanceOf(testUsers[0]) - initBal1, depositAmount);

        vm.prank(testUsers[1]);
        bremBadgerToken.withdrawAll();     

        assertEq(remBadgerToken.balanceOf(testUsers[1]) - initBal2, depositAmount * 2);

        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), 0);
        assertEq(bremBadgerToken.vestedAmount(testUsers[1]), 0); 
    }

    function testPricePerShareWithDonation() public {
        vm.prank(testOwner);
        bremBadgerToken.enableDeposits();

        vm.prank(testUsers[0]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(100e18);

        // Donate 10 remBadger
        vm.prank(testUsers[1]);
        remBadgerToken.transfer(address(bremBadgerToken), 10e18);    
        assertEq(bremBadgerToken.getPricePerFullShare(), 1.1e18); 
    }

    function testWithdrawAfterDonation() public {
        vm.prank(testOwner);
        bremBadgerToken.enableDeposits();

        vm.prank(testUsers[0]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        vm.prank(testUsers[1]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        uint256 vestingPerWeek1 = 100e18 / uint256(12);
        uint256 vestingPerWeek2 = 200e18 / uint256(12);

        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(100e18);

        vm.prank(testUsers[1]);
        bremBadgerToken.deposit(200e18);

        uint256 initBal1 = remBadgerToken.balanceOf(testUsers[0]);
        uint256 initBal2 = remBadgerToken.balanceOf(testUsers[1]);

        vm.prank(testUsers[2]);
        remBadgerToken.transfer(address(bremBadgerToken), 30e18);    
        assertEq(bremBadgerToken.getPricePerFullShare(), 1.1e18); 

        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 1 weeks);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), vestingPerWeek1 * 1.1e18 / 1e18);
        assertEq(bremBadgerToken.vestedAmount(testUsers[1]), vestingPerWeek2 * 1.1e18 / 1e18);

        vm.warp(block.timestamp + 20 weeks);

        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();

        vm.prank(testUsers[1]);
        bremBadgerToken.withdrawAll();

        assertEq(remBadgerToken.balanceOf(testUsers[0]) - initBal1, 110e18);
        assertEq(remBadgerToken.balanceOf(testUsers[1]) - initBal2, 220e18);
    }

    function testEarlyTerminationBeforeUnlock() public {
        vm.prank(testOwner);
        bremBadgerToken.enableDeposits();

        vm.prank(testUsers[0]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        uint256 depositAmount = 100e18;

        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(depositAmount);

        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), 0);

        vm.expectRevert("Only owner");
        vm.prank(testUsers[2]);
        bremBadgerToken.terminate();

        vm.prank(testOwner);
        bremBadgerToken.terminate();

        vm.expectRevert("No more deposits");
        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(depositAmount);

        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), depositAmount);

        uint256 balBefore = remBadgerToken.balanceOf(testUsers[0]);
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();
        uint256 balAfter = remBadgerToken.balanceOf(testUsers[0]);

        assertEq(balAfter - balBefore, depositAmount);
        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), 0);
    }

    function testEarlyTerminationAfterUnlock() public {
        vm.prank(testOwner);
        bremBadgerToken.enableDeposits();

        vm.prank(testUsers[0]);
        remBadgerToken.approve(address(bremBadgerToken), type(uint256).max);

        uint256 depositAmount = 100e18;
        uint256 vestingPerWeek = depositAmount / 12;
        uint256 residualAmount = depositAmount % 12;

        vm.prank(testUsers[0]);
        bremBadgerToken.deposit(depositAmount);

        uint256 initBal = remBadgerToken.balanceOf(testUsers[0]);

        vm.warp(bremBadgerToken.UNLOCK_TIMESTAMP() + 3 weeks);

        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), vestingPerWeek * 3);

        uint256 balBefore = remBadgerToken.balanceOf(testUsers[0]);
        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();

        assertEq(remBadgerToken.balanceOf(testUsers[0]) - balBefore, vestingPerWeek * 3);

        vm.expectRevert("Only owner");
        vm.prank(testUsers[2]);
        bremBadgerToken.terminate();

        vm.prank(testOwner);
        bremBadgerToken.terminate();

        assertEq(bremBadgerToken.vestedAmount(testUsers[0]), depositAmount - vestingPerWeek * 3);

        vm.prank(testUsers[0]);
        bremBadgerToken.withdrawAll();

        assertEq(remBadgerToken.balanceOf(testUsers[0]) - initBal, depositAmount);
    }
}
