// Remix IDE Deployment Script for DonuettesComining
// Copy and paste this into Remix IDE's JavaScript VM or Injected Web3 environment

async function deployDonuettesComining() {
    // ============================================
    // CONFIGURE THESE VALUES BEFORE DEPLOYING
    // ============================================
    const DONUETTE_MINER_ADDRESS = "0x..."; // Address of deployed DonuetteMiner contract
    const DONUT_ADDRESS = "0x...";          // Address of DONUT token
    const PROVIDER_ADDRESS = "0x...";       // Provider address (can be 0x0000000000000000000000000000000000000000)
    
    // ============================================
    // Get Donuette token address from DonuetteMiner
    // ============================================
    console.log("Getting Donuette token address from DonuetteMiner...");
    
    // ABI for donuette() function
    const minerABI = [
        {
            "inputs": [],
            "name": "donuette",
            "outputs": [{"internalType": "address", "name": "", "type": "address"}],
            "stateMutability": "view",
            "type": "function"
        }
    ];
    
    const minerContract = new ethers.Contract(DONUETTE_MINER_ADDRESS, minerABI, ethers.provider);
    const DONUETTE_ADDRESS = await minerContract.donuette();
    
    console.log("DonuetteMiner address:", DONUETTE_MINER_ADDRESS);
    console.log("Donuette token address:", DONUETTE_ADDRESS);
    console.log("DONUT token address:", DONUT_ADDRESS);
    console.log("Provider address:", PROVIDER_ADDRESS);
    
    // ============================================
    // Deploy DonuettesComining Contract
    // ============================================
    console.log("\nDeploying DonuettesComining contract...");
    
    // Get the contract ABI and bytecode
    // In Remix, you can get this from the compiled contract
    // For now, we'll use the DeployDonuettesComining helper contract
    
    // Option 1: Deploy using the helper contract
    const deployerABI = [
        {
            "inputs": [
                {"internalType": "address", "name": "_miner", "type": "address"},
                {"internalType": "address", "name": "_donuette", "type": "address"},
                {"internalType": "address", "name": "_donut", "type": "address"},
                {"internalType": "address", "name": "_provider", "type": "address"}
            ],
            "name": "deploy",
            "outputs": [{"internalType": "address", "name": "pool", "type": "address"}],
            "stateMutability": "nonpayable",
            "type": "function"
        }
    ];
    
    // First, deploy the helper contract (or use it if already deployed)
    // Then call deploy() with the parameters
    
    // Option 2: Direct deployment (if you have the bytecode)
    // Uncomment and use this if you have the compiled bytecode
    /*
    const DonuettesCominingFactory = await ethers.getContractFactory("DonuettesComining");
    const pool = await DonuettesCominingFactory.deploy(
        DONUETTE_MINER_ADDRESS,
        DONUETTE_ADDRESS,
        DONUT_ADDRESS,
        PROVIDER_ADDRESS
    );
    
    await pool.deployed();
    console.log("DonuettesComining deployed at:", pool.address);
    */
    
    console.log("\n=== Deployment Instructions ===");
    console.log("1. Compile DonuettesComining.sol in Remix");
    console.log("2. Go to Deploy & Run Transactions");
    console.log("3. Select your environment (JavaScript VM or Injected Web3)");
    console.log("4. Select 'DonuettesComining' from the contract dropdown");
    console.log("5. Fill in the constructor parameters:");
    console.log("   - _miner:", DONUETTE_MINER_ADDRESS);
    console.log("   - _donuette:", DONUETTE_ADDRESS);
    console.log("   - _donut:", DONUT_ADDRESS);
    console.log("   - _provider:", PROVIDER_ADDRESS);
    console.log("6. Click 'Deploy'");
    console.log("\nOr use the DeployDonuettesComining helper contract for easier deployment!");
}

// Run the deployment
deployDonuettesComining().catch(console.error);

