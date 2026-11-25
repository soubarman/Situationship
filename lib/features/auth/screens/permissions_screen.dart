import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/providers/shared_prefs_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';

class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  bool _isLoading = false;

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);

    // Request Location, Camera, and Microphone natively
    await [
      Permission.location,
      Permission.camera,
      Permission.microphone,
    ].request();

    // Mark as requested in SharedPreferences so we don't ask again
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('permissionsRequested', true);

    if (!mounted) return;
    
    // Navigate to feed
    context.go('/feed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.obsidianBase,
      body: Stack(
        children: [
          // Ambient background glow
          Center(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primaryPink.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  // Icon Cluster with micro-border cards
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildIconBox(Icons.location_on_rounded, const Color(0xFFFF5277)),
                      const SizedBox(width: 14),
                      _buildIconBox(Icons.camera_alt_rounded, const Color(0xFFF9A03F)),
                      const SizedBox(width: 14),
                      _buildIconBox(Icons.mic_rounded, const Color(0xFF00E5FF)),
                    ],
                  ),
                  const SizedBox(height: 40),
                  
                  // Text Content
                  Text(
                    'Let\'s get you set up.',
                    textAlign: TextAlign.center,
                    style: DesignTokens.displayHero(color: Colors.white).copyWith(fontSize: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Situationship uses location for nearby matches, and camera and microphone to post real-time Takes and voice notes.',
                    textAlign: TextAlign.center,
                    style: DesignTokens.bodyLarge(color: DesignTokens.textSecondary),
                  ),
                  const Spacer(),

                  // Grant Button
                  GestureDetector(
                    onTap: _isLoading
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            _requestPermissions();
                          },
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryPink.withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.2,
                                ),
                              )
                            : Text(
                                'Grant Access & Continue ✨',
                                style: DesignTokens.labelBold(color: Colors.white).copyWith(fontSize: 15),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () async {
                      final prefs = ref.read(sharedPreferencesProvider);
                      await prefs.setBool('permissionsRequested', true);
                      if (context.mounted) context.go('/feed');
                    },
                    child: Text(
                      'Maybe Later',
                      style: DesignTokens.bodyMedium(color: DesignTokens.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconBox(IconData icon, Color color) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: DesignTokens.obsidianCard,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }
}
