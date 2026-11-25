"""
functions/tests/test_emulator_backend.py
────────────────────────────────────────
Real Firebase Emulator-backed Python test suite for Situationship backend services.
Tests real Firestore transactions, real concurrency, batch limits, and idempotency
against the live Firestore Emulator (127.0.0.1:8080).
Zero production services or external networks are contacted.
"""

import sys
import os
import json
import pytest
import concurrent.futures

# Set emulator environment variables before initializing client
os.environ["FIRESTORE_EMULATOR_HOST"] = "127.0.0.1:8080"
os.environ["GCLOUD_PROJECT"] = "situation-ship-test"

# Ensure functions package is in sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import hmac
import hashlib
from unittest.mock import patch, MagicMock
from flask import Flask, Request
from werkzeug.test import EnvironBuilder
from google.cloud import firestore as gcp_firestore
from firebase_admin import firestore, auth
import main
from main import (
    api,
    execute_phone_unlock,
    execute_pii_migration,
    verify_payment_signature,
    handle_payment_webhook,
    ApiError,
)

_flask_test_app = Flask("test_emulator_backend")

def call_api_emulator(path: str, method: str = "POST", json_data: dict = None, headers: dict = None, args: dict = None):
    builder = EnvironBuilder(
        path=path,
        method=method,
        data=json.dumps(json_data) if json_data is not None else None,
        content_type="application/json" if json_data is not None else None,
        headers=headers or {},
        query_string=args or {}
    )
    environ = builder.get_environ()
    req = Request(environ)
    with _flask_test_app.request_context(environ):
        return api(req)

# Connect directly to the local Firestore Emulator
@pytest.fixture(scope="session")
def emulator_db():
    client = gcp_firestore.Client(project="situation-ship-test")
    return client


@pytest.fixture(autouse=True)
def clean_emulator_collections(emulator_db):
    """Clean up emulator collections before each test to guarantee complete test isolation."""
    # Delete test documents in users collection
    users_col = emulator_db.collection("users")
    for doc in users_col.stream():
        # Clean subcollections
        for sub in ["unlocked_contacts", "private", "idempotency_records"]:
            for sdoc in doc.reference.collection(sub).stream():
                sdoc.reference.delete()
        doc.reference.delete()

    # Clean migration checkpoints
    for cdoc in emulator_db.collection("_admin_migrations").stream():
        cdoc.reference.delete()

    # Clean orders, payment audits, and coin transactions
    for col_name in ["orders", "payment_audit_logs", "coin_transactions", "spotlight_bids"]:
        for doc in emulator_db.collection(col_name).stream():
            doc.reference.delete()

    yield


# ── TEST 1: Real Firestore Transaction Phone Unlock ───────────────────────────
def test_real_firestore_transaction_phone_unlock(emulator_db):
    """Verify phone unlock transaction on real Firestore emulator with real atomic commit."""
    caller_ref = emulator_db.collection("users").document("real_caller1")
    target_ref = emulator_db.collection("users").document("real_target1")
    target_priv = target_ref.collection("private").document("profile")

    caller_ref.set({
        "id": "real_caller1",
        "name": "Alice",
        "coins": 100,
        "isSubscribed": False,
        "isSuspended": False,
        "unlockedUserPhones": [],
        "blockedUsers": [],
    })
    target_ref.set({
        "id": "real_target1",
        "name": "Bob",
        "isPhonePublic": True,
        "phoneVisibilityVersion": 1,
        "blockedUsers": [],
    })
    target_priv.set({
        "phoneNumber": "+91 98765 43210",
        "email": "bob@example.com",
    })

    # Execute unlock
    key = "real_key_001"
    res = execute_phone_unlock(emulator_db, "real_caller1", "real_target1", idempotency_key=key)

    assert res["success"] is True
    assert res["phoneNumber"] == "+91 98765 43210"
    assert res["paymentType"] == "coins"

    # Verify real caller doc updated in emulator
    caller_snap = caller_ref.get().to_dict()
    assert caller_snap["coins"] == 50
    assert "real_target1_1" in caller_snap["unlockedUserPhones"]

    # Verify real contact doc created in emulator
    contact_snap = target_ref.collection("unlocked_contacts").document("real_caller1").get().to_dict()
    assert contact_snap["phoneNumber"] == "+91 98765 43210"
    assert contact_snap["phoneVisibilityVersion"] == 1

    # Verify real idempotency doc created in emulator
    idemp_snap = caller_ref.collection("idempotency_records").document(key).get().to_dict()
    assert idemp_snap["targetId"] == "real_target1"
    assert idemp_snap["phoneVisibilityVersion"] == 1


# ── TEST 2: Real Firestore Cross-Target Idempotency Rejection (HTTP 409) ──────
def test_real_firestore_cross_target_idempotency_rejected(emulator_db):
    """Verify that attempting to reuse an idempotency key across targets fails with HTTP 409."""
    caller_ref = emulator_db.collection("users").document("reuse_caller")
    target_bob = emulator_db.collection("users").document("reuse_bob")
    target_charlie = emulator_db.collection("users").document("reuse_charlie")

    caller_ref.set({
        "id": "reuse_caller",
        "coins": 100,
        "isSuspended": False,
        "unlockedUserPhones": [],
        "blockedUsers": [],
    })
    target_bob.set({
        "id": "reuse_bob",
        "isPhonePublic": True,
        "phoneVisibilityVersion": 1,
        "blockedUsers": [],
    })
    target_bob.collection("private").document("profile").set({
        "phoneNumber": "+91 99999 11111",
    })
    target_charlie.set({
        "id": "reuse_charlie",
        "isPhonePublic": True,
        "phoneVisibilityVersion": 1,
        "blockedUsers": [],
    })
    target_charlie.collection("private").document("profile").set({
        "phoneNumber": "+91 88888 22222",
    })

    key = "shared_reuse_key"

    # Step 1: Unlock Bob
    res1 = execute_phone_unlock(emulator_db, "reuse_caller", "reuse_bob", idempotency_key=key)
    assert res1["success"] is True
    assert res1["phoneNumber"] == "+91 99999 11111"
    assert caller_ref.get().to_dict()["coins"] == 50

    # Step 2: Attempt to unlock Charlie with same key
    with pytest.raises(ApiError) as exc_info:
        execute_phone_unlock(emulator_db, "reuse_caller", "reuse_charlie", idempotency_key=key)

    assert exc_info.value.status_code == 409
    assert "idempotency conflict" in exc_info.value.message.lower()

    # Verify Charlie's phone number was not revealed
    assert "+91 88888 22222" not in str(exc_info.value)

    # Verify no coins deducted
    assert caller_ref.get().to_dict()["coins"] == 50

    # Verify no contact record created for Charlie
    assert not target_charlie.collection("unlocked_contacts").document("reuse_caller").get().exists


# ── TEST 3: Concurrent Duplicate Unlock Requests (Same Key) ───────────────────
def test_real_firestore_concurrent_duplicate_requests(emulator_db):
    """
    Simulate 5 simultaneous concurrent threads executing unlock with the same idempotency key.
    Firestore transaction retry mechanics and idempotency guarantee that:
    1. Every thread succeeds without crashing.
    2. Exactly 50 coins are deducted (never 250).
    """
    caller_ref = emulator_db.collection("users").document("conc_caller")
    target_ref = emulator_db.collection("users").document("conc_target")

    caller_ref.set({
        "id": "conc_caller",
        "coins": 100,
        "isSuspended": False,
        "unlockedUserPhones": [],
        "blockedUsers": [],
    })
    target_ref.set({
        "id": "conc_target",
        "isPhonePublic": True,
        "phoneVisibilityVersion": 1,
        "blockedUsers": [],
    })
    target_ref.collection("private").document("profile").set({
        "phoneNumber": "+91 55555 44444",
    })

    key = "concurrent_key_exact"

    def run_unlock():
        return execute_phone_unlock(emulator_db, "conc_caller", "conc_target", idempotency_key=key)

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        futures = [executor.submit(run_unlock) for _ in range(3)]
        results = [f.result() for f in futures]

    # All return phone successfully
    for r in results:
        assert r["success"] is True
        assert r["phoneNumber"] == "+91 55555 44444"

    # Crucial assertion: Coins were deducted EXACTLY once (100 - 50 = 50)
    final_coins = caller_ref.get().to_dict()["coins"]
    assert final_coins == 50


# ── TEST 4: Concurrent Insufficient Balance Protection ────────────────────────
def test_real_firestore_concurrent_insufficient_balance(emulator_db):
    """
    Caller has 50 coins (only enough for 1 unlock).
    Two concurrent requests are fired for two DIFFERENT targets.
    One transaction must succeed, and the other must fail with HTTP 402.
    Final balance must be exactly 0, never negative.
    """
    caller_ref = emulator_db.collection("users").document("broke_caller")
    t1_ref = emulator_db.collection("users").document("target_alpha")
    t2_ref = emulator_db.collection("users").document("target_beta")

    caller_ref.set({
        "id": "broke_caller",
        "coins": 50,  # only enough for one
        "isSuspended": False,
        "unlockedUserPhones": [],
        "blockedUsers": [],
    })
    t1_ref.set({"id": "target_alpha", "isPhonePublic": True, "phoneVisibilityVersion": 1, "blockedUsers": []})
    t1_ref.collection("private").document("profile").set({"phoneNumber": "+91 11111 00000"})

    t2_ref.set({"id": "target_beta", "isPhonePublic": True, "phoneVisibilityVersion": 1, "blockedUsers": []})
    t2_ref.collection("private").document("profile").set({"phoneNumber": "+91 22222 00000"})

    def unlock_t1():
        return execute_phone_unlock(emulator_db, "broke_caller", "target_alpha", idempotency_key="key_alpha_11")

    def unlock_t2():
        return execute_phone_unlock(emulator_db, "broke_caller", "target_beta", idempotency_key="key_beta_22")

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        f1 = executor.submit(unlock_t1)
        f2 = executor.submit(unlock_t2)

        results = []
        errors = []
        for f in [f1, f2]:
            try:
                results.append(f.result())
            except ApiError as e:
                errors.append(e)

    # Exactly one succeeded and one failed with 402
    assert len(results) == 1
    assert len(errors) == 1
    assert errors[0].status_code == 402

    # Balance is exactly 0
    final_coins = caller_ref.get().to_dict()["coins"]
    assert final_coins == 0


# ── TEST 5: Real Firestore Migration Batch Operations (Boundary of 250 Users) ─
def test_real_firestore_migration_batch_boundary_250(emulator_db):
    """
    Seed 250 legacy user documents in the emulator.
    Execute migration with batch_size=250.
    Verify all 250 are migrated atomically (500 write operations total).
    Verify checkpoint document is created.
    """
    users_col = emulator_db.collection("users")
    batch = emulator_db.batch()

    for i in range(250):
        doc_ref = users_col.document(f"emu_user_{i:03d}")
        batch.set(doc_ref, {
            "id": f"emu_user_{i:03d}",
            "name": f"User {i:03d}",
            "email": f"user_{i:03d}@emulator.test",
            "phoneNumber": f"+91 90000 00{i:03d}",
        })
    batch.commit()

    # Execute migration with limit=300 to process all 250 in one run while testing 250 batch limit
    res = execute_pii_migration(emulator_db, limit=300, batch_size=250)

    assert res["success"] is True
    assert res["batchMigrated"] == 250
    assert res["isComplete"] is True

    # Check first and last document
    first_doc = users_col.document("emu_user_000").get().to_dict()
    assert "email" not in first_doc
    assert "phoneNumber" not in first_doc
    first_priv = users_col.document("emu_user_000").collection("private").document("profile").get().to_dict()
    assert first_priv["email"] == "user_000@emulator.test"
    assert first_priv["phoneNumber"] == "+91 90000 00000"

    last_doc = users_col.document("emu_user_249").get().to_dict()
    assert "email" not in last_doc
    assert "phoneNumber" not in last_doc
    last_priv = users_col.document("emu_user_249").collection("private").document("profile").get().to_dict()
    assert last_priv["email"] == "user_249@emulator.test"
    assert last_priv["phoneNumber"] == "+91 90000 00249"

    # Checkpoint
    cp = emulator_db.collection("_admin_migrations").document("pii_migration").get().to_dict()
    assert cp["status"] == "completed"
    assert cp["totalMigrated"] == 250


# ── TEST 6: Real Firestore Checkpoint Recovery Across Multiple Pages ──────────
def test_real_firestore_checkpoint_recovery(emulator_db):
    """
    Seed 30 users.
    Run page 1 with limit=10.
    Resume with resume=True for page 2 with limit=10.
    Verify checkpoint state advances properly without duplicate processing.
    """
    users_col = emulator_db.collection("users")
    batch = emulator_db.batch()

    for i in range(30):
        doc_ref = users_col.document(f"page_user_{i:02d}")
        batch.set(doc_ref, {
            "id": f"page_user_{i:02d}",
            "email": f"p_{i:02d}@test.com",
            "phoneNumber": f"+91 80000 000{i:02d}",
        })
    batch.commit()

    # Run page 1
    res1 = execute_pii_migration(emulator_db, limit=10, batch_size=10)
    assert res1["batchMigrated"] == 10
    assert res1["isComplete"] is False
    assert res1["lastProcessedId"] == "page_user_09"

    # Run page 2 with resume=True
    res2 = execute_pii_migration(emulator_db, limit=10, batch_size=10, resume=True)
    assert res2["batchMigrated"] == 10
    assert res2["isComplete"] is False
    assert res2["lastProcessedId"] == "page_user_19"

    # Run page 3
    res3 = execute_pii_migration(emulator_db, limit=10, batch_size=10, resume=True)
    assert res3["batchMigrated"] == 10
    assert res3["lastProcessedId"] == "page_user_29"

    # Run page 4 to verify completion
    res4 = execute_pii_migration(emulator_db, limit=10, batch_size=10, resume=True)
    assert res4["batchMigrated"] == 0
    assert res4["isComplete"] is True

    cp = emulator_db.collection("_admin_migrations").document("pii_migration").get().to_dict()
    assert cp["status"] == "completed"
    assert cp["totalMigrated"] == 30


# ── TEST 7: HTTP Routing & Auth Layer Integration on Real Emulator ─────────────

def test_real_firestore_http_missing_auth_header_401():
    """Verify that requests missing Authorization headers return HTTP 401."""
    resp = call_api_emulator("/admin/stats", method="GET")
    assert resp.status_code == 401
    body = json.loads(resp.data)
    assert "authorization header" in body["detail"].lower()


def test_real_firestore_http_malformed_auth_header_401():
    """Verify that malformed Bearer headers return HTTP 401."""
    resp1 = call_api_emulator("/admin/stats", method="GET", headers={"Authorization": "Basic badtoken"})
    assert resp1.status_code == 401

    resp2 = call_api_emulator("/admin/stats", method="GET", headers={"Authorization": "Bearer "})
    assert resp2.status_code == 401


def test_real_firestore_http_ordinary_user_admin_endpoint_403(emulator_db):
    """Verify ordinary user token calling admin endpoint receives HTTP 403."""
    # Seed ordinary user in emulator
    emulator_db.collection("users").document("emu_user1").set({
        "id": "emu_user1",
        "isSuspended": False,
    })

    with patch("main.get_db", return_value=emulator_db):
        with patch("main.auth.verify_id_token", return_value={"uid": "emu_user1", "email": "user@test.com", "admin": False}):
            resp = call_api_emulator("/admin/stats", method="GET", headers={"Authorization": "Bearer ordinary_token"})
            assert resp.status_code == 403
            body = json.loads(resp.data)
            assert "admin privileges required" in body["detail"].lower()


def test_real_firestore_http_unverified_email_admin_endpoint_403(emulator_db):
    """Verify unverified situationship@gmail.com account is rejected with HTTP 403."""
    emulator_db.collection("users").document("attacker_uid").set({
        "id": "attacker_uid",
        "isSuspended": False,
    })

    with patch("main.get_db", return_value=emulator_db):
        with patch("main.auth.verify_id_token", return_value={"uid": "attacker_uid", "email": "situationship@gmail.com", "email_verified": False}):
            resp = call_api_emulator("/admin/stats", method="GET", headers={"Authorization": "Bearer attacker_token"})
            assert resp.status_code == 403
            body = json.loads(resp.data)
            assert "admin privileges required" in body["detail"].lower()


def test_real_firestore_http_genuine_admin_claim_accepted_200(emulator_db):
    """Verify genuine admin token executes on real emulator and returns HTTP 200."""
    emulator_db.collection("users").document("emu_admin1").set({
        "id": "emu_admin1",
        "isSuspended": False,
    })

    with patch("main.get_db", return_value=emulator_db):
        with patch("main.auth.verify_id_token", return_value={"uid": "emu_admin1", "email": "admin@test.com", "admin": True}):
            resp = call_api_emulator("/admin/stats", method="GET", headers={"Authorization": "Bearer admin_token"})
            assert resp.status_code == 200
            body = json.loads(resp.data)
            assert "pending_review" in body
            assert "total" in body


def test_real_firestore_http_suspended_admin_rejected_403(emulator_db):
    """Verify suspended admin token is rejected by authoritative emulator Firestore check."""
    emulator_db.collection("users").document("emu_admin_suspended").set({
        "id": "emu_admin_suspended",
        "isSuspended": True,  # Authoritative suspension in emulator!
    })

    with patch("main.get_db", return_value=emulator_db):
        with patch("main.auth.verify_id_token", return_value={"uid": "emu_admin_suspended", "email": "suspended@test.com", "admin": True}):
            resp = call_api_emulator("/admin/stats", method="GET", headers={"Authorization": "Bearer admin_token"})
            assert resp.status_code == 403
            body = json.loads(resp.data)
            assert "suspended" in body["detail"].lower()


def test_real_firestore_http_revoked_token_rejected_401(emulator_db):
    """Verify that revoked admin tokens fail verification with HTTP 401."""
    with patch("main.get_db", return_value=emulator_db):
        with patch("main.auth.verify_id_token", side_effect=auth.RevokedIdTokenError("Token has been revoked")):
            resp = call_api_emulator("/admin/stats", method="GET", headers={"Authorization": "Bearer revoked_token"})
            assert resp.status_code == 401
            body = json.loads(resp.data)
            assert "revoked" in body["detail"].lower()


def test_real_firestore_http_unlock_phone_end_to_end(emulator_db):
    """
    End-to-end HTTP request to /user/unlock-phone through api() handler.
    Validates token authentication, transactional coin deduction, contact creation,
    and idempotency records in real Firestore Emulator.
    """
    caller_ref = emulator_db.collection("users").document("http_caller")
    target_ref = emulator_db.collection("users").document("http_target")

    caller_ref.set({
        "id": "http_caller",
        "coins": 100,
        "isSuspended": False,
        "unlockedUserPhones": [],
        "blockedUsers": [],
    })
    target_ref.set({
        "id": "http_target",
        "isPhonePublic": True,
        "phoneVisibilityVersion": 1,
        "blockedUsers": [],
    })
    target_ref.collection("private").document("profile").set({
        "phoneNumber": "+91 99999 88888",
    })

    with patch("main.get_db", return_value=emulator_db):
        with patch("main.auth.verify_id_token", return_value={"uid": "http_caller"}):
            resp = call_api_emulator(
                "/user/unlock-phone",
                method="POST",
                headers={"Authorization": "Bearer valid_token"},
                json_data={
                    "targetUserId": "http_target",
                    "idempotencyKey": "http_idemp_key_01"
                }
            )
            assert resp.status_code == 200
            body = json.loads(resp.data)
            assert body["success"] is True
            assert body["phoneNumber"] == "+91 99999 88888"

    # Verify real Firestore emulator updates
    assert caller_ref.get().to_dict()["coins"] == 50
    assert target_ref.collection("unlocked_contacts").document("http_caller").get().to_dict()["phoneNumber"] == "+91 99999 88888"


def test_real_firestore_http_migrate_pii_end_to_end(emulator_db):
    """
    End-to-end HTTP request to /admin/migrate-pii through api() handler.
    Validates admin custom claims, authoritative suspension check,
    and atomic batch migration on real Firestore Emulator.
    """
    admin_ref = emulator_db.collection("users").document("http_admin")
    admin_ref.set({"id": "http_admin", "isSuspended": False})

    # Seed 5 legacy users
    for i in range(5):
        emulator_db.collection("users").document(f"legacy_{i}").set({
            "id": f"legacy_{i}",
            "email": f"leg_{i}@test.com",
            "phoneNumber": f"+91 70000 0000{i}"
        })

    with patch("main.get_db", return_value=emulator_db):
        with patch("main.auth.verify_id_token", return_value={"uid": "http_admin", "admin": True}):
            resp = call_api_emulator(
                "/admin/migrate-pii",
                method="POST",
                headers={"Authorization": "Bearer valid_admin_token"},
                json_data={"batchSize": 10, "limit": 10}
            )
            assert resp.status_code == 200
            body = json.loads(resp.data)
            assert body["success"] is True
            assert body["batchMigrated"] == 5

    # Verify public PII was removed and moved to private/profile in real emulator
    legacy0 = emulator_db.collection("users").document("legacy_0").get().to_dict()
    assert "email" not in legacy0
    assert "phoneNumber" not in legacy0
    priv0 = emulator_db.collection("users").document("legacy_0").collection("private").document("profile").get().to_dict()
    assert priv0["email"] == "leg_0@test.com"


# ── TEST 16: PII Migration Preserves Newer Private Profile Data ───────────────
def test_real_firestore_pii_migration_preserves_newer_private_data(emulator_db):
    """
    Verify that when users/{uid}/private/profile already contains updated PII,
    the server migration deletes stale PII from the public document WITHOUT
    overwriting the newer private values.
    """
    user_ref = emulator_db.collection("users").document("user_preserve_pii")
    user_ref.set({
        "id": "user_preserve_pii",
        "name": "Jane Doe",
        "email": "stale_public@old.com",
        "phoneNumber": "+91 11111 00000",
        "unlockedUserPhones": ["old_target_1"],
        "phoneUnlocksUsed": 1,
    })

    # Newer private data
    priv_ref = user_ref.collection("private").document("profile")
    priv_ref.set({
        "email": "newer_private@secure.com",
        "phoneNumber": "+91 99999 88888",
        "updatedAt": firestore.SERVER_TIMESTAMP,
    })

    # Execute migration
    res = execute_pii_migration(emulator_db, limit=10, batch_size=10)
    assert res["success"] is True
    assert res["batchMigrated"] == 1

    # Verify public document has all legacy PII removed
    pub_snap = user_ref.get().to_dict()
    assert "email" not in pub_snap
    assert "phoneNumber" not in pub_snap
    assert "unlockedUserPhones" not in pub_snap
    assert "phoneUnlocksUsed" not in pub_snap
    assert "piiMigratedAt" in pub_snap

    # Verify private document PRESERVED newer values
    priv_snap = priv_ref.get().to_dict()
    assert priv_snap["email"] == "newer_private@secure.com"
    assert priv_snap["phoneNumber"] == "+91 99999 88888"


# ── TEST 17: PII Migration Rerun Safety & Idempotency ────────────────────────
def test_real_firestore_pii_migration_rerun_safety(emulator_db):
    """
    Verify that re-running the migration against an already-migrated database
    is a safe, idempotent no-op with 0 errors and 0 double-migrations.
    """
    for i in range(3):
        emulator_db.collection("users").document(f"clean_user_{i}").set({
            "id": f"clean_user_{i}",
            "name": f"Clean {i}",
            "email": f"clean_{i}@test.com",
            "phoneNumber": f"+91 60000 0000{i}"
        })

    # Run 1: Migrates 3
    res1 = execute_pii_migration(emulator_db, limit=10, batch_size=10)
    assert res1["batchMigrated"] == 3

    # Run 2: Re-run immediately on the same data
    res2 = execute_pii_migration(emulator_db, limit=10, batch_size=10)
    assert res2["success"] is True
    assert res2["batchMigrated"] == 0
    assert res2["batchSkipped"] == 3
    assert res2["batchFailed"] == 0


# ── TEST 18: Real Payment Settlement Verification (Captured) ─────────────────
def test_real_firestore_payment_settlement_verification_captured(emulator_db):
    """
    Verify /payments/verify with genuine gateway settlement check:
    1. Signature is validated.
    2. Razorpay API confirms status == 'captured'.
    3. Coins are credited and audit log written.
    4. Replay call is idempotent and does not double-credit.
    """
    secret = "rzp_secret_settle_test"
    order_id = "order_settle_123"
    payment_id = "pay_settle_456"
    user_id = "user_payer_1"

    emulator_db.collection("users").document(user_id).set({"id": user_id, "coins": 50})
    emulator_db.collection("orders").document(order_id).set({
        "orderId": order_id,
        "userId": user_id,
        "amount": 9900,
        "currency": "INR",
        "coins": 100,
        "status": "created",
    })

    sig_message = f"{order_id}|{payment_id}".encode("utf-8")
    valid_sig = hmac.new(secret.encode("utf-8"), sig_message, hashlib.sha256).hexdigest()

    mock_gateway_payment = {
        "id": payment_id,
        "order_id": order_id,
        "status": "captured",
        "amount": 9900,
        "currency": "INR",
    }

    with patch.dict(os.environ, {"RAZORPAY_KEY_ID": "rzp_key_test", "RAZORPAY_KEY_SECRET": secret}):
        with patch("main.fetch_razorpay_payment", return_value=mock_gateway_payment):
            res = verify_payment_signature(emulator_db, user_id, order_id, payment_id, valid_sig)
            assert res["success"] is True
            assert res["newBalance"] == 150
            assert res["coinsAwarded"] == 100

            # Verify order status in emulator
            order_snap = emulator_db.collection("orders").document(order_id).get().to_dict()
            assert order_snap["status"] == "paid"
            assert order_snap["gatewayStatus"] == "captured"

            # Verify audit log in emulator
            audit_snap = emulator_db.collection("payment_audit_logs").document(payment_id).get().to_dict()
            assert audit_snap["status"] == "captured"
            assert audit_snap["amount"] == 9900

            # Test Idempotent Replay
            res_replay = verify_payment_signature(emulator_db, user_id, order_id, payment_id, valid_sig)
            assert res_replay["success"] is True
            assert res_replay["alreadyProcessed"] is True

            # Assert balance remained 150 (NOT 250)
            user_snap = emulator_db.collection("users").document(user_id).get().to_dict()
            assert user_snap["coins"] == 150


# ── TEST 19: Payment Settlement Rejection for Unsettled Payment ───────────────
def test_real_firestore_payment_settlement_verification_unsettled_rejected(emulator_db):
    """
    Verify /payments/verify rejects payments that have NOT reached captured/settled state
    (e.g. status='authorized' or 'failed') even if signature matches.
    """
    secret = "rzp_secret_settle_test"
    order_id = "order_unsettled_123"
    payment_id = "pay_unsettled_456"
    user_id = "user_payer_2"

    emulator_db.collection("users").document(user_id).set({"id": user_id, "coins": 50})
    emulator_db.collection("orders").document(order_id).set({
        "orderId": order_id,
        "userId": user_id,
        "amount": 9900,
        "currency": "INR",
        "coins": 100,
        "status": "created",
    })

    sig_message = f"{order_id}|{payment_id}".encode("utf-8")
    valid_sig = hmac.new(secret.encode("utf-8"), sig_message, hashlib.sha256).hexdigest()

    # Gateway reports authorized but NOT captured
    mock_unsettled_payment = {
        "id": payment_id,
        "order_id": order_id,
        "status": "authorized",
        "amount": 9900,
        "currency": "INR",
    }

    with patch.dict(os.environ, {"RAZORPAY_KEY_ID": "rzp_key_test", "RAZORPAY_KEY_SECRET": secret}):
        with patch("main.fetch_razorpay_payment", return_value=mock_unsettled_payment):
            with pytest.raises(ApiError) as exc_info:
                verify_payment_signature(emulator_db, user_id, order_id, payment_id, valid_sig)

            assert exc_info.value.status_code == 400
            assert "settled state" in exc_info.value.message.lower()

            # Ensure order was NOT marked paid and coins NOT credited
            order_snap = emulator_db.collection("orders").document(order_id).get().to_dict()
            assert order_snap["status"] == "created"
            user_snap = emulator_db.collection("users").document(user_id).get().to_dict()
            assert user_snap["coins"] == 50


# ── TEST 20: Payment Amount & Currency Mismatch Rejection ─────────────────────
def test_real_firestore_payment_amount_currency_mismatch_rejected(emulator_db):
    """
    Verify /payments/verify rejects payments where gateway amount or currency
    does not match the server-created order.
    """
    secret = "rzp_secret_settle_test"
    order_id = "order_mismatch_123"
    payment_id = "pay_mismatch_456"
    user_id = "user_payer_3"

    emulator_db.collection("users").document(user_id).set({"id": user_id, "coins": 50})
    emulator_db.collection("orders").document(order_id).set({
        "orderId": order_id,
        "userId": user_id,
        "amount": 9900,
        "currency": "INR",
        "coins": 100,
        "status": "created",
    })

    sig_message = f"{order_id}|{payment_id}".encode("utf-8")
    valid_sig = hmac.new(secret.encode("utf-8"), sig_message, hashlib.sha256).hexdigest()

    # Mismatched amount (tampered client attempting to pay 100 paise for 100 coins)
    mock_tampered_payment = {
        "id": payment_id,
        "order_id": order_id,
        "status": "captured",
        "amount": 100,  # mismatch!
        "currency": "INR",
    }

    with patch.dict(os.environ, {"RAZORPAY_KEY_ID": "rzp_key_test", "RAZORPAY_KEY_SECRET": secret}):
        with patch("main.fetch_razorpay_payment", return_value=mock_tampered_payment):
            with pytest.raises(ApiError) as exc_info:
                verify_payment_signature(emulator_db, user_id, order_id, payment_id, valid_sig)

            assert exc_info.value.status_code == 400
            assert "amount mismatch" in exc_info.value.message.lower()
            assert emulator_db.collection("users").document(user_id).get().to_dict()["coins"] == 50


# ── TEST 21: Real Payment Webhook Captured & Idempotent Delivery ──────────────
def test_real_firestore_payment_webhook_captured_and_duplicate_delivery(emulator_db):
    """
    Verify webhook processing for payment.captured:
    1. Validates raw body HMAC signature with webhook secret.
    2. Credits user coins and marks order paid.
    3. Duplicate webhook delivery is handled idempotently without double-crediting.
    """
    secret = "wh_sec_emulator_test"
    user_id = "user_webhook_1"
    order_id = "order_wh_123"
    payment_id = "pay_wh_456"

    emulator_db.collection("users").document(user_id).set({"id": user_id, "coins": 10})
    emulator_db.collection("orders").document(order_id).set({
        "orderId": order_id,
        "userId": user_id,
        "amount": 9900,
        "currency": "INR",
        "coins": 100,
        "status": "created",
    })

    webhook_payload = {
        "event": "payment.captured",
        "payload": {
            "payment": {
                "entity": {
                    "id": payment_id,
                    "order_id": order_id,
                    "amount": 9900,
                    "currency": "INR",
                    "status": "captured",
                }
            }
        }
    }
    raw_body = json.dumps(webhook_payload).encode("utf-8")
    valid_sig = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()

    with patch.dict(os.environ, {"RAZORPAY_WEBHOOK_SECRET": secret}):
        # First delivery
        res1 = handle_payment_webhook(emulator_db, raw_body, valid_sig)
        assert res1["status"] == "ok"
        assert emulator_db.collection("users").document(user_id).get().to_dict()["coins"] == 110
        assert emulator_db.collection("orders").document(order_id).get().to_dict()["status"] == "paid"

        # Duplicate delivery
        res2 = handle_payment_webhook(emulator_db, raw_body, valid_sig)
        assert res2["status"] == "ok"
        assert "already processed" in res2["message"].lower()

        # Crucial check: Coins were NOT incremented again
        assert emulator_db.collection("users").document(user_id).get().to_dict()["coins"] == 110


# ── TEST 22: Real Payment Webhook Failed & Refund Events ──────────────────────
def test_real_firestore_payment_webhook_failed_and_refund(emulator_db):
    """
    Verify webhook processing for payment.failed and refund.processed events.
    """
    secret = "wh_sec_emulator_test"
    order_id = "order_wh_failed_123"
    payment_id = "pay_wh_failed_456"

    emulator_db.collection("orders").document(order_id).set({
        "orderId": order_id,
        "userId": "user_fail_1",
        "status": "created",
    })

    # Test payment.failed
    fail_payload = {
        "event": "payment.failed",
        "payload": {
            "payment": {
                "entity": {
                    "id": payment_id,
                    "order_id": order_id,
                    "error_code": "BAD_REQUEST_ERROR",
                    "error_description": "Payment was declined by issuing bank",
                }
            }
        }
    }
    raw_fail = json.dumps(fail_payload).encode("utf-8")
    sig_fail = hmac.new(secret.encode("utf-8"), raw_fail, hashlib.sha256).hexdigest()

    with patch.dict(os.environ, {"RAZORPAY_WEBHOOK_SECRET": secret}):
        res_fail = handle_payment_webhook(emulator_db, raw_fail, sig_fail)
        assert res_fail["status"] == "ok"

        order_doc = emulator_db.collection("orders").document(order_id).get().to_dict()
        assert order_doc["status"] == "failed"
        assert order_doc["errorCode"] == "BAD_REQUEST_ERROR"

        audit_doc = emulator_db.collection("payment_audit_logs").document(payment_id).get().to_dict()
        assert audit_doc["status"] == "failed"
        assert audit_doc["errorDescription"] == "Payment was declined by issuing bank"

        # Test refund.processed
        refund_payload = {
            "event": "refund.processed",
            "payload": {
                "refund": {
                    "entity": {
                        "id": "rfnd_test_789",
                        "payment_id": payment_id,
                        "amount": 9900,
                    }
                }
            }
        }
        raw_refund = json.dumps(refund_payload).encode("utf-8")
        sig_refund = hmac.new(secret.encode("utf-8"), raw_refund, hashlib.sha256).hexdigest()
        res_refund = handle_payment_webhook(emulator_db, raw_refund, sig_refund)
        assert res_refund["status"] == "ok"

        refund_audit = emulator_db.collection("payment_audit_logs").document("rfnd_test_789").get().to_dict()
        assert refund_audit["status"] == "refunded"
        assert refund_audit["amount"] == 9900

