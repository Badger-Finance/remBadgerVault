
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import {Setup} from "./Setup.sol";

abstract contract Properties is Setup, Asserts {
  // Property that asserts we never get more
  function never_claimed_more() public {
    t(totalWithdrawn <= totalDeposited, "never more");
  }

  // Property that asserts that the check never reverts
  function it_never_reverts_and_is_never_more() public {
    try vault.vestedAmount(address(this)) returns (uint256 amt) {
      t(amt <= totalDeposited, "never more than deposited");
    } catch {
      t(false, "never reverts");
    }
  }
}
