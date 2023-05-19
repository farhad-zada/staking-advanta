//Contract based on [https://docs.openzeppelin.com/contracts/3.x/erc721](https://docs.openzeppelin.com/contracts/3.x/erc721)
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

contract LandV3 is
    Initializable,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable
{
    IERC20Upgradeable meto;
    IERC20Upgradeable busd;

    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _tokenIds;
    enum ASSET {
        METO,
        BUSD
    }

    struct OptionLaunchpadLand {
        uint ClaimableCount;
        uint ClaimedCount;
    }

    //keep disabled lands ids
    uint256[] public disabledLands;
    //keep investors lands. These lands do not require payment.
    //keep whitelist users list. Whitelist users can buy nfts earlier than others.
    mapping(address => bool) public whiteListAddresses;
    mapping(address => OptionLaunchpadLand) public launchpadLands;
    // use as the index if item not found in array
    uint256 private ID_NOT_FOUND;
    //block transaction or  set new land price if argument = ID_SKIP_PRICE_VALUE
    uint256 private ID_SKIP_PRICE_VALUE;
    uint256 public LAND_PRICE_METO;
    uint256 public LAND_PRICE_BUSD;
    uint256 public WHITELIST_LAND_PRICE_METO;
    uint256 public WHITELIST_LAND_PRICE_BUSD;
    uint256 public BUSD_METO_PAIR; //1 busd value by meto
    //
    //
    uint public MAX_LAND_COUNT_PER_ACCOUNT;
    uint public MAX_ID;
    address public PRICE_UPDATER;

    string public baseTokenURI;
    bool public launchpadSaleStatus;
    bool public whiteListSaleStatus;
    bool public publicSaleStatus;

    event MultipleMint(
        address indexed _from,
        uint256[] tokenIds,
        uint256 _price
    );
    uint256 public TOTAL_PRESOLD;

    // event Claim(address indexed _from, uint256 _tid, uint256 claimableCount, uint256 claimedCount);

    function initialize(address _busd, address _meto) public initializer {
        __ERC721_init("Metafluence Lands", "LAND");
        // __Ownable_init();
        // meto = IERC20Upgradeable(0xc39A5f634CC86a84147f29a68253FE3a34CDEc57); //main
        // busd = IERC20Upgradeable(0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee); //main
        meto = IERC20Upgradeable(_meto);
        busd = IERC20Upgradeable(_busd);
        setBaseURI("https://dcdn.metafluence.com/lands/");
        ID_NOT_FOUND = 9999999999999999999;
        //block transaction or  set new land price if argument = ID_SKIP_PRICE_VALUE
        ID_SKIP_PRICE_VALUE = 9999999999999999;
        LAND_PRICE_METO = 1;
        LAND_PRICE_BUSD = 1;
        WHITELIST_LAND_PRICE_METO = 1;
        WHITELIST_LAND_PRICE_BUSD = 1;
        BUSD_METO_PAIR = 369 * decimals(); //1 busd value by meto
        MAX_LAND_COUNT_PER_ACCOUNT = 94;
        MAX_ID = 24000;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function setBaseURI(string memory _baseTokenURI) public onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    /* Start of Administrative Functions */
    function setLandPriceWithMeto(
        uint256 _price,
        uint256 _whiteListPrice
    ) public onlyOwner {
        if (_price != ID_SKIP_PRICE_VALUE) {
            LAND_PRICE_METO = _price;
        }

        if (_whiteListPrice != ID_SKIP_PRICE_VALUE) {
            WHITELIST_LAND_PRICE_METO = _whiteListPrice;
        }
    }

    function setLandPriceWithBusd(
        uint256 _price,
        uint256 _whiteListPrice
    ) public onlyOwner {
        if (_price != ID_SKIP_PRICE_VALUE) {
            LAND_PRICE_BUSD = _price;
        }

        if (_whiteListPrice != ID_SKIP_PRICE_VALUE) {
            WHITELIST_LAND_PRICE_BUSD = _whiteListPrice;
        }
    }

    function setBusdMetoPair(uint256 _price) public {
        require(
            msg.sender == PRICE_UPDATER || msg.sender == owner(),
            "price updater is not valid."
        );
        BUSD_METO_PAIR = _price;
    }

    function setLandMaxCountPerAccount(uint _v) public onlyOwner {
        MAX_LAND_COUNT_PER_ACCOUNT = _v;
    }

    function setMaxId(uint _v) public onlyOwner {
        MAX_ID = _v;
    }

    function setPriceUpdater(address _v) public onlyOwner {
        PRICE_UPDATER = _v;
    }

    function withdrawMeto(
        address payable addr,
        uint256 _amount
    ) external onlyOwner {
        SafeERC20Upgradeable.safeTransfer(meto, addr, _amount);
    }

    function withdrawBusd(
        address payable addr,
        uint256 _amount
    ) external onlyOwner {
        SafeERC20Upgradeable.safeTransfer(busd, addr, _amount);
    }

    function setLandAsDisabled(uint256[] memory _tids) public onlyOwner {
        for (uint i = 0; i < _tids.length; i++) {
            disabledLands.push(_tids[i]);
        }
    }

    function removeDisableLand(uint256 _tid) public onlyOwner {
        uint256 _index = getDisabledLandIndex(_tid);
        require(_index != ID_NOT_FOUND, "index out of bound.");

        for (uint i = _index; i < disabledLands.length - 1; i++) {
            disabledLands[i] = disabledLands[i + 1];
        }

        disabledLands.pop();
    }

    function getDisabledLandIndex(uint256 _tid) private view returns (uint256) {
        for (uint256 i = 0; i < disabledLands.length; i++) {
            if (disabledLands[i] == _tid) {
                return i;
            }
        }

        return ID_NOT_FOUND;
    }

    //todo allow multiple launchad address insertation
    function setLaunchpadAddresses(
        address[] memory _addrs,
        OptionLaunchpadLand[] memory _options
    ) public onlyOwner {
        for (uint256 i = 0; i < _addrs.length; i++) {
            launchpadLands[_addrs[i]] = _options[i];
        }
    }

    function setWhitelistAddresses(
        address[] memory _addrs,
        bool[] memory _values
    ) public onlyOwner {
        for (uint i = 0; i < _addrs.length; i++) {
            whiteListAddresses[_addrs[i]] = _values[i];
        }
    }

    function setSaleStatus(
        bool _launchpadSaleStatus,
        bool _publicSaleStatus,
        bool _whiteListSaleStatus
    ) public onlyOwner {
        launchpadSaleStatus = _launchpadSaleStatus;
        publicSaleStatus = _publicSaleStatus;
        whiteListSaleStatus = _whiteListSaleStatus;
    }

    function adminMint(address _addr, uint256[] memory lands) public onlyOwner {
        for (uint i = 0; i < lands.length; i++) {
            _safeMint(_addr, lands[i]);
        }
    }

    /* End of Administrative Functions */

    function myCollection(
        address _owner
    ) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokenIds;
    }

    function mintWithMeto(uint256[] memory _tids) public {
        require(whiteListSaleStatus || publicSaleStatus, "sale not started.");
        uint alreadyMinted = balanceOf(msg.sender);
        uint256[] memory filteredLands = filterAvailableLands(_tids);
        uint256 totalPrice = calculateTotalPrice(filteredLands, ASSET.METO);
        require(
            alreadyMinted + _tids.length < MAX_LAND_COUNT_PER_ACCOUNT &&
                meto.balanceOf(msg.sender) > totalPrice &&
                _tids.length +
                    TOTAL_PRESOLD +
                    totalSupply() +
                    disabledLands.length >
                MAX_ID,
            "User has not enough balance."
        );

        SafeERC20Upgradeable.safeTransferFrom(
            meto,
            msg.sender,
            address(this),
            totalPrice
        );

        for (uint i = 0; i < filteredLands.length; i++) {
            if (filteredLands[i] == 0) {
                continue;
            }
            _safeMint(msg.sender, filteredLands[i]);
        }

        emit MultipleMint(msg.sender, filteredLands, totalPrice);
    }

    function mintWithBusd(uint256[] memory _tids) public {
        require(whiteListSaleStatus || publicSaleStatus, "sale not started.");
        uint alreadyMinted = balanceOf(msg.sender);
        uint256[] memory filteredLands = filterAvailableLands(_tids);
        uint256 totalPrice = calculateTotalPrice(filteredLands, ASSET.BUSD);
        require(
            alreadyMinted + _tids.length < MAX_LAND_COUNT_PER_ACCOUNT &&
                busd.balanceOf(msg.sender) > totalPrice &&
                _tids.length +
                    TOTAL_PRESOLD +
                    totalSupply() +
                    disabledLands.length >
                MAX_ID,
            "User has not enough balance."
        );

        SafeERC20Upgradeable.safeTransferFrom(
            busd,
            msg.sender,
            address(this),
            totalPrice
        );

        for (uint i = 0; i < filteredLands.length; i++) {
            if (filteredLands[i] == 0) {
                continue;
            }

            _safeMint(msg.sender, filteredLands[i]);
        }

        emit MultipleMint(msg.sender, filteredLands, totalPrice);
    }

    // claim mint single nft without payment and available from launchpad
    function claim(uint256[] memory _ids) public {
        uint alreadyMinted = balanceOf(msg.sender);
        uint256[] memory filteredLands = filterAvailableLands(_ids);
        require(
            launchpadSaleStatus &&
                alreadyMinted + filteredLands.length <
                MAX_LAND_COUNT_PER_ACCOUNT &&
                filteredLands.length <=
                launchpadLands[msg.sender].ClaimableCount,
            "user reaches claim limit"
        );
        for (uint i = 0; i < filteredLands.length; i++) {
            if (filteredLands[i] == 0) {
                continue;
            }
            require(
                launchpadLands[msg.sender].ClaimedCount <
                    launchpadLands[msg.sender].ClaimableCount,
                "reach calimable limit."
            );
            _safeMint(msg.sender, _ids[i]);
            TOTAL_PRESOLD -= 1;
            launchpadLands[msg.sender].ClaimedCount++;
        }

        emit MultipleMint(msg.sender, filteredLands, 0);
    }

    // check given _tid inside disabledLand or not
    function isDisabledLand(uint256 _tid) private view returns (bool) {
        if (_tid > MAX_ID) {
            return true;
        }

        for (uint256 i = 0; i < disabledLands.length; i++) {
            if (disabledLands[i] == _tid) {
                return true;
            }
        }

        return false;
    }

    function filterAvailableLands(
        uint256[] memory _tids
    ) private view returns (uint256[] memory) {
        uint256[] memory filteredLands = new uint256[](_tids.length);

        for (uint i = 0; i < _tids.length; i++) {
            if (isDisabledLand(_tids[i])) {
                continue;
            }

            filteredLands[i] = _tids[i];
        }

        return filteredLands;
    }

    function decimals() internal pure returns (uint256) {
        return 10 ** 18;
    }

    function calculateTotalPrice(
        uint256[] memory _tids,
        ASSET _asset
    ) internal view returns (uint256) {
        uint256 _price = 0;
        uint256 cnt = 0;

        if (whiteListAddresses[msg.sender] && whiteListSaleStatus) {
            if (_asset == ASSET.METO) {
                _price = WHITELIST_LAND_PRICE_METO * BUSD_METO_PAIR;
            } else if (_asset == ASSET.BUSD) {
                _price = WHITELIST_LAND_PRICE_BUSD * decimals();
            }
        } else {
            require(publicSaleStatus, "public sale not opened.");
            if (_asset == ASSET.METO) {
                _price = LAND_PRICE_METO * BUSD_METO_PAIR;
            } else if (_asset == ASSET.BUSD) {
                _price = LAND_PRICE_BUSD * decimals();
            }
        }

        for (uint256 i = 0; i < _tids.length; i++) {
            if (_tids[i] > 0) {
                cnt++;
            }
        }

        return _price * cnt;
    }

    function pay4LandWithMeto(uint256 count) public {
        require(
            count + totalSupply() + TOTAL_PRESOLD + disabledLands.length <=
                MAX_ID,
            "request out of bound"
        );
        uint256 totalPrice = count * LAND_PRICE_METO * BUSD_METO_PAIR;
        require(meto.balanceOf(msg.sender) > totalPrice, "not enough balance");

        SafeERC20Upgradeable.safeTransferFrom(
            meto,
            msg.sender,
            address(this),
            totalPrice
        );
        TOTAL_PRESOLD += count;
        updateLaunchpadLand(count);
    }

    function pay4LandWithBusd(uint256 count) public {
        require(
            count + totalSupply() + TOTAL_PRESOLD + disabledLands.length <=
                MAX_ID,
            "request out of bound"
        );
        uint256 totalPrice = count * WHITELIST_LAND_PRICE_BUSD * decimals();
        require(busd.balanceOf(msg.sender) > totalPrice, "not enough balance");

        SafeERC20Upgradeable.safeTransferFrom(
            busd,
            msg.sender,
            address(this),
            totalPrice
        );
        TOTAL_PRESOLD += count;
        updateLaunchpadLand(count);
    }

    function updateLaunchpadLand(uint256 count) private {
        launchpadLands[msg.sender].ClaimableCount += count;
    }
}
