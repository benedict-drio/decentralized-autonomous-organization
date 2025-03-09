# DAO Smart Contract Documentation

A sophisticated Decentralized Autonomous Organization (DAO) implementation featuring advanced governance mechanisms, secure asset management, and modular proposal system. Designed for enterprise-grade decentralized governance.

## Table of Contents

- [DAO Smart Contract Documentation](#dao-smart-contract-documentation)
	- [Table of Contents](#table-of-contents)
	- [Key Features ](#key-features-)
	- [Error Codes ](#error-codes-)
	- [Governance Parameters ](#governance-parameters-)
	- [Data Structures ](#data-structures-)
		- [Member Profile](#member-profile)
		- [Proposal Structure](#proposal-structure)
	- [Core Functions ](#core-functions-)
		- [Token Management](#token-management)
		- [Delegation System](#delegation-system)
	- [Proposal System ](#proposal-system-)
		- [Proposal Types](#proposal-types)
		- [Lifecycle](#lifecycle)
	- [Voting Mechanism ](#voting-mechanism-)
	- [Security Features ](#security-features-)
	- [Events ](#events-)
	- [Deployment Notes ](#deployment-notes-)
	- [Usage Examples ](#usage-examples-)
		- [Creating a Transfer Proposal](#creating-a-transfer-proposal)
		- [Voting with Delegation](#voting-with-delegation)
	- [Read-Only Functions ](#read-only-functions-)

## Key Features <a name="key-features"></a>

- **Multi-Type Proposals**
  - Asset transfers
  - Governance parameter changes
  - Cross-contract executions
- **Delegated Voting System**
  - Voting power delegation
  - Automatic delegation tracking
  - Delegation cooldowns
- **Enhanced Security**
  - Time-locked executions
  - Unstaking cooldowns
  - Proposal execution delays
- **Multi-Asset Support**
  - Native STX handling
  - SIP-010 token integration
- **Advanced Governance**
  - Adjustable parameters
  - Dynamic quorum calculations
  - Proposal lifecycle management

## Error Codes <a name="error-codes"></a>

| Code | Constant                  | Description              |
| ---- | ------------------------- | ------------------------ |
| 100  | ERR-NOT-AUTHORIZED        | Unauthorized operation   |
| 101  | ERR-INVALID-AMOUNT        | Invalid token amount     |
| 102  | ERR-PROPOSAL-NOT-FOUND    | Nonexistent proposal     |
| 103  | ERR-ALREADY-VOTED         | Duplicate voting attempt |
| ...  | ...                       | ...                      |
| 120  | ERR-PROPOSAL-TYPE-INVALID | Invalid proposal type    |

_Full error list available in contract source_

## Governance Parameters <a name="governance-parameters"></a>

| Parameter             | Default | Description                          |
| --------------------- | ------- | ------------------------------------ |
| `quorum-threshold`    | 50%     | Minimum participation required       |
| `proposal-duration`   | 144     | Voting period in blocks (~24 hours)  |
| `timelock-period`     | 72      | Delay for critical ops (~12 hours)   |
| `execution-delay`     | 12      | Post-vote execution delay (~2 hours) |
| `min-proposal-amount` | 1M STX  | Minimum stake for proposal creation  |

## Data Structures <a name="data-structures"></a>

### Member Profile

```clarity
{
    staked-amount: uint,
    last-reward-block: uint,
    rewards-claimed: uint,
    delegated-to: (optional principal),
    cooldown-end-block: uint
}
```

### Proposal Structure

```clarity
{
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    amount: uint,
    recipient: principal,
    start-block: uint,
    end-block: uint,
    execution-block: uint,
    yes-votes: uint,
    no-votes: uint,
    status: (string-ascii 20),
    executed: bool,
    proposal-type: (string-ascii 20),
    parameter: (optional (string-ascii 20)),
    contract-call: (optional {contract: principal, function: (string-ascii 30)})
}
```

## Core Functions <a name="core-functions"></a>

### Token Management

```clarity
;; Stake tokens to gain voting power
(define-public (stake-tokens (amount uint))

;; Initiate unstaking process (starts cooldown)
(define-public (request-unstake (amount uint))

;; Complete unstaking after cooldown
(define-public (unstake-tokens (amount uint))
```

### Delegation System

```clarity
;; Delegate voting power to another member
(define-public (delegate-to (delegate principal))

;; Remove existing delegation
(define-public (undelegate)
```

## Proposal System <a name="proposal-system"></a>

### Proposal Types

1. **Asset Transfer**
   - Direct STX transfers from DAO treasury
   - Requires recipient validation
2. **Parameter Adjustment**
   - Modify governance parameters
   - Requires timelock period
3. **Contract Execution**
   - Call external contract functions
   - Supports arbitrary contract interactions

### Lifecycle

1. Creation → 2. Voting → 3. Queuing → 4. Execution/Rejection

## Voting Mechanism <a name="voting-mechanism"></a>

- **Weighted Voting**: Voting power = Staked amount + Delegated tokens
- **Delegation Rules**:
  - Self-delegation prohibited
  - Immediate delegation updates
  - Cooldown on delegation changes
- **Quorum Calculation**:
  `quorum = (total_staked * quorum_threshold) / 1000`

## Security Features <a name="security-features"></a>

- **Time Locks**
  - Mandatory delay for critical operations
  - Applies to parameter changes and ownership transfers
- **Cooldown Periods**
  - 6-hour unstaking cooldown
  - 12-hour timelock for governance changes
- **Input Validation**
  - Principal address checks
  - String length validation
  - Type-specific proposal validation

## Events <a name="events"></a>

| Event Name           | Data Included                 |
| -------------------- | ----------------------------- |
| `tokens-staked`      | Amount, staker address        |
| `proposal-created`   | ID, title, proposal type      |
| `vote-cast`          | Proposal ID, voter, direction |
| `parameter-changed`  | Parameter name, new value     |
| `delegation-changed` | Delegator, delegatee          |

## Deployment Notes <a name="deployment-notes"></a>

1. **Initial Setup**

```clarity
;; Set initial governance parameters
(var-set quorum-threshold u600)  ;; 60% quorum
(var-set min-proposal-amount u500000)  ;; 0.5 STX
```

2. **Governance Token Integration**

```clarity
;; Set SIP-010 token address
(var-set governance-token (some 'SP3XYZ...))
```

3. **Security Recommendations**

- Set initial timelock period > 72 blocks
- Conduct third-party audit
- Implement multi-sig for initial ownership

## Usage Examples <a name="usage-examples"></a>

### Creating a Transfer Proposal

```clarity
(create-proposal
    "Community Grant"
    "Fund developer grant program"
    PROPOSAL-TYPE-TRANSFER
    u10000000  ;; 10 STX
    'SP3RECIPIENT
    none
    none
    none)
```

### Voting with Delegation

```clarity
;; Delegate voting power
(delegate-to 'SP3DELEGATEE)

;; Vote through delegation
(vote proposal-id true)
```

## Read-Only Functions <a name="read-only-functions"></a>

```clarity
;; Get member's effective voting power
(get-effective-voting-power 'SP3MEMBER)

;; Retrieve proposal details
(get-proposal-info proposal-id)

;; Check active timelocks
(get-timelock-info 'SP3ADDRESS)
```
