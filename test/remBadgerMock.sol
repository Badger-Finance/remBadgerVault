// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract remBadgerMock is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable BADGER_TOKEN;

    constructor(address badgerToken) ERC20("remBadger", "remBadger") {
        BADGER_TOKEN = ERC20(badgerToken);
    }

    function deposit(uint256 _amount) external {
        require(_amount > 0);

        uint256 balBefore = BADGER_TOKEN.balanceOf(address(this));
        BADGER_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 balAfter = BADGER_TOKEN.balanceOf(address(this));

        _amount = balAfter - balBefore; // Additional check for deflationary tokens

        uint256 totalShares = totalSupply();
        uint256 sharesToMint;
        if (totalShares == 0) {
            sharesToMint = _amount;
        } else {
            sharesToMint = _amount * totalShares / balBefore;
        }

        _mint(msg.sender, sharesToMint);
    }

    function withdraw(uint256 _shares) external {
        require(_shares <= balanceOf(msg.sender));
        uint256 amountToTransfer = _shares * getPricePerFullShare();
        _burn(msg.sender, _shares);

        BADGER_TOKEN.safeTransfer(msg.sender, amountToTransfer);
    }

    function getPricePerFullShare() public view returns (uint256) {
        if (totalSupply() == 0) {
            return 1e18;
        }
        return BADGER_TOKEN.balanceOf(address(this)) * 1e18 / totalSupply();
    }
}
