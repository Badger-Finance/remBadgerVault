
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseSetup} from "@chimera/BaseSetup.sol";

import "src/bremBadger.sol";
import "./MockERC20.sol";

abstract contract Setup is BaseSetup {

    MockERC20 want;
    bremBadger vault;

    uint256 totalDeposited;
    uint256 totalWithdrawn;


    function setup() internal virtual override {
      want = new MockERC20("remBadger", "rBADGER");
      vault = new bremBadger(address(want), address(this), address(this));

      want.mint(address(this), 1_000_000e18);
      want.approve(address(vault), type(uint256).max);
    }
}
