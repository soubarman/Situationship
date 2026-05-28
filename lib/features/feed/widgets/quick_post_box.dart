import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/post_model.dart';

// ─── Mood data ────────────────────────────────────────────────────────────────

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

// ─── Firestore ────────────────────────────────────────────────────────────────

final _db = FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: 'default',
);

// ─── Quick Post Box ───────────────────────────────────────────────────────────

class QuickPostBox extends ConsumerStatefulWidget {
  final String? communityId;
  final String? communityName;

  const QuickPostBox({
    super.key,
    this.communityId,
    this.communityName,
  });

  @override
  ConsumerState<QuickPostBox> createState() => _QuickPostBoxState();
}

class _QuickPostBoxState extends ConsumerState<QuickPostBox> {
  final _captionCtrl = TextEditingController();
  final _focusNode = FocusNode();
  String? _selectedMoodEmoji;
  String? _selectedMoodLabel;
  XFile? _imageFile;
  bool _isSaving = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Mood picker ────────────────────────────────────────────────────────────

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

  // ── Image picker ────────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (picked != null) setState(() => _imageFile = picked);
  }

  // ── Post ────────────────────────────────────────────────────────────────────

  Future<void> _post() async {
    final text = _captionCtrl.text.trim();
    if (text.isEmpty && _imageFile == null && _selectedMoodLabel == null) {
      _snack('Say something first 💬');
      return;
    }
    _focusNode.unfocus();
    setState(() => _isSaving = true);
    try {
      final currentUser = ref.read(currentUserProvider);
      final postId = DateTime.now().millisecondsSinceEpoch.toString();

      String? imageUrl;
      if (_imageFile != null) {
        final storageRef = FirebaseStorage.instance.ref('posts/$postId.jpg');
        if (kIsWeb) {
          final bytes = await _imageFile!.readAsBytes();
          await storageRef.putData(bytes);
        } else {
          await storageRef.putFile(File(_imageFile!.path));
        }
        imageUrl = await storageRef.getDownloadURL();
      }

      final moodString = _selectedMoodLabel != null
          ? '$_selectedMoodEmoji $_selectedMoodLabel'
          : null;

      final post = PostModel(
        id: postId,
        userId: currentUser.id,
        userName: currentUser.name,
        userAvatar: currentUser.avatarUrl,
        isUserVerified: currentUser.isVerified,
        imageUrl: imageUrl,
        caption: text.isEmpty ? '' : text,
        createdAt: DateTime.now(),
        mood: moodString,
        communityId: widget.communityId,
        communityName: widget.communityName,
      );

      await _db.collection('posts').doc(postId).set(post.toMap());
      await _db.collection('users').doc(currentUser.id).update({
        'postCount': FieldValue.increment(1),
      });

      if (mounted) {
        _captionCtrl.clear();
        setState(() {
          _selectedMoodEmoji = null;
          _selectedMoodLabel = null;
          _imageFile = null;
          _isSaving = false;
        });
        _snack('Posted! 🎉', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _snack('Failed: $e', isError: true);
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

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final hasMood = _selectedMoodLabel != null;
    final hasContent = _captionCtrl.text.isNotEmpty ||
        _imageFile != null ||
        hasMood;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _isFocused
              ? AppTheme.primaryBlue.withOpacity(0.5)
              : (isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.06)),
          width: _isFocused ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: _isFocused
                ? AppTheme.primaryBlue.withOpacity(0.12)
                : Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: _isFocused ? 20 : 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Text input row ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: TextField(
              controller: _captionCtrl,
              focusNode: _focusNode,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Share your vibe...',
                hintStyle: TextStyle(
                  color: isDark
                      ? Colors.white38
                      : const Color(0xFFADB5BD),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                fillColor: Colors.transparent,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : AppTheme.textPrimary,
                height: 1.4,
              ),
              maxLines: null,
              minLines: 1,
            ),
          ),

          // ── Mood chip (when selected) ────────────────────────────────────
          if (hasMood)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Text(
                    'Feeling: ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? Colors.white54
                          : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  _MoodChip(
                    emoji: _selectedMoodEmoji!,
                    label: _selectedMoodLabel!,
                    onRemove: () => setState(() {
                      _selectedMoodEmoji = null;
                      _selectedMoodLabel = null;
                    }),
                  ),
                ],
              ),
            ),

          // ── Image preview ────────────────────────────────────────────────
          if (_imageFile != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: kIsWeb
                        ? Image.network(_imageFile!.path,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover)
                        : Image.file(File(_imageFile!.path),
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => setState(() => _imageFile = null),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Divider ──────────────────────────────────────────────────────
          const SizedBox(height: 12),
          Divider(
            height: 1,
            thickness: 1,
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : const Color(0xFFEEF0F5),
          ),

          // ── Action bar ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                // Photo
                _ToolBtn(
                  icon: Icons.image_outlined,
                  label: 'Photo',
                  color: AppTheme.primaryBlue,
                  isDark: isDark,
                  onTap: _pickPhoto,
                ),
                const SizedBox(width: 4),
                // Mood
                _ToolBtn(
                  icon: Icons.sentiment_satisfied_alt_outlined,
                  label: 'Mood',
                  color: AppTheme.primaryBlue,
                  isDark: isDark,
                  onTap: _openMoodPicker,
                ),
                const Spacer(),
                // Post button — gradient pill
                _PostButton(
                  isSaving: _isSaving,
                  enabled: hasContent || !_isSaving,
                  onTap: _post,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tool button (Photo / Mood) ────────────────────────────────────────────────

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Post button ───────────────────────────────────────────────────────────────

class _PostButton extends StatefulWidget {
  final bool isSaving;
  final bool enabled;
  final VoidCallback onTap;

  const _PostButton({
    required this.isSaving,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_PostButton> createState() => _PostButtonState();
}

class _PostButtonState extends State<_PostButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.isSaving) widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            gradient: widget.isSaving
                ? null
                : AppTheme.primaryGradient,
            color: widget.isSaving ? const Color(0xFFD0D0D0) : null,
            borderRadius: BorderRadius.circular(50),
            boxShadow: widget.isSaving
                ? []
                : [
                    BoxShadow(
                      color: AppTheme.primaryBlue.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: widget.isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Post',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─── Mood chip ─────────────────────────────────────────────────────────────────

class _MoodChip extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onRemove;

  const _MoodChip({
    required this.emoji,
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: AppTheme.primaryBlue.withOpacity(0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildEmojiImage(emoji, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.primaryBlue,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close_rounded,
              size: 13,
              color: AppTheme.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mood picker sheet ─────────────────────────────────────────────────────────

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
              // Handle bar
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

              // Title
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

              // Mood grid
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
