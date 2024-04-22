// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {bremBadger} from "../src/bremBadger.sol";
import {remBadgerMock} from "./remBadgerMock.sol";
import {BadgerMock} from "./badgerMock.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract bremBadgerForkTests is Test {

    address public testOwner;
    ERC20 public badgerToken;
    ERC20 public remBadgerToken;
    bremBadger public bremBadgerToken;

    function setUp() public {
        testOwner = vm.addr(0x12345);
        badgerToken = new BadgerMock();
        remBadgerToken = new remBadgerMock(address(badgerToken));
        bremBadgerToken = new bremBadger(address(remBadgerToken), testOwner);
    }

    function testDeposit() public {

    }
}
