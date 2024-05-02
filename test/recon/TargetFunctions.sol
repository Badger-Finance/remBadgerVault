
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {vm} from "@chimera/Hevm.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {

    function bremBadger_deposit(uint256 _amount) public {
      vault.deposit(_amount);
      totalDeposited += _amount;
    }

    function bremBadger_disableDeposits() public {
      vault.disableDeposits();
    }

    function bremBadger_enableDeposits() public {
      vault.enableDeposits();
    }


    function bremBadger_terminate() public {
      require(totalDeposited == 1_000_000e18); // Force fuzzer to spend time befor this
      vault.terminate();
    }

    function bremBadger_withdrawAll() public {
      uint256 balB4 = want.balanceOf(address(this));
      vault.withdrawAll();

      totalWithdrawn += want.balanceOf(address(this)) - balB4;
    }
}
