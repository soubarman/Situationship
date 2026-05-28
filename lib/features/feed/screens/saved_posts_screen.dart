import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/post_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../widgets/post_card.dart';

class SavedPostsScreen extends ConsumerStatefulWidget {
  const SavedPostsScreen({super.key});

  @override
  ConsumerState<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends ConsumerState<SavedPostsScreen> {
  String _selectedCategory = 'All';
  List<String> _savedPostIds = [];
  bool _isLoading = true;

  final List<Map<String, dynamic>> _folders = [
    {'name': 'All', 'icon': '📂', 'color': AppTheme.primaryBlue},
    {'name': 'Reflective', 'icon': '🤔', 'color': Colors.purple},
    {'name': 'Energetic', 'icon': '🔥', 'color': Colors.orange},
    {'name': 'Chill', 'icon': '😎', 'color': Colors.teal},
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedPostIds();
  }

  Future<void> _loadSavedPostIds() async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarked = prefs.getStringList('bookmarked_posts') ?? [];
    if (mounted) {
      setState(() {
        _savedPostIds = bookmarked;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allPosts = ref.watch(postsProvider);

    // Filter posts that are saved
    final savedPosts = allPosts.where((p) => _savedPostIds.contains(p.id)).toList();

    // Filter by selected category folder
    final filteredPosts = savedPosts.where((p) {
      if (_selectedCategory == 'All') return true;
      if (p.mood == null) return false;
      return p.mood!.toLowerCase().contains(_selectedCategory.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1216) : Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Saved Posts', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category Folders Horizontal Row
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _folders.map((folder) {
                        final isSelected = _selectedCategory == folder['name'];
                        final folderColor = folder['color'] as Color;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedCategory = folder['name'];
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? folderColor.withOpacity(0.12)
                                  : (isDark ? AppTheme.darkSurface : Colors.white),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? folderColor : (isDark ? Colors.white10 : Colors.black12),
                                width: isSelected ? 1.5 : 0.8,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: folderColor.withOpacity(0.15),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      )
                                    ]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Text(folder['icon'] as String, style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 8),
                                Text(
                                  folder['name'] as String,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    color: isSelected ? folderColor : (isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(height: 1, color: Colors.grey),
                ),

                // Saved Posts List
                Expanded(
                  child: filteredPosts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('📂', style: TextStyle(fontSize: 48)),
                              const SizedBox(height: 12),
                              Text(
                                _selectedCategory == 'All'
                                    ? 'No saved posts yet'
                                    : 'No saved posts in "$_selectedCategory"',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Save posts from your feed to view them here',
                                style: TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: filteredPosts.length,
                          itemBuilder: (context, index) {
                            final post = filteredPosts[index];
                            return PostCard(
                              post: post,
                              onLike: () {
                                ref.read(postsProvider.notifier).toggleLike(
                                      post.id,
                                      ref.read(currentUserProvider).id,
                                    );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
