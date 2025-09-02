;; Healthcare Blockchain Governance Core Contract
;; Provides comprehensive governance functionality for healthcare blockchain networks

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_PROPOSAL (err u103))
(define-constant ERR_VOTING_ENDED (err u104))
(define-constant ERR_VOTING_ACTIVE (err u105))
(define-constant ERR_INSUFFICIENT_STAKE (err u106))
(define-constant ERR_ALREADY_VOTED (err u107))
(define-constant ERR_QUORUM_NOT_MET (err u108))
(define-constant ERR_INVALID_STAKEHOLDER (err u109))

;; Stakeholder Types
(define-constant STAKEHOLDER_HEALTHCARE_PROVIDER u1)
(define-constant STAKEHOLDER_REGULATOR u2)
(define-constant STAKEHOLDER_PATIENT u3)
(define-constant STAKEHOLDER_TECH_PARTNER u4)

;; Proposal Types
(define-constant PROPOSAL_PROTOCOL_UPGRADE u1)
(define-constant PROPOSAL_GOVERNANCE_CHANGE u2)
(define-constant PROPOSAL_COMPLIANCE_UPDATE u3)
(define-constant PROPOSAL_EMERGENCY u4)

;; Voting Status
(define-constant VOTE_FOR u1)
(define-constant VOTE_AGAINST u2)
(define-constant VOTE_ABSTAIN u3)

;; Data Maps

;; Stakeholder registry with type, stake amount, and reputation score
(define-map stakeholders
    principal
    {
        stakeholder-type: uint,
        stake-amount: uint,
        reputation-score: uint,
        registration-height: uint,
        is-active: bool
    }
)

;; Proposals with detailed metadata
(define-map proposals
    uint
    {
        proposer: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        proposal-type: uint,
        voting-start: uint,
        voting-end: uint,
        votes-for: uint,
        votes-against: uint,
        votes-abstain: uint,
        total-voting-power: uint,
        required-quorum: uint,
        is-executed: bool,
        is-emergency: bool
    }
)

;; Individual votes tracking
(define-map votes
    {proposal-id: uint, voter: principal}
    {
        vote-type: uint,
        voting-power: uint,
        vote-height: uint
    }
)

;; Delegation tracking for proxy voting
(define-map delegations
    principal
    {
        delegate-to: principal,
        delegation-start: uint,
        delegation-end: uint,
        is-active: bool
    }
)

;; Governance parameters
(define-map governance-params
    (string-ascii 50)
    uint
)

;; Data Variables
(define-data-var proposal-counter uint u0)
(define-data-var governance-active bool true)

;; Initialize governance parameters
(map-set governance-params "voting-period" u1440) ;; 1440 blocks (~10 days)
(map-set governance-params "emergency-voting-period" u144) ;; 144 blocks (~1 day)
(map-set governance-params "min-stake-provider" u1000)
(map-set governance-params "min-stake-regulator" u500)
(map-set governance-params "min-stake-patient" u100)
(map-set governance-params "min-stake-tech" u750)
(map-set governance-params "quorum-standard" u51) ;; 51%
(map-set governance-params "quorum-emergency" u67) ;; 67%
(map-set governance-params "quorum-governance" u75) ;; 75%

;; Helper Functions

;; Get minimum stake for stakeholder type
(define-private (get-min-stake (stakeholder-type uint))
    (if (is-eq stakeholder-type STAKEHOLDER_HEALTHCARE_PROVIDER)
        (default-to u1000 (map-get? governance-params "min-stake-provider"))
        (if (is-eq stakeholder-type STAKEHOLDER_REGULATOR)
            (default-to u500 (map-get? governance-params "min-stake-regulator"))
            (if (is-eq stakeholder-type STAKEHOLDER_PATIENT)
                (default-to u100 (map-get? governance-params "min-stake-patient"))
                (default-to u750 (map-get? governance-params "min-stake-tech"))))))

;; Calculate voting power based on stake and stakeholder type
(define-private (calculate-voting-power (stakeholder-type uint) (stake-amount uint) (reputation uint))
    (let ((base-power (if (is-eq stakeholder-type STAKEHOLDER_HEALTHCARE_PROVIDER)
                         (* stake-amount u3) ;; Providers get 3x weight
                         (if (is-eq stakeholder-type STAKEHOLDER_REGULATOR)
                             (* stake-amount u4) ;; Regulators get 4x weight
                             (if (is-eq stakeholder-type STAKEHOLDER_PATIENT)
                                 (* stake-amount u1) ;; Patients get 1x weight
                                 (* stake-amount u2))))) ;; Tech partners get 2x weight
          (reputation-bonus (/ (* base-power reputation) u100)))
        (+ base-power reputation-bonus)))

;; Check if address is valid stakeholder
(define-private (is-valid-stakeholder (address principal))
    (match (map-get? stakeholders address)
        stakeholder-data (get is-active stakeholder-data)
        false))

;; Get required quorum for proposal type
(define-private (get-required-quorum (proposal-type uint))
    (if (is-eq proposal-type PROPOSAL_EMERGENCY)
        (default-to u67 (map-get? governance-params "quorum-emergency"))
        (if (is-eq proposal-type PROPOSAL_GOVERNANCE_CHANGE)
            (default-to u75 (map-get? governance-params "quorum-governance"))
            (default-to u51 (map-get? governance-params "quorum-standard")))))

;; Public Functions

;; Register as a stakeholder
(define-public (register-stakeholder (stakeholder-type uint) (stake-amount uint))
    (let ((min-stake (get-min-stake stakeholder-type)))
        (asserts! (>= stake-amount min-stake) ERR_INSUFFICIENT_STAKE)
        (asserts! (and (>= stakeholder-type u1) (<= stakeholder-type u4)) ERR_INVALID_STAKEHOLDER)
        (asserts! (is-none (map-get? stakeholders tx-sender)) ERR_ALREADY_EXISTS)
        (ok (map-set stakeholders tx-sender
            {
                stakeholder-type: stakeholder-type,
                stake-amount: stake-amount,
                reputation-score: u100, ;; Initial reputation
                registration-height: block-height,
                is-active: true
            }))))

;; Update stakeholder stake
(define-public (update-stake (new-stake uint))
    (match (map-get? stakeholders tx-sender)
        stakeholder-data
        (let ((min-stake (get-min-stake (get stakeholder-type stakeholder-data))))
            (asserts! (>= new-stake min-stake) ERR_INSUFFICIENT_STAKE)
            (ok (map-set stakeholders tx-sender
                (merge stakeholder-data {stake-amount: new-stake}))))
        ERR_NOT_FOUND))

;; Create a new proposal
(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (proposal-type uint) (is-emergency bool))
    (let ((proposal-id (+ (var-get proposal-counter) u1))
          (voting-period (if is-emergency
                           (default-to u144 (map-get? governance-params "emergency-voting-period"))
                           (default-to u1440 (map-get? governance-params "voting-period"))))
          (voting-start block-height)
          (voting-end (+ block-height voting-period))
          (required-quorum (get-required-quorum proposal-type)))
        (asserts! (var-get governance-active) ERR_UNAUTHORIZED)
        (asserts! (is-valid-stakeholder tx-sender) ERR_UNAUTHORIZED)
        (asserts! (and (>= proposal-type u1) (<= proposal-type u4)) ERR_INVALID_PROPOSAL)
        (var-set proposal-counter proposal-id)
        (ok (map-set proposals proposal-id
            {
                proposer: tx-sender,
                title: title,
                description: description,
                proposal-type: proposal-type,
                voting-start: voting-start,
                voting-end: voting-end,
                votes-for: u0,
                votes-against: u0,
                votes-abstain: u0,
                total-voting-power: u0,
                required-quorum: required-quorum,
                is-executed: false,
                is-emergency: is-emergency
            }))))

;; Vote on a proposal
(define-public (vote-on-proposal (proposal-id uint) (vote-type uint))
    (match (map-get? proposals proposal-id)
        proposal-data
        (match (map-get? stakeholders tx-sender)
            stakeholder-data
            (let ((voting-power (calculate-voting-power
                                (get stakeholder-type stakeholder-data)
                                (get stake-amount stakeholder-data)
                                (get reputation-score stakeholder-data)))
                  (vote-key {proposal-id: proposal-id, voter: tx-sender}))
                (asserts! (get is-active stakeholder-data) ERR_UNAUTHORIZED)
                (asserts! (<= block-height (get voting-end proposal-data)) ERR_VOTING_ENDED)
                (asserts! (>= block-height (get voting-start proposal-data)) ERR_VOTING_ACTIVE)
                (asserts! (is-none (map-get? votes vote-key)) ERR_ALREADY_VOTED)
                (asserts! (and (>= vote-type u1) (<= vote-type u3)) ERR_INVALID_PROPOSAL)
                
                ;; Record the vote
                (map-set votes vote-key
                    {
                        vote-type: vote-type,
                        voting-power: voting-power,
                        vote-height: block-height
                    })
                
                ;; Update proposal vote counts
                (map-set proposals proposal-id
                    (merge proposal-data
                        {
                            votes-for: (if (is-eq vote-type VOTE_FOR)
                                         (+ (get votes-for proposal-data) voting-power)
                                         (get votes-for proposal-data)),
                            votes-against: (if (is-eq vote-type VOTE_AGAINST)
                                             (+ (get votes-against proposal-data) voting-power)
                                             (get votes-against proposal-data)),
                            votes-abstain: (if (is-eq vote-type VOTE_ABSTAIN)
                                             (+ (get votes-abstain proposal-data) voting-power)
                                             (get votes-abstain proposal-data)),
                            total-voting-power: (+ (get total-voting-power proposal-data) voting-power)
                        }))
                (ok true))
            ERR_NOT_FOUND)
        ERR_NOT_FOUND))

;; Delegate voting power to another stakeholder
(define-public (delegate-voting-power (delegate-to principal) (duration uint))
    (begin
        (asserts! (is-valid-stakeholder tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-valid-stakeholder delegate-to) ERR_INVALID_STAKEHOLDER)
        (asserts! (not (is-eq tx-sender delegate-to)) ERR_INVALID_PROPOSAL)
        (let ((delegation-end (+ block-height duration)))
            (ok (map-set delegations tx-sender
                {
                    delegate-to: delegate-to,
                    delegation-start: block-height,
                    delegation-end: delegation-end,
                    is-active: true
                })))))

;; Execute a proposal (if it passed)
(define-public (execute-proposal (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal-data
        (let ((total-votes (+ (+ (get votes-for proposal-data)
                                 (get votes-against proposal-data))
                              (get votes-abstain proposal-data)))
              (approval-rate (if (> total-votes u0)
                               (/ (* (get votes-for proposal-data) u100) total-votes)
                               u0))
              (participation-rate (if (> (get total-voting-power proposal-data) u0)
                                    (/ (* total-votes u100) (get total-voting-power proposal-data))
                                    u0)))
            (asserts! (> block-height (get voting-end proposal-data)) ERR_VOTING_ACTIVE)
            (asserts! (not (get is-executed proposal-data)) ERR_ALREADY_EXISTS)
            (asserts! (>= participation-rate (get required-quorum proposal-data)) ERR_QUORUM_NOT_MET)
            (asserts! (> (get votes-for proposal-data) (get votes-against proposal-data)) ERR_UNAUTHORIZED)
            
            ;; Mark as executed
            (map-set proposals proposal-id
                (merge proposal-data {is-executed: true}))
            (ok true))
        ERR_NOT_FOUND))

;; Update governance parameter (only through governance)
(define-public (update-governance-param (param-name (string-ascii 50)) (new-value uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (ok (map-set governance-params param-name new-value))))

;; Emergency pause governance (only owner)
(define-public (pause-governance)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (ok (var-set governance-active false))))

;; Resume governance (only owner)
(define-public (resume-governance)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (ok (var-set governance-active true))))

;; Read-only Functions

;; Get stakeholder information
(define-read-only (get-stakeholder-info (address principal))
    (map-get? stakeholders address))

;; Get proposal information
(define-read-only (get-proposal-info (proposal-id uint))
    (map-get? proposals proposal-id))

;; Get vote information
(define-read-only (get-vote-info (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter}))

;; Get governance parameter
(define-read-only (get-governance-param (param-name (string-ascii 50)))
    (map-get? governance-params param-name))

;; Check if governance is active
(define-read-only (is-governance-active)
    (var-get governance-active))

;; Get current proposal counter
(define-read-only (get-proposal-counter)
    (var-get proposal-counter))

;; Calculate current voting power for an address
(define-read-only (get-voting-power (address principal))
    (match (map-get? stakeholders address)
        stakeholder-data
        (if (get is-active stakeholder-data)
            (some (calculate-voting-power
                   (get stakeholder-type stakeholder-data)
                   (get stake-amount stakeholder-data)
                   (get reputation-score stakeholder-data)))
            none)
        none))

;; Check if proposal has reached quorum and passed
(define-read-only (check-proposal-status (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal-data
        (let ((total-votes (+ (+ (get votes-for proposal-data)
                                 (get votes-against proposal-data))
                              (get votes-abstain proposal-data)))
              (participation-rate (if (> (get total-voting-power proposal-data) u0)
                                    (/ (* total-votes u100) (get total-voting-power proposal-data))
                                    u0))
              (passed (and (>= participation-rate (get required-quorum proposal-data))
                          (> (get votes-for proposal-data) (get votes-against proposal-data))
                          (> block-height (get voting-end proposal-data)))))
            (some {
                participation-rate: participation-rate,
                quorum-met: (>= participation-rate (get required-quorum proposal-data)),
                passed: passed,
                can-execute: (and passed (not (get is-executed proposal-data)))
            }))
        none))
