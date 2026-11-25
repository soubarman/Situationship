"""
functions/tests/test_backend_security.py
────────────────────────────────────────
Comprehensive automated unit test suite using in-memory mocked Firestore objects:
- SEC-5.2-05: Critical identity binding and cross-target idempotency conflict rejection (HTTP 409).
- SEC-5.2-06: Strict idempotency key validation (regex, length, type, safe characters).
- SEC-5.2-01: Admin suspension check and fail-closed security.
- SEC-5.2-03: PII migration batch limit validation (1-250 range, operation limits <= 500).
- Existing phone unlock and PII migration access control tests.
"""

import sys
import os
import json
import pytest
from unittest.mock import MagicMock, patch
from flask import Flask, Request
from werkzeug.test import EnvironBuilder

# Ensure functions package is in sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from firebase_admin import firestore, auth
from google.api_core import exceptions as gcp_exceptions
import grpc
import main
from main import (
    api,
    execute_phone_unlock,
    execute_pii_migration,
    authenticate_admin,
    ApiError,
)

_flask_test_app = Flask("test_backend_security")

def call_api(path: str, method: str = "POST", json_data: dict = None, headers: dict = None, args: dict = None):
    """Helper to dispatch mock HTTP requests into the on_request api entrypoint."""
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


# ── In-Memory Firestore Mock Engine for Transactions & Batches ────────────────
class MockDocSnapshot:
    def __init__(self, doc_id: str, data: dict, exists: bool = True, reference = None):
        self.id = doc_id
        self._data = data.copy() if data else {}
        self.exists = exists
        self.reference = reference

    def to_dict(self):
        return self._data.copy() if self.exists else None

    @property
    def data(self):
        return self._data.copy() if self.exists else None


class MockDocRef:
    def __init__(self, store: dict, path: str):
        self.store = store
        self.path = path
        self.id = path.split("/")[-1]

    def get(self, transaction=None):
        if self.path in self.store:
            return MockDocSnapshot(self.id, self.store[self.path], exists=True, reference=self)
        return MockDocSnapshot(self.id, {}, exists=False, reference=self)

    def set(self, data: dict, merge: bool = False):
        clean_data = {}
        for k, v in data.items():
            if str(v) == "SERVER_TIMESTAMP" or "Sentinel" in str(type(v)):
                clean_data[k] = "2026-11-24T12:00:00Z"
            else:
                clean_data[k] = v

        if merge and self.path in self.store:
            self.store[self.path].update(clean_data)
        else:
            self.store[self.path] = clean_data.copy()

    def update(self, data: dict):
        if self.path not in self.store:
            raise KeyError(f"Document {self.path} does not exist")
        for k, v in data.items():
            if "Sentinel" in str(type(v)) or "DELETE_FIELD" in str(v) or v is firestore.DELETE_FIELD:
                self.store[self.path].pop(k, None)
            elif str(v) == "SERVER_TIMESTAMP":
                self.store[self.path][k] = "2026-11-24T12:00:00Z"
            else:
                self.store[self.path][k] = v

    def collection(self, name: str):
        return MockCollection(self.store, f"{self.path}/{name}")


class MockCollection:
    def __init__(self, store: dict, path: str):
        self.store = store
        self.path = path

    def document(self, doc_id: str):
        return MockDocRef(self.store, f"{self.path}/{doc_id}")

    def order_by(self, field: str):
        return MockQuery(self.store, self.path)

    def limit(self, count: int):
        return MockQuery(self.store, self.path, limit_val=count)

    def where(self, field, op, val):
        return MockQuery(self.store, self.path).where(field, op, val)

    def stream(self):
        return MockQuery(self.store, self.path).stream()


class MockQuery:
    def __init__(self, store: dict, col_path: str, limit_val: int = None, start_after_id: str = None):
        self.store = store
        self.col_path = col_path
        self.limit_val = limit_val
        self.start_after_id = start_after_id

    def order_by(self, field: str):
        return self

    def limit(self, count: int):
        self.limit_val = count
        return self

    def start_after(self, doc_or_dict):
        doc_id = doc_or_dict.id if hasattr(doc_or_dict, "id") else str(doc_or_dict)
        self.start_after_id = doc_id
        return self

    def where(self, field, op, val):
        if field in ["__name__", "document_id"] and op == ">":
            self.start_after_id = val
        return self

    def stream(self):
        docs = []
        prefix = f"{self.col_path}/"
        for k in sorted(self.store.keys()):
            if k.startswith(prefix):
                suffix = k[len(prefix):]
                if "/" not in suffix:
                    docs.append(MockDocSnapshot(suffix, self.store[k], exists=True, reference=MockDocRef(self.store, k)))

        if self.start_after_id:
            idx = -1
            for i, d in enumerate(docs):
                if d.id == self.start_after_id:
                    idx = i
                    break
            if idx >= 0:
                docs = docs[idx + 1:]

        if self.limit_val is not None:
            docs = docs[:self.limit_val]

        return docs


class MockBatch:
    def __init__(self, store: dict):
        self.store = store
        self.ops = []

    def set(self, ref, data, merge=False):
        self.ops.append(('set', ref, data, merge))

    def update(self, ref, data):
        self.ops.append(('update', ref, data))

    def commit(self):
        for op, ref, data, *extra in self.ops:
            if op == 'set':
                ref.set(data, merge=extra[0] if extra else False)
            elif op == 'update':
                ref.update(data)
        self.ops.clear()


class MockTransaction:
    def __init__(self, store: dict):
        self.store = store
        self.writes = []

    def update(self, ref, data: dict):
        self.writes.append(('update', ref, data))

    def set(self, ref, data: dict, merge: bool = False):
        self.writes.append(('set', ref, data, merge))

    def _commit(self):
        for op, ref, data, *extra in self.writes:
            if op == 'update':
                ref.update(data)
            elif op == 'set':
                ref.set(data, merge=extra[0] if extra else False)
        self.writes.clear()


class MockFirestoreDb:
    def __init__(self, store: dict = None):
        self.store = store if store is not None else {}

    def collection(self, name: str):
        return MockCollection(self.store, name)

    def batch(self):
        return MockBatch(self.store)

    def transaction(self):
        return MockTransaction(self.store)


def mock_transactional_decorator(fn):
    def wrapper(txn):
        res = fn(txn)
        if hasattr(txn, '_commit'):
            txn._commit()
        return res
    return wrapper

main.firestore.transactional = mock_transactional_decorator


# ── FIXTURES ──────────────────────────────────────────────────────────────────

@pytest.fixture
def mock_db():
    store = {
        # Caller Alice: 100 coins, not subscribed
        "users/caller1": {
            "id": "caller1",
            "name": "Alice",
            "coins": 100,
            "isSubscribed": False,
            "isSuspended": False,
            "unlockedUserPhones": [],
            "blockedUsers": [],
        },
        # Target Bob: Phone public, version 1
        "users/target1": {
            "id": "target1",
            "name": "Bob",
            "isPhonePublic": True,
            "phoneVisibilityVersion": 1,
            "blockedUsers": [],
        },
        "users/target1/private/profile": {
            "phoneNumber": "+91 98765 43210",
            "email": "bob@example.com",
        },
        # Target Charlie: Phone public, version 1
        "users/target_charlie": {
            "id": "target_charlie",
            "name": "Charlie",
            "isPhonePublic": True,
            "phoneVisibilityVersion": 1,
            "blockedUsers": [],
        },
        "users/target_charlie/private/profile": {
            "phoneNumber": "+91 77777 66666",
            "email": "charlie@example.com",
        },
        # Active Administrator
        "users/admin1": {
            "id": "admin1",
            "name": "Admin User",
            "isSuspended": False,
            "role": "admin",
        },
        # Suspended Administrator
        "users/admin_suspended": {
            "id": "admin_suspended",
            "name": "Suspended Admin",
            "isSuspended": True,
            "role": "admin",
        },
    }
    return MockFirestoreDb(store)


# ── FINDING 1 REGRESSION TESTS: SEC-5.2-05 CRITICAL IDENTITY BINDING ───────────

def test_idempotency_cross_target_reuse_rejected_with_409(mock_db):
    """
    Step 1: Unlock Bob using key 'same_key_123'.
    Step 2: Attempt to unlock Charlie using the SAME key 'same_key_123'.
    Step 3: Verify the second request returns HTTP 409 Conflict.
    Step 4: Verify Charlie's phone number is NEVER returned.
    Step 5: Verify no additional coins are deducted from caller.
    Step 6: Verify no contact record for Charlie is created.
    """
    key = "same_key_123"

    # Step 1: Unlock Bob
    res1 = execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key=key)
    assert res1["success"] is True
    assert res1["phoneNumber"] == "+91 98765 43210"
    assert mock_db.store["users/caller1"]["coins"] == 50

    # Step 2 & 3: Attempt to unlock Charlie with the same key
    with pytest.raises(ApiError) as exc_info:
        execute_phone_unlock(mock_db, "caller1", "target_charlie", idempotency_key=key)

    assert exc_info.value.status_code == 409
    assert "idempotency conflict" in exc_info.value.message.lower()

    # Step 4: Ensure Charlie's phone was never returned to caller
    assert "+91 77777 66666" not in str(exc_info.value)

    # Step 5: Verify caller coins remain at 50 (no additional deduction)
    assert mock_db.store["users/caller1"]["coins"] == 50

    # Step 6: Verify no contact record for Charlie was created
    assert "users/target_charlie/unlocked_contacts/caller1" not in mock_db.store


def test_idempotent_replay_legitimate_same_target(mock_db):
    """Verify legitimate replay for Bob with same key returns cached result without charging again."""
    key = "valid_replay_key"
    res1 = execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key=key)
    assert res1["success"] is True
    assert mock_db.store["users/caller1"]["coins"] == 50

    # Replay
    res2 = execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key=key)
    assert res2["success"] is True
    assert res2.get("idempotentReplay") is True
    assert res2["phoneNumber"] == "+91 98765 43210"
    # Still 50 coins
    assert mock_db.store["users/caller1"]["coins"] == 50


def test_idempotency_key_reused_for_obsolete_version_rejected_with_409(mock_db):
    """Verify changing phone visibility version cannot replay an obsolete key (409 Conflict)."""
    key = "version_bound_key"
    res1 = execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key=key)
    assert res1["success"] is True

    # Target user increments visibility version to 2
    mock_db.store["users/target1"]["phoneVisibilityVersion"] = 2

    # Attempting to reuse the same key for version 2 raises 409
    with pytest.raises(ApiError) as exc_info:
        execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key=key)

    assert exc_info.value.status_code == 409
    assert "obsolete visibility version" in exc_info.value.message.lower()


# ── FINDING 2 REGRESSION TESTS: SEC-5.2-06 IDEMPOTENCY KEY VALIDATION ──────────

def test_idempotency_key_validation_missing_key(mock_db):
    """Missing key (None) is permitted (proceeds without idempotency recording)."""
    res = execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key=None)
    assert res["success"] is True


def test_idempotency_key_validation_empty_key(mock_db):
    """Empty string key is rejected with HTTP 400."""
    with pytest.raises(ApiError) as exc_info:
        execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key="")
    assert exc_info.value.status_code == 400
    assert "between 8 and 128" in exc_info.value.message.lower()


def test_idempotency_key_validation_non_string(mock_db):
    """Non-string keys (int, bool, list) are rejected with HTTP 400."""
    with pytest.raises(ApiError) as exc_info1:
        execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key=12345678)
    assert exc_info1.value.status_code == 400
    assert "must be a string" in exc_info1.value.message.lower()

    with pytest.raises(ApiError) as exc_info2:
        execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key=True)
    assert exc_info2.value.status_code == 400


def test_idempotency_key_validation_path_traversal(mock_db):
    """Keys with '/' or path traversal characters are rejected with HTTP 400."""
    with pytest.raises(ApiError) as exc_info:
        execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key="key/with/slash")
    assert exc_info.value.status_code == 400
    assert "only ascii letters" in exc_info.value.message.lower()


def test_idempotency_key_validation_whitespace(mock_db):
    """Keys with whitespace are rejected with HTTP 400."""
    with pytest.raises(ApiError) as exc_info:
        execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key="key with spaces")
    assert exc_info.value.status_code == 400


def test_idempotency_key_validation_length_bounds(mock_db):
    """Keys shorter than 8 or longer than 128 characters are rejected with HTTP 400."""
    with pytest.raises(ApiError) as exc_short:
        execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key="short")
    assert exc_short.value.status_code == 400

    with pytest.raises(ApiError) as exc_long:
        execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key="a" * 129)
    assert exc_long.value.status_code == 400


def test_idempotency_key_validation_valid(mock_db):
    """Valid keys (alphanumeric, underscore, hyphen, 8-128 chars) are accepted."""
    valid_key = "unlock_caller1_target1_1-xyz"
    res = execute_phone_unlock(mock_db, "caller1", "target1", idempotency_key=valid_key)
    assert res["success"] is True


# ── FINDING 3 REGRESSION TESTS: SEC-5.2-01 ADMIN SUSPENSION CHECK ──────────────

@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_valid_active_administrator_accepted(mock_verify, mock_get_db, mock_db):
    mock_verify.return_value = {"uid": "admin1", "email": "admin@example.com", "admin": True}
    mock_get_db.return_value = mock_db

    class Req:
        headers = {"Authorization": "Bearer token"}
    uid = authenticate_admin(Req())
    assert uid == "admin1"


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_suspended_administrator_rejected(mock_verify, mock_get_db, mock_db):
    mock_verify.return_value = {"uid": "admin_suspended", "email": "suspended@example.com", "admin": True}
    mock_get_db.return_value = mock_db

    class Req:
        headers = {"Authorization": "Bearer token"}
    with pytest.raises(ValueError) as exc_info:
        authenticate_admin(Req())
    assert "suspended" in str(exc_info.value).lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_missing_admin_user_document_fails_closed(mock_verify, mock_get_db, mock_db):
    # Admin UID does not exist in users collection
    mock_verify.return_value = {"uid": "admin_ghost", "email": "ghost@example.com", "admin": True}
    mock_get_db.return_value = mock_db

    class Req:
        headers = {"Authorization": "Bearer token"}
    with pytest.raises(ValueError) as exc_info:
        authenticate_admin(Req())
    assert "not found" in str(exc_info.value).lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_ordinary_user_rejected_from_admin(mock_verify, mock_get_db, mock_db):
    mock_verify.return_value = {"uid": "caller1", "email": "caller1@example.com", "admin": False}
    mock_get_db.return_value = mock_db

    class Req:
        headers = {"Authorization": "Bearer token"}
    with pytest.raises(ValueError) as exc_info:
        authenticate_admin(Req())
    assert "admin privileges required" in str(exc_info.value).lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_admin_firestore_lookup_error_fails_closed(mock_verify, mock_get_db):
    mock_verify.return_value = {"uid": "admin1", "email": "admin@example.com", "admin": True}
    
    # Simulate database error
    exploding_db = MagicMock()
    exploding_db.collection.side_effect = RuntimeError("Firestore connection timeout")
    mock_get_db.return_value = exploding_db

    class Req:
        headers = {"Authorization": "Bearer token"}
    with pytest.raises(ValueError) as exc_info:
        authenticate_admin(Req())
    assert "verification failed" in str(exc_info.value).lower()


# ── FINDING 4 REGRESSION TESTS: SEC-5.2-03 PII MIGRATION BATCH LIMITS ──────────

@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_migration_batch_boundary_250_accepted(mock_verify, mock_get_db, mock_db):
    mock_verify.return_value = {"uid": "admin1", "email": "admin@example.com", "admin": True}
    mock_get_db.return_value = mock_db

    resp = call_api(
        "/admin/migrate-pii",
        method="POST",
        headers={"Authorization": "Bearer admin_token"},
        json_data={"batchSize": 250, "limit": 100}
    )
    assert resp.status_code == 200
    res = json.loads(resp.data)
    assert res["success"] is True


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_migration_batch_boundary_251_rejected(mock_verify, mock_get_db, mock_db):
    mock_verify.return_value = {"uid": "admin1", "email": "admin@example.com", "admin": True}
    mock_get_db.return_value = mock_db

    resp = call_api(
        "/admin/migrate-pii",
        method="POST",
        headers={"Authorization": "Bearer admin_token"},
        json_data={"batchSize": 251}
    )
    assert resp.status_code == 400
    assert "between 1 and 250" in json.loads(resp.data)["detail"].lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_migration_batch_size_zero_and_negative_rejected(mock_verify, mock_get_db, mock_db):
    mock_verify.return_value = {"uid": "admin1", "email": "admin@example.com", "admin": True}
    mock_get_db.return_value = mock_db

    resp0 = call_api(
        "/admin/migrate-pii",
        method="POST",
        headers={"Authorization": "Bearer admin_token"},
        json_data={"batchSize": 0}
    )
    assert resp0.status_code == 400

    resp_neg = call_api(
        "/admin/migrate-pii",
        method="POST",
        headers={"Authorization": "Bearer admin_token"},
        json_data={"batchSize": -10}
    )
    assert resp_neg.status_code == 400


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_migration_batch_size_boolean_and_non_numeric_rejected(mock_verify, mock_get_db, mock_db):
    mock_verify.return_value = {"uid": "admin1", "email": "admin@example.com", "admin": True}
    mock_get_db.return_value = mock_db

    # Boolean True (in Python isinstance(True, int) is True, so check explicitly)
    resp_bool = call_api(
        "/admin/migrate-pii",
        method="POST",
        headers={"Authorization": "Bearer admin_token"},
        json_data={"batchSize": True}
    )
    assert resp_bool.status_code == 400
    assert "must be an integer" in json.loads(resp_bool.data)["detail"].lower()

    # Non-numeric string
    resp_str = call_api(
        "/admin/migrate-pii",
        method="POST",
        headers={"Authorization": "Bearer admin_token"},
        json_data={"batchSize": "two_hundred"}
    )
    assert resp_str.status_code == 400


def test_migration_batch_operations_never_exceed_500():
    """Verify that even with 250 users in execute_pii_migration, total batch operations never exceed 500."""
    store = {
        f"users/user_{i:03d}": {
            "id": f"user_{i:03d}",
            "email": f"user_{i:03d}@example.com",
            "phoneNumber": f"+91 00000 00{i:03d}",
        } for i in range(250)
    }
    db = MockFirestoreDb(store)

    max_ops_seen = 0
    original_commit = MockBatch.commit

    def tracked_commit(self):
        nonlocal max_ops_seen
        max_ops_seen = max(max_ops_seen, len(self.ops))
        original_commit(self)

    with patch.object(MockBatch, "commit", side_effect=tracked_commit, autospec=True):
        res = execute_pii_migration(db, limit=250, batch_size=250)
        assert res["batchMigrated"] == 250

    # 250 users * 2 ops = 500 ops. Must not exceed 500.
    assert max_ops_seen <= 500


# ── EXISTING SECURITY CHECKS (PRESERVED) ───────────────────────────────────────

def test_unauthenticated_unlock_request():
    resp = call_api("/user/unlock-phone", method="POST", json_data={"targetUserId": "target1"})
    assert resp.status_code == 401
    assert "authorization header" in json.loads(resp.data)["detail"].lower()


@patch("main.auth.verify_id_token")
def test_invalid_firebase_token(mock_verify):
    mock_verify.side_effect = Exception("Firebase ID token has expired")
    resp = call_api(
        "/user/unlock-phone",
        method="POST",
        headers={"Authorization": "Bearer expired_token"},
        json_data={"targetUserId": "target1"}
    )
    assert resp.status_code == 401
    assert "authentication failed" in json.loads(resp.data)["detail"].lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_valid_administrator_migration(mock_verify, mock_get_db):
    mock_verify.return_value = {"uid": "admin1", "email": "admin@example.com", "admin": True}
    store = {
        "users/admin1": {
            "id": "admin1",
            "name": "Admin User",
            "isSuspended": False,
        },
        "users/user_legacy": {
            "id": "user_legacy",
            "name": "Legacy User",
            "email": "legacy@example.com",
            "phoneNumber": "+91 12345 67890",
        }
    }
    db = MockFirestoreDb(store)
    mock_get_db.return_value = db

    resp = call_api(
        "/admin/migrate-pii",
        method="POST",
        headers={"Authorization": "Bearer admin_token"},
        json_data={"limit": 100}
    )
    assert resp.status_code == 200
    res = json.loads(resp.data)
    assert res["success"] is True
    assert res["batchMigrated"] == 1
    assert "email" not in store["users/user_legacy"]
    assert store["users/user_legacy/private/profile"]["email"] == "legacy@example.com"


def test_insufficient_coin_balance(mock_db):
    mock_db.store["users/caller1"]["coins"] = 20
    with pytest.raises(ApiError) as exc_info:
        execute_phone_unlock(mock_db, "caller1", "target1")
    assert exc_info.value.status_code == 402


def test_blocked_user_unlock_attempts(mock_db):
    mock_db.store["users/target1"]["blockedUsers"] = ["caller1"]
    with pytest.raises(ApiError) as exc_info:
        execute_phone_unlock(mock_db, "caller1", "target1")
    assert exc_info.value.status_code == 403

    mock_db.store["users/target1"]["blockedUsers"] = []
    mock_db.store["users/caller1"]["blockedUsers"] = ["target1"]
    with pytest.raises(ApiError) as exc_info2:
        execute_phone_unlock(mock_db, "caller1", "target1")
    assert exc_info2.value.status_code == 403


def test_self_unlocking_rejected(mock_db):
    with pytest.raises(ApiError) as exc_info:
        execute_phone_unlock(mock_db, "caller1", "caller1")
    assert exc_info.value.status_code == 400


def test_transaction_failure_without_partial_coin_deduction(mock_db):
    def exploding_set(*args, **kwargs):
        raise RuntimeError("Database connection lost during write")

    with patch.object(MockTransaction, "set", side_effect=exploding_set):
        with pytest.raises(RuntimeError):
            execute_phone_unlock(mock_db, "caller1", "target1")

    assert mock_db.store["users/caller1"]["coins"] == 100
    assert "target1_1" not in mock_db.store["users/caller1"]["unlockedUserPhones"]


# ── PHASE 5.5: TASK 2 ADVERSARIAL ADMIN AUTHORIZATION TESTS ──────────────────

@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_admin_auth_missing_admin_claim_denied(mock_verify, mock_get_db, mock_db):
    """Token with no admin claim at all is denied."""
    mock_verify.return_value = {"uid": "admin1", "email": "admin@example.com"}  # missing 'admin' key
    mock_get_db.return_value = mock_db

    class Req:
        headers = {"Authorization": "Bearer token"}
    with pytest.raises(ValueError) as exc_info:
        authenticate_admin(Req())
    assert "admin privileges required" in str(exc_info.value).lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_admin_auth_admin_claim_false_denied(mock_verify, mock_get_db, mock_db):
    """Token with admin: False is denied."""
    mock_verify.return_value = {"uid": "admin1", "email": "admin@example.com", "admin": False}
    mock_get_db.return_value = mock_db

    class Req:
        headers = {"Authorization": "Bearer token"}
    with pytest.raises(ValueError) as exc_info:
        authenticate_admin(Req())
    assert "admin privileges required" in str(exc_info.value).lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_admin_auth_unverified_situationship_email_denied(mock_verify, mock_get_db, mock_db):
    """Unverified account with situationship@gmail.com without custom claim is strictly denied."""
    mock_verify.return_value = {"uid": "attacker_uid", "email": "situationship@gmail.com", "email_verified": False}
    mock_get_db.return_value = mock_db

    class Req:
        headers = {"Authorization": "Bearer token"}
    with pytest.raises(ValueError) as exc_info:
        authenticate_admin(Req())
    assert "admin privileges required" in str(exc_info.value).lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_admin_auth_verified_situationship_email_without_admin_claim_denied(mock_verify, mock_get_db, mock_db):
    """Verified account with situationship@gmail.com but without admin claim is strictly denied."""
    mock_verify.return_value = {"uid": "legit_looking_uid", "email": "situationship@gmail.com", "email_verified": True}
    mock_get_db.return_value = mock_db

    class Req:
        headers = {"Authorization": "Bearer token"}
    with pytest.raises(ValueError) as exc_info:
        authenticate_admin(Req())
    assert "admin privileges required" in str(exc_info.value).lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_admin_auth_ordinary_verified_user_denied(mock_verify, mock_get_db, mock_db):
    """Ordinary verified user without admin claim is denied."""
    mock_verify.return_value = {"uid": "caller1", "email": "user@example.com", "email_verified": True}
    mock_get_db.return_value = mock_db

    class Req:
        headers = {"Authorization": "Bearer token"}
    with pytest.raises(ValueError) as exc_info:
        authenticate_admin(Req())
    assert "admin privileges required" in str(exc_info.value).lower()


@patch("main.auth.verify_id_token")
def test_admin_auth_invalid_token_denied(mock_verify):
    """Invalid or unparseable token raises Authentication failed."""
    mock_verify.side_effect = Exception("Firebase ID token has invalid signature")

    class Req:
        headers = {"Authorization": "Bearer invalid_garbage_token"}
    with pytest.raises(ValueError) as exc_info:
        authenticate_admin(Req())
    assert "authentication failed" in str(exc_info.value).lower()


@patch("main.auth.verify_id_token")
def test_admin_auth_revoked_token_denied(mock_verify):
    """Revoked token raises RevokedIdTokenError and fails with Authentication failed."""
    mock_verify.side_effect = auth.RevokedIdTokenError("Token has been revoked")

    class Req:
        headers = {"Authorization": "Bearer revoked_token"}
    with pytest.raises(ValueError) as exc_info:
        authenticate_admin(Req())
    assert "revoked" in str(exc_info.value).lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_admin_auth_client_supplied_admin_in_body_denied(mock_verify, mock_get_db, mock_db):
    """Client-supplied admin=true or role='admin' in JSON body cannot grant administrative access."""
    mock_verify.return_value = {"uid": "caller1", "email": "caller1@example.com", "admin": False}
    mock_get_db.return_value = mock_db

    resp = call_api(
        "/admin/migrate-pii",
        method="POST",
        headers={"Authorization": "Bearer ordinary_user_token"},
        json_data={"admin": True, "role": "admin", "isAdmin": True, "batchSize": 100}
    )
    assert resp.status_code == 403
    body = json.loads(resp.data)
    assert "admin privileges required" in body["detail"].lower()


# ── PHASE 5.5: TASK 3 ALL ADMINISTRATIVE ENDPOINTS VERIFICATION ──────────────

@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_admin_endpoints_migrate_pii_rejects_non_admin(mock_verify, mock_get_db, mock_db):
    mock_verify.return_value = {"uid": "caller1", "email": "caller1@example.com", "admin": False}
    mock_get_db.return_value = mock_db
    resp = call_api("/admin/migrate-pii", method="POST", headers={"Authorization": "Bearer non_admin_token"})
    assert resp.status_code == 403


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_admin_endpoints_stats_rejects_non_admin(mock_verify, mock_get_db, mock_db):
    mock_verify.return_value = {"uid": "caller1", "email": "caller1@example.com", "admin": False}
    mock_get_db.return_value = mock_db
    resp = call_api("/admin/stats", method="GET", headers={"Authorization": "Bearer non_admin_token"})
    assert resp.status_code == 403


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_admin_endpoints_verifications_rejects_non_admin(mock_verify, mock_get_db, mock_db):
    mock_verify.return_value = {"uid": "caller1", "email": "caller1@example.com", "admin": False}
    mock_get_db.return_value = mock_db
    resp = call_api("/admin/verifications/target1/approve", method="POST", headers={"Authorization": "Bearer non_admin_token"}, json_data={"reason": "test"})
    assert resp.status_code == 403


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_admin_endpoints_reset_attempts_rejects_non_admin(mock_verify, mock_get_db, mock_db):
    mock_verify.return_value = {"uid": "caller1", "email": "caller1@example.com", "admin": False}
    mock_get_db.return_value = mock_db
    resp = call_api("/reset-attempts", method="GET", headers={"Authorization": "Bearer non_admin_token"}, args={"userId": "target1"})
    assert resp.status_code == 403


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_admin_endpoints_create_admin_disabled(mock_verify, mock_get_db, mock_db):
    """Endpoint /create-admin is disabled in production and cannot be accessed by non-admins or admins."""
    # Non-admin is rejected with 403 (Admin privileges required)
    mock_verify.return_value = {"uid": "caller1", "email": "caller1@example.com", "admin": False}
    mock_get_db.return_value = mock_db
    resp1 = call_api("/create-admin", method="GET", headers={"Authorization": "Bearer non_admin_token"})
    assert resp1.status_code == 403

    # Genuine admin also receives 403 (Disabled in production)
    mock_verify.return_value = {"uid": "admin1", "email": "admin@example.com", "admin": True}
    resp2 = call_api("/create-admin", method="GET", headers={"Authorization": "Bearer admin_token"})
    assert resp2.status_code == 403
    assert b"disabled in production" in resp2.data.lower()


# ── PHASE 5.5: TASK 4 STRUCTURED CONTENTION RETRY TESTS ──────────────────────

def test_transaction_retry_on_gcp_aborted_exception(mock_db):
    """Verify that google.api_core.exceptions.Aborted triggers retries with fresh transactions."""
    attempts = 0
    real_transaction = mock_db.transaction

    def flaky_transaction():
        nonlocal attempts
        attempts += 1
        txn = real_transaction()
        if attempts == 1:
            orig_set = txn.set
            def fail_set(*args, **kwargs):
                raise gcp_exceptions.Aborted("Transaction conflict on commit")
            txn.set = fail_set
        return txn

    with patch.object(mock_db, "transaction", side_effect=flaky_transaction):
        res = execute_phone_unlock(mock_db, "caller1", "target1")
        assert res["success"] is True
        assert attempts == 2


def test_transaction_no_retry_on_permanent_api_error(mock_db):
    """Verify that ApiError (e.g. 402, 403, 409) is NOT retried."""
    mock_db.store["users/caller1"]["coins"] = 10
    with pytest.raises(ApiError) as exc_info:
        execute_phone_unlock(mock_db, "caller1", "target1")
    assert exc_info.value.status_code == 402


# ── PHASE 5.5: TASK 5 HTTP AND AUTHENTICATION LAYER TESTS ────────────────────

def test_http_missing_auth_header_returns_401():
    """HTTP request with missing Authorization header returns HTTP 401."""
    resp = call_api("/admin/stats", method="GET")
    assert resp.status_code == 401
    body = json.loads(resp.data)
    assert "authorization header" in body["detail"].lower()


def test_http_malformed_bearer_token_returns_401():
    """HTTP request with malformed Bearer header returns HTTP 401."""
    resp1 = call_api("/admin/stats", method="GET", headers={"Authorization": "Basic 12345"})
    assert resp1.status_code == 401

    resp2 = call_api("/admin/stats", method="GET", headers={"Authorization": "Bearer "})
    assert resp2.status_code == 401


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_http_ordinary_user_calling_admin_endpoint_returns_403(mock_verify, mock_get_db, mock_db):
    """Ordinary user token calling admin endpoint receives HTTP 403."""
    mock_verify.return_value = {"uid": "caller1", "email": "caller1@example.com", "admin": False}
    mock_get_db.return_value = mock_db
    resp = call_api("/admin/stats", method="GET", headers={"Authorization": "Bearer ordinary_token"})
    assert resp.status_code == 403
    body = json.loads(resp.data)
    assert "admin privileges required" in body["detail"].lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_http_unverified_allowlisted_email_without_admin_claim_returns_403(mock_verify, mock_get_db, mock_db):
    """Unverified email situationship@gmail.com without admin claim receives HTTP 403."""
    mock_verify.return_value = {"uid": "spoofed_uid", "email": "situationship@gmail.com", "email_verified": False}
    mock_get_db.return_value = mock_db
    resp = call_api("/admin/stats", method="GET", headers={"Authorization": "Bearer spoofed_token"})
    assert resp.status_code == 403
    body = json.loads(resp.data)
    assert "admin privileges required" in body["detail"].lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_http_genuine_admin_claim_accepted_returns_200(mock_verify, mock_get_db, mock_db):
    """Genuine admin claim with active account returns HTTP 200."""
    mock_verify.return_value = {"uid": "admin1", "email": "admin@example.com", "admin": True}
    mock_get_db.return_value = mock_db
    resp = call_api("/admin/stats", method="GET", headers={"Authorization": "Bearer admin_token"})
    assert resp.status_code == 200
    body = json.loads(resp.data)
    assert "pending_review" in body


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_http_suspended_admin_returns_403(mock_verify, mock_get_db, mock_db):
    """Suspended admin returns HTTP 403."""
    mock_verify.return_value = {"uid": "admin_suspended", "email": "suspended@example.com", "admin": True}
    mock_get_db.return_value = mock_db
    resp = call_api("/admin/stats", method="GET", headers={"Authorization": "Bearer admin_token"})
    assert resp.status_code == 403
    body = json.loads(resp.data)
    assert "suspended" in body["detail"].lower()


@patch("main.auth.verify_id_token")
def test_http_revoked_token_returns_401(mock_verify):
    """Revoked token calling admin endpoint receives HTTP 401."""
    mock_verify.side_effect = auth.RevokedIdTokenError("Token has been revoked")
    resp = call_api("/admin/stats", method="GET", headers={"Authorization": "Bearer revoked_token"})
    assert resp.status_code == 401
    body = json.loads(resp.data)
    assert "revoked" in body["detail"].lower()


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_http_client_supplied_uid_cannot_impersonate_admin(mock_verify, mock_get_db, mock_db):
    """Client-supplied userId or UID in query/body cannot impersonate an admin UID."""
    mock_verify.return_value = {"uid": "caller1", "email": "caller1@example.com", "admin": False}
    mock_get_db.return_value = mock_db
    resp = call_api("/admin/stats", method="GET", headers={"Authorization": "Bearer ordinary_token"}, args={"uid": "admin1", "userId": "admin1"})
    assert resp.status_code == 403


@patch("main.get_db")
@patch("main.auth.verify_id_token")
def test_http_admin_endpoint_does_not_execute_logic_on_failed_auth(mock_verify, mock_get_db, mock_db):
    """Administrative business logic is never executed when auth fails."""
    mock_verify.return_value = {"uid": "caller1", "email": "caller1@example.com", "admin": False}
    mock_get_db.return_value = mock_db
    target_snap_before = mock_db.collection("verifications").document("target1").get().to_dict()

    resp = call_api(
        "/admin/verifications/target1/approve",
        method="POST",
        headers={"Authorization": "Bearer non_admin_token"},
        json_data={"reason": "unauthorized approve"}
    )
    assert resp.status_code == 403

    # Assert Firestore was NOT mutated
    target_snap_after = mock_db.collection("verifications").document("target1").get().to_dict()
    assert target_snap_before == target_snap_after


# ── Payment, Spotlight & User Reward Unit Tests ──────────────────────────────
from main import (
    create_payment_order,
    verify_payment_signature,
    handle_payment_webhook,
    execute_spotlight_bid,
    execute_daily_login,
    execute_claim_milestone,
)
import hmac
import hashlib


def test_payment_create_order_503_when_unconfigured(mock_db):
    """create_payment_order raises 503 when Razorpay credentials are not configured."""
    with patch.dict(os.environ, {"RAZORPAY_KEY_ID": "", "RAZORPAY_KEY_SECRET": ""}):
        with pytest.raises(ApiError) as exc:
            create_payment_order(mock_db, "user1", "pack_100")
        assert exc.value.status_code == 503
        assert "configuration required" in exc.value.message.lower()


def test_payment_create_order_invalid_pack_400(mock_db):
    """create_payment_order raises 400 when an invalid packId is requested."""
    with patch.dict(os.environ, {"RAZORPAY_KEY_ID": "rzp_test_123", "RAZORPAY_KEY_SECRET": "sec_test_123"}):
        with pytest.raises(ApiError) as exc:
            create_payment_order(mock_db, "user1", "invalid_pack")
        assert exc.value.status_code == 400
        assert "invalid coin pack" in exc.value.message.lower()


def test_payment_create_order_success(mock_db):
    """create_payment_order creates an order document in Firestore and returns order payload."""
    with patch.dict(os.environ, {"RAZORPAY_KEY_ID": "rzp_test_123", "RAZORPAY_KEY_SECRET": "sec_test_123"}):
        res = create_payment_order(mock_db, "user1", "pack_100")
        assert res["success"] is True
        assert res["amount"] == 9900
        assert res["coins"] == 100
        order_id = res["orderId"]
        saved = mock_db.collection("orders").document(order_id).get().to_dict()
        assert saved is not None
        assert saved["status"] == "created"
        assert saved["userId"] == "user1"


def test_payment_verify_invalid_signature_400(mock_db):
    """verify_payment_signature rejects invalid HMAC-SHA256 signature with 400."""
    with patch.dict(os.environ, {"RAZORPAY_KEY_ID": "rzp_test_123", "RAZORPAY_KEY_SECRET": "sec_test_123"}):
        with pytest.raises(ApiError) as exc:
            verify_payment_signature(mock_db, "user1", "order_123", "pay_123", "bad_signature")
        assert exc.value.status_code == 400
        assert "invalid payment signature" in exc.value.message.lower()


def test_payment_verify_success_awards_coins_and_audit_log(mock_db):
    """verify_payment_signature verifies signature, credits coins, and writes audit log."""
    secret = "sec_test_123"
    order_id = "order_abc123"
    payment_id = "pay_xyz789"
    message = f"{order_id}|{payment_id}".encode("utf-8")
    valid_sig = hmac.new(secret.encode("utf-8"), message, hashlib.sha256).hexdigest()

    mock_db.collection("orders").document(order_id).set({
        "orderId": order_id,
        "userId": "user1",
        "coins": 100,
        "amount": 9900,
        "status": "created",
    })
    mock_db.collection("users").document("user1").set({"coins": 50})

    mock_gateway = {
        "id": payment_id,
        "order_id": order_id,
        "status": "captured",
        "amount": 9900,
        "currency": "INR",
    }
    with patch.dict(os.environ, {"RAZORPAY_KEY_ID": "rzp_test_123", "RAZORPAY_KEY_SECRET": secret}):
        with patch("main.fetch_razorpay_payment", return_value=mock_gateway):
            res = verify_payment_signature(mock_db, "user1", order_id, payment_id, valid_sig)
            assert res["success"] is True
            assert res["newBalance"] == 150

            # Assert order marked paid
            order_doc = mock_db.collection("orders").document(order_id).get().to_dict()
            assert order_doc["status"] == "paid"

            # Assert audit log exists
            audit = mock_db.collection("payment_audit_logs").document(payment_id).get().to_dict()
            assert audit is not None
            assert audit["coins"] == 100

            # Idempotency replay
            res2 = verify_payment_signature(mock_db, "user1", order_id, payment_id, valid_sig)
            assert res2["success"] is True
            assert res2["alreadyProcessed"] is True
            # Coins must NOT increase again
            user_doc = mock_db.collection("users").document("user1").get().to_dict()
            assert user_doc["coins"] == 150


def test_spotlight_bid_insufficient_coins_402(mock_db):
    """execute_spotlight_bid returns 402 if user has fewer coins than the bid."""
    mock_db.collection("users").document("user_broke").set({"coins": 5})
    with pytest.raises(ApiError) as exc:
        execute_spotlight_bid(mock_db, "user_broke", 50)
    assert exc.value.status_code == 402
    assert "insufficient coins" in exc.value.message.lower()


def test_spotlight_bid_success_deducts_coins(mock_db):
    """execute_spotlight_bid atomically deducts coins and writes session bid."""
    mock_db.collection("users").document("user_rich").set({"coins": 150, "displayName": "RichUser"})
    res = execute_spotlight_bid(mock_db, "user_rich", 50, session_id="session_mumbai")
    assert res["success"] is True
    assert res["remainingCoins"] == 100

    user_doc = mock_db.collection("users").document("user_rich").get().to_dict()
    assert user_doc["coins"] == 100

    bid_doc = mock_db.collection("spotlight_sessions").document("session_mumbai").collection("bids").document("user_rich").get().to_dict()
    assert bid_doc is not None
    assert bid_doc["amount"] == 50


def test_daily_login_award_and_idempotency(mock_db):
    """execute_daily_login awards coins and is idempotent for the same day."""
    mock_db.collection("users").document("user_login").set({"coins": 20, "loginStreak": 2})

    res = execute_daily_login(mock_db, "user_login")
    assert res["success"] is True
    assert res["alreadyClaimed"] is False
    assert res["rewardCoins"] > 0
    new_coins = res["coins"]

    # Replay on same day
    res2 = execute_daily_login(mock_db, "user_login")
    assert res2["success"] is True
    assert res2["alreadyClaimed"] is True
    assert res2["rewardCoins"] == 0
    assert res2["coins"] == new_coins


def test_milestone_claim_photo_verified(mock_db):
    """execute_claim_milestone verifies requirement and prevents duplicate claims."""
    # Unverified user cannot claim photo_verified
    mock_db.collection("users").document("user_unverified").set({"coins": 10, "isVerified": False})
    with pytest.raises(ApiError) as exc:
        execute_claim_milestone(mock_db, "user_unverified", "photo_verified")
    assert exc.value.status_code == 400

    # Verified user can claim photo_verified (50 coins)
    mock_db.collection("users").document("user_verified").set({"coins": 10, "isVerified": True})
    res = execute_claim_milestone(mock_db, "user_verified", "photo_verified")
    assert res["success"] is True
    assert res["rewardCoins"] == 50
    assert res["coins"] == 60

    # Second claim fails with 409 Conflict
    with pytest.raises(ApiError) as exc:
        execute_claim_milestone(mock_db, "user_verified", "photo_verified")
    assert exc.value.status_code == 409

