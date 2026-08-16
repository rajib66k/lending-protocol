# 🏦 Lending Protocol

<p align="center">
  <b>A decentralized lending protocol built with Solidity and Foundry.</b>
</p>

<p align="center">
  Supply liquidity, borrow assets, manage debt, and interact with an on-chain lending pool powered by interest-rate and oracle logic.
</p>

<p align="center">

![Solidity](https://img.shields.io/badge/Solidity-363636?style=for-the-badge\&logo=solidity\&logoColor=white)

![Foundry](https://img.shields.io/badge/Foundry-000000?style=for-the-badge\&logo=ethereum\&logoColor=white)

![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-Contracts-4E5EE4?style=for-the-badge\&logo=openzeppelin\&logoColor=white)

![Ethereum](https://img.shields.io/badge/Ethereum-EVM-3C3C3D?style=for-the-badge\&logo=ethereum\&logoColor=white)

![DeFi](https://img.shields.io/badge/DeFi-Lending-00A3FF?style=for-the-badge)

</p>

---

## 📖 About

**Lending Protocol** is a decentralized finance project implemented in **Solidity** using **Foundry**.

The protocol is designed around a lending-pool architecture where users can interact with supplied liquidity and debt positions through dedicated smart contracts.

The project separates core responsibilities across:

* 🏦 Lending pool management
* 💧 Liquidity accounting
* 💳 Debt accounting
* 📈 Interest-rate calculation
* 🔮 Oracle handling
* 🧮 Reserve accounting
* 🛡️ Validation and risk checks
* 👤 User configuration
* 🏛️ Treasury management

The source code is organized into dedicated modules rather than placing the entire protocol inside a single contract.

---

# ✨ Features

### 💧 Liquidity Provision

Users can supply assets to the lending pool and receive a representation of their liquidity position through the protocol's `LiquidityToken` contract.

```text
User
 │
 │ Supply Assets
 ▼
┌─────────────────┐
│      Pool       │
└────────┬────────┘
         │
         ▼
  Liquidity Token
```

The protocol separates liquidity-token functionality from the main pool logic.

---

### 💳 Borrowing & Debt Accounting

The protocol contains a dedicated `DebtToken` contract for tracking borrower debt.

```text
User
 │
 │ Borrow
 ▼
┌─────────────────┐
│      Pool       │
└────────┬────────┘
         │
         ▼
    Debt Token
```

This allows debt accounting to remain separate from liquidity accounting.

---

### 📈 Interest Rate Model

Interest-rate calculations are isolated inside the `InterestRateModel` library.

This allows the protocol to calculate borrowing/lending rates independently from the main pool implementation.

---

### 🔮 Oracle Integration

The project includes an `OracleLib` module for oracle-related functionality.

Oracle logic can be used by the protocol to obtain external market information required for lending and risk calculations.

---

### 🧮 Reserve Management

Reserve accounting is separated into `ReserveLogic`.

This keeps reserve-related calculations and state transitions modular instead of embedding all accounting logic inside the main pool contract.

---

### 🛡️ Validation Logic

The protocol contains a dedicated `ValidationLogic` library for validating protocol operations.

This provides a separate layer for checking whether requested actions satisfy the protocol's requirements before state-changing operations are executed.

---

### 🏛️ Treasury

Protocol treasury functionality is implemented through a dedicated `Treasury` contract.

This provides a separate component for handling protocol-owned funds and treasury-related operations.

---

# 🏗️ Architecture

The protocol follows a modular architecture:

```text
                         ┌─────────────────────┐
                         │        User         │
                         └──────────┬──────────┘
                                    │
                                    ▼
                         ┌─────────────────────┐
                         │        Pool         │
                         │   Core Protocol     │
                         └──────┬──────┬───────┘
                                │      │
                    ┌───────────┘      └────────────┐
                    ▼                               ▼
          ┌─────────────────┐             ┌─────────────────┐
          │ LiquidityToken  │             │    DebtToken    │
          │   LP Position   │             │  Debt Position  │
          └─────────────────┘             └─────────────────┘

                                │
              ┌─────────────────┼──────────────────┐
              │                 │                  │
              ▼                 ▼                  ▼
      ┌──────────────┐  ┌───────────────┐  ┌───────────────┐
      │ InterestRate │  │  ReserveLogic │  │ Validation    │
      │    Model     │  │               │  │    Logic      │
      └──────────────┘  └───────────────┘  └───────────────┘
              │                 │                  │
              └─────────────────┼──────────────────┘
                                │
                                ▼
                         ┌───────────────┐
                         │   OracleLib   │
                         └───────────────┘

                                │
                                ▼
                         ┌───────────────┐
                         │    Treasury   │
                         └───────────────┘
```

The repository's `src` directory is explicitly divided into `configuration`, `interfaces`, `libraries`, `protocol`, `treasury`, and `types`.

---

# 📂 Project Structure

```text
src/
│
├── configuration/
│   └── UserConfiguration.sol
│
├── interfaces/
│   ├── IDebtToken.sol
│   ├── ILiquidityToken.sol
│   └── IPool.sol
│
├── libraries/
│   ├── InterestRateModel.sol
│   ├── Math.sol
│   ├── OracleLib.sol
│   ├── ReserveLogic.sol
│   └── ValidationLogic.sol
│
├── protocol/
│   ├── DebtToken.sol
│   ├── LiquidityToken.sol
│   └── Pool.sol
│
├── treasury/
│   └── Treasury.sol
│
└── types/
    └── ...
```

This structure is based on the current repository source tree.

---

# 🧩 Core Components

## `Pool.sol`

The `Pool` contract is the central component of the protocol.

It coordinates the main lending-pool operations and connects the liquidity, debt, validation, reserve, and configuration components.

```text
                 ┌───────────────┐
                 │     Pool      │
                 └───────┬───────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
 LiquidityToken      DebtToken       Validation
        │                │                │
        └────────────────┼────────────────┘
                         │
                         ▼
                  Reserve / Rates
```

The current `Pool.sol` implementation is a substantial core contract with more than 650 lines of Solidity source.

---

## `LiquidityToken.sol`

Represents liquidity positions associated with supplied assets.

```text
Supply
  │
  ▼
Pool
  │
  ▼
LiquidityToken
```

The repository also exposes an `ILiquidityToken` interface for this component.

---

## `DebtToken.sol`

Tracks debt positions created through borrowing.

```text
Borrow
  │
  ▼
Pool
  │
  ▼
DebtToken
```

The contract is paired with `IDebtToken` to provide a clear interface between the debt-accounting layer and the main protocol.

---

## `InterestRateModel.sol`

Contains the protocol's interest-rate calculations.

Keeping the interest-rate model in a separate library makes the architecture easier to reason about and allows rate calculations to be reused by the protocol.

---

## `OracleLib.sol`

Provides oracle-related functionality used by the lending system.

Oracle data is an important part of lending protocols because asset valuations can influence borrowing and risk calculations.

---

## `ReserveLogic.sol`

Handles reserve-related accounting logic.

Separating reserve calculations into a library helps keep the core `Pool` implementation more modular.

---

## `ValidationLogic.sol`

Provides validation functionality for protocol operations.

The purpose of this layer is to keep protocol checks separated from the core state-management logic.

---

## `UserConfiguration.sol`

Contains user-level configuration functionality used by the protocol.

This provides a dedicated place for tracking configuration/state associated with user positions.

---

## `Treasury.sol`

Provides a dedicated treasury component for protocol funds and treasury-related operations.

This modular approach makes the protocol easier to extend and test.

---

# 🛠️ Tech Stack

### Smart Contracts

* **Solidity**
* **Ethereum / EVM**
* **OpenZeppelin**
* **Foundry**

### Development

* **Forge** — Build & testing
* **Anvil** — Local Ethereum node
* **Cast** — Contract interaction
* **Foundry Scripts** — Deployment and automation

The repository is structured as a Foundry project and includes `lib`, `script`, `src`, `test`, GitHub Actions, `foundry.toml`, and `foundry.lock`.

---

# 🚀 Getting Started

## Prerequisites

Install Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
```

Then:

```bash
foundryup
```

Verify:

```bash
forge --version
```

---

## 📥 Clone

```bash
git clone https://github.com/rajib66k/lending-protocol.git
```

```bash
cd lending-protocol
```

Install dependencies:

```bash
forge install
```

---

# 🔨 Build

Compile the contracts:

```bash
forge build
```

---

# 🧪 Test

Run the test suite:

```bash
forge test
```

For detailed traces:

```bash
forge test -vv
```

For maximum verbosity:

```bash
forge test -vvvv
```

---

# 🧹 Format

Format Solidity files:

```bash
forge fmt
```

---

# ⛓️ Local Development

Start a local Ethereum node:

```bash
anvil
```

Then use Foundry scripts to deploy and interact with the protocol.

---

# 🚀 Deployment

A typical Foundry deployment command:

```bash
forge script script/<YourScript>.s.sol:<ContractName> \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast
```

---

# 🧪 Testing Philosophy

A lending protocol requires careful testing around:

* Liquidity accounting
* Borrowing and repayment
* Debt growth
* Interest calculations
* Oracle behavior
* Reserve accounting
* User configuration
* Edge cases
* Access control
* Liquidation/risk scenarios

This repository includes a dedicated `test` directory alongside the protocol source.

---

# 🔐 Security

> ⚠️ **This project should be considered experimental and unaudited unless an independent audit has been completed.**

Before using the protocol with real assets, perform a comprehensive security review covering:

* Reentrancy
* Oracle manipulation
* Interest-rate edge cases
* Precision and rounding
* Insolvent positions
* Borrowing limits
* Reserve accounting
* Access control
* Token accounting
* Economic attacks
* Liquidation behavior
* Unexpected ERC-20 behavior

**Do not use unaudited contracts with real funds.**

---

# 🧠 What This Project Demonstrates

This project demonstrates practical implementation of several DeFi concepts:

```text
Solidity
   │
   ├── Lending Pools
   │
   ├── Liquidity Accounting
   │
   ├── Debt Accounting
   │
   ├── Interest Rate Models
   │
   ├── Oracle Integration
   │
   ├── Reserve Management
   │
   ├── User Configuration
   │
   ├── Treasury Management
   │
   └── Modular Smart Contract Architecture
```

# ⭐ Support

If you find this project useful or interesting, consider giving it a ⭐.

Feedback, suggestions, and contributions are welcome.

---

## 📜 License

This project is intended for educational and development purposes. Please review the repository's license and source code before reuse.
