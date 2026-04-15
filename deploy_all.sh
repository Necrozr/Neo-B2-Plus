#!/bin/bash
set -e

echo "=========================================="
echo "  Neo B2-Plus - Full Build & Deploy"
echo "=========================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --contracts-only    Deploy smart contracts only (no Go build)"
    echo "  --go-only          Build Go only (skip contract deployment)"
    echo "  --all              Full deploy (contracts + Go)"
    echo "  --init             Initialize new deployment (creates config)"
    echo "  --help             Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  DEPLOYER_PRIVATE_KEY   EVM deployment key"
    echo "  TRON_PRIVATE_KEY       Tron deployment key"
    echo "  SOLANA_CLUSTER         Solana cluster (default: mainnet)"
    echo ""
}

CONTRACTS_ONLY=0
GO_ONLY=0
ALL_DEPLOY=0
INIT_MODE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --contracts-only)
            CONTRACTS_ONLY=1
            shift
            ;;
        --go-only)
            GO_ONLY=1
            shift
            ;;
        --all)
            ALL_DEPLOY=1
            shift
            ;;
        --init)
            INIT_MODE=1
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

if [ $CONTRACTS_ONLY -eq 0 ] && [ $GO_ONLY -eq 0 ] && [ $INIT_MODE -eq 0 ]; then
    ALL_DEPLOY=1
fi

if [ $INIT_MODE -eq 1 ]; then
    echo -e "${BLUE}[INIT]${NC} Initializing new deployment..."

    if [ -f "config.json" ]; then
        echo -e "${YELLOW}[WARN] config.json already exists${NC}"
        read -p "Overwrite? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    cat > config.json << 'EOF'
{
  "serverPort": "8080",
  "networks": [
    {
      "name": "ethereum",
      "type": "evm",
      "networkId": 1,
      "factoryAddress": "0x...",
      "rpcUrls": ["https://eth.llamarpc.com"]
    },
    {
      "name": "polygon",
      "type": "evm",
      "networkId": 137,
      "factoryAddress": "0x...",
      "rpcUrls": ["https://polygon-rpc.com"]
    },
    {
      "name": "bsc",
      "type": "evm",
      "networkId": 56,
      "factoryAddress": "0x...",
      "rpcUrls": ["https://bsc-dataseed.binance.org"]
    },
    {
      "name": "base",
      "type": "evm",
      "networkId": 8453,
      "factoryAddress": "0x...",
      "rpcUrls": ["https://mainnet.base.org"]
    },
    {
      "name": "tron",
      "type": "tron",
      "networkId": 728126428,
      "factoryAddress": "T...",
      "tronGridUrl": "https://api.trongrid.io"
    },
    {
      "name": "solana",
      "type": "solana",
      "programId": "...",
      "cluster": "mainnet",
      "rpcUrls": ["https://api.mainnet-beta.solana.com"]
    }
  ],
  "dbMaxOpenConns": 100,
  "webhookWorkerPoolSize": 10,
  "webhookJobQueueSize": 100,
  "webhookMaxRetries": 5,
  "webhookTimeout": 10
}
EOF

    cat > .env.example << 'EOF'
# Neo B2-Plus Environment Configuration

# Database
DATABASE_URL=postgresql://user:password@localhost:5432/neob2plus

# Security (Generate with: openssl rand -hex 32)
ADMIN_API_KEY=your_admin_api_key_here
WEBHOOK_SECRET=your_webhook_secret_here

# Authorizer (Deployer) Private Key
AUTHORIZER_PRIVATE_KEY=0x...

# Contract Deployment Keys
DEPLOYER_PRIVATE_KEY=0x...
TRON_PRIVATE_KEY=your_tron_private_key

# RPC URLs (Optional - fallbacks if not in config.json)
ETHEREUM_RPC=https://eth.llamarpc.com
POLYGON_RPC=https://polygon-rpc.com
BSC_RPC=https://bsc-dataseed.binance.org
BASE_RPC=https://mainnet.base.org

# Etherscan (for contract verification)
ETHERSCAN_API_KEY=your_etherscan_api_key

# Solana
SOLANA_CLUSTER=mainnet
EOF

    cat > scripts/deployments.json << 'EOF'
{
  "version": "1.0.0",
  "networkType": "mainnet",
  "evm": [],
  "tron": null,
  "solana": null
}
EOF

    echo -e "${GREEN}[DONE]${NC} Created config.json, .env.example, scripts/deployments.json"
    echo ""
    echo "Next steps:"
    echo "  1. cp .env.example .env && edit .env"
    echo "  2. bash scripts/deploy_full.sh"
    echo "  3. Update config.json with deployed addresses"
    echo "  4. $0 --all"
    exit 0
fi

if [ $CONTRACTS_ONLY -eq 1 ]; then
    echo -e "${BLUE}[STEP]${NC} Deploying smart contracts..."
    bash scripts/deploy_full.sh
    echo ""
    echo -e "${GREEN}[DONE]${NC} Contract deployment complete"
    exit 0
fi

if [ $GO_ONLY -eq 1 ]; then
    echo -e "${BLUE}[STEP]${NC} Building Go server..."
else
    echo -e "${YELLOW}[1/3]${NC} Deploying contracts..."
    bash scripts/deploy_full.sh
fi

echo -e "${YELLOW}[2/3]${NC} Building Go application..."
echo "------------------------------------------"

if ! command -v go &> /dev/null; then
    echo -e "${RED}[ERROR] Go not found. Install Go 1.21+${NC}"
    exit 1
fi

GO_VERSION=$(go version | grep -oP 'go\K[0-9]+\.[0-9]+')
echo -e "${BLUE}[INFO]${NC} Go version: $GO_VERSION"

mkdir -p bin

echo -e "${YELLOW}[BUILD]${NC} Compiling for linux/amd64..."
GOOS=linux GOARCH=amd64 go build -o bin/gateway ./cmd/server

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[PASS]${NC} Linux binary built"
else
    echo -e "${RED}[FAIL]${NC} Build failed"
    exit 1
fi

echo -e "${YELLOW}[3/3]${NC} Verifying build..."
echo "------------------------------------------"

if [ -f "bin/gateway" ]; then
    BINARY_SIZE=$(du -h bin/gateway 2>/dev/null | cut -f1 || echo "unknown")
    echo -e "${GREEN}[PASS]${NC} Binary ready: bin/gateway (${BINARY_SIZE})"
else
    echo -e "${RED}[FAIL]${NC} Binary not found"
    exit 1
fi

if [ -f "config.json" ]; then
    echo -e "${GREEN}[PASS]${NC} config.json found"
else
    echo -e "${YELLOW}[WARN]${NC} config.json not found"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "  Build Complete!"
echo "==========================================${NC}"
echo ""
echo "Start gateway:"
echo "  ./bin/gateway"
echo ""
echo "Or with environment:"
echo "  DATABASE_URL=postgresql://... ./bin/gateway"
echo ""
