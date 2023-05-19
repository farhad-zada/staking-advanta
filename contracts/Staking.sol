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
TESTs DONE = V
_V__1. ERC20:           CREATE one token for METO, mint for three adresses
_V__2. ERC751 NFT:      create two, one for LAND and one for METAHUT, mint for three addresses
_V__3. STAKE:           ORDINARY
_V__4. CLAIM:
_V__5. STAKE:           LAND
_V__6. CLAIM:
_V__7. STAKE:           METAHUT
_V__8. CLAIM:
_V__9. STAKE:           LEVEL
_V__10. CLAIM:
_V__11. ADMIN:           SET & UNSET
_V__12. CLAIM BEFORE DEADLINE
_V__13. CLAIM EARLY & CHECK PENALTY

*/

contract Staking is Initializable, OwnableUpgradeable {
    IERC20Upgradeable public token;
    IERC721Upgradeable public land;
    IERC721Upgradeable public metahut;
    ILevels public levels;

    uint256 public totalStakedToken;
    uint256 public totalStakedLand;
    uint256 public totalStakedMetahut;

    uint256 public rewardPercentage;
    uint256 public rewardPercentageLand;
    uint256 public rewardPercentageMetahut;
    uint256 public penaltyPercentage;
    uint256 public rewardDeadlineSeconds;

    uint256 public poolMaxSize;
    uint256 public minStakingAmount;
    uint256 public maxStakingAmount;
    uint256 public penaltyDivisionStep;

    address public address(metahut);

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
    mapping(address => bool) public admins;
    mapping(address => Staking[]) public stakings;
    mapping(NftType => IERC721Upgradeable) internal _typeToNft;
    mapping(address => mapping(uint256 => address)) public owners;
    mapping(address => mapping(address => uint256[])) public ownings;
    mapping(address => bool) private _nonReentrant;
    mapping(uint64 => uint256) public levelReward;

    event Stake(address indexed staker, Staking staking);
    event Claim(address indexed staker, Staking staking);

    // Modifiers

    modifier stakeAvailable(address _staker, uint256 _amount) {
        if (_amount < minStakingAmount)
            revert Staking__NotAvailable({amount: _amount});
        if (totalStakedToken + _amount > poolMaxSize)
            revert Staking__NotAvailable({amount: totalStakedToken + _amount});
        if (stakeStatus != StakeStatus.ACTIVE)
            revert Staking__StatusNotActive();
        if (getUserTotalStakedTokenAmount(_staker) + _amount > maxStakingAmount)
            revert Staking__NotAvailable({amount: _amount});
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
        token = IERC20Upgradeable(_token);
        land = IERC721Upgradeable(_land);
        metahut = IERC721Upgradeable(_metahut);
        _typeToNft[NftType.LAND] = land;
        _typeToNft[NftType.METAHUT] = metahut;
        levels = ILevels(_levels);

        rewardPercentage = 10;
        rewardPercentageLand = 20;
        rewardPercentageMetahut = 30;
        penaltyPercentage = 10;
        rewardDeadlineSeconds = 3600 * 24 * 30 * 3; // 3 months

        poolMaxSize = 20_000_000 * 10e18;
        minStakingAmount = 20_000 * 10e18;
        maxStakingAmount = 500_000 * 10e18;
        penaltyDivisionStep = 30 * 3;
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
            owners[address(land)][nftId] = staker;
            ownings[address(land)][staker].push(nftId);
            staking.percent = rewardPercentageLand;
        } else if (nftType == NftType.METAHUT) {
            metahut.transferFrom(sponsor, address(this), nftId);
            totalStakedMetahut += 1;
            owners[address(metahut)][nftId] = staker;
            ownings[address(metahut)][staker].push(nftId);
            staking.percent = rewardPercentageMetahut;
        } else {
            staking.percent = rewardPercentage;
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
            _remove(staker, index, staking.nftId, address(land));
            totalStakedLand -= 1;
        } else if (staking.nftType == NftType.METAHUT) {
            metahut.transferFrom(address(this), staker, staking.nftId);
            _remove(staker, index, staking.nftId, address(metahut));
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
        uint256 chunkSize = rewardDeadlineSeconds / penaltyDivisionStep;
        uint256 chunkPercent = (penaltyPercentage * 10e10) /
            penaltyDivisionStep;
        uint256 percent = penaltyPercentage *
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
        if (secondsStaked < rewardDeadlineSeconds) {
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
        if (secondsStaked < rewardDeadlineSeconds) {
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
        rewardDeadlineSeconds = deadline;
    }
}
