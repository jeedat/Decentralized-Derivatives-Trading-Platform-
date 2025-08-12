;; Decentralized Derivatives Trading Platform
;; Comprehensive on-chain functionality for decentralized derivatives trading
;; Includes margin management, automated settlement, access controls, and emergency functions
;; All critical blockchain-required functionality with proper security measures

;; ACCESS CONTROL

(define-constant platform-admin tx-sender)

;; ERROR CONSTANTS

(define-constant ERR-UNAUTHORIZED-USER (err u1000))
(define-constant ERR-INVALID-DERIVATIVE-ID (err u1001))
(define-constant ERR-DERIVATIVE-EXPIRED (err u1002))
(define-constant ERR-DERIVATIVE-ALREADY-SETTLED (err u1003))
(define-constant ERR-INSUFFICIENT-FUNDS (err u1004))
(define-constant ERR-INVALID-MATURITY (err u1005))
(define-constant ERR-INVALID-TARGET-PRICE (err u1006))
(define-constant ERR-NOT-POSITION-OWNER (err u1007))
(define-constant ERR-INVALID-FEE (err u1008))
(define-constant ERR-INVALID-POSITION-SIZE (err u1009))
(define-constant ERR-UNSUPPORTED-DERIVATIVE-TYPE (err u1010))
(define-constant ERR-INSUFFICIENT-MARGIN (err u1011))
(define-constant ERR-NOT-POSITION-CREATOR (err u1012))
(define-constant ERR-DERIVATIVE-NOT-FOUND (err u1013))
(define-constant ERR-PLATFORM-SUSPENDED (err u1014))
(define-constant ERR-INVALID-RATE (err u1015))
(define-constant ERR-MARGIN-FROZEN (err u1016))

;; DERIVATIVE TYPE CONSTANTS

(define-constant long-position-type u1)
(define-constant short-position-type u2)

;; DERIVATIVE STATUS CONSTANTS

(define-constant state-open u1)
(define-constant state-settled u2)
(define-constant state-matured u3)

;; PLATFORM LIMITS

(define-constant min-maturity-blocks u144) ;; ~24 hours
(define-constant max-maturity-blocks u52560) ;; ~1 year
(define-constant min-target-price u1000) ;; 0.001 STX
(define-constant max-target-price u100000000) ;; 100 STX
(define-constant min-position-size u1)
(define-constant max-position-size u1000000)

;; PLATFORM STATE

(define-data-var platform-suspended bool false)
(define-data-var critical-mode bool false)

;; CORE DATA STRUCTURES

;; Primary derivatives registry with margin tracking
(define-map derivatives-ledger
  { derivative-id: uint }
  {
    position-creator: principal,
    position-owner: principal,
    target-price: uint,
    fee-amount: uint,
    maturity-block: uint,
    derivative-type: uint,
    position-state: uint,
    position-size: uint,
    inception-block: uint,
    margin-amount: uint,
    margin-frozen: bool
  }
)

;; Creator margin tracking
(define-map creator-margins
  { creator: principal }
  { total-frozen: uint, available-funds: uint }
)

;; Derivative pricing feed (for automated settlement)
(define-map rate-feeds
  { feed-block: uint }
  { stx-rate: uint, timestamp: uint, reporter: principal }
)

;; Global derivative counter
(define-data-var next-derivative-id uint u1)

;; Platform fee settings
(define-data-var platform-commission-rate uint u100) ;; 1% = 100 basis points
(define-data-var commission-recipient principal tx-sender)

;; VALIDATION FUNCTIONS

(define-private (is-valid-derivative-id (derivative-id uint))
  (and (> derivative-id u0) (< derivative-id (var-get next-derivative-id)))
)

(define-private (is-valid-derivative-type (derivative-type uint))
  (or (is-eq derivative-type long-position-type) (is-eq derivative-type short-position-type))
)

(define-private (is-derivative-active (derivative-data (tuple 
    (position-creator principal) (position-owner principal) (target-price uint)
    (fee-amount uint) (maturity-block uint) (derivative-type uint)
    (position-state uint) (position-size uint) (inception-block uint)
    (margin-amount uint) (margin-frozen bool))))
  (and 
    (< block-height (get maturity-block derivative-data))
    (is-eq (get position-state derivative-data) state-open)
  )
)

;; Fixed margin calculation with proper validation
(define-private (calculate-required-margin (derivative-type uint) (target-price uint) (position-size uint))
  (begin
    ;; These inputs should already be validated before this function is called
    ;; This function now assumes validated inputs
    (if (is-eq derivative-type long-position-type)
      ;; Long position: margin = position-size * target-price (for covered longs)
      (* position-size target-price)
      ;; Short position: margin = position-size * target-price (cash-secured shorts)
      (* position-size target-price)
    )
  )
)

(define-private (calculate-platform-commission (fee-amount uint))
  (/ (* fee-amount (var-get platform-commission-rate)) u10000)
)

;; ACCESS CONTROL FUNCTIONS

(define-private (is-platform-admin)
  (is-eq tx-sender platform-admin)
)

(define-private (check-not-suspended)
  (not (var-get platform-suspended))
)

;; MARGIN MANAGEMENT

(define-public (deposit-margin (amount uint))
  (begin
    (asserts! (check-not-suspended) ERR-PLATFORM-SUSPENDED)
    (asserts! (> amount u0) ERR-INVALID-RATE)
    
    ;; Transfer margin to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update margin tracking
    (let ((current-margin (default-to { total-frozen: u0, available-funds: u0 } 
                                      (map-get? creator-margins { creator: tx-sender }))))
      (map-set creator-margins
        { creator: tx-sender }
        { 
          total-frozen: (get total-frozen current-margin),
          available-funds: (+ (get available-funds current-margin) amount)
        }
      )
    )
    
    (ok true)
  )
)

(define-public (withdraw-margin (amount uint))
  (begin
    (asserts! (check-not-suspended) ERR-PLATFORM-SUSPENDED)
    (asserts! (> amount u0) ERR-INVALID-RATE)
    
    (let ((margin-data (unwrap! (map-get? creator-margins { creator: tx-sender }) 
                                ERR-INSUFFICIENT-MARGIN)))
      
      ;; Check available balance
      (asserts! (>= (get available-funds margin-data) amount) ERR-INSUFFICIENT-MARGIN)
      
      ;; Transfer margin back to user
      (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
      
      ;; Update margin tracking
      (map-set creator-margins
        { creator: tx-sender }
        { 
          total-frozen: (get total-frozen margin-data),
          available-funds: (- (get available-funds margin-data) amount)
        }
      )
      
      (ok true)
    )
  )
)

;; READ-ONLY FUNCTIONS

(define-read-only (get-derivative-details (derivative-id uint))
  (begin
    (asserts! (is-valid-derivative-id derivative-id) ERR-INVALID-DERIVATIVE-ID)
    (ok (map-get? derivatives-ledger { derivative-id: derivative-id }))
  )
)

(define-read-only (get-creator-margin (creator principal))
  (map-get? creator-margins { creator: creator })
)

(define-read-only (get-platform-configuration)
  {
    platform-suspended: (var-get platform-suspended),
    critical-mode: (var-get critical-mode),
    platform-commission-rate: (var-get platform-commission-rate),
    next-derivative-id: (var-get next-derivative-id)
  }
)

(define-read-only (get-rate-feed (feed-block uint))
  (map-get? rate-feeds { feed-block: feed-block })
)

;; DERIVATIVE CREATION WITH PROPER INPUT VALIDATION

(define-public (create-derivative-position 
    (target-price uint)
    (fee-amount uint)
    (maturity-block uint)
    (derivative-type uint)
    (position-size uint))
  (let ((new-derivative-id (var-get next-derivative-id)))
    
    ;; Platform state checks
    (asserts! (check-not-suspended) ERR-PLATFORM-SUSPENDED)
    
    ;; Input validation BEFORE any calculations
    (asserts! (and (>= target-price min-target-price) (<= target-price max-target-price)) ERR-INVALID-TARGET-PRICE)
    (asserts! (> fee-amount u0) ERR-INVALID-FEE)
    (asserts! (and (>= position-size min-position-size) (<= position-size max-position-size)) ERR-INVALID-POSITION-SIZE)
    (asserts! (and 
               (> maturity-block (+ block-height min-maturity-blocks))
               (< maturity-block (+ block-height max-maturity-blocks))
              ) ERR-INVALID-MATURITY)
    (asserts! (is-valid-derivative-type derivative-type) ERR-UNSUPPORTED-DERIVATIVE-TYPE)
    
    ;; Now calculate required margin with validated inputs
    (let ((required-margin (calculate-required-margin derivative-type target-price position-size)))
      
      (asserts! (> required-margin u0) ERR-INSUFFICIENT-MARGIN)
      
      ;; Check margin availability
      (let ((creator-margin-data (unwrap! (map-get? creator-margins { creator: tx-sender }) 
                                          ERR-INSUFFICIENT-MARGIN)))
        (asserts! (>= (get available-funds creator-margin-data) required-margin) ERR-INSUFFICIENT-MARGIN)
        
        ;; Lock margin
        (map-set creator-margins
          { creator: tx-sender }
          { 
            total-frozen: (+ (get total-frozen creator-margin-data) required-margin),
            available-funds: (- (get available-funds creator-margin-data) required-margin)
          }
        )
      )
      
      ;; Create derivative position
      (map-set derivatives-ledger
        { derivative-id: new-derivative-id }
        {
          position-creator: tx-sender,
          position-owner: tx-sender,
          target-price: target-price,
          fee-amount: fee-amount,
          maturity-block: maturity-block,
          derivative-type: derivative-type,
          position-state: state-open,
          position-size: position-size,
          inception-block: block-height,
          margin-amount: required-margin,
          margin-frozen: true
        }
      )
      
      ;; Increment counter
      (var-set next-derivative-id (+ new-derivative-id u1))
      
      (ok new-derivative-id)
    )
  )
)

;; DERIVATIVE TRANSFER

(define-public (transfer-position (derivative-id uint) (new-owner principal))
  (begin
    (asserts! (check-not-suspended) ERR-PLATFORM-SUSPENDED)
    (asserts! (is-valid-derivative-id derivative-id) ERR-INVALID-DERIVATIVE-ID)
    
    (let ((derivative-data (unwrap! (map-get? derivatives-ledger { derivative-id: derivative-id }) 
                                    ERR-DERIVATIVE-NOT-FOUND)))
      
      ;; Validation
      (asserts! (is-derivative-active derivative-data) ERR-DERIVATIVE-EXPIRED)
      (asserts! (is-eq (get position-owner derivative-data) tx-sender) ERR-NOT-POSITION-OWNER)
      
      ;; Transfer ownership
      (map-set derivatives-ledger
        { derivative-id: derivative-id }
        (merge derivative-data { position-owner: new-owner })
      )
      
      (ok true)
    )
  )
)

;; DERIVATIVE PURCHASE WITH FEES

(define-public (purchase-position (derivative-id uint))
  (begin
    (asserts! (check-not-suspended) ERR-PLATFORM-SUSPENDED)
    (asserts! (is-valid-derivative-id derivative-id) ERR-INVALID-DERIVATIVE-ID)
    
    (let ((derivative-data (unwrap! (map-get? derivatives-ledger { derivative-id: derivative-id }) 
                                    ERR-DERIVATIVE-NOT-FOUND))
          (platform-commission (calculate-platform-commission (get fee-amount derivative-data))))
      
      ;; Validation
      (asserts! (is-derivative-active derivative-data) ERR-DERIVATIVE-EXPIRED)
      (asserts! (is-eq (get position-creator derivative-data) (get position-owner derivative-data)) ERR-UNAUTHORIZED-USER)
      
      ;; Fee payment to creator
      (try! (stx-transfer? (- (get fee-amount derivative-data) platform-commission) tx-sender (get position-creator derivative-data)))
      
      ;; Platform commission payment
      (if (> platform-commission u0)
        (try! (stx-transfer? platform-commission tx-sender (var-get commission-recipient)))
        true
      )
      
      ;; Transfer ownership
      (map-set derivatives-ledger
        { derivative-id: derivative-id }
        (merge derivative-data { position-owner: tx-sender })
      )
      
      (ok true)
    )
  )
)

;; DERIVATIVE EXERCISE WITH MARGIN RELEASE

(define-public (settle-long-position (derivative-id uint))
  (begin
    (asserts! (check-not-suspended) ERR-PLATFORM-SUSPENDED)
    (asserts! (is-valid-derivative-id derivative-id) ERR-INVALID-DERIVATIVE-ID)
    
    (let ((derivative-data (unwrap! (map-get? derivatives-ledger { derivative-id: derivative-id }) 
                                    ERR-DERIVATIVE-NOT-FOUND))
          (settlement-cost (* (get target-price derivative-data) (get position-size derivative-data))))
      
      ;; Validation
      (asserts! (is-derivative-active derivative-data) ERR-DERIVATIVE-EXPIRED)
      (asserts! (is-eq (get derivative-type derivative-data) long-position-type) ERR-UNSUPPORTED-DERIVATIVE-TYPE)
      (asserts! (is-eq (get position-owner derivative-data) tx-sender) ERR-NOT-POSITION-OWNER)
      
      ;; Settlement payment to creator
      (try! (stx-transfer? settlement-cost tx-sender (get position-creator derivative-data)))
      
      ;; Release margin back to creator
      (let ((creator-margin-data (unwrap! (map-get? creator-margins { creator: (get position-creator derivative-data) }) 
                                          ERR-INSUFFICIENT-MARGIN)))
        (map-set creator-margins
          { creator: (get position-creator derivative-data) }
          { 
            total-frozen: (- (get total-frozen creator-margin-data) (get margin-amount derivative-data)),
            available-funds: (+ (get available-funds creator-margin-data) (get margin-amount derivative-data))
          }
        )
      )
      
      ;; Mark as settled
      (map-set derivatives-ledger
        { derivative-id: derivative-id }
        (merge derivative-data { position-state: state-settled, margin-frozen: false })
      )
      
      (ok true)
    )
  )
)

(define-public (settle-short-position (derivative-id uint))
  (begin
    (asserts! (check-not-suspended) ERR-PLATFORM-SUSPENDED)
    (asserts! (is-valid-derivative-id derivative-id) ERR-INVALID-DERIVATIVE-ID)
    
    (let ((derivative-data (unwrap! (map-get? derivatives-ledger { derivative-id: derivative-id }) 
                                    ERR-DERIVATIVE-NOT-FOUND))
          (payout-amount (* (get target-price derivative-data) (get position-size derivative-data))))
      
      ;; Validation
      (asserts! (is-derivative-active derivative-data) ERR-DERIVATIVE-EXPIRED)
      (asserts! (is-eq (get derivative-type derivative-data) short-position-type) ERR-UNSUPPORTED-DERIVATIVE-TYPE)
      (asserts! (is-eq (get position-owner derivative-data) tx-sender) ERR-NOT-POSITION-OWNER)
      
      ;; Payout from locked margin to owner
      (try! (as-contract (stx-transfer? payout-amount tx-sender tx-sender)))
      
      ;; Update margin (remaining goes back to creator)
      (let ((creator-margin-data (unwrap! (map-get? creator-margins { creator: (get position-creator derivative-data) }) 
                                          ERR-INSUFFICIENT-MARGIN))
            (remaining-margin (- (get margin-amount derivative-data) payout-amount)))
        (map-set creator-margins
          { creator: (get position-creator derivative-data) }
          { 
            total-frozen: (- (get total-frozen creator-margin-data) (get margin-amount derivative-data)),
            available-funds: (+ (get available-funds creator-margin-data) remaining-margin)
          }
        )
      )
      
      ;; Mark as settled
      (map-set derivatives-ledger
        { derivative-id: derivative-id }
        (merge derivative-data { position-state: state-settled, margin-frozen: false })
      )
      
      (ok true)
    )
  )
)

;; AUTOMATED SETTLEMENT WITH MARGIN RELEASE

(define-public (settle-matured-position (derivative-id uint))
  (begin
    (asserts! (is-valid-derivative-id derivative-id) ERR-INVALID-DERIVATIVE-ID)
    
    (let ((derivative-data (unwrap! (map-get? derivatives-ledger { derivative-id: derivative-id }) 
                                    ERR-DERIVATIVE-NOT-FOUND)))
      
      ;; Validation
      (asserts! (>= block-height (get maturity-block derivative-data)) ERR-UNAUTHORIZED-USER)
      (asserts! (is-eq (get position-state derivative-data) state-open) ERR-DERIVATIVE-ALREADY-SETTLED)
      
      ;; Release margin back to creator
      (if (get margin-frozen derivative-data)
        (let ((creator-margin-data (unwrap! (map-get? creator-margins { creator: (get position-creator derivative-data) }) 
                                            ERR-INSUFFICIENT-MARGIN)))
          (map-set creator-margins
            { creator: (get position-creator derivative-data) }
            { 
              total-frozen: (- (get total-frozen creator-margin-data) (get margin-amount derivative-data)),
              available-funds: (+ (get available-funds creator-margin-data) (get margin-amount derivative-data))
            }
          )
        )
        true
      )
      
      ;; Mark as matured
      (map-set derivatives-ledger
        { derivative-id: derivative-id }
        (merge derivative-data { position-state: state-matured, margin-frozen: false })
      )
      
      (ok true)
    )
  )
)

;; PRICE FEED MANAGEMENT (For automated settlement)

(define-public (update-rate-feed (stx-rate uint))
  (begin
    (asserts! (> stx-rate u0) ERR-INVALID-RATE)
    
    (map-set rate-feeds
      { feed-block: block-height }
      { stx-rate: stx-rate, timestamp: block-height, reporter: tx-sender }
    )
    
    (ok true)
  )
)

;; ADMIN FUNCTIONS

(define-public (suspend-platform)
  (begin
    (asserts! (is-platform-admin) ERR-UNAUTHORIZED-USER)
    (var-set platform-suspended true)
    (ok true)
  )
)

(define-public (resume-platform)
  (begin
    (asserts! (is-platform-admin) ERR-UNAUTHORIZED-USER)
    (var-set platform-suspended false)
    (ok true)
  )
)

(define-public (set-platform-commission (new-commission-rate uint))
  (begin
    (asserts! (is-platform-admin) ERR-UNAUTHORIZED-USER)
    (asserts! (<= new-commission-rate u1000) ERR-INVALID-RATE) ;; Max 10%
    (var-set platform-commission-rate new-commission-rate)
    (ok true)
  )
)

(define-public (activate-critical-mode)
  (begin
    (asserts! (is-platform-admin) ERR-UNAUTHORIZED-USER)
    (var-set critical-mode true)
    (var-set platform-suspended true)
    (ok true)
  )
)

;; CONTRACT INITIALIZATION

(begin
  (print "Complete Decentralized Derivatives Trading Platform Deployed")
  (var-get next-derivative-id)
)