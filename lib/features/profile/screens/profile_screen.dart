import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/models/post_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/utils/seeder.dart';
import '../../../core/providers/firebase_auth_provider.dart';
import 'dart:ui';
import '../../feed/widgets/post_card.dart';
import '../../feed/screens/saved_posts_screen.dart';
import '../../../shared/widgets/background_orbs.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/providers/access_provider.dart';
import '../../wallet/widgets/coin_gate_sheet.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _handleLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? AppTheme.darkSurface 
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout 🚪', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to log out? We\'ll miss you! ✨'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authControllerProvider.notifier).signOut();
              context.go('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingShimmer(bool isDark) {
    return Scaffold(
      body: Shimmer.fromColors(
        baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 100),
              // Profile image shimmer
              Center(
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Name shimmer
              Container(
                width: 120,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 8),
              // Username shimmer
              Container(
                width: 80,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 32),
              // Stats shimmer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(3, (i) => Column(
                  children: [
                    Container(
                      width: 40,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 30,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                )),
              ),
              const SizedBox(height: 32),
              // Bio shimmer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 200,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Grid shimmer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: 9,
                  itemBuilder: (context, index) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userDataAsync = ref.watch(userDataStreamProvider);
    final user = ref.watch(currentUserProvider);
    
    // Fetch all posts belonging to the user directly, independent of the active Feed filter
    final streamPosts = ref.watch(postsPaginationProvider).asData?.value ?? [];
    final localPosts = ref.watch(postsProvider);
    final List<PostModel> posts = [];
    final Set<String> seenIds = {};
    for (var p in [...localPosts, ...streamPosts]) {
      if (!seenIds.contains(p.id) && p.userId == user.id) {
        posts.add(p);
        seenIds.add(p.id);
      }
    }
    posts.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show loading shimmer while user data is loading
    if (userDataAsync.isLoading) {
      return _buildLoadingShimmer(isDark);
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Stack(
        children: [
          // Background Effect
          const BackgroundOrbs(),
          
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Glassmorphic Header (Avatar, Name, Actions)
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 64, 20, 0),
                    child: _buildGlassHeader(context, ref, user, isDark),
                  ),
                ),
              ),
              
              // Glassmorphic Stats Row
              SliverToBoxAdapter(
                child: _buildStats(user, posts.length, context, isDark),
              ),

              // Profile Visitors section
              SliverToBoxAdapter(
                child: _buildVisitorsCard(context, ref, user, isDark),
              ),
              
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBio(user, context),
                    _buildInterests(user, context, isDark),
                    _buildGridHeader(context, isDark),
                  ],
                ),
              ),
              
              _buildPostsGrid(posts, context, isDark, ref),
              SliverPadding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 120)),
            ],
          ),

          // Custom Back Button (Placed last so it stays on top of the scroll view and receives clicks)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : Colors.black),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/feed');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassHeader(BuildContext context, WidgetRef ref, UserModel user, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar with Glowing Border
        Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF00C6FF), Color(0xFF0072FF), AppTheme.accentPurple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryBlue.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
            ),
            padding: const EdgeInsets.all(3),
            child: CircleAvatar(
              backgroundImage: NetworkImage(
                user.avatarUrl ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(user.name)}&size=200&background=6ECBF5&color=fff&rounded=true',
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        
        // Name, Location, Actions
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      user.name,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (user.isVerified) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified_rounded, color: AppTheme.primaryBlue, size: 20),
                  ],
                ],
              ),
              if (user.location != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on_rounded, size: 14, color: AppTheme.textSecondary.withOpacity(0.8)),
                    const SizedBox(width: 4),
                    Text(
                      user.location!,
                      style: TextStyle(color: AppTheme.textSecondary.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: _GlassButton(
                      label: 'Edit Profile',
                      icon: Icons.edit_rounded,
                      onTap: () => context.push('/profile/edit'),
                      isPrimary: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _GlassButton(
                    label: '',
                    icon: Icons.settings_rounded,
                    onTap: () => _showSettingsSheet(context, ref),
                    isPrimary: false,
                    isIconOnly: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showSettingsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SettingsSheet(ref: ref),
    );
  }

  Widget _buildStats(UserModel user, int postCount, BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatItem(label: 'Followers', value: '${user.followers.length}'),
                _Divider(isDark: isDark, isGlass: true),
                _StatItem(label: 'Likes', value: '${user.likedBy.length}'),
                _Divider(isDark: isDark, isGlass: true),
                _StatItem(label: 'Photos', value: '$postCount'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisitorsCard(BuildContext context, WidgetRef ref, UserModel currentUser, bool isDark) {
    final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
    
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('profile_views')
          .where('targetId', isEqualTo: currentUser.id)
          .snapshots(),
      builder: (context, snapshot) {
        final allDocs = snapshot.hasData ? snapshot.data!.docs : [];
        final sortedDocs = allDocs.toList()..sort((a, b) {
          final aTime = a.data()['viewedAt'] as int? ?? 0;
          final bTime = b.data()['viewedAt'] as int? ?? 0;
          return bTime.compareTo(aTime);
        });
        
        final Map<String, dynamic> uniqueVisitors = {};
        for (var doc in sortedDocs) {
          final visitorId = doc.data()['viewerId'] as String? ?? '';
          if (!uniqueVisitors.containsKey(visitorId)) {
            uniqueVisitors[visitorId] = doc;
          }
        }
        final docs = uniqueVisitors.values.toList();
        
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('👻', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Text(
                            'Profile Visitors',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No profile views yet! 👻\n(Views by others will appear here)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontSize: 13,
                              height: 1.4,
                            ),
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
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark 
                        ? [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.02)]
                        : [Colors.black.withOpacity(0.05), Colors.black.withOpacity(0.01)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? Colors.purpleAccent : AppTheme.primaryBlue).withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: -5,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text('👻', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Text(
                              'Profile Visitors',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        if (docs.length <= 3 && docs.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: isDark ? Colors.white54 : Colors.black54),
                            onPressed: () => context.push('/profile/visitors'),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: docs.length > 3 ? 3 : docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final visitorId = data['viewerId'] as String;
                        final visitorName = data['viewerName'] as String? ?? 'User';
                        final visitorAvatar = data['viewerAvatar'] as String?;
                        
                        final isUnlocked = currentUser.hasActiveSubscription || 
                            currentUser.unlockedVisitors.contains(visitorId);
                            
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: (isUnlocked && visitorId.isNotEmpty) ? () => context.push('/profile/view/$visitorId') : (isUnlocked && visitorId.isEmpty ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This profile is unavailable or was deleted.'))) : null),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundImage: NetworkImage(
                                      isUnlocked 
                                          ? (visitorAvatar ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(visitorName)}')
                                          : 'https://ui-avatars.com/api/?name=%3F&background=252E42&color=fff'
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      isUnlocked ? visitorName : 'Ghost Visitor 👻',
                                      style: TextStyle(
                                        color: isDark ? Colors.white70 : Colors.black87,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (!isUnlocked)
                                    TextButton.icon(
                                      onPressed: () => _unlockGhostView(context, ref, currentUser, visitorId),
                                      icon: const Icon(Icons.lock_open_rounded, size: 14, color: AppTheme.primaryBlue),
                                      label: const Text('Unlock', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        backgroundColor: AppTheme.primaryBlue.withOpacity(0.12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    )
                                  else
                                    const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textSecondary, size: 14),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (docs.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => context.push('/profile/visitors'),
                            style: TextButton.styleFrom(
                              backgroundColor: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'See All Visitors (${docs.length})',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _unlockGhostView(BuildContext context, WidgetRef ref, UserModel currentUser, String visitorId) async {
    final allowed = await showCoinGate(context, ref, 'undo_ghost');
    if (!allowed) return;

    try {
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
      
      await db.runTransaction((tx) async {
        final userRef = db.collection('users').doc(currentUser.id);
        final snap = await tx.get(userRef);
        if (!snap.exists) return;
        
        final unlocked = List<String>.from(snap.data()?['unlockedVisitors'] ?? []);
        if (!unlocked.contains(visitorId)) {
          unlocked.add(visitorId);
        }
        
        tx.update(userRef, {
          'unlockedVisitors': unlocked,
        });
      });
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Visitor identity unlocked! 👻🎉'),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to unlock: $e'),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Widget _buildBio(UserModel user, BuildContext context) {
    if (user.bio == null || user.bio!.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Text(
        user.bio!,
        style: const TextStyle(
          fontSize: 15,
          height: 1.5,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildInterests(UserModel user, BuildContext context, bool isDark) {
    if (user.interests == null || user.interests!.isEmpty) return const SizedBox();
    
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Wrap(
          spacing: 8,
          runSpacing: 12,
          children: user.interests!.map((interest) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.1) : AppTheme.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.2) : AppTheme.primaryBlue.withOpacity(0.2),
                ),
              ),
              child: Text(
                interest.toString(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppTheme.primaryBlue,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildGridHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
      child: Text(
        'Photos & Video', 
        style: TextStyle(
          fontSize: 18, 
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
    );
  }

  SliverPadding _buildPostsGrid(
    List<PostModel> posts,
    BuildContext context,
    bool isDark,
    WidgetRef ref,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.8, // Taller portrait ratio
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final post = posts[index];
            return GestureDetector(
              onTap: () => _showPostDetail(context, post, posts),
              child: Hero(
                tag: 'post_${post.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
                        Image.network(
                          post.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: isDark ? Colors.white10 : Colors.black12,
                            child: const Center(
                              child: Icon(Icons.broken_image_rounded, color: AppTheme.textSecondary, size: 28),
                            ),
                          ),
                        )
                      else if (post.mood != null)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.primaryBlue.withOpacity(isDark ? 0.25 : 0.12),
                                AppTheme.primaryGreen.withOpacity(isDark ? 0.25 : 0.12),
                              ],
                            ),
                          ),
                          child: Center(
                            child: _buildEmojiImage(post.mood!.split(' ').first, size: 40),
                          ),
                        )
                      else
                        Container(
                          color: isDark ? Colors.white10 : Colors.black12,
                          child: const Center(child: Text('✨', style: TextStyle(fontSize: 40))),
                        ),

                      // Vignette bottom gradient
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),

                      // Stats counters row
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: Row(
                          children: [
                            Icon(Icons.favorite_rounded, color: Colors.white.withOpacity(0.9), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${post.likes.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (post.commentCount > 0) ...[
                              const SizedBox(width: 12),
                              Icon(Icons.chat_bubble_rounded, color: Colors.white.withOpacity(0.9), size: 12),
                              const SizedBox(width: 4),
                              Text(
                                '${post.commentCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                            const Spacer(),
                            if (post.isReel)
                              const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          childCount: posts.length,
        ),
      ),
    );
  }

  void _showPostDetail(BuildContext context, PostModel post, List<PostModel> allPosts) {
    final initialIndex = allPosts.indexWhere((p) => p.id == post.id);
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _ProfilePostsScrollSheet(
        posts: allPosts,
        initialIndex: initialIndex >= 0 ? initialIndex : 0,
      ),
    );
  }
}

// ─── Glassmorphic Button ────────────────────────────────────────────────────

class _GlassButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isIconOnly;

  const _GlassButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
    this.isIconOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 36,
            width: isIconOnly ? 36 : null,
            padding: EdgeInsets.symmetric(horizontal: isIconOnly ? 0 : 12),
            decoration: BoxDecoration(
              color: isPrimary 
                  ? AppTheme.primaryBlue.withOpacity(isDark ? 0.2 : 0.1) 
                  : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isPrimary 
                    ? AppTheme.primaryBlue.withOpacity(isDark ? 0.4 : 0.2)
                    : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon, 
                  size: 18, 
                  color: isPrimary 
                      ? (isDark ? Colors.white : AppTheme.primaryBlue)
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
                if (!isIconOnly) ...[
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: isPrimary 
                          ? (isDark ? Colors.white : AppTheme.primaryBlue)
                          : (isDark ? Colors.white70 : Colors.black87),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Premium Scrollable Profile Posts Sheet ───────────────────────────────────

class _ProfilePostsScrollSheet extends ConsumerStatefulWidget {
  final List<PostModel> posts;
  final int initialIndex;

  const _ProfilePostsScrollSheet({
    required this.posts,
    required this.initialIndex,
  });

  @override
  ConsumerState<_ProfilePostsScrollSheet> createState() => _ProfilePostsScrollSheetState();
}

class _ProfilePostsScrollSheetState extends ConsumerState<_ProfilePostsScrollSheet> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    // Estimate 540px height per post card to jump directly to the target post on load
    const double estimateHeight = 540.0;
    _scrollController = ScrollController(
      initialScrollOffset: widget.initialIndex * estimateHeight,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      builder: (context, sheetScrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkBg : const Color(0xFFF8FAFC),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    'Posts',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48), // balance back button space
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: widget.posts.length,
                itemBuilder: (context, index) {
                  final post = widget.posts[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: PostCard(
                      key: ValueKey(post.id),
                      post: post,
                      onLike: () {
                        ref
                            .read(postsProvider.notifier)
                            .toggleLike(post.id, currentUser.id);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  final WidgetRef ref;
  const _SettingsSheet({required this.ref});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
          ),
          const Text('Settings ⚙️', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          // Theme selection container
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : const Color(0xFFF3F6FF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : Colors.black.withOpacity(0.04),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      themeMode == ThemeMode.dark
                          ? Icons.dark_mode_rounded
                          : (themeMode == ThemeMode.light
                              ? Icons.light_mode_rounded
                              : Icons.settings_suggest_rounded),
                      color: AppTheme.primaryBlue,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Appearance',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _buildThemeOption(
                        context,
                        ref,
                        mode: ThemeMode.light,
                        label: 'Light',
                        icon: Icons.light_mode_rounded,
                        isSelected: themeMode == ThemeMode.light,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildThemeOption(
                        context,
                        ref,
                        mode: ThemeMode.dark,
                        label: 'Dark',
                        icon: Icons.dark_mode_rounded,
                        isSelected: themeMode == ThemeMode.dark,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildThemeOption(
                        context,
                        ref,
                        mode: ThemeMode.system,
                        label: 'System',
                        icon: Icons.settings_suggest_rounded,
                        isSelected: themeMode == ThemeMode.system,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Notifications
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : const Color(0xFFF3F6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.notifications_outlined, color: AppTheme.primaryGreen),
                const SizedBox(width: 12),
                const Expanded(child: Text('Notifications', style: TextStyle(fontWeight: FontWeight.w600))),
                Switch(
                  value: true,
                  activeColor: AppTheme.primaryBlue,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Privacy
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            tileColor: isDark ? AppTheme.darkCard : const Color(0xFFF3F6FF),
            leading: Icon(Icons.privacy_tip_outlined, color: AppTheme.accentPurple),
            title: const Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              // Usually you'd use url_launcher to open a webpage here
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
                  title: const Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.w700)),
                  content: const SingleChildScrollView(
                    child: Text(
                      'Your privacy is our priority.\n\n'
                      'We collect basic profile information and match preferences to provide our service. '
                      'Your data is never sold to third parties.\n\n'
                      'If you delete your account, all personal data is permanently wiped from our servers within 30 days.',
                      style: TextStyle(height: 1.5),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // Saved Posts (Bookmarks)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            tileColor: isDark ? AppTheme.darkCard : const Color(0xFFF3F6FF),
            leading: const Icon(Icons.bookmark_outline, color: AppTheme.primaryBlue),
            title: const Text('Saved Posts', style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SavedPostsScreen()),
              );
            },
          ),
           const SizedBox(height: 20),
          // Logout
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context); // Close sheet
                // Re-use the existing logout dialog
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Theme.of(ctx).brightness == Brightness.dark 
                        ? AppTheme.darkSurface 
                        : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Logout 🚪', style: TextStyle(fontWeight: FontWeight.w800)),
                    content: const Text('Are you sure you want to log out? We\'ll miss you! ✨'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          ref.read(authControllerProvider.notifier).signOut();
                          ctx.go('/login');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.error,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error.withOpacity(0.1),
                foregroundColor: AppTheme.error,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Delete Account
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                Navigator.pop(context); // Close sheet
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Theme.of(ctx).brightness == Brightness.dark 
                        ? AppTheme.darkSurface 
                        : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Delete Account 🚨', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.error)),
                    content: const Text('Are you completely sure? This action is permanent and cannot be undone. All your matches, messages, and profile data will be permanently erased.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          // We call delete account via the auth provider
                          try {
                            // Example delete logic - typically you'd trigger a cloud function or provider method
                            await ref.read(authControllerProvider.notifier).deleteAccount();
                            ctx.go('/login');
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to delete account. You may need to re-authenticate first.')),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.error,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Delete Permanently'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.delete_forever_rounded, size: 20),
              label: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.error.withOpacity(0.8),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    WidgetRef ref, {
    required ThemeMode mode,
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
  }) {
    final activeColor = AppTheme.primaryBlue;
    return GestureDetector(
      onTap: () {
        ref.read(themeModeProvider.notifier).setThemeMode(mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withOpacity(0.12)
              : (isDark ? Colors.white.withOpacity(0.04) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (isDark ? AppTheme.darkBorder : Colors.black.withOpacity(0.08)),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? activeColor : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  const _HeaderActionButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.4),
          ),
        ),
        child: Icon(icon, size: 18, color: isDark ? Colors.white : Colors.black87),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppTheme.primaryBlue,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  final bool isGlass;
  
  const _Divider({required this.isDark, this.isGlass = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      width: 1,
      color: isGlass 
          ? (isDark ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.1))
          : (isDark ? AppTheme.darkBorder : Colors.grey.withOpacity(0.2)),
    );
  }
}

Widget _buildEmojiImage(String emoji, {double size = 20}) {
  try {
    final runes = emoji.runes.toList();
    final cleanRunes = runes.where((r) => r != 0xFE0F).toList();
    final hex = cleanRunes.map((r) => r.toRadixString(16)).join('-');
    
    return Image.network(
      'https://cdnjs.cloudflare.com/ajax/libs/twemoji/14.0.2/72x72/$hex.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Text(
        emoji,
        style: TextStyle(
          fontSize: size,
          fontFamilyFallback: const ['Apple Color Emoji', 'Segoe UI Emoji', 'Noto Color Emoji', 'Android Emoji'],
        ),
      ),
    );
  } catch (_) {
    return Text(
      emoji,
      style: TextStyle(
        fontSize: size,
        fontFamilyFallback: const ['Apple Color Emoji', 'Segoe UI Emoji', 'Noto Color Emoji', 'Android Emoji'],
      ),
    );
  }
}
