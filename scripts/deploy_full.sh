#!/bin/bash
set -e

echo "=========================================="
echo "  Neo B2-Plus - Complete Mainnet Deploy"
echo "=========================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs 2>/dev/null || true)
fi

DEPLOYMENTS_FILE="$SCRIPT_DIR/scripts/deployments.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

check_env() {
    if [ -z "$2" ]; then
        echo -e "${RED}[SKIP] $1 not configured${NC}"
        return 1
    fi
    echo -e "${GREEN}[OK]${NC} $1 configured"
    return 0
}

echo ""
echo -e "${BLUE}[INFO] Environment Check${NC}"
echo "------------------------------------------"

if check_env "DEPLOYER_PRIVATE_KEY (EVM)" "$DEPLOYER_PRIVATE_KEY"; then
    EVM_ENABLED=1
else
    EVM_ENABLED=0
fi

if check_env "TRON_PRIVATE_KEY (Tron)" "$TRON_PRIVATE_KEY"; then
    TRON_ENABLED=1
else
    TRON_ENABLED=0
fi

if command -v anchor &> /dev/null && [ -f "$SCRIPT_DIR/contracts/solana/Anchor.toml" ]; then
    echo -e "${GREEN}[OK]${NC} Anchor CLI and project found"
    SOLANA_ENABLED=1
else
    echo -e "${RED}[SKIP] Solana not configured (Anchor not found)${NC}"
    SOLANA_ENABLED=0
fi

echo ""
echo -e "${BLUE}[INFO] Deploy Plan${NC}"
echo "------------------------------------------"
[ $EVM_ENABLED -eq 1 ] && echo "  [x] EVM Networks (Polygon, BSC, Base, Ethereum)"
[ $EVM_ENABLED -eq 0 ] && echo "  [ ] EVM Networks (SKIPPED - set DEPLOYER_PRIVATE_KEY)"
[ $TRON_ENABLED -eq 1 ] && echo "  [x] Tron Network"
[ $TRON_ENABLED -eq 0 ] && echo "  [ ] Tron Network (SKIPPED - set TRON_PRIVATE_KEY)"
[ $SOLANA_ENABLED -eq 1 ] && echo "  [x] Solana (Anchor)"
[ $SOLANA_ENABLED -eq 0 ] && echo "  [ ] Solana (SKIPPED - Anchor not configured)"
echo ""

if [ $EVM_ENABLED -eq 0 ] && [ $TRON_ENABLED -eq 0 ] && [ $SOLANA_ENABLED -eq 0 ]; then
    echo -e "${RED}[ERROR] Nothing to deploy. Configure at least one network.${NC}"
    echo ""
    echo "Required environment variables:"
    echo "  EVM:       DEPLOYER_PRIVATE_KEY"
    echo "  Tron:      TRON_PRIVATE_KEY"
    echo "  Solana:    (Anchor CLI only)"
    exit 1
fi

init_deployments() {
    if [ ! -f "$DEPLOYMENTS_FILE" ]; then
        cat > "$DEPLOYMENTS_FILE" << EOF
{
  "version": "1.0.0",
  "networkType": "mainnet",
  "createdAt": "$TIMESTAMP",
  "evm": [],
  "tron": null,
  "solana": null
}
EOF
    fi
}

CONTRACT_VARS=""

echo -e "${BLUE}==========================================${NC}"
echo ""

if [ $EVM_ENABLED -eq 1 ]; then
    echo -e "${YELLOW}[1/?] Deploying EVM contracts...${NC}"
    echo "------------------------------------------"
    cd "$SCRIPT_DIR/scripts"
    node deploy_evm.js
    echo ""
fi

if [ $TRON_ENABLED -eq 1 ]; then
    echo -e "${YELLOW}[2/?] Deploying Tron contracts...${NC}"
    echo "------------------------------------------"
    bash "$SCRIPT_DIR/scripts/deploy_tron.sh"
    echo ""
fi

if [ $SOLANA_ENABLED -eq 1 ]; then
    echo -e "${YELLOW}[3/?] Deploying Solana program...${NC}"
    echo "------------------------------------------"
    bash "$SCRIPT_DIR/scripts/deploy_solana.sh"
    echo ""
fi

echo ""
echo -e "${GREEN}=========================================="
echo "  Deployment Complete!"
echo "==========================================${NC}"
echo ""

if [ -f "$DEPLOYMENTS_FILE" ]; then
    echo -e "${BLUE}Deployments saved to:${NC} $DEPLOYMENTS_FILE"
    echo ""
    echo "Contents:"
    cat "$DEPLOYMENTS_FILE"
fi

echo ""
echo -e "${BLUE}[NEXT STEPS]${NC}"
echo "------------------------------------------"
echo ""
echo "1. Copy deployments.json to config:"
echo "   cp scripts/deployments.json config/"
echo ""
echo "2. Update config.json with network settings"
echo ""
echo "3. Build Go server:"
echo "   go build -o neob2plus ./cmd/server"
echo ""
echo "4. Run server:"
echo "   ./neob2plus"
echo ""
echo "5. Register routers (if needed):"
echo "   # Add allowed DEX routers via factory contract"
echo ""
echo "=========================================="
