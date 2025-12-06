// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/DonuetteMiner.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockDONUT is ERC20 {
    constructor() ERC20("Donut", "DONUT") {
        _mint(msg.sender, 100000000 * 1e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DonuetteMinerTest is Test {
    DonuetteMiner public miner;
    Donuette public donuette;
    MockDONUT public donut;

    address public treasury = makeAddr("treasury");
    address public provider = makeAddr("provider");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    function setUp() public {
        donut = new MockDONUT();
        miner = new DonuetteMiner(address(donut), treasury);
        donuette = Donuette(miner.donuette());

        // Fund users
        donut.mint(user1, 10000 * 1e18);
        donut.mint(user2, 10000 * 1e18);
        
        vm.prank(user1);
        donut.approve(address(miner), type(uint256).max);
        vm.prank(user2);
        donut.approve(address(miner), type(uint256).max);
    }

    function testInitialState() public {
        assertEq(address(miner.donut()), address(donut));
        assertEq(miner.treasury(), treasury);
        
        DonuetteMiner.Slot0 memory slot0 = miner.getSlot0();
        assertEq(slot0.miner, treasury); // Initial miner is treasury
        assertEq(slot0.epochId, 0);
    }

    function testMine() public {
        // User 1 mines
        vm.prank(user1);
        uint256 price = miner.mine(user1, provider, 0, block.timestamp + 100, type(uint256).max, "test");
        
        DonuetteMiner.Slot0 memory slot0 = miner.getSlot0();
        assertEq(slot0.miner, user1);
        assertEq(slot0.epochId, 1);
        
        // Check fees
        // Initial miner was treasury, so 80% goes to treasury (as previous miner)
        // 20% fee split: 5% provider, 15% treasury.
        // Total to treasury: 80% + 15% = 95%.
        // Total to provider: 5%.
        
        uint256 totalFee = price * 2000 / 10000;
        uint256 providerFee = totalFee / 4;
        uint256 treasuryFee = totalFee - providerFee;
        uint256 minerReward = price - totalFee;
        
        assertEq(donut.balanceOf(provider), providerFee);
        // Treasury was the initial miner, so it gets the minerReward too
        assertEq(donut.balanceOf(treasury), treasuryFee + minerReward);
    }

    function testMinting() public {
        // Advance time to generate some rewards
        vm.warp(block.timestamp + 100);
        
        // User 1 mines
        vm.prank(user1);
        miner.mine(user1, address(0), 0, block.timestamp + 100, type(uint256).max, "test");
        
        // Advance time again
        vm.warp(block.timestamp + 100);
        
        // User 2 mines
        vm.prank(user2);
        miner.mine(user2, address(0), 1, block.timestamp + 100, type(uint256).max, "test2");
        
        // User 1 should have received Donuettes
        // DPS is initially 4 ether per second
        // 100 seconds passed (between user1 mine and user2 mine)
        // Wait, the minting happens for the PREVIOUS miner based on time elapsed SINCE previous mine.
        // 1. Initial state: miner=treasury, time=T0
        // 2. T0+100: User1 mines. 
        //    - Time passed: 100s.
        //    - Mints to treasury: 100 * 4 = 400 Donuette.
        //    - New miner: User1. New time: T0+100.
        // 3. T0+200: User2 mines.
        //    - Time passed: 100s.
        //    - Mints to User1: 100 * 4 = 400 Donuette.
        
        uint256 expectedMint = 100 * 4 ether;
        assertEq(donuette.balanceOf(user1), expectedMint);
    }
    
    function testPriceDecay() public {
        uint256 initialPrice = miner.getPrice();
        assertEq(initialPrice, 5 ether); // MIN_INIT_PRICE
        
        vm.warp(block.timestamp + 1800); // 30 mins (half of 1 hour epoch)
        
        uint256 midPrice = miner.getPrice();
        // Should be roughly half
        assertApproxEqRel(midPrice, 2.5 ether, 0.01e18); // 1% tolerance
        
        vm.warp(block.timestamp + 1800); // Another 30 mins (total 1 hour)
        uint256 endPrice = miner.getPrice();
        assertEq(endPrice, 0.01 ether); // Should hit floor (0.01 DONUT)
    }

    function testExpired() public {
        vm.prank(user1);
        vm.expectRevert(DonuetteMiner.DonuetteMiner__Expired.selector);
        miner.mine(user1, provider, 0, block.timestamp - 1, type(uint256).max, "test");
    }

    function testEpochMismatch() public {
        vm.prank(user1);
        vm.expectRevert(DonuetteMiner.DonuetteMiner__EpochIdMismatch.selector);
        miner.mine(user1, provider, 1, block.timestamp + 100, type(uint256).max, "test");
    }

    function testMaxPriceExceeded() public {
        uint256 currentPrice = miner.getPrice();
        vm.prank(user1);
        vm.expectRevert(DonuetteMiner.DonuetteMiner__MaxPriceExceeded.selector);
        miner.mine(user1, provider, 0, block.timestamp + 100, currentPrice - 1, "test");
    }
}
