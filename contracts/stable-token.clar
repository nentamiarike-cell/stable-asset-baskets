;; Stable Asset Basket Token (SABT)
;; SIP-010 compliant fungible token backed by commodity baskets
;; Implements transfer, approval, and integration with basket manager

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-TOKEN-OWNER (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-INSUFFICIENT-ALLOWANCE (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))
(define-constant ERR-UNAUTHORIZED (err u105))
(define-constant ERR-BASKET-MANAGER-ONLY (err u106))
(define-constant ERR-TOKEN-PAUSED (err u107))
(define-constant ERR-INVALID-RECIPIENT (err u108))
(define-constant ERR-SAME-SENDER-RECIPIENT (err u109))
(define-constant ERR-MINT-FAILED (err u110))
(define-constant ERR-BURN-FAILED (err u111))

;; Token Configuration
(define-constant TOKEN-NAME "Stable Asset Basket Token")
(define-constant TOKEN-SYMBOL "SABT")
(define-constant TOKEN-DECIMALS u6)
(define-constant TOKEN-URI u"https://stable-asset-baskets.com/token-info")

;; Maximum token supply (100M tokens with 6 decimals)
(define-constant MAX-SUPPLY u100000000000000)

;; Data Variables
(define-data-var token-paused bool false)
(define-data-var total-supply uint u0)
(define-data-var basket-manager-contract (optional principal) none)
(define-data-var fee-recipient (optional principal) none)
(define-data-var transfer-fee uint u0) ;; Fee in basis points (100 = 1%)

;; Data Maps

;; Token balances for each user
(define-map token-balances
    { owner: principal }
    { balance: uint }
)

;; Allowances for spending tokens on behalf of others
(define-map token-allowances
    { owner: principal, spender: principal }
    { allowance: uint }
)

;; Basket-specific token balances (tracks which basket tokens belong to)
(define-map basket-token-balances
    { owner: principal, basket-id: uint }
    { balance: uint }
)

;; Authorized minters (basket manager and admin)
(define-map authorized-minters
    { minter: principal }
    { active: bool }
)

;; Token metadata for different baskets
(define-map basket-metadata
    { basket-id: uint }
    {
        name: (string-ascii 64),
        description: (string-ascii 128),
        total-tokens-minted: uint,
        active: bool
    }
)

;; User transaction history
(define-map transaction-history
    { user: principal, tx-id: uint }
    {
        transaction-type: (string-ascii 10), ;; "mint", "burn", "transfer"
        amount: uint,
        basket-id: (optional uint),
        stacks-block-height: uint,
        counterparty: (optional principal)
    }
)

(define-data-var next-tx-id uint u1)

;; Private Functions

;; Check if user is authorized (owner or authorized minter)
(define-private (is-authorized-minter (user principal))
    (or
        (is-eq user CONTRACT-OWNER)
        (match (map-get? authorized-minters { minter: user })
            minter-info (get active minter-info)
            false
        )
    )
)

;; Check if basket manager is calling
(define-private (is-basket-manager-call)
    (match (var-get basket-manager-contract)
        manager (is-eq tx-sender manager)
        false
    )
)

;; Calculate transfer fee
(define-private (calculate-transfer-fee (amount uint))
    (let
        (
            (fee-rate (var-get transfer-fee))
        )
        (if (> fee-rate u0)
            (/ (* amount fee-rate) u10000) ;; Basis points calculation
            u0
        )
    )
)

;; Update total supply safely
(define-private (update-total-supply (new-supply uint))
    (begin
        (asserts! (<= new-supply MAX-SUPPLY) ERR-INVALID-AMOUNT)
        (ok (var-set total-supply new-supply))
    )
)

;; Record transaction in history
(define-private (record-transaction
    (user principal)
    (tx-type (string-ascii 10))
    (amount uint)
    (basket-id (optional uint))
    (counterparty (optional principal))
)
    (let
        (
            (tx-id (var-get next-tx-id))
        )
        (map-set transaction-history
            { user: user, tx-id: tx-id }
            {
                transaction-type: tx-type,
                amount: amount,
                basket-id: basket-id,
                stacks-block-height: stacks-block-height,
                counterparty: counterparty
            }
        )
        (var-set next-tx-id (+ tx-id u1))
        tx-id
    )
)

;; Internal transfer function
(define-private (transfer-internal
    (amount uint)
    (sender principal)
    (recipient principal)
    (memo (optional (buff 34)))
)
    (let
        (
            (sender-balance (get-balance sender))
            (recipient-balance (get-balance recipient))
            (fee (calculate-transfer-fee amount))
            (net-amount (- amount fee))
        )
        (asserts! (not (var-get token-paused)) ERR-TOKEN-PAUSED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (not (is-eq sender recipient)) ERR-SAME-SENDER-RECIPIENT)
        (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
        
        ;; Update balances
        (map-set token-balances
            { owner: sender }
            { balance: (- sender-balance amount) }
        )
        
        (map-set token-balances
            { owner: recipient }
            { balance: (+ recipient-balance net-amount) }
        )
        
        ;; Handle transfer fee
        (if (> fee u0)
            (match (var-get fee-recipient)
                fee-addr
                    (let
                        (
                            (fee-balance (get-balance fee-addr))
                        )
                        (map-set token-balances
                            { owner: fee-addr }
                            { balance: (+ fee-balance fee) }
                        )
                        true
                    )
                ;; If no fee recipient, burn the fee
                (begin
                    (try! (update-total-supply (- (var-get total-supply) fee)))
                    true
                )
            )
            true
        )
        
        ;; Record transaction
        (record-transaction sender "transfer" amount none (some recipient))
        (record-transaction recipient "receive" net-amount none (some sender))
        
        ;; Print transfer event
        (print {
            type: "transfer",
            sender: sender,
            recipient: recipient,
            amount: amount,
            fee: fee,
            memo: memo
        })
        
        (ok true)
    )
)

;; Public Functions - SIP-010 Standard

;; Transfer tokens
(define-public (transfer
    (amount uint)
    (sender principal)
    (recipient principal)
    (memo (optional (buff 34)))
)
    (begin
        (asserts! (or (is-eq tx-sender sender) (is-eq contract-caller sender)) ERR-NOT-TOKEN-OWNER)
        (transfer-internal amount sender recipient memo)
    )
)

;; Get token name
(define-read-only (get-name)
    (ok TOKEN-NAME)
)

;; Get token symbol
(define-read-only (get-symbol)
    (ok TOKEN-SYMBOL)
)

;; Get token decimals
(define-read-only (get-decimals)
    (ok TOKEN-DECIMALS)
)

;; Get total token supply
(define-read-only (get-total-supply)
    (ok (var-get total-supply))
)

;; Get token URI
(define-read-only (get-token-uri)
    (ok (some TOKEN-URI))
)

;; Get user balance
(define-read-only (get-balance (who principal))
    (default-to u0 (get balance (map-get? token-balances { owner: who })))
)

;; Transfer tokens from one user to another (with allowance)
(define-public (transfer-from
    (amount uint)
    (sender principal)
    (recipient principal)
    (memo (optional (buff 34)))
)
    (let
        (
            (allowance (get-allowance sender tx-sender))
        )
        (asserts! (>= allowance amount) ERR-INSUFFICIENT-ALLOWANCE)
        
        ;; Update allowance
        (map-set token-allowances
            { owner: sender, spender: tx-sender }
            { allowance: (- allowance amount) }
        )
        
        ;; Perform transfer
        (transfer-internal amount sender recipient memo)
    )
)

;; Approve spending allowance
(define-public (approve (spender principal) (amount uint))
    (begin
        (asserts! (not (is-eq tx-sender spender)) ERR-SAME-SENDER-RECIPIENT)
        
        (map-set token-allowances
            { owner: tx-sender, spender: spender }
            { allowance: amount }
        )
        
        (print {
            type: "approval",
            owner: tx-sender,
            spender: spender,
            amount: amount
        })
        
        (ok true)
    )
)

;; Get allowance amount
(define-read-only (get-allowance (owner principal) (spender principal))
    (default-to u0 (get allowance (map-get? token-allowances { owner: owner, spender: spender })))
)

;; Extended Functions

;; Mint tokens (basket manager only)
(define-public (mint (recipient principal) (amount uint) (basket-id uint))
    (let
        (
            (current-balance (get-balance recipient))
            (current-basket-balance (get-basket-balance recipient basket-id))
            (current-supply (var-get total-supply))
        )
        (asserts! (is-basket-manager-call) ERR-BASKET-MANAGER-ONLY)
        (asserts! (not (var-get token-paused)) ERR-TOKEN-PAUSED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        ;; Check supply limit
        (asserts! (<= (+ current-supply amount) MAX-SUPPLY) ERR-INVALID-AMOUNT)
        
        ;; Update balances
        (map-set token-balances
            { owner: recipient }
            { balance: (+ current-balance amount) }
        )
        
        (map-set basket-token-balances
            { owner: recipient, basket-id: basket-id }
            { balance: (+ current-basket-balance amount) }
        )
        
        ;; Update total supply
        (try! (update-total-supply (+ current-supply amount)))
        
        ;; Update basket metadata
        (match (map-get? basket-metadata { basket-id: basket-id })
            metadata
                (map-set basket-metadata
                    { basket-id: basket-id }
                    (merge metadata {
                        total-tokens-minted: (+ (get total-tokens-minted metadata) amount)
                    })
                )
            ;; Create new basket metadata if it doesn't exist
            (map-set basket-metadata
                { basket-id: basket-id }
                {
                    name: "Commodity Basket",
                    description: "Tokens backed by commodity basket",
                    total-tokens-minted: amount,
                    active: true
                }
            )
        )
        
        ;; Record transaction
        (record-transaction recipient "mint" amount (some basket-id) none)
        
        (print {
            type: "mint",
            recipient: recipient,
            amount: amount,
            basket-id: basket-id
        })
        
        (ok true)
    )
)

;; Burn tokens (basket manager only)
(define-public (burn (owner principal) (amount uint) (basket-id uint))
    (let
        (
            (current-balance (get-balance owner))
            (current-basket-balance (get-basket-balance owner basket-id))
            (current-supply (var-get total-supply))
        )
        (asserts! (is-basket-manager-call) ERR-BASKET-MANAGER-ONLY)
        (asserts! (not (var-get token-paused)) ERR-TOKEN-PAUSED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (>= current-basket-balance amount) ERR-INSUFFICIENT-BALANCE)
        
        ;; Update balances
        (map-set token-balances
            { owner: owner }
            { balance: (- current-balance amount) }
        )
        
        (map-set basket-token-balances
            { owner: owner, basket-id: basket-id }
            { balance: (- current-basket-balance amount) }
        )
        
        ;; Update total supply
        (try! (update-total-supply (- current-supply amount)))
        
        ;; Update basket metadata
        (match (map-get? basket-metadata { basket-id: basket-id })
            metadata
                (map-set basket-metadata
                    { basket-id: basket-id }
                    (merge metadata {
                        total-tokens-minted: (- (get total-tokens-minted metadata) amount)
                    })
                )
            false ;; Should not happen if basket exists
        )
        
        ;; Record transaction
        (record-transaction owner "burn" amount (some basket-id) none)
        
        (print {
            type: "burn",
            owner: owner,
            amount: amount,
            basket-id: basket-id
        })
        
        (ok true)
    )
)

;; Administrative Functions

;; Set basket manager contract
(define-public (set-basket-manager (manager principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
        (ok (var-set basket-manager-contract (some manager)))
    )
)

;; Authorize minter
(define-public (authorize-minter (minter principal) (active bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
        (ok (map-set authorized-minters { minter: minter } { active: active }))
    )
)

;; Set transfer fee
(define-public (set-transfer-fee (fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
        (asserts! (<= fee u1000) ERR-INVALID-AMOUNT) ;; Max 10% fee
        (ok (var-set transfer-fee fee))
    )
)

;; Set fee recipient
(define-public (set-fee-recipient (recipient (optional principal)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
        (ok (var-set fee-recipient recipient))
    )
)

;; Pause/unpause token
(define-public (set-token-pause (paused bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
        (ok (var-set token-paused paused))
    )
)

;; Extended Read-Only Functions

;; Get basket-specific balance
(define-read-only (get-basket-balance (owner principal) (basket-id uint))
    (default-to u0 (get balance (map-get? basket-token-balances { owner: owner, basket-id: basket-id })))
)

;; Get basket metadata
(define-read-only (get-basket-metadata (basket-id uint))
    (map-get? basket-metadata { basket-id: basket-id })
)

;; Get transaction history
(define-read-only (get-transaction-history (user principal) (tx-id uint))
    (map-get? transaction-history { user: user, tx-id: tx-id })
)

;; Check if token is paused
(define-read-only (is-token-paused)
    (var-get token-paused)
)

;; Get transfer fee
(define-read-only (get-transfer-fee)
    (var-get transfer-fee)
)

;; Get fee recipient
(define-read-only (get-fee-recipient)
    (var-get fee-recipient)
)

;; Check if minter is authorized
(define-read-only (is-minter-authorized (minter principal))
    (match (map-get? authorized-minters { minter: minter })
        minter-info (get active minter-info)
        false
    )
)

;; Get basket manager contract
(define-read-only (get-basket-manager)
    (var-get basket-manager-contract)
)

;; Get max supply
(define-read-only (get-max-supply)
    MAX-SUPPLY
)
