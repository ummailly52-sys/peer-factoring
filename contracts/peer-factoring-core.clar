;; Peer Factoring Core Contract
;; Main contract for peer-to-peer invoice factoring with advanced features
;; Handles investor matching, payments, disputes, and portfolio management

;; Import invoice-manager contract
;; (use-trait invoice-manager-trait .invoice-manager)

;; Define constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_AMOUNT (err u402))
(define-constant ERR_INSUFFICIENT_FUNDS (err u403))
(define-constant ERR_INVOICE_NOT_FOUND (err u404))
(define-constant ERR_INVOICE_NOT_AVAILABLE (err u405))
(define-constant ERR_ALREADY_PURCHASED (err u406))
(define-constant ERR_PAYMENT_NOT_DUE (err u407))
(define-constant ERR_PAYMENT_OVERDUE (err u408))
(define-constant ERR_DISPUTE_EXISTS (err u409))
(define-constant ERR_INVALID_DISPUTE (err u410))
(define-constant ERR_ESCROW_ERROR (err u411))
(define-constant ERR_TRANSFER_FAILED (err u412))
(define-constant ERR_INVALID_INVESTOR (err u413))
(define-constant ERR_DIVERSIFICATION_LIMIT (err u414))

;; System configuration
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points
(define-data-var max-investment-per-invoice uint u50000000000) ;; 50,000 STX
(define-data-var min-investor-balance uint u10000000) ;; 10 STX minimum
(define-data-var dispute-resolution-period uint u1008) ;; ~1 week in blocks
(define-data-var auto-collection-enabled bool true)
(define-data-var system-active bool true)

;; Platform stats
(define-data-var total-volume uint u0)
(define-data-var total-invoices-processed uint u0)
(define-data-var total-platform-fees uint u0)
(define-data-var active-investors uint u0)

;; Investment tracking
(define-map investor-portfolios
  { investor: principal }
  {
    total-invested: uint,
    total-collected: uint,
    active-investments: uint,
    roi-percentage: uint,
    last-activity: uint,
    risk-score: uint
  }
)

;; Invoice purchase records
(define-map invoice-purchases
  { invoice-id: uint }
  {
    investor: principal,
    purchase-price: uint,
    platform-fee: uint,
    purchased-at: uint,
    collection-status: uint,
    collected-amount: uint,
    dispute-id: (optional uint)
  }
)

;; Escrow accounts for pending transactions
(define-map escrow-accounts
  { transaction-id: uint }
  {
    holder: principal,
    amount: uint,
    purpose: (string-ascii 64),
    created-at: uint,
    release-height: uint,
    released: bool
  }
)

;; Dispute management
(define-map disputes
  { dispute-id: uint }
  {
    invoice-id: uint,
    initiator: principal,
    respondent: principal,
    dispute-type: uint,
    description: (string-ascii 512),
    status: uint,
    created-at: uint,
    resolution: (optional (string-ascii 512)),
    resolved-at: (optional uint)
  }
)

(define-data-var dispute-nonce uint u0)
(define-data-var escrow-nonce uint u0)

;; Collection status constants
(define-constant COLLECTION_PENDING u0)
(define-constant COLLECTION_PARTIAL u1)
(define-constant COLLECTION_COMPLETE u2)
(define-constant COLLECTION_DEFAULTED u3)
(define-constant COLLECTION_DISPUTED u4)

;; Dispute type constants
(define-constant DISPUTE_NON_PAYMENT u0)
(define-constant DISPUTE_PARTIAL_PAYMENT u1)
(define-constant DISPUTE_QUALITY_ISSUE u2)
(define-constant DISPUTE_FRAUDULENT_INVOICE u3)

;; Dispute status constants
(define-constant DISPUTE_STATUS_OPEN u0)
(define-constant DISPUTE_STATUS_INVESTIGATING u1)
(define-constant DISPUTE_STATUS_RESOLVED u2)
(define-constant DISPUTE_STATUS_CLOSED u3)

;; Read-only functions

;; Get investor portfolio
(define-read-only (get-investor-portfolio (investor principal))
  (default-to 
    {
      total-invested: u0,
      total-collected: u0,
      active-investments: u0,
      roi-percentage: u0,
      last-activity: u0,
      risk-score: u0
    }
    (map-get? investor-portfolios { investor: investor })
  )
)

;; Get invoice purchase details
(define-read-only (get-invoice-purchase (invoice-id uint))
  (map-get? invoice-purchases { invoice-id: invoice-id })
)

;; Get dispute details
(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes { dispute-id: dispute-id })
)

;; Calculate expected return on investment
(define-read-only (calculate-expected-roi (purchase-price uint) (face-value uint))
  (if (> face-value purchase-price)
    (/ (* (- face-value purchase-price) u10000) purchase-price)
    u0
  )
)

;; Get platform statistics
(define-read-only (get-platform-stats)
  {
    total-volume: (var-get total-volume),
    total-invoices-processed: (var-get total-invoices-processed),
    total-platform-fees: (var-get total-platform-fees),
    active-investors: (var-get active-investors),
    platform-fee-rate: (var-get platform-fee-rate)
  }
)

;; Check if investor meets diversification requirements
(define-read-only (check-diversification-limit (investor principal) (investment-amount uint))
  (let (
    (portfolio (get-investor-portfolio investor))
    (total-invested (get total-invested portfolio))
    (proposed-total (+ total-invested investment-amount))
  )
    (<= investment-amount (/ proposed-total u10)) ;; Max 10% in single invoice
  )
)

;; Validate investor eligibility
(define-read-only (is-eligible-investor (investor principal))
  (>= (stx-get-balance investor) (var-get min-investor-balance))
)

;; Check if system is active
(define-read-only (is-system-active)
  (var-get system-active)
)

;; Public functions

;; Purchase invoice with comprehensive validation
(define-public (purchase-invoice (invoice-id uint))
  (begin
    ;; System checks first
    (asserts! (var-get system-active) ERR_UNAUTHORIZED)
    
    (let (
      (invoice-data (unwrap! (contract-call? .invoice-manager get-invoice invoice-id) ERR_INVOICE_NOT_FOUND))
      (buyer tx-sender)
      (invoice-amount (get amount invoice-data))
      (discount-rate (get discount-rate invoice-data))
      (purchase-price (contract-call? .invoice-manager calculate-discount-price invoice-amount discount-rate))
      (platform-fee (/ (* purchase-price (var-get platform-fee-rate)) u10000))
      (total-cost (+ purchase-price platform-fee))
    )
      ;; Investor eligibility
      (asserts! (is-eligible-investor buyer) ERR_INVALID_INVESTOR)
      (asserts! (check-diversification-limit buyer purchase-price) ERR_DIVERSIFICATION_LIMIT)
      
      ;; Invoice availability
      (asserts! (contract-call? .invoice-manager is-invoice-available invoice-id) ERR_INVOICE_NOT_AVAILABLE)
      (asserts! (is-none (get-invoice-purchase invoice-id)) ERR_ALREADY_PURCHASED)
      
      ;; Financial checks
      (asserts! (>= (stx-get-balance buyer) total-cost) ERR_INSUFFICIENT_FUNDS)
      (asserts! (<= purchase-price (var-get max-investment-per-invoice)) ERR_INVALID_AMOUNT)
      
      ;; Transfer payment to contract (escrow)
      (try! (stx-transfer? total-cost buyer (as-contract tx-sender)))
      
      ;; Mark invoice as sold
      (try! (contract-call? .invoice-manager mark-invoice-sold invoice-id buyer purchase-price))
      
      ;; Record purchase
      (map-set invoice-purchases
        { invoice-id: invoice-id }
        {
          investor: buyer,
          purchase-price: purchase-price,
          platform-fee: platform-fee,
          purchased-at: stacks-block-height,
          collection-status: COLLECTION_PENDING,
          collected-amount: u0,
          dispute-id: none
        }
      )
      
      ;; Transfer payment to seller (minus platform fee)
      (try! (as-contract (stx-transfer? purchase-price tx-sender (get seller invoice-data))))
      
      ;; Update investor portfolio
      (update-investor-portfolio buyer purchase-price u0)
      
      ;; Update platform stats
      (var-set total-volume (+ (var-get total-volume) purchase-price))
      (var-set total-invoices-processed (+ (var-get total-invoices-processed) u1))
      (var-set total-platform-fees (+ (var-get total-platform-fees) platform-fee))
      
      (ok invoice-id)
    )
  )
)

;; Process debtor payment
(define-public (process-payment (invoice-id uint) (payment-amount uint))
  (let (
    (purchase-data (unwrap! (get-invoice-purchase invoice-id) ERR_INVOICE_NOT_FOUND))
    (invoice-data (unwrap! (contract-call? .invoice-manager get-invoice invoice-id) ERR_INVOICE_NOT_FOUND))
    (investor (get investor purchase-data))
    (invoice-amount (get amount invoice-data))
    (debtor (get debtor invoice-data))
  )
    ;; Verify payment comes from debtor
    (asserts! (is-eq tx-sender debtor) ERR_UNAUTHORIZED)
    
    ;; Verify payment amount
    (asserts! (> payment-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= payment-amount invoice-amount) ERR_INVALID_AMOUNT)
    
    ;; Transfer payment to investor
    (try! (stx-transfer? payment-amount debtor investor))
    
    ;; Update collection status
    (let (
      (new-collected-amount (+ (get collected-amount purchase-data) payment-amount))
      (new-status (if (>= new-collected-amount invoice-amount)
                     COLLECTION_COMPLETE
                     COLLECTION_PARTIAL))
    )
      (map-set invoice-purchases
        { invoice-id: invoice-id }
        (merge purchase-data {
          collection-status: new-status,
          collected-amount: new-collected-amount
        })
      )
      
      ;; Update investor portfolio
      (update-investor-portfolio investor u0 payment-amount)
      
      ;; Update invoice status if complete
      (try! (if (is-eq new-status COLLECTION_COMPLETE)
        (contract-call? .invoice-manager update-invoice-status invoice-id u3)
        (ok true)
      ))
    )
    
    (ok payment-amount)
  )
)

;; Initiate dispute
(define-public (initiate-dispute 
  (invoice-id uint) 
  (dispute-type uint)
  (description (string-ascii 512))
)
  (let (
    (dispute-id (+ (var-get dispute-nonce) u1))
    (purchase-data (unwrap! (get-invoice-purchase invoice-id) ERR_INVOICE_NOT_FOUND))
    (invoice-data (unwrap! (contract-call? .invoice-manager get-invoice invoice-id) ERR_INVOICE_NOT_FOUND))
    (initiator tx-sender)
  )
    ;; Verify initiator is investor or debtor
    (asserts! (or (is-eq initiator (get investor purchase-data))
                  (is-eq initiator (get debtor invoice-data))) ERR_UNAUTHORIZED)
    
    ;; Check no existing dispute
    (asserts! (is-none (get dispute-id purchase-data)) ERR_DISPUTE_EXISTS)
    
    ;; Validate dispute type
    (asserts! (<= dispute-type DISPUTE_FRAUDULENT_INVOICE) ERR_INVALID_DISPUTE)
    
    ;; Create dispute
    (map-set disputes
      { dispute-id: dispute-id }
      {
        invoice-id: invoice-id,
        initiator: initiator,
        respondent: (if (is-eq initiator (get investor purchase-data))
                       (get debtor invoice-data)
                       (get investor purchase-data)),
        dispute-type: dispute-type,
        description: description,
        status: DISPUTE_STATUS_OPEN,
        created-at: stacks-block-height,
        resolution: none,
        resolved-at: none
      }
    )
    
    ;; Update purchase record
    (map-set invoice-purchases
      { invoice-id: invoice-id }
      (merge purchase-data {
        collection-status: COLLECTION_DISPUTED,
        dispute-id: (some dispute-id)
      })
    )
    
    ;; Update dispute nonce
    (var-set dispute-nonce dispute-id)
    
    (ok dispute-id)
  )
)

;; Resolve dispute (admin function)
(define-public (resolve-dispute 
  (dispute-id uint) 
  (resolution (string-ascii 512))
  (refund-amount uint)
)
  (let (
    (dispute-data (unwrap! (get-dispute dispute-id) ERR_INVALID_DISPUTE))
    (invoice-id (get invoice-id dispute-data))
    (purchase-data (unwrap! (get-invoice-purchase invoice-id) ERR_INVOICE_NOT_FOUND))
  )
    ;; Only contract owner can resolve disputes
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    ;; Verify dispute is open
    (asserts! (is-eq (get status dispute-data) DISPUTE_STATUS_OPEN) ERR_INVALID_DISPUTE)
    
    ;; Process refund if applicable
    (try! (if (> refund-amount u0)
      (as-contract (stx-transfer? refund-amount tx-sender (get investor purchase-data)))
      (ok true)
    ))
    
    ;; Update dispute status
    (map-set disputes
      { dispute-id: dispute-id }
      (merge dispute-data {
        status: DISPUTE_STATUS_RESOLVED,
        resolution: (some resolution),
        resolved-at: (some stacks-block-height)
      })
    )
    
    ;; Update collection status
    (map-set invoice-purchases
      { invoice-id: invoice-id }
      (merge purchase-data {
        collection-status: COLLECTION_COMPLETE
      })
    )
    
    (ok true)
  )
)

;; Emergency functions

;; Pause system (emergency)
(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set system-active false)
    (ok true)
  )
)

;; Resume system
(define-public (resume-system)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set system-active true)
    (ok true)
  )
)

;; Private helper functions

;; Create escrow account
(define-private (create-escrow-account 
  (transaction-id uint) 
  (holder principal) 
  (amount uint) 
  (purpose (string-ascii 64))
  (release-delay uint)
)
  (let (
    (release-height (+ stacks-block-height release-delay))
  )
    (map-set escrow-accounts
      { transaction-id: transaction-id }
      {
        holder: holder,
        amount: amount,
        purpose: purpose,
        created-at: stacks-block-height,
        release-height: release-height,
        released: false
      }
    )
    (var-set escrow-nonce transaction-id)
    (ok transaction-id)
  )
)

;; Release escrow
(define-private (release-escrow (transaction-id uint))
  (let (
    (escrow-data (unwrap! (map-get? escrow-accounts { transaction-id: transaction-id }) ERR_ESCROW_ERROR))
  )
    (asserts! (not (get released escrow-data)) ERR_ESCROW_ERROR)
    (asserts! (>= stacks-block-height (get release-height escrow-data)) ERR_ESCROW_ERROR)
    
    (map-set escrow-accounts
      { transaction-id: transaction-id }
      (merge escrow-data { released: true })
    )
    (ok true)
  )
)

;; Update investor portfolio
(define-private (update-investor-portfolio (investor principal) (invested uint) (collected uint))
  (let (
    (current-portfolio (get-investor-portfolio investor))
    (new-total-invested (+ (get total-invested current-portfolio) invested))
    (new-total-collected (+ (get total-collected current-portfolio) collected))
    (new-active (if (> invested u0) 
                   (+ (get active-investments current-portfolio) u1)
                   (get active-investments current-portfolio)))
  )
    (map-set investor-portfolios
      { investor: investor }
      {
        total-invested: new-total-invested,
        total-collected: new-total-collected,
        active-investments: new-active,
        roi-percentage: (if (> new-total-invested u0)
                          (/ (* new-total-collected u10000) new-total-invested)
                          u0),
        last-activity: stacks-block-height,
        risk-score: (calculate-risk-score investor)
      }
    )
  )
)

;; Calculate investor risk score (simplified)
(define-private (calculate-risk-score (investor principal))
  (let (
    (portfolio (get-investor-portfolio investor))
    (total-invested (get total-invested portfolio))
    (total-collected (get total-collected portfolio))
  )
    ;; Simple risk score based on collection rate
    (if (> total-invested u0)
      (/ (* total-collected u100) total-invested)
      u50 ;; Default neutral score
    )
  )
)

