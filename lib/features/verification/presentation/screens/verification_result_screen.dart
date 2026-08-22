// lib/features/verification/presentation/screens/verification_result_screen.dart
//
// Step 3: Shows verification processing state and final result.
// Auto-updates from Firestore real-time listener.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/verification_provider.dart';
import '../widgets/s_badge_widget.dart';

class VerificationResultScreen extends ConsumerWidget {
  const VerificationResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submission = ref.watch(verificationSubmissionProvider);
    final firestoreStatus = ref.watch(verificationStatusStreamProvider);

    // Use Firestore as the source of truth once processing completes
    final isFirestoreApproved = firestoreStatus.valueOrNull?.isApproved ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: _buildBody(context, ref, submission, isFirestoreApproved),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    SubmissionState submission,
    bool isFirestoreApproved,
  ) {
    if (submission.step == SubmissionStep.uploading) {
      return _ProgressView(
        title: 'Uploading Video',
        subtitle: 'Securely uploading your verification video…',
        progress: submission.uploadProgress,
        showProgress: true,
      );
    }

    if (submission.step == SubmissionStep.processing) {
      return const _ProgressView(
        title: 'AI is Verifying',
        subtitle: 'Our private AI is analyzing your face and liveness…\nThis usually takes 20–60 seconds.',
        showProgress: false,
        isAnimating: true,
      );
    }

    if (submission.step == SubmissionStep.failed) {
      return _FailedView(
        error: submission.error ?? 'Unknown error occurred.',
        onRetry: () {
          ref.read(verificationSubmissionProvider.notifier).reset();
          context.pop();
        },
      );
    }

    if (submission.step == SubmissionStep.completed || isFirestoreApproved) {
      final decision = submission.decision ??
          (isFirestoreApproved ? 'approved' : 'manual_review');

      switch (decision) {
        case 'approved':
          return _ApprovedView(onDone: () {
            ref.read(verificationSubmissionProvider.notifier).reset();
            context.go('/');
          });
        case 'manual_review':
          return _ManualReviewView(onDone: () {
            ref.read(verificationSubmissionProvider.notifier).reset();
            context.go('/');
          });
        case 'rejected':
          return _RejectedView(
            reason: submission.message,
            onRetry: () {
              ref.read(verificationSubmissionProvider.notifier).reset();
              context.go('/verification');
            },
          );
        default:
          return _ManualReviewView(onDone: () => context.go('/'));
      }
    }

    // Default: processing
    return const _ProgressView(
      title: 'Processing',
      subtitle: 'Please wait…',
      showProgress: false,
      isAnimating: true,
    );
  }
}

// ── Progress / Loading View ───────────────────────────────────────────────────

class _ProgressView extends StatefulWidget {
  final String title;
  final String subtitle;
  final double? progress;
  final bool showProgress;
  final bool isAnimating;

  const _ProgressView({
    required this.title,
    required this.subtitle,
    this.progress,
    this.showProgress = false,
    this.isAnimating = false,
  });

  @override
  State<_ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<_ProgressView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated spinner
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer ring
                    Transform.rotate(
                      angle: _controller.value * 2 * math.pi,
                      child: CustomPaint(
                        size: const Size(100, 100),
                        painter: _RingPainter(
                          color: const Color(0xFFAB47BC),
                          strokeWidth: 3,
                          dashLength: 0.6,
                        ),
                      ),
                    ),
                    // Inner ring (opposite direction)
                    Transform.rotate(
                      angle: -_controller.value * 2 * math.pi * 0.7,
                      child: CustomPaint(
                        size: const Size(72, 72),
                        painter: _RingPainter(
                          color: const Color(0xFFFF6B9D),
                          strokeWidth: 2,
                          dashLength: 0.3,
                        ),
                      ),
                    ),
                    const SBadgeWidget(size: 40, showTooltip: false),
                  ],
                );
              },
            ),

            const SizedBox(height: 40),

            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              widget.subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 15,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            if (widget.showProgress && widget.progress != null) ...[
              const SizedBox(height: 32),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: widget.progress,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFAB47BC)),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${((widget.progress ?? 0) * 100).toInt()}%',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;

  const _RingPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawArc(rect, 0, math.pi * 2 * dashLength, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Approved View ─────────────────────────────────────────────────────────────

class _ApprovedView extends StatefulWidget {
  final VoidCallback onDone;
  const _ApprovedView({required this.onDone});

  @override
  State<_ApprovedView> createState() => _ApprovedViewState();
}

class _ApprovedViewState extends State<_ApprovedView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _scaleAnim = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scaleAnim,
              child: const SBadgeWidget(size: 100, showTooltip: false),
            ),
            const SizedBox(height: 32),
            const Text(
              '🎉 You\'re Verified!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Your S badge is now visible on your profile, posts, and across the app.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: widget.onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFAB47BC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Go to Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Manual Review View ────────────────────────────────────────────────────────

class _ManualReviewView extends StatelessWidget {
  final VoidCallback onDone;
  const _ManualReviewView({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF9800).withOpacity(0.1),
                border: Border.all(
                  color: const Color(0xFFFF9800).withOpacity(0.4),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.hourglass_top_rounded,
                color: Color(0xFFFF9800),
                size: 52,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Under Manual Review',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Our team is reviewing your verification. '
              'This usually takes less than 24 hours. '
              'We\'ll notify you once it\'s done.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 15,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            OutlinedButton(
              onPressed: onDone,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white54),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('OK, Got It'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Rejected View ─────────────────────────────────────────────────────────────

class _RejectedView extends StatelessWidget {
  final String? reason;
  final VoidCallback onRetry;
  const _RejectedView({this.reason, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF5252).withOpacity(0.1),
                border: Border.all(
                  color: const Color(0xFFFF5252).withOpacity(0.4),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Color(0xFFFF5252),
                size: 52,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Verification Failed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (reason != null)
              Text(
                reason!,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 15,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 8),
            Text(
              'Please try again in a well-lit area with your face clearly visible.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 13,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFAB47BC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Try Again',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Failed View (submission error) ───────────────────────────────────────────

class _FailedView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _FailedView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF5252), size: 64),
            const SizedBox(height: 20),
            const Text(
              'Submission Error',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFAB47BC)),
              child: const Text('Go Back', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
