// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DonuettesComining} from "../src/DonuettesComining.sol";
import {DonuetteMiner} from "../src/DonuetteMiner.sol";

contract DeployDonuettesComining is Script {
    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Retrieve contract addresses from environment variables
        address donuetteMinerAddress = vm.envAddress("DONUETTE_MINER_ADDRESS");
        address donut = vm.envAddress("DONUT_ADDRESS");
        address provider = vm.envAddress("PROVIDER_ADDRESS");

        // Get Donuette token address from DonuetteMiner contract
        DonuetteMiner donuetteMiner = DonuetteMiner(donuetteMinerAddress);
        address donuette = donuetteMiner.donuette();

        console.log("DonuetteMiner address:", donuetteMinerAddress);
        console.log("Donuette token address:", donuette);
        console.log("DONUT token address:", donut);
        console.log("Provider address:", provider);

        vm.startBroadcast(deployerPrivateKey);

        // Owner is the deployer address
        address owner = vm.addr(deployerPrivateKey);

        DonuettesComining pool = new DonuettesComining(
            donuetteMinerAddress,
            donuette,
            donut,
            provider,
            owner
        );

        console.log("DonuettesComining Pool deployed at:", address(pool));
        console.log("Owner address:", owner);

        vm.stopBroadcast();
    }
}
