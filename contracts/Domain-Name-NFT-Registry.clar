(define-non-fungible-token domain-name uint)

(define-constant contract-owner tx-sender)
(define-constant err-expired (err u100))
(define-constant err-not-owner (err u101))
(define-constant err-already-registered (err u102))
(define-constant err-invalid-name (err u103))
(define-constant err-name-too-short (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-not-for-sale (err u106))
(define-constant err-insufficient-payment (err u107))
(define-constant min-length u3)
(define-constant registration-period u52560)
(define-constant name-price u100000000)

(define-data-var last-domain-id uint u0)
(define-data-var dao-address principal contract-owner)

(define-map domain-names
    { name: (string-ascii 50) }
    { owner: principal, expires: uint, address: (optional (string-ascii 50)), id: uint }
)

(define-map name-preorders
    { name: (string-ascii 50) }
    { buyer: principal, paid: uint }
)

(define-map name-resolvers
    { name: (string-ascii 50) }
    { btc: (optional (string-ascii 50)), stx: (optional principal) }
)

(define-map domain-marketplace
    { name: (string-ascii 50) }
    { seller: principal, price: uint, listed: bool }
)

(define-read-only (get-last-token-id)
    (ok (var-get last-domain-id))
)

(define-read-only (get-token-uri (id uint))
    (ok none)
)

(define-read-only (get-owner (name (string-ascii 50)))
    (match (map-get? domain-names {name: name})
        entry (ok (get owner entry))
        (err u404)
    )
)

(define-read-only (get-expiration (name (string-ascii 50)))
    (match (map-get? domain-names {name: name})
        entry (ok (get expires entry))
        (err u404)
    )
)

(define-read-only (resolve-name (name (string-ascii 50)))
    (match (map-get? name-resolvers {name: name})
        entry (ok entry)
        (err u404)
    )
)

(define-read-only (get-domain-listing (name (string-ascii 50)))
    (match (map-get? domain-marketplace {name: name})
        entry (ok entry)
        (err u404)
    )
)

(define-public (preorder-name (name (string-ascii 50)) (paid uint))
    (begin
        (try! (stx-transfer? paid tx-sender contract-owner))
        (ok (map-set name-preorders
            {name: name}
            {buyer: tx-sender, paid: paid}
        ))
    )
)

(define-public (register-name (name (string-ascii 50)))
    (let 
        (
            (preorder (unwrap! (map-get? name-preorders {name: name}) (err u404)))
            (name-length (len name))
        )
        (asserts! (is-eq (get buyer preorder) tx-sender) err-unauthorized)
        (asserts! (>= name-length min-length) err-name-too-short)
        (asserts! (is-none (map-get? domain-names {name: name})) err-already-registered)
        
        (let
            (
                (domain-id (+ (var-get last-domain-id) u1))
                (expires-at (+ burn-block-height registration-period))
            )
            (try! (nft-mint? domain-name domain-id tx-sender))
            (var-set last-domain-id domain-id)
            (map-set domain-names
                {name: name}
                {
                    owner: tx-sender,
                    expires: expires-at,
                    address: none,
                    id: domain-id
                }
            )
            (map-delete name-preorders {name: name})
            (ok domain-id)
        )
    )
)

(define-public (renew-name (name (string-ascii 50)))
    (let
        (
            (domain (unwrap! (map-get? domain-names {name: name}) (err u404)))
            (current-owner (get owner domain))
        )
        (asserts! (is-eq tx-sender current-owner) err-not-owner)
        (try! (stx-transfer? name-price tx-sender contract-owner))
        (ok (map-set domain-names
            {name: name}
            (merge domain {expires: (+ burn-block-height registration-period)})
        ))
    )
)

(define-public (transfer-name (name (string-ascii 50)) (new-owner principal))
    (let
        (
            (domain (unwrap! (map-get? domain-names {name: name}) (err u404)))
            (current-owner (get owner domain))
            (domain-id (get id domain))
        )
        (asserts! (is-eq tx-sender current-owner) err-not-owner)
        (try! (nft-transfer? domain-name domain-id tx-sender new-owner))
        (ok (map-set domain-names
            {name: name}
            (merge domain {owner: new-owner})
        ))
    )
)

(define-public (set-name-resolver (name (string-ascii 50)) (btc-address (optional (string-ascii 50))) (stx-address (optional principal)))
    (let
        (
            (domain (unwrap! (map-get? domain-names {name: name}) (err u404)))
        )
        (asserts! (is-eq tx-sender (get owner domain)) err-not-owner)
        (ok (map-set name-resolvers
            {name: name}
            {btc: btc-address, stx: stx-address}
        ))
    )
)

(define-public (update-dao-address (new-address principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (var-set dao-address new-address)
        (ok true)
    )
)

(define-public (list-domain-for-sale (name (string-ascii 50)) (price uint))
    (let
        (
            (domain (unwrap! (map-get? domain-names {name: name}) (err u404)))
        )
        (asserts! (is-eq tx-sender (get owner domain)) err-not-owner)
        (asserts! (> price u0) err-invalid-name)
        (ok (map-set domain-marketplace
            {name: name}
            {seller: tx-sender, price: price, listed: true}
        ))
    )
)

(define-public (unlist-domain (name (string-ascii 50)))
    (let
        (
            (domain (unwrap! (map-get? domain-names {name: name}) (err u404)))
            (listing (unwrap! (map-get? domain-marketplace {name: name}) err-not-for-sale))
        )
        (asserts! (is-eq tx-sender (get owner domain)) err-not-owner)
        (ok (map-set domain-marketplace
            {name: name}
            (merge listing {listed: false})
        ))
    )
)

(define-public (buy-domain (name (string-ascii 50)))
    (let
        (
            (domain (unwrap! (map-get? domain-names {name: name}) (err u404)))
            (listing (unwrap! (map-get? domain-marketplace {name: name}) err-not-for-sale))
            (domain-owner (get owner domain))
            (domain-id (get id domain))
            (sale-price (get price listing))
        )
        (asserts! (get listed listing) err-not-for-sale)
        (asserts! (not (is-eq tx-sender domain-owner)) err-not-owner)
        (try! (stx-transfer? sale-price tx-sender domain-owner))
        (try! (nft-transfer? domain-name domain-id domain-owner tx-sender))
        (map-set domain-names
            {name: name}
            (merge domain {owner: tx-sender})
        )
        (map-delete domain-marketplace {name: name})
        (ok true)
    )
)