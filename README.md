# 🌐 Domain Name NFT Registry

> Decentralized domain name system built on Stacks blockchain

## 🎯 Overview

The Domain Name NFT Registry enables users to:
- 🔒 Register unique .stx domain names as NFTs
- 🔄 Map domains to STX/BTC addresses
- 💫 Transfer domain ownership
- ⏰ Renew domain registrations
- 🔍 Resolve domain names to addresses

## 📋 Features

- Minimum domain length: 3 characters
- Registration period: ~52,560 blocks (~365 days)
- Registration price: 100 STX
- Two-step registration process (preorder + register) to prevent front-running

## 🚀 Usage

### Register a Domain

1. Preorder your domain:
```bash
stx call preorder-name [hash] [amount]
```

2. Complete registration:
```bash
stx call register-name [name] [salt]
```

### Manage Your Domain

Set resolver addresses:
```bash
stx call set-name-resolver [name] [btc-address] [stx-address]
```

Transfer ownership:
```bash
stx call transfer-name [name] [new-owner]
```

Renew registration:
```bash
stx call renew-name [name]
```

## 🔍 Query Functions

- `get-owner`: Get domain owner
- `get-expiration`: Check domain expiration
- `resolve-name`: Lookup associated addresses
- `get-last-token-id`: Get latest minted token ID

## ⚖️ Governance

Contract includes basic DAO functionality for future governance implementation.
```
