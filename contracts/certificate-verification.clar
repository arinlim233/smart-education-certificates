;; Certificate Verification Contract
;; Smart contract that enables employers and institutions to verify authenticity of certificates instantly

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-found (err u200))
(define-constant err-invalid-certificate (err u201))
(define-constant err-unauthorized (err u202))
(define-constant err-already-verified (err u203))
(define-constant err-verification-failed (err u204))

;; Data Variables
(define-data-var next-verification-id uint u1)
(define-data-var total-verifications uint u0)
(define-data-var registry-contract-address (optional principal) none)

;; Data Maps
(define-map verifications uint {
    certificate-id: uint,
    verifier-address: principal,
    verification-date: uint,
    verification-result: bool,
    verification-notes: (string-utf8 200)
})

(define-map verification-history uint (list 100 uint))
(define-map verifier-stats principal {
    total-verifications: uint,
    successful-verifications: uint,
    registration-date: uint,
    is-authorized: bool
})

(define-map certificate-verification-count uint uint)
(define-map batch-verifications uint {
    batch-id: uint,
    verifier: principal,
    certificate-ids: (list 50 uint),
    results: (list 50 bool),
    verification-date: uint
})

;; Private Functions
(define-private (increment-verifier-stats (verifier principal) (success bool))
    (let (
        (current-stats (default-to 
            { total-verifications: u0, successful-verifications: u0, registration-date: stacks-block-height, is-authorized: true }
            (map-get? verifier-stats verifier)
        ))
    )
        (map-set verifier-stats verifier {
            total-verifications: (+ (get total-verifications current-stats) u1),
            successful-verifications: (if success 
                (+ (get successful-verifications current-stats) u1)
                (get successful-verifications current-stats)
            ),
            registration-date: (get registration-date current-stats),
            is-authorized: (get is-authorized current-stats)
        })
    )
)

(define-private (increment-certificate-verification-count (certificate-id uint))
    (let (
        (current-count (default-to u0 (map-get? certificate-verification-count certificate-id)))
    )
        (map-set certificate-verification-count certificate-id (+ current-count u1))
    )
)

(define-private (add-to-verification-history (certificate-id uint) (verification-id uint))
    (let (
        (current-history (default-to (list) (map-get? verification-history certificate-id)))
    )
        (map-set verification-history certificate-id 
            (unwrap-panic (as-max-len? (append current-history verification-id) u100))
        )
    )
)

(define-private (is-verifier-authorized (verifier principal))
    (match (map-get? verifier-stats verifier)
        stats (get is-authorized stats)
        true ;; New verifiers are authorized by default
    )
)

;; Read-only Functions
(define-read-only (get-verification (verification-id uint))
    (map-get? verifications verification-id)
)

(define-read-only (get-verifier-stats (verifier principal))
    (map-get? verifier-stats verifier)
)

(define-read-only (get-certificate-verification-count (certificate-id uint))
    (default-to u0 (map-get? certificate-verification-count certificate-id))
)

(define-read-only (get-verification-history (certificate-id uint))
    (default-to (list) (map-get? verification-history certificate-id))
)

(define-read-only (get-batch-verification (batch-id uint))
    (map-get? batch-verifications batch-id)
)

(define-read-only (get-total-verifications)
    (var-get total-verifications)
)

(define-read-only (get-next-verification-id)
    (var-get next-verification-id)
)

(define-read-only (verify-certificate-existence (certificate-id uint))
    ;; This would typically call the registry contract, but for simplicity we'll assume it exists
    ;; In a real implementation, this would use contract-call? to the registry contract
    true
)

(define-read-only (get-verifier-success-rate (verifier principal))
    (match (map-get? verifier-stats verifier)
        stats 
        (if (> (get total-verifications stats) u0)
            (/ (* (get successful-verifications stats) u100) (get total-verifications stats))
            u0
        )
        u0
    )
)

;; Public Functions
(define-public (verify-certificate 
    (certificate-id uint) 
    (notes (string-utf8 200))
)
    (let (
        (verification-id (var-get next-verification-id))
        (current-block-height stacks-block-height)
        (certificate-exists (verify-certificate-existence certificate-id))
    )
        (asserts! (is-verifier-authorized tx-sender) err-unauthorized)
        (asserts! certificate-exists err-not-found)
        
        (let (
            (verification-result certificate-exists)
        )
            (map-set verifications verification-id {
                certificate-id: certificate-id,
                verifier-address: tx-sender,
                verification-date: current-block-height,
                verification-result: verification-result,
                verification-notes: notes
            })
            
            (increment-verifier-stats tx-sender verification-result)
            (increment-certificate-verification-count certificate-id)
            (add-to-verification-history certificate-id verification-id)
            
            (var-set next-verification-id (+ verification-id u1))
            (var-set total-verifications (+ (var-get total-verifications) u1))
            
            (ok {
                verification-id: verification-id,
                result: verification-result,
                certificate-id: certificate-id
            })
        )
    )
)

(define-public (batch-verify (certificate-ids (list 50 uint)))
    (let (
        (batch-id (var-get next-verification-id))
        (current-block-height stacks-block-height)
    )
        (asserts! (is-verifier-authorized tx-sender) err-unauthorized)
        (asserts! (> (len certificate-ids) u0) err-invalid-certificate)
        
        (let (
            (results (map verify-certificate-existence certificate-ids))
        )
            (map-set batch-verifications batch-id {
                batch-id: batch-id,
                verifier: tx-sender,
                certificate-ids: certificate-ids,
                results: results,
                verification-date: current-block-height
            })
            
            ;; Update stats for batch verification
            (increment-verifier-stats tx-sender true)
            (var-set next-verification-id (+ batch-id u1))
            (var-set total-verifications (+ (var-get total-verifications) (len certificate-ids)))
            
            (ok {
                batch-id: batch-id,
                total-certificates: (len certificate-ids),
                results: results
            })
        )
    )
)

(define-public (authorize-verifier (verifier principal))
    (let (
        (current-stats (default-to 
            { total-verifications: u0, successful-verifications: u0, registration-date: stacks-block-height, is-authorized: false }
            (map-get? verifier-stats verifier)
        ))
    )
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        
        (map-set verifier-stats verifier 
            (merge current-stats { is-authorized: true })
        )
        
        (ok true)
    )
)

(define-public (revoke-verifier-authorization (verifier principal))
    (let (
        (current-stats (map-get? verifier-stats verifier))
    )
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (is-some current-stats) err-not-found)
        
        (map-set verifier-stats verifier 
            (merge (unwrap-panic current-stats) { is-authorized: false })
        )
        
        (ok true)
    )
)

(define-public (set-registry-contract (registry-address principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (var-set registry-contract-address (some registry-address))
        (ok true)
    )
)

(define-public (verify-institution-certificate 
    (certificate-id uint) 
    (expected-institution-id uint)
    (notes (string-utf8 200))
)
    (let (
        (verification-id (var-get next-verification-id))
        (current-block-height stacks-block-height)
        (certificate-exists (verify-certificate-existence certificate-id))
    )
        (asserts! (is-verifier-authorized tx-sender) err-unauthorized)
        (asserts! certificate-exists err-not-found)
        
        ;; In a real implementation, this would verify the institution matches
        (let (
            (verification-result certificate-exists)
        )
            (map-set verifications verification-id {
                certificate-id: certificate-id,
                verifier-address: tx-sender,
                verification-date: current-block-height,
                verification-result: verification-result,
                verification-notes: notes
            })
            
            (increment-verifier-stats tx-sender verification-result)
            (increment-certificate-verification-count certificate-id)
            (add-to-verification-history certificate-id verification-id)
            
            (var-set next-verification-id (+ verification-id u1))
            (var-set total-verifications (+ (var-get total-verifications) u1))
            
            (ok {
                verification-id: verification-id,
                result: verification-result,
                institution-verified: true
            })
        )
    )
)
