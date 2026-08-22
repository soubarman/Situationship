// lib/features/verification/presentation/providers/verification_provider.dart
//
// Riverpod providers for the verification feature.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../../../../core/providers/firestore_provider.dart';
import '../../data/models/challenge_model.dart';
import '../../data/models/verification_status_model.dart';

// Replace with your Firebase Cloud Function HTTP URL after deploying.
// Look for the URL printed by 'firebase deploy --only functions' (e.g. https://api-xxxx-uc.a.run.app)
const _kApiBase = 'https://us-central1-situation-ship.cloudfunctions.net/api';

// ─── Helper: get Firebase ID token ────────────────────────────────────────────
Future<String> _getIdToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not authenticated');
  return (await user.getIdToken()) ?? '';
}

// ─── Verification Status Stream ───────────────────────────────────────────────

final verificationStatusStreamProvider =
    StreamProvider.autoDispose<VerificationStatusModel>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return Stream.value(VerificationStatusModel.notStarted());
  }

  final db = firestoreProvider;
  return db
      .collection('verifications')
      .doc(user.uid)
      .snapshots()
      .map((snap) {
    if (!snap.exists) return VerificationStatusModel.notStarted();
    return VerificationStatusModel.fromMap(snap.data()!);
  });
});

// ─── Challenge Notifier ───────────────────────────────────────────────────────

class ChallengeNotifier extends AsyncNotifier<ChallengeModel?> {
  @override
  FutureOr<ChallengeModel?> build() => null;

  Future<void> fetchChallenge() async {
    state = const AsyncValue.loading();
    try {
      final token = await _getIdToken();
      final response = await http.post(
        Uri.parse('$_kApiBase/challenge'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        state = AsyncValue.data(ChallengeModel.fromJson(data));
      } else if (response.statusCode == 429) {
        final body = jsonDecode(response.body);
        throw Exception(body['detail'] ?? 'Too many attempts. Please wait.');
      } else {
        throw Exception('Failed to get challenge: ${response.statusCode}');
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final challengeProvider =
    AsyncNotifierProvider<ChallengeNotifier, ChallengeModel?>(
  ChallengeNotifier.new,
);

// ─── Submission Notifier ──────────────────────────────────────────────────────

enum SubmissionStep {
  idle,
  uploading,
  processing,
  completed,
  failed,
}

class SubmissionState {
  final SubmissionStep step;
  final double uploadProgress;
  final String? jobId;
  final String? decision;
  final String? message;
  final String? error;

  const SubmissionState({
    this.step = SubmissionStep.idle,
    this.uploadProgress = 0,
    this.jobId,
    this.decision,
    this.message,
    this.error,
  });

  SubmissionState copyWith({
    SubmissionStep? step,
    double? uploadProgress,
    String? jobId,
    String? decision,
    String? message,
    String? error,
  }) {
    return SubmissionState(
      step: step ?? this.step,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      jobId: jobId ?? this.jobId,
      decision: decision ?? this.decision,
      message: message ?? this.message,
      error: error ?? this.error,
    );
  }
}

class VerificationSubmissionNotifier extends Notifier<SubmissionState> {
  @override
  SubmissionState build() => const SubmissionState();

  Future<void> submitVideo({
    required Uint8List videoBytes,
    required ChallengeModel challenge,
  }) async {
    state = const SubmissionState(step: SubmissionStep.uploading, uploadProgress: 0);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      // ── Step 1: Upload video to Firebase Storage ──────────────────
      final storagePath = 'verifications/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.webm';
      final storageRef = FirebaseStorage.instance.ref(storagePath);

      final uploadTask = storageRef.putData(
        videoBytes,
        SettableMetadata(contentType: 'video/webm'),
      );

      // Track upload progress
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        state = state.copyWith(uploadProgress: progress);
      });

      await uploadTask;

      // Get a short-lived download URL for the worker
      final downloadUrl = await storageRef.getDownloadURL();

      state = state.copyWith(
        step: SubmissionStep.processing,
        uploadProgress: 1.0,
      );

      // ── Step 2: Submit to verification API ──────────────────────────
      final token = await _getIdToken();
      final response = await http.post(
        Uri.parse('$_kApiBase/verify'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'challengeId': challenge.challengeId,
          'videoStoragePath': storagePath,
          'videoDownloadUrl': downloadUrl,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 202) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final jobId = data['jobId'] as String;
        state = state.copyWith(
          jobId: jobId,
          decision: data['decision'] as String?,
          message: data['message'] as String?,
          step: data['status'] == 'completed' ? SubmissionStep.completed : SubmissionStep.processing,
        );

        if (data['status'] != 'completed') {
          // ── Step 3: Poll for result ────────────────────────────────────
          await _pollForResult(jobId, token);
        }
      } else if (response.statusCode == 429) {
        final body = jsonDecode(response.body);
        throw Exception(body['detail'] ?? 'Maximum attempts reached.');
      } else {
        throw Exception('Submission failed: ${response.statusCode}');
      }
    } catch (e) {
      state = state.copyWith(
        step: SubmissionStep.failed,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _pollForResult(String jobId, String token) async {
    const maxAttempts = 40;  // Poll for up to ~2 minutes
    const interval = Duration(seconds: 3);

    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(interval);

      try {
        final response = await http.get(
          Uri.parse('$_kApiBase/verify/status/$jobId'),
          headers: {'Authorization': 'Bearer $token'},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final status = data['status'] as String;

          if (status == 'completed') {
            state = state.copyWith(
              step: SubmissionStep.completed,
              decision: data['decision'] as String?,
              message: data['message'] as String?,
            );
            return;
          } else if (status == 'failed') {
            throw Exception(data['message'] ?? 'Processing failed');
          }
          // Still processing — continue polling
        }
      } catch (e) {
        if (i == maxAttempts - 1) {
          state = state.copyWith(
            step: SubmissionStep.failed,
            error: 'Timeout waiting for verification result. Please try again.',
          );
          return;
        }
      }
    }

    state = state.copyWith(
      step: SubmissionStep.failed,
      error: 'Verification is taking longer than expected. Check back later.',
    );
  }

  void reset() {
    state = const SubmissionState();
  }
}

final verificationSubmissionProvider =
    NotifierProvider<VerificationSubmissionNotifier, SubmissionState>(
  VerificationSubmissionNotifier.new,
);
