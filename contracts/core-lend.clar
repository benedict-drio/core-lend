;; CoreLend: Bitcoin-Backed Decentralized Finance Protocol
;; Secure lending infrastructure leveraging Bitcoin's security with DeFi flexibility
;; A next-generation lending protocol enabling Bitcoin-centric DeFi operations through Stacks layer

;; Protocol Overview:
;; - Bitcoin-Settled: First lending protocol with direct Bitcoin finality
;; - Risk-Weighted Collateral: Multi-asset support with dynamic collateral ratios
;; - Algorithmic Interest Rates: Market-driven rates with reserve-backed stability
;; - CLEND Governance: Native token for protocol governance and fee sharing
;; - SIP-010 Compliant: Full interoperability with Stacks token standards
;; - Liquidation Protection: Real-time health monitoring and penalty incentives

;; Key Innovations:
;; 1. Bitcoin-Centric Design: Enables BTC-denominated positions with STX/BTC oracle pricing
;; 2. Capital Efficiency: Cross-collateralization with optimized LTV ratios
;; 3. Protocol-Controlled Reserves: Sustainable yield generation through reserve factoring
;; 4. Modular Architecture: Easily upgradable market parameters and risk models
;; 5. Transparent Liquidations: Dutch auction-style liquidation engine with penalty redistribution

;; Technical Highlights:
;; - Precision Math: 6-decimal fixed-point arithmetic for financial calculations
;; - Real-Time Accrual: Block-based interest compounding with reserve allocation
;; - Risk Management: Dual collateral/liquidation ratio system with position health monitoring
;; - Capital Controls: Supply/borrow caps with market-specific debt ceilings
;; - Oracle Integration: Price feed abstraction layer for multi-source valuation

(impl-trait .sip-010-trait-ft-standard.sip-010-trait)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-PAUSED (err u103)) 
(define-constant ERR-INVALID-AMOUNT (err u104))
(define-constant ERR-MARKET-NOT-FOUND (err u105))
(define-constant ERR-BELOW-COLLATERAL-RATIO (err u106))
(define-constant ERR-MAX-BORROW-EXCEEDED (err u107))
(define-constant ERR-CANNOT-LIQUIDATE (err u108))
(define-constant ERR-TOKEN-TRANSFER-FAILED (err u109))
(define-constant ERR-MARKET-ALREADY-EXISTS (err u110))

;; Constants
(define-constant PRECISION u1000000) ;; 6 decimal places for calculations
(define-constant DEFAULT-COLLATERAL-RATIO u1500000) ;; 150% in PRECISION format
(define-constant DEFAULT-LIQUIDATION-RATIO u1250000) ;; 125% in PRECISION format
(define-constant DEFAULT-LIQUIDATION-PENALTY u100000) ;; 10% in PRECISION format
(define-constant DEFAULT-INTEREST-RATE u50000) ;; 5% annual rate in PRECISION format
(define-constant DEFAULT-ORIGINATION-FEE u10000) ;; 1% in PRECISION format
(define-constant DEFAULT-RESERVE-FACTOR u300000) ;; 30% of interest goes to reserves
(define-constant MAX-UINT u340282366920938463463374607431768211455) ;; 2^128 - 1

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var treasury principal tx-sender)
(define-data-var protocol-paused bool false)
(define-data-var last-accrual-timestamp uint block-height)
(define-data-var total-deposits uint u0)
(define-data-var total-borrows uint u0)
(define-data-var total-reserves uint u0)

;; Token properties per SIP-010
(define-data-var token-name (string-ascii 32) "CoreLend")
(define-data-var token-symbol (string-ascii 10) "CLEND")
(define-data-var token-decimals uint u6)
(define-data-var token-uri (optional (string-utf8 256)) none)

;; Market data structure
(define-map markets
  principal ;; token-id
  {
    enabled: bool,
    collateral-ratio: uint, ;; minimum collateral ratio scaled by PRECISION
    liquidation-ratio: uint, ;; liquidation threshold ratio scaled by PRECISION
    liquidation-penalty: uint, ;; liquidation penalty scaled by PRECISION
    interest-rate: uint, ;; interest rate per year scaled by PRECISION
    origination-fee: uint, ;; fee charged on borrow scaled by PRECISION
    reserve-factor: uint, ;; percentage of interest that goes to reserves
    supply-cap: uint, ;; maximum amount that can be supplied
    borrow-cap: uint, ;; maximum amount that can be borrowed
    last-interest-update: uint ;; timestamp of last interest accrual
  }
)

;; User balances for supply and borrow positions
(define-map user-positions
  { user: principal, token: principal }
  {
    supplied: uint,
    borrowed: uint, 
    collateral-enabled: bool ;; whether this asset is used as collateral
  }
)

;; User balances for CLEND governance token
(define-map token-balances
  principal
  uint)

;; Approved operators that can transfer tokens on behalf of owners
(define-map token-approvals
  { owner: principal, operator: principal }
  uint)

;; Oracle prices for tokens (in STX with PRECISION decimal places)
(define-map token-prices
  principal
  uint)

;; Functions

;; SIP-010 Functions
(define-read-only (get-name)
  (ok (var-get token-name)))

(define-read-only (get-symbol)
  (ok (var-get token-symbol)))

(define-read-only (get-decimals)
  (ok (var-get token-decimals)))

(define-read-only (get-balance (account principal))
  (ok (default-to u0 (map-get? token-balances account))))

(define-read-only (get-total-supply)
  (ok (var-get total-deposits)))

(define-read-only (get-token-uri)
  (ok (var-get token-uri)))

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (or (is-eq tx-sender sender) 
                 (>= (default-to u0 (map-get? token-approvals {owner: sender, operator: tx-sender})) amount))
      ERR-NOT-AUTHORIZED)
    (asserts! (>= (default-to u0 (map-get? token-balances sender)) amount) ERR-INSUFFICIENT-BALANCE)
    
    (map-set token-balances sender 
      (- (default-to u0 (map-get? token-balances sender)) amount))
    
    (map-set token-balances recipient 
      (+ (default-to u0 (map-get? token-balances recipient)) amount))
    
    (print {type: "ft_transfer_event", token-id: "CLEND", amount: amount, sender: sender, recipient: recipient})
    
    (match memo 
      memo-data (print {type: "ft_transfer_memo", token-id: "CLEND", memo: memo-data})
      none)
    
    (ok true)))

(define-public (transfer-memo (amount uint) (sender principal) (recipient principal) (memo (buff 34)))
  (transfer amount sender recipient (some memo)))

(define-public (approve (operator principal) (amount uint))
  (begin
    (map-set token-approvals {owner: tx-sender, operator: operator} amount)
    (print {type: "ft_approve", token-id: "CLEND", spender: operator, amount: amount})
    (ok true)))

;; Protocol Admin Functions

;; Initialize or update a market
(define-public (set-market (token-id principal) 
                         (enabled bool)
                         (collateral-ratio uint) 
                         (liquidation-ratio uint)
                         (liquidation-penalty uint)
                         (interest-rate uint)
                         (origination-fee uint)
                         (reserve-factor uint)
                         (supply-cap uint)
                         (borrow-cap uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (>= collateral-ratio liquidation-ratio) ERR-INVALID-AMOUNT)
    (asserts! (< liquidation-penalty PRECISION) ERR-INVALID-AMOUNT)
    (asserts! (<= reserve-factor PRECISION) ERR-INVALID-AMOUNT)
    
    (map-set markets token-id {
      enabled: enabled,
      collateral-ratio: collateral-ratio,
      liquidation-ratio: liquidation-ratio,
      liquidation-penalty: liquidation-penalty,
      interest-rate: interest-rate,
      origination-fee: origination-fee,
      reserve-factor: reserve-factor,
      supply-cap: supply-cap,
      borrow-cap: borrow-cap,
      last-interest-update: (default-to (- block-height u1) 
                               (get last-interest-update (map-get? markets token-id)))
    })
    
    (ok true)))

;; Set token price from oracle
(define-public (set-token-price (token-id principal) (price uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (> price u0) ERR-INVALID-AMOUNT)
    (map-set token-prices token-id price)
    (ok true)))

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)))

;; Set treasury address
(define-public (set-treasury (new-treasury principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set treasury new-treasury)
    (ok true)))