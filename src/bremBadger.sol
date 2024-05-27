// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract bremBadger is ReentrancyGuard, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // The start of the program is set retroactively to Feb 18, 2024. 
    // This means that the unlock must occur 9 months after this, on Nov 18, 2024. 
    // The timestamp for this is: 1731888000
    uint256 public constant UNLOCK_TIMESTAMP = 1731888000;
    uint256 public constant VESTING_WEEKS = 12;
    uint256 public constant ONE_WEEK_IN_SECONDS = 1 weeks;
    uint256 public constant DEPOSIT_PERIOD_IN_SECONDS = 2 weeks;

    IERC20 public immutable REM_BADGER_TOKEN;
    /// @notice owner can enable/disable/terminate the vault
    address public immutable OWNER;
    /// @notice admin can upgrade the contract implementation
    address public immutable ADMIN;

    uint256 public depositStart;
    uint256 public depositEnd;
    mapping(address => uint256) public totalDeposited;
    mapping(address => uint256) public totalClaimed;
    bool public terminated;

    event DepositsEnabled(uint256 start, uint256 end);
    event DepositsDisabled();
    event Terminated();

    modifier onlyOwner() {
        require(msg.sender == OWNER, "Only owner");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == ADMIN, "Only admin");
        _;
    }

    constructor(address _remBadgerToken, address _owner, address _admin) {
        _disableInitializers();

        // make sure we can upgrade again
        require(_admin != address(0));

        OWNER = _owner;
        ADMIN = _admin;
        REM_BADGER_TOKEN = IERC20(_remBadgerToken);
    }

    function initialize() external onlyOwner initializer {
        UUPSUpgradeable.__UUPSUpgradeable_init();
    }

    function enableDeposits() external onlyOwner {
        depositStart = block.timestamp;
        depositEnd = block.timestamp + DEPOSIT_PERIOD_IN_SECONDS; /// @audit I think this needs to be changeable since it's starting in a odd way

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

        /// @notice deposit period will end before UNLOCK_TIMESTAMP
        totalDeposited[msg.sender] += balAfter - balBefore;
    }

    function withdrawAll() external nonReentrant {        
        require(terminated || block.timestamp > UNLOCK_TIMESTAMP, "Not yet");

        uint256 vestedAmount = _vestedAmount(msg.sender);

        require(vestedAmount > 0, "zero amount");

        totalClaimed[msg.sender] += vestedAmount;

        REM_BADGER_TOKEN.safeTransfer(msg.sender, vestedAmount);
    }

    function _vestedAmount(address _depositor) private view returns (uint256) {
        uint256 depositAmount = totalDeposited[_depositor];
        uint256 claimedAmount = totalClaimed[_depositor];
        uint256 maxClaim = depositAmount - claimedAmount;

        if (terminated) {
            return maxClaim;
        }

        uint256 sharesPerWeek = depositAmount / VESTING_WEEKS;
        uint256 numWeeks = (block.timestamp - UNLOCK_TIMESTAMP) / ONE_WEEK_IN_SECONDS;

        /// @dev return max claimable amount after the final week to prevent rounding error
        if (numWeeks >= VESTING_WEEKS) {
            return maxClaim;
        }

        uint256 vestingAmount = numWeeks * sharesPerWeek;

        if (vestingAmount <= claimedAmount) {
            return 0;
        }

        vestingAmount -= claimedAmount;

        return vestingAmount > maxClaim ? maxClaim : vestingAmount;
    }
    
    function vestedAmount(address _depositor) public view returns (uint256) {
        if (!terminated && block.timestamp <= UNLOCK_TIMESTAMP) return 0;

        return _vestedAmount(_depositor);
    }

    function _authorizeUpgrade(
        address
    ) internal view override onlyAdmin {}
}
