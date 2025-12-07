# DonuettesComining Deployment Checklist

## ✅ Pre-Deployment Checklist

- [ ] DonuetteMiner contract is deployed
- [ ] Have DonuetteMiner contract address
- [ ] Have DONUT token contract address
- [ ] Have provider address (or use zero address)
- [ ] Wallet connected to Remix with sufficient ETH for gas
- [ ] Correct network selected (mainnet/testnet/local)

## 📝 Required Information

Before deploying, gather these addresses:

1. **DonuetteMiner Address**: `0x...`
2. **DONUT Token Address**: `0x...`
3. **Provider Address**: `0x...` (or `0x0000000000000000000000000000000000000000`)
4. **Donuette Token Address**: `0x...` (get from DonuetteMiner)

## 🚀 Deployment Steps

### Step 1: Get Donuette Token Address

**In Remix Console:**
```javascript
// Replace YOUR_MINER_ADDRESS with your DonuetteMiner address
const miner = await ethers.getContractAt(
  ["function donuette() view returns (address)"],
  "YOUR_MINER_ADDRESS"
);
const donuette = await miner.donuette();
console.log("Donuette token:", donuette);
```

**Or use the helper contract:**
1. Deploy `DeployDonuettesComining.sol`
2. Call `getDonuetteAddress(YOUR_MINER_ADDRESS)`

### Step 2: Add Contract to Remix

- [ ] Create new file: `DonuettesComining.sol`
- [ ] Copy content from `src/DonuettesComining.sol`
- [ ] Remix auto-resolves OpenZeppelin imports ✅

### Step 3: Compile

- [ ] Go to **Solidity Compiler** tab
- [ ] Select compiler: **0.8.19+**
- [ ] Click **"Compile DonuettesComining.sol"**
- [ ] ✅ No errors

### Step 4: Deploy

- [ ] Go to **Deploy & Run Transactions**
- [ ] Select environment: **Injected Web3** or **JavaScript VM**
- [ ] Select contract: **"DonuettesComining"**
- [ ] Fill constructor:
  ```
  _miner: [DonuetteMiner address]
  _donuette: [Donuette token address from Step 1]
  _donut: [DONUT token address]
  _provider: [Provider address or 0x0000...0000]
  ```
- [ ] Click **"Deploy"**
- [ ] Confirm transaction
- [ ] ✅ Copy deployed address!

## ✅ Post-Deployment Verification

Test these functions on the deployed contract:

- [ ] `currentPoolId()` → Returns `1`
- [ ] `miner()` → Returns DonuetteMiner address
- [ ] `donuette()` → Returns Donuette token address
- [ ] `donut()` → Returns DONUT token address
- [ ] `provider()` → Returns provider address
- [ ] `minDeposit()` → Returns `100000000000000000000` (100 DONUT)

## 📋 Save This Information

After deployment, save:

```
Deployed Contract Address: 0x...
Deployment Network: [mainnet/testnet/local]
Deployment Date: [date]
Transaction Hash: 0x...
```

## 🆘 Need Help?

- Check `QUICK_START.md` for quick reference
- Check `README.md` for detailed instructions
- Check `deploy.js` for JavaScript deployment script

