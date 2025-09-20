;; Invoice Manager Contract
;; Manages invoice creation, validation, and basic operations for peer factoring

;; Define constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_AMOUNT (err u402))
(define-constant ERR_INVALID_DISCOUNT (err u403))
(define-constant ERR_INVOICE_NOT_FOUND (err u404))
(define-constant ERR_INVOICE_ALREADY_SOLD (err u405))
(define-constant ERR_INVALID_STATUS (err u406))
(define-constant ERR_INSUFFICIENT_TIME (err u407))
(define-constant ERR_INVALID_DEBTOR (err u408))

;; Define data variables
(define-data-var invoice-nonce uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points
(define-data-var min-invoice-amount uint u1000000000) ;; 1000 STX in microSTX
(define-data-var max-discount-rate uint u2500) ;; 25% in basis points
(define-data-var grace-period-days uint u7)

;; Invoice status enum
(define-constant STATUS_PENDING u0)
(define-constant STATUS_AVAILABLE u1)
(define-constant STATUS_SOLD u2)
(define-constant STATUS_PAID u3)
(define-constant STATUS_OVERDUE u4)
(define-constant STATUS_DISPUTED u5)
(define-constant STATUS_CANCELLED u6)

;; Invoice data structure
(define-map invoices
  { invoice-id: uint }
  {
    seller: principal,
    debtor: principal,
    amount: uint,
    discount-rate: uint,
    due-date: uint,
    created-at: uint,
    status: uint,
    description: (string-ascii 256),
    buyer: (optional principal),
    purchase-price: (optional uint),
    purchased-at: (optional uint)
  }
)

;; Seller invoice tracking
(define-map seller-invoices
  { seller: principal }
  { invoice-ids: (list 100 uint) }
)

;; Debtor invoice tracking
(define-map debtor-invoices
  { debtor: principal }
  { invoice-ids: (list 100 uint) }
)

;; Available invoices for purchase
(define-map available-invoices-map
  { status: uint }
  { invoice-ids: (list 1000 uint) }
)

;; Read-only functions

;; Get invoice details
(define-read-only (get-invoice (invoice-id uint))
  (map-get? invoices { invoice-id: invoice-id })
)

;; Get current invoice nonce
(define-read-only (get-invoice-nonce)
  (var-get invoice-nonce)
)

;; Get platform fee rate
(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)

;; Calculate platform fee
(define-read-only (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-rate)) u10000)
)

;; Calculate discounted price
(define-read-only (calculate-discount-price (amount uint) (discount-rate uint))
  (let (
    (discount-amount (/ (* amount discount-rate) u10000))
  )
    (- amount discount-amount)
  )
)

;; Get seller invoices
(define-read-only (get-seller-invoices (seller principal))
  (default-to 
    { invoice-ids: (list) }
    (map-get? seller-invoices { seller: seller })
  )
)

;; Get debtor invoices
(define-read-only (get-debtor-invoices (debtor principal))
  (default-to 
    { invoice-ids: (list) }
    (map-get? debtor-invoices { debtor: debtor })
  )
)

;; Check if invoice is available for purchase
(define-read-only (is-invoice-available (invoice-id uint))
  (match (get-invoice invoice-id)
    invoice-data (is-eq (get status invoice-data) STATUS_AVAILABLE)
    false
  )
)

;; Check if invoice is overdue
(define-read-only (is-invoice-overdue (invoice-id uint))
  (match (get-invoice invoice-id)
    invoice-data 
    (let (
      (current-height stacks-block-height)
      (due-height (get due-date invoice-data))
      (grace-period (* (var-get grace-period-days) u144)) ;; ~144 blocks per day
    )
      (> current-height (+ due-height grace-period))
    )
    false
  )
)

;; Validate invoice amount
(define-read-only (is-valid-amount (amount uint))
  (>= amount (var-get min-invoice-amount))
)

;; Validate discount rate
(define-read-only (is-valid-discount-rate (discount-rate uint))
  (and (> discount-rate u0) (<= discount-rate (var-get max-discount-rate)))
)

;; Public functions

;; Create new invoice
(define-public (create-invoice 
  (debtor principal) 
  (amount uint) 
  (discount-rate uint)
  (days-until-due uint)
  (description (string-ascii 256))
)
  (let (
    (invoice-id (+ (var-get invoice-nonce) u1))
    (current-height stacks-block-height)
    (due-date (+ current-height (* days-until-due u144))) ;; ~144 blocks per day
    (seller tx-sender)
  )
    ;; Validation
    (asserts! (is-valid-amount amount) ERR_INVALID_AMOUNT)
    (asserts! (is-valid-discount-rate discount-rate) ERR_INVALID_DISCOUNT)
    (asserts! (> days-until-due u0) ERR_INSUFFICIENT_TIME)
    (asserts! (not (is-eq seller debtor)) ERR_INVALID_DEBTOR)
    
    ;; Create invoice
    (map-set invoices
      { invoice-id: invoice-id }
      {
        seller: seller,
        debtor: debtor,
        amount: amount,
        discount-rate: discount-rate,
        due-date: due-date,
        created-at: current-height,
        status: STATUS_PENDING,
        description: description,
        buyer: none,
        purchase-price: none,
        purchased-at: none
      }
    )
    
    ;; Update seller tracking
    (update-seller-invoices seller invoice-id)
    
    ;; Update debtor tracking
    (update-debtor-invoices debtor invoice-id)
    
    ;; Update nonce
    (var-set invoice-nonce invoice-id)
    
    (ok invoice-id)
  )
)

;; Make invoice available for purchase
(define-public (make-invoice-available (invoice-id uint))
  (let (
    (invoice-data (unwrap! (get-invoice invoice-id) ERR_INVOICE_NOT_FOUND))
  )
    ;; Only seller can make available
    (asserts! (is-eq tx-sender (get seller invoice-data)) ERR_UNAUTHORIZED)
    ;; Must be in pending status
    (asserts! (is-eq (get status invoice-data) STATUS_PENDING) ERR_INVALID_STATUS)
    
    ;; Update status
    (map-set invoices
      { invoice-id: invoice-id }
      (merge invoice-data { status: STATUS_AVAILABLE })
    )
    
    (ok true)
  )
)

;; Cancel invoice (only by seller, only if not sold)
(define-public (cancel-invoice (invoice-id uint))
  (let (
    (invoice-data (unwrap! (get-invoice invoice-id) ERR_INVOICE_NOT_FOUND))
  )
    ;; Only seller can cancel
    (asserts! (is-eq tx-sender (get seller invoice-data)) ERR_UNAUTHORIZED)
    ;; Cannot cancel if already sold
    (asserts! (not (is-eq (get status invoice-data) STATUS_SOLD)) ERR_INVOICE_ALREADY_SOLD)
    
    ;; Update status
    (map-set invoices
      { invoice-id: invoice-id }
      (merge invoice-data { status: STATUS_CANCELLED })
    )
    
    (ok true)
  )
)

;; Update invoice status (internal use)
(define-public (update-invoice-status (invoice-id uint) (new-status uint))
  (let (
    (invoice-data (unwrap! (get-invoice invoice-id) ERR_INVOICE_NOT_FOUND))
  )
    ;; Only contract owner or seller can update status
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) 
                  (is-eq tx-sender (get seller invoice-data))) ERR_UNAUTHORIZED)
    
    ;; Update status
    (map-set invoices
      { invoice-id: invoice-id }
      (merge invoice-data { status: new-status })
    )
    
    (ok true)
  )
)

;; Mark invoice as sold (called by peer-factoring contract)
(define-public (mark-invoice-sold 
  (invoice-id uint) 
  (buyer principal) 
  (purchase-price uint)
)
  (let (
    (invoice-data (unwrap! (get-invoice invoice-id) ERR_INVOICE_NOT_FOUND))
  )
    ;; Only available invoices can be sold
    (asserts! (is-eq (get status invoice-data) STATUS_AVAILABLE) ERR_INVALID_STATUS)
    
    ;; Update invoice with sale information
    (map-set invoices
      { invoice-id: invoice-id }
      (merge invoice-data {
        status: STATUS_SOLD,
        buyer: (some buyer),
        purchase-price: (some purchase-price),
        purchased-at: (some stacks-block-height)
      })
    )
    
    (ok true)
  )
)

;; Private helper functions

;; Update seller invoice list
(define-private (update-seller-invoices (seller principal) (invoice-id uint))
  (let (
    (current-list (get invoice-ids (default-to { invoice-ids: (list) } 
                    (map-get? seller-invoices { seller: seller }))))
  )
    (match (as-max-len? (append current-list invoice-id) u100)
      updated-list (begin 
        (map-set seller-invoices
          { seller: seller }
          { invoice-ids: updated-list }
        )
        true
      )
      false
    )
  )
)

;; Update debtor invoice list
(define-private (update-debtor-invoices (debtor principal) (invoice-id uint))
  (let (
    (current-list (get invoice-ids (default-to { invoice-ids: (list) } 
                    (map-get? debtor-invoices { debtor: debtor }))))
  )
    (match (as-max-len? (append current-list invoice-id) u100)
      updated-list (begin 
        (map-set debtor-invoices
          { debtor: debtor }
          { invoice-ids: updated-list }
        )
        true
      )
      false
    )
  )
)

;; Admin functions (only contract owner)

;; Update platform fee rate
(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_AMOUNT) ;; Max 10%
    (var-set platform-fee-rate new-rate)
    (ok true)
  )
)

;; Update minimum invoice amount
(define-public (set-min-invoice-amount (new-amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set min-invoice-amount new-amount)
    (ok true)
  )
)

;; Update maximum discount rate
(define-public (set-max-discount-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u5000) ERR_INVALID_DISCOUNT) ;; Max 50%
    (var-set max-discount-rate new-rate)
    (ok true)
  )
)


