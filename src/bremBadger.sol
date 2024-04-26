// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract bremBadger is ERC20Upgradeable, ReentrancyGuard, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // The start of the program is set retroactively to Feb 18, 2024. 
    // This means that the unlock must occur 9 months after this, on Nov 18, 2024. 
    // The timestamp for this is: 1731888000
    uint256 public constant UNLOCK_TIMESTAMP = 1731888000;
    uint256 public constant VESTING_WEEKS = 12;
    uint256 public constant ONE_WEEK_IN_SECONDS = 1 weeks;
    uint256 public constant DEPOSIT_PERIOD_IN_SECONDS = 2 weeks;

    IERC20 public immutable REM_BADGER_TOKEN;
    address public immutable OWNER;

    uint256 public depositStart;
    uint256 public depositEnd;
    mapping(address => uint256) public numVestings;
    mapping(address => uint256) public sharesPerWeek;
    bool public terminated;

    event DepositsEnabled(uint256 start, uint256 end);
    event DepositsDisabled();
    event Terminated();

    modifier onlyOwner() {
        require(msg.sender == OWNER, "Only owner");
        _;
    }

    constructor(address _remBadgerToken, address _owner) {
        _disableInitializers();

        OWNER = _owner;
        REM_BADGER_TOKEN = IERC20(_remBadgerToken);
    }

    function initialize() external onlyOwner initializer {
        ERC20Upgradeable.__ERC20_init("bremBADGER", "bremBADGER");
        UUPSUpgradeable.__UUPSUpgradeable_init();
    }

    function enableDeposits() external onlyOwner {
        require(depositStart == 0);

        depositStart = block.timestamp;
        depositEnd = block.timestamp + DEPOSIT_PERIOD_IN_SECONDS;

        require(depositEnd < UNLOCK_TIMESTAMP);

        emit DepositsEnabled(depositStart, depositEnd);
    }

    function disableDeposits() external onlyOwner {
        depositEnd = block.timestamp;

        emit DepositsDisabled();
    }

    /// @notice Governance is allowed to terminate the program early if the underlying
    /// BADGER token appreciate significantly in price. Doing so will unlock 100%
    /// of the remBadger tokens immediately.
    function terminate() external onlyOwner {
        terminated = true;

        emit Terminated();
    }

    function deposit(uint256 _amount) external nonReentrant {
        require(
            !terminated && block.timestamp >= depositStart && block.timestamp < depositEnd, 
            "No more deposits"
        );
        require(_amount > 0, "zero amount");

        uint256 balBefore = REM_BADGER_TOKEN.balanceOf(address(this));
        REM_BADGER_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 balAfter = REM_BADGER_TOKEN.balanceOf(address(this));

        _amount = balAfter - balBefore; // Additional check for deflationary tokens

        uint256 totalShares = totalSupply();
        uint256 sharesToMint;
        if (totalShares == 0) {
            sharesToMint = _amount;
        } else {
            sharesToMint = _amount * totalShares / balBefore;
        }

        _mint(msg.sender, sharesToMint);

        sharesPerWeek[msg.sender] = balanceOf(msg.sender) / VESTING_WEEKS;
    }

    function withdrawAll() external nonReentrant {
        uint256 shares;
        if (terminated) {
            shares = balanceOf(msg.sender);
        } else {
            require(block.timestamp > UNLOCK_TIMESTAMP, "Not yet");

            uint256 numWeeks;
            (shares, numWeeks) = _vestedShares(msg.sender);

            if (numWeeks > 0) {
                numVestings[msg.sender] += numWeeks;
            }
        }
        
        require(shares > 0, "zero shares");

        uint256 vestedAmount = _sharesToUnderlyingAmount(shares);

        _burn(msg.sender, shares);

        REM_BADGER_TOKEN.safeTransfer(msg.sender, vestedAmount);
    }

    function _vestedShares(address _depositor) private view returns (uint256, uint256) {
        uint256 shares = balanceOf(_depositor);

        // No shares, 100% vested
        if (shares == 0) return (0, 0);

        uint256 vestedWeeks = numVestings[_depositor];
        uint256 remainingWeeks = VESTING_WEEKS - vestedWeeks;

        // 0 remaining weeks, 100% vested
        if (remainingWeeks == 0) return (0, 0);

        // Return all shares in the final week to prevent residuals from rounding
        if (remainingWeeks == 1) return (shares, 1);

        uint256 sharesPerWeek = sharesPerWeek[_depositor];
        uint256 numWeeks = (block.timestamp - UNLOCK_TIMESTAMP) / ONE_WEEK_IN_SECONDS;
        
        // Return 0 if the vested weeks have already been claimed
        if (numWeeks <= vestedWeeks) return (0, 0);

        numWeeks -= vestedWeeks;

        if (numWeeks >= remainingWeeks) {
            // Clamp to remaining week if someone wants to withdraw after 12 weeks
            return (shares, remainingWeeks);
        } else {
            return (sharesPerWeek * numWeeks, numWeeks);
        }
    }

    function _sharesToUnderlyingAmount(uint256 _shares) private view returns (uint256) {
        return _shares * getPricePerFullShare() / 1e18;
    }

    function vestedAmount(address _depositor) public view returns (uint256) {
        if (terminated) return balanceOf(_depositor);

        if (block.timestamp <= UNLOCK_TIMESTAMP) return 0;

        (uint256 shares, ) = _vestedShares(_depositor);

        return _sharesToUnderlyingAmount(shares);
    }

    function getPricePerFullShare() public view returns (uint256) {
        if (totalSupply() == 0) {
            return 1e18;
        }
        return REM_BADGER_TOKEN.balanceOf(address(this)) * 1e18 / totalSupply();
    }

    function _authorizeUpgrade(
        address
    ) internal view override onlyOwner {}
}
