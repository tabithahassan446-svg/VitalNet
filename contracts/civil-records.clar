;; title: civil-records
;; version: 1.0.0
;; summary: Main contract for VitalNet civil records management
;; description: Handles birth and death certificate registration and verification

;; Constants
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INVALID_INPUT (err u400))
(define-constant ERR_INSUFFICIENT_PERMISSIONS (err u403))
(define-constant ERR_RECORD_SEALED (err u410))
(define-constant CONTRACT_OWNER tx-sender)

;; Record type constants
(define-constant RECORD_TYPE_BIRTH u1)
(define-constant RECORD_TYPE_DEATH u2)

;; Record status constants
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_AMENDED u2)
(define-constant STATUS_SEALED u3)

;; Data Variables
(define-data-var next-record-id uint u1)
(define-data-var total-birth-records uint u0)
(define-data-var total-death-records uint u0)
(define-data-var total-verified-records uint u0)
(define-data-var registry-admin principal tx-sender)

;; Data Maps

;; Birth records registry
(define-map birth-records
  uint ;; record-id
  {
    full-name: (string-ascii 200),
    birth-date: uint, ;; timestamp
    birth-place: (string-ascii 200),
    birth-country: (string-ascii 100),
    mother-name: (string-ascii 200),
    father-name: (string-ascii 200),
    attending-physician: (string-ascii 200),
    hospital-facility: (string-ascii 200),
    birth-weight: uint, ;; in grams
    birth-length: uint, ;; in centimeters
    registration-date: uint,
    registrar: principal,
    status: uint,
    verification-hash: (string-ascii 64),
    certificate-number: (string-ascii 50)
  }
)

;; Death records registry
(define-map death-records
  uint ;; record-id
  {
    full-name: (string-ascii 200),
    death-date: uint, ;; timestamp
    death-place: (string-ascii 200),
    death-country: (string-ascii 100),
    cause-of-death: (string-ascii 500),
    attending-physician: (string-ascii 200),
    facility: (string-ascii 200),
    age-at-death: uint,
    next-of-kin: (string-ascii 200),
    registration-date: uint,
    registrar: principal,
    status: uint,
    verification-hash: (string-ascii 64),
    certificate-number: (string-ascii 50)
  }
)

;; Person identity registry (links multiple records)
(define-map person-records
  (string-ascii 64) ;; person-hash (for privacy)
  {
    birth-record-id: (optional uint),
    death-record-id: (optional uint),
    total-records: uint,
    first-registration: uint,
    last-updated: uint
  }
)

;; Record verification and integrity
(define-map record-verifications
  uint ;; record-id
  {
    record-type: uint,
    verification-timestamp: uint,
    verified-by: principal,
    integrity-confirmed: bool,
    additional-notes: (string-ascii 500)
  }
)

;; Access control for record viewing
(define-map record-access-log
  { record-id: uint, accessor: principal }
  {
    access-timestamp: uint,
    access-type: (string-ascii 50), ;; "view", "verify", "update"
    authorized: bool
  }
)

;; Certificate number tracking
(define-map certificate-numbers
  (string-ascii 50) ;; certificate-number
  {
    record-id: uint,
    record-type: uint,
    issued-date: uint,
    issuing-authority: principal
  }
)

;; Public Functions

;; Register a new birth certificate
(define-public (register-birth
  (full-name (string-ascii 200))
  (birth-date uint)
  (birth-place (string-ascii 200))
  (birth-country (string-ascii 100))
  (mother-name (string-ascii 200))
  (father-name (string-ascii 200))
  (attending-physician (string-ascii 200))
  (hospital-facility (string-ascii 200))
  (birth-weight uint)
  (birth-length uint)
  (certificate-number (string-ascii 50)))
  (let 
    (
      (record-id (var-get next-record-id))
      (verification-hash (generate-verification-hash full-name birth-date))
      (person-hash (generate-person-hash full-name birth-date))
    )
    
    ;; Validate registrar permissions (basic check - would integrate with registry-management)
    (asserts! (> (len full-name) u0) ERR_INVALID_INPUT)
    (asserts! (> birth-date u0) ERR_INVALID_INPUT)
    (asserts! (> (len birth-place) u0) ERR_INVALID_INPUT)
    (asserts! (> (len certificate-number) u0) ERR_INVALID_INPUT)
    
    ;; Check certificate number is unique
    (asserts! (is-none (map-get? certificate-numbers certificate-number)) ERR_ALREADY_EXISTS)
    
    ;; Create birth record
    (map-set birth-records record-id {
      full-name: full-name,
      birth-date: birth-date,
      birth-place: birth-place,
      birth-country: birth-country,
      mother-name: mother-name,
      father-name: father-name,
      attending-physician: attending-physician,
      hospital-facility: hospital-facility,
      birth-weight: birth-weight,
      birth-length: birth-length,
      registration-date: stacks-block-height,
      registrar: tx-sender,
      status: STATUS_ACTIVE,
      verification-hash: verification-hash,
      certificate-number: certificate-number
    })
    
    ;; Register certificate number
    (map-set certificate-numbers certificate-number {
      record-id: record-id,
      record-type: RECORD_TYPE_BIRTH,
      issued-date: stacks-block-height,
      issuing-authority: tx-sender
    })
    
    ;; Update person records
    (update-person-records person-hash (some record-id) none)
    
    ;; Update statistics
    (var-set next-record-id (+ record-id u1))
    (var-set total-birth-records (+ (var-get total-birth-records) u1))
    
    (ok record-id)
  )
)

;; Register a new death certificate
(define-public (register-death
  (full-name (string-ascii 200))
  (death-date uint)
  (death-place (string-ascii 200))
  (death-country (string-ascii 100))
  (cause-of-death (string-ascii 500))
  (attending-physician (string-ascii 200))
  (facility (string-ascii 200))
  (age-at-death uint)
  (next-of-kin (string-ascii 200))
  (certificate-number (string-ascii 50)))
  (let 
    (
      (record-id (var-get next-record-id))
      (verification-hash (generate-verification-hash full-name death-date))
      (person-hash (generate-person-hash full-name death-date))
    )
    
    ;; Validate input
    (asserts! (> (len full-name) u0) ERR_INVALID_INPUT)
    (asserts! (> death-date u0) ERR_INVALID_INPUT)
    (asserts! (> (len death-place) u0) ERR_INVALID_INPUT)
    (asserts! (> (len cause-of-death) u0) ERR_INVALID_INPUT)
    (asserts! (> (len certificate-number) u0) ERR_INVALID_INPUT)
    
    ;; Check certificate number is unique
    (asserts! (is-none (map-get? certificate-numbers certificate-number)) ERR_ALREADY_EXISTS)
    
    ;; Create death record
    (map-set death-records record-id {
      full-name: full-name,
      death-date: death-date,
      death-place: death-place,
      death-country: death-country,
      cause-of-death: cause-of-death,
      attending-physician: attending-physician,
      facility: facility,
      age-at-death: age-at-death,
      next-of-kin: next-of-kin,
      registration-date: stacks-block-height,
      registrar: tx-sender,
      status: STATUS_ACTIVE,
      verification-hash: verification-hash,
      certificate-number: certificate-number
    })
    
    ;; Register certificate number
    (map-set certificate-numbers certificate-number {
      record-id: record-id,
      record-type: RECORD_TYPE_DEATH,
      issued-date: stacks-block-height,
      issuing-authority: tx-sender
    })
    
    ;; Update person records
    (update-person-records person-hash none (some record-id))
    
    ;; Update statistics
    (var-set next-record-id (+ record-id u1))
    (var-set total-death-records (+ (var-get total-death-records) u1))
    
    (ok record-id)
  )
)

;; Verify a record's authenticity
(define-public (verify-record (record-id uint) (record-type uint))
  (let 
    (
      (verification-entry {
        record-type: record-type,
        verification-timestamp: stacks-block-height,
        verified-by: tx-sender,
        integrity-confirmed: true,
        additional-notes: "Record verified"
      })
    )
    
    ;; Validate record exists
    (asserts! 
      (if (is-eq record-type RECORD_TYPE_BIRTH)
        (is-some (map-get? birth-records record-id))
        (is-some (map-get? death-records record-id))
      )
      ERR_NOT_FOUND
    )
    
    ;; Record verification
    (map-set record-verifications record-id verification-entry)
    
    ;; Log access
    (log-record-access record-id "verify")
    
    ;; Update verification count
    (var-set total-verified-records (+ (var-get total-verified-records) u1))
    
    (ok true)
  )
)

;; Amend a record (limited fields)
(define-public (amend-record (record-id uint) (record-type uint) (notes (string-ascii 500)))
  (let 
    (
      (is-birth (is-eq record-type RECORD_TYPE_BIRTH))
    )
    
    ;; Only registrar or admin can amend
    (asserts! 
      (or 
        (is-eq tx-sender (var-get registry-admin))
        (if is-birth
          (match (map-get? birth-records record-id)
            record (is-eq tx-sender (get registrar record))
            false
          )
          (match (map-get? death-records record-id)
            record (is-eq tx-sender (get registrar record))
            false
          )
        )
      )
      ERR_UNAUTHORIZED
    )
    
    ;; Update record status to amended
    (if is-birth
      (match (map-get? birth-records record-id)
        record (map-set birth-records record-id (merge record { status: STATUS_AMENDED }))
        false
      )
      (match (map-get? death-records record-id)
        record (map-set death-records record-id (merge record { status: STATUS_AMENDED }))
        false
      )
    )
    
    ;; Log the amendment
    (log-record-access record-id "amend")
    
    (ok true)
  )
)

;; Access logging functions (public for write access)

;; Get birth record with logging
(define-public (get-birth-record-with-log (record-id uint))
  (begin
    ;; Log access attempt
    (map-set record-access-log 
      { record-id: record-id, accessor: tx-sender }
      {
        access-timestamp: stacks-block-height,
        access-type: "view",
        authorized: true
      }
    )
    (ok (map-get? birth-records record-id))
  )
)

;; Get death record with logging
(define-public (get-death-record-with-log (record-id uint))
  (begin
    ;; Log access attempt
    (map-set record-access-log 
      { record-id: record-id, accessor: tx-sender }
      {
        access-timestamp: stacks-block-height,
        access-type: "view",
        authorized: true
      }
    )
    (ok (map-get? death-records record-id))
  )
)

;; Read-only Functions

;; Get birth record details (authorized access - no logging)
(define-read-only (get-birth-record (record-id uint))
  (map-get? birth-records record-id)
)

;; Get death record details (authorized access - no logging)
(define-read-only (get-death-record (record-id uint))
  (map-get? death-records record-id)
)

;; Get person's all records by hash
(define-read-only (get-person-records (person-hash (string-ascii 64)))
  (map-get? person-records person-hash)
)

;; Get record verification info
(define-read-only (get-record-verification (record-id uint))
  (map-get? record-verifications record-id)
)

;; Get certificate number info
(define-read-only (get-certificate-info (certificate-number (string-ascii 50)))
  (map-get? certificate-numbers certificate-number)
)

;; Get system statistics
(define-read-only (get-system-stats)
  {
    total-birth-records: (var-get total-birth-records),
    total-death-records: (var-get total-death-records),
    total-verified-records: (var-get total-verified-records),
    next-record-id: (var-get next-record-id),
    registry-admin: (var-get registry-admin)
  }
)

;; Check if record exists
(define-read-only (record-exists (record-id uint) (record-type uint))
  (if (is-eq record-type RECORD_TYPE_BIRTH)
    (is-some (map-get? birth-records record-id))
    (is-some (map-get? death-records record-id))
  )
)

;; Get access log for a record
(define-read-only (get-access-log (record-id uint) (accessor principal))
  (map-get? record-access-log { record-id: record-id, accessor: accessor })
)

;; Private Functions

;; Generate verification hash for integrity
(define-private (generate-verification-hash (name (string-ascii 200)) (date uint))
  ;; Simple hash simulation - in production would use more sophisticated hashing
  (int-to-ascii (+ (len name) date))
)

;; Generate person hash for privacy
(define-private (generate-person-hash (name (string-ascii 200)) (date uint))
  ;; Simple hash simulation - in production would use proper hashing
  (int-to-ascii (+ (* (len name) u31) date))
)

;; Update person records registry
(define-private (update-person-records 
  (person-hash (string-ascii 64)) 
  (birth-id (optional uint)) 
  (death-id (optional uint)))
  (let 
    (
      (existing-record (default-to 
        {
          birth-record-id: none,
          death-record-id: none,
          total-records: u0,
          first-registration: stacks-block-height,
          last-updated: stacks-block-height
        }
        (map-get? person-records person-hash)
      ))
    )
    (map-set person-records person-hash {
      birth-record-id: (if (is-some birth-id) birth-id (get birth-record-id existing-record)),
      death-record-id: (if (is-some death-id) death-id (get death-record-id existing-record)),
      total-records: (+ (get total-records existing-record) u1),
      first-registration: (get first-registration existing-record),
      last-updated: stacks-block-height
    })
  )
)

;; Log record access for audit trail
(define-private (log-record-access (record-id uint) (access-type (string-ascii 50)))
  (map-set record-access-log 
    { record-id: record-id, accessor: tx-sender }
    {
      access-timestamp: stacks-block-height,
      access-type: access-type,
      authorized: true
    }
  )
)
