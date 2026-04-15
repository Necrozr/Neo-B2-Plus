#!/bin/bash
set -e

echo "=========================================="
echo "  Neo B2-Plus - Tron Mainnet Deploy"
echo "=========================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ -f "../.env" ]; then
    export $(grep -v '^#' ../.env | xargs 2>/dev/null || true)
fi

if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs 2>/dev/null || true)
fi

if [ -z "$TRON_PRIVATE_KEY" ]; then
    echo -e "${RED}[ERROR] TRON_PRIVATE_KEY not set in .env${NC}"
    echo ""
    echo "Add to .env:"
    echo "  TRON_PRIVATE_KEY=your_tron_private_key"
    echo "  TRON_GRID_URL=https://api.trongrid.io"
    exit 1
fi

TRON_GRID_URL="${TRON_GRID_URL:-https://api.trongrid.io}"
echo -e "${YELLOW}[INFO] Using TronGrid: $TRON_GRID_URL${NC}"

echo -e "\n${YELLOW}[1/3]${NC} Compiling contracts..."
npx hardhat compile --force
echo -e "${GREEN}[PASS] Compilation successful${NC}"

echo -e "\n${YELLOW}[2/3]${NC} Deploying to Tron mainnet..."

cat > /tmp/deploy_tron.js << 'TRONEOF'
const { ethers } = require("hardhat");
const TronWeb = require("tronweb");

async function deploy() {
  const privateKey = process.env.TRON_PRIVATE_KEY;
  const tronGridUrl = process.env.TRON_GRID_URL || "https://api.trongrid.io";

  const tronWeb = new TronWeb({
    fullHost: tronGridUrl,
    privateKey: privateKey,
  });

  const wallet = tronWeb.defaultAddress;
  console.log(`[INFO] Deployer: ${wallet.base58}`);

  const balance = await tronWeb.trx.getBalance(wallet.base58);
  const balanceTRX = (balance / 1e6).toFixed(2);
  console.log(`[INFO] Balance: ${balanceTRX} TRX`);

  if (parseFloat(balanceTRX) < 50) {
    console.error(`[ERROR] Insufficient TRX. Need at least 50 TRX, have ${balanceTRX} TRX`);
    process.exit(1);
  }

  console.log(`\n[DEPLOY] SplitterLogic...`);
  const SplitterLogic = await ethers.getContractFactory("contracts/tron/SplitterLogic.sol:SplitterLogic");
  const splitterImpl = await SplitterLogic.deploy();
  await splitterImpl.waitForDeployment();
  const splitterAddr = await splitterImpl.getAddress();
  const splitterTron = tronWeb.address.fromHex(splitterAddr.replace("0x", "0x41"));
  console.log(`[DONE] SplitterLogic: ${splitterTron}`);

  console.log(`\n[DEPLOY] MerchantFactory...`);
  const MerchantFactory = await ethers.getContractFactory("contracts/tron/MerchantFactory.sol:MerchantFactory");
  const factory = await MerchantFactory.deploy(wallet.base58, splitterTron);
  await factory.waitForDeployment();
  const factoryAddr = await factory.getAddress();
  const factoryTron = tronWeb.address.fromHex(factoryAddr.replace("0x", "0x41"));
  console.log(`[DONE] MerchantFactory: ${factoryTron}`);

  return {
    network: "tron",
    chainId: 728126428,
    splitterLogic: splitterTron,
    factory: factoryTron,
    deployer: wallet.base58,
    feeBps: 10,
    tronGridUrl: tronGridUrl,
    timestamp: new Date().toISOString(),
  };
}

deploy()
  .then(result => {
    console.log("\n" + "=".repeat(50));
    console.log("Deployment Result");
    console.log("=".repeat(50));
    console.log(JSON.stringify(result, null, 2));
    console.log("=".repeat(50));
  })
  .catch(error => {
    console.error("[ERROR]", error);
    process.exit(1);
  });
TRONEOF

TRON_PRIVATE_KEY="$TRON_PRIVATE_KEY" TRON_GRID_URL="$TRON_GRID_URL" npx hardhat run /tmp/deploy_tron.js --network tron

echo -e "\n${YELLOW}[3/3]${NC} Saving deployment info..."

DEPLOYMENTS_FILE="$SCRIPT_DIR/deployments.json"
if [ -f "$DEPLOYMENTS_FILE" ]; then
    node -e "
    const fs = require('fs');
    const data = JSON.parse(fs.readFileSync('$DEPLOYMENTS_FILE', 'utf8'));
    if (!data.tron) data.tron = {};
    data.tron = { chainId: 728126428, tronGridUrl: '$TRON_GRID_URL', timestamp: new Date().toISOString() };
    fs.writeFileSync('$DEPLOYMENTS_FILE', JSON.stringify(data, null, 2));
    "
    echo -e "${GREEN}[PASS] Updated deployments.json${NC}"
else
    echo -e "${YELLOW}[WARN] deployments.json not found. Create it with manual Tron addresses.${NC}"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "  Tron Deploy Complete"
echo "==========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Update config.json with Tron settings:"
echo "     - chainId: 728126428"
echo "     - factory: <MerchantFactory address>"
echo "     - tronGridUrl: $TRON_GRID_URL"
echo ""
echo "  2. Deploy Solana: bash scripts/deploy_solana.sh"
echo ""
echo "  3. Build Go server: go build ./cmd/server"
echo ""
