;; Title: Decentralized Autonomous Organization (DAO) Contract
;; 
;; Summary:
;; An improved DAO implementation with enhanced security, modular design, and additional functionality
;; for governance through token staking, proposal creation, and voting mechanisms.
;;
;; Description:
;; This contract extends the core DAO functionality with:
;; - Enhanced member management with delegation capability
;; - Advanced proposal lifecycle with executable code support
;; - More granular access controls and security measures
;; - Enhanced treasury management with multi-asset support
;; - Time-lock mechanisms for critical operations
;; - Event logging for better transparency
;; - Governance parameter adjustment by DAO vote

;; Error Codes - Extended for more specific errors
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-PROPOSAL-EXPIRED (err u104))
(define-constant ERR-INSUFFICIENT-BALANCE (err u105))
(define-constant ERR-PROPOSAL-NOT-ACTIVE (err u106))
(define-constant ERR-INVALID-STATUS (err u107))
(define-constant ERR-INVALID-OWNER (err u108))
(define-constant ERR-INVALID-TITLE (err u109))
(define-constant ERR-INVALID-DESCRIPTION (err u110))
(define-constant ERR-INVALID-RECIPIENT (err u111))
(define-constant ERR-INVALID-VOTE (err u112))
(define-constant ERR-TIMELOCK-ACTIVE (err u113))
(define-constant ERR-DELEGATE-NOT-FOUND (err u114))
(define-constant ERR-SELF-DELEGATION (err u115))
(define-constant ERR-INACTIVE-MEMBER (err u116))
(define-constant ERR-ZERO-QUORUM (err u117))
(define-constant ERR-COOLDOWN-ACTIVE (err u118))
(define-constant ERR-INVALID-PARAMETER (err u119))
(define-constant ERR-PROPOSAL-TYPE-INVALID (err u120))

;; Governance Parameters - Extended with adjustable parameters
(define-data-var dao-owner principal tx-sender)
(define-data-var total-staked uint u0)
(define-data-var proposal-count uint u0)
(define-data-var quorum-threshold uint u500) ;; 50% in basis points
(define-data-var proposal-duration uint u144) ;; ~24 hours in blocks
(define-data-var min-proposal-amount uint u1000000) ;; Minimum STX required for proposal creation
(define-data-var governance-token (optional principal) none) ;; Optional SIP-010 token for governance
(define-data-var timelock-period uint u72) ;; ~12 hours in blocks for critical changes
(define-data-var unstake-cooldown uint u36) ;; ~6 hours in blocks before unstaking
(define-data-var execution-delay uint u12) ;; ~2 hours in blocks before proposal execution

;; Status constants for clarity and consistency
(define-constant STATUS-ACTIVE "ACTIVE")
(define-constant STATUS-EXECUTED "EXECUTED")
(define-constant STATUS-REJECTED "REJECTED")
(define-constant STATUS-CANCELLED "CANCELLED")
(define-constant STATUS-QUEUED "QUEUED")

;; Proposal types to support different actions
(define-constant PROPOSAL-TYPE-TRANSFER "TRANSFER")
(define-constant PROPOSAL-TYPE-PARAMETER "PARAMETER")
(define-constant PROPOSAL-TYPE-CONTRACT-CALL "CONTRACT_CALL")

;; Data Structures - Enhanced with additional fields
;; Tracks member participation, rewards, and delegation
(define-map members 
    principal 
    {
        staked-amount: uint,
        last-reward-block: uint,
        rewards-claimed: uint,
        delegated-to: (optional principal),
        cooldown-end-block: uint
    }
)

;; Tracks delegated voting power
(define-map delegations
    principal
    {
        total-delegated: uint,
        delegators: (list 20 principal)
    }
)

;; Stores timelocked operations
(define-map timelocks
    principal
    {
        operation: (string-ascii 20),
        end-block: uint,
        data: (optional {parameter: (string-ascii 20), value: uint})
    }
)

;; Enhanced proposal structure with more fields
(define-map proposals 
    uint 
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
)

;; Records member votes on proposals
(define-map votes 
    {proposal-id: uint, voter: principal} 
    {vote: bool, power: uint}
)

;; Authorization Functions - Enhanced with role checks
(define-private (is-dao-owner)
    (is-eq tx-sender (var-get dao-owner))
)

(define-private (is-dao-contract)
    (is-eq tx-sender (as-contract tx-sender))
)

(define-private (is-member (address principal))
    (match (map-get? members address)
        member (> (get staked-amount member) u0)
        false
    )
)

;; Enhanced Validation Functions
(define-private (validate-string-ascii (input (string-ascii 500)))
    (and 
        (not (is-eq input ""))
        (<= (len input) u500)
    )
)

(define-private (validate-principal (address principal))
    (and
        (not (is-eq address tx-sender))
        (not (is-eq address (as-contract tx-sender)))
    )
)

(define-private (validate-proposal-type (proposal-type (string-ascii 20)))
    (or 
        (is-eq proposal-type PROPOSAL-TYPE-TRANSFER)
        (is-eq proposal-type PROPOSAL-TYPE-PARAMETER)
        (is-eq proposal-type PROPOSAL-TYPE-CONTRACT-CALL)
    )
)

(define-private (validate-parameter (parameter (string-ascii 20)))
    (or 
        (is-eq parameter "quorum-threshold")
        (is-eq parameter "proposal-duration")
        (is-eq parameter "min-proposal-amount")
        (is-eq parameter "timelock-period")
        (is-eq parameter "unstake-cooldown")
        (is-eq parameter "execution-delay")
    )
)

;; Timelock Management
(define-private (set-timelock (operation (string-ascii 20)) (parameter (optional (string-ascii 20))) (value (optional uint)))
    (map-set timelocks tx-sender {
        operation: operation,
        end-block: (+ block-height (var-get timelock-period)),
        data: (match (and parameter value)
            (and (some param) (some val)) (some {parameter: param, value: val})
            none
        )
    })
)

(define-private (check-timelock (operation (string-ascii 20)))
    (match (map-get? timelocks tx-sender)
        timelock (and 
            (is-eq (get operation timelock) operation)
            (>= block-height (get end-block timelock))
        )
        false
    )
)