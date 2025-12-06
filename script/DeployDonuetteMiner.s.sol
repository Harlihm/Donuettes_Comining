// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DonuetteMiner} from "../src/DonuetteMiner.sol";

contract DeployDonuetteMiner is Script {
    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Retrieve contract addresses from environment variables
        address donut = vm.envAddress("DONUT_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        DonuetteMiner miner = new DonuetteMiner(
            donut,
            treasury
        );

        console.log("DonuetteMiner deployed at:", address(miner));
        console.log("Donuette token deployed at:", address(miner.donuette()));

        vm.stopBroadcast();
    }
}
