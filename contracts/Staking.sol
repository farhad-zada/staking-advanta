// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {ILevels} from "./ILevels.sol";

error Staking__NotAdmin();
error Staking__NotAvailable(uint256 amount);
error Staking__StatusNotActive();
error Staking__InvalidTokenId(uint256 tokenId);
error Staking__InvalidId();
error Staking__InsufficientFunds(uint balance);
error Staking__ContractLacksBalance();
error Staking__TransferFailed();
error Staking__NotEnoughAllowance();

/* @dev

_V__1. ERC20:           CREATE one token for METO, mint for three adresses
_V__2. ERC751 NFT:      create two, one for LAND and one for METAHUT, mint for three addresses
_V__3. STAKE:           ORDINARY
_V__4. CLAIM:
_V__5. STAKE:           LAND
_V__6. CLAIM:
___7. STAKE:           METAHUT
___8. CLAIM:
_V__9. STAKE:           LEVEL
_V__10. CLAIM:
___11. ADMIN:           SET & UNSET
___12. CLAIM BEFORE DEADLINE
___13. CLAIM EARLY & CHECK PENALTY

*/

contract PrevilagedStaking is Initializable, OwnableUpgradeable {
    IERC20Upgradeable public token;
    IERC721Upgradeable public land;
    IERC721Upgradeable public metahut;
    ILevels public levels;

    uint256 public totalStakedToken;
    uint256 public totalStakedLand;
    uint256 public totalStakedMetahut;

    uint256 public REWARD_PERCENTAGE;
    uint256 public REWARD_PERCENTAGE_LAND;
    uint256 public REWARD_PERCENTAGE_METAHUT;
    uint256 public PENALTY_PERCENTAGE;
    // uint256 public constant REWARD_DEADLINE_SECONDS =  3600 * 24 * 30 * 3; // 3 months
    uint256 public REWARD_DEADLINE_SECONDS; // 3 months

    uint256 public POOL_MAX_SIZE; // * 10e18;
    uint256 public MIN_STAKING_AMOUNT; // * 10e18;
    uint256 public MAX_STAKING_AMOUNT; // * 10e18;
    uint256 public PENALTY_DIVISION_STEP; //0 * 3;

    // address public constant TOKEN_CONTRACT_ADDRESS =
    //     0xcD6a42782d230D7c13A74ddec5dD140e55499Df9; //TODO: This addresses are not valid
    // address public constant LAND_CONTRACT_ADDRESS =
    //     0x9d83e140330758a8fFD07F8Bd73e86ebcA8a5692;
    // address public constant METAHUT_CONTRACT_ADDRESS =
    //     0x7b96aF9Bd211cBf6BA5b0dd53aa61Dc5806b6AcE;
    // address public levelContract = 0xe2899bddFD890e320e643044c6b95B9B0b84157A;
    address public TOKEN_CONTRACT_ADDRESS; //TODO: This addresses are not valid
    address public LAND_CONTRACT_ADDRESS;
    address public METAHUT_CONTRACT_ADDRESS;

    enum NftType {
        NONE,
        LAND,
        METAHUT
    }
    enum StakeStatus {
        WAITING,
        ACTIVE,
        PAUSED,
        COMPLETED
    }

    StakeStatus public stakeStatus;

    struct Staking {
        NftType nftType;
        uint256 nftId;
        uint256 amount;
        uint256 percent;
        uint256 stakedAt;
    }
    mapping(address => bool) private admins;
    mapping(address => Staking[]) private stakings;
    mapping(NftType => IERC721Upgradeable) internal _typeToNft;
    mapping(address => mapping(uint256 => address)) private owners;
    mapping(address => mapping(address => uint256[])) private ownings;
    mapping(address => bool) private _nonReentrant;
    mapping(uint64 => uint256) private levelReward;

    event Stake(address indexed staker, Staking staking);
    event Claim(address indexed staker, Staking staking);

    // Modifiers

    modifier stakeAvailable(address _staker, uint256 _amount) {
        if (_amount < MIN_STAKING_AMOUNT)
            revert Staking__NotAvailable({amount: _amount});
        if (totalStakedToken + _amount > POOL_MAX_SIZE)
            revert Staking__NotAvailable({amount: totalStakedToken + _amount});
        if (stakeStatus != StakeStatus.ACTIVE)
            revert Staking__StatusNotActive();
        if (
            getUserTotalStakedTokenAmount(_staker) + _amount >
            MAX_STAKING_AMOUNT
        ) revert Staking__NotAvailable({amount: _amount});
        _;
    }

    modifier admin() {
        if (!admins[msg.sender]) revert Staking__NotAdmin();
        _;
    }
    modifier nonReentrant() {
        require(!_nonReentrant[msg.sender], "Reentrancy");
        _nonReentrant[msg.sender] = true;
        _;
        _nonReentrant[msg.sender] = false;
    }

    // Init

    function initialize(
        address _token,
        address _levels,
        address _land,
        address _metahut
    ) public initializer {
        __Ownable_init();
        admins[msg.sender] = true;
        //TODO: stakeStatus = StakeStatus.ACTIVE;
        token = IERC20Upgradeable(_token);
        TOKEN_CONTRACT_ADDRESS = _token;
        land = IERC721Upgradeable(_land);
        LAND_CONTRACT_ADDRESS = _land;
        metahut = IERC721Upgradeable(_metahut);
        METAHUT_CONTRACT_ADDRESS = _metahut;
        _typeToNft[NftType.LAND] = land;
        _typeToNft[NftType.METAHUT] = metahut;
        levels = ILevels(_levels);

        REWARD_PERCENTAGE = 10;
        REWARD_PERCENTAGE_LAND = 20;
        REWARD_PERCENTAGE_METAHUT = 30;
        PENALTY_PERCENTAGE = 10;
        // uint256 public constant REWARD_DEADLINE_SECONDS =  3600 * 24 * 30 * 3; // 3 months
        REWARD_DEADLINE_SECONDS = 60; // 3 months

        POOL_MAX_SIZE = 20_000_000; // * 10e18;
        MIN_STAKING_AMOUNT = 20_000; // * 10e18;
        MAX_STAKING_AMOUNT = 500_000; // * 10e18;
        PENALTY_DIVISION_STEP = 3; //0 * 3;
    }

    function stake(
        NftType nftType,
        uint256 nftId,
        uint256 _amount,
        bool withLevel
    ) public nonReentrant stakeAvailable(msg.sender, _amount) {
        _stake(nftType, nftId, _amount, msg.sender, msg.sender, withLevel);
    }

    function claim(uint256 _id, NftType nftType) public nonReentrant {
        _claim(msg.sender, _id, nftType);
    }

    function _remove(
        address _staker,
        uint256 _index,
        uint256 _nftId,
        address _nft
    ) internal {
        delete stakings[_staker][_index];
        if (_nft != address(0)) {
            delete owners[_nft][_nftId];
            for (uint i = 0; i < ownings[_nft][_staker].length; i++) {
                if (ownings[_nft][_staker][i] == _nftId) {
                    delete ownings[_nft][_staker][i];
                    return;
                }
            }
        }
    }

    function setStakingStatus(StakeStatus status) public onlyOwner {
        stakeStatus = status;
    }

    function setLevelReward(
        uint64 _level,
        uint256 _rewardPercent
    ) public onlyOwner {
        levelReward[_level] = _rewardPercent;
    }

    function withdraw(address payable who, uint amount) external onlyOwner {
        SafeERC20Upgradeable.safeTransfer(token, who, amount);
    }

    function setAdmin(address who, bool status) public onlyOwner {
        admins[who] = status;
    }

    // Helpers

    function _stake(
        NftType nftType,
        uint256 nftId,
        uint256 _amount,
        address staker,
        address sponsor,
        bool withLevel
    ) internal stakeAvailable(staker, _amount) {
        uint256 _balance = token.balanceOf(sponsor);
        if (_balance < _amount)
            revert Staking__InsufficientFunds({balance: _balance});

        Staking memory staking = Staking({
            nftType: nftType,
            nftId: nftId,
            amount: _amount,
            percent: 0,
            stakedAt: block.timestamp
        });

        if (token.allowance(staker, address(this)) < _amount)
            revert Staking__NotEnoughAllowance();
        token.transferFrom(staker, address(this), _amount);
        totalStakedToken += _amount;

        if (withLevel) {
            staking.percent = levelReward[levels.getLevel(staker)];
        } else if (nftType == NftType.LAND) {
            land.transferFrom(sponsor, address(this), nftId);
            totalStakedLand += 1;
            owners[LAND_CONTRACT_ADDRESS][nftId] = staker;
            ownings[LAND_CONTRACT_ADDRESS][staker].push(nftId);
            staking.percent = REWARD_PERCENTAGE_LAND;
        } else if (nftType == NftType.METAHUT) {
            metahut.transferFrom(sponsor, address(this), nftId);
            totalStakedMetahut += 1;
            owners[METAHUT_CONTRACT_ADDRESS][nftId] = staker;
            ownings[METAHUT_CONTRACT_ADDRESS][staker].push(nftId);
            staking.percent = REWARD_PERCENTAGE_METAHUT;
        } else {
            staking.percent = REWARD_PERCENTAGE;
        }
        stakings[staker].push(staking);
        emit Stake(staker, staking);
    }

    function _claim(address staker, uint256 _id, NftType nftType) internal {
        uint256 _balance = token.balanceOf(address(this));
        int256 _index = _getStakeIndexById(staker, nftType, _id);
        if (_index < 0) revert Staking__InvalidId();
        uint256 index = uint256(_index);

        (uint256 rewardedAmount, uint256 amount) = _getTransferAmount(
            staker,
            index
        );
        if (_balance < rewardedAmount) revert Staking__ContractLacksBalance();

        totalStakedToken -= amount;

        SafeERC20Upgradeable.safeTransfer(token, staker, rewardedAmount);

        Staking memory staking = stakings[staker][uint256(index)];

        if (staking.nftType == NftType.LAND) {
            land.transferFrom(address(this), staker, staking.nftId);
            _remove(staker, index, staking.nftId, LAND_CONTRACT_ADDRESS);
            totalStakedLand -= 1;
        } else if (staking.nftType == NftType.METAHUT) {
            metahut.transferFrom(address(this), staker, staking.nftId);
            _remove(staker, index, staking.nftId, METAHUT_CONTRACT_ADDRESS);
            totalStakedMetahut -= 1;
        } else {
            _remove(staker, index, staking.nftId, address(0));
        }

        emit Claim(staker, staking);
    }

    // State helper funcs

    function _getPenalty(
        uint256 amount,
        uint256 secondsStaked
    ) internal view returns (uint) {
        uint256 chunkSize = REWARD_DEADLINE_SECONDS / PENALTY_DIVISION_STEP;
        uint256 chunkPercent = (PENALTY_PERCENTAGE * 10e10) /
            PENALTY_DIVISION_STEP;
        uint256 percent = PENALTY_PERCENTAGE *
            10e10 -
            ((secondsStaked / chunkSize) * chunkPercent);
        return amount - (((amount * percent) / 100) / 10e10);
    }

    function _getStakeIndexById(
        address _staker,
        NftType _nftType,
        uint256 _id
    ) internal view returns (int256) {
        Staking[] memory _stakings = stakings[_staker];
        for (uint256 i = 0; i < _stakings.length; i++) {
            if (
                _stakings[i].stakedAt == _id && _stakings[i].nftType == _nftType
            ) {
                return int(i);
            }
        }
        return -1;
    }

    function _getTransferAmount(
        address _staker,
        uint256 _index
    ) internal view returns (uint256, uint256) {
        Staking memory staking = stakings[_staker][_index];
        uint256 timestamp = block.timestamp;
        uint256 secondsStaked = timestamp - staking.stakedAt;
        if (secondsStaked < REWARD_DEADLINE_SECONDS) {
            return (_getPenalty(staking.amount, secondsStaked), staking.amount);
        }
        return ((staking.amount * staking.percent) / 100, staking.amount);
    }

    // State read funcs

    function getMyStakes() public view returns (Staking[] memory) {
        return stakings[msg.sender];
    }

    function getStakes(
        address staker
    ) public view onlyOwner returns (Staking[] memory) {
        return stakings[staker];
    }

    function getUserTotalStakedTokenAmount(
        address staker
    ) public view returns (uint256) {
        require(msg.sender == staker || msg.sender == owner(), "Unallowed");
        Staking[] memory _stakings = stakings[staker];
        uint256 total;
        for (uint i = 0; i < _stakings.length; i++) {
            total += _stakings[i].amount;
        }
        return total;
    }

    function getStakeById(
        NftType _nftType,
        uint256 _id
    ) public view returns (Staking memory staking) {
        Staking[] memory _stakings = stakings[msg.sender];
        for (uint256 i = 0; i < _stakings.length; i++) {
            if (
                _stakings[i].stakedAt == _id && _stakings[i].nftType == _nftType
            ) {
                return _stakings[i];
            }
        }
        return Staking(NftType.NONE, 0, 0, 0, 0);
    }

    function getTransferAmount(
        uint256 _index
    ) public view returns (uint256, uint256) {
        Staking memory staking = stakings[msg.sender][_index];
        uint256 timestamp = block.timestamp;
        uint256 secondsStaked = timestamp - staking.stakedAt;
        if (secondsStaked < REWARD_DEADLINE_SECONDS) {
            return (_getPenalty(staking.amount, secondsStaked), staking.amount);
        }
        return ((staking.amount * staking.percent) / 100, staking.amount);
    }

    function isAdminTrue() public view returns (bool) {
        return admins[msg.sender];
    }

    function getIsAdmin(address who) public view onlyOwner returns (bool) {
        return admins[who];
    }

    function getLevelReward(uint64 _level) public view returns (uint256) {
        return levelReward[_level];
    }

    // Admin functions

    // admin sets specific reward percent for user
    function modifyRewardPersentage(
        address staker,
        NftType nftType,
        uint256 id,
        uint256 newPercent
    ) public admin {
        int256 _index = _getStakeIndexById(staker, nftType, id);
        if (_index < 0) revert Staking__InvalidId();
        uint256 index = uint256(_index);

        stakings[staker][index].percent = newPercent;
    }

    // admin sets stake for a specific user
    function setStake(
        address staker,
        NftType nftType,
        uint256 nftId,
        uint256 _amount,
        address sponsor,
        bool withLevel
    ) public admin {
        _stake(nftType, nftId, _amount, staker, sponsor, withLevel);
    }

    // admin claims a specific user
    function claimFor(
        address staker,
        uint256 _id,
        NftType nftType
    ) public admin {
        _claim(staker, _id, nftType);
    }

    //TESTING FUNCS

    function redoRewardDedline(uint256 deadline) public {
        REWARD_DEADLINE_SECONDS = deadline;
    }
}
