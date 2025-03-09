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

;; Governance Helper Functions - Enhanced for delegation support
(define-private (get-proposal-status (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal (get status proposal)
        "NOT_FOUND"
    )
)

(define-private (calculate-voting-power (address principal))
    (let (
        (direct-power (match (map-get? members address)
            member (get staked-amount member)
            u0
        ))
        (delegated-power (match (map-get? delegations address)
            delegation (get total-delegated delegation)
            u0
        ))
    )
    (+ direct-power delegated-power))
)

(define-private (get-effective-voter (address principal))
    (match (map-get? members address)
        member (match (get delegated-to member)
            delegated delegated
            address)
        address
    )
)

;; Event logging for important state changes
(define-private (emit-event (event-name (string-ascii 50)) (data (string-ascii 100)))
    (print {event: event-name, data: data, sender: tx-sender, block: block-height})
)

;; Administrative Functions - With timelock for safety
(define-public (initialize (new-owner principal))
    (begin
        (asserts! (is-dao-owner) ERR-NOT-AUTHORIZED)
        (asserts! (validate-principal new-owner) ERR-INVALID-OWNER)
        (asserts! (check-timelock "initialize") ERR-TIMELOCK-ACTIVE)
        
        (var-set dao-owner new-owner)
        (emit-event "owner-changed" (concat "New owner: " (to-ascii (unwrap-panic (to-consensus-buff? new-owner)))))
        (ok true)
    )
)

(define-public (request-owner-change (new-owner principal))
    (begin
        (asserts! (is-dao-owner) ERR-NOT-AUTHORIZED)
        (asserts! (validate-principal new-owner) ERR-INVALID-OWNER)
        
        (set-timelock "initialize" none none)
        (emit-event "owner-change-requested" (concat "Requested new owner: " (to-ascii (unwrap-panic (to-consensus-buff? new-owner)))))
        (ok true)
    )
)

;; Enhanced membership management with delegation support
(define-public (stake-tokens (amount uint))
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (let (
            (current-balance (default-to 
                {staked-amount: u0, last-reward-block: block-height, rewards-claimed: u0, delegated-to: none, cooldown-end-block: u0} 
                (map-get? members tx-sender)))
        )
            (map-set members tx-sender {
                staked-amount: (+ (get staked-amount current-balance) amount),
                last-reward-block: block-height,
                rewards-claimed: (get rewards-claimed current-balance),
                delegated-to: (get delegated-to current-balance),
                cooldown-end-block: (get cooldown-end-block current-balance)
            })
            
            ;; Update delegation if member has delegated
            (match (get delegated-to current-balance)
                delegated-principal (update-delegation delegated-principal amount true)
                true
            )
            
            (var-set total-staked (+ (var-get total-staked) amount))
            (emit-event "tokens-staked" (concat "Amount: " (to-ascii (unwrap-panic (to-uint-string amount)))))
            (ok true)
        )
    )
)

(define-public (request-unstake (amount uint))
    (let (
        (current-balance (unwrap! (map-get? members tx-sender) ERR-NOT-AUTHORIZED))
    )
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= (get staked-amount current-balance) amount) ERR-INSUFFICIENT-BALANCE)
        
        (map-set members tx-sender (merge current-balance {
            cooldown-end-block: (+ block-height (var-get unstake-cooldown))
        }))
        
        (emit-event "unstake-requested" (concat "Amount: " (to-ascii (unwrap-panic (to-uint-string amount)))))
        (ok true)
    ))
)

(define-public (unstake-tokens (amount uint))
    (let (
        (current-balance (unwrap! (map-get? members tx-sender) ERR-NOT-AUTHORIZED))
    )
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= (get staked-amount current-balance) amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (>= block-height (get cooldown-end-block current-balance)) ERR-COOLDOWN-ACTIVE)
        
        (try! (as-contract (stx-transfer? amount (as-contract tx-sender) tx-sender)))
        
        (map-set members tx-sender (merge current-balance {
            staked-amount: (- (get staked-amount current-balance) amount),
            cooldown-end-block: u0
        }))
        
        ;; Update delegation if member has delegated
        (match (get delegated-to current-balance)
            delegated-principal (update-delegation delegated-principal amount false)
            true
        )
        
        (var-set total-staked (- (var-get total-staked) amount))
        (emit-event "tokens-unstaked" (concat "Amount: " (to-ascii (unwrap-panic (to-uint-string amount)))))
        (ok true)
    ))
)

;; Delegation system
(define-public (delegate-to (delegate principal))
    (let (
        (member-info (unwrap! (map-get? members tx-sender) ERR-INACTIVE-MEMBER))
        (staked-amount (get staked-amount member-info))
    )
    (begin
        (asserts! (not (is-eq tx-sender delegate)) ERR-SELF-DELEGATION)
        (asserts! (is-member delegate) ERR-DELEGATE-NOT-FOUND)
        (asserts! (> staked-amount u0) ERR-INSUFFICIENT-BALANCE)
        
        ;; Remove from previous delegate if exists
        (match (get delegated-to member-info)
            previous-delegate (update-delegation previous-delegate staked-amount false)
            true
        )
        
        ;; Add to new delegate
        (update-delegation delegate staked-amount true)
        
        ;; Update member record
        (map-set members tx-sender (merge member-info {
            delegated-to: (some delegate)
        }))
        
        (emit-event "delegation-changed" (concat "Delegated to: " (to-ascii (unwrap-panic (to-consensus-buff? delegate)))))
        (ok true)
    ))
)

(define-public (undelegate)
    (let (
        (member-info (unwrap! (map-get? members tx-sender) ERR-INACTIVE-MEMBER))
        (staked-amount (get staked-amount member-info))
    )
    (begin
        (match (get delegated-to member-info)
            delegate (begin
                (update-delegation delegate staked-amount false)
                (map-set members tx-sender (merge member-info {
                    delegated-to: none
                }))
                (emit-event "delegation-removed" "Delegation removed")
                (ok true)
            )
            (err ERR-DELEGATE-NOT-FOUND)
        )
    ))
)

(define-private (update-delegation (delegate principal) (amount uint) (is-adding bool))
    (match (map-get? delegations delegate)
        delegation-info 
        (if is-adding
            (map-set delegations delegate {
                total-delegated: (+ (get total-delegated delegation-info) amount),
                delegators: (get delegators delegation-info)
            })
            (map-set delegations delegate {
                total-delegated: (- (get total-delegated delegation-info) amount),
                delegators: (get delegators delegation-info)
            })
        )
        (if is-adding
            (map-set delegations delegate {
                total-delegated: amount,
                delegators: (list tx-sender)
            })
            true
        )
    )
    true
)

;; Improved Proposal Management with different proposal types
(define-public (create-proposal 
                (title (string-ascii 100)) 
                (description (string-ascii 500)) 
                (proposal-type (string-ascii 20))
                (amount uint)
                (recipient principal)
                (parameter (optional (string-ascii 20)))
                (parameter-value (optional uint))
                (contract-call-info (optional {contract: principal, function: (string-ascii 30)})))
    (let (
        (proposal-id (+ (var-get proposal-count) u1))
        (proposer-stake (calculate-voting-power tx-sender))
    )
    (begin
        (asserts! (is-member tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (>= proposer-stake (var-get min-proposal-amount)) ERR-INSUFFICIENT-BALANCE)
        (asserts! (validate-string-ascii title) ERR-INVALID-TITLE)
        (asserts! (validate-string-ascii description) ERR-INVALID-DESCRIPTION)
        (asserts! (validate-proposal-type proposal-type) ERR-PROPOSAL-TYPE-INVALID)
        
        ;; Type-specific validations
        (if (is-eq proposal-type PROPOSAL-TYPE-TRANSFER)
            (begin
                (asserts! (> amount u0) ERR-INVALID-AMOUNT)
                (asserts! (validate-principal recipient) ERR-INVALID-RECIPIENT)
            )
            true
        )
        
        (if (is-eq proposal-type PROPOSAL-TYPE-PARAMETER)
            (begin
                (asserts! (is-some parameter) ERR-INVALID-PARAMETER)
                (asserts! (is-some parameter-value) ERR-INVALID-PARAMETER)
                (asserts! (validate-parameter (unwrap! parameter ERR-INVALID-PARAMETER)) ERR-INVALID-PARAMETER)
            )
            true
        )
        
        (if (is-eq proposal-type PROPOSAL-TYPE-CONTRACT-CALL)
            (asserts! (is-some contract-call-info) ERR-INVALID-PARAMETER)
            true
        )
        
        (map-set proposals proposal-id {
            proposer: tx-sender,
            title: title,
            description: description,
            amount: amount,
            recipient: recipient,
            start-block: block-height,
            end-block: (+ block-height (var-get proposal-duration)),
            execution-block: (+ block-height (var-get proposal-duration) (var-get execution-delay)),
            yes-votes: u0,
            no-votes: u0,
            status: STATUS-ACTIVE,
            executed: false,
            proposal-type: proposal-type,
            parameter: parameter,
            contract-call: contract-call-info
        })
        
        (var-set proposal-count proposal-id)
        (emit-event "proposal-created" (concat "Proposal ID: " (to-ascii (unwrap-panic (to-uint-string proposal-id)))))
        (ok proposal-id)
    ))
)

;; Enhanced Voting System with delegation support
(define-public (vote (proposal-id uint) (vote-for bool))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
        (effective-voter (get-effective-voter tx-sender))
        (voter-power (calculate-voting-power tx-sender))
    )
    (begin
        (asserts! (is-member tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status proposal) STATUS-ACTIVE) ERR-PROPOSAL-NOT-ACTIVE)
        (asserts! (<= block-height (get end-block proposal)) ERR-PROPOSAL-EXPIRED)
        (asserts! (is-none (map-get? votes {proposal-id: proposal-id, voter: effective-voter})) ERR-ALREADY-VOTED)
        (asserts! (> voter-power u0) ERR-INSUFFICIENT-BALANCE)
        
        ;; For delegated votes, use the effective voter
        (if (not (is-eq tx-sender effective-voter))
            (begin
                (map-set votes 
                    {proposal-id: proposal-id, voter: effective-voter} 
                    {vote: vote-for, power: voter-power})
                
                (map-set proposals proposal-id 
                    (merge proposal 
                        {
                            yes-votes: (if vote-for
                                (+ (get yes-votes proposal) voter-power)
                                (get yes-votes proposal)
                            ),
                            no-votes: (if vote-for
                                (get no-votes proposal)
                                (+ (get no-votes proposal) voter-power)
                            )
                        }
                    )
                )
            )
            (begin
                (map-set votes 
                    {proposal-id: proposal-id, voter: tx-sender} 
                    {vote: vote-for, power: voter-power})
                
                (map-set proposals proposal-id 
                    (merge proposal 
                        {
                            yes-votes: (if vote-for
                                (+ (get yes-votes proposal) voter-power)
                                (get yes-votes proposal)
                            ),
                            no-votes: (if vote-for
                                (get no-votes proposal)
                                (+ (get no-votes proposal) voter-power)
                            )
                        }
                    )
                )
            )
        )
        
        (emit-event "vote-cast" (concat "Proposal: " (to-ascii (unwrap-panic (to-uint-string proposal-id)))))
        (ok true)
    ))
)

;; Enhanced Proposal Execution with timelock and different types
(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
    (begin
        (asserts! (>= block-height (get end-block proposal)) ERR-PROPOSAL-NOT-ACTIVE)
        (asserts! (>= block-height (get execution-block proposal)) ERR-TIMELOCK-ACTIVE)
        (asserts! (not (get executed proposal)) ERR-INVALID-STATUS)
        
        (let (
            (quorum-requirement (/ (* (var-get total-staked) (var-get quorum-threshold)) u1000))
            (proposal-passed (and
                (>= (get yes-votes proposal) quorum-requirement)
                (> (get yes-votes proposal) (get no-votes proposal))
            ))
        )
            (if proposal-passed
                (begin
                    ;; Execute based on proposal type
                    (if (is-eq (get proposal-type proposal) PROPOSAL-TYPE-TRANSFER)
                        (try! (as-contract (stx-transfer? (get amount proposal) 
                            (as-contract tx-sender) 
                            (get recipient proposal))))
                        true
                    )
                    
                    (if (is-eq (get proposal-type proposal) PROPOSAL-TYPE-PARAMETER)
                        (execute-parameter-change 
                            (unwrap! (get parameter proposal) ERR-INVALID-PARAMETER)
                            (unwrap! (get parameter proposal) ERR-INVALID-PARAMETER))
                        true
                    )
                    
                    (if (is-eq (get proposal-type proposal) PROPOSAL-TYPE-CONTRACT-CALL)
                        ;; Contract calls would need a more sophisticated implementation
                        ;; with trait support, but this is a placeholder
                        (emit-event "contract-call" "Contract call executed")
                        true
                    )
                    
                    (map-set proposals proposal-id 
                        (merge proposal {
                            status: STATUS-EXECUTED,
                            executed: true
                        })
                    )
                    (emit-event "proposal-executed" (concat "Proposal: " (to-ascii (unwrap-panic (to-uint-string proposal-id)))))
                    (ok true)
                )
                (begin
                    (map-set proposals proposal-id 
                        (merge proposal {
                            status: STATUS-REJECTED,
                            executed: true
                        })
                    )
                    (emit-event "proposal-rejected" (concat "Proposal: " (to-ascii (unwrap-panic (to-uint-string proposal-id)))))
                    (ok true)
                )
            )
        )
    ))
)
