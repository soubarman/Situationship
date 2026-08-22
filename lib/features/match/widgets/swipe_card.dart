import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/utils/location_helper.dart';

class SwipeCard extends ConsumerWidget {
  final UserModel user;
  final bool isBackground;
  final double? deviceLat;
  final double? deviceLon;

  const SwipeCard({
    super.key,
    required this.user,
    required this.isBackground,
    this.deviceLat,
    this.deviceLon,
  });

  // Dynamic Theme Gradients & Accent Colors based on user ID
  static const List<List<Color>> _themeGradients = [
    // Theme 1: Electric Violet
    [Color(0xFF6D28D9), Color(0xFF7C3AED), Color(0xFF5B21B6)],
    // Theme 2: Acid Lime to Coral Sunset
    [Color(0xFFBEF264), Color(0xFFEAB308), Color(0xFFEA580C)],
    // Theme 3: Neon Magenta Violet
    [Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFF4C1D95)],
    // Theme 4: Electric Cyan Cobalt
    [Color(0xFF06B6D4), Color(0xFF2563EB), Color(0xFF1E3A8A)],
  ];

  static const List<Color> _accentColors = [
    Color(0xFFE0FE10), // Acid Lime/Yellow
    Color(0xFF0F172A), // Dark Navy
    Color(0xFFFACC15), // Golden Yellow
    Color(0xFFE0FE10), // Neon Lime
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final themeIndex = user.id.hashCode.abs() % _themeGradients.length;
    final gradientColors = _themeGradients[themeIndex];
    final accentColor = _accentColors[themeIndex];
    final isDarkThemeText = themeIndex == 1; // Theme 2 uses dark text for contrast

    final distance = LocationHelper.getDistanceKm(
      lat1: deviceLat,
      lon1: deviceLon,
      loc1: currentUser.location,
      loc2: user.location,
      id1: currentUser.id,
      id2: user.id,
    );

    final primaryTextColor = isDarkThemeText ? const Color(0xFF0F172A) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isBackground ? 0.08 : 0.25),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardH = constraints.maxHeight;
            final avatarSize = (cardH * 0.42).clamp(180.0, 260.0);

            return Stack(
              fit: StackFit.expand,
              children: [
                // Background tint layer for stack depth
                if (isBackground)
                  Container(
                    color: Colors.black.withValues(alpha: 0.35),
                  ),

                if (!isBackground)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Top Bar Header ────────────────────────────────
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'New Matches',
                                  style: GoogleFonts.syne(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: primaryTextColor,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                Text(
                                  'Nearby',
                                  style: GoogleFonts.playfairDisplay(
                                    fontSize: 26,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w600,
                                    color: accentColor,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            // Distance Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: primaryTextColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '📍 $distance km',
                                style: GoogleFonts.syne(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: primaryTextColor,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        // Subtitle Location & Age
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              user.location?.isNotEmpty == true
                                  ? user.location!
                                  : 'Nearby Soul',
                              style: GoogleFonts.syne(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: primaryTextColor.withValues(alpha: 0.8),
                              ),
                            ),
                            Text(
                              '${user.age} years',
                              style: GoogleFonts.syne(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: accentColor,
                              ),
                            ),
                          ],
                        ),

                        // ── Center Hero Circular Photo ────────────────────
                        Expanded(
                          child: Center(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer glow ring
                                Container(
                                  width: avatarSize + 12,
                                  height: avatarSize + 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: accentColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                // Main circular photo
                                Container(
                                  width: avatarSize,
                                  height: avatarSize,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                  ),
                                  child: ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: user.avatarUrl ??
                                          'https://i.pravatar.cc/400?u=${user.id}',
                                      fit: BoxFit.cover,
                                      memCacheWidth: 800,
                                      progressIndicatorBuilder: (context, url, progress) =>
                                          Container(
                                        color: accentColor.withValues(alpha: 0.2),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── Giant Serif Name & Details ────────────────────
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                user.name,
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  color: accentColor,
                                  letterSpacing: -0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 2),
                              if (user.interests.isNotEmpty)
                                Text(
                                  user.interests.take(3).join(' / '),
                                  style: GoogleFonts.playfairDisplay(
                                    fontSize: 15,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w500,
                                    color: primaryTextColor.withValues(alpha: 0.9),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              if (user.bio != null && user.bio!.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Text(
                                    user.bio!.toUpperCase(),
                                    style: GoogleFonts.syne(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: primaryTextColor.withValues(alpha: 0.75),
                                      letterSpacing: 0.5,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
