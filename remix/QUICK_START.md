# Quick Start: Deploy DonuettesComining in Remix IDE

## 🚀 Fast Deployment Steps

### 1. Open Remix IDE
Visit [remix.ethereum.org](https://remix.ethereum.org)

### 2. Get Your Contract Addresses Ready
You'll need:
- ✅ DonuetteMiner contract address
- ✅ DONUT token address  
- ✅ Provider address (or use `0x0000000000000000000000000000000000000000`)

### 3. Get Donuette Token Address

**Option A: Using Remix**
1. In Remix, go to **Deploy & Run Transactions**
2. Under **"At Address"**, paste your DonuetteMiner address
3. Use this ABI to call `donuette()`:
```json
[{"inputs":[],"name":"donuette","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"}]
```

**Option B: Using JavaScript in Remix Console**
```javascript
const miner = await ethers.getContractAt(
  ["function donuette() view returns (address)"],
  "YOUR_MINER_ADDRESS_HERE"
);
const donuette = await miner.donuette();
console.log("Donuette:", donuette);
```

### 4. Add Contract to Remix

**Method 1: Direct Import (Easiest)**
1. In Remix, click **"Create New File"**
2. Name it `DonuettesComining.sol`
3. Copy the entire content from `src/DonuettesComining.sol` in this repo
4. Remix will auto-resolve OpenZeppelin imports from GitHub

**Method 2: Using GitHub**
1. In Remix, go to **File Explorer**
2. Click the **GitHub icon** (or use **Load from GitHub**)
3. Enter: `https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/contracts/`
4. Then add your contract file

### 5. Compile
1. Go to **Solidity Compiler** tab
2. Select compiler version: **0.8.19** or higher
3. Click **"Compile DonuettesComining.sol"**
4. ✅ Should compile without errors

### 6. Deploy
1. Go to **Deploy & Run Transactions**
2. Select environment:
   - **Injected Web3** (for MetaMask/mainnet/testnet)
   - **JavaScript VM** (for testing)
3. Select contract: **"DonuettesComining"**
4. Fill constructor parameters:
   ```
   _miner: 0x... (DonuetteMiner address)
   _donuette: 0x... (from step 3)
   _donut: 0x... (DONUT token address)
   _provider: 0x... (or 0x0000000000000000000000000000000000000000)
   ```
5. Click **"Deploy"**
6. Confirm transaction in MetaMask (if using Injected Web3)
7. ✅ Copy the deployed address!

## 📋 Constructor Parameters

```
_miner:      address of DonuetteMiner contract
_donuette:   address of Donuette token (call donuette() on DonuetteMiner)
_donut:       address of DONUT ERC20 token
_provider:    provider address (can be zero address: 0x0000...0000)
```

## ✅ Verify Deployment

After deployment, test these functions:
- `currentPoolId()` → should return `1`
- `miner()` → should return your DonuetteMiner address
- `donut()` → should return your DONUT token address

## 🆘 Troubleshooting

**"Cannot find module @openzeppelin/contracts"**
- Remix should auto-resolve, but if not:
  - Go to Settings → Compiler
  - Add remapping: `@openzeppelin/contracts/=https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/contracts/`

**"Deployment failed"**
- Check all addresses are valid (not zero except provider)
- Ensure you have enough ETH for gas
- Verify DonuetteMiner is deployed and accessible

**"Can't get donuette address"**
- Make sure DonuetteMiner is deployed
- Check you're on the correct network
- Verify the contract has the `donuette()` function

## 📝 Example

```solidity
// Deploy with these example values (replace with real addresses):
_miner:     0x1234567890123456789012345678901234567890
_donuette:  0xabcdefabcdefabcdefabcdefabcdefabcdefabcd  
_donut:     0x9876543210987654321098765432109876543210
_provider:  0x0000000000000000000000000000000000000000
```

Done! 🎉

