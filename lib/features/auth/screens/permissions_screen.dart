import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/providers/shared_prefs_provider.dart';

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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Icon Cluster
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildIconBox(Icons.location_on_rounded, const Color(0xFFE84855)),
                  const SizedBox(width: 16),
                  _buildIconBox(Icons.camera_alt_rounded, const Color(0xFFF9A03F)),
                  const SizedBox(width: 16),
                  _buildIconBox(Icons.mic_rounded, const Color(0xFF00E5FF)),
                ],
              ),
              const SizedBox(height: 48),
              
              // Text Content
              const Text(
                'Let\'s get you set up.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Situationship needs access to your location for Spotlight matches, and your camera and microphone to post Takes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const Spacer(),

              // Grant Button
              GestureDetector(
                onTap: _isLoading ? null : _requestPermissions,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE84855), Color(0xFFF9A03F)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE84855).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Enable Permissions',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Skip button
              TextButton(
                onPressed: () async {
                  final prefs = ref.read(sharedPreferencesProvider);
                  await prefs.setBool('permissionsRequested', true);
                  if (mounted) context.go('/feed');
                },
                child: const Text(
                  'Maybe later',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconBox(IconData icon, Color color) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Icon(icon, color: color, size: 32),
    );
  }
}
