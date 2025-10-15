;; title: registry-management
;; version: 1.0.0
;; summary: Registry management contract for VitalNet authorization system
;; description: Manages registrar authorization, permissions, and administrative functions

;; Constants
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INVALID_INPUT (err u400))
(define-constant ERR_INSUFFICIENT_PERMISSIONS (err u403))
(define-constant ERR_ADMIN_REQUIRED (err u402))
(define-constant CONTRACT_OWNER tx-sender)

;; Authorization level constants
(define-constant AUTH_LEVEL_VIEWER u1)
(define-constant AUTH_LEVEL_REGISTRAR u2)
(define-constant AUTH_LEVEL_SENIOR_REGISTRAR u3)
(define-constant AUTH_LEVEL_ADMINISTRATOR u4)

;; Registrar status constants
(define-constant STATUS_PENDING u1)
(define-constant STATUS_ACTIVE u2)
(define-constant STATUS_SUSPENDED u3)
(define-constant STATUS_REVOKED u4)

;; Institution type constants
(define-constant INSTITUTION_HOSPITAL u1)
(define-constant INSTITUTION_GOVERNMENT u2)
(define-constant INSTITUTION_CLINIC u3)
(define-constant INSTITUTION_OTHER u4)

;; Data Variables
(define-data-var system-admin principal tx-sender)
(define-data-var total-registrars uint u0)
(define-data-var total-active-registrars uint u0)
(define-data-var total-authorization-requests uint u0)
(define-data-var system-maintenance-mode bool false)

;; Data Maps

;; Registrar profiles and authorization
(define-map registrars
  principal
  {
    institution-name: (string-ascii 200),
    institution-type: uint,
    license-number: (string-ascii 100),
    jurisdiction: (string-ascii 100),
    contact-person: (string-ascii 200),
    email: (string-ascii 100),
    phone: (string-ascii 20),
    address: (string-ascii 300),
    authorization-level: uint,
    status: uint,
    registration-date: uint,
    last-activity: uint,
    authorized-by: principal,
    total-records-created: uint,
    reputation-score: uint
  }
)

;; Authorization requests from potential registrars
(define-map authorization-requests
  principal
  {
    institution-name: (string-ascii 200),
    institution-type: uint,
    license-number: (string-ascii 100),
    jurisdiction: (string-ascii 100),
    contact-person: (string-ascii 200),
    email: (string-ascii 100),
    phone: (string-ascii 20),
    address: (string-ascii 300),
    requested-level: uint,
    request-date: uint,
    supporting-documents: (string-ascii 500),
    request-notes: (string-ascii 1000),
    reviewed-by: (optional principal),
    review-date: (optional uint),
    review-status: uint
  }
)

;; Administrative actions log
(define-map admin-actions
  { action-id: uint, admin: principal }
  {
    action-type: (string-ascii 50), ;; "authorize", "revoke", "suspend", "modify"
    target-registrar: principal,
    timestamp: uint,
    details: (string-ascii 500),
    previous-values: (string-ascii 500)
  }
)

;; Jurisdiction management
(define-map jurisdictions
  (string-ascii 100) ;; jurisdiction-name
  {
    lead-registrar: (optional principal),
    total-registrars: uint,
    total-records: uint,
    established-date: uint,
    contact-info: (string-ascii 200)
  }
)

;; System configuration parameters
(define-map system-config
  (string-ascii 50) ;; config-key
  {
    value: uint,
    description: (string-ascii 200),
    last-updated: uint,
    updated-by: principal
  }
)

;; Registrar activity tracking
(define-map registrar-activity
  { registrar: principal, month: uint } ;; month as YYYYMM
  {
    records-created: uint,
    records-verified: uint,
    last-login: uint,
    activity-score: uint
  }
)

;; Action counter for logging
(define-data-var next-action-id uint u1)

;; Public Functions

;; Request authorization as a registrar
(define-public (request-authorization
  (institution-name (string-ascii 200))
  (institution-type uint)
  (license-number (string-ascii 100))
  (jurisdiction (string-ascii 100))
  (contact-person (string-ascii 200))
  (email (string-ascii 100))
  (phone (string-ascii 20))
  (address (string-ascii 300))
  (requested-level uint)
  (supporting-documents (string-ascii 500))
  (request-notes (string-ascii 1000)))
  (begin
    ;; Check if request already exists
    (asserts! (is-none (map-get? authorization-requests tx-sender)) ERR_ALREADY_EXISTS)
    
    ;; Validate input parameters
    (asserts! (> (len institution-name) u0) ERR_INVALID_INPUT)
    (asserts! (<= institution-type INSTITUTION_OTHER) ERR_INVALID_INPUT)
    (asserts! (>= institution-type INSTITUTION_HOSPITAL) ERR_INVALID_INPUT)
    (asserts! (<= requested-level AUTH_LEVEL_ADMINISTRATOR) ERR_INVALID_INPUT)
    (asserts! (>= requested-level AUTH_LEVEL_VIEWER) ERR_INVALID_INPUT)
    (asserts! (> (len license-number) u0) ERR_INVALID_INPUT)
    (asserts! (> (len jurisdiction) u0) ERR_INVALID_INPUT)
    
    ;; Create authorization request
    (map-set authorization-requests tx-sender {
      institution-name: institution-name,
      institution-type: institution-type,
      license-number: license-number,
      jurisdiction: jurisdiction,
      contact-person: contact-person,
      email: email,
      phone: phone,
      address: address,
      requested-level: requested-level,
      request-date: stacks-block-height,
      supporting-documents: supporting-documents,
      request-notes: request-notes,
      reviewed-by: none,
      review-date: none,
      review-status: STATUS_PENDING
    })
    
    ;; Update statistics
    (var-set total-authorization-requests (+ (var-get total-authorization-requests) u1))
    
    (ok true)
  )
)

;; Authorize a registrar (admin only)
(define-public (authorize-registrar 
  (registrar-address principal)
  (authorization-level uint)
  (approved bool))
  (let 
    (
      (request-info (unwrap! (map-get? authorization-requests registrar-address) ERR_NOT_FOUND))
      (action-id (var-get next-action-id))
    )
    
    ;; Only admin can authorize
    (asserts! (is-eq tx-sender (var-get system-admin)) ERR_ADMIN_REQUIRED)
    
    ;; Validate authorization level
    (asserts! (<= authorization-level AUTH_LEVEL_ADMINISTRATOR) ERR_INVALID_INPUT)
    (asserts! (>= authorization-level AUTH_LEVEL_VIEWER) ERR_INVALID_INPUT)
    
    (if approved
      (begin
        ;; Create registrar profile
        (map-set registrars registrar-address {
          institution-name: (get institution-name request-info),
          institution-type: (get institution-type request-info),
          license-number: (get license-number request-info),
          jurisdiction: (get jurisdiction request-info),
          contact-person: (get contact-person request-info),
          email: (get email request-info),
          phone: (get phone request-info),
          address: (get address request-info),
          authorization-level: authorization-level,
          status: STATUS_ACTIVE,
          registration-date: stacks-block-height,
          last-activity: stacks-block-height,
          authorized-by: tx-sender,
          total-records-created: u0,
          reputation-score: u100
        })
        
        ;; Update jurisdiction info
        (update-jurisdiction-stats (get jurisdiction request-info) registrar-address)
        
        ;; Update statistics
        (var-set total-registrars (+ (var-get total-registrars) u1))
        (var-set total-active-registrars (+ (var-get total-active-registrars) u1))
      )
      true ;; Request denied, no registrar created
    )
    
    ;; Update request status
    (map-set authorization-requests registrar-address (merge request-info {
      reviewed-by: (some tx-sender),
      review-date: (some stacks-block-height),
      review-status: (if approved STATUS_ACTIVE STATUS_REVOKED)
    }))
    
    ;; Log admin action
    (log-admin-action action-id "authorize" registrar-address 
      (if approved "Registrar authorized" "Authorization denied") "")
    
    (ok approved)
  )
)

;; Update registrar information
(define-public (update-registrar-info
  (registrar-address principal)
  (new-authorization-level uint)
  (new-status uint))
  (let 
    (
      (registrar-info (unwrap! (map-get? registrars registrar-address) ERR_NOT_FOUND))
      (action-id (var-get next-action-id))
      (previous-values (concat-strings 
        (int-to-ascii (get authorization-level registrar-info))
        (int-to-ascii (get status registrar-info))
      ))
    )
    
    ;; Only admin can update registrar info
    (asserts! (is-eq tx-sender (var-get system-admin)) ERR_ADMIN_REQUIRED)
    
    ;; Validate new values
    (asserts! (<= new-authorization-level AUTH_LEVEL_ADMINISTRATOR) ERR_INVALID_INPUT)
    (asserts! (>= new-authorization-level AUTH_LEVEL_VIEWER) ERR_INVALID_INPUT)
    (asserts! (<= new-status STATUS_REVOKED) ERR_INVALID_INPUT)
    (asserts! (>= new-status STATUS_PENDING) ERR_INVALID_INPUT)
    
    ;; Update registrar information
    (map-set registrars registrar-address (merge registrar-info {
      authorization-level: new-authorization-level,
      status: new-status,
      last-activity: stacks-block-height
    }))
    
    ;; Update active registrars count if status changed
    (if (and 
          (is-eq (get status registrar-info) STATUS_ACTIVE)
          (not (is-eq new-status STATUS_ACTIVE))
        )
      (var-set total-active-registrars (- (var-get total-active-registrars) u1))
      (if (and 
            (not (is-eq (get status registrar-info) STATUS_ACTIVE))
            (is-eq new-status STATUS_ACTIVE)
          )
        (var-set total-active-registrars (+ (var-get total-active-registrars) u1))
        true
      )
    )
    
    ;; Log admin action
    (log-admin-action action-id "modify" registrar-address 
      "Registrar information updated" previous-values)
    
    (ok true)
  )
)

;; Revoke registrar authorization
(define-public (revoke-registrar (registrar-address principal) (reason (string-ascii 500)))
  (let 
    (
      (registrar-info (unwrap! (map-get? registrars registrar-address) ERR_NOT_FOUND))
      (action-id (var-get next-action-id))
    )
    
    ;; Only admin can revoke
    (asserts! (is-eq tx-sender (var-get system-admin)) ERR_ADMIN_REQUIRED)
    
    ;; Update registrar status
    (map-set registrars registrar-address (merge registrar-info {
      status: STATUS_REVOKED,
      last-activity: stacks-block-height
    }))
    
    ;; Update active registrars count
    (if (is-eq (get status registrar-info) STATUS_ACTIVE)
      (var-set total-active-registrars (- (var-get total-active-registrars) u1))
      true
    )
    
    ;; Log admin action
    (log-admin-action action-id "revoke" registrar-address reason "")
    
    (ok true)
  )
)

;; Update system configuration (admin only)
(define-public (update-system-config 
  (config-key (string-ascii 50))
  (new-value uint)
  (description (string-ascii 200)))
  (begin
    ;; Only admin can update system config
    (asserts! (is-eq tx-sender (var-get system-admin)) ERR_ADMIN_REQUIRED)
    
    ;; Update configuration
    (map-set system-config config-key {
      value: new-value,
      description: description,
      last-updated: stacks-block-height,
      updated-by: tx-sender
    })
    
    (ok true)
  )
)

;; Record registrar activity
(define-public (record-activity 
  (registrar-address principal)
  (activity-type (string-ascii 20))
  (count uint))
  (let 
    (
      (current-month (get-current-month))
      (existing-activity (default-to 
        {
          records-created: u0,
          records-verified: u0,
          last-login: u0,
          activity-score: u0
        }
        (map-get? registrar-activity { registrar: registrar-address, month: current-month })
      ))
    )
    
    ;; Update activity based on type
    (let 
      (
        (updated-activity 
          (if (is-eq activity-type "create")
            (merge existing-activity { 
              records-created: (+ (get records-created existing-activity) count),
              last-login: stacks-block-height
            })
            (if (is-eq activity-type "verify")
              (merge existing-activity { 
                records-verified: (+ (get records-verified existing-activity) count),
                last-login: stacks-block-height
              })
              (merge existing-activity { 
                last-login: stacks-block-height
              })
            )
          )
        )
      )
      
      ;; Update activity record
      (map-set registrar-activity 
        { registrar: registrar-address, month: current-month }
        (merge updated-activity {
          activity-score: (calculate-activity-score updated-activity)
        })
      )
    )
    
    (ok true)
  )
)

;; Read-only Functions

;; Get registrar information
(define-read-only (get-registrar-info (registrar-address principal))
  (map-get? registrars registrar-address)
)

;; Get authorization request
(define-read-only (get-authorization-request (registrar-address principal))
  (map-get? authorization-requests registrar-address)
)

;; Check if address is authorized registrar
(define-read-only (is-authorized-registrar (address principal) (required-level uint))
  (match (map-get? registrars address)
    registrar-info 
      (and 
        (is-eq (get status registrar-info) STATUS_ACTIVE)
        (>= (get authorization-level registrar-info) required-level)
      )
    false
  )
)

;; Get system statistics
(define-read-only (get-system-stats)
  {
    total-registrars: (var-get total-registrars),
    total-active-registrars: (var-get total-active-registrars),
    total-authorization-requests: (var-get total-authorization-requests),
    system-admin: (var-get system-admin),
    maintenance-mode: (var-get system-maintenance-mode)
  }
)

;; Get jurisdiction information
(define-read-only (get-jurisdiction-info (jurisdiction-name (string-ascii 100)))
  (map-get? jurisdictions jurisdiction-name)
)

;; Get system configuration
(define-read-only (get-system-config (config-key (string-ascii 50)))
  (map-get? system-config config-key)
)

;; Get registrar activity for a specific month
(define-read-only (get-registrar-activity (registrar-address principal) (month uint))
  (map-get? registrar-activity { registrar: registrar-address, month: month })
)

;; Get admin action log
(define-read-only (get-admin-action (action-id uint) (admin principal))
  (map-get? admin-actions { action-id: action-id, admin: admin })
)

;; Check admin status
(define-read-only (is-admin (address principal))
  (is-eq address (var-get system-admin))
)

;; Private Functions

;; Update jurisdiction statistics
(define-private (update-jurisdiction-stats (jurisdiction-name (string-ascii 100)) (registrar principal))
  (let 
    (
      (existing-jurisdiction (default-to 
        {
          lead-registrar: none,
          total-registrars: u0,
          total-records: u0,
          established-date: stacks-block-height,
          contact-info: ""
        }
        (map-get? jurisdictions jurisdiction-name)
      ))
    )
    (map-set jurisdictions jurisdiction-name (merge existing-jurisdiction {
      total-registrars: (+ (get total-registrars existing-jurisdiction) u1),
      lead-registrar: (if (is-none (get lead-registrar existing-jurisdiction)) 
                       (some registrar) 
                       (get lead-registrar existing-jurisdiction)
                     )
    }))
  )
)

;; Log administrative actions
(define-private (log-admin-action 
  (action-id uint)
  (action-type (string-ascii 50))
  (target principal)
  (details (string-ascii 500))
  (previous-values (string-ascii 500)))
  (begin
    (map-set admin-actions 
      { action-id: action-id, admin: tx-sender }
      {
        action-type: action-type,
        target-registrar: target,
        timestamp: stacks-block-height,
        details: details,
        previous-values: previous-values
      }
    )
    (var-set next-action-id (+ action-id u1))
  )
)

;; Calculate activity score based on registrar activity
(define-private (calculate-activity-score (activity {
  records-created: uint,
  records-verified: uint,
  last-login: uint,
  activity-score: uint
}))
  (+ 
    (* (get records-created activity) u5)
    (* (get records-verified activity) u3)
    u10 ;; base score
  )
)

;; Get current month as YYYYMM format (simplified)
(define-private (get-current-month)
  ;; Simplified month calculation - in production would use proper date functions
  (/ stacks-block-height u4320) ;; Approximate blocks per month
)

;; Concatenate strings (helper function)
(define-private (concat-strings (str1 (string-ascii 64)) (str2 (string-ascii 64)))
  ;; Simple concatenation simulation - in production would use proper string functions
  str1 ;; Returning first string for now
)
