# Deploying DonuettesComining Contract in Remix IDE

This guide will help you deploy the DonuettesComining contract using Remix IDE.

## Prerequisites

1. **Deployed DonuetteMiner Contract** - You need the address of your deployed DonuetteMiner contract
2. **DONUT Token Address** - Address of the DONUT ERC20 token
3. **Provider Address** - Address of the provider (can be `0x0000000000000000000000000000000000000000` if no provider)
4. **Wallet with ETH** - For gas fees

## Method 1: Using Remix IDE with GitHub Imports (Recommended)

### Step 1: Open Remix IDE
Go to [https://remix.ethereum.org](https://remix.ethereum.org)

### Step 2: Configure Remix for OpenZeppelin Imports

1. Go to **Settings** (gear icon)
2. Under **Compiler**, enable **"Auto compile"**
3. Under **General**, make sure **"Enable localhost network"** is checked if testing locally

### Step 3: Add Files to Remix

1. Create a new file: `DonuettesComining.sol`
2. Copy the contents from `src/DonuettesComining.sol`
3. Remix will automatically resolve OpenZeppelin imports from GitHub

**Note:** If imports don't resolve automatically, you can manually configure the import paths:
- Go to **Settings** → **Compiler**
- Add import path: `@openzeppelin/contracts/=https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/contracts/`

### Step 4: Get Donuette Token Address

Before deploying, you need to get the Donuette token address from your DonuetteMiner contract:

1. In Remix, go to **Deploy & Run Transactions**
2. Connect to your network (Injected Web3 or your RPC)
3. At the bottom, under **"At Address"**, enter your DonuetteMiner contract address
4. Use the ABI from DonuetteMiner to call `donuette()` function
5. Copy the returned address - this is your Donuette token address

**Or use this JavaScript snippet in Remix console:**
```javascript
// Replace with your DonuetteMiner address
const minerAddress = "0x...";
const minerABI = [{"inputs":[],"name":"donuette","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"}];
const miner = new ethers.Contract(minerAddress, minerABI, ethers.provider);
const donuetteAddress = await miner.donuette();
console.log("Donuette address:", donuetteAddress);
```

### Step 5: Deploy DonuettesComining

1. Go to **Deploy & Run Transactions** tab
2. Select your environment:
   - **JavaScript VM** (for testing)
   - **Injected Web3** (for mainnet/testnet with MetaMask)
   - **Custom RPC** (for custom networks)
3. Select **"DonuettesComining"** from the contract dropdown
4. Fill in the constructor parameters:
   ```
   _miner: <DonuetteMiner contract address>
   _donuette: <Donuette token address from step 4>
   _donut: <DONUT token address>
   _provider: <Provider address or 0x0000000000000000000000000000000000000000>
   ```
5. Click **"Deploy"**
6. Confirm the transaction in your wallet (if using Injected Web3)
7. Copy the deployed contract address

## Method 2: Using the Helper Deployment Contract

### Step 1: Add Helper Contract

1. Create a new file: `DeployDonuettesComining.sol`
2. Copy the contents from `remix/DeployDonuettesComining.sol`

### Step 2: Compile Both Contracts

1. Compile `DonuettesComining.sol` first
2. Then compile `DeployDonuettesComining.sol`

### Step 3: Deploy Using Helper

1. Deploy `DeployDonuettesComining` contract (no constructor parameters)
2. Call the `deploy()` function with:
   - `_miner`: DonuetteMiner address
   - `_donuette`: Donuette token address
   - `_donut`: DONUT token address
   - `_provider`: Provider address
3. The function returns the deployed DonuettesComining contract address

### Step 4: Get Donuette Address (Alternative)

You can also use the helper contract's `getDonuetteAddress()` function:
1. Call `getDonuetteAddress(minerAddress)` with your DonuetteMiner address
2. It will return the Donuette token address

## Method 3: Using Flattened Contract

If you're having issues with imports, you can use a flattened version:

1. Use a tool like `forge flatten` or `truffle-flattener` to create a single file
2. Copy the flattened contract to Remix
3. Deploy directly without worrying about imports

## Constructor Parameters Reference

```solidity
constructor(
    address _miner,      // DonuetteMiner contract address
    address _donuette,    // Donuette token address (get from DonuetteMiner.donuette())
    address _donut,       // DONUT ERC20 token address
    address _provider     // Provider address (can be zero address)
)
```

## Verification

After deployment, verify the contract:

1. Check that `currentPoolId()` returns `1` (first pool is created automatically)
2. Check that `miner()`, `donuette()`, `donut()`, and `provider()` return the correct addresses
3. Check that `minDeposit()` returns `5000000000000000000` (5 DONUT with 18 decimals)

## Troubleshooting

### Import Errors
- Make sure you're using Solidity version `^0.8.19`
- Check that OpenZeppelin contracts are accessible (Remix should auto-resolve from GitHub)
- If issues persist, use the flattened contract approach

### Deployment Fails
- Check that all addresses are valid (not zero address except provider)
- Ensure you have enough ETH for gas
- Verify the DonuetteMiner contract is deployed and accessible
- Make sure the Donuette token address is correct (call `donuette()` on DonuetteMiner)

### Network Issues
- Make sure you're connected to the correct network
- Check your RPC endpoint is working
- Verify your wallet has sufficient balance

## Example Deployment Values

For testing purposes, you can use these example values (replace with your actual addresses):

```
_miner: 0x1234567890123456789012345678901234567890
_donuette: 0xabcdefabcdefabcdefabcdefabcdefabcdefabcd
_donut: 0x9876543210987654321098765432109876543210
_provider: 0x0000000000000000000000000000000000000000
```

## Next Steps

After deployment:
1. Save the contract address
2. Verify the contract on a block explorer (if on mainnet/testnet)
3. Update your frontend/dApp to use the new contract address
4. Test the contract functions (deposit, mine, claimRewards, etc.)

