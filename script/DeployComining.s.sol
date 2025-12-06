// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {Comining} from "../src/Comining.sol";

contract DeployComining is Script {
    function setUp() public {}

    function run() public {
        // Retrieve private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Retrieve contract addresses from environment variables
        // You need to create a .env file with these values
        address miner = vm.envAddress("MINER_ADDRESS");
        address donut = vm.envAddress("DONUT_ADDRESS");
        address quote = vm.envAddress("WETH_ADDRESS");
        address provider = vm.envAddress("PROVIDER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        Comining pool = new Comining(
            miner,
            donut,
            quote,
            provider
        );

        console.log("Comining Pool deployed at:", address(pool));

        vm.stopBroadcast();
    }
}
