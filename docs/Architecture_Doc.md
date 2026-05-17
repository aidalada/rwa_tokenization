# Architecture & Design Document

**Project:** RWA Tokenization Platform (Option C)
**Team:** [Yerulan, Yerassyl, Zharkynai]
**Author (Lead Smart Contract & Architecture):** Yerulan

## 1. System Context & Container Diagram (C4 Level 1 & 2)

This section outlines the high-level architecture of our RWA protocol and the interactions between core contracts, external dependencies, and actors.

```mermaid
graph TD
    User([User/Investor]) -->|Calls| Proxy(AssetManager Proxy)
    Admin([Protocol Admin]) -->|Upgrades| Proxy
    Admin -->|Deploys tokens| Factory(RWA Factory)
    
    Proxy -->|Delegates logic| Impl(AssetManagerV1 Impl)
    Impl -->|Checks KYC| KYC(KYCPassport ERC721)
    Factory -->|CREATE2| Token(RWAToken ERC20)
    
    classDef contract fill:#f9f,stroke:#333,stroke-width:2px;
    class Proxy,Impl,KYC,Factory,Token contract;
```

## 2. Sequence Diagrams

Below are the sequence diagrams illustrating the critical user flows within the protocol.

### 2.1 RWA Token Deployment via CREATE2

The `RWAFactory` utilizes the `CREATE2` opcode to ensure deterministic deployment of asset tokens, allowing off-chain clients to predict the address before spending gas.

```mermaid
sequenceDiagram
    actor Admin
    participant Factory as RWAFactory
    participant Token as RWAToken

    Admin->>Factory: predictTokenAddress(salt)
    Factory-->>Admin: returns predictedAddress
    
    Admin->>Factory: deployWithCreate2(salt)
    Factory->>Token: new RWAToken{salt}()
    Token-->>Factory: token deployed
    Factory->>Factory: emit TokenCreated(address)
    Factory-->>Admin: returns actualAddress
```


### 2.2 Secure Logic Upgrade (UUPS V1 to V2)

The protocol uses the UUPS (Universal Upgradeable Proxy Standard). The upgrade logic is secured by the `UPGRADER_ROLE`.

```mermaid
sequenceDiagram
    actor Admin
    participant Proxy as ERC1967Proxy
    participant V1 as AssetManagerV1 (Impl)
    participant V2 as AssetManagerV2 (Impl)

    Admin->>V2: deploy AssetManagerV2()
    V2-->>Admin: returns V2 address
    
    Admin->>Proxy: upgradeToAndCall(V2 address, "")
    Proxy->>V1: delegatecall _authorizeUpgrade()
    V1-->>Proxy: success (checks UPGRADER_ROLE)
    Proxy->>Proxy: update implementation slot to V2
    Proxy-->>Admin: upgrade successful
```


(Note: The third sequence diagram for AMM Swaps / DAO Voting will be added by Team Member 2/3).

## 3. Data Model & Storage Layout

To ensure safe upgradeability, we strictly monitor the storage layout. Below is the proof from Foundry (`forge inspect`) demonstrating that upgrading from `AssetManagerV1` to `AssetManagerV2` does not cause storage collisions.

| Name        | Type    | Slot | Offset | Bytes | Contract                             |
|=============|=========|======|========|=======|======================================|
| rwaToken    | address | 0    | 0      | 20    | src/AssetManagerV2.sol:AssetManagerV2|
| kycPassport | address | 1    | 0      | 20    | src/AssetManagerV2.sol:AssetManagerV2|
| platformFee | uint256 | 2    | 0      | 32    | src/AssetManagerV2.sol:AssetManagerV2|

_Conclusion: `platformFee` is safely appended to Slot 2, preserving Slots 0 and 1._

## 4. Trust Assumptions & Access Control

The protocol operates under the following trust assumptions and role distributions:

- **DEFAULT_ADMIN_ROLE:** The highest privilege. Initially held by the deployer, ultimately transferred to the DAO Timelock. Can grant or revoke any role.
    
- **UPGRADER_ROLE:** Authorized to call `upgradeToAndCall` on the UUPS proxy. If compromised, a malicious implementation could drain the protocol.
    
- **PAUSER_ROLE:** An emergency role (Circuit Breaker) capable of halting token transfers via `pause()`.
    
- **KYC_ISSUER_ROLE:** Authorized to mint and revoke Soulbound KYC Passports.
    
- **Centralization Risks:** Before the DAO transition, the protocol relies on a multisig/admin not acting maliciously. Post-transition, trust is shifted to the token holders.

## 5. Architecture Decision Records (ADRs)

#### ADR 1: Choice of Proxy Pattern

- **Context:** We needed an upgradeable architecture for the Asset Manager.
    
- **Options:** Transparent Proxy vs. UUPS (ERC1967).
    
- **Decision:** UUPS was chosen.
    
- **Consequences:** Cheaper deployment costs. However, it requires extreme caution: if an implementation is deployed without `_authorizeUpgrade`, the proxy becomes permanently "bricked".
    

#### ADR 2: Factory Deployment Method

- **Context:** Deploying new RWA tokens efficiently.
    
- **Options:** Standard `CREATE` vs. `CREATE2`.
    
- **Decision:** We implemented both, but prioritize `CREATE2` for production.
    
- **Consequences:** Allows the frontend to accurately predict the token contract address before deployment, improving UX.
    

#### ADR 3: KYC Implementation

- **Context:** Complying with real-world asset regulations (Role-gated minting).
    
- **Options:** Whitelist mapping in ERC20 vs. Separate ERC721 NFT.
    
- **Decision:** We chose a Soulbound ERC721 (Non-transferable NFT).
    
- **Consequences:** Makes the KYC status composable (other DApps can check the NFT balance) and keeps the ERC20 token logic cleaner.


# 🏗️ Architecture Document: RWA Tokenization Platform

## 1. Executive Summary
This document outlines the architectural design, component interactions, storage layouts, and design decisions for the RWA Tokenization Platform. The system is designed to securely tokenize Real World Assets (RWA), provide liquidity via an automated market maker (AMM), and offer yield generation through an ERC-4626 Vault, all governed by a decentralized DAO.

---

## 2. System Context (C4 Level 1)
The Context diagram illustrates the high-level interactions between the users, our platform, and external systems (Chainlink Oracles).

```mermaid
graph TD
    User([Platform User / Investor])
    Admin([DAO / Token Holders])
    
    subgraph RWA Protocol
        App[RWA Smart Contract Protocol]
    end
    
    Oracle[Chainlink Data Feeds]
    L2[L2 Blockchain / Arbitrum Sepolia]

    User -->|Deposits, Swaps, Votes| App
    Admin -->|Proposes Upgrades, Changes Params| App
    App -->|Reads Price & Reserves| Oracle
    App -->|Deployed on| L2
```


## 3. Container & Component Diagram (C4 Level 2)
This diagram details the internal smart contract architecture, showing how the Factory deploys components, how the UUPS Proxy routes logic, and how the DeFi primitives interact.

```mermaid
graph TD
    subgraph Core
        Factory[RWAFactory <br/> CREATE2]
        KYC[KYCPassport <br/> ERC-721 Soulbound]
        Token[RWAToken <br/> ERC20Votes/Permit]
    end

    subgraph Upgradability
        Proxy[AssetManager Proxy <br/> ERC1967]
        ImplV1[AssetManager V1]
        ImplV2[AssetManager V2]
    end

    subgraph DeFi Primitives
        AMM[RWAAMM Pool <br/> x*y=k]
        Vault[RWAVault <br/> ERC-4626]
    end

    subgraph Oracles
        OracleAdapter[RWAOracle Adapter]
        Chainlink[Chainlink Aggregators]
    end

    Factory -.->|Deploys| Token
    Factory -.->|Deploys| AMM
    Factory -.->|Deploys| Vault
    
    Proxy -->|Delegates Calls| ImplV1
    Proxy -.->|Upgrades To| ImplV2
    
    AMM -->|Reads Price| OracleAdapter
    OracleAdapter -->|Fetches Data| Chainlink
```

## 4. Sequence Diagrams (Critical User Flows)
Below are the sequence diagrams for the three most critical protocol operations.

### Flow 1: Token Swap in AMM (x * y = k)
```mermaid
sequenceDiagram
    actor User
    participant AMM as RWAAMM
    participant Token0 as USDC
    participant Token1 as RWAToken

    User->>Token0: approve(AMM, amountIn)
    User->>AMM: swap(Token0, amountIn)
    activate AMM
    AMM->>Token0: safeTransferFrom(User, AMM, amountIn)
    note right of AMM: Calculate out = (reserveOut * amountIn * 997) / (reserveIn * 1000 + amountIn * 997)
    AMM->>Token1: safeTransfer(User, amountOut)
    AMM-->>User: emit Swap()
    deactivate AMM
```


### Flow 2: Yield Vault Deposit (ERC-4626)
```mermaid
sequenceDiagram
    actor User
    participant Vault as RWAVault
    participant Asset as RWAToken

    User->>Asset: approve(Vault, assets)
    User->>Vault: deposit(assets, User)
    activate Vault
    note right of Vault: Calculate shares incorporating _decimalsOffset() to prevent inflation attack
    Vault->>Asset: safeTransferFrom(User, Vault, assets)
    Vault->>Vault: _mint(User, shares)
    Vault-->>User: return shares
    deactivate Vault
```

### Flow 3: DAO Upgrade Flow (UUPS Proxy)
```mermaid
sequenceDiagram
    actor Proposer
    participant Gov as Governor
    participant Time as Timelock
    participant Proxy as AssetManagerProxy

    Proposer->>Gov: propose(upgradeToAndCall(V2))
    note over Gov: 1 week voting period
    Gov->>Gov: State changes to Succeeded
    Proposer->>Gov: queue(proposal)
    Gov->>Time: schedule operation
    note over Time: 2 days mandatory delay
    Proposer->>Gov: execute(proposal)
    Gov->>Time: execute
    Time->>Proxy: upgradeToAndCall(V2)
```


## 5. Storage Layout & Data Model
Managing storage correctly is critical for the `AssetManager` UUPS Proxy to prevent storage collisions during V1 -> V2 upgrades.

|**Slot**|**Type**|**Variable Name**|**Description**|
|---|---|---|---|
|`0`|`address`|`owner`|Admin address (Inherited from OwnableUpgradeable)|
|`1`|`uint256`|`totalAssetsManaged`|Tracks total RWA volume|
|`2`|`mapping`|`whitelistedIssuers`|KYC'd asset issuers|

**AssetManagerV2 Storage (Upgrade Path):**

|**Slot**|**Type**|**Variable Name**|**Description**|
|---|---|---|---|
|`0`|`address`|`owner`|Must remain at Slot 0|
|`1`|`uint256`|`totalAssetsManaged`|Must remain at Slot 1|
|`2`|`mapping`|`whitelistedIssuers`|Must remain at Slot 2|
|`3`|`uint256`|`platformFee`|**NEW IN V2:** Appended to avoid collisions|
_Safety Check:_ No variables were deleted or reordered. New state variables are strictly appended to the end of the layout.

## 6. Trust Assumptions & Role Management
The protocol relies on several trust assumptions and strictly defined roles to minimize centralization vectors.

- **Upgrades (`UPGRADER_ROLE`):** Held exclusively by the `TimelockController`. No single EOA (Externally Owned Account) can upgrade the proxy.
    
- **Minting (`MINTER_ROLE`):** Held by the Factory and the DAO. Users can only mint if they have passed the KYC process and hold the `KYCPassport` NFT.
    
- **Oracle Integrity:** We assume Chainlink node operators behave honestly. However, we mitigate stale data by hardcoding a `1 hours` timeout.
    
- **Multisig Compromise:** If the DAO governance is bypassed, the 2-day Timelock delay provides a "circuit breaker" window for users to withdraw their liquidity (`removeLiquidity`) and exit the Vault before a malicious upgrade executes.


## 7. Architecture Decision Records (ADRs)
### ADR-01: Upgradability Pattern

- **Context:** The core `AssetManager` requires future updates.
    
- **Decision:** Implement **UUPS (Universal Upgradeable Proxy Standard)** instead of Transparent Proxy.
    
- **Consequences:** Gas costs for deployment and user interactions are cheaper. The upgrade logic resides in the implementation, requiring careful attention to avoid bricking the contract (ensured by OpenZeppelin's `_authorizeUpgrade`).
    

### ADR-02: Inflation Attack Mitigation in Yield Vault

- **Context:** ERC-4626 Vaults are susceptible to the "first depositor" (donation) attack, where an attacker manipulates the share price by sending raw assets to the contract.
    
- **Decision:** Override `_decimalsOffset()` to return `3`.
    
- **Consequences:** The vault creates 10^3 virtual assets and shares. It mathematically forces attackers to spend an exponentially larger, economically unviable amount of capital to execute the donation attack.
    

### ADR-03: AMM Math Optimization

- **Context:** Calculating the initial liquidity shares requires a square root function `sqrt(x * y)`. Pure Solidity implementations are gas-intensive.
    
- **Decision:** Implement the Babylonian square root method using **Inline Yul Assembly**.
    
- **Consequences:** Readability is slightly reduced, but gas consumption during pool initialization is drastically optimized.



