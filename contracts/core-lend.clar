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