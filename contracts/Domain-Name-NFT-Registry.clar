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
(define-constant err-invalid-parent (err u108))
(define-constant err-subdomain-exists (err u109))
(define-constant min-length u3)
(define-constant registration-period u52560)
(define-constant name-price u100000000)
(define-constant subdomain-price u10000000)

(define-data-var last-domain-id uint u0)
(define-data-var dao-address principal contract-owner)
(define-data-var last-history-id uint u0)

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

(define-map subdomains
    { parent: (string-ascii 50), subdomain: (string-ascii 50) }
    { owner: principal, created: uint, active: bool }
)

(define-map domain-history
    { history-id: uint }
    { domain-name: (string-ascii 50), event-type: (string-ascii 20), from-owner: (optional principal), to-owner: principal, price: (optional uint), block-height: uint }
)

(define-map domain-history-by-name
    { name: (string-ascii 50), index: uint }
    { history-id: uint }
)

(define-map domain-analytics
    { name: (string-ascii 50) }
    { total-transfers: uint, last-sale-price: (optional uint), highest-sale-price: (optional uint), total-history-count: uint }
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

(define-read-only (get-subdomain-info (parent (string-ascii 50)) (subdomain (string-ascii 50)))
    (match (map-get? subdomains {parent: parent, subdomain: subdomain})
        entry (ok entry)
        (err u404)
    )
)

(define-read-only (is-valid-parent-domain (parent (string-ascii 50)))
    (match (map-get? domain-names {name: parent})
        domain (ok (and (> (get expires domain) burn-block-height) (is-eq tx-sender (get owner domain))))
        (err u404)
    )
)

(define-read-only (get-domain-history (history-id uint))
    (match (map-get? domain-history {history-id: history-id})
        entry (ok entry)
        (err u404)
    )
)

(define-read-only (get-domain-history-by-name (name (string-ascii 50)) (index uint))
    (match (map-get? domain-history-by-name {name: name, index: index})
        entry (match (map-get? domain-history {history-id: (get history-id entry)})
            history (ok history)
            (err u404)
        )
        (err u404)
    )
)

(define-read-only (get-domain-analytics (name (string-ascii 50)))
    (match (map-get? domain-analytics {name: name})
        entry (ok entry)
        (err u404)
    )
)

;; Advanced Analytics Functions
(define-read-only (get-domain-reputation-score (name (string-ascii 50)))
    (let
        (
            (domain-info (unwrap! (map-get? domain-names {name: name}) (err u404)))
            (analytics (default-to {total-transfers: u0, last-sale-price: none, highest-sale-price: none, total-history-count: u0} (map-get? domain-analytics {name: name})))
            (domain-age (- burn-block-height (- (get expires domain-info) registration-period)))
            (transfer-score (* (get total-transfers analytics) u10))
            (age-score (/ domain-age u1000))
            (sale-score (match (get highest-sale-price analytics)
                highest-price (/ highest-price u1000000)
                u0
            ))
        )
        (ok (+ transfer-score age-score sale-score))
    )
)

(define-read-only (get-platform-analytics)
    (let
        (
            (total-domains (var-get last-domain-id))
            (current-height burn-block-height)
        )
        (ok {
            total-domains: total-domains,
            total-history-events: (var-get last-history-id),
            current-block-height: current-height,
            registration-price: name-price,
            subdomain-price: subdomain-price
        })
    )
)

(define-read-only (get-domain-market-stats (name (string-ascii 50)))
    (let
        (
            (domain-info (unwrap! (map-get? domain-names {name: name}) (err u404)))
            (analytics (default-to {total-transfers: u0, last-sale-price: none, highest-sale-price: none, total-history-count: u0} (map-get? domain-analytics {name: name})))
            (listing (map-get? domain-marketplace {name: name}))
            (is-listed (match listing
                market-entry (get listed market-entry)
                false
            ))
            (current-price (match listing
                market-entry (some (get price market-entry))
                none
            ))
        )
        (ok {
            name: name,
            owner: (get owner domain-info),
            expires: (get expires domain-info),
            is-listed: is-listed,
            current-price: current-price,
            last-sale-price: (get last-sale-price analytics),
            highest-sale-price: (get highest-sale-price analytics),
            total-transfers: (get total-transfers analytics),
            days-until-expiry: (if (> (get expires domain-info) burn-block-height)
                (/ (- (get expires domain-info) burn-block-height) u144)
                u0
            )
        })
    )
)

(define-read-only (is-domain-premium (name (string-ascii 50)))
    (let
        (
            (name-len (len name))
            (analytics (default-to {total-transfers: u0, last-sale-price: none, highest-sale-price: none, total-history-count: u0} (map-get? domain-analytics {name: name})))
            (has-high-activity (> (get total-transfers analytics) u5))
            (has-valuable-sales (match (get highest-sale-price analytics)
                highest (> highest (* name-price u5))
                false
            ))
        )
        (ok (or 
            (is-eq name-len u3)
            (is-eq name-len u4)
            has-high-activity
            has-valuable-sales
        ))
    )
)

(define-read-only (get-domain-activity-level (name (string-ascii 50)))
    (let
        (
            (analytics (default-to {total-transfers: u0, last-sale-price: none, highest-sale-price: none, total-history-count: u0} (map-get? domain-analytics {name: name})))
            (total-activity (get total-history-count analytics))
        )
        (ok (if (>= total-activity u10)
            "high"
            (if (>= total-activity u3)
                "medium"
                "low"
            )
        ))
    )
)

(define-read-only (estimate-domain-value (name (string-ascii 50)))
    (let
        (
            (domain-info (unwrap! (map-get? domain-names {name: name}) (err u404)))
            (analytics (default-to {total-transfers: u0, last-sale-price: none, highest-sale-price: none, total-history-count: u0} (map-get? domain-analytics {name: name})))
            (name-len (len name))
            (base-value (if (<= name-len u4) (* name-price u3) name-price))
            (activity-multiplier (+ u100 (* (get total-transfers analytics) u20)))
            (scarcity-bonus (if (<= name-len u3) u200 u100))
        )
        (ok (/ (* base-value activity-multiplier scarcity-bonus) u10000))
    )
)

;; Domain Search and Filter Functions
(define-read-only (check-domain-by-length-range (name (string-ascii 50)) (min-len uint) (max-len uint))
    (let
        (
            (name-len (len name))
        )
        (ok (and (>= name-len min-len) (<= name-len max-len)))
    )
)

(define-read-only (check-domain-price-range (name (string-ascii 50)) (min-price uint) (max-price uint))
    (let
        (
            (listing (map-get? domain-marketplace {name: name}))
        )
        (match listing
            market-entry (ok (and 
                (get listed market-entry)
                (>= (get price market-entry) min-price)
                (<= (get price market-entry) max-price)
            ))
            (ok false)
        )
    )
)

(define-read-only (check-domain-expiry-range (name (string-ascii 50)) (min-blocks uint) (max-blocks uint))
    (let
        (
            (domain-info (unwrap! (map-get? domain-names {name: name}) (err u404)))
            (blocks-until-expiry (if (> (get expires domain-info) burn-block-height)
                (- (get expires domain-info) burn-block-height)
                u0
            ))
        )
        (ok (and (>= blocks-until-expiry min-blocks) (<= blocks-until-expiry max-blocks)))
    )
)

(define-read-only (check-domain-owner-match (name (string-ascii 50)) (target-owner principal))
    (let
        (
            (domain-info (unwrap! (map-get? domain-names {name: name}) (err u404)))
        )
        (ok (is-eq (get owner domain-info) target-owner))
    )
)

(define-read-only (check-domain-transfer-count (name (string-ascii 50)) (min-transfers uint))
    (let
        (
            (analytics (default-to {total-transfers: u0, last-sale-price: none, highest-sale-price: none, total-history-count: u0} (map-get? domain-analytics {name: name})))
        )
        (ok (>= (get total-transfers analytics) min-transfers))
    )
)

(define-read-only (is-domain-available-for-registration (name (string-ascii 50)))
    (let
        (
            (name-len (len name))
            (existing-domain (map-get? domain-names {name: name}))
        )
        (ok (and 
            (>= name-len min-length)
            (is-none existing-domain)
        ))
    )
)

(define-read-only (get-domain-search-metadata (name (string-ascii 50)))
    (match (map-get? domain-names {name: name})
        domain-info (let
            (
                (analytics (default-to {total-transfers: u0, last-sale-price: none, highest-sale-price: none, total-history-count: u0} (map-get? domain-analytics {name: name})))
                (listing (map-get? domain-marketplace {name: name}))
                (reputation (unwrap-panic (get-domain-reputation-score name)))
                (is-premium (unwrap-panic (is-domain-premium name)))
                (activity-level (unwrap-panic (get-domain-activity-level name)))
            )
            (ok {
                name: name,
                length: (len name),
                owner: (get owner domain-info),
                expires: (get expires domain-info),
                blocks-until-expiry: (if (> (get expires domain-info) burn-block-height)
                    (- (get expires domain-info) burn-block-height)
                    u0
                ),
                total-transfers: (get total-transfers analytics),
                reputation-score: reputation,
                is-premium: is-premium,
                activity-level: activity-level,
                is-listed: (match listing
                    market-entry (get listed market-entry)
                    false
                ),
                current-price: (match listing
                    market-entry (some (get price market-entry))
                    none
                ),
                estimated-value: (unwrap-panic (estimate-domain-value name))
            })
        )
        (err u404)
    )
)

(define-private (record-domain-history (name-str (string-ascii 50)) (event-type (string-ascii 20)) (from-owner (optional principal)) (to-owner principal) (price (optional uint)))
    (let
        (
            (new-history-id (+ (var-get last-history-id) u1))
            (current-analytics (default-to {total-transfers: u0, last-sale-price: none, highest-sale-price: none, total-history-count: u0} (map-get? domain-analytics {name: name-str})))
            (new-total-transfers (if (is-eq event-type "transfer") (+ (get total-transfers current-analytics) u1) (get total-transfers current-analytics)))
            (new-last-sale-price (if (is-some price) price (get last-sale-price current-analytics)))
            (new-highest-sale-price 
                (match price
                    sale-price (match (get highest-sale-price current-analytics)
                        current-high (some (if (> sale-price current-high) sale-price current-high))
                        (some sale-price)
                    )
                    (get highest-sale-price current-analytics)
                )
            )
            (new-total-count (+ (get total-history-count current-analytics) u1))
        )
        (var-set last-history-id new-history-id)
        (map-set domain-history
            {history-id: new-history-id}
            {domain-name: name-str, event-type: event-type, from-owner: from-owner, to-owner: to-owner, price: price, block-height: burn-block-height}
        )
        (map-set domain-history-by-name
            {name: name-str, index: new-total-count}
            {history-id: new-history-id}
        )
        (map-set domain-analytics
            {name: name-str}
            {total-transfers: new-total-transfers, last-sale-price: new-last-sale-price, highest-sale-price: new-highest-sale-price, total-history-count: new-total-count}
        )
        new-history-id
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
            (record-domain-history name "register" none tx-sender none)
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
        (map-set domain-names
            {name: name}
            (merge domain {owner: new-owner})
        )
        (record-domain-history name "transfer" (some current-owner) new-owner none)
        (ok true)
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
        (record-domain-history name "sale" (some domain-owner) tx-sender (some sale-price))
        (ok true)
    )
)

(define-public (create-subdomain (parent (string-ascii 50)) (subdomain (string-ascii 50)))
    (let
        (
            (parent-domain (unwrap! (map-get? domain-names {name: parent}) err-invalid-parent))
            (subdomain-length (len subdomain))
        )
        (asserts! (is-eq tx-sender (get owner parent-domain)) err-not-owner)
        (asserts! (> (get expires parent-domain) burn-block-height) err-expired)
        (asserts! (>= subdomain-length min-length) err-name-too-short)
        (asserts! (is-none (map-get? subdomains {parent: parent, subdomain: subdomain})) err-subdomain-exists)
        (try! (stx-transfer? subdomain-price tx-sender (var-get dao-address)))
        (ok (map-set subdomains
            {parent: parent, subdomain: subdomain}
            {owner: tx-sender, created: burn-block-height, active: true}
        ))
    )
)

(define-public (transfer-subdomain (parent (string-ascii 50)) (subdomain (string-ascii 50)) (new-owner principal))
    (let
        (
            (subdomain-info (unwrap! (map-get? subdomains {parent: parent, subdomain: subdomain}) (err u404)))
        )
        (asserts! (is-eq tx-sender (get owner subdomain-info)) err-not-owner)
        (asserts! (get active subdomain-info) err-not-for-sale)
        (ok (map-set subdomains
            {parent: parent, subdomain: subdomain}
            (merge subdomain-info {owner: new-owner})
        ))
    )
)

(define-public (deactivate-subdomain (parent (string-ascii 50)) (subdomain (string-ascii 50)))
    (let
        (
            (subdomain-info (unwrap! (map-get? subdomains {parent: parent, subdomain: subdomain}) (err u404)))
            (parent-domain (unwrap! (map-get? domain-names {name: parent}) err-invalid-parent))
        )
        (asserts! (or (is-eq tx-sender (get owner subdomain-info)) (is-eq tx-sender (get owner parent-domain))) err-not-owner)
        (ok (map-set subdomains
            {parent: parent, subdomain: subdomain}
            (merge subdomain-info {active: false})
        ))
    )
)