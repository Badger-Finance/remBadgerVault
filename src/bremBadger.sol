// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract bremBadger is ERC20Upgradeable, Initializable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // The start of the program is set retroactively to Feb 18, 2024. 
    // This mean that the unlock must occur 9 months after this, on Nov 18, 2024. 
    // The timestamp for this is: 1731888000
    uint256 public constant UNLOCK_TIMESTAMP = 1731888000;
    uint256 public constant VESTING_WEEKS = 12;
    uint256 public constant ONE_WEEK_IN_SECONDS = 1 weeks;

    IERC20 public immutable REM_BADGER_TOKEN;
    address public immutable OWNER;

    uint256 public depositStart;
    uint256 public depositEnd;
    mapping(address => uint256) public numVestings;

    modifier onlyOwner() {
        require(msg.sender == OWNER, "Only owner");
        _;
    }

    constructor(address _remBadgerToken, address _owner) {
        _disableInitializers();

        OWNER = _owner;
        REM_BADGER_TOKEN = IERC20(_remBadgerToken);
    }

    function initialize() external initializer {
        ERC20Upgradeable.__ERC20Upgradeable_init("bremBADGER", "bremBADGER");
        UUPSUpgradeable.__UUPSUpgradeable_init();
    }

    function enableDeposits() external onlyOwner {
        depositStart = block.timestamp;
        depositEnd = depositStart + 2 weeks;
    }

    function disableDeposits() external onlyOwner {
        depositEnd = block.timestamp;
    }

    function deposit(uint256 _amount) external {
        require(block.timestamp >= depositStart && block.timestamp < depositEnd, "No more deposits");

        uint256 _pool = balance();
        uint256 _before = REM_BADGER_TOKEN.balanceOf(address(this));
        REM_BADGER_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = REM_BADGER_TOKEN.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
    }

    function withdraw(uint256 amount) external {
        require(block.timestamp >= UNLOCK_TIMESTAMP, "Not yet");

        (uint256 vestedAmount, uint256 numWeeks) = _vestedAmount();

        require(vestedAmount > 0, "zero amount");

        if (numWeeks > 0) {
            numVestings[msg.sender] += numWeeks;
        }

        REM_BADGER_TOKEN.safeTransfer(msg.sender, vestedAmount);
        // TODO: emit event
    }

    function _vestedAmount() private view returns (uint256 vestedAmount, uint256 numWeeks) {
        uint256 shares = balanceOf(msg.sender);

        if (shares == 0) return 0;

        uint256 remainingWeeks = VESTING_WEEKS - numVestings[msg.sender];

        if (remainingWeeks > 0) {
            shares = shares / remainingWeeks;
        }
        
        uint256 numWeeks = (block.timestamp - UNLOCK_TIMESTAMP) / ONE_WEEK_IN_SECONDS;

        if (numWeeks > remainingWeeks) {
            numWeeks = remainingWeeks;
        }

        shares = numWeeks > 0 ? shares * numWeeks : shares;

        _burn(msg.sender, shares);

        return (shares * getPricePerFullShare(), numWeeks);
    }

    function available() public view returns (uint256) {
        if (block.timestamp < UNLOCK_TIMESTAMP) return 0;

        (uint256 vestedAmount, ) = _vestedAmount();

        return vestedAmount;
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
