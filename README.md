# Neo B2-Plus | Decentralized Multi-Chain Payment Gateway

<p align="center">
  <img src="https://img.shields.io/badge/Go-1.25-blue?style=flat&logo=go" alt="Go Version">
  <img src="https://img.shields.io/badge/Solidity-0.8.x-darkblue?style=flat&logo=solidity" alt="Solidity">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat">
  <img src="https://img.shields.io/badge/Status-Production%20Ready-brightgreen?style=flat">
</p>

---

## Overview

Neo B2-Plus is a **high-performance, fully decentralized multi-chain payment gateway** that enables merchants to accept cryptocurrency payments across multiple blockchain families while maintaining self-custody of funds.

### Key Capabilities

| Feature | Description |
|---------|-------------|
| **Multi-Chain Support** | EVM (Polygon, BSC, Arbitrum, Optimism, Base, Ethereum), Solana, Tron |
| **Self-Custody** | Merchants control their funds directly via EIP-1167 clones |
| **0.1% Fee** | Fixed infrastructure fee split on-chain |
| **EIP-712 Signatures** | Secure off-chain payment authorization |
| **Real-time Webhooks** | Instant payment notifications with HMAC verification |
| **High Availability** | Circuit breakers, RPC failover, rate limiting |

---

## Quick Start

### 1. Initialize Configuration

The binary includes an initialization routine to generate template files:

```bash
# Linux
chmod +x neob2plus-linux-amd64
./neob2plus-linux-amd64 --init

# Windows
./neob2plus-windows-amd64.exe --init
```
Em Contrução
