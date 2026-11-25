import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/providers/app_state_provider.dart';

class SuspendedScreen extends ConsumerWidget {
  const SuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userDataStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final suspensionReason = userAsync.asData?.value?.suspensionReason;
    final suspendedUntil = userAsync.asData?.value?.suspendedUntil;

    return Scaffold(
      backgroundColor: DesignTokens.obsidianBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DesignTokens.error.withValues(alpha: 0.14),
                  border: Border.all(
                    color: DesignTokens.error.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: DesignTokens.error.withValues(alpha: 0.25),
                      blurRadius: 28,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.shield_outlined, color: DesignTokens.error, size: 40),
              ),
              const SizedBox(height: 28),

              // Title
              Text(
                'Account Suspended',
                textAlign: TextAlign.center,
                style: DesignTokens.headingLarge(color: Colors.white).copyWith(fontSize: 26),
              ),
              const SizedBox(height: 10),

              // Subtitle
              Text(
                'Your account has been restricted by the Situationship team due to a violation of our community safety guidelines.',
                textAlign: TextAlign.center,
                style: DesignTokens.bodyLarge(color: DesignTokens.textSecondary),
              ),

              // Reason card
              if (suspensionReason != null && suspensionReason.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: DesignTokens.error.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                    border: Border.all(color: DesignTokens.error.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, color: DesignTokens.error, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          suspensionReason,
                          style: DesignTokens.bodyMedium(color: DesignTokens.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Duration
              if (suspendedUntil != null) ...[
                const SizedBox(height: 14),
                Text(
                  'Suspension ends: ${_formatDate(suspendedUntil)}',
                  style: DesignTokens.bodyMedium(color: DesignTokens.textMuted),
                ),
              ] else ...[
                const SizedBox(height: 14),
                Text(
                  'This suspension is permanent.',
                  style: DesignTokens.bodyMedium(color: DesignTokens.textMuted),
                ),
              ],

              const SizedBox(height: 36),

              // Contact support
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: DesignTokens.obsidianCard,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mail_outline_rounded, color: DesignTokens.textSecondary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'If you believe this is a mistake, contact us at\nsupport@situationship.app',
                        style: DesignTokens.bodyMedium(color: DesignTokens.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Sign out button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusFull)),
                  ),
                  child: const Text('Sign Out'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
