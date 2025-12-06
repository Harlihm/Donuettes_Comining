// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Donut is ERC20, ERC20Permit, ERC20Votes {
    address public immutable miner;

    error Donut__NotMiner();

    event Donut__Minted(address account, uint256 amount);
    event Donut__Burned(address account, uint256 amount);

    constructor() ERC20("Donut", "DONUT") ERC20Permit("Donut") {
        miner = msg.sender;
    }

    function mint(address account, uint256 amount) external {
        if (msg.sender != miner) revert Donut__NotMiner();
        _mint(account, amount);
        emit Donut__Minted(account, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit Donut__Burned(msg.sender, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}

contract Miner is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant FEE = 2_000;
    uint256 public constant DIVISOR = 10_000;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant EPOCH_PERIOD = 1 hours;
    uint256 public constant PRICE_MULTIPLIER = 2e18;
    uint256 public constant MIN_INIT_PRICE = 0.0001 ether;
    uint256 public constant ABS_MAX_INIT_PRICE = type(uint192).max;

    uint256 public constant INITIAL_DPS = 4 ether;
    uint256 public constant HALVING_PERIOD = 30 days;
    uint256 public constant TAIL_DPS = 0.01 ether;

    address public immutable donut;
    address public immutable quote;
    uint256 public immutable startTime;

    address public treasury;

    struct Slot0 {
        uint8 locked;
        uint16 epochId;
        uint192 initPrice;
        uint40 startTime;
        uint256 dps;
        address miner;
        string uri;
    }

    Slot0 internal slot0;

    error Miner__InvalidMiner();
    error Miner__Reentrancy();
    error Miner__Expired();
    error Miner__EpochIdMismatch();
    error Miner__MaxPriceExceeded();
    error Miner__InvalidTreasury();

    event Miner__Mined(address indexed sender, address indexed miner, uint256 price, string uri);
    event Miner__Minted(address indexed miner, uint256 amount);
    event Miner__ProviderFee(address indexed provider, uint256 amount);
    event Miner__TreasuryFee(address indexed treasury, uint256 amount);
    event Miner__MinerFee(address indexed miner, uint256 amount);
    event Miner__TreasurySet(address indexed treasury);

    modifier nonReentrant() {
        if (slot0.locked == 2) revert Miner__Reentrancy();
        slot0.locked = 2;
        _;
        slot0.locked = 1;
    }

    modifier nonReentrantView() {
        if (slot0.locked == 2) revert Miner__Reentrancy();
        _;
    }

    constructor(address _quote, address _treasury) {
        if (_treasury == address(0)) revert Miner__InvalidTreasury();
        quote = _quote;
        treasury = _treasury;
        startTime = block.timestamp;

        slot0.initPrice = uint192(MIN_INIT_PRICE);
        slot0.startTime = uint40(startTime);
        slot0.miner = _treasury;
        slot0.dps = INITIAL_DPS;

        donut = address(new Donut());
    }

    function mine(
        address miner,
        address provider,
        uint256 epochId,
        uint256 deadline,
        uint256 maxPrice,
        string memory uri
    ) external nonReentrant returns (uint256 price) {
        if (miner == address(0)) revert Miner__InvalidMiner();
        if (block.timestamp > deadline) revert Miner__Expired();

        Slot0 memory slot0Cache = slot0;

        if (uint16(epochId) != slot0Cache.epochId) revert Miner__EpochIdMismatch();

        price = _getPriceFromCache(slot0Cache);
        if (price > maxPrice) revert Miner__MaxPriceExceeded();

        if (price > 0) {
            uint256 totalFee = price * FEE / DIVISOR;
            uint256 minerFee = price - totalFee;
            uint256 providerFee = 0;
            uint256 treasuryFee = 0;

            if (provider == address(0)) {
                treasuryFee = totalFee;
            } else {
                providerFee = totalFee / 4;
                treasuryFee = totalFee - providerFee;
            }

            if (providerFee > 0) {
                IERC20(quote).safeTransferFrom(msg.sender, provider, providerFee);
                emit Miner__ProviderFee(provider, providerFee);
            }

            IERC20(quote).safeTransferFrom(msg.sender, treasury, treasuryFee);
            emit Miner__TreasuryFee(treasury, treasuryFee);

            IERC20(quote).safeTransferFrom(msg.sender, slot0Cache.miner, minerFee);
            emit Miner__MinerFee(slot0Cache.miner, minerFee);
        }

        uint256 newInitPrice = price * PRICE_MULTIPLIER / PRECISION;

        if (newInitPrice > ABS_MAX_INIT_PRICE) {
            newInitPrice = ABS_MAX_INIT_PRICE;
        } else if (newInitPrice < MIN_INIT_PRICE) {
            newInitPrice = MIN_INIT_PRICE;
        }

        uint256 mineTime = block.timestamp - slot0Cache.startTime;
        uint256 minedAmount = mineTime * slot0Cache.dps;

        Donut(donut).mint(slot0Cache.miner, minedAmount);
        emit Miner__Minted(slot0Cache.miner, minedAmount);

        unchecked {
            slot0Cache.epochId++;
        }
        slot0Cache.initPrice = uint192(newInitPrice);
        slot0Cache.startTime = uint40(block.timestamp);
        slot0Cache.miner = miner;
        slot0Cache.dps = _getDpsFromTime(block.timestamp);
        slot0Cache.uri = uri;

        slot0 = slot0Cache;

        emit Miner__Mined(msg.sender, miner, price, uri);

        return price;
    }

    function _getPriceFromCache(Slot0 memory slot0Cache) internal view returns (uint256) {
        uint256 timePassed = block.timestamp - slot0Cache.startTime;

        if (timePassed > EPOCH_PERIOD) {
            return 0;
        }

        return slot0Cache.initPrice - slot0Cache.initPrice * timePassed / EPOCH_PERIOD;
    }

    function _getDpsFromTime(uint256 time) internal view returns (uint256 dps) {
        uint256 halvings = time <= startTime ? 0 : (time - startTime) / HALVING_PERIOD;
        dps = INITIAL_DPS >> halvings;
        if (dps < TAIL_DPS) dps = TAIL_DPS;
        return dps;
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert Miner__InvalidTreasury();
        treasury = _treasury;
        emit Miner__TreasurySet(_treasury);
    }

    function getPrice() external view nonReentrantView returns (uint256) {
        return _getPriceFromCache(slot0);
    }

    function getDps() external view nonReentrantView returns (uint256) {
        return _getDpsFromTime(block.timestamp);
    }

    function getSlot0() external view nonReentrantView returns (Slot0 memory) {
        return slot0;
    }
}