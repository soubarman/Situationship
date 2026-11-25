"""Server-Side PII Migration Runner for Situationship.

Executes atomic, batched migration of legacy PII (email, phoneNumber, etc.)
from public user profiles (users/{uid}) into users/{uid}/private/profile.
Deletes the legacy fields from public documents.

Features:
- Cursor-based pagination (`start_after`)
- Maximum batch size of 200 documents (400 atomic writes, well under Firestore's 500 limit)
- Checkpoint persistence in `_admin_migrations/pii_remediation`
- Support for dry-run inspection (--dry-run)
- Resumable from last checkpoint (--resume)
- Idempotent and non-destructive: does not overwrite newer private data

Usage:
    # Dry-run inspection
    python tools/run_pii_migration.py --dry-run

    # Execute full migration
    python tools/run_pii_migration.py --execute

    # Resume from checkpoint
    python tools/run_pii_migration.py --execute --resume
"""

import argparse
import sys
import time
from typing import Optional, Dict, Any

import firebase_admin
from firebase_admin import firestore

_app_initialized = False
CHECKPOINT_DOC = "_admin_migrations/pii_remediation"
LEGACY_PII_FIELDS = [
    "email",
    "phoneNumber",
    "unlockedUserPhones",
    "phoneUnlocksUsed",
]
MAX_BATCH_SIZE = 200  # 200 docs * 2 writes = 400 operations (limit is 500)


def init_firebase():
    global _app_initialized
    if not _app_initialized:
        if not firebase_admin._apps:
            firebase_admin.initialize_app()
        _app_initialized = True


def get_db():
    init_firebase()
    return firestore.client()


def get_checkpoint(db) -> Optional[Dict[str, Any]]:
    ref = db.document(CHECKPOINT_DOC)
    doc = ref.get()
    if doc.exists:
        return doc.to_dict()
    return None


def save_checkpoint(db, last_uid: Optional[str], migrated: int, skipped: int, errors: int, status: str):
    ref = db.document(CHECKPOINT_DOC)
    ref.set({
        "lastProcessedUid": last_uid,
        "migratedCount": migrated,
        "skippedCount": skipped,
        "errorCount": errors,
        "status": status,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }, merge=True)


def run_migration(dry_run: bool = True, resume: bool = False, batch_size: int = MAX_BATCH_SIZE):
    db = get_db()
    batch_size = min(batch_size, MAX_BATCH_SIZE)

    print("=" * 60)
    print("SITUATIONSHIP PII MIGRATION RUNNER")
    print(f"Mode: {'DRY RUN (no writes)' if dry_run else 'LIVE EXECUTION'}")
    print(f"Batch Size: {batch_size} documents")
    print("=" * 60)

    last_doc = None
    migrated_total = 0
    skipped_total = 0
    error_total = 0

    if resume:
        checkpoint = get_checkpoint(db)
        if checkpoint and checkpoint.get("lastProcessedUid"):
            last_uid = checkpoint["lastProcessedUid"]
            print(f"[RESUME] Resuming from last checkpoint UID: {last_uid}")
            migrated_total = checkpoint.get("migratedCount", 0)
            skipped_total = checkpoint.get("skippedCount", 0)
            error_total = checkpoint.get("errorCount", 0)
            try:
                last_doc = db.collection("users").document(last_uid).get()
                if not last_doc.exists:
                    print(f"[WARN] Checkpoint document {last_uid} not found. Starting fresh.")
                    last_doc = None
            except Exception as e:
                print(f"[WARN] Error loading checkpoint doc: {e}. Starting fresh.")
                last_doc = None

    if not dry_run:
        save_checkpoint(db, last_doc.id if last_doc else None, migrated_total, skipped_total, error_total, "RUNNING")

    batch_number = 0

    while True:
        batch_number += 1
        query = db.collection("users").order_by("__name__").limit(batch_size)
        if last_doc:
            query = query.start_after(last_doc)

        docs = list(query.stream())
        if not docs:
            print("[INFO] No more user documents to process. Migration complete.")
            break

        print(f"\n--- Batch {batch_number}: Processing {len(docs)} documents ---")

        batch = db.batch() if not dry_run else None
        batch_migrated = 0
        batch_skipped = 0
        batch_errors = 0

        for doc in docs:
            uid = doc.id
            data = doc.to_dict() or {}

            # Check if document contains legacy PII
            has_pii = any(field in data and data[field] is not None for field in LEGACY_PII_FIELDS)

            if not has_pii:
                batch_skipped += 1
                continue

            try:
                # Check existing private profile to ensure we NEVER overwrite newer private data
                private_ref = db.collection("users").document(uid).collection("private").document("profile")
                private_snap = private_ref.get()
                private_data = private_snap.to_dict() if private_snap.exists else {}

                private_payload: Dict[str, Any] = {}
                if "email" in data and data["email"] and not private_data.get("email"):
                    private_payload["email"] = data["email"]
                if "phoneNumber" in data and data["phoneNumber"] and not private_data.get("phoneNumber"):
                    private_payload["phoneNumber"] = data["phoneNumber"]

                if private_payload:
                    private_payload["migratedAt"] = firestore.SERVER_TIMESTAMP

                # Public document delete payload: delete all legacy PII and unlock tracking fields
                public_delete_payload = {
                    field: firestore.DELETE_FIELD
                    for field in LEGACY_PII_FIELDS
                    if field in data
                }
                public_delete_payload["piiMigratedAt"] = firestore.SERVER_TIMESTAMP

                if dry_run:
                    print(f"  [DRY-RUN] UID: {uid} -> Migrating fields: {list(public_delete_payload.keys())} (preserving private: {list(private_data.keys())})")
                else:
                    if private_payload:
                        batch.set(private_ref, private_payload, merge=True)
                    batch.update(doc.reference, public_delete_payload)

                batch_migrated += 1
            except Exception as e:
                print(f"  [ERROR] Failed to stage migration for UID {uid}: {e}")
                batch_errors += 1

        if not dry_run and batch_migrated > 0:
            try:
                batch.commit()
                print(f"  [SUCCESS] Batch {batch_number} committed ({batch_migrated} migrated).")
            except Exception as e:
                print(f"  [FATAL] Failed to commit batch {batch_number}: {e}")
                batch_errors += batch_migrated
                batch_migrated = 0

        migrated_total += batch_migrated
        skipped_total += batch_skipped
        error_total += batch_errors

        last_doc = docs[-1]
        if not dry_run:
            save_checkpoint(db, last_doc.id, migrated_total, skipped_total, error_total, "IN_PROGRESS")

        # Small pause between batches to prevent hammering Firestore quota
        time.sleep(0.1)

    final_status = "COMPLETED" if error_total == 0 else "COMPLETED_WITH_ERRORS"
    if not dry_run:
        save_checkpoint(db, last_doc.id if last_doc else None, migrated_total, skipped_total, error_total, final_status)

    print("\n" + "=" * 60)
    print("MIGRATION SUMMARY")
    print(f"Status:          {final_status}")
    print(f"Total Migrated:  {migrated_total}")
    print(f"Total Skipped:   {skipped_total}")
    print(f"Total Errors:    {error_total}")
    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(description="Situationship PII Migration Runner")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--dry-run", action="store_true", help="Inspect documents without making writes")
    group.add_argument("--execute", action="store_true", help="Perform real writes")

    parser.add_argument("--resume", action="store_true", help="Resume from last checkpoint")
    parser.add_argument("--batch-size", type=int, default=MAX_BATCH_SIZE, help="Documents per batch (max 200)")

    args = parser.parse_args()
    run_migration(dry_run=args.dry_run, resume=args.resume, batch_size=args.batch_size)


if __name__ == "__main__":
    main()
