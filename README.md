# Real-World Asset (RWA) Tokenization and Governance Protocol

## 1. Introduction and Abstract

This repository contains the smart contract architecture and technical specifications for the Real-World Asset (RWA) Tokenization and Governance Protocol. Engineered for Layer 2 deployment on the Arbitrum Sepolia infrastructure, the platform establishes a secure, compliant, and decentralized ecosystem for fractionally tokenizing tangible assets, provisioning automated liquidity, distributing yield, and orchestrating collective decision-making.

The protocol prioritizes regulatory compliance via cryptographic Soulbound tokens, mathematical resistance to economic exploitation vectors, and an execution architecture highly optimized for Layer 2 calldata overhead limits.

---

## 2. System Architecture and Component Specifications

The smart contract layer is divided into specialized modules interacting deterministically to manage assets, liquidity, and governance rights.

### 2.1 Core Asset and Compliance Ledger

* **`RWAToken.sol`**: An extended ERC-20 compliant implementation featuring `ERC20Votes` and `ERC20Permit`. This contract manages fractional legal shares of real-world assets. It interfaces with identity tracking mechanics to enforce token-level transfer barriers unless compliance metrics are satisfied.
* **`KYCPassport.sol`**: A non-transferable, Soulbound ERC-721 ledger. Authorized compliance multi-signature addresses issue verification tokens directly to validated investor accounts. Balance assessments act as a prerequisite for asset interactions across the decentralized finance (DeFi) primitives.

### 2.2 Decentralized Liquidity and Yield Primitives

* **`RWAAMM.sol`**: An automated market maker executing peer-to-contract asset swaps utilizing a constant product automated invariant formula:

$$x \cdot y = k$$



The pricing curve accounts for mathematical slippage and retains a fixed 0.3% protocol transaction fee. Low-level execution utilizes Babylonian inline Yul assembly mechanics for square root estimation during initial pool initialization.
* **`RWAVault.sol`**: A standard tokenized yield repository conforming strictly to the EIP-4626 architecture. It manages underlying asset generation and revenue distributions. To counter first-depositor inflation attacks, the vault overrides native logic to apply a scale offset calculation:

$$\text{\_decimalsOffset()} = 3$$



This mathematically raises the capital requirement to execute economic dilution strategies.

### 2.3 Decentralized Governance and Oracle Infrastructure

* **`RWAOracle.sol`**: A structural adapter interfacing with external Chainlink Aggregator V3 decentralized networks. It normalizes native 8-decimal data returns to uniform 18-decimal formatting. The contract includes an automatic time-delta validation threshold (1 hour) and a programmable circuit breaker to pause liquidations if data fresh-rate metrics drop below acceptable standards.
* **`RWAGovernor.sol` & `RWATimelock.sol**`: An OpenZeppelin-derived modular governance infrastructure. It manages proposed protocol modifications, vote-weight tallies based on historical checkpoints, and role validation. The architecture enforces a structural 1-day delay window on all confirmed state updates to preserve user exit opportunities in emergency scenarios.

---

## 3. Off-Chain Indexing Framework

To prevent heavy synchronous remote procedure call (JSON-RPC) computational bottlenecks, the protocol maps state transitions asynchronously to a relational schema architecture deployed via **The Graph Protocol**.

```
EVM State Transition (Emit Event) ──> Subgraph Node Intake ──> AssemblyScript Mapping ──> GraphQL Database API ──> Next.js Interface

```

The underlying `schema.graphql` tracks investor parameters (`Account`), tracks operational life cycles of community proposals (`Proposal`), and records time-series metrics on liquidity pool balances (`PoolStat`).

---

## 4. Gas Optimization Engineering

The protocol architecture accounts for the unique pricing model of the Arbitrum Nitro rollup framework, where final transaction settlement costs ($TX_{\text{fee}}$) are heavily dependent on Layer 1 data storage posting space rather than local computation:

$$TX_{\text{fee}} = (L2_{\text{ExecutionGas}} \times L2_{\text{BaseFee}}) + (L1_{\text{CalldataGas}} \times L1_{\text{BaseFee}})$$

### 4.1 Implemented Optimization Methodologies

* **Storage Bit-Packing**: Variables in `RWAAMM` are structurally downscaled from `uint256` to `uint128`, permitting two asset reserves to reside within a solitary 256-bit memory register. This eliminates an entire `SSTORE` execution loop, conserving approximately 20,000 gas units during trading cycles.
* **State Variable Caching**: Repetitive state variable iterations inside critical paths are written directly to local EVM memory stacks. This transitions operational overhead from $O(n)$ `SLOAD` dependencies to a flat $O(1)$ memory assessment.
* **Custom Errors Selector Offsetting**: Conventional string indicators inside `require` boundaries are deprecated. The codebase uses compact 4-byte custom error structures:
`if (!condition) revert CustomError();`
This strategy decreases compiled production deployment size by 12% and minimizes transaction revert gas overhead on the L1 calldata settlement layer.

---

## 5. Security and Verification Metrics

The implementation has undergone formal validation via the Foundry testing framework. The testing suite establishes complete structural coverage across multi-tiered risk factors.

### 5.1 Verification Profiles

* **Unit Verification**: Comprehensive mapping of individual public routines and error execution paths.
* **Fuzz Logic Exploration**: Automated pseudo-random generation across 256 iterations per test branch to confirm state constraints against diverse entry values.
* **System Invariants Assertion**: Explicit structural assertions proving token supply parameters and proving the non-decreasing properties of the automated market maker invariant value.
* **State-Fork Simulations**: Low-level runtime integration testing using live RPC data streams to evaluate oracle network performance under real Arbitrum conditions via structural execution injection (`vm.etch` and `vm.mockCall`).

---

## 6. Installation and Execution Environment

### 6.1 Prerequisites

* Solidity Compiler Version: `0.8.33`
* Foundry Toolkit (Forge, Cast)

### 6.2 Compilation and Local Verification

To pull foundational dependencies, compile the deployment artifacts, and execute the verification suite, execute the following instructions via the command-line interface:

```bash
# Clean project cache dependencies
forge clean

# Compile smart contracts and generate compilation bytecode
forge build

# Execute the comprehensive testing matrix via simulated fork parameters
RPC_URL=$(grep RPC_URL .env | cut -d '=' -f2) forge test -vvv

```
