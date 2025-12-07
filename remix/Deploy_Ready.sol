// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Ready-to-Deploy DonuettesComining
 * @notice This file contains the deployment addresses pre-configured
 * 
 * DEPLOYMENT ADDRESSES:
 * - DonuetteMiner: 0xe1f972216da2d14f0a0f6afb115940151b78decb
 * - Donuette Token: 0x89d326378b7f807d9e8cf06e921e99d6cb85bb0a
 * - DONUT Token: 0xae4a37d554c6d6f3e398546d8566b25052e0169c
 * - Provider: 0xD343e99D993b63B0b7d86320ae0611E3018E4e1f
 * 
 * INSTRUCTIONS:
 * 1. Make sure DonuettesComining.sol is compiled in Remix
 * 2. Go to Deploy & Run Transactions
 * 3. Select "DonuettesComining" contract
 * 4. Use these constructor parameters:
 *    _miner: 0xe1f972216da2d14f0a0f6afb115940151b78decb
 *    _donuette: 0x89d326378b7f807d9e8cf06e921e99d6cb85bb0a
 *    _donut: 0xae4a37d554c6d6f3e398546d8566b25052e0169c
 *    _provider: 0xD343e99D993b63B0b7d86320ae0611E3018E4e1f
 * 5. Click Deploy!
 */

// This contract is just for reference - deploy DonuettesComining directly in Remix
contract DeploymentHelper {
    address public constant DONUETTE_MINER = 0xe1f972216da2d14f0a0f6afb115940151b78decb;
    address public constant DONUETTE_TOKEN = 0x89d326378b7f807d9e8cf06e921e99d6cb85bb0a;
    address public constant DONUT_TOKEN = 0xae4a37d554c6d6f3e398546d8566b25052e0169c;
    address public constant PROVIDER = 0xD343e99D993b63B0b7d86320ae0611E3018E4e1f;
    
    function getDeploymentParams() public pure returns (
        address miner,
        address donuette,
        address donut,
        address provider
    ) {
        return (
            0xe1f972216da2d14f0a0f6afb115940151b78decb, // _miner
            0x89d326378b7f807d9e8cf06e921e99d6cb85bb0a, // _donuette
            0xae4a37d554c6d6f3e398546d8566b25052e0169c, // _donut
            0xD343e99D993b63B0b7d86320ae0611E3018E4e1f  // _provider
        );
    }
}

