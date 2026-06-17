import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/models/user_model.dart';
import '../../../core/models/community_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../shared/widgets/image_with_fallback.dart';
import '../../../shared/widgets/background_orbs.dart';
import '../../../core/utils/location_helper.dart';
import '../widgets/swipe_deck.dart';
import 'liked_history_screen.dart';

class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  double? _deviceLat;
  double? _deviceLon;
  bool _isLocating = false;
  final Set<String> _localSkippedIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchDeviceLocation();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchDeviceLocation() async {
    if (!mounted) return;
    setState(() => _isLocating = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isLocating = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _isLocating = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isLocating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 5),
      );

      if (mounted) {
        setState(() {
          _deviceLat = position.latitude;
          _deviceLon = position.longitude;
          _isLocating = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to get location: $e');
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(matchQueueProvider);
    final currentUser = ref.watch(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final minAge = ref.watch(filterMinAgeProvider);
    final maxAge = ref.watch(filterMaxAgeProvider);
    final maxDistance = ref.watch(filterMaxDistanceProvider);
    final matchIrrespective = ref.watch(filterMatchIrrespectiveProvider);

    // Dynamic real-time filter based on age and geographical distance in kilometers
    final filteredUsers = users.where((user) {
      // Don't show users the current user already follows (already liked/followed)
      if (currentUser.following.contains(user.id)) return false;

      // Don't show users already skipped in this session
      if (_localSkippedIds.contains(user.id)) return false;

      // Age check
      if (user.age < minAge || user.age > maxAge) return false;

      // Real distance check using LocationHelper in kilometers (with real GPS support)
      final distance = LocationHelper.getDistanceKm(
        lat1: _deviceLat,
        lon1: _deviceLon,
        loc1: currentUser.location,
        loc2: user.location,
        id1: currentUser.id,
        id2: user.id,
      );

      if (matchIrrespective) return true;
      return distance <= maxDistance;
    }).toList();

    // Split users
    final nearbyUsers = filteredUsers.take(10).toList();

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          const BackgroundOrbs(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────
                _buildHeader(),

                // ── Glassmorphic Tab Bar ─────────────────────────────────
                _buildGlassTabBar(isDark),

                // ── Tab Content ──────────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      // ── Tab 0: Discover ──────────────────────────────
                      RefreshIndicator(
                        onRefresh: () async {
                          ref.read(matchQueueProvider.notifier).reset();
                          await _fetchDeviceLocation();
                        },
                        color: AppTheme.primaryBlue,
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Location Alert Banner if unset and no GPS active
                              if ((currentUser.location == null ||
                                      currentUser.location!.trim().isEmpty) &&
                                  _deviceLat == null)
                                _buildLocationAlertBanner(),

                              // Swipe to Match Section
                              _buildSectionHeaderWithIcon(
                                icon: Icons.explore_rounded,
                                iconColor: const Color(0xFF6B4EE6),
                                title: 'Swipe to Match ✨',
                                titleColor: const Color(0xFF6B4EE6),
                                trailing: _buildMatchModeDropdown(isDark),
                              ),
                              SwipeDeck(
                                users: filteredUsers,
                                deviceLat: _deviceLat,
                                deviceLon: _deviceLon,
                                onSwipeLeft: (user) {
                                  setState(() {
                                    _localSkippedIds.add(user.id);
                                  });
                                },
                                onSwipeRight: (user) {
                                  final currentUser =
                                      ref.read(currentUserProvider);
                                  if (currentUser.id.isNotEmpty &&
                                      !currentUser.following
                                          .contains(user.id)) {
                                    ref
                                        .read(socialProvider.notifier)
                                        .toggleFollow(
                                          currentUserId: currentUser.id,
                                          targetUserId: user.id,
                                          isCurrentlyFollowing: false,
                                        )
                                        .catchError((e) {
                                      debugPrint(
                                          'Failed to auto-follow user: $e');
                                    });
                                  }
                                },
                              ),

                              const SizedBox(height: 24),

                              // Nearby Souls Section
                              _buildSectionHeaderWithIcon(
                                icon: Icons.location_on,
                                iconColor: const Color(0xFFFF7A59),
                                title: 'Nearby Souls',
                                titleColor: const Color(0xFF6B4EE6),
                              ),
                              _buildNearbyList(nearbyUsers),
                              SizedBox(height: MediaQuery.of(context).padding.bottom + 120),
                            ],
                          ),
                        ),
                      ),

                      // ── Tab 1: Liked History ──────────────────────────
                      const LikedHistoryScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassTabBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.white.withOpacity(0.75),
                width: 1.0,
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryBlue, Color(0xFF6B4EE6)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              labelColor: Colors.white,
              unselectedLabelColor:
                  isDark ? Colors.white60 : Colors.black54,
              labelStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.explore_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Discover'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Liked'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationAlertBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark 
              ? [AppTheme.primaryBlue.withOpacity(0.15), const Color(0xFF6B4EE6).withOpacity(0.15)]
              : [AppTheme.primaryBlue.withOpacity(0.08), const Color(0xFF6B4EE6).withOpacity(0.08)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryBlue.withOpacity(0.3),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_off_rounded, color: AppTheme.primaryBlue, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unlock Exact Distance 📍',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark ? Colors.white : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Set your city in profile to see precise distance to other souls.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => context.push('/profile/edit'),
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppTheme.primaryBlue),
          ),
        ],
      ),
    );
  }


  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
                  child: const Text(
                    'Discover 💫',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLocating ? 'Determining your GPS... 📍' : 'Find your perfect vibe today',
                  style: TextStyle(
                     fontSize: 14,
                     color: isDark ? Colors.white60 : AppTheme.textSecondary,
                     fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.primaryGradient,
                    border: Border.all(
                      color: isDark ? Colors.white24 : Colors.white,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: currentUser.avatarUrl != null
                        ? Image.network(currentUser.avatarUrl!, fit: BoxFit.cover)
                        : const Center(child: Text('😎', style: TextStyle(fontSize: 20))),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeaderWithIcon({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Color titleColor,
    Widget? trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : AppTheme.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildNearbyList(List<UserModel> users) {
    if (users.isEmpty) return const SizedBox(height: 140, child: Center(child: Text('No users nearby')));
    
    return SizedBox(
      height: 160,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: users.length,
        itemBuilder: (context, index) {
          return _NearbyCard(
            user: users[index],
            deviceLat: _deviceLat,
            deviceLon: _deviceLon,
          );
        },
      ),
    );
  }

  Widget _buildMatchModeDropdown(bool isDark) {
    final matchIrrespective = ref.watch(filterMatchIrrespectiveProvider);
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 6),
      height: 36, // Compact height for perfect vertical centering in the row
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.07),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<bool>(
          value: matchIrrespective,
          isDense: true, // Extremely compact layout to avoid text squishing
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryBlue, size: 18),
          dropdownColor: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppTheme.textPrimary,
          ),
          onChanged: (bool? newValue) {
            if (newValue != null) {
              ref.read(filterMatchIrrespectiveProvider.notifier).state = newValue;
            }
          },
          items: [
            DropdownMenuItem<bool>(
              value: false,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_rounded, size: 14, color: AppTheme.primaryBlue),
                  const SizedBox(width: 6),
                  Text(
                    'Nearby',
                    style: TextStyle(
                      color: isDark ? Colors.white : AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            DropdownMenuItem<bool>(
              value: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.public_rounded, size: 14, color: AppTheme.primaryGreen),
                  const SizedBox(width: 6),
                  Text(
                    'Global',
                    style: TextStyle(
                      color: isDark ? Colors.white : AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilters() {
    // Read current filter values from providers
    final currentMinAge = ref.read(filterMinAgeProvider);
    final currentMaxAge = ref.read(filterMaxAgeProvider);
    final currentMaxDistance = ref.read(filterMaxDistanceProvider);

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        // Declare state variables here outside the StatefulBuilder's builder callback 
        // to ensure they survive modal dialog internal redraw/setModalState triggers!
        double minAge = currentMinAge;
        double maxAge = currentMaxAge;
        double maxDistance = currentMaxDistance;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 24),
                  const Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 24),
                  // Age Range
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Age Range', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text('${minAge.toInt()} - ${maxAge.toInt()}', style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  RangeSlider(
                    values: RangeValues(minAge, maxAge),
                    min: 18,
                    max: 65,
                    divisions: 47,
                    activeColor: AppTheme.primaryBlue,
                    inactiveColor: AppTheme.primaryBlue.withOpacity(0.2),
                    onChanged: (values) {
                      setModalState(() {
                        minAge = values.start;
                        maxAge = values.end;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // Distance
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Max Distance', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text('${maxDistance.toInt()} km', style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Slider(
                    value: maxDistance,
                    min: 5,
                    max: 100,
                    divisions: 19,
                    activeColor: AppTheme.primaryGreen,
                    inactiveColor: AppTheme.primaryGreen.withOpacity(0.2),
                    onChanged: (value) {
                      setModalState(() {
                        maxDistance = value;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            ref.read(filterMinAgeProvider.notifier).state = 18;
                            ref.read(filterMaxAgeProvider.notifier).state = 35;
                            ref.read(filterMaxDistanceProvider.notifier).state = 50;
                            ref.read(matchQueueProvider.notifier).applyFilters(
                              maxDistance: 50,
                              minAge: 18,
                              maxAge: 35,
                            );
                            context.pop();
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            // Save filter state to providers
                            ref.read(filterMinAgeProvider.notifier).state = minAge;
                            ref.read(filterMaxAgeProvider.notifier).state = maxAge;
                            ref.read(filterMaxDistanceProvider.notifier).state = maxDistance;
                            ref.read(matchQueueProvider.notifier).applyFilters(
                              maxDistance: maxDistance,
                              minAge: minAge,
                              maxAge: maxAge,
                            );
                            context.pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Apply Filters', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 16 : 0),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _NearbyCard extends ConsumerWidget {
  final UserModel user;
  final double? deviceLat;
  final double? deviceLon;

  const _NearbyCard({
    required this.user,
    this.deviceLat,
    this.deviceLon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final distance = LocationHelper.getDistanceKm(
      lat1: deviceLat,
      lon1: deviceLon,
      loc1: currentUser.location,
      loc2: user.location,
      id1: currentUser.id,
      id2: user.id,
    );

    return GestureDetector(
      onTap: () => context.push('/profile/view/${user.id}'),
      child: Container(
        width: 110,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: AppTheme.primaryBlue.withOpacity(0.08),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                user.avatarUrl ?? 'https://i.pravatar.cc/400?u=${user.id}',
                fit: BoxFit.cover,
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.06),
                      Colors.black.withOpacity(0.82),
                    ],
                    stops: const [0.35, 0.65, 1.0],
                  ),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 14,
                right: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${user.name}, ${user.age}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.25), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on, color: Colors.white, size: 12),
                          const SizedBox(width: 3),
                          Text(
                            '$distance km',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


