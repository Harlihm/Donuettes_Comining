// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../src/Comining.sol";
import "../src/Contract.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
}

contract CominingTest is Test {
    Comining public pool;
    Miner public miner;
    Donut public donut;
    MockWETH public weth;

    address public treasury = makeAddr("treasury");
    address public provider = makeAddr("provider");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    receive() external payable {}

    function setUp() public {
        // Deploy WETH
        weth = new MockWETH();

        // Deploy Miner
        miner = new Miner(address(weth), treasury);
        donut = Donut(miner.donut());

        // Deploy Pool
        pool = new Comining(
            address(miner),
            address(donut),
            address(weth),
            provider
        );

        // Label addresses
        vm.label(address(pool), "Pool");
        vm.label(address(miner), "Miner");
        vm.label(address(donut), "Donut");
        vm.label(address(weth), "WETH");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
    }

    function testInitialState() public {
        assertEq(pool.currentPoolId(), 1);
        (,,,,,, Comining.PoolStatus status) = pool.getPoolDetails(1);
        assertEq(uint(status), uint(Comining.PoolStatus.ACCEPTING_DEPOSITS));
    }

    function testDeposit() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        
        // Deposit less than minPoolSize (0.1 ether) to avoid auto-mining
        uint256 depositAmount = 0.05 ether;
        pool.deposit{value: depositAmount}();

        (uint256 poolId, uint256 deposited, uint256 shares,,) = pool.getCurrentPoolPosition(user1);
        
        assertEq(poolId, 1);
        assertEq(deposited, depositAmount);
        assertEq(shares, depositAmount); // 1:1 for first depositor
        
        vm.stopPrank();
    }

    function testMining() public {
        // 1. User deposits enough to mine
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        
        // Get current price to know how much we need
        uint256 price = miner.getPrice();
        // Deposit slightly more than price to cover slippage/fees
        uint256 depositAmount = price * 120 / 100; 
        if (depositAmount < 0.1 ether) depositAmount = 0.1 ether; // Min pool size

        pool.deposit{value: depositAmount}();
        
        // 2. Trigger mine (should happen automatically if autoMineEnabled is true and deposit is sufficient)
        // If not auto-mined (due to price fluctuation or logic), we can force it
        // But let's check if it mined.
        
        (,,,,,, Comining.PoolStatus status) = pool.getPoolDetails(1);
        
        // If it didn't auto mine, try manual mine
        if (status == Comining.PoolStatus.ACCEPTING_DEPOSITS) {
             pool.mine();
        }

        (,,,,,, status) = pool.getPoolDetails(1);
        assertEq(uint(status), uint(Comining.PoolStatus.MINING));
        
        // Check new pool created
        assertEq(pool.currentPoolId(), 2);
        
        vm.stopPrank();
    }

    function testOutbidAndRewards() public {
        // --- Pool 1 Mining ---
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        uint256 price1 = miner.getPrice();
        uint256 deposit1 = price1 * 120 / 100;
        if (deposit1 < 0.1 ether) deposit1 = 0.1 ether;
        pool.deposit{value: deposit1}();
        
        // Ensure mined
        (,,,,,, Comining.PoolStatus status1) = pool.getPoolDetails(1);
        if (status1 == Comining.PoolStatus.ACCEPTING_DEPOSITS) {
            pool.mine();
        }
        vm.stopPrank();

        // Move time forward to generate donuts and lower price for next miner
        vm.warp(block.timestamp + 10 minutes);

        // --- Pool 2 Mining (Outbidding Pool 1) ---
        vm.deal(user2, 10 ether);
        vm.startPrank(user2);
        
        uint256 price2 = miner.getPrice();
        uint256 deposit2 = price2 * 120 / 100;
        if (deposit2 < 0.1 ether) deposit2 = 0.1 ether;
        
        // Deposit into Pool 2
        pool.deposit{value: deposit2}();
        
        // Ensure mined
        (,,,,,, Comining.PoolStatus status2) = pool.getPoolDetails(2);
        if (status2 == Comining.PoolStatus.ACCEPTING_DEPOSITS) {
            pool.mine();
        }
        vm.stopPrank();

        // --- Check Pool 1 Status ---
        (,,,,,, status1) = pool.getPoolDetails(1);
        assertEq(uint(status1), uint(Comining.PoolStatus.OUTBID));

        // --- Claim Rewards for User 1 ---
        vm.startPrank(user1);
        
        uint256 balanceBefore = user1.balance;
        uint256 donutBefore = donut.balanceOf(user1);
        
        (uint256 ethReward, uint256 donutReward, bool canClaim) = pool.getClaimableRewards(1, user1);
        assertTrue(canClaim);
        assertTrue(ethReward > 0);
        // Donut reward might be 0 if mined immediately after? No, we warped 10 mins.
        // Wait, Pool 1 mined, then Pool 2 mined. 
        // When Pool 2 mines, it pays WETH to Miner. 
        // Miner pays previous miner (Pool 1) a refund/reward?
        // Let's check Miner.sol logic.
        // Miner.mine -> pays 'minerFee' to slot0Cache.miner.
        // slot0Cache.miner was Pool 1 (address(pool)).
        // So Pool 1 receives WETH.
        // Also Donut.mint is called for slot0Cache.miner (Pool 1).
        
        pool.claimRewards(1);
        
        uint256 balanceAfter = user1.balance;
        uint256 donutAfter = donut.balanceOf(user1);
        
        assertEq(balanceAfter - balanceBefore, ethReward);
        assertEq(donutAfter - donutBefore, donutReward);
        
        vm.stopPrank();
    }

    function testMultipleDeposits() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);

        // First deposit
        uint256 deposit1 = 0.02 ether;
        pool.deposit{value: deposit1}();

        // Second deposit
        uint256 deposit2 = 0.03 ether;
        pool.deposit{value: deposit2}();

        (uint256 poolId, uint256 deposited, uint256 shares,,) = pool.getCurrentPoolPosition(user1);
        
        assertEq(poolId, 1);
        assertEq(deposited, deposit1 + deposit2);
        assertEq(shares, deposit1 + deposit2);
        
        // Check internal state to ensure user isn't duplicated in arrays
        (,,,,, uint256 depositorCount,) = pool.getPoolDetails(1);
        assertEq(depositorCount, 1);

        vm.stopPrank();
    }
    function testWithdraw() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);

        uint256 depositAmount = 0.05 ether;
        pool.deposit{value: depositAmount}();

        // Check balance before withdraw
        (,, uint256 shares,,) = pool.getCurrentPoolPosition(user1);
        assertEq(shares, depositAmount);

        // Withdraw half
        uint256 withdrawShares = shares / 2;
        uint256 balanceBefore = user1.balance;
        
        pool.withdrawFromCurrentPool(withdrawShares);
        
        uint256 balanceAfter = user1.balance;
        // Since shares map 1:1 to ETH when no rewards/penalties exist yet
        assertEq(balanceAfter - balanceBefore, withdrawShares); 

        // Check pool state
        (,, uint256 remainingShares,,) = pool.getCurrentPoolPosition(user1);
        assertEq(remainingShares, shares - withdrawShares);

        vm.stopPrank();
    }

    function testRescueFunds() public {
        // Send some random ETH to the contract (not via deposit)
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        (bool success,) = address(pool).call{value: 1 ether}("");
        require(success);
        
        assertEq(address(pool).balance, 1 ether);
        
        // Send some random tokens
        MockWETH randomToken = new MockWETH();
        randomToken.deposit{value: 1 ether}();
        randomToken.transfer(address(pool), 1 ether);
        assertEq(randomToken.balanceOf(address(pool)), 1 ether);
        
        // Try to rescue as non-owner (should fail)
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        pool.rescueFunds(address(0), 1 ether);
        
        // Rescue ETH as owner
        uint256 ownerBalanceBefore = address(this).balance;
        pool.rescueFunds(address(0), 1 ether);
        assertEq(address(pool).balance, 0);
        
        // Rescue Tokens as owner
        pool.rescueFunds(address(randomToken), 1 ether);
        assertEq(randomToken.balanceOf(address(pool)), 0);
    }
}
