;; Basket Manager Contract
;; Manages commodity baskets for stable token pegging to multiple assets
;; Handles collateralization, pricing, and basket configurations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-AUTHORIZED (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u103))
(define-constant ERR-BASKET-NOT-FOUND (err u104))
(define-constant ERR-COMMODITY-NOT-FOUND (err u105))
(define-constant ERR-INVALID-WEIGHT (err u106))
(define-constant ERR-BASKET-PAUSED (err u107))
(define-constant ERR-PRICE-TOO-OLD (err u108))
(define-constant ERR-DIVISION-BY-ZERO (err u109))
(define-constant ERR-OVERFLOW (err u110))

;; Maximum values for safety
(define-constant MAX-UINT u340282366920938463463374607431768211455)
(define-constant PRECISION u1000000) ;; 6 decimal places
(define-constant MIN-COLLATERAL-RATIO u150) ;; 150% minimum
(define-constant PRICE-VALIDITY-PERIOD u7200) ;; 2 hours in blocks

;; Data Variables
(define-data-var contract-paused bool false)
(define-data-var next-basket-id uint u1)
(define-data-var total-collateral uint u0)
(define-data-var emergency-admin (optional principal) none)

;; Data Maps

;; Commodity definitions
(define-map commodities
    { commodity-id: uint }
    {
        name: (string-ascii 32),
        symbol: (string-ascii 8),
        price: uint,
        price-timestamp: uint,
        active: bool,
        min-weight: uint,
        max-weight: uint
    }
)

;; Basket configurations
(define-map baskets
    { basket-id: uint }
    {
        name: (string-ascii 64),
        total-weight: uint,
        collateral-ratio: uint,
        active: bool,
        created-at: uint,
        last-updated: uint
    }
)

;; Commodity weights in each basket
(define-map basket-weights
    { basket-id: uint, commodity-id: uint }
    { weight: uint }
)

;; User collateral positions
(define-map user-collateral
    { user: principal, basket-id: uint }
    {
        stx-collateral: uint,
        tokens-minted: uint,
        last-interaction: uint
    }
)

;; Authorized oracles for price updates
(define-map authorized-oracles
    { oracle: principal }
    { active: bool }
)

;; Private Functions

;; Calculate basket value based on commodity weights and prices
(define-private (calculate-basket-value (basket-id uint))
    (let
        (
            (basket-opt (map-get? baskets { basket-id: basket-id }))
        )
        (match basket-opt
            basket-info
                (let
                    (
                        (total-weight (get total-weight basket-info))
                    )
                    (if (> total-weight u0)
                        (get total-value (fold calculate-commodity-contribution
                            (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) ;; Support up to 10 commodities
                            { basket-id: basket-id, total-value: u0, total-weight: total-weight }))
                        u0
                    )
                )
            u0
        )
    )
)

;; Calculate single commodity contribution to basket value
(define-private (calculate-commodity-contribution
    (commodity-id uint)
    (state { basket-id: uint, total-value: uint, total-weight: uint })
)
    (let
        (
            (basket-id (get basket-id state))
            (current-value (get total-value state))
            (total-weight (get total-weight state))
            (weight-info (map-get? basket-weights { basket-id: basket-id, commodity-id: commodity-id }))
            (commodity-info (map-get? commodities { commodity-id: commodity-id }))
        )
        (match weight-info
            weight-data
                (match commodity-info
                    commodity-data
                        (let
                            (
                                (weight (get weight weight-data))
                                (price (get price commodity-data))
                                (weighted-value (/ (* price weight) total-weight))
                            )
                            {
                                basket-id: basket-id,
                                total-value: (+ current-value weighted-value),
                                total-weight: total-weight
                            }
                        )
                    ;; No commodity data
                    state
                )
            ;; No weight data
            state
        )
    )
)

;; Validate price timestamp
(define-private (is-price-valid (timestamp uint))
    (let ((current-height stacks-block-height))
        (< (- current-height timestamp) PRICE-VALIDITY-PERIOD)
    )
)

;; Calculate required collateral for token amount
(define-private (calculate-required-collateral (basket-id uint) (token-amount uint))
    (let
        (
            (basket-opt (map-get? baskets { basket-id: basket-id }))
        )
        (match basket-opt
            basket-info
                (let
                    (
                        (collateral-ratio (get collateral-ratio basket-info))
                        (basket-value (calculate-basket-value basket-id))
                    )
                    (if (and (> basket-value u0) (> collateral-ratio u0))
                        (/ (* token-amount basket-value collateral-ratio) (* PRECISION u100))
                        u0
                    )
                )
            u0
        )
    )
)

;; Check if user is authorized (owner or emergency admin)
(define-private (is-authorized (user principal))
    (or
        (is-eq user CONTRACT-OWNER)
        (match (var-get emergency-admin)
            admin (is-eq user admin)
            false
        )
    )
)

;; Helper function for setting basket weights
(define-private (set-basket-weight-helper
    (commodity-weight { commodity-id: uint, weight: uint })
    (basket-id uint)
)
    (map-set basket-weights
        { basket-id: basket-id, commodity-id: (get commodity-id commodity-weight) }
        { weight: (get weight commodity-weight) }
    )
)

;; Public Functions

;; Initialize a new commodity
(define-public (add-commodity
    (commodity-id uint)
    (name (string-ascii 32))
    (symbol (string-ascii 8))
    (initial-price uint)
    (min-weight uint)
    (max-weight uint)
)
    (begin
        (asserts! (is-authorized tx-sender) ERR-OWNER-ONLY)
        (asserts! (not (var-get contract-paused)) ERR-BASKET-PAUSED)
        (asserts! (> initial-price u0) ERR-INVALID-AMOUNT)
        (asserts! (<= min-weight max-weight) ERR-INVALID-WEIGHT)
        
        (ok (map-set commodities
            { commodity-id: commodity-id }
            {
                name: name,
                symbol: symbol,
                price: initial-price,
                price-timestamp: stacks-block-height,
                active: true,
                min-weight: min-weight,
                max-weight: max-weight
            }
        ))
    )
)

;; Update commodity price (oracle function)
(define-public (update-price (commodity-id uint) (new-price uint))
    (begin
        (asserts! (> new-price u0) ERR-INVALID-AMOUNT)
        (asserts!
            (match (map-get? authorized-oracles { oracle: tx-sender })
                oracle-info (get active oracle-info)
                false
            )
            ERR-NOT-AUTHORIZED
        )
        
        (match (map-get? commodities { commodity-id: commodity-id })
            commodity-info
                (ok (map-set commodities
                    { commodity-id: commodity-id }
                    (merge commodity-info {
                        price: new-price,
                        price-timestamp: stacks-block-height
                    })
                ))
            ERR-COMMODITY-NOT-FOUND
        )
    )
)

;; Create a new basket
(define-public (create-basket
    (name (string-ascii 64))
    (commodity-ids (list 10 uint))
    (weights (list 10 uint))
    (collateral-ratio uint)
)
    (let
        (
            (basket-id (var-get next-basket-id))
            (total-weight (fold + weights u0))
        )
        (asserts! (is-authorized tx-sender) ERR-OWNER-ONLY)
        (asserts! (not (var-get contract-paused)) ERR-BASKET-PAUSED)
        (asserts! (>= collateral-ratio MIN-COLLATERAL-RATIO) ERR-INVALID-AMOUNT)
        (asserts! (> total-weight u0) ERR-INVALID-WEIGHT)
        (asserts! (is-eq (len commodity-ids) (len weights)) ERR-INVALID-WEIGHT)
        
        ;; Create basket
        (map-set baskets
            { basket-id: basket-id }
            {
                name: name,
                total-weight: total-weight,
                collateral-ratio: collateral-ratio,
                active: true,
                created-at: stacks-block-height,
                last-updated: stacks-block-height
            }
        )
        
        ;; Set commodity weights using zip and map
        (let
            (
                (commodity-weight-pairs (map make-commodity-weight-pair commodity-ids weights))
            )
            (map set-weight-for-basket commodity-weight-pairs (list basket-id basket-id basket-id basket-id basket-id basket-id basket-id basket-id basket-id basket-id))
        )
        
        (var-set next-basket-id (+ basket-id u1))
        (ok basket-id)
    )
)

;; Helper function to create commodity-weight pairs
(define-private (make-commodity-weight-pair (commodity-id uint) (weight uint))
    { commodity-id: commodity-id, weight: weight }
)

;; Helper function to set weights for a basket
(define-private (set-weight-for-basket
    (commodity-weight { commodity-id: uint, weight: uint })
    (basket-id uint)
)
    (map-set basket-weights
        { basket-id: basket-id, commodity-id: (get commodity-id commodity-weight) }
        { weight: (get weight commodity-weight) }
    )
)

;; Deposit collateral and mint tokens
(define-public (deposit-collateral (basket-id uint) (stx-amount uint))
    (let
        (
            (basket-info (unwrap! (map-get? baskets { basket-id: basket-id }) ERR-BASKET-NOT-FOUND))
            (basket-value (calculate-basket-value basket-id))
            (collateral-ratio (get collateral-ratio basket-info))
            (tokens-to-mint (if (> basket-value u0)
                (/ (* stx-amount PRECISION) basket-value)
                u0
            ))
            (user-position (default-to
                { stx-collateral: u0, tokens-minted: u0, last-interaction: u0 }
                (map-get? user-collateral { user: tx-sender, basket-id: basket-id })
            ))
        )
        (asserts! (not (var-get contract-paused)) ERR-BASKET-PAUSED)
        (asserts! (get active basket-info) ERR-BASKET-NOT-FOUND)
        (asserts! (> stx-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (> basket-value u0) ERR-INVALID-AMOUNT)
        
        ;; Transfer STX collateral
        (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))
        
        ;; Update user position
        (map-set user-collateral
            { user: tx-sender, basket-id: basket-id }
            {
                stx-collateral: (+ (get stx-collateral user-position) stx-amount),
                tokens-minted: (+ (get tokens-minted user-position) tokens-to-mint),
                last-interaction: stacks-block-height
            }
        )
        
        ;; Update total collateral
        (var-set total-collateral (+ (var-get total-collateral) stx-amount))
        
        (ok tokens-to-mint)
    )
)

;; Withdraw collateral by burning tokens
(define-public (withdraw-collateral (basket-id uint) (token-amount uint))
    (let
        (
            (user-position (unwrap! (map-get? user-collateral { user: tx-sender, basket-id: basket-id }) ERR-NOT-AUTHORIZED))
            (basket-value (calculate-basket-value basket-id))
            (stx-to-return (if (> basket-value u0)
                (/ (* token-amount basket-value) PRECISION)
                u0
            ))
        )
        (asserts! (not (var-get contract-paused)) ERR-BASKET-PAUSED)
        (asserts! (>= (get tokens-minted user-position) token-amount) ERR-INSUFFICIENT-COLLATERAL)
        (asserts! (>= (get stx-collateral user-position) stx-to-return) ERR-INSUFFICIENT-COLLATERAL)
        
        ;; Update user position
        (map-set user-collateral
            { user: tx-sender, basket-id: basket-id }
            {
                stx-collateral: (- (get stx-collateral user-position) stx-to-return),
                tokens-minted: (- (get tokens-minted user-position) token-amount),
                last-interaction: stacks-block-height
            }
        )
        
        ;; Return STX collateral
        (try! (as-contract (stx-transfer? stx-to-return tx-sender tx-sender)))
        
        ;; Update total collateral
        (var-set total-collateral (- (var-get total-collateral) stx-to-return))
        
        (ok stx-to-return)
    )
)

;; Authorize oracle
(define-public (authorize-oracle (oracle principal) (active bool))
    (begin
        (asserts! (is-authorized tx-sender) ERR-OWNER-ONLY)
        (ok (map-set authorized-oracles { oracle: oracle } { active: active }))
    )
)

;; Emergency pause
(define-public (set-emergency-pause (paused bool))
    (begin
        (asserts! (is-authorized tx-sender) ERR-OWNER-ONLY)
        (ok (var-set contract-paused paused))
    )
)

;; Set emergency admin
(define-public (set-emergency-admin (admin (optional principal)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
        (ok (var-set emergency-admin admin))
    )
)

;; Read-only functions

;; Get basket info
(define-read-only (get-basket-info (basket-id uint))
    (map-get? baskets { basket-id: basket-id })
)

;; Get commodity info
(define-read-only (get-commodity-info (commodity-id uint))
    (map-get? commodities { commodity-id: commodity-id })
)

;; Get user collateral position
(define-read-only (get-user-position (user principal) (basket-id uint))
    (map-get? user-collateral { user: user, basket-id: basket-id })
)

;; Get basket current value
(define-read-only (get-basket-value (basket-id uint))
    (ok (calculate-basket-value basket-id))
)

;; Check if contract is paused
(define-read-only (is-paused)
    (var-get contract-paused)
)

;; Get total system collateral
(define-read-only (get-total-collateral)
    (var-get total-collateral)
)

;; Get basket weight for commodity
(define-read-only (get-basket-weight (basket-id uint) (commodity-id uint))
    (map-get? basket-weights { basket-id: basket-id, commodity-id: commodity-id })
)

;; Check if oracle is authorized
(define-read-only (is-oracle-authorized (oracle principal))
    (match (map-get? authorized-oracles { oracle: oracle })
        oracle-info (get active oracle-info)
        false
    )
)
