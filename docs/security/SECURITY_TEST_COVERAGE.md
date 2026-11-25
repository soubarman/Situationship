# Situationship — Security Test Coverage & Rules Verification

**Last Updated:** November 24, 2026 (Phase 5.5 Completion)  
**Total Automated Tests:** **186 tests** across 3 test suites  
**Success Rate:** **100% (186 passing, 0 failing, 0 skipped)**  
**Test Harness Environments:**
1. **Firebase Local Emulator Suite** (Firestore port 8080, Storage port 9199)
2. **Mocha JS Rules Test Suite** (`@firebase/rules-unit-testing`)
3. **Python Pytest Integration Test Suite** (connected directly to Firestore Emulator via gRPC)
4. **Python Pytest Unit Test Suite** (in-memory mocks with Flask application contexts)

---

## 1. Test Suite Architecture & Environment Separation

To ensure absolute transparency and prevent confusion between mock unit tests and live emulator verification, tests are partitioned into three dedicated test suites:

| Suite Name | Target System | Execution Engine | Test File | Test Count | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Suite 1: Security Rules Emulator Tests** | Firestore & Storage Rules | Mocha + `@firebase/rules-unit-testing` | `test/security/security_rules.test.js` | 120 | **120 Passing** |
| **Suite 2: Cloud Functions Emulator Integration** | Real Firestore Transactions & HTTP Routing | Pytest + `google-cloud-firestore` (`127.0.0.1:8080`) | `functions/tests/test_emulator_backend.py` | 15 | **15 Passing** |
| **Suite 3: Backend Security Unit Tests** | Authorization, Parsing, Logic & Contention | Pytest + In-Memory Mocks | `functions/tests/test_backend_security.py` | 51 | **51 Passing** |

---

## 2. Suite 1: Security Rules Emulator Tests (120 Tests)

Located in [test/security/security_rules.test.js](file:///c:/Users/DELL/Downloads/Situationship/test/security/security_rules.test.js). Executed with:
```powershell
$env:PATH = "C:\Program Files\Microsoft\jdk-21.0.13.102-hotspot\bin;" + $env:PATH
firebase emulators:exec --only firestore,storage "npm test"
```

### Domain 1: User Document Security & Profile Privacy (26 Tests)
- **TEST 1:** User A cannot modify User B coins balance (DENIED)
- **TEST 2:** Owner User B cannot self-grant coins via owner allowlist (DENIED)
- **TEST 3:** Owner User B cannot self-grant verification status (DENIED)
- **TEST 4:** Owner User B cannot self-grant subscription (DENIED)
- **TEST 5:** User A cannot read User B private settings subcollection (DENIED)
- **TEST 1.1:** User cannot self-grant coins or role during user creation (DENIED)
- **TEST 1.2:** User cannot self-grant isVerified: true during user creation (DENIED)
- **TEST 1.3:** User cannot inject unlockedUserPhones during user creation (DENIED)
- **TEST 1.4:** Owner User B cannot modify unlockedUserPhones or unlockedVisitors on update (DENIED)
- **TEST 1.5:** Owner User B cannot modify dailyLoginStreak or conversationRewardsToday on update (DENIED)
- **TEST 1.6:** Non-owner User C cannot remove existing users from Bob likedBy array (DENIED)
- **TEST 1.7:** Non-owner User C cannot replace likedBy array elements with different UIDs (DENIED)
- **TEST 1.8:** Non-owner User C can append ONLY their own UID to Bob likedBy array (PERMITTED)
- **TEST 1.9:** Non-owner User C cannot inject another user UID into Bob followers array (DENIED)
- **TEST 1.10:** Non-owner User C can append ONLY their own UID to Bob followers array (PERMITTED)
- **TEST 1.11:** Non-owner User C cannot tamper with superLikeNotes for another user (DENIED)
- **TEST 1.12:** Non-owner User C can submit superLikeNotes under their own UID key (PERMITTED)
- **TEST 1.13:** Suspended user cannot update their own profile (DENIED)
- **TEST 1.14:** Suspended user cannot read other user profiles (DENIED)
- **TEST 1.15:** User A cannot read User B profile if User B has blocked User A (DENIED)
- **TEST 4B.11:** Blocked user cannot read target user profile document (DENIED)
- **TEST 4B.12:** Non-owner cannot read private settings/documents in users/{userId}/private/{doc} (DENIED)
- **TEST 4B.13:** Owner can read own private document in users/{userId}/private/{doc} (PERMITTED)
- **TEST 4B.18:** Client cannot grant itself purchased coins or alter coin balances (DENIED)
- **TEST 4B.19:** Client cannot self-activate subscription or alter subscriptionExpiry (DENIED)
- **LEGITIMATE 1:** Alice can update her own bio and interests (PERMITTED)
- **LEGITIMATE 2:** Alice can swipe right and like Bob (append self to likedBy) (PERMITTED)

### Domain 2: Chat & Direct Message Security (15 Tests)
- **TEST 6:** User A cannot initiate chat without mutual like / match (DENIED)
- **TEST 7:** Unauthorized user cannot alter chat participants (DENIED)
- **TEST 8:** Chat participants cannot tamper with unread count arbitrarily (DENIED)
- **TEST 2.1:** Sender User A cannot mark message as read (DENIED)
- **TEST 2.2:** Recipient User B cannot alter text of User A message (DENIED)
- **TEST 2.3:** Recipient Bob can mark Alice message as read (PERMITTED)
- **TEST 2.4:** Sender Alice can edit text of her own message (PERMITTED)
- **TEST 2.5:** Sender Alice can delete her own message (PERMITTED)
- **TEST 2.6:** Blocked user cannot read existing chat (DENIED)
- **TEST 2.7:** User A cannot forge senderId when sending a message (DENIED)
- **TEST 2.8:** User A cannot forge invalid message type (DENIED)
- **TEST 4B.16:** Message reaction update spoofing another user identity is rejected (DENIED)
- **TEST 4B.17:** Message reaction update with caller own UID is permitted (PERMITTED)
- **LEGITIMATE 3:** Alice and Bob can chat in their mutual chat (PERMITTED)
- **LEGITIMATE 4:** Alice can create chat with Bob because Bob already liked Alice (PERMITTED)

### Domain 3: Communities & Community Rooms (12 Tests)
- **TEST 9:** Non-member User C cannot read community rooms (DENIED)
- **TEST 10:** Non-member User C cannot post messages in community (DENIED)
- **TEST 3.1:** Non-member User C cannot read community rooms (DENIED)
- **TEST 3.2:** Non-admin Member Bob cannot update community configuration (DENIED)
- **TEST 3.3:** Non-member User C cannot join by arbitrarily setting memberCount to 1000 (DENIED)
- **TEST 3.4:** Non-member User C cannot tamper with memberCount during join (DENIED)
- **TEST 3.5:** Member Bob can post a message in comm1 (PERMITTED)
- **TEST 3.6:** Member Bob can edit text of his own community message (PERMITTED)
- **TEST 3.7:** Member Bob cannot edit Alice community message (DENIED)
- **TEST 3.8:** Community admin Alice can delete community messages (PERMITTED)
- **TEST 4B.9:** User cannot self-grant community membership by editing memberAvatars without count or rules (DENIED)
- **TEST 4B.10:** User cannot self-grant community admin rights or alter adminId (DENIED)

### Domain 4: Posts, Stories & Notifications (14 Tests)
- **TEST 11:** User A cannot modify caption of User B post (DENIED)
- **TEST 12:** User A cannot forge system notification for User B (DENIED)
- **TEST 14:** User A cannot delete User B posts (DENIED)
- **TEST 19:** Suspended user cannot create posts (DENIED)
- **TEST 4.1:** User A cannot arbitrarily jump commentCount by 50 on Bob post (DENIED)
- **TEST 4.2:** User A can increment commentCount by 1 when commenting (PERMITTED)
- **TEST 4.3:** User A can like Bob post (append own UID to likes) (PERMITTED)
- **TEST 4.4:** User A cannot edit Bob comment text (DENIED)
- **TEST 4.5:** Bob can edit text of his own comment (PERMITTED)
- **TEST 4.6:** Viewer User C cannot inject third-party User A into story viewers (DENIED)
- **TEST 4.7:** Viewer Charlie can append self to story viewers (PERMITTED)
- **TEST 4.8:** User A cannot forge type: system notification for User B (DENIED)
- **TEST 4B.14:** Arbitrary commentCount increment (e.g. +5) on post is rejected (DENIED)
- **TEST 4B.15:** Legitimate commentCount increment (+1) on post is permitted (PERMITTED)

### Domain 5: Boosts, Milestones, Analytics & Views (11 Tests)
- **TEST 13:** Client User A cannot create paid boost directly (DENIED)
- **TEST 5.1:** User A cannot inject fake analytics event with mismatched userId (DENIED)
- **TEST 5.2:** User A can log analytics event for their own interaction (PERMITTED)
- **TEST 5.3:** User A cannot create paid boost (DENIED)
- **TEST 5.4:** User A cannot claim coin reward directly (DENIED)
- **TEST 5.5:** User A cannot claim coin milestone with approved status and fake giftCode (DENIED)
- **TEST 5.6:** User A can submit pending milestone claim if eligible (PERMITTED)
- **TEST 5.7:** User A cannot create profile view with mismatched viewerId (DENIED)
- **TEST 5.8:** User A cannot create profile view for non-existent target (DENIED)
- **TEST 5.9:** User A can record valid profile view of Bob (PERMITTED)
- **TEST 4B.20:** Ineligible user claiming milestone reward without required totalEarnedCoins is rejected (DENIED)
- **TEST 4B.21:** Eligible user claiming milestone with sufficient totalEarnedCoins succeeds (PERMITTED)

### Domain 6: Storage Paths, Media & File Integrity (20 Tests)
- **TEST 15:** User A cannot overwrite User B avatar (DENIED)
- **TEST 16:** Non-participant User C cannot read chat attachment in Storage (DENIED)
- **TEST 6.1:** User A cannot upload oversized avatar (>10MB) (DENIED)
- **TEST 6.2:** User A cannot upload non-image content type as avatar (DENIED)
- **TEST 6.3:** User A cannot upload avatar with mismatched filename prefix (DENIED)
- **TEST 6.4:** User A can upload valid avatar under own UID prefix (PERMITTED)
- **TEST 6.5:** Blocked user User A cannot read chat attachment in Storage (DENIED)
- **TEST 6.6:** User A can upload and delete own media in UID-based posts path (PERMITTED)
- **TEST 6.7:** User A cannot delete User B media in UID-based posts path (DENIED)
- **TEST 6.8:** Non-member User C cannot upload media to comm1 in Storage (DENIED)
- **TEST 6.9:** Non-owner User A cannot read User B private verification video (DENIED)
- **TEST 6.10:** User B can upload and read own private verification video (PERMITTED)
- **TEST 4B.1:** Storage upload via old flat /posts/{fileName} is denied (DENIED)
- **TEST 4B.2:** Storage upload via old flat /stories/{fileName} is denied (DENIED)
- **TEST 4B.3:** Storage upload via old flat /voice_notes/{fileName} is denied (DENIED)
- **TEST 4B.4:** Storage upload via old flat /communities/{fileName} is denied (DENIED)
- **TEST 4B.5:** User cannot upload to another user UID-based posts path (DENIED)
- **TEST 4B.6:** User cannot upload to another user UID-based stories path (DENIED)
- **TEST 4B.7:** User cannot upload to another user UID-based voice_notes path (DENIED)
- **TEST 4B.8:** Non-member cannot upload cover or media to community (DENIED)
- **TEST 4B.22:** Blocked user cannot access chat attachments in Storage (DENIED)

### Domain 7: User Privacy & PII Access Rules (22 Tests)
- **TEST 5.P1:** User A cannot read User B private/profile (DENIED)
- **TEST 5.P2:** Another user cannot write to Bob private profile document (DENIED)
- **TEST 5.P3:** Account owner can read and write own private profile document (PERMITTED)
- **TEST 5.P4:** User cannot create public profile containing email (DENIED)
- **TEST 5.P5:** User cannot create public profile containing phoneNumber (DENIED)
- **TEST 5.P6:** User cannot update public profile with phoneNumber (DENIED)
- **TEST 5.P7:** User cannot modify their own unlockedUserPhones array directly (DENIED)
- **TEST 5.P8:** User cannot modify their own phoneUnlocksUsed directly (DENIED)
- **TEST 5.P9:** User cannot modify their own coin balance directly (DENIED)
- **TEST 5.P10:** Authorized viewer can read unlocked contact document in unlocked_contacts (PERMITTED)
- **TEST 5.P11:** Unauthorized viewer cannot read another user's unlocked contact document (DENIED)
- **TEST 5.P12:** Client cannot write or forge own unlocked contact document directly (DENIED)
- **TEST 5.P13:** Blocked user cannot read target user profile document (DENIED)
- **TEST 5.P14:** Blocked viewer cannot read unlocked contact (viewer blocked target) (DENIED)
- **TEST 5.P15:** Blocked viewer cannot read unlocked contact (target blocked viewer) (DENIED)
- **TEST 5.P16:** Viewer cannot read contact after target disables phone visibility (isPhonePublic = false) (DENIED)
- **TEST 5.P17:** Stale phoneVisibilityVersion cannot authorize contact read (DENIED)
- **TEST 5.P18:** Unauthorized user cannot create an unlocked contact record (DENIED)
- **TEST 5.P19:** Unauthorized user cannot update an unlocked contact record (DENIED)
- **TEST 5.P20:** Target owner can read their own unlocked contacts list (PERMITTED)
- **TEST 5.P21:** Account owner can read and update their own private/profile (PERMITTED)

---

## 3. Suite 2: Cloud Functions Emulator Integration Tests (15 Tests)

Located in [functions/tests/test_emulator_backend.py](file:///c:/Users/DELL/Downloads/Situationship/functions/tests/test_emulator_backend.py). Executed against the live Firebase Firestore Emulator (`127.0.0.1:8080`) with:
```powershell
$env:PATH = "C:\Program Files\Microsoft\jdk-21.0.13.102-hotspot\bin;" + $env:PATH
firebase emulators:exec --only firestore 'functions\venv\Scripts\python.exe -m pytest functions/tests/test_emulator_backend.py -v'
```

### Part A: Service-Layer Transactions & Batch Operations (6 Tests)
- **TEST 1:** Real Firestore Transaction Phone Unlock (Coins deducted, contact created, idempotency recorded) — **PASSED**
- **TEST 2:** Real Firestore Cross-Target Idempotency Rejection (HTTP 409 Conflict, Charlie's phone never revealed, 0 coins deducted) — **PASSED**
- **TEST 3:** Concurrent Duplicate Unlock Requests (3 simultaneous worker threads with same key serialize cleanly; coins deducted exactly once) — **PASSED**
- **TEST 4:** Concurrent Insufficient Balance Protection (Caller with 50 coins fires 2 concurrent unlocks; exactly 1 succeeds, 1 fails with HTTP 402, balance ends at 0) — **PASSED**
- **TEST 5:** Real Firestore Migration Batch Boundary (250 legacy users seeded; batch migrated atomically with 500 write operations at exact Firestore ceiling) — **PASSED**
- **TEST 6:** Real Firestore Checkpoint Recovery Across Multiple Pages (30 users migrated across multiple pages with cursor resumption; checkpoint accurately tracks progress to completion) — **PASSED**

### Part B: HTTP & Authentication Layer Integration (9 Tests)
- **TEST 7.1:** Missing Authorization header returns HTTP 401 — **PASSED**
- **TEST 7.2:** Malformed Bearer header returns HTTP 401 — **PASSED**
- **TEST 7.3:** Ordinary user calling admin endpoint receives HTTP 403 — **PASSED**
- **TEST 7.4:** Unverified situationship@gmail.com account is rejected with HTTP 403 — **PASSED**
- **TEST 7.5:** Genuine admin claim returns HTTP 200 on live emulator data — **PASSED**
- **TEST 7.6:** Suspended admin is rejected by authoritative emulator Firestore check with HTTP 403 — **PASSED**
- **TEST 7.7:** Revoked admin token returns HTTP 401 — **PASSED**
- **TEST 7.8:** End-to-end HTTP `/user/unlock-phone` flow (auth, transaction, contact created, coins deducted) — **PASSED**
- **TEST 7.9:** End-to-end HTTP `/admin/migrate-pii` flow (admin check, batch migration committed) — **PASSED**

---

## 4. Suite 3: Backend Security Unit Tests (51 Tests)

Located in [functions/tests/test_backend_security.py](file:///c:/Users/DELL/Downloads/Situationship/functions/tests/test_backend_security.py). Executed with:
```powershell
& functions\venv\Scripts\python.exe -m pytest functions/tests/test_backend_security.py -v
```

### SEC-5.2-05 Regression: Identity Binding (3 Tests)
- `test_idempotency_cross_target_reuse_rejected_with_409`: Reusing idempotency key for different target fails with HTTP 409
- `test_idempotent_replay_legitimate_same_target`: Legitimate re-request returns phone without re-charging coins
- `test_idempotency_key_reused_for_obsolete_version_rejected_with_409`: Reusing key after version increment fails with HTTP 409

### SEC-5.2-06: Idempotency Key Validation (7 Tests)
- `test_idempotency_key_validation_missing_key`: Missing key accepted (optional parameter)
- `test_idempotency_key_validation_empty_key`: Empty string rejected with HTTP 400
- `test_idempotency_key_validation_non_string`: Non-string (e.g. integer) rejected with HTTP 400
- `test_idempotency_key_validation_path_traversal`: Path traversal syntax rejected with HTTP 400
- `test_idempotency_key_validation_whitespace`: Key containing whitespace rejected with HTTP 400
- `test_idempotency_key_validation_length_bounds`: Keys < 8 or > 128 characters rejected with HTTP 400
- `test_idempotency_key_validation_valid`: Well-formed alphanumeric key accepted

### SEC-5.2-01: Admin Authorization & Suspension Check (5 Tests)
- `test_valid_active_administrator_accepted`: Active admin successfully authenticated
- `test_suspended_administrator_rejected`: Suspended admin rejected with HTTP 403
- `test_missing_admin_user_document_fails_closed`: Missing user doc fails closed with HTTP 403
- `test_ordinary_user_rejected_from_admin`: Standard user rejected with HTTP 403
- `test_admin_firestore_lookup_error_fails_closed`: Firestore query failure fails closed with HTTP 403

### SEC-5.2-03: PII Migration Batch Size Bounds (5 Tests)
- `test_migration_batch_boundary_250_accepted`: Batch size 250 accepted
- `test_migration_batch_boundary_251_rejected`: Batch size > 250 rejected with HTTP 400
- `test_migration_batch_size_zero_and_negative_rejected`: Batch size <= 0 rejected with HTTP 400
- `test_migration_batch_size_boolean_and_non_numeric_rejected`: Boolean batch size rejected with HTTP 400
- `test_migration_batch_operations_never_exceed_500`: Batch operations strictly limited to 500 writes

### Core Domain Security Handlers (7 Tests)
- `test_unauthenticated_unlock_request`: Missing auth header rejected with HTTP 401
- `test_invalid_firebase_token`: Malformed token rejected with HTTP 401
- `test_valid_administrator_migration`: Valid admin triggers migration successfully
- `test_insufficient_coin_balance`: Caller with < 50 coins rejected with HTTP 402
- `test_blocked_user_unlock_attempts`: Blocked user unlock attempt rejected with HTTP 403
- `test_self_unlocking_rejected`: Caller unlocking own phone rejected with HTTP 400
- `test_transaction_failure_without_partial_coin_deduction`: Aborted transaction rolls back atomic updates

### Phase 5.5 Adversarial Admin Authorization (8 Tests)
- `test_admin_auth_missing_admin_claim_denied`: Missing admin claim rejected
- `test_admin_auth_admin_claim_false_denied`: Admin claim set to False rejected
- `test_admin_auth_unverified_situationship_email_denied`: Unverified situationship email rejected
- `test_admin_auth_verified_situationship_email_without_admin_claim_denied`: Verified email without custom claim rejected
- `test_admin_auth_ordinary_verified_user_denied`: Ordinary verified user rejected
- `test_admin_auth_invalid_token_denied`: Malformed token rejected
- `test_admin_auth_revoked_token_denied`: Revoked token rejected
- `test_admin_auth_client_supplied_admin_in_body_denied`: Body injection cannot bypass auth

### Phase 5.5 All Admin Endpoints Audit (5 Tests)
- `test_admin_endpoints_migrate_pii_rejects_non_admin`: Non-admin rejected from /admin/migrate-pii
- `test_admin_endpoints_stats_rejects_non_admin`: Non-admin rejected from /admin/stats
- `test_admin_endpoints_verifications_rejects_non_admin`: Non-admin rejected from /admin/verifications/*
- `test_admin_endpoints_reset_attempts_rejects_non_admin`: Non-admin rejected from /reset-attempts
- `test_admin_endpoints_create_admin_disabled`: /create-admin is disabled in production

### Phase 5.5 Structured Contention Retries (2 Tests)
- `test_transaction_retry_on_gcp_aborted_exception`: gcp_exceptions.Aborted triggers retries with fresh transactions
- `test_transaction_no_retry_on_permanent_api_error`: ApiError permanent errors fail fast without retrying

### Phase 5.5 HTTP & Authentication Layer Tests (9 Tests)
- `test_http_missing_auth_header_returns_401`: Missing header returns 401
- `test_http_malformed_bearer_token_returns_401`: Malformed bearer returns 401
- `test_http_ordinary_user_calling_admin_endpoint_returns_403`: Ordinary user calling admin returns 403
- `test_http_unverified_allowlisted_email_without_admin_claim_returns_403`: Unverified email without claim returns 403
- `test_http_genuine_admin_claim_accepted_returns_200`: Genuine claim returns 200
- `test_http_suspended_admin_returns_403`: Suspended admin returns 403
- `test_http_revoked_token_returns_401`: Revoked token returns 401
- `test_http_client_supplied_uid_cannot_impersonate_admin`: Client-supplied UID rejected with 403
- `test_http_admin_endpoint_does_not_execute_logic_on_failed_auth`: Business logic never runs on failed auth
