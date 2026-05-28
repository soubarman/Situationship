import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/app_state_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _query = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use new paginated discovery provider or fall back to match queue
    final allUsers = ref.watch(discoveryProvider).valueOrNull ?? ref.watch(matchQueueProvider);
    final allPosts = ref.watch(postsProvider);

    final matchedUsers = _query.isEmpty
        ? <UserModel>[]
        : (allUsers ?? [])
            .where((u) => u.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    final matchedPosts = _query.isEmpty
        ? []
        : allPosts
            .where(
              (p) =>
                  p.caption.toLowerCase().contains(_query.toLowerCase()) ||
                  p.tags.any(
                    (t) => t.toLowerCase().contains(_query.toLowerCase()),
                  ) ||
                  p.userName.toLowerCase().contains(_query.toLowerCase()),
            )
            .toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Container(
          height: 44,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : const Color(0xFFF3F6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : const Color(0xFFE5E7EB),
            ),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: (v) => _onSearchChanged(v.trim()),
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search people, posts, tags...',
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppTheme.primaryBlue),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded, size: 18, color: AppTheme.textTertiary),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
            ),
          ),
        ),
      ),
      body: _query.isEmpty
          ? _buildEmptyState(isDark, allUsers ?? [])
          : (matchedUsers.isEmpty && matchedPosts.isEmpty)
              ? _buildNoResults()
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (matchedUsers.isNotEmpty) ...[
                      _sectionHeader('People'),
                      ...matchedUsers.map((u) => _UserResultTile(user: u)),
                    ],
                    if (matchedPosts.isNotEmpty) ...[
                      _sectionHeader('Posts'),
                      ...matchedPosts.map((p) {
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: p.imageUrl != null
                                ? Image.network(
                                    p.imageUrl!,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: 48,
                                    height: 48,
                                    color: AppTheme.primaryBlue.withOpacity(0.2),
                                    child: const Icon(Icons.image_outlined),
                                  ),
                          ),
                          title: Text(
                            p.userName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            p.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                          trailing: Text('${p.likes.length} ❤️',
                              style: const TextStyle(fontSize: 12)),
                        );
                      }),
                    ],
                  ],
                ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.textTertiary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, List<UserModel> allUsers) {
    final trending = ['Photography', 'GoldenHour', 'Music', 'Travel', 'Fitness', 'Art'];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trending tags 🔥',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: trending.map((tag) {
              return GestureDetector(
                onTap: () {
                  _searchController.text = tag;
                  setState(() => _query = tag);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    '#$tag',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          Text(
            'Suggested People',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...allUsers.take(3).map((u) => _UserResultTile(user: u)),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            'No results for "$_query"',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Try different keywords',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _UserResultTile extends StatelessWidget {
  final UserModel user;
  const _UserResultTile({required this.user});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/profile/view/${user.id}'),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundImage: NetworkImage(
                user.avatarUrl ?? 'https://i.pravatar.cc/100?u=${user.id}',
              ),
            ),
            if (user.isOnline)
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
        title: Row(
          children: [
            Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            if (user.isVerified) ...[
              const SizedBox(width: 4),
              Icon(Icons.verified_rounded, size: 14, color: AppTheme.primaryBlue),
            ],
          ],
        ),
        subtitle: Text(
          user.bio ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(50),
          ),
          child: const Text(
            'Follow',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
