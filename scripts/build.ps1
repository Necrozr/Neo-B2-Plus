# scripts/build.ps1
# Deployment script for Neo B2-Plus Gateway using Garble for anti-piracy obfuscation

Write-Host "Iniciando processo de build seguro do Neo B2-Plus..." -ForegroundColor Cyan

# 1. Verifica se Garble está instalado, senão instala
$garbleExists = Get-Command garble -ErrorAction SilentlyContinue
if (-not $garbleExists) {
    Write-Host "Garble (ofuscador Go) não encontrado. Instalando..." -ForegroundColor Yellow
    go install mvdan.cc/garble@latest
}

Write-Host "Limpando dependências (go mod tidy)..."
go mod tidy

# 2. Compilação Ofuscada
# -literals: Ofusca strings (como o endereço do contrato e chaves públicas)
# -ldflags="-w -s": Remove tabelas de símbolos e DWARF debugging info para dificultar o reverse engineering
Write-Host "Compilando binário ofuscado com garble..." -ForegroundColor Yellow
garble -literals build -ldflags="-w -s" -o bin/neo-b2-plus.exe ./cmd/server

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Build concluído com sucesso: bin/neo-b2-plus.exe" -ForegroundColor Green
    Write-Host "Lojas / Usuários mal-intencionados não poderão explorar o binário para bypassar o Smart Contract." -ForegroundColor Green
} else {
    Write-Host "❌ Falha no build." -ForegroundColor Red
}
