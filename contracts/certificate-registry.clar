;; Certificate Registry Contract
;; Smart contract for registering and issuing verifiable academic certificates on-chain

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-institution (err u103))
(define-constant err-unauthorized (err u104))

;; Data Variables
(define-data-var next-certificate-id uint u1)
(define-data-var next-institution-id uint u1)

;; Data Maps
(define-map institutions uint {
    name: (string-ascii 100),
    address: principal,
    is-active: bool,
    registration-date: uint,
    total-certificates-issued: uint
})

(define-map certificates uint {
    institution-id: uint,
    student-name: (string-utf8 100),
    student-id: (string-ascii 50),
    course-name: (string-utf8 150),
    grade: (string-ascii 10),
    issue-date: uint,
    certificate-hash: (buff 32),
    is-valid: bool
})

(define-map institution-by-address principal uint)
(define-map certificate-by-hash (buff 32) uint)

;; Private Functions
(define-private (is-institution-valid (institution-id uint))
    (match (map-get? institutions institution-id)
        institution (get is-active institution)
        false
    )
)

(define-private (get-institution-by-address (address principal))
    (map-get? institution-by-address address)
)

(define-private (increment-institution-certificates (institution-id uint))
    (match (map-get? institutions institution-id)
        institution 
        (map-set institutions institution-id
            (merge institution {
                total-certificates-issued: (+ (get total-certificates-issued institution) u1)
            })
        )
        false
    )
)

(define-private (create-certificate-hash (student-id (string-ascii 50)) (course-name (string-utf8 150)) (issue-date uint))
    (keccak256 (concat 
        (unwrap-panic (to-consensus-buff? student-id))
        (concat 
            (unwrap-panic (to-consensus-buff? course-name))
            (unwrap-panic (to-consensus-buff? issue-date))
        )
    ))
)

;; Read-only Functions
(define-read-only (get-certificate (certificate-id uint))
    (map-get? certificates certificate-id)
)

(define-read-only (get-institution (institution-id uint))
    (map-get? institutions institution-id)
)

(define-read-only (get-certificate-by-hash (cert-hash (buff 32)))
    (match (map-get? certificate-by-hash cert-hash)
        certificate-id (map-get? certificates certificate-id)
        none
    )
)

(define-read-only (get-institution-stats (institution-id uint))
    (match (map-get? institutions institution-id)
        institution (some {
            name: (get name institution),
            total-certificates: (get total-certificates-issued institution),
            is-active: (get is-active institution),
            registration-date: (get registration-date institution)
        })
        none
    )
)

(define-read-only (is-certificate-valid (certificate-id uint))
    (match (map-get? certificates certificate-id)
        certificate (get is-valid certificate)
        false
    )
)

(define-read-only (get-next-certificate-id)
    (var-get next-certificate-id)
)

(define-read-only (get-next-institution-id)
    (var-get next-institution-id)
)

;; Public Functions
(define-public (register-institution (name (string-ascii 100)) (institution-address principal))
    (let (
        (institution-id (var-get next-institution-id))
        (current-block-height stacks-block-height)
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (get-institution-by-address institution-address)) err-already-exists)
        
        (map-set institutions institution-id {
            name: name,
            address: institution-address,
            is-active: true,
            registration-date: current-block-height,
            total-certificates-issued: u0
        })
        
        (map-set institution-by-address institution-address institution-id)
        (var-set next-institution-id (+ institution-id u1))
        
        (ok institution-id)
    )
)

(define-public (issue-certificate 
    (student-name (string-utf8 100))
    (student-id (string-ascii 50))
    (course-name (string-utf8 150))
    (grade (string-ascii 10))
)
    (let (
        (certificate-id (var-get next-certificate-id))
        (current-block-height stacks-block-height)
        (institution-id-opt (get-institution-by-address tx-sender))
        (cert-hash (create-certificate-hash student-id course-name current-block-height))
    )
        (asserts! (is-some institution-id-opt) err-unauthorized)
        
        (let ((institution-id (unwrap-panic institution-id-opt)))
            (asserts! (is-institution-valid institution-id) err-invalid-institution)
            (asserts! (is-none (map-get? certificate-by-hash cert-hash)) err-already-exists)
            
            (map-set certificates certificate-id {
                institution-id: institution-id,
                student-name: student-name,
                student-id: student-id,
                course-name: course-name,
                grade: grade,
                issue-date: current-block-height,
                certificate-hash: cert-hash,
                is-valid: true
            })
            
            (map-set certificate-by-hash cert-hash certificate-id)
            (increment-institution-certificates institution-id)
            (var-set next-certificate-id (+ certificate-id u1))
            
            (ok certificate-id)
        )
    )
)

(define-public (revoke-certificate (certificate-id uint))
    (let (
        (certificate-opt (map-get? certificates certificate-id))
        (institution-id-opt (get-institution-by-address tx-sender))
    )
        (asserts! (is-some certificate-opt) err-not-found)
        (asserts! (is-some institution-id-opt) err-unauthorized)
        
        (let (
            (certificate (unwrap-panic certificate-opt))
            (institution-id (unwrap-panic institution-id-opt))
        )
            (asserts! (is-eq (get institution-id certificate) institution-id) err-unauthorized)
            
            (map-set certificates certificate-id
                (merge certificate { is-valid: false })
            )
            
            (ok true)
        )
    )
)

(define-public (deactivate-institution (institution-id uint))
    (let (
        (institution-opt (map-get? institutions institution-id))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-some institution-opt) err-not-found)
        
        (let ((institution (unwrap-panic institution-opt)))
            (map-set institutions institution-id
                (merge institution { is-active: false })
            )
            
            (ok true)
        )
    )
)

(define-public (reactivate-institution (institution-id uint))
    (let (
        (institution-opt (map-get? institutions institution-id))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-some institution-opt) err-not-found)
        
        (let ((institution (unwrap-panic institution-opt)))
            (map-set institutions institution-id
                (merge institution { is-active: true })
            )
            
            (ok true)
        )
    )
)
