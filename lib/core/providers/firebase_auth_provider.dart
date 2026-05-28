import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'firestore_provider.dart';

// ─── Auth State Stream ───────────────────────────────────────────────────────

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

// ─── Auth Controller ─────────────────────────────────────────────────────────

class AuthController extends StateNotifier<AsyncValue<User?>> {
  AuthController() : super(const AsyncValue.loading()) {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      state = AsyncValue.data(user);
    });
  }

  final _auth = FirebaseAuth.instance;

  // Convenience getter for Firestore using the centralized provider
  FirebaseFirestore get _db => firestoreProvider;

  // ── Email Sign In ───────────────────────────────────────────────────────────

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      state = AsyncValue.data(_auth.currentUser);
    } on FirebaseAuthException catch (e) {
      state = const AsyncValue.data(null);
      throw _mapFirebaseError(e);
    }
  }

  // ── Email Sign Up ───────────────────────────────────────────────────────────

  Future<void> signUpWithEmail({
    required String name,
    required String email,
    required String password,
    required int age,
    required String bio,
    required String location,
    required List<String> interests,
    XFile? avatarFile,
  }) async {
    state = const AsyncValue.loading();
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      final user = cred.user!;

      await user.updateDisplayName(name);

      String? photoUrl;

      if (avatarFile != null) {
        final storageRef =
            FirebaseStorage.instance.ref('avatars/${user.uid}.jpg');

        if (kIsWeb) {
          final bytes = await avatarFile.readAsBytes();
          await storageRef.putData(bytes);
        } else {
          await storageRef.putFile(File(avatarFile.path));
        }

        photoUrl = await storageRef.getDownloadURL();
        await user.updatePhotoURL(photoUrl);
      }

      await _db.collection('users').doc(user.uid).set({
        'id': user.uid,
        'name': name,
        'email': email,
        'bio': bio,
        'age': age,
        'location': location,
        'avatarUrl': photoUrl,
        'interests': interests,
        'isVerified': false,
        'isOnline': true,
        'photos': photoUrl != null ? [photoUrl] : [],
        'followers': [],
        'following': [],
        'likedBy': [],
        'matches': [],
        'postCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      state = AsyncValue.data(user);
    } on FirebaseAuthException catch (e) {
      state = const AsyncValue.data(null);
      throw _mapFirebaseError(e);
    }
  }

  // ── Google Sign In (FINAL FIXED VERSION) ────────────────────────────────────

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();

    try {
      if (kIsWeb) {
        // ✅ Correct for Flutter Web
        final provider = GoogleAuthProvider();
        await _auth.signInWithPopup(provider);
      } else {
        // ✅ Mobile
        final GoogleSignIn googleSignIn = GoogleSignIn();
        final GoogleSignInAccount? googleUser =
            await googleSignIn.signIn();

        if (googleUser == null) {
          state = AsyncValue.data(_auth.currentUser);
          return;
        }

        final googleAuth = await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        await _auth.signInWithCredential(credential);
      }

      final user = _auth.currentUser;

      if (user != null) {
        final userDoc = await _db.collection('users').doc(user.uid).get();

        if (!userDoc.exists) {
          await _db.collection('users').doc(user.uid).set({
            'id': user.uid,
            'name': user.displayName ?? 'User',
            'email': user.email ?? '',
            'bio': 'New to Situationship! ✨',
            'age': 21,
            'location': 'Earth 🌍',
            'avatarUrl': user.photoURL,
            'interests': [],
            'isVerified': false,
            'isOnline': true,
            'photos': user.photoURL != null ? [user.photoURL] : [],
            'followers': [],
            'following': [],
            'likedBy': [],
            'matches': [],
            'postCount': 0,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      state = AsyncValue.data(user);
    } catch (e) {
      state = const AsyncValue.data(null);
      throw Exception('Google Sign-In failed: $e');
    }
  }

  // ── Apple Sign In ───────────────────────────────────────────────────────────

  Future<void> signInWithApple() async {
    state = const AsyncValue.loading();

    try {
      final appleProvider = AppleAuthProvider();
      if (kIsWeb) {
        await _auth.signInWithPopup(appleProvider);
      } else {
        // For mobile, you would need to use the sign_in_with_apple package
        // This is a simplified implementation
        await _auth.signInWithProvider(appleProvider);
      }

      final user = _auth.currentUser;

      if (user != null) {
        final userDoc = await _db.collection('users').doc(user.uid).get();

        if (!userDoc.exists) {
          await _db.collection('users').doc(user.uid).set({
            'id': user.uid,
            'name': user.displayName ?? 'User',
            'email': user.email ?? '',
            'bio': 'New to Situationship! ✨',
            'age': 21,
            'location': 'Earth 🌍',
            'avatarUrl': user.photoURL,
            'interests': [],
            'isVerified': false,
            'isOnline': true,
            'photos': user.photoURL != null ? [user.photoURL] : [],
            'followers': [],
            'following': [],
            'likedBy': [],
            'matches': [],
            'postCount': 0,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      state = AsyncValue.data(user);
    } catch (e) {
      state = const AsyncValue.data(null);
      // For now, show a more user-friendly message
      throw Exception('Apple Sign-In is not available. Please use email or Google sign-in.');
    }
  }

  // ── Sign Out ────────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _auth.signOut();
    state = const AsyncValue.data(null);
  }

  // ── Error Mapping ───────────────────────────────────────────────────────────

  Exception _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return Exception('No account found with that email.');
      case 'wrong-password':
        return Exception('Incorrect password.');
      case 'email-already-in-use':
        return Exception('Account already exists.');
      case 'weak-password':
        return Exception('Password too weak.');
      case 'invalid-email':
        return Exception('Invalid email.');
      case 'too-many-requests':
        return Exception('Too many attempts.');
      default:
        return Exception(e.message ?? 'Authentication failed.');
    }
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<User?>>((ref) {
  return AuthController();
});
