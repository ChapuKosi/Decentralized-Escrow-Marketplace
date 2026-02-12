# Architecture Documentation

**Portfolio Project:** Smart Contract Architecture

This document outlines the architecture and design decisions for the Decentralized Escrow Marketplace smart contracts. This is a portfolio project focused on demonstrating smart contract development skills.

## Smart Contract Architecture

**Note:** This portfolio project focuses on smart contract implementation only. No frontend or web interface is included.

```
┌─────────────────────────────────────────────────────────────────┐
│                      SMART CONTRACT LAYER                       │
│                                                                 │
│  ┌─────────────────────┐        ┌──────────────────────────┐    │
│  │  EscrowFactory.sol  │◄──────►│ ArbitratorRegistry.sol   │    │
│  │                     │        │                          │    │
│  │ - createEscrow()    │        │ - registerArbitrator()   │    │
│  │ - trackEscrows()    │        │ - getRandomArbitrator()  │    │
│  │ - manageFees()      │        │ - recordResolution()     │    │
│  │ - pause/unpause()   │        │ - reputation tracking    │    │
│  └──────────┬──────────┘        └──────────────────────────┘    │
│             │                                                   │
│             │ creates & manages                                 │
│             ▼                                                   │
│  ┌─────────────────────────────────────────────┐                │
│  │         Individual Escrow Contracts         │                │
│  │                                             │                │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐   │                │
│  │  │ Escrow 1 │  │ Escrow 2 │  │ Escrow N │   │                │
│  │  │ (Deal A) │  │ (Deal B) │  │ (Deal Z) │   │                │
│  │  └──────────┘  └──────────┘  └──────────┘   │                │
│  └─────────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────────┘
```

## Escrow Lifecycle Flow

```
┌──────────┐
│  BUYER   │
└─────┬────┘
      │
      │ 1. createEscrow()
      │    + deposit funds
      ▼
┌─────────────────┐
│ FACTORY creates │──────► Individual Escrow Contract
│  Escrow.sol     │        - Funds locked
└─────────────────┘        - Deadline set
                           - State: CREATED
      │
      │ emits EscrowCreated event
      ▼
┌──────────┐                      ┌──────────┐
│  SELLER  │                      │  BUYER   │
└─────┬────┘                      └────┬─────┘
      │                                │
      │ 2. acceptEscrow()              │
      │    State: CREATED → ACCEPTED   │
      ▼                                │
 [Work Phase]                          │
      │                                │
      │ 3. markCompleted()             │
      │    (signals completion)        │
      ▼                                │
                                       │
      ┌──────────────────────────────┼─────────┐
      │                              │         │
      │ 4a. Happy Path               │ 4b. Dispute Path
      │                              │         │
      ▼                              ▼         │
  Buyer satisfied           Buyer/Seller       │
      │                     raises dispute     │
      │                              │         │
      │ releasePayment()             │         │
      │                              ▼         │
      │                     ┌─────────────┐    │
      │                     │ Arbitrator  │    │
      │                     │  Assigned   │    │
      │                     └──────┬──────┘    │
      │                            │           │
      │                            │           │
      │                     resolveDispute()   │
      │                            │           │
      ▼                            ▼           ▼
 State: COMPLETED          State: RESOLVED    State: CANCELLED
 Seller receives funds     Funds distributed  Buyer refunded
```

## State Machine Diagram

```
                  ┌─────────────────────────────┐
                  │       CREATED               │
                  │  - Escrow deployed          │
                  │  - Funds locked             │
                  └──┬────────────────────┬─────┘
                     │                    │
        acceptEscrow()│                   │cancelEscrow()
                     │                    │(buyer only)
                     ▼                    ▼
           ┌─────────────────┐     ┌─────────────┐
           │    ACCEPTED     │     │  CANCELLED  │
           │  - Work phase   │     │ - Refunded  │
           └────┬─────┬──────┘     └─────────────┘
                │     │
                │     │raiseDispute()
                │     │
releasePayment()│     ▼
                │  ┌──────────────────┐
                │  │    DISPUTED      │
                │  │ - Awaiting arb.  │
                │  └────────┬─────────┘
                │           │
                │           │resolveDispute()
                │           │
                ▼           ▼
           ┌─────────────────────┐
           │    COMPLETED/       │
           │     RESOLVED        │
           │  - Funds released   │
           └─────────────────────┘
```

## Dispute Resolution Flow

```
┌───────────────────────────────────────────────────────────────┐
│                    DISPUTE INITIATED                          │
└───────────────────────────────────────────────────────────────┘
                             │
                             │ Buyer or Seller
                             │ raises dispute
                             │ + pays dispute fee
                             ▼
                  ┌──────────────────────┐
                  │ Escrow State         │
                  │ ACCEPTED → DISPUTED  │
                  └──────────┬───────────┘
                             │
                             │ Anyone calls
                             │ assignArbitratorToEscrow()
                             ▼
                  ┌──────────────────────┐
                  │  Factory queries     │
                  │  ArbitratorRegistry  │
                  │  for best arbitrator │
                  └──────────┬───────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │  Arbitrator Assigned │
                  │  to Escrow           │
                  └──────────┬───────────┘
                             │
                  ┌──────────┴───────────┐
                  │                      │
                  │ Arbitrator Reviews:  │
                  │ - Description        │
                  │ - Dispute reason     │
                  │ - Off-chain evidence │
                  │                      │
                  └──────────┬───────────┘
                             │
                             │ resolveDispute()
                             │
            ┌────────────────┼────────────────┐
            │                │                │
            ▼                ▼                ▼
    ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
    │ BUYER_WINS   │ │ SELLER_WINS  │ │    SPLIT     │
    │              │ │              │ │              │
    │ Full refund  │ │ Full payment │ │ 50/50 split  │
    │ to buyer     │ │ to seller    │ │ both parties │
    └──────────────┘ └──────────────┘ └──────────────┘
            │                │                │
            └────────────────┼────────────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │ State: RESOLVED      │
                  │ Funds distributed    │
                  │ Reputation updated   │
                  └──────────────────────┘
```

## User Role Interactions

```
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  ┌──────────┐                                  ┌──────────┐    │
│  │  BUYER   │                                  │  SELLER  │    │
│  └────┬─────┘                                  └─────┬────┘    │
│       │                                              │         │
│       │ Can:                                         │ Can:    │
│       │ • createEscrow()                             │ • acceptEscrow()
│       │ • releasePayment()                           │ • markCompleted()
│       │ • raiseDispute()                             │ • raiseDispute()
│       │ • cancelEscrow()                             │ • claimAfterDeadline()
│       │   (before acceptance)                        │         │
│       │                                              │         │
│       └──────────────┬───────────────────────────────┘         │
│                      │                                         │
│                      ▼                                         │
│           ┌────────────────────┐                               │
│           │   ESCROW CONTRACT  │                               │
│           │  - Holds funds     │                               │
│           │  - Enforces rules  │                               │
│           └────────────────────┘                               │
│                      │                                         │
│                      │ (if disputed)                           │
│                      ▼                                         │
│           ┌────────────────────┐                               │
│           │   ARBITRATOR       │                               │
│           │                    │                               │
│           │ Can:               │                               │
│           │ • resolveDispute() │                               │
│           │ • updateFee()      │                               │
│           │                    │                               │
│           └────────────────────┘                               │
│                      │                                         │
│                      ▼                                         │
│           ┌────────────────────┐                               │
│           │   FACTORY OWNER    │                               │
│           │                    │                               │
│           │ Can:               │                               │
│           │ • pause/unpause    │                               │
│           │ • setSupportedToken│                               │
│           │ • setPlatformFee   │                               │
│           │ • withdrawFees     │                               │
│           │ • registerArbitrator                               │
│           │                    │                               │
│           └────────────────────┘                               │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## Token Flow Diagram

### ETH Escrow
```
┌──────┐                                             ┌────────┐
│Buyer │                                             │ Seller │
└───┬──┘                                             └───┬────┘
    │                                                    │
    │ 1. createEscrow{value: 1 ETH}                      │
    │ ──────────────────────────────►                    │
    │                                                    │
    │        ┌─────────────────┐                         │
    │        │ Escrow Contract │                         │
    │        │  Balance: 1 ETH │                         │
    │        └─────────────────┘                         │
    │                   │                                │
    │                   │ (work completed)               │
    │                   │                                │
    │ 2. releasePayment()                                │
    │ ──────────────────┼───────────────────────────────►│
    │                   │                         1 ETH  │
    │                   │                                │
    │        ┌─────────────────┐                         │
    │        │ Escrow Contract │                         │
    │        │   Balance: 0    │                         │
    │        └─────────────────┘                         │
```

### ERC20 Escrow
```
┌──────┐                                             ┌────────┐
│Buyer │                                             │ Seller │
└───┬──┘                                             └───┬────┘
    │                                                    │
    │ 1. token.approve(factory, 100 USDC)                │
    │ ───────────────────────────────────►               │
    │                                                    │
    │ 2. createEscrow(seller, token, 100, ...)           │
    │ ──────────────────────────────────►                │
    │                                                    │
    │        ┌─────────────────────┐                     │
    │        │  Escrow Contract    │                     │
    │        │ Token: 100 USDC     │                     │
    │        └─────────────────────┘                     │
    │                   │                                │
    │ 3. releasePayment()                                │
    │ ──────────────────┼───────────────────────────────►│
    │                   │                       100 USDC │
    │                   │                                │
    │        ┌─────────────────────┐                     │
    │        │  Escrow Contract    │                     │
    │        │  Token: 0 USDC      │                     │
    │        └─────────────────────┘                     │
```

## Gas Cost Comparison

```
Operation            │ Optimized │ Unoptimized │ Savings
─────────────────────┼───────────┼─────────────┼─────────
Create Escrow        │  160k     │  210k       │  50k (24%)
Accept Escrow        │   50k     │   65k       │  15k (23%)
Release Payment      │   45k     │   60k       │  15k (25%)
Raise Dispute        │   60k     │   75k       │  15k (20%)
Resolve Dispute      │   55k     │   70k       │  15k (21%)

Optimizations Used:
✓ Immutable variables
✓ Storage packing
✓ Events for off-chain data
✓ Short-circuit checks
✓ External functions
```

## Security Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    SECURITY LAYERS                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Layer 1: Access Control                                    │
│  ├─ Role-based permissions                                  │
│  ├─ Buyer/Seller/Arbitrator checks                          │
│  └─ Owner-only admin functions                              │
│                                                             │
│  Layer 2: State Validation                                  │
│  ├─ State machine enforcement                               │
│  ├─ Deadline checks                                         │
│  └─ Amount validations                                      │
│                                                             │
│  Layer 3: Reentrancy Protection                             │
│  ├─ ReentrancyGuard on state-changing functions             │
│  ├─ Checks-Effects-Interactions pattern                     │
│  └─ No external calls before state updates                  │
│                                                             │
│  Layer 4: Economic Security                                 │
│  ├─ Dispute fees prevent spam                               │
│  ├─ Reputation system for arbitrators                       │
│  └─ Platform fees for sustainability                        │
│                                                             │
│  Layer 5: Emergency Controls                                │
│  ├─ Pause mechanism for factory                             │
│  ├─ Existing escrows remain functional                      │
│  └─ Owner can update parameters                             │
│                                                             │
│  Layer 6: Arithmetic Safety                                 │
│  ├─ Solidity 0.8+ overflow protection                       │
│  ├─ Safe division handling                                  │
│  └─ No unchecked blocks                                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

*These diagrams illustrate the complete architecture and flows of the Decentralized Escrow Marketplace*
