import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/user_model.dart';
import '../../../core/models/community_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../shared/widgets/image_with_fallback.dart';

class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  int _selectedCommunityTab = 0; // 0 = Explore All, 1 = My Communities

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(matchQueueProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);

    // Split users
    final nearbyUsers = users.take(10).toList();
    final communitiesAsync = ref.watch(communitiesProvider);
    final communities = communitiesAsync.valueOrNull ?? CommunityModel.defaults;

    final filteredCommunities = _selectedCommunityTab == 0
        ? communities
        : communities.where((c) => c.createdBy == currentUser.id).toList();

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.read(matchQueueProvider.notifier).reset();
          },
          color: AppTheme.primaryBlue,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                
                // Nearby Souls Section
                _buildSectionHeaderWithIcon(
                  icon: Icons.location_on,
                  iconColor: const Color(0xFFFF7A59), // Orange-ish
                  title: 'Nearby Souls',
                  titleColor: const Color(0xFF6B4EE6), // Purple
                ),
                _buildNearbyList(nearbyUsers),
                
                const SizedBox(height: 24),
                
                // Vibe Communities Section
                _buildSectionHeaderWithIcon(
                  icon: Icons.people_alt_rounded,
                  iconColor: const Color(0xFF2DD4BF), // Teal
                  title: 'Vibe Communities',
                  titleColor: const Color(0xFF6B4EE6), // Purple
                  trailing: GestureDetector(
                    onTap: () => context.push('/community/create'),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.accentPink, width: 1.5),
                      ),
                      child: const Icon(Icons.add, color: AppTheme.accentPink, size: 18),
                    ),
                  ),
                ),
                // Pill Tabs
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      _buildPillTab(
                        label: 'Explore All',
                        isSelected: _selectedCommunityTab == 0,
                        onTap: () => setState(() => _selectedCommunityTab = 0),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 12),
                      _buildPillTab(
                        label: 'My Communities',
                        isSelected: _selectedCommunityTab == 1,
                        onTap: () => setState(() => _selectedCommunityTab = 1),
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildCommunitiesGrid(filteredCommunities),
                
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                  'Find your perfect vibe today',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showFilters(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.12)
                      : Colors.black.withOpacity(0.07),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.tune_rounded, color: AppTheme.primaryBlue, size: 22),
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
    if (users.isEmpty) return const SizedBox(height: 240, child: Center(child: Text('No users nearby')));
    
    return SizedBox(
      height: 260,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: users.length,
        itemBuilder: (context, index) {
          return _NearbyCard(user: users[index]);
        },
      ),
    );
  }

  Widget _buildCommunitiesGrid(List<CommunityModel> communities) {
    if (communities.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85, // Adjust ratio as needed
      ),
      itemCount: communities.length,
      itemBuilder: (context, index) {
        final community = communities[index];
        return _CommunityCard(
          key: ValueKey(community.id),
          community: community,
        );
      },
    );
  }

  Widget _buildPillTab({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryBlue
              : (isDark ? AppTheme.darkCard : Colors.white),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryBlue
                : (isDark ? Colors.white10 : Colors.black12),
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black87),
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
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
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // Local state for slider positions
          double minAge = currentMinAge;
          double maxAge = currentMaxAge;
          double maxDistance = currentMaxDistance;

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
                    Text('${maxDistance.toInt()} miles', style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700)),
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
                          // Reset to defaults
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
      ),
    );
  }
}

class _NearbyCard extends StatelessWidget {
  final UserModel user;
  const _NearbyCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/profile/view/${user.id}'),
      child: Container(
        width: 180,
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
                        fontSize: 18,
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
                            '${(user.id.hashCode % 10) + 1}.${(user.id.hashCode % 9)} mi',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
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

class _CommunityCard extends ConsumerWidget {
  final CommunityModel community;
  const _CommunityCard({super.key, required this.community});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);
    final isJoined = currentUser.joinedCommunities.contains(community.id);
    
    return GestureDetector(
      onTap: () => context.push('/community/${community.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard.withOpacity(0.8) : Colors.white.withOpacity(0.88),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.18 : 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image Section
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: ImageWithFallback(
                    imageUrl: community.imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      community.tag,
                      style: const TextStyle(
                        color: Color(0xFF6B4EE6),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Info Section
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    community.name,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.people_alt_rounded,
                        size: 14,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '${community.memberAvatars.isEmpty ? 1 : community.memberAvatars.length} members',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black45,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: OutlinedButton(
                      onPressed: () => context.push('/community/${community.id}'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: isJoined ? (isDark ? AppTheme.darkSurface : Colors.grey[100]) : Colors.transparent,
                        side: BorderSide(
                          color: isJoined ? (isDark ? Colors.white38 : Colors.black26) : AppTheme.accentPink,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        isJoined ? 'Joined' : 'Enter',
                        style: TextStyle(
                          color: isJoined ? (isDark ? Colors.white54 : Colors.black54) : AppTheme.accentPink,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
