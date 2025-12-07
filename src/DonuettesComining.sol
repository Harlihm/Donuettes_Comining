// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IDonuetteMiner {
    struct Slot0 {
        uint8 locked;
        uint16 epochId;
        uint192 initPrice;
        uint40 startTime;
        uint256 dps;
        address miner;
        string uri;
    }

    function mine(
        address miner,
        address provider,
        uint256 epochId,
        uint256 deadline,
        uint256 maxPrice,
        string memory uri
    ) external returns (uint256 price);
    
    function getPrice() external view returns (uint256);
    function getSlot0() external view returns (Slot0 memory);
}

interface IDonut {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IDonuette {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/**
 * @title Donuettes Co-mining
 * @notice Rotating pool system for mining Donuettes - each pool mines independently, new pools auto-create
 * @dev Once a pool starts mining, it becomes closed and a new pool opens for deposits
 *      Uses DONUT tokens instead of ETH
 */
contract DonuettesComining is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    enum PoolStatus {
        ACCEPTING_DEPOSITS,  // Pool is open for deposits
        MINING,              // Pool is currently the Donuette King
        OUTBID,              // Pool was outbid, distributing rewards
        CLOSED               // All rewards claimed, pool finalized
    }

    struct Pool {
        uint256 poolId;
        uint256 totalDeposited;
        uint256 totalShares;
        uint256 donutSpent;
        uint256 donutReceived;
        uint256 donuetteMined;
        uint256 startTime;
        uint256 mineTime;
        PoolStatus status;
        mapping(address => uint256) userShares;
        mapping(address => bool) claimed;
        address[] depositors;
    }

    IDonuetteMiner public immutable miner;
    IDonuette public immutable donuette;
    IERC20 public immutable donut; // DONUT token
    address public provider;

    uint256 public currentPoolId;
    uint256 public totalPoolsCreated;
    
    mapping(uint256 => Pool) public pools;
    mapping(address => uint256[]) public userPoolIds;

    // Settings
    uint256 public minDeposit = 5 ether; // 5 DONUT (using 18 decimals)
    uint256 public maxPriceSlippage = 500; // 5%
    uint256 public constant DIVISOR = 10_000;
    bool public autoMineEnabled = true;
    uint256 public minPoolSize = 1000 ether; // Minimum pool size before mining (1000 DONUT)

    // Events
    event PoolCreated(uint256 indexed poolId);
    event Deposited(uint256 indexed poolId, address indexed user, uint256 amount, uint256 shares);
    event PoolMined(uint256 indexed poolId, uint256 donutSpent, uint256 donuetteMined);
    event PoolOutbid(uint256 indexed poolId, uint256 donutReceived);
    event RewardsClaimed(uint256 indexed poolId, address indexed user, uint256 donutAmount, uint256 donuetteAmount);
    event Withdrawn(uint256 indexed poolId, address indexed user, uint256 amount);
    event SettingsUpdated(uint256 minDeposit, uint256 maxSlippage, bool autoMine, uint256 minPoolSize);

    constructor(
        address _miner,
        address _donuette,
        address _donut,
        address _provider
    ) {
        miner = IDonuetteMiner(_miner);
        donuette = IDonuette(_donuette);
        donut = IERC20(_donut);
        provider = _provider;
        
        // Create first pool
        _createNewPool();
    }

    /**
     * @notice Deposit DONUT tokens into the current active pool
     * @param amount Amount of DONUT tokens to deposit
     */
    function deposit(uint256 amount) external nonReentrant {
        require(amount >= minDeposit, "Below minimum deposit");
        
        Pool storage pool = pools[currentPoolId];
        require(pool.status == PoolStatus.ACCEPTING_DEPOSITS, "Pool not accepting deposits");

        // Transfer DONUT tokens from user
        donut.safeTransferFrom(msg.sender, address(this), amount);

        uint256 sharesToMint;
        if (pool.totalShares == 0) {
            sharesToMint = amount;
        } else {
            sharesToMint = (amount * pool.totalShares) / pool.totalDeposited;
        }

        // First time depositor in this pool
        if (pool.userShares[msg.sender] == 0) {
            pool.depositors.push(msg.sender);
            userPoolIds[msg.sender].push(currentPoolId);
        }

        pool.userShares[msg.sender] += sharesToMint;
        pool.totalShares += sharesToMint;
        pool.totalDeposited += amount;

        emit Deposited(currentPoolId, msg.sender, amount, sharesToMint);

        // Try to mine if pool is large enough
        if (autoMineEnabled && pool.totalDeposited >= minPoolSize) {
            // Only try to mine if the pool has enough DONUT to cover the current price
            uint256 currentPrice = miner.getPrice();
            if (pool.totalDeposited >= currentPrice) {
                _tryMine();
            }
        }
    }

    /**
     * @notice Withdraw from current pool (only if not yet mining)
     * @param shares Number of shares to withdraw
     */
    function withdrawFromCurrentPool(uint256 shares) external nonReentrant {
        Pool storage pool = pools[currentPoolId];
        require(pool.status == PoolStatus.ACCEPTING_DEPOSITS, "Pool already mining");
        require(shares <= pool.userShares[msg.sender], "Insufficient shares");

        uint256 donutAmount = (shares * pool.totalDeposited) / pool.totalShares;
        
        pool.userShares[msg.sender] -= shares;
        pool.totalShares -= shares;
        pool.totalDeposited -= donutAmount;

        donut.safeTransfer(msg.sender, donutAmount);

        emit Withdrawn(currentPoolId, msg.sender, donutAmount);
    }

    /**
     * @notice Claim rewards from a specific pool that was outbid
     * @param poolId Pool ID to claim from
     */
    function claimRewards(uint256 poolId) external nonReentrant {
        Pool storage pool = pools[poolId];
        require(pool.status == PoolStatus.OUTBID, "Pool not ready for claims");
        require(!pool.claimed[msg.sender], "Already claimed");
        require(pool.userShares[msg.sender] > 0, "No shares in pool");

        pool.claimed[msg.sender] = true;

        // Calculate user's share of rewards
        uint256 sharePercentage = (pool.userShares[msg.sender] * 1e18) / pool.totalShares;
        
        // DONUT rewards (includes initial deposit + profit)
        uint256 totalDonut = pool.totalDeposited - pool.donutSpent + pool.donutReceived;
        uint256 donutReward = (totalDonut * sharePercentage) / 1e18;
        
        // Donuette rewards
        uint256 donuetteReward = (pool.donuetteMined * sharePercentage) / 1e18;

        // Transfer rewards
        if (donutReward > 0) {
            donut.safeTransfer(msg.sender, donutReward);
        }

        if (donuetteReward > 0) {
            require(donuette.transfer(msg.sender, donuetteReward), "Donuette transfer failed");
        }

        emit RewardsClaimed(poolId, msg.sender, donutReward, donuetteReward);

        // Check if all users claimed, mark pool as closed
        _checkPoolClosure(poolId);
    }

    /**
     * @notice Claim rewards from multiple pools at once
     * @param poolIds Array of pool IDs to claim from
     */
    function claimMultiplePools(uint256[] calldata poolIds) external nonReentrant {
        for (uint256 i = 0; i < poolIds.length; i++) {
            uint256 poolId = poolIds[i];
            Pool storage pool = pools[poolId];
            
            if (pool.status != PoolStatus.OUTBID || pool.claimed[msg.sender] || pool.userShares[msg.sender] == 0) {
                continue;
            }

            pool.claimed[msg.sender] = true;

            uint256 sharePercentage = (pool.userShares[msg.sender] * 1e18) / pool.totalShares;
            uint256 totalDonut = pool.totalDeposited - pool.donutSpent + pool.donutReceived;
            uint256 donutReward = (totalDonut * sharePercentage) / 1e18;
            uint256 donuetteReward = (pool.donuetteMined * sharePercentage) / 1e18;

            if (donutReward > 0) {
                donut.safeTransfer(msg.sender, donutReward);
            }

            if (donuetteReward > 0) {
                require(donuette.transfer(msg.sender, donuetteReward), "Donuette transfer failed");
            }

            emit RewardsClaimed(poolId, msg.sender, donutReward, donuetteReward);
            _checkPoolClosure(poolId);
        }
    }

    /**
     * @notice Manually trigger mining for current pool
     */
    function mine() external nonReentrant {
        _tryMine();
    }

    /**
     * @notice Internal function to attempt mining
     */
    function _tryMine() internal {
        Pool storage pool = pools[currentPoolId];
        require(pool.status == PoolStatus.ACCEPTING_DEPOSITS, "Pool not ready");
        
        uint256 currentPrice = miner.getPrice();
        require(currentPrice > 0, "Price is zero");
        require(pool.totalDeposited >= currentPrice, "Insufficient pool funds");
        require(donut.balanceOf(address(this)) >= currentPrice, "Insufficient DONUT balance");

        uint256 maxPrice = currentPrice + (currentPrice * maxPriceSlippage / DIVISOR);
        IDonuetteMiner.Slot0 memory slot0 = miner.getSlot0();
        uint16 epochId = slot0.epochId;
        address previousMiner = slot0.miner;
        
        // Find the previous mining pool (if it's one of ours)
        uint256 previousPoolId = 0;
        for (uint256 i = currentPoolId - 1; i > 0; i--) {
            if (pools[i].status == PoolStatus.MINING) {
                previousPoolId = i;
                break;
            }
        }
        
        // Track balances before mining
        uint256 donuetteBefore = 0;
        uint256 donutBefore = donut.balanceOf(address(this));
        
        // If previous miner is this contract (one of our pools), track its donuette balance
        if (previousMiner == address(this) && previousPoolId > 0) {
            donuetteBefore = donuette.balanceOf(address(this));
        }

        // Approve and mine
        donut.safeApprove(address(miner), currentPrice);
        
        uint256 pricePaid = miner.mine(
            address(this),
            provider,
            epochId,
            block.timestamp + 300,
            maxPrice,
            string(abi.encodePacked("DonuettePool#", _toString(currentPoolId)))
        );

        // After mining, donuettes are minted to previousMiner and DONUT is transferred
        // The miner contract transfers 80% of pricePaid to previousMiner
        uint256 donuetteAfter = 0;
        uint256 donutAfter = donut.balanceOf(address(this));
        
        // If previous miner was one of our pools, check what it received
        if (previousMiner == address(this) && previousPoolId > 0) {
            donuetteAfter = donuette.balanceOf(address(this));
        }
        
        uint256 donuetteReceived = donuetteAfter > donuetteBefore ? donuetteAfter - donuetteBefore : 0;
        
        // Calculate DONUT received by previous pool
        // The current pool spent pricePaid, but if previous miner is this contract,
        // it received 80% of pricePaid. However, since both are address(this),
        // the net change is: -pricePaid + 0.8*pricePaid = -0.2*pricePaid
        // So we need to track the previous pool's balance separately
        // Actually, the miner transfers FROM msg.sender (current pool) TO previous miner
        // So if previous miner is address(this), the contract's balance changes by:
        // -pricePaid (spent) + 0.8*pricePaid (received by previous pool) = -0.2*pricePaid net
        // But we need to attribute the 0.8*pricePaid to the previous pool
        
        // Since both pools are the same contract, we can't easily separate them
        // The previous pool should receive 80% of pricePaid
        uint256 donutReceived = 0;
        if (previousMiner == address(this) && previousPoolId > 0) {
            // Previous pool receives 80% of pricePaid
            donutReceived = (pricePaid * 8000) / DIVISOR;
        }

        // Update the previous mining pool if it's one of ours
        if (previousPoolId > 0) {
            Pool storage prevPool = pools[previousPoolId];
            prevPool.status = PoolStatus.OUTBID;
            prevPool.donuetteMined = donuetteReceived;
            prevPool.donutReceived = donutReceived;
            
            emit PoolOutbid(previousPoolId, donutReceived);
        }

        // Update current pool state
        pool.status = PoolStatus.MINING;
        pool.donutSpent = pricePaid;
        pool.mineTime = block.timestamp;
        // pool.donuetteMined is 0 for now (will be set when outbid)

        emit PoolMined(currentPoolId, pricePaid, 0);

        // Create new pool immediately
        _createNewPool();
    }

    /**
     * @notice Create a new pool for deposits
     */
    function _createNewPool() internal {
        totalPoolsCreated++;
        currentPoolId = totalPoolsCreated;
        
        Pool storage newPool = pools[currentPoolId];
        newPool.poolId = currentPoolId;
        newPool.status = PoolStatus.ACCEPTING_DEPOSITS;
        newPool.startTime = block.timestamp;

        emit PoolCreated(currentPoolId);
    }

    /**
     * @notice Check if pool should be marked as closed
     * @param poolId Pool ID to check
     */
    function _checkPoolClosure(uint256 poolId) internal {
        Pool storage pool = pools[poolId];
        
        // Check if all depositors claimed
        bool allClaimed = true;
        for (uint256 i = 0; i < pool.depositors.length; i++) {
            if (!pool.claimed[pool.depositors[i]]) {
                allClaimed = false;
                break;
            }
        }

        if (allClaimed) {
            pool.status = PoolStatus.CLOSED;
        }
    }

    /**
     * @notice Get user's position in current pool
     * @param user User address
     * @return poolId Current pool ID
     * @return deposited Amount deposited by user
     * @return shares User's shares
     * @return sharePercentage User's share percentage (in basis points)
     * @return status Pool status
     */
    function getCurrentPoolPosition(address user) external view returns (
        uint256 poolId,
        uint256 deposited,
        uint256 shares,
        uint256 sharePercentage,
        PoolStatus status
    ) {
        Pool storage pool = pools[currentPoolId];
        poolId = currentPoolId;
        shares = pool.userShares[user];
        sharePercentage = pool.totalShares > 0 ? (shares * DIVISOR) / pool.totalShares : 0;
        deposited = pool.totalShares > 0 ? (shares * pool.totalDeposited) / pool.totalShares : 0;
        status = pool.status;
    }

    /**
     * @notice Get claimable rewards for a specific pool
     * @param poolId Pool ID
     * @param user User address
     * @return donutReward Claimable DONUT amount
     * @return donuetteReward Claimable Donuette amount
     * @return canClaim Whether user can claim
     */
    function getClaimableRewards(uint256 poolId, address user) external view returns (
        uint256 donutReward,
        uint256 donuetteReward,
        bool canClaim
    ) {
        Pool storage pool = pools[poolId];
        
        if (pool.status != PoolStatus.OUTBID || pool.claimed[user] || pool.userShares[user] == 0) {
            return (0, 0, false);
        }

        uint256 sharePercentage = (pool.userShares[user] * 1e18) / pool.totalShares;
        uint256 totalDonut = pool.totalDeposited - pool.donutSpent + pool.donutReceived;
        
        donutReward = (totalDonut * sharePercentage) / 1e18;
        donuetteReward = (pool.donuetteMined * sharePercentage) / 1e18;
        canClaim = true;
    }

    /**
     * @notice Get all pools user participated in
     * @param user User address
     * @return Array of pool IDs
     */
    function getUserPools(address user) external view returns (uint256[] memory) {
        return userPoolIds[user];
    }

    /**
     * @notice Get pool details
     * @param poolId Pool ID
     * @return totalDeposited Total DONUT deposited
     * @return totalShares Total shares
     * @return donutSpent DONUT spent on mining
     * @return donutReceived DONUT received from being outbid
     * @return donuetteMined Donuettes mined
     * @return depositorCount Number of depositors
     * @return status Pool status
     */
    function getPoolDetails(uint256 poolId) external view returns (
        uint256 totalDeposited,
        uint256 totalShares,
        uint256 donutSpent,
        uint256 donutReceived,
        uint256 donuetteMined,
        uint256 depositorCount,
        PoolStatus status
    ) {
        Pool storage pool = pools[poolId];
        return (
            pool.totalDeposited,
            pool.totalShares,
            pool.donutSpent,
            pool.donutReceived,
            pool.donuetteMined,
            pool.depositors.length,
            pool.status
        );
    }

    /**
     * @notice Get current price from miner
     * @return Current price in DONUT
     */
    function getCurrentGlazePrice() external view returns (uint256) {
        return miner.getPrice();
    }

    /**
     * @notice Update settings (onlyOwner)
     * @param _minDeposit Minimum deposit amount
     * @param _maxSlippage Maximum price slippage (in basis points)
     * @param _autoMine Whether to auto-mine when pool is ready
     * @param _minPoolSize Minimum pool size before mining
     */
    function updateSettings(
        uint256 _minDeposit,
        uint256 _maxSlippage,
        bool _autoMine,
        uint256 _minPoolSize
    ) external onlyOwner {
        minDeposit = _minDeposit;
        maxPriceSlippage = _maxSlippage;
        autoMineEnabled = _autoMine;
        minPoolSize = _minPoolSize;
        emit SettingsUpdated(_minDeposit, _maxSlippage, _autoMine, _minPoolSize);
    }

    /**
     * @notice Update provider address (onlyOwner)
     * @param _provider New provider address
     */
    function updateProvider(address _provider) external onlyOwner {
        provider = _provider;
    }

    /**
     * @notice Helper to convert uint to string
     * @param value Number to convert
     * @return String representation
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @notice Rescue stuck tokens (onlyOwner)
     * @dev Emergency function to recover funds sent by mistake
     * @param token Token address (address(0) for DONUT if needed)
     * @param amount Amount to rescue
     */
    function rescueFunds(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            // For DONUT, use the donut address
            donut.safeTransfer(msg.sender, amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }
}
