import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/community_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../core/utils/location_helper.dart';
import '../../../shared/widgets/background_orbs.dart';

class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0; // 0 = Active, 1 = Connections, 2 = Communities

  // Active tab state
  int _selectedRangeKm = 3;
  bool _isLiveVisible = true;

  // Communities tab filter
  String _selectedCommunityCategory = 'All';

  // Search state
  bool _isSearching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || _tabController.index != _selectedTab) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _cycleRange() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedRangeKm == 3) {
        _selectedRangeKm = 5;
      } else if (_selectedRangeKm == 5) {
        _selectedRangeKm = 10;
      } else if (_selectedRangeKm == 10) {
        _selectedRangeKm = 25;
      } else {
        _selectedRangeKm = 3;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '⚡ Radar range set to $_selectedRangeKm km',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          duration: const Duration(milliseconds: 1400),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF7C3AED),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  Future<void> _toggleLive(UserModel currentUser) async {
    HapticFeedback.mediumImpact();
    final newStatus = !_isLiveVisible;
    setState(() => _isLiveVisible = newStatus);

    if (currentUser.id.isNotEmpty) {
      try {
        await firestoreProvider.collection('users').doc(currentUser.id).set({
          'isOnline': newStatus,
          'isLiveRadarEnabled': newStatus,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[LiveToggle] Error: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus
                ? '🛰️ Live Radar ON: You are visible to nearby souls'
                : '👻 Ghost Mode ON: You are hidden from live radar',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          duration: const Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
          backgroundColor: newStatus ? const Color(0xFF059669) : const Color(0xFF334155),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  void _openChatWithUser(UserModel targetUser, UserModel currentUser) {
    final chatId = 'chat_${currentUser.id}_${targetUser.id}';
    context.push('/chats/$chatId', extra: {
      'name': targetUser.name,
      'avatarUrl': targetUser.avatarUrl,
      'isOnline': targetUser.isOnline,
    });
  }

  void _showActiveUserModal(UserModel user, UserModel currentUser) {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final matchScore = 80 + (user.id.hashCode.abs() % 18);
    final vibeLabel = _vibeLabels[user.id.hashCode.abs() % _vibeLabels.length];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(sheetCtx).padding.bottom + 16,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141724) : Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Photo Card Header with close X
                  Stack(
                    children: [
                      Container(
                        height: 230,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2235),
                          image: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                              ? DecorationImage(
                                  image: CachedNetworkImageProvider(user.avatarUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: user.avatarUrl == null || user.avatarUrl!.isEmpty
                            ? Center(
                                child: Text(
                                  user.name.isNotEmpty ? user.name[0] : '?',
                                  style: const TextStyle(fontSize: 54, color: Colors.white70),
                                ),
                              )
                            : null,
                      ),
                      // Dark gradient overlay
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.15),
                                Colors.black.withOpacity(0.75),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Close button
                      Positioned(
                        top: 14,
                        right: 14,
                        child: GestureDetector(
                          onTap: () => Navigator.of(sheetCtx).pop(),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(0.55),
                              border: Border.all(color: Colors.white24, width: 1),
                            ),
                            child: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                      // Active indicator badge
                      Positioned(
                        left: 14,
                        bottom: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white12, width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Active 5m ago',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Info Section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${user.name}, ${user.age}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : Colors.black87,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$vibeLabel · $matchScore% match',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8B5CF6),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Buttons
                        Row(
                          children: [
                            // Tap in button
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(sheetCtx).pop();
                                  _openChatWithUser(user, currentUser);
                                },
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF4F75FF), Color(0xFF8B5CF6)],
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF4F75FF).withOpacity(0.35),
                                        blurRadius: 14,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Tap in',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Close button
                            Expanded(
                              child: GestureDetector(
                                onTap: () => Navigator.of(sheetCtx).pop(),
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF222638)
                                        : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withOpacity(0.1)
                                          : Colors.black.withOpacity(0.06),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Close',
                                      style: TextStyle(
                                        color: isDark ? Colors.white : Colors.black87,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);
    final allQueueUsers = ref.watch(matchQueueProvider);
    final unlikedIds = ref.watch(unlikedUserIdsProvider);

    // ── Filter out current user, disliked users, and session-unliked users ──
    final dislikedSet = currentUser.dislikedUsers.toSet();
    final validUsers = allQueueUsers.where((u) {
      if (u.id == currentUser.id) return false;
      if (dislikedSet.contains(u.id)) return false;
      if (unlikedIds.contains(u.id)) return false;
      return true;
    }).toList();

    // Fallback users if queue has few profiles
    final activeUsers = validUsers.isNotEmpty ? validUsers : _fallbackUsers;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090C15) : const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          const BackgroundOrbs(),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top App Bar: "People" + Search button
                    _buildTopBar(isDark),

                    // 3-Pill Tab Bar: Active | Connections | Communities
                    _buildSegmentedTabBar(isDark),

                    const SizedBox(height: 8),

                    // Tab Views
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _buildActiveTab(activeUsers, currentUser, isDark),
                          _buildConnectionsTab(activeUsers, currentUser, isDark),
                          _buildCommunitiesTab(currentUser, isDark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Top Header & Search ───────────────────────────────────────────────────

  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (!_isSearching)
            Text(
              'People',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            )
          else
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF191D2C) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Search people or vibe clubs...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF8B5CF6)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchCtrl.clear();
                  _searchQuery = '';
                }
              });
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
                  width: 1,
                ),
              ),
              child: Icon(
                _isSearching ? Icons.close_rounded : Icons.search_rounded,
                size: 19,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 3-Pill Segmented Tab Bar ──────────────────────────────────────────────

  Widget _buildSegmentedTabBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131722) : const Color(0xFFE2E8F0).withOpacity(0.6),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
          ),
        ),
        child: Row(
          children: [
            _buildTabButton(0, 'Active', isDark),
            const SizedBox(width: 4),
            _buildTabButton(1, 'Connections', isDark),
            const SizedBox(width: 4),
            _buildTabButton(2, 'Communities', isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label, bool isDark) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _tabController.animateTo(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF4F75FF), Color(0xFF8B5CF6)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF4F75FF).withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white.withOpacity(0.55) : const Color(0xFF64748B)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1: ACTIVE (Screenshots 1 & 2)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActiveTab(List<UserModel> users, UserModel currentUser, bool isDark) {
    // ── Filter by distance using LocationHelper ──
    final nearbyUsers = users.where((u) {
      final dist = LocationHelper.getDistanceKm(
        lat1: null,
        lon1: null,
        loc1: currentUser.location,
        loc2: u.location,
        id1: currentUser.id,
        id2: u.id,
      );
      return dist <= _selectedRangeKm;
    }).toList();

    // Use nearby users if found within radius; otherwise show available
    final displayUsers = nearbyUsers.isNotEmpty ? nearbyUsers : users;

    final featuredUser = displayUsers.isNotEmpty ? displayUsers[0] : _fallbackUsers[0];
    final otherUsers = displayUsers.length > 1
        ? displayUsers.sublist(1)
        : (users.length > 1 ? users.sublist(1) : _fallbackUsers.sublist(1));

    final countDisplay = nearbyUsers.isNotEmpty ? nearbyUsers.length : displayUsers.length;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Live Nearby Status Header ──────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withOpacity(0.6),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Live nearby',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              Text(
                '$countDisplay online · $_selectedRangeKm km',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            "Tap someone who's around right now",
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white.withOpacity(0.45) : const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 14),

          // ── Featured Active Profile Card ──────────────────────────────────
          _buildFeaturedActiveCard(featuredUser, currentUser, isDark),

          const SizedBox(height: 20),

          // ── ALSO AROUND section ───────────────────────────────────────────
          Text(
            'ALSO AROUND',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),

          // Horizontal list of avatars
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: otherUsers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final u = otherUsers[index];
                return _buildAlsoAroundAvatarItem(u, currentUser, isDark);
              },
            ),
          ),

          const SizedBox(height: 18),

          // ── Bottom Utility Cards (Live & Km range) ────────────────────────
          Row(
            children: [
              // Left: Live visibility card
              Expanded(
                child: GestureDetector(
                  onTap: () => _toggleLive(currentUser),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: _isLiveVisible
                          ? (isDark ? const Color(0xFF09281D) : const Color(0xFFECFDF5))
                          : (isDark ? const Color(0xFF141824) : Colors.white),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isLiveVisible
                            ? const Color(0xFF10B981).withOpacity(isDark ? 0.4 : 0.5)
                            : (isDark ? Colors.white12 : Colors.black12),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isLiveVisible
                              ? const Color(0xFF10B981).withOpacity(0.12)
                              : Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(isDark ? 0.25 : 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Text('🛰️', style: TextStyle(fontSize: 18)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isLiveVisible ? 'Live' : 'Hidden',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  color: _isLiveVisible
                                      ? (isDark ? const Color(0xFF34D399) : const Color(0xFF065F46))
                                      : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _isLiveVisible ? 'Visible nearby' : 'Ghost mode',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: _isLiveVisible
                                      ? (isDark ? Colors.white60 : const Color(0xFF047857))
                                      : (isDark ? Colors.white38 : Colors.black45),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Right: Km range selector card
              Expanded(
                child: GestureDetector(
                  onTap: _cycleRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF181432) : const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF7C3AED).withOpacity(isDark ? 0.4 : 0.3),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7C3AED).withOpacity(0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              '$_selectedRangeKm',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'km range',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                'Within ${_selectedRangeKm}km',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark ? Colors.white60 : const Color(0xFF6D28D9),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedActiveCard(UserModel user, UserModel currentUser, bool isDark) {
    final vibeLabel = _vibeLabels[user.id.hashCode.abs() % _vibeLabels.length];
    final matchScore = 86 + (user.id.hashCode.abs() % 12);

    return Container(
      height: 310,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: const Color(0xFF171B2B),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image
            if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
              CachedNetworkImage(
                imageUrl: user.avatarUrl!,
                fit: BoxFit.cover,
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF312E81), Color(0xFF4C1D95)],
                  ),
                ),
                child: Center(
                  child: Text(
                    user.name.isNotEmpty ? user.name[0] : '?',
                    style: const TextStyle(fontSize: 64, color: Colors.white70),
                  ),
                ),
              ),

            // Gradient Overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.35, 0.65, 1.0],
                    colors: [
                      Colors.black.withOpacity(0.25),
                      Colors.transparent,
                      Colors.black.withOpacity(0.65),
                      Colors.black.withOpacity(0.92),
                    ],
                  ),
                ),
              ),
            ),

            // Top Badges Row
            Positioned(
              top: 14,
              left: 14,
              right: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Active now badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Active now',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Match % badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12, width: 0.8),
                    ),
                    child: Text(
                      '$matchScore%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Profile info & Action Buttons
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${user.name}, ${user.age}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    vibeLabel,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFC4B5FD),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Button Row: Tap in + View
                  Row(
                    children: [
                      // Tap in button
                      GestureDetector(
                        onTap: () => _openChatWithUser(user, currentUser),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4F75FF), Color(0xFF8B5CF6)],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4F75FF).withOpacity(0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Tap in',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // View button
                      GestureDetector(
                        onTap: () => context.push('/profile/view/${user.id}'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white24, width: 1),
                          ),
                          child: const Text(
                            'View',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlsoAroundAvatarItem(UserModel user, UserModel currentUser, bool isDark) {
    final times = ['now', '5m ago', '12m ago', 'now', '18m ago', '8m ago'];
    final timeStr = times[user.id.hashCode.abs() % times.length];

    final avatarGrads = [
      [const Color(0xFF3B82F6), const Color(0xFF8B5CF6)],
      [const Color(0xFFEC4899), const Color(0xFF8B5CF6)],
      [const Color(0xFF10B981), const Color(0xFF06B6D4)],
      [const Color(0xFFF59E0B), const Color(0xFFEF4444)],
    ];
    final grad = avatarGrads[user.id.hashCode.abs() % avatarGrads.length];

    return GestureDetector(
      onTap: () => _showActiveUserModal(user, currentUser),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withOpacity(0.55),
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2.5),
                  child: ClipOval(
                    child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: user.avatarUrl!,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: grad),
                            ),
                            child: Center(
                              child: Text(
                                user.name.isNotEmpty ? user.name[0] : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              // Green dot
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF090C15) : Colors.white,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            user.name.split(' ').first,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white38 : const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2: CONNECTIONS (Strictly Mutual Matches Only)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConnectionsTab(List<UserModel> users, UserModel currentUser, bool isDark) {
    // Check for strictly mutual matches or Firestore matches array
    final matchedList = users.where((u) {
      if (u.id == currentUser.id) return false;
      if (currentUser.dislikedUsers.contains(u.id)) return false;
      return currentUser.matches.contains(u.id) ||
          (currentUser.following.contains(u.id) &&
              (u.following.contains(currentUser.id) ||
                  currentUser.followers.contains(u.id)));
    }).toList();

    if (matchedList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF8B5CF6).withOpacity(isDark ? 0.2 : 0.1),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 34,
                    color: Color(0xFF8B5CF6),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No connections yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'When you and someone like each other, your mutual matches will appear here for you to chat.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white.withOpacity(0.5) : const Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _tabController.animateTo(0);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F75FF), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F75FF).withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Explore Active People',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final vibeTags = [
      'Deep talks',
      'Coffee dates',
      'Night walks',
      'Indie music',
      'Late texts',
      'Voice notes',
      'Shared playlists',
      'Honest talks',
      'Spontaneous plans',
    ];

    final matchTimes = [
      'Matched 3d ago',
      'Matched 1w ago',
      'Matched 2w ago',
      'Matched 3w ago',
      'Matched 4d ago',
      'Matched 5d ago',
      'Matched 1w ago',
      'Matched 2w ago',
      'Matched 3d ago',
    ];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      physics: const BouncingScrollPhysics(),
      itemCount: matchedList.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14, left: 2),
            child: Text(
              "People you've matched with",
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white.withOpacity(0.45) : const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }

        final user = matchedList[index - 1];
        final tag = vibeTags[(index - 1) % vibeTags.length];
        final timeStr = matchTimes[(index - 1) % matchTimes.length];

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              // Avatar
              GestureDetector(
                onTap: () => context.push('/profile/view/${user.id}'),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: ClipOval(
                    child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: user.avatarUrl!,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: const Color(0xFF262D42),
                            child: Center(
                              child: Text(
                                user.name.isNotEmpty ? user.name[0] : '?',
                                style: const TextStyle(color: Colors.white, fontSize: 18),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Info Column
              Expanded(
                child: GestureDetector(
                  onTap: () => _openChatWithUser(user, currentUser),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name.split(' ').first,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tag,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Message button
              GestureDetector(
                onTap: () => _openChatWithUser(user, currentUser),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161A28) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
                    ),
                  ),
                  child: Text(
                    'Message',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3: COMMUNITIES (Real Data & Photos from Firestore)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCommunitiesTab(UserModel currentUser, bool isDark) {
    final communitiesAsync = ref.watch(communitiesProvider);
    final allCommunities = communitiesAsync.valueOrNull ?? [];

    // Filter by search and category
    var filtered = allCommunities;
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((c) =>
          c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.tag.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.description.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    if (_selectedCommunityCategory != 'All') {
      filtered = filtered
          .where((c) => c.tag.toLowerCase() == _selectedCommunityCategory.toLowerCase())
          .toList();
    }

    final featuredCommunity = allCommunities.isNotEmpty ? allCommunities.first : null;
    final trendingList = allCommunities.take(4).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Text Section ───────────────────────────────────────────
          const Text(
            'COMMUNITIES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: Color(0xFFA78BFA),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Find your\nkind of people',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.15,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Circles built around place, campus, and\nenergy — not just swipes.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white.withOpacity(0.5) : const Color(0xFF64748B),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),

          // ── "+ Create a community" Button ─────────────────────────────────
          GestureDetector(
            onTap: () => context.push('/community/create'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131726) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 16, color: Color(0xFF8B5CF6)),
                  const SizedBox(width: 6),
                  Text(
                    'Create a community',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // ── Category Filter Chips: All | Local | Campus | Vibe | Creators ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildCategoryChip('All', isDark),
                const SizedBox(width: 8),
                _buildCategoryChip('Local', isDark),
                const SizedBox(width: 8),
                _buildCategoryChip('Campus', isDark),
                const SizedBox(width: 8),
                _buildCategoryChip('Vibe', isDark),
                const SizedBox(width: 8),
                _buildCategoryChip('Creators', isDark),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Real FEATURED Card from Firestore ─────────────────────────────
          if (featuredCommunity != null) ...[
            _buildFeaturedCommunityCard(featuredCommunity, isDark),
            const SizedBox(height: 24),
          ],

          // ── Trending Section (Real Firestore Communities & Photos) ────────
          if (trendingList.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Trending',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Popular now',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white38 : const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Trending horizontal cards with real photos
            SizedBox(
              height: 165,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: trendingList.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final comm = trendingList[index];
                  return _buildTrendingCard(comm, isDark);
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Explore Section ───────────────────────────────────────────────
          Text(
            'Explore',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 12),

          // Explore wide list cards
          if (filtered.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(
                      Icons.bubble_chart_outlined,
                      size: 48,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No communities found',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap above to create your first community circle!',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white38 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filtered.map((comm) => _buildExploreWideCard(comm, currentUser, isDark)),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, bool isDark) {
    final isSelected = _selectedCommunityCategory == label;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedCommunityCategory = label);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : const Color(0xFF0F172A))
              : (isDark ? const Color(0xFF141724) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : (isDark ? Colors.white12 : Colors.black12),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isSelected
                ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                : (isDark ? Colors.white70 : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedCommunityCard(CommunityModel comm, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withOpacity(0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Real Community Background Photo
            if (comm.imageUrl.isNotEmpty)
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: comm.imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1E1038), Color(0xFF160A2A)],
                      ),
                    ),
                  ),
                ),
              )
            else
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1E1038), Color(0xFF160A2A)],
                    ),
                  ),
                ),
              ),

            // Deep Gradient Scrim
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.4, 0.9],
                    colors: [
                      Colors.black.withOpacity(0.4),
                      Colors.black.withOpacity(0.7),
                      Colors.black.withOpacity(0.92),
                    ],
                  ),
                ),
              ),
            ),

            // Card Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Tag & Members row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'FEATURED',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: Color(0xFFC4B5FD),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24, width: 0.8),
                        ),
                        child: Text(
                          '${comm.memberCount} members',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Category tag
                  Text(
                    comm.tag.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFA78BFA),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),

                  // Title
                  Text(
                    comm.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Description
                  Text(
                    comm.description.isNotEmpty
                        ? comm.description
                        : 'Connect and chat with other members in this circle.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withOpacity(0.8),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),

                  // "Open feed" Button
                  GestureDetector(
                    onTap: () => context.push('/community/${comm.id}'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Text(
                        'Open feed',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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

  Widget _buildTrendingCard(CommunityModel comm, bool isDark) {
    return GestureDetector(
      onTap: () => context.push('/community/${comm.id}'),
      child: SizedBox(
        width: 136,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 105,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFF1E2235),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (comm.imageUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: comm.imageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF312E81), Color(0xFF4C1D95)],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              comm.name.isNotEmpty ? comm.name[0] : '?',
                              style: const TextStyle(fontSize: 32, color: Colors.white70, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF312E81), Color(0xFF4C1D95)],
                          ),
                        ),
                        child: Center(
                          child: Text(
                            comm.name.isNotEmpty ? comm.name[0] : '?',
                            style: const TextStyle(fontSize: 32, color: Colors.white70, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),

                    // Subtle bottom gradient
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.6),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Top-right category badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white12, width: 0.6),
                        ),
                        child: Text(
                          comm.tag,
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              comm.name,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${comm.memberCount} members',
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.white38 : const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExploreWideCard(CommunityModel comm, UserModel currentUser, bool isDark) {
    final isJoined = currentUser.joinedCommunities.contains(comm.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => context.push('/community/${comm.id}'),
        child: Container(
          height: 104,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF121624) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Row(
              children: [
                // Left Photo Thumbnail (Strict Fixed Size)
                SizedBox(
                  width: 104,
                  height: 104,
                  child: comm.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: comm.imageUrl,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          errorWidget: (_, __, ___) => Container(
                            color: const Color(0xFF1E2235),
                            child: Center(
                              child: Text(
                                comm.name.isNotEmpty ? comm.name[0] : '?',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF1E2235),
                          child: Center(
                            child: Text(
                              comm.name.isNotEmpty ? comm.name[0] : '?',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                ),

                // Right Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Title + Join Button Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                comm.name,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Join / Open button
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ref.read(socialProvider.notifier).toggleCommunityJoin(
                                      currentUserId: currentUser.id,
                                      communityId: comm.id,
                                      isCurrentlyJoined: isJoined,
                                      isOnlyAdminApproved: comm.isOnlyAdminApproved,
                                      pendingApprovals: comm.pendingApprovals,
                                    );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4.5),
                                decoration: BoxDecoration(
                                  color: isJoined
                                      ? (isDark ? const Color(0xFF22283A) : const Color(0xFFE2E8F0))
                                      : (isDark ? Colors.white : const Color(0xFF0F172A)),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isJoined
                                        ? (isDark ? Colors.white12 : Colors.black12)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Text(
                                  isJoined ? 'Open' : 'Join',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: isJoined
                                        ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                        : (isDark ? const Color(0xFF0F172A) : Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Tag & Member count
                        Text(
                          '${comm.tag.toUpperCase()} · ${comm.memberCount} members',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? Colors.white38 : const Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        // Description
                        Text(
                          comm.description.isNotEmpty
                              ? comm.description
                              : 'Vibe, share thoughts & connect with like-minded souls',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        // Active status indicator
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'active circle',
                              style: TextStyle(
                                fontSize: 9.5,
                                color: isDark ? Colors.white38 : const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Helpers & Fallbacks ─────────────────────────────────────────────────────

const _vibeLabels = [
  'Midnight Thinker',
  'Soft Chaos',
  'Golden Hour',
  'Warm Current',
  'Soft Rebel',
  'Night Owl',
  'Quiet Storm',
];

final _fallbackUsers = [
  const UserModel(
    id: 'ananya-sample',
    name: 'Ananya',
    email: 'ananya@sample.com',
    age: 23,
    avatarUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500',
    isOnline: true,
  ),
  const UserModel(
    id: 'rishima-sample',
    name: 'Rishima',
    email: 'rishima@sample.com',
    age: 24,
    avatarUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=500',
    isOnline: true,
  ),
  const UserModel(
    id: 'mayuri-sample',
    name: 'Mayuri',
    email: 'mayuri@sample.com',
    age: 22,
    avatarUrl: 'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=500',
    isOnline: true,
  ),
  const UserModel(
    id: 'stuti-sample',
    name: 'Stuti',
    email: 'stuti@sample.com',
    age: 25,
    avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
    isOnline: true,
  ),
  const UserModel(
    id: 'kaveri-sample',
    name: 'Kaveri',
    email: 'kaveri@sample.com',
    age: 23,
    avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
    isOnline: true,
  ),
];
