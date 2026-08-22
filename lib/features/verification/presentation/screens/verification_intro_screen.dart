// lib/features/verification/presentation/screens/verification_intro_screen.dart
//
// Step 1: Verification intro screen detailing instructions and showing attempts.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/verification_status_model.dart';
import '../providers/verification_provider.dart';
import '../widgets/s_badge_widget.dart';

class VerificationIntroScreen extends ConsumerWidget {
  const VerificationIntroScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(verificationStatusStreamProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Get Verified',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: statusAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFAB47BC)),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error: $e',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (status) {
          if (status.isApproved) {
            return _AlreadyVerified();
          }
          return _IntroContent(status: status);
        },
      ),
    );
  }
}

class _AlreadyVerified extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SBadgeWidget(size: 80),
          const SizedBox(height: 24),
          const Text(
            'You\'re Verified! ✨',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your S badge is visible on your profile.',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _IntroContent extends StatelessWidget {
  final VerificationStatusModel status;

  const _IntroContent({required this.status});

  String _formatTimestamp(String tsStr) {
    try {
      final dt = DateTime.parse(tsStr).toLocal();
      final month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month - 1];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$month ${dt.day}, $hour:$minute $ampm';
    } catch (e) {
      return tsStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canVerify = status.attemptsRemaining > 0;
    final attemptsUsed = status.attemptsUsed;
    final attemptsRemaining = status.attemptsRemaining;
    final lastStatus = status.status;
    final lastReason = status.reason;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFFF6B9D).withOpacity(0.15),
                  const Color(0xFF7C4DFF).withOpacity(0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFFAB47BC).withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                const SBadgeWidget(size: 64, showTooltip: false),
                const SizedBox(height: 16),
                const Text(
                  'Earn Your S Badge',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Show the community you\'re a real person. '
                  'Record a short video challenge and our AI will verify you instantly.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Last attempt status/reason banner
          if (lastStatus == 'rejected' && lastReason != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFFF5252), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Previous attempt rejected',
                          style: TextStyle(
                            color: Color(0xFFFF5252),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lastReason,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (lastStatus == 'manual_review') ...[
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_empty, color: Color(0xFFFF9800), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Under review — our team is checking your verification. This may take up to 24 hours.',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Steps list
          const Text(
            'How It Works',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const _Step(
            number: '1',
            title: 'Get a Challenge',
            description: 'You\'ll receive a random 6-digit code, facial action, and head movement.',
          ),
          const _Step(
            number: '2',
            title: 'Record Your Video',
            description: 'Record yourself saying the code and doing the actions. Max 15 seconds.',
          ),
          const _Step(
            number: '3',
            title: 'AI Verifies You',
            description: 'Our private AI checks that you\'re a real person matching your profile photo.',
          ),
          const _Step(
            number: '4',
            title: 'Get Your S Badge',
            description: 'Instantly verified — your S badge appears on your profile!',
          ),

          const SizedBox(height: 24),

          // Tips card
          const Text(
            '✅ Tips for Success',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...[
            'Use good lighting — avoid dark rooms',
            'Your full face must be visible',
            'Use the same face as your profile photo',
            'Speak clearly when saying the code',
            'Hold your phone steady',
          ].map((tip) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('  •  ', style: TextStyle(color: Color(0xFF4CAF50))),
                    Expanded(
                      child: Text(
                        tip,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              )),

          const SizedBox(height: 24),

          // Attempt history list
          if (status.attemptsList.isNotEmpty) ...[
            const Text(
              'Attempt History',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...status.attemptsList.map((attempt) {
              Color statusColor;
              IconData statusIcon;
              switch (attempt.status) {
                case 'approved':
                  statusColor = const Color(0xFF4CAF50);
                  statusIcon = Icons.check_circle_outline;
                  break;
                case 'rejected':
                  statusColor = const Color(0xFFFF5252);
                  statusIcon = Icons.error_outline;
                  break;
                case 'manual_review':
                  statusColor = const Color(0xFFFF9800);
                  statusIcon = Icons.hourglass_empty;
                  break;
                default:
                  statusColor = const Color(0xFF2196F3);
                  statusIcon = Icons.pending_actions;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Attempt #${attempt.attemptNumber}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: statusColor.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, color: statusColor, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                attempt.status.toUpperCase().replaceAll('_', ' '),
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatTimestamp(attempt.timestamp),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12,
                      ),
                    ),
                    if (attempt.reason.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.02),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          attempt.reason,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
          ],

          // Attempts counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.refresh,
                  color: Colors.white.withOpacity(0.5),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  'Attempts used: $attemptsUsed / 5  ($attemptsRemaining remaining)',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // CTA Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: canVerify
                  ? () => context.push('/verification/record')
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                disabledBackgroundColor: Colors.white.withOpacity(0.05),
              ),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: canVerify
                      ? const LinearGradient(
                          colors: [Color(0xFFFF6B9D), Color(0xFFAB47BC), Color(0xFF7C4DFF)],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  alignment: Alignment.center,
                  child: Text(
                    canVerify
                        ? (attemptsUsed == 0 ? 'Start Verification' : 'Try Again')
                        : 'Maximum Attempts Reached',
                    style: TextStyle(
                      color: canVerify ? Colors.white : Colors.white.withOpacity(0.3),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String title;
  final String description;

  const _Step({
    required this.number,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFFF6B9D), Color(0xFFAB47BC)],
              ),
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
