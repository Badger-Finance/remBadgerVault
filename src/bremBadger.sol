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
    // This mean that the unlock must occur 9 months after this, on Nov 18, 2024. 
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

    event DepositsEnabled(uint256 start, uint256 end);
    event DepositsDisabled();

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
        depositStart = block.timestamp;
        depositEnd = block.timestamp + DEPOSIT_PERIOD_IN_SECONDS;

        require(depositEnd < UNLOCK_TIMESTAMP);

        emit DepositsEnabled(depositStart, depositEnd);
    }

    function disableDeposits() external onlyOwner {
        depositEnd = block.timestamp;

        emit DepositsDisabled();
    }

    function deposit(uint256 _amount) external nonReentrant {
        require(block.timestamp >= depositStart && block.timestamp < depositEnd, "No more deposits");
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
    }

    function withdrawAll() external nonReentrant {
        require(block.timestamp >= UNLOCK_TIMESTAMP, "Not yet");

        (uint256 shares, uint256 numWeeks) = _vestedShares();

        require(shares > 0, "zero shares");

        uint256 vestedAmount = shares * getPricePerFullShare();

        _burn(msg.sender, shares);

        if (numWeeks > 0) {
            numVestings[msg.sender] += numWeeks;
        }

        REM_BADGER_TOKEN.safeTransfer(msg.sender, vestedAmount);

        // TODO: emit event
    }

    function _vestedShares() private view returns (uint256, uint256) {
        uint256 shares = balanceOf(msg.sender);

        if (shares == 0) return (0, 0);

        uint256 remainingWeeks = VESTING_WEEKS - numVestings[msg.sender];

        if (remainingWeeks == 0) return (0, 0);
        if (remainingWeeks == 1) return (shares, 1);

        shares = shares / remainingWeeks;
        
        uint256 numWeeks = (block.timestamp - UNLOCK_TIMESTAMP) / ONE_WEEK_IN_SECONDS;

        if (numWeeks > remainingWeeks) {
            numWeeks = remainingWeeks;
        }

        shares = numWeeks > 0 ? shares * numWeeks : shares;

        return (shares, numWeeks);
    }

    function vestedAmount() public view returns (uint256) {
        if (block.timestamp < UNLOCK_TIMESTAMP) return 0;

        (uint256 shares, ) = _vestedShares();

        return shares * getPricePerFullShare();
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
