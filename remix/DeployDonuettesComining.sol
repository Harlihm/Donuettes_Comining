// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// This is a Remix IDE compatible deployment script
// 
// INSTRUCTIONS:
// 1. Make sure DonuettesComining.sol is in the same folder or adjust the import path
// 2. In Remix, you can import from GitHub or use local files
// 3. If using local files, the import path should match your Remix file structure
//
// For example, if both files are in the same folder:
// import {DonuettesComining} from "./DonuettesComining.sol";
//
// Or if DonuettesComining is in a parent folder:
// import {DonuettesComining} from "../DonuettesComining.sol";

// Adjust this import path based on your Remix file structure
import {DonuettesComining} from "../src/DonuettesComining.sol";

/**
 * @title DeployDonuettesComining
 * @notice Simple deployment contract for Remix IDE
 * @dev Call deploy() with the required parameters
 */
contract DeployDonuettesComining {
    
    /**
     * @notice Deploy DonuettesComining contract
     * @param _miner Address of the DonuetteMiner contract
     * @param _donuette Address of the Donuette token (get from DonuetteMiner.donuette())
     * @param _donut Address of the DONUT token
     * @param _provider Address of the provider (can be address(0) if no provider)
     * @return pool Address of the deployed DonuettesComining contract
     */
    function deploy(
        address _miner,
        address _donuette,
        address _donut,
        address _provider
    ) public returns (address pool) {
        DonuettesComining poolContract = new DonuettesComining(
            _miner,
            _donuette,
            _donut,
            _provider
        );
        return address(poolContract);
    }
    
    /**
     * @notice Helper function to get Donuette token address from DonuetteMiner
     * @param minerAddress Address of the DonuetteMiner contract
     * @return donuetteAddress Address of the Donuette token
     */
    function getDonuetteAddress(address minerAddress) public view returns (address donuetteAddress) {
        // Interface to get donuette address
        (bool success, bytes memory data) = minerAddress.staticcall(
            abi.encodeWithSignature("donuette()")
        );
        require(success, "Failed to get donuette address");
        return abi.decode(data, (address));
    }
}

