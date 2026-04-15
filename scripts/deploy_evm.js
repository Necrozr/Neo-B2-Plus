const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

const DEPLOYMENTS_FILE = path.join(__dirname, "deployments.json");

const networks = [
  { name: "ethereum", chainId: 1, rpc: process.env.ETHEREUM_RPC || "https://eth.llamarpc.com" },
  { name: "polygon", chainId: 137, rpc: process.env.POLYGON_RPC || "https://polygon-rpc.com" },
  { name: "bsc", chainId: 56, rpc: process.env.BSC_RPC || "https://bsc-dataseed.binance.org" },
  { name: "base", chainId: 8453, rpc: process.env.BASE_RPC || "https://mainnet.base.org" },
];

async function deploy(network) {
  console.log(`\n${"=".repeat(50)}`);
  console.log(`Deploying to ${network.name.toUpperCase()} (chainId: ${network.chainId})`);
  console.log(`${"=".repeat(50)}`);

  const provider = new ethers.JsonRpcProvider(network.rpc);
  const wallet = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, provider);

  console.log(`Deployer: ${wallet.address}`);

  const balance = await provider.getBalance(wallet.address);
  console.log(`Balance: ${ethers.formatEther(balance)} ETH/BNB/MATIC`);

  console.log(`\nDeploying SplitterLogic (implementation)...`);
  const SplitterLogic = await ethers.getContractFactory("SplitterLogic", wallet);
  const splitterImpl = await SplitterLogic.deploy();
  await splitterImpl.waitForDeployment();
  const splitterImplAddress = await splitterImpl.getAddress();
  console.log(`SplitterLogic: ${splitterImplAddress}`);

  console.log(`\nDeploying MerchantFactory (with SplitterLogic)...`);
  const MerchantFactory = await ethers.getContractFactory("MerchantFactory", wallet);
  const factory = await MerchantFactory.deploy(wallet.address, splitterImplAddress);
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log(`MerchantFactory: ${factoryAddress}`);

  console.log(`\nFee: 0.1% (10 bps - hardcoded in SplitterLogic)`);

  const verification = await verifyContracts(network, splitterImplAddress, factoryAddress);
  if (!verification) {
    console.log(`Note: Verification skipped (need ETHERSCAN_API_KEY)`);
  }

  return {
    network: network.name,
    chainId: network.chainId,
    splitterLogic: splitterImplAddress,
    factory: factoryAddress,
    feeBps: 10,
    deployer: wallet.address,
    timestamp: new Date().toISOString(),
  };
}

async function verifyContracts(network, splitterImpl, factory) {
  if (!process.env.ETHERSCAN_API_KEY) return false;

  try {
    console.log(`\nVerifying contracts on ${network.name}...`);

    await hre.run("verify:verify", {
      address: splitterImpl,
      constructorArguments: [],
    });
    console.log(`SplitterLogic verified`);

    await hre.run("verify:verify", {
      address: factory,
      constructorArguments: [process.env.DEPLOYER_PRIVATE_KEY, splitterImpl],
    });
    console.log(`MerchantFactory verified`);

    return true;
  } catch (e) {
    console.log(`Verification failed: ${e.message}`);
    return false;
  }
}

async function main() {
  if (!process.env.DEPLOYER_PRIVATE_KEY) {
    console.error("Error: DEPLOYER_PRIVATE_KEY not set in .env");
    console.log("Example .env:");
    console.log("  DEPLOYER_PRIVATE_KEY=0x...");
    console.log("  ETHEREUM_RPC=https://eth.llamarpc.com");
    console.log("  POLYGON_RPC=https://polygon-rpc.com");
    console.log("  BSC_RPC=https://bsc-dataseed.binance.org");
    console.log("  BASE_RPC=https://mainnet.base.org");
    console.log("  ETHERSCAN_API_KEY=your_api_key (optional)");
    process.exit(1);
  }

  console.log("=".repeat(50));
  console.log("  Neo B2-Plus - EVM Mainnet Deploy");
  console.log("=".repeat(50));

  const results = [];

  for (const network of networks) {
    try {
      const result = await deploy(network);
      results.push(result);
      console.log(`\n[PASS] ${network.name} deployed successfully`);
    } catch (error) {
      console.error(`\n[FAIL] ${network.name}:`, error.message);
    }
  }

  let existing = {};
  if (fs.existsSync(DEPLOYMENTS_FILE)) {
    try {
      existing = JSON.parse(fs.readFileSync(DEPLOYMENTS_FILE, "utf8"));
    } catch (e) {
      console.log("Creating new deployments file");
    }
  }

  existing.evm = results;
  existing.version = "1.0.0";
  existing.updatedAt = new Date().toISOString();

  fs.writeFileSync(DEPLOYMENTS_FILE, JSON.stringify(existing, null, 2));

  console.log(`\n${"=".repeat(50)}`);
  console.log("Deployment Summary");
  console.log(`${"=".repeat(50)}`);
  console.log(`Saved to: ${DEPLOYMENTS_FILE}\n`);

  console.log("Config for config.json:");
  console.log(JSON.stringify(results.map((r) => ({
    name: r.network,
    networkId: r.chainId,
    factoryAddress: r.factory,
    rpcUrls: [networks.find((n) => n.name === r.network).rpc],
  })), null, 2));
}

main().catch((error) => {
  console.error("Deployment failed:", error);
  process.exit(1);
});
