import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/post_model.dart';
import '../../wallet/widgets/coin_gate_sheet.dart';
import '../../../core/providers/access_provider.dart';

final _db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  XFile? _imageFile;
  final _captionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  bool _isSaving = false;
  String? _selectedMoodEmoji;
  String? _selectedMoodLabel;
  bool _isPriority = false;

  @override
  void dispose() {
    _captionCtrl.dispose();
    _locationCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (picked != null) setState(() => _imageFile = picked);
  }

  Future<void> _post() async {
    if (_imageFile == null) {
      _snack('Please pick a photo first 📸');
      return;
    }
    if (_captionCtrl.text.trim().isEmpty) {
      _snack('Add a caption ✏️');
      return;
    }

    if (_isPriority) {
      final allowed = await showCoinGate(context, ref, 'priority_feed');
      if (!allowed) {
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final currentUser = ref.read(currentUserProvider);
      final postId =
          DateTime.now().millisecondsSinceEpoch.toString();

      // Upload image
      final storageRef =
          FirebaseStorage.instance.ref('posts/$postId.jpg');
      if (kIsWeb) {
        final bytes = await _imageFile!.readAsBytes();
        await storageRef.putData(bytes);
      } else {
        await storageRef.putFile(File(_imageFile!.path));
      }
      final imageUrl = await storageRef.getDownloadURL();

      // Parse tags
      final tags = _tagsCtrl.text
          .split(' ')
          .map((t) => t.replaceAll('#', '').trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final post = PostModel(
        id: postId,
        userId: currentUser.id,
        userName: currentUser.name,
        userAvatar: currentUser.avatarUrl,
        isUserVerified: currentUser.isVerified,
        imageUrl: imageUrl,
        caption: _captionCtrl.text.trim(),
        createdAt: DateTime.now(),
        tags: tags,
        mood: _selectedMoodLabel != null
            ? '$_selectedMoodEmoji $_selectedMoodLabel'
            : null,
        location: _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
        isPriority: _isPriority,
      );

      // Save to Firestore
      await _db.collection('posts').doc(postId).set(post.toMap());
      ref.read(postsProvider.notifier).addPost(post);

      // Increment user's postCount
      await _db.collection('users').doc(currentUser.id).update({
        'postCount': FieldValue.increment(1),
      });

      if (mounted) {
        _snack('Post shared! 🎉', isSuccess: true);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _snack('Failed to post: $e', isError: true);
      }
    }
  }

  void _snack(String msg, {bool isError = false, bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError
          ? AppTheme.error
          : isSuccess
              ? AppTheme.success
              : AppTheme.primaryBlue,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        title: const Text('New Post'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _post,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Share',
                    style: TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image picker
            GestureDetector(
              onTap: _pickImage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                height: 320,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _imageFile != null
                        ? AppTheme.primaryBlue.withOpacity(0.4)
                        : (isDark ? AppTheme.darkBorder : Colors.black12),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: _imageFile != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: kIsWeb
                            ? Image.network(_imageFile!.path,
                                fit: BoxFit.cover, width: double.infinity)
                            : Image.file(File(_imageFile!.path),
                                fit: BoxFit.cover, width: double.infinity),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.primaryBlue, AppTheme.accentPurple],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.add_photo_alternate_rounded,
                                color: Colors.white, size: 40),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Tap to choose a photo',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Share a moment with the world ✨',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            if (_imageFile != null) ...[
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Change photo'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 28),

            _label('Caption'),
            const SizedBox(height: 10),
            _buildField(
              _captionCtrl,
              'Write something vibe-worthy... ✨',
              isDark,
              maxLines: 4,
            ),
            const SizedBox(height: 20),

            _label('Mood (optional)'),
            const SizedBox(height: 10),
            _buildMoodSelector(isDark),
            const SizedBox(height: 20),

            _label('Tags (optional)'),
            const SizedBox(height: 10),
            _buildField(
              _tagsCtrl,
              '#Travel #Vibes #Photography',
              isDark,
            ),
            const SizedBox(height: 20),

            _label('Location (optional)'),
            const SizedBox(height: 10),
            _buildField(
              _locationCtrl,
              'Where was this taken? 📍',
              isDark,
              prefixIcon: Icons.location_on_rounded,
            ),
            const SizedBox(height: 24),
            
            _buildPrioritySwitch(isDark),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildPrioritySwitch(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : Colors.black12,
        ),
      ),
      child: SwitchListTile(
        value: _isPriority,
        activeColor: AppTheme.primaryBlue,
        title: const Row(
          children: [
            Text('⚡', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text(
              'Priority Feed Placement',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
        subtitle: const Text(
          'Places your post higher in the feed for maximum views (Free with Premium or costs 10 coins)',
          style: TextStyle(fontSize: 11),
        ),
        onChanged: (val) {
          setState(() => _isPriority = val);
        },
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
      );

  Widget _buildField(
    TextEditingController ctrl,
    String hint,
    bool isDark, {
    int maxLines = 1,
    IconData? prefixIcon,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: isDark ? AppTheme.darkCard : Colors.white,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppTheme.primaryBlue, size: 20)
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: isDark ? AppTheme.darkBorder : Colors.black12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: isDark ? AppTheme.darkBorder : Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }
  Future<void> _openMoodPicker() async {
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MoodPickerSheet(
        selectedLabel: _selectedMoodLabel,
        onSelect: (emoji, label) {
          setState(() {
            _selectedMoodEmoji = emoji;
            _selectedMoodLabel = label;
          });
          Navigator.of(context, rootNavigator: true).pop();
        },
      ),
    );
  }

  Widget _buildMoodSelector(bool isDark) {
    final hasMood = _selectedMoodLabel != null;
    return GestureDetector(
      onTap: _openMoodPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppTheme.darkBorder : Colors.black12,
          ),
        ),
        child: Row(
          children: [
            if (hasMood) ...[
              _buildEmojiImage(_selectedMoodEmoji!, size: 24),
              const SizedBox(width: 10),
              Text(
                _selectedMoodLabel!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryBlue,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedMoodEmoji = null;
                    _selectedMoodLabel = null;
                  });
                },
                child: const Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Colors.redAccent,
                ),
              ),
            ] else ...[
              Icon(Icons.sentiment_satisfied_alt_outlined,
                  color: AppTheme.primaryBlue, size: 22),
              const SizedBox(width: 10),
              const Text(
                'How are you feeling? Share your mood...',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Colors.grey),
            ]
          ],
        ),
      ),
    );
  }
}

class _MoodItem {
  final String emoji;
  final String label;
  const _MoodItem(this.emoji, this.label);
}

const _moods = [
  _MoodItem('❤️', 'Flirty'),
  _MoodItem('😍', "Crushin'"),
  _MoodItem('✨', "Vibin'"),
  _MoodItem('🥺', 'Feeling cute'),
  _MoodItem('🔥', 'In the mood'),
  _MoodItem('💌', 'Manifesting love'),
  _MoodItem('😎', 'Chill'),
  _MoodItem('🌙', 'Lost in thoughts'),
  _MoodItem('☁️', 'Daydreaming'),
  _MoodItem('🎵', 'Vibing with music'),
  _MoodItem('🛋️', 'Just chilling'),
  _MoodItem('🤔', 'Confused'),
  _MoodItem('😄', "It's complicated"),
  _MoodItem('🦋', 'Mixed feelings'),
  _MoodItem('💭', 'Missing someone'),
  _MoodItem('📵', 'On read'),
  _MoodItem('🚀', 'Excited'),
  _MoodItem('🌍', 'Adventurous'),
  _MoodItem('🎉', 'Party mood'),
];

class _MoodPickerSheet extends StatefulWidget {
  final String? selectedLabel;
  final void Function(String emoji, String label) onSelect;

  const _MoodPickerSheet({
    required this.selectedLabel,
    required this.onSelect,
  });

  @override
  State<_MoodPickerSheet> createState() => _MoodPickerSheetState();
}

class _MoodPickerSheetState extends State<_MoodPickerSheet> {
  String? _hoveredLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkSurface : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: ShaderMask(
                  shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
                  child: const Text(
                    'How are you feeling?',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.86,
                  ),
                  itemCount: _moods.length,
                  itemBuilder: (_, i) {
                    final mood = _moods[i];
                    final isSelected = widget.selectedLabel == mood.label;
                    final isHovered = _hoveredLabel == mood.label;

                    return GestureDetector(
                      onTap: () => widget.onSelect(mood.emoji, mood.label),
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredLabel = mood.label),
                        onExit: (_) => setState(() => _hoveredLabel = null),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryBlue.withOpacity(0.1)
                                : isHovered
                                    ? AppTheme.primaryBlue.withOpacity(0.05)
                                    : (isDark
                                        ? AppTheme.darkCard
                                        : const Color(0xFFF4F5FA)),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryBlue
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildEmojiImage(mood.emoji, size: 28),
                              const SizedBox(height: 6),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  mood.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? AppTheme.primaryBlue
                                        : (isDark
                                            ? Colors.white70
                                            : AppTheme.textSecondary),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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
