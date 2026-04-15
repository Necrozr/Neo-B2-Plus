#!/bin/bash
set -e

echo "=========================================="
echo "  Neo B2-Plus - Solana Mainnet Deploy"
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

if ! command -v solana &> /dev/null; then
    echo -e "${RED}[ERROR] Solana CLI not found${NC}"
    echo ""
    echo "Install from: https://docs.solana.com/cli/install-solana-cli-tools"
    echo "  curl -sSfL https://release.solana.com/stable/install.sh | sh"
    exit 1
fi

if ! command -v anchor &> /dev/null; then
    echo -e "${RED}[ERROR] Anchor CLI not found${NC}"
    echo ""
    echo "Install with:"
    echo "  npm install -g @project-serum/anchor-cli"
    echo "  # or"
    echo "  cargo install anchor-cli"
    exit 1
fi

CLUSTER="${SOLANA_CLUSTER:-mainnet}"
echo -e "${YELLOW}[INFO] Target cluster: $CLUSTER${NC}"

ANCHOR_TOML="$SCRIPT_DIR/contracts/solana/Anchor.toml"
PROGRAMS_DIR="$SCRIPT_DIR/contracts/solana/programs/splitter/target/deploy"

echo -e "\n${YELLOW}[1/5]${NC} Checking wallet..."
solana address
solana balance

echo -e "\n${YELLOW}[2/5]${NC} Building Solana program..."
cd "$SCRIPT_DIR/contracts/solana"
anchor build
echo -e "${GREEN}[PASS] Build successful${NC}"

PROGRAM_KEYPAIR="$PROGRAMS_DIR/neo_splitter-keypair.json"
if [ ! -f "$PROGRAM_KEYPAIR" ]; then
    echo -e "${YELLOW}[INFO] Generating new program keypair...${NC}"
    solana-keygen new -o "$PROGRAM_KEYPAIR" --no-passphrase -s
fi

PROGRAM_ID=$(solana-keypair pubkey "$PROGRAM_KEYPAIR")
echo -e "${YELLOW}[INFO] Program ID: $PROGRAM_ID${NC}"

echo -e "\n${YELLOW}[3/5]${NC} Updating Anchor.toml with Program ID..."
sed -i.bak "s/neo_splitter = \".*\"/neo_splitter = \"$PROGRAM_ID\"/" "$ANCHOR_TOML"
echo -e "${GREEN}[PASS] Anchor.toml updated${NC}"

echo -e "\n${YELLOW}[4/5]${NC} Rebuilding with new ID..."
anchor build
echo -e "${GREEN}[PASS] Rebuilt${NC}"

echo -e "\n${YELLOW}[5/5]${NC} Deploying to $CLUSTER..."

if [ "$CLUSTER" = "mainnet" ]; then
    solana program deploy \
        --url "$CLUSTER" \
        --keypair "$PROGRAM_KEYPAIR" \
        "$PROGRAMS_DIR/neo_splitter.so"
else
    anchor deploy --provider.cluster "$CLUSTER"
fi

echo -e "${GREEN}[PASS] Deployed successfully${NC}"

echo -e "\n${YELLOW}[INFO]${NC} Initializing factory..."
echo ""
echo "Run this command to initialize the factory:"
echo ""
echo "  anchor run initialize_factory \\"
echo "    --provider.cluster $CLUSTER \\"
echo "    --keypair ~/.config/solana/id.json"
echo ""
echo "Or use the SDK/CLI with:"
echo "  Program ID: $PROGRAM_ID"
echo ""

DEPLOYMENTS_FILE="$SCRIPT_DIR/deployments.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat > "$SCRIPT_DIR/deployments_solana.json" << EOF
{
  "network": "solana-$CLUSTER",
  "programId": "$PROGRAM_ID",
  "cluster": "$CLUSTER",
  "feeBps": 10,
  "timestamp": "$TIMESTAMP",
  "setup": {
    "factory": {
      "seeds": ["factory"],
      "space": "8 + 32 + 32 + 32 + 2 + 1 + 1 = ~81 bytes"
    },
    "merchant": {
      "seeds": ["merchant", <merchant_wallet>],
      "space": "8 + 32 + 32 + 32 + 8 + 1 = ~114 bytes"
    },
    "payment": {
      "seeds": ["payment", <payment_id>],
      "space": "8 + 32 + 32 + 32 + 8 + 8 + 8 + 8 + 1 = ~145 bytes"
    }
  }
}
EOF

echo -e "${GREEN}[PASS] Saved to deployments_solana.json${NC}"

if [ -f "$DEPLOYMENTS_FILE" ]; then
    node -e "
    const fs = require('fs');
    const data = JSON.parse(fs.readFileSync('$DEPLOYMENTS_FILE', 'utf8'));
    if (!data.solana) data.solana = {};
    data.solana = {
      programId: '$PROGRAM_ID',
      cluster: '$CLUSTER',
      feeBps: 10,
      timestamp: '$TIMESTAMP'
    };
    fs.writeFileSync('$DEPLOYMENTS_FILE', JSON.stringify(data, null, 2));
    "
    echo -e "${GREEN}[PASS] Updated deployments.json${NC}"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "  Solana Deploy Complete"
echo "==========================================${NC}"
echo ""
echo "Config for config.json:"
echo "  solana:"
echo "    programId: $PROGRAM_ID"
echo "    cluster: $CLUSTER"
echo "    rpcUrls:"
echo "      - https://api.mainnet-beta.solana.com"
echo ""
echo "Next: Deploy EVM contracts: node scripts/deploy_evm.js"
echo "      Deploy Tron: bash scripts/deploy_tron.sh"
echo ""
