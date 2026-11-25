import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/presence_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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

  static Map<String, dynamic> buildInitialUserProfileMap({
    required String uid,
    required String name,
    required String bio,
    required int age,
    required String location,
    String gender = 'other',
    String? avatarUrl,
    List<String> interests = const [],
    List<String> photos = const [],
    String? relationshipIntent,
    List<String> interestedIn = const [],
  }) {
    return {
      'id': uid,
      'name': name,
      'bio': bio,
      'age': age,
      'location': location,
      'gender': gender,
      'isPhonePublic': false,
      'phoneVisibilityVersion': 1,
      'avatarUrl': avatarUrl,
      'interests': interests,
      'photos': photos,
      'followers': <String>[],
      'following': <String>[],
      'likedBy': <String>[],
      'superLikedBy': <String>[],
      'matches': <String>[],
      'dislikedUsers': <String>[],
      'postCount': 0,
      'isOnline': true,
      'isVerified': false,
      'isSubscribed': false,
      'isSuspended': false,
      'coins': 0,
      'totalEarnedCoins': 0,
      'claimedMilestones': <String>[],
      'role': 'user',
      'unlockedUserPhones': <String>[],
      'unlockedVisitors': <String>[],
      'dailyLoginStreak': 0,
      'conversationRewardsToday': 0,
      'phoneUnlocksUsed': 0,
      'phoneUnlockQuota': 0,
      'subscriptionExpiry': null,
      if (relationshipIntent != null) 'relationshipIntent': relationshipIntent,
      if (interestedIn.isNotEmpty) 'interestedIn': interestedIn,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

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
    required String gender,
    required String phoneNumber,
    required List<String> interests,
    XFile? avatarFile,
    List<XFile>? photoFiles,
  }) async {
    state = const AsyncValue.loading();
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      final user = cred.user!;

      await user.updateDisplayName(name);

      final List<String> uploadedPhotoUrls = [];
      final filesToUpload = (photoFiles != null && photoFiles.isNotEmpty)
          ? photoFiles.take(4).toList()
          : (avatarFile != null ? [avatarFile] : <XFile>[]);

      for (int i = 0; i < filesToUpload.length; i++) {
        try {
          final f = filesToUpload[i];
          final storageRef = FirebaseStorage.instance
              .ref('avatars/${user.uid}_photo_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
          if (kIsWeb) {
            final bytes = await f.readAsBytes();
            await storageRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
          } else {
            await storageRef.putFile(File(f.path), SettableMetadata(contentType: 'image/jpeg'));
          }
          final url = await storageRef.getDownloadURL();
          uploadedPhotoUrls.add(url);
        } catch (e) {
          debugPrint('Storage upload failed for photo $i: $e');
        }
      }

      final String? photoUrl = uploadedPhotoUrls.isNotEmpty ? uploadedPhotoUrls.first : null;
      if (photoUrl != null) {
        try {
          await user.updatePhotoURL(photoUrl);
        } catch (_) {}
      }

      // 1. Create public profile document (PII excluded, strict security rules compliant)
      final publicProfile = buildInitialUserProfileMap(
        uid: user.uid,
        name: name,
        bio: bio,
        age: age,
        location: location,
        gender: gender,
        avatarUrl: photoUrl,
        interests: interests,
        photos: uploadedPhotoUrls,
      );
      await _db.collection('users').doc(user.uid).set(publicProfile);

      // 2. Create private profile document (owner-only PII)
      await _db.collection('users').doc(user.uid).collection('private').doc('profile').set({
        'email': email,
        'phoneNumber': phoneNumber,
        'createdAt': FieldValue.serverTimestamp(),
      });

      state = AsyncValue.data(user);
    } catch (e) {
      debugPrint('[AuthController] signUpWithEmail error: $e');
      state = AsyncValue.data(_auth.currentUser);
      if (e is FirebaseAuthException) {
        throw _mapFirebaseError(e);
      }
      throw Exception('Failed to create account: $e');
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
          final initialProfile = buildInitialUserProfileMap(
            uid: user.uid,
            name: user.displayName ?? 'User',
            bio: 'New to Situationship! ✨',
            age: 21,
            location: 'Earth 🌍',
            avatarUrl: user.photoURL,
            photos: user.photoURL != null ? [user.photoURL!] : [],
          );
          await _db.collection('users').doc(user.uid).set(initialProfile);
          await _db.collection('users').doc(user.uid).collection('private').doc('profile').set({
            'email': user.email ?? '',
            'phoneNumber': null,
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
          final initialProfile = buildInitialUserProfileMap(
            uid: user.uid,
            name: user.displayName ?? 'User',
            bio: 'New to Situationship! ✨',
            age: 21,
            location: 'Earth 🌍',
            avatarUrl: user.photoURL,
            photos: user.photoURL != null ? [user.photoURL!] : [],
          );
          await _db.collection('users').doc(user.uid).set(initialProfile);
          await _db.collection('users').doc(user.uid).collection('private').doc('profile').set({
            'email': user.email ?? '',
            'phoneNumber': null,
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

  // ── Delete Account ──────────────────────────────────────────────────────────

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user != null) {
      state = const AsyncValue.loading();
      try {
        await _db.collection('users').doc(user.uid).delete();
        await user.delete();
        state = const AsyncValue.data(null);
      } on FirebaseAuthException catch (e) {
        state = AsyncValue.data(user);
        throw _mapFirebaseError(e);
      } catch (e) {
        state = AsyncValue.data(user);
        throw Exception('Failed to delete account');
      }
    }
  }

  // ── Sign Out ────────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await PresenceService.instance.markOffline();
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
