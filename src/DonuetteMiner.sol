// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title donuette
 * @notice ERC20 token mined by spending DONUT tokens
 */
contract Donuette is ERC20, ERC20Permit, ERC20Votes {
    address public immutable miner;

    error Donuette__NotMiner();

    event Donuette__Minted(address account, uint256 amount);
    event Donuette__Burned(address account, uint256 amount);

    constructor() ERC20("Donuette", "Donuette") ERC20Permit("Donuette") {
        miner = msg.sender;
    }

    function mint(address account, uint256 amount) external {
        if (msg.sender != miner) revert Donuette__NotMiner();
        _mint(account, amount);
        emit Donuette__Minted(account, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit Donuette__Burned(msg.sender, amount);
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

/**
 * @title DonuetteMiner
 * @notice Mine Donuettes by spending DONUT tokens, using the same King Glazer mechanism
 * @dev Similar to DONUT Miner but uses DONUT as quote token and mints Donuettes
 */
contract DonuetteMiner is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant FEE = 2_000; // 20% total fee
    uint256 public constant DIVISOR = 10_000;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant EPOCH_PERIOD = 1 hours;
    uint256 public constant PRICE_MULTIPLIER = 2e18; // 2x multiplier
    uint256 public constant MIN_INIT_PRICE = 5 ether; // Start at 5 DONUT
    uint256 public constant MIN_PRICE_FLOOR = 0.01 ether; // 0.01 DONUT
    uint256 public constant ABS_MAX_INIT_PRICE = type(uint192).max;

    uint256 public constant INITIAL_DPS = 4 ether; // 4 Donuette per second
    uint256 public constant HALVING_PERIOD = 30 days;
    uint256 public constant TAIL_DPS = 0.01 ether;

    address public immutable donuette;
    address public immutable donut; // DONUT token address (quote)
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

    error DonuetteMiner__InvalidMiner();
    error DonuetteMiner__Reentrancy();
    error DonuetteMiner__Expired();
    error DonuetteMiner__EpochIdMismatch();
    error DonuetteMiner__MaxPriceExceeded();
    error DonuetteMiner__InvalidTreasury();

    event DonuetteMiner__Mined(address indexed sender, address indexed miner, uint256 price, string uri);
    event DonuetteMiner__Minted(address indexed miner, uint256 amount);
    event DonuetteMiner__ProviderFee(address indexed provider, uint256 amount);
    event DonuetteMiner__TreasuryFee(address indexed treasury, uint256 amount);
    event DonuetteMiner__MinerFee(address indexed miner, uint256 amount);
    event DonuetteMiner__TreasurySet(address indexed treasury);

    modifier nonReentrant() {
        if (slot0.locked == 2) revert DonuetteMiner__Reentrancy();
        slot0.locked = 2;
        _;
        slot0.locked = 1;
    }

    modifier nonReentrantView() {
        if (slot0.locked == 2) revert DonuetteMiner__Reentrancy();
        _;
    }

    constructor(address _donut, address _treasury) {
        if (_treasury == address(0)) revert DonuetteMiner__InvalidTreasury();
        donut = _donut;
        treasury = _treasury;
        startTime = block.timestamp;

        slot0.initPrice = uint192(MIN_INIT_PRICE);
        slot0.startTime = uint40(startTime);
        slot0.miner = _treasury;
        slot0.dps = INITIAL_DPS;

        donuette = address(new Donuette());
    }

    /**
     * @notice Mine Donuettes by spending DONUT tokens
     * @param miner Address that will receive the mined Donuettes
     * @param provider Frontend provider address (gets 5% fee)
     * @param epochId Current epoch ID (prevents front-running)
     * @param deadline Transaction deadline
     * @param maxPrice Maximum price willing to pay
     * @param uri Optional URI for the mining event
     */
    function mine(
        address miner,
        address provider,
        uint256 epochId,
        uint256 deadline,
        uint256 maxPrice,
        string memory uri
    ) external nonReentrant returns (uint256 price) {
        if (miner == address(0)) revert DonuetteMiner__InvalidMiner();
        if (block.timestamp > deadline) revert DonuetteMiner__Expired();

        Slot0 memory slot0Cache = slot0;

        if (uint16(epochId) != slot0Cache.epochId) revert DonuetteMiner__EpochIdMismatch();

        price = _getPriceFromCache(slot0Cache);
        if (price > maxPrice) revert DonuetteMiner__MaxPriceExceeded();

        if (price > 0) {
            uint256 totalFee = price * FEE / DIVISOR; // 20% fee
            uint256 minerFee = price - totalFee; // 80% to previous miner
            uint256 providerFee = 0;
            uint256 treasuryFee = 0;

            if (provider == address(0)) {
                // No provider: all 20% goes to treasury
                treasuryFee = totalFee;
            } else {
                // With provider: 5% to provider, 15% to treasury
                providerFee = totalFee / 4; // 5% of total (25% of 20%)
                treasuryFee = totalFee - providerFee; // 15%
            }

            // Transfer DONUT fees
            if (providerFee > 0) {
                IERC20(donut).safeTransferFrom(msg.sender, provider, providerFee);
                emit DonuetteMiner__ProviderFee(provider, providerFee);
            }

            IERC20(donut).safeTransferFrom(msg.sender, treasury, treasuryFee);
            emit DonuetteMiner__TreasuryFee(treasury, treasuryFee);

            // Transfer 80% DONUT to previous miner
            IERC20(donut).safeTransferFrom(msg.sender, slot0Cache.miner, minerFee);
            emit DonuetteMiner__MinerFee(slot0Cache.miner, minerFee);
        }

        // Calculate new starting price (2x)
        uint256 newInitPrice = price * PRICE_MULTIPLIER / PRECISION;

        if (newInitPrice > ABS_MAX_INIT_PRICE) {
            newInitPrice = ABS_MAX_INIT_PRICE;
        } else if (newInitPrice < MIN_INIT_PRICE) {
            newInitPrice = MIN_INIT_PRICE;
        }

        // Calculate and mint Donuettes to previous miner
        uint256 mineTime = block.timestamp - slot0Cache.startTime;
        uint256 minedAmount = mineTime * slot0Cache.dps;

        Donuette(donuette).mint(slot0Cache.miner, minedAmount);
        emit DonuetteMiner__Minted(slot0Cache.miner, minedAmount);

        // Update state
        unchecked {
            slot0Cache.epochId++;
        }
        slot0Cache.initPrice = uint192(newInitPrice);
        slot0Cache.startTime = uint40(block.timestamp);
        slot0Cache.miner = miner;
        slot0Cache.dps = _getDpsFromTime(block.timestamp);
        slot0Cache.uri = uri;

        slot0 = slot0Cache;

        emit DonuetteMiner__Mined(msg.sender, miner, price, uri);

        return price;
    }

    /**
     * @notice Get current price based on Dutch auction
     */
    function _getPriceFromCache(Slot0 memory slot0Cache) internal view returns (uint256) {
        uint256 timePassed = block.timestamp - slot0Cache.startTime;

        if (timePassed > EPOCH_PERIOD) {
            return MIN_PRICE_FLOOR;
        }

        uint256 price = slot0Cache.initPrice - slot0Cache.initPrice * timePassed / EPOCH_PERIOD;
        return price < MIN_PRICE_FLOOR ? MIN_PRICE_FLOOR : price;
    }

    /**
     * @notice Calculate DPS based on halving schedule
     */
    function _getDpsFromTime(uint256 time) internal view returns (uint256 dps) {
        uint256 halvings = time <= startTime ? 0 : (time - startTime) / HALVING_PERIOD;
        dps = INITIAL_DPS >> halvings;
        if (dps < TAIL_DPS) dps = TAIL_DPS;
        return dps;
    }

    /**
     * @notice Update treasury address (onlyOwner)
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert DonuetteMiner__InvalidTreasury();
        treasury = _treasury;
        emit DonuetteMiner__TreasurySet(_treasury);
    }

    /**
     * @notice Get current price
     */
    function getPrice() external view nonReentrantView returns (uint256) {
        return _getPriceFromCache(slot0);
    }

    /**
     * @notice Get current DPS (Donuettes per second)
     */
    function getDps() external view nonReentrantView returns (uint256) {
        return _getDpsFromTime(block.timestamp);
    }

    /**
     * @notice Get current state
     */
    function getSlot0() external view nonReentrantView returns (Slot0 memory) {
        return slot0;
    }
}
