// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RdacStaking is Initializable, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable, Ownable2StepUpgradeable {
    bytes32 public constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");

    uint256 private entered;
    uint256 private stakingId;
    address public tokenContractAddress;
    mapping(address => mapping(uint256 => Staking)) staking;

    event Stake(uint256 indexed id, address indexed holder, uint256 amount, uint256 ts, uint256 lockDay);
    event Unstake(uint256 indexed id, address indexed holder, uint256 amount, uint256 ts);

    modifier nonReentrant() {
        require(entered != 2, "REENTRANT");
        entered = 2;
        _;
        entered = 1;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _tokenContractAddress) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __Ownable_init(msg.sender);
        __Ownable2Step_init();

        _grantRole(UPGRADE_ROLE, msg.sender);

        tokenContractAddress = _tokenContractAddress;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADE_ROLE) {
    }

    /**
     * @dev stake tokens
     *
     */
    function stake(uint256 _amount, uint256 _lockDays) external nonReentrant whenNotPaused {
        if (_lockDays == 2 || _lockDays == 30 || _lockDays == 60 || _lockDays == 90) {
            _transferToken(msg.sender, address(this), _amount);

            uint256 unlockAt = block.timestamp + _lockDays * 86400;
            staking[msg.sender][++stakingId] = Staking({
                amount: _amount,
                unlockAt: unlockAt,
                lockDays: _lockDays
            });
            emit Stake(stakingId, msg.sender, _amount, block.timestamp, _lockDays);
        } else {
            revert InvalidLockDay();
        }
    }

    /**
     * @dev unstake tokens
     *
     */
    function unstake(uint256 _id) external nonReentrant whenNotPaused {
        uint256 _amount = staking[msg.sender][_id].amount;
        if (_amount == 0) revert StakingNotFound();
        if (staking[msg.sender][_id].unlockAt > block.timestamp) revert NotUnlock();

        staking[msg.sender][_id] = Staking({amount: 0, lockDays: 0, unlockAt: 0});

        emit Unstake(_id, msg.sender, _amount, block.timestamp);

        _transferToken(address(this), msg.sender, _amount);
    }

    /**
     * @dev Grants `role` to `account`.
     */
    function grantRole(bytes32 role, address account) public override onlyOwner {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     */
    function revokeRole(bytes32 role, address account) public override onlyOwner {
        _revokeRole(role, account);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * transfer $RDAC
     */
    function _transferToken(address _from, address _to, uint256 _amount) internal {
        IERC20 asset = IERC20(tokenContractAddress);
        if (_from == address(this)) { // transfer out
            bool succ = asset.transfer(_to, _amount);
            if (!succ) revert PaymentFailed();
        } else { // transfer in
            if (asset.allowance(_from, address(this)) < _amount) // Make sure this is an erc20 token
                revert InsufficientBalance();

            bool succ = asset.transferFrom(_from, _to, _amount);
            if (!succ) revert PaymentFailed();
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    error InvalidLockDay();
    error InsufficientBalance();
    error StakingNotFound();
    error NotUnlock();
    error PaymentFailed();

    struct Staking {
        uint256 amount;
        uint256 unlockAt;
        uint256 lockDays;
    }
}
