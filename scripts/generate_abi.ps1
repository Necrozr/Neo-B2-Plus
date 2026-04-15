# scripts/generate_abi.ps1
# Script para extração do ABI via Solc/Hardhat e Geração das Binds no Go-Ethereum

Write-Host "Recompilando Contratos (Splitter e Factory)..." -ForegroundColor Cyan
npx hardhat compile

Write-Host "Criando pastas de contratos nativos..."
mkdir -p core/contracts/bindings

Write-Host "Gerando Código Nativo Go (pkg) usando ABIgen..." -ForegroundColor Yellow
# O abigen converte o ABI+Bin gerado pelo Hardhat numa classe golang tipada!
abigen --abi=./artifacts/contracts/SplitterFactory.sol/SplitterFactory.json --pkg=bindings --type=SplitterFactory --out=./core/contracts/bindings/splitter_factory.go
abigen --abi=./artifacts/contracts/PaymentSplitter.sol/PaymentSplitter.json --pkg=bindings --type=PaymentSplitter --out=./core/contracts/bindings/payment_splitter.go

Write-Host "✅ Módulos de Smart Contracts integrados. Você já pode chamá-los no backend via bindings.NewSplitterFactory()" -ForegroundColor Green
