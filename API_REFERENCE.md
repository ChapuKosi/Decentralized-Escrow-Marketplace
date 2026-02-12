# Smart Contract API Reference

**Portfolio Project:** Decentralized Escrow Marketplace Smart Contracts

This document provides technical specifications and API reference for the smart contract implementation. This is a portfolio project demonstrating smart contract development capabilities.

## Contract Overview

### Escrow.sol
Individual escrow contract representing a single deal between buyer and seller.

#### Key Functions

**For Buyers:**
- `releasePayment()` - Release funds to seller when satisfied
- `raiseDispute(string reason)` - Raise a dispute with arbitration
- `cancelEscrow()` - Cancel before seller accepts

**For Sellers:**
- `acceptEscrow()` - Accept the deal and start work
- `markCompleted()` - Signal work is done
- `claimAfterDeadline()` - Claim funds if buyer doesn't respond after deadline + 7 days

**For Arbitrators:**
- `resolveDispute(DisputeOutcome outcome)` - Resolve dispute

**View Functions:**
- `getDetails()` - Get all escrow information
- `isActive()` - Check if escrow is in active state
- `timeRemaining()` - Get seconds until deadline
- `isDeadlinePassed()` - Check if deadline has passed

#### State Machine

```
CREATED
  ↓ acceptEscrow()
ACCEPTED
  ↓ releasePayment() OR raiseDispute()
COMPLETED / DISPUTED
  ↓ (if disputed) resolveDispute()
RESOLVED
```

#### Events

```solidity
event EscrowCreated(address indexed buyer, address indexed seller, uint256 amount, uint256 deadline)
event EscrowAccepted(address indexed seller, uint256 timestamp)
event WorkCompleted(address indexed seller, uint256 timestamp)
event PaymentReleased(address indexed seller, uint256 amount, uint256 timestamp)
event DisputeRaised(address indexed raiser, string reason, uint256 timestamp)
event DisputeResolved(DisputeOutcome outcome, address indexed arbitrator, uint256 timestamp)
event EscrowCancelled(uint256 timestamp)
```

---

### EscrowFactory.sol
Factory contract for creating and managing escrow deals. Central hub of the marketplace.

#### Key Functions

**For Users:**
- `createEscrow(...)` - Create new escrow with default dispute fee
- `createEscrowWithCustomFee(...)` - Create escrow with custom dispute fee

**For Admins:**
- `setSupportedToken(address token, bool supported)` - Add/remove token support
- `setDefaultDisputeFee(uint256 newFee)` - Update dispute fee
- `setPlatformFee(uint256 newFeePercent)` - Update platform fee (max 10%)
- `pause() / unpause()` - Emergency controls
- `withdrawFees()` - Withdraw accumulated platform fees

**View Functions:**
- `getAllEscrows()` - Get all created escrows
- `getUserEscrows(address user)` - Get escrows for specific user
- `getActiveEscrows()` - Get all active escrows
- `getStatistics()` - Get marketplace statistics

#### Important Notes

- Platform fee is in basis points (250 = 2.5%)
- ETH is always supported (address(0))
- Only pauses new escrow creation, existing escrows continue
- Factory must be approved to spend ERC20 tokens

---

### ArbitratorRegistry.sol
Manages pool of trusted arbitrators and their reputation.

#### Key Functions

**For Owner:**
- `registerArbitrator(address arbitrator, uint256 feePerCase)` - Register new arbitrator
- `deactivateArbitrator(address arbitrator)` - Deactivate arbitrator
- `reactivateArbitrator(address arbitrator)` - Reactivate arbitrator

**For Arbitrators:**
- `updateFee(uint256 feePerCase)` - Update their fee

**For System:**
- `assignCase(address arbitrator)` - Record case assignment
- `recordResolution(address arbitrator, bool satisfactory)` - Update reputation

**View Functions:**
- `getRandomArbitrator()` - Get random active arbitrator
- `getBestArbitrator()` - Get arbitrator with best reputation
- `getActiveArbitrators()` - Get all active arbitrators
- `getArbitratorInfo(address)` - Get arbitrator details

#### Reputation System

- Arbitrators start with reputation of 100
- Satisfactory resolution: +1 (max 100)
- Unsatisfactory resolution: -5
- Auto-deactivated if reputation drops below 50

---

## Design Patterns Used

### 1. Factory Pattern
`EscrowFactory` creates individual `Escrow` contracts. Benefits:
- Single entry point
- Easier to track all escrows
- Can upgrade factory without affecting existing escrows

### 2. State Machine
Escrows follow strict state transitions:
- Prevents invalid operations
- Makes logic clear and auditable
- Easy to reason about

### 3. Checks-Effects-Interactions
All functions follow CEI pattern:
```solidity
// 1. Checks
if (msg.sender != buyer) revert Unauthorized();
if (state != State.ACCEPTED) revert InvalidState();

// 2. Effects
state = State.COMPLETED;

// 3. Interactions
_transferFunds(seller, amount);
```

### 4. Pull Over Push
Users must actively claim funds rather than automatic transfers:
- Reduces gas costs
- Prevents griefing attacks
- More predictable behavior

### 5. Circuit Breaker
Emergency pause mechanism:
- Owner can pause factory
- Existing escrows unaffected
- Can resume when safe

---

## Security Considerations

### Reentrancy
- All state-changing functions use `nonReentrant` modifier
- CEI pattern enforced throughout
- External calls always last

### Access Control
- Role-based permissions (buyer, seller, arbitrator)
- Only owner can manage factory settings
- No privilege escalation possible

### Arithmetic
- Solidity 0.8.20+ has built-in overflow protection
- Division by zero checked implicitly
- No unchecked blocks used

### Front-Running
- Dispute fees prevent spam attacks
- First-come-first-serve on acceptance
- No MEV opportunities

### Griefing
- Dispute fees discourage frivolous disputes
- Reputation system holds arbitrators accountable
- Deadline + grace period prevents fund locking

---

## Gas Optimization Tips

1. **Use `immutable` for constants set in constructor**
   - Saves 2100 gas per read
   - Used extensively in Escrow.sol

2. **Pack storage variables**
   - Group small types together
   - Saves storage slots

3. **Use events for data that doesn't need to be on-chain**
   - Much cheaper than storage
   - Can be indexed off-chain

4. **Short-circuit with `revert` early**
   - Fail fast to save gas
   - All validations at function start

5. **Use `external` over `public`**
   - Cheaper for external calls
   - Used for all user-facing functions

---

## Upgrade Path

### Without Breaking Existing Escrows

1. **Deploy new Factory**
   - Old escrows remain functional
   - New features in new factory only

2. **Deploy new Escrow implementation**
   - Factory can create new version
   - Old escrows unchanged

3. **Maintain backward compatibility**
   - Keep interfaces stable
   - Add new functions, don't change existing

### With Proxies (Future)

Could implement upgradeable proxies for:
- Factory contract
- Arbitrator registry
- Individual escrows (more complex)

---

## Testing Strategy

### Unit Tests
Test individual functions in isolation:
- Happy paths
- Edge cases
- Access control
- State transitions

### Integration Tests
Test multiple contracts together:
- End-to-end flows
- Cross-contract calls
- Event emissions

### Fuzz Tests
Randomized inputs to find edge cases:
- Large/small amounts
- Extreme timestamps
- Random addresses

### Invariant Tests (Future)
Properties that should always hold:
- Total value locked = sum of escrow balances
- State transitions only go forward
- Funds always accounted for

---

## Contract Interaction

### Using Foundry Cast

```bash
# Create escrow
cast send $FACTORY_ADDRESS "createEscrow(address,address,uint256,uint256,string)" \
  $SELLER_ADDRESS \
  0x0000000000000000000000000000000000000000 \
  500000000000000000 \
  $DEADLINE \
  "Build website" \
  --value 0.5ether \
  --private-key $PRIVATE_KEY

# Check escrow details
cast call $ESCROW_ADDRESS "getDetails()"
```

### Listening to Events

```typescript
factory.on('EscrowCreated', (escrow, buyer, seller, token, amount, deadline) => {
  console.log('New escrow created:', escrow);
  // Update UI
});
```

### Using The Graph (Recommended)

Create a subgraph to index all events:
- Fast queries
- Historical data
- Complex filters
- Reduced RPC calls

---

## Common Patterns

### Creating ETH Escrow
```solidity
factory.createEscrow{value: amount}(
  seller,
  address(0), // ETH
  amount,
  deadline,
  description
);
```

### Creating Token Escrow
```solidity
// 1. Approve factory
token.approve(address(factory), amount);

// 2. Create escrow
factory.createEscrow(
  seller,
  address(token),
  amount,
  deadline,
  description
);
```

### Handling Disputes
```solidity
// Buyer or seller raises dispute
escrow.raiseDispute{value: disputeFee}("Reason");

// Factory assigns arbitrator
factory.assignArbitratorToEscrow(escrowAddress);

// Arbitrator resolves
escrow.resolveDispute(Escrow.DisputeOutcome.BUYER_WINS);
```

---

## FAQ

**Q: Can I cancel an escrow after it's been accepted?**
A: No, once accepted, you must either complete it or raise a dispute.

**Q: What happens if the buyer never responds?**
A: Seller can claim funds after deadline + 7 days grace period.

**Q: How are arbitrators chosen?**
A: Currently uses the arbitrator with best reputation. Future: random selection or buyer choice.

**Q: Can I use any ERC20 token?**
A: Only tokens whitelisted by factory owner via `setSupportedToken()`.

**Q: What if I lose the dispute?**
A: Arbitrator's decision is final. Future versions may include appeals.

**Q: Are there platform fees?**
A: Yes, configurable by owner (max 10%). Default is 2.5%.

---

