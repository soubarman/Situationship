"""Admin Management CLI Tool for Situationship.

Enforces server-side administrator provisioning and de-provisioning using
Firebase Admin SDK. Strictly uses custom claims ('admin': True) and revokes
refresh tokens on de-provisioning to prevent unauthorized session persistence.

Usage:
    python tools/admin_manager.py grant <uid>
    python tools/admin_manager.py revoke <uid>
    python tools/admin_manager.py get <uid>
    python tools/admin_manager.py list
"""

import argparse
import os
import sys
from typing import Optional

import firebase_admin
from firebase_admin import auth, firestore

_app_initialized = False


def init_firebase():
    global _app_initialized
    if not _app_initialized:
        if not firebase_admin._apps:
            # Respect FIREBASE_AUTH_EMULATOR_HOST and FIRESTORE_EMULATOR_HOST if set
            firebase_admin.initialize_app()
        _app_initialized = True


def get_db():
    init_firebase()
    return firestore.client()


def grant_admin(uid: str) -> bool:
    """Safely grants admin claim to the specified UID and updates Firestore."""
    init_firebase()
    db = get_db()

    try:
        user = auth.get_user(uid)
    except auth.UserNotFoundError:
        print(f"[ERROR] User with UID '{uid}' not found in Firebase Auth.", file=sys.stderr)
        return False
    except Exception as e:
        print(f"[ERROR] Failed to fetch user from Firebase Auth: {e}", file=sys.stderr)
        return False

    current_claims = user.custom_claims or {}
    if current_claims.get("admin") is True:
        print(f"[INFO] User {uid} already has admin custom claim.")
    else:
        new_claims = dict(current_claims)
        new_claims["admin"] = True
        try:
            auth.set_custom_user_claims(uid, new_claims)
            print(f"[SUCCESS] Custom claim 'admin: True' granted to UID: {uid}")
        except Exception as e:
            print(f"[ERROR] Failed to set custom claims: {e}", file=sys.stderr)
            return False

    # Also update Firestore role if user doc exists
    try:
        user_ref = db.collection("users").document(uid)
        user_doc = user_ref.get()
        if user_doc.exists:
            user_ref.update({
                "role": "admin",
                "isAdmin": True,
                "adminGrantedAt": firestore.SERVER_TIMESTAMP,
            })
            print(f"[SUCCESS] Updated Firestore document users/{uid} with role='admin'.")
        else:
            print(f"[WARN] Firestore document users/{uid} does not exist yet. Claim set in Auth only.")
    except Exception as e:
        print(f"[WARN] Failed to update Firestore user document: {e}", file=sys.stderr)

    return True


def revoke_admin(uid: str) -> bool:
    """Revokes admin claim from the specified UID, revokes tokens, and updates Firestore."""
    init_firebase()
    db = get_db()

    try:
        user = auth.get_user(uid)
    except auth.UserNotFoundError:
        print(f"[ERROR] User with UID '{uid}' not found in Firebase Auth.", file=sys.stderr)
        return False
    except Exception as e:
        print(f"[ERROR] Failed to fetch user from Firebase Auth: {e}", file=sys.stderr)
        return False

    current_claims = user.custom_claims or {}
    new_claims = dict(current_claims)
    new_claims.pop("admin", None)

    try:
        auth.set_custom_user_claims(uid, new_claims)
        print(f"[SUCCESS] Removed 'admin' claim from UID: {uid}")
    except Exception as e:
        print(f"[ERROR] Failed to remove custom claims: {e}", file=sys.stderr)
        return False

    # Invalidate existing sessions immediately
    try:
        auth.revoke_refresh_tokens(uid)
        print(f"[SUCCESS] Revoked all refresh tokens for UID: {uid} to prevent token persistence.")
    except Exception as e:
        print(f"[WARN] Could not revoke refresh tokens: {e}", file=sys.stderr)

    # Update Firestore role
    try:
        user_ref = db.collection("users").document(uid)
        user_doc = user_ref.get()
        if user_doc.exists:
            user_ref.update({
                "role": "user",
                "isAdmin": False,
                "adminRevokedAt": firestore.SERVER_TIMESTAMP,
            })
            print(f"[SUCCESS] Updated Firestore document users/{uid} with role='user'.")
    except Exception as e:
        print(f"[WARN] Failed to update Firestore user document: {e}", file=sys.stderr)

    return True


def get_user_status(uid: str):
    """Displays Auth claims and Firestore profile status for a user."""
    init_firebase()
    db = get_db()

    print(f"--- User Status: {uid} ---")
    try:
        user = auth.get_user(uid)
        print(f"Auth UID:          {user.uid}")
        print(f"Auth Email:        {user.email} (verified: {user.email_verified})")
        print(f"Auth Disabled:     {user.disabled}")
        print(f"Custom Claims:     {user.custom_claims}")
        print(f"Admin Claim:       {bool(user.custom_claims and user.custom_claims.get('admin') is True)}")
    except auth.UserNotFoundError:
        print(f"[WARN] User not found in Firebase Auth.")
    except Exception as e:
        print(f"[ERROR] Auth fetch error: {e}")

    try:
        user_ref = db.collection("users").document(uid)
        doc = user_ref.get()
        if doc.exists:
            data = doc.to_dict() or {}
            print(f"Firestore Role:    {data.get('role')}")
            print(f"Firestore isAdmin: {data.get('isAdmin')}")
            print(f"isSuspended:       {data.get('isSuspended')}")
        else:
            print(f"Firestore Doc:     DOES NOT EXIST")
    except Exception as e:
        print(f"[ERROR] Firestore fetch error: {e}")


def list_admins():
    """Lists all users registered with role='admin' in Firestore."""
    init_firebase()
    db = get_db()
    print("--- Listing Administrative Accounts ---")
    try:
        users = db.collection("users").where("role", "==", "admin").stream()
        count = 0
        for doc in users:
            count += 1
            data = doc.to_dict()
            print(f"UID: {doc.id} | DisplayName: {data.get('displayName', 'N/A')} | isAdmin: {data.get('isAdmin')}")
        if count == 0:
            print("No users found with role='admin' in Firestore.")
    except Exception as e:
        print(f"[ERROR] Failed to query Firestore admins: {e}")


def main():
    parser = argparse.ArgumentParser(description="Situationship Admin Claim & Role Manager")
    subparsers = parser.add_subparsers(dest="command", required=True)

    grant_parser = subparsers.add_parser("grant", help="Grant admin claim to user")
    grant_parser.add_argument("uid", help="Firebase User UID")

    revoke_parser = subparsers.add_parser("revoke", help="Revoke admin claim from user")
    revoke_parser.add_argument("uid", help="Firebase User UID")

    get_parser = subparsers.add_parser("get", help="Inspect user admin status")
    get_parser.add_argument("uid", help="Firebase User UID")

    subparsers.add_parser("list", help="List admin accounts in Firestore")

    args = parser.parse_args()

    if args.command == "grant":
        success = grant_admin(args.uid)
        sys.exit(0 if success else 1)
    elif args.command == "revoke":
        success = revoke_admin(args.uid)
        sys.exit(0 if success else 1)
    elif args.command == "get":
        get_user_status(args.uid)
    elif args.command == "list":
        list_admins()


if __name__ == "__main__":
    main()
