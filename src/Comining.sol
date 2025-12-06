// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IMiner {
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

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

/**
 * @title Co-mining
 * @notice Rotating pool system - each pool mines independently, new pools auto-create
 * @dev Once a pool starts mining, it becomes closed and a new pool opens for deposits
 */
contract Comining is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    enum PoolStatus {
        ACCEPTING_DEPOSITS,  // Pool is open for deposits
        MINING,              // Pool is currently the King Glazer
        OUTBID,              // Pool was outbid, distributing rewards
        CLOSED               // All rewards claimed, pool finalized
    }

    struct Pool {
        uint256 poolId;
        uint256 totalDeposited;
        uint256 totalShares;
        uint256 ethSpent;
        uint256 ethReceived;
        uint256 donutMined;
        uint256 startTime;
        uint256 mineTime;
        PoolStatus status;
        mapping(address => uint256) userShares;
        mapping(address => bool) claimed;
        address[] depositors;
    }

    IMiner public immutable miner;
    IDonut public immutable donut;
    IERC20 public immutable quote; // WETH
    address public provider;

    uint256 public currentPoolId;
    uint256 public totalPoolsCreated;
    
    mapping(uint256 => Pool) public pools;
    mapping(address => uint256[]) public userPoolIds;

    // Settings
    uint256 public minDeposit = 0.01 ether;
    uint256 public maxPriceSlippage = 500; // 5%
    uint256 public constant DIVISOR = 10_000;
    bool public autoMineEnabled = true;
    uint256 public minPoolSize = 0.1 ether; // Minimum pool size before mining

    // Events
    event PoolCreated(uint256 indexed poolId);
    event Deposited(uint256 indexed poolId, address indexed user, uint256 amount, uint256 shares);
    event PoolMined(uint256 indexed poolId, uint256 ethSpent, uint256 donutMined);
    event PoolOutbid(uint256 indexed poolId, uint256 ethReceived);
    event RewardsClaimed(uint256 indexed poolId, address indexed user, uint256 ethAmount, uint256 donutAmount);
    event Withdrawn(uint256 indexed poolId, address indexed user, uint256 amount);
    event SettingsUpdated(uint256 minDeposit, uint256 maxSlippage, bool autoMine, uint256 minPoolSize);

    constructor(
        address _miner,
        address _donut,
        address _quote,
        address _provider
    ) {
        miner = IMiner(_miner);
        donut = IDonut(_donut);
        quote = IERC20(_quote);
        provider = _provider;
        
        // Create first pool
        _createNewPool();
    }

    /**
     * @notice Deposit ETH into the current active pool
     */
    function deposit() external payable nonReentrant {
        require(msg.value >= minDeposit, "Below minimum deposit");
        
        Pool storage pool = pools[currentPoolId];
        require(pool.status == PoolStatus.ACCEPTING_DEPOSITS, "Pool not accepting deposits");

        uint256 sharesToMint;
        if (pool.totalShares == 0) {
            sharesToMint = msg.value;
        } else {
            sharesToMint = (msg.value * pool.totalShares) / pool.totalDeposited;
        }

        // First time depositor in this pool
        if (pool.userShares[msg.sender] == 0) {
            pool.depositors.push(msg.sender);
            userPoolIds[msg.sender].push(currentPoolId);
        }

        pool.userShares[msg.sender] += sharesToMint;
        pool.totalShares += sharesToMint;
        pool.totalDeposited += msg.value;

        emit Deposited(currentPoolId, msg.sender, msg.value, sharesToMint);

        // Try to mine if pool is large enough
        if (autoMineEnabled && pool.totalDeposited >= minPoolSize) {
            // Only try to mine if the pool has enough ETH to cover the current price
            // This prevents the deposit from reverting and ensures the pool can afford it
            uint256 currentPrice = miner.getPrice();
            if (pool.totalDeposited >= currentPrice) {
                _tryMine();
            }
        }
    }

    /**
     * @notice Withdraw from current pool (only if not yet mining)
     */
    function withdrawFromCurrentPool(uint256 shares) external nonReentrant {
        Pool storage pool = pools[currentPoolId];
        require(pool.status == PoolStatus.ACCEPTING_DEPOSITS, "Pool already mining");
        require(shares <= pool.userShares[msg.sender], "Insufficient shares");

        uint256 ethAmount = (shares * pool.totalDeposited) / pool.totalShares;
        
        pool.userShares[msg.sender] -= shares;
        pool.totalShares -= shares;
        pool.totalDeposited -= ethAmount;

        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "ETH transfer failed");

        emit Withdrawn(currentPoolId, msg.sender, ethAmount);
    }

    /**
     * @notice Claim rewards from a specific pool that was outbid
     */
    function claimRewards(uint256 poolId) external nonReentrant {
        Pool storage pool = pools[poolId];
        require(pool.status == PoolStatus.OUTBID, "Pool not ready for claims");
        require(!pool.claimed[msg.sender], "Already claimed");
        require(pool.userShares[msg.sender] > 0, "No shares in pool");

        pool.claimed[msg.sender] = true;

        // Calculate user's share of rewards
        uint256 sharePercentage = (pool.userShares[msg.sender] * 1e18) / pool.totalShares;
        
        // ETH rewards (includes initial deposit + profit)
        uint256 totalEth = pool.totalDeposited - pool.ethSpent + pool.ethReceived;
        uint256 ethReward = (totalEth * sharePercentage) / 1e18;
        
        // DONUT rewards
        uint256 donutReward = (pool.donutMined * sharePercentage) / 1e18;

        // Transfer rewards
        if (ethReward > 0) {
            (bool success, ) = msg.sender.call{value: ethReward}("");
            require(success, "ETH transfer failed");
        }

        if (donutReward > 0) {
            require(donut.transfer(msg.sender, donutReward), "DONUT transfer failed");
        }

        emit RewardsClaimed(poolId, msg.sender, ethReward, donutReward);

        // Check if all users claimed, mark pool as closed
        _checkPoolClosure(poolId);
    }

    /**
     * @notice Claim rewards from multiple pools at once
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
            uint256 totalEth = pool.totalDeposited - pool.ethSpent + pool.ethReceived;
            uint256 ethReward = (totalEth * sharePercentage) / 1e18;
            uint256 donutReward = (pool.donutMined * sharePercentage) / 1e18;

            if (ethReward > 0) {
                (bool success, ) = msg.sender.call{value: ethReward}("");
                require(success, "ETH transfer failed");
            }

            if (donutReward > 0) {
                require(donut.transfer(msg.sender, donutReward), "DONUT transfer failed");
            }

            emit RewardsClaimed(poolId, msg.sender, ethReward, donutReward);
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
        require(address(this).balance >= currentPrice, "Insufficient ETH balance");

        uint256 maxPrice = currentPrice + (currentPrice * maxPriceSlippage / DIVISOR);
        IMiner.Slot0 memory slot0 = miner.getSlot0();
        uint16 epochId = slot0.epochId;

        // Wrap ETH to WETH
        IWETH(address(quote)).deposit{value: currentPrice}();

        uint256 donutBefore = donut.balanceOf(address(this));
        uint256 quoteBefore = quote.balanceOf(address(this));

        // Approve and mine
        quote.safeApprove(address(miner), currentPrice);
        
        uint256 pricePaid = miner.mine(
            address(this),
            provider,
            epochId,
            block.timestamp + 300,
            maxPrice,
            string(abi.encodePacked("DonutPool#", _toString(currentPoolId)))
        );

        uint256 donutAfter = donut.balanceOf(address(this));
        uint256 quoteAfter = quote.balanceOf(address(this));

        uint256 donutReceived = donutAfter - donutBefore;
        
        // Calculate WETH received (rewards for previous pool)
        uint256 quoteReceived = 0;
        if (quoteAfter > (quoteBefore - pricePaid)) {
            quoteReceived = quoteAfter - (quoteBefore - pricePaid);
        }

        // Find and update the previous mining pool
        for (uint256 i = currentPoolId - 1; i > 0; i--) {
            if (pools[i].status == PoolStatus.MINING) {
                Pool storage prevPool = pools[i];
                prevPool.status = PoolStatus.OUTBID;
                prevPool.donutMined = donutReceived;
                prevPool.ethReceived = quoteReceived;
                
                // Unwrap WETH rewards to ETH
                if (quoteReceived > 0) {
                    IWETH(address(quote)).withdraw(quoteReceived);
                }
                
                emit PoolOutbid(i, quoteReceived);
                break;
            }
        }

        // Update current pool state
        pool.status = PoolStatus.MINING;
        pool.ethSpent = pricePaid;
        pool.mineTime = block.timestamp;
        // pool.donutMined is 0 for now

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
     * @notice Receive ETH payouts when pool gets outbid
     */
    receive() external payable {}

    /**
     * @notice Get user's position in current pool
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
     */
    function getClaimableRewards(uint256 poolId, address user) external view returns (
        uint256 ethReward,
        uint256 donutReward,
        bool canClaim
    ) {
        Pool storage pool = pools[poolId];
        
        if (pool.status != PoolStatus.OUTBID || pool.claimed[user] || pool.userShares[user] == 0) {
            return (0, 0, false);
        }

        uint256 sharePercentage = (pool.userShares[user] * 1e18) / pool.totalShares;
        uint256 totalEth = pool.totalDeposited - pool.ethSpent + pool.ethReceived;
        
        ethReward = (totalEth * sharePercentage) / 1e18;
        donutReward = (pool.donutMined * sharePercentage) / 1e18;
        canClaim = true;
    }

    /**
     * @notice Get all pools user participated in
     */
    function getUserPools(address user) external view returns (uint256[] memory) {
        return userPoolIds[user];
    }

    /**
     * @notice Get pool details
     */
    function getPoolDetails(uint256 poolId) external view returns (
        uint256 totalDeposited,
        uint256 totalShares,
        uint256 ethSpent,
        uint256 ethReceived,
        uint256 donutMined,
        uint256 depositorCount,
        PoolStatus status
    ) {
        Pool storage pool = pools[poolId];
        return (
            pool.totalDeposited,
            pool.totalShares,
            pool.ethSpent,
            pool.ethReceived,
            pool.donutMined,
            pool.depositors.length,
            pool.status
        );
    }

    /**
     * @notice Get current price from miner
     */
    function getCurrentGlazePrice() external view returns (uint256) {
        return miner.getPrice();
    }

    /**
     * @notice Update settings (onlyOwner)
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
     */
    function updateProvider(address _provider) external onlyOwner {
        provider = _provider;
    }

    /**
     * @notice Helper to convert uint to string
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
     * @notice Rescue stuck tokens or ETH (onlyOwner)
     * @dev Emergency function to recover funds sent by mistake. 
     *      WARNING: Owner can technically withdraw pool funds with this, so trust is required.
     */
    function rescueFunds(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }
}
