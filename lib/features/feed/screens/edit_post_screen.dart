import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/post_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';

class EditPostScreen extends ConsumerStatefulWidget {
  final PostModel post;

  const EditPostScreen({super.key, required this.post});

  @override
  ConsumerState<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends ConsumerState<EditPostScreen> {
  late TextEditingController _captionController;
  String? _selectedMood;
  String? _imageUrl;
  String? _musicTrack;
  String? _musicArtist;
  bool _imageRemoved = false;

  final List<String> _moods = [
    '😎 Chill',
    '😊 Happy',
    '😔 Sad',
    '🔥 Energetic',
    '🤔 Reflective',
    '😴 Tired',
    '🤪 Playful',
    '🥰 Loved',
  ];

  final List<Map<String, String>> _popularSongs = [
    {
      'title': 'Blinding Lights',
      'artist': 'The Weeknd',
      'category': 'Energetic',
      'cover': 'https://images.unsplash.com/photo-1614680376593-902f74fa0d41?w=120&auto=format&fit=crop&q=60',
    },
    {
      'title': 'As It Was',
      'artist': 'Harry Styles',
      'category': 'Mood',
      'cover': 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=120&auto=format&fit=crop&q=60',
    },
    {
      'title': 'Stay',
      'artist': 'The Kid LAROI & Justin Bieber',
      'category': 'Energetic',
      'cover': 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=120&auto=format&fit=crop&q=60',
    },
    {
      'title': 'Someone Like You',
      'artist': 'Adele',
      'category': 'Sad',
      'cover': 'https://images.unsplash.com/photo-1487180142328-0c4e37023af5?w=120&auto=format&fit=crop&q=60',
    },
    {
      'title': 'Levitating',
      'artist': 'Dua Lipa',
      'category': 'Energetic',
      'cover': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=120&auto=format&fit=crop&q=60',
    },
    {
      'title': 'Fix You',
      'artist': 'Coldplay',
      'category': 'Sad',
      'cover': 'https://images.unsplash.com/photo-1506157786151-b8491531f063?w=120&auto=format&fit=crop&q=60',
    },
  ];

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.post.caption);
    _selectedMood = widget.post.mood;
    _imageUrl = widget.post.imageUrl;
    _musicTrack = widget.post.musicTrack;
    _musicArtist = widget.post.musicArtist;
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  void _showMoodPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Current Mood',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _moods.map((mood) {
                  final isSelected = _selectedMood == mood;
                  return ChoiceChip(
                    label: Text(mood),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedMood = selected ? mood : null;
                      });
                      Navigator.pop(context);
                    },
                    selectedColor: AppTheme.primaryBlue.withOpacity(0.2),
                    checkmarkColor: AppTheme.primaryBlue,
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.primaryBlue : (isDark ? Colors.white : Colors.black87),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showMusicPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return DefaultTabController(
              length: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                    const Text(
                      'Music Picker',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search songs or artists...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: isDark ? Colors.white10 : Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TabBar(
                      indicatorColor: AppTheme.primaryBlue,
                      labelColor: AppTheme.primaryBlue,
                      unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
                      tabs: const [
                        Tab(text: 'Sad'),
                        Tab(text: 'Mood'),
                        Tab(text: 'Energetic'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildMusicList(scrollController, 'Sad'),
                          _buildMusicList(scrollController, 'Mood'),
                          _buildMusicList(scrollController, 'Energetic'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMusicList(ScrollController scrollController, String category) {
    final songs = _popularSongs.where((s) => s['category'] == category).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      controller: scrollController,
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isSelected = _musicTrack == song['title'] && _musicArtist == song['artist'];

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryBlue.withOpacity(0.08)
                : (isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.01)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.primaryBlue.withOpacity(0.3) : Colors.transparent,
            ),
          ),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                song['cover']!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
            title: Text(
              song['title']!,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              song['artist']!,
              style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12),
            ),
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: AppTheme.primaryBlue)
                : Icon(Icons.add_circle_outline, color: isDark ? Colors.white60 : Colors.black45),
            onTap: () {
              setState(() {
                _musicTrack = song['title'];
                _musicArtist = song['artist'];
              });
              Navigator.pop(context);
            },
          ),
        );
      },
    );
  }

  void _saveChanges() async {
    final caption = _captionController.text.trim();
    if (caption.isEmpty && !_imageRemoved && _imageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot save empty post')),
      );
      return;
    }

    ref.read(postsProvider.notifier).editPost(
          widget.post.id,
          caption: caption,
          mood: _selectedMood,
          imageUrl: _imageRemoved ? null : _imageUrl,
          musicTrack: _musicTrack,
          musicArtist: _musicArtist,
        );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Post edited successfully!'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.success,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1216) : Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Edit Screen', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _saveChanges,
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 16),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User info row
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: NetworkImage(
                      widget.post.userAvatar ?? 'https://i.pravatar.cc/100?u=${widget.post.userId}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '@you',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (_selectedMood != null) ...[
                            Text(
                              'feeling ${_selectedMood!.split(' ').last}',
                              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                            ),
                            const SizedBox(width: 4),
                            const Text('·', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            'Edited',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white30 : Colors.black38, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Caption input box
              TextField(
                controller: _captionController,
                maxLines: 5,
                style: const TextStyle(fontSize: 15, height: 1.4),
                decoration: InputDecoration(
                  hintText: "What's on your mind?",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.primaryBlue),
                  ),
                  filled: true,
                  fillColor: isDark ? AppTheme.darkSurface : Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              // Image display with delete option
              if (_imageUrl != null && !_imageRemoved) ...[
                const Text(
                  'Image Attachment',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        _imageUrl!,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _imageRemoved = true;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ] else if (_imageRemoved) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _imageRemoved = false;
                    });
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Undo Remove Image'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                    side: const BorderSide(color: AppTheme.primaryBlue),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Mood Card Selector
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                ),
                child: Row(
                  children: [
                    const Text('Current Mood: ', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Text(
                      _selectedMood ?? 'None Set',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _showMoodPicker,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: const Text('Change', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Music Attachment Card Selector
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.music_note, color: AppTheme.primaryBlue),
                        const SizedBox(width: 8),
                        const Text('Post Music', style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        if (_musicTrack != null)
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _musicTrack = null;
                                _musicArtist = null;
                              });
                            },
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_musicTrack != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black).withOpacity(0.03),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Text('🎵 ', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _musicTrack!,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    _musicArtist ?? '',
                                    style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showMusicPicker,
                        icon: const Icon(Icons.library_music_outlined, size: 18),
                        label: Text(_musicTrack != null ? 'Change Music' : 'Add Music'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryBlue,
                          side: const BorderSide(color: AppTheme.primaryBlue),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
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
