import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/post_model.dart';

// â”€â”€â”€ Mood data â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _MoodItem {
  final String emoji;
  final String label;
  const _MoodItem(this.emoji, this.label);
}

const _moods = [
  _MoodItem('â¤ï¸', 'Flirty'),
  _MoodItem('ðŸ˜', "Crushin'"),
  _MoodItem('âœ¨', "Vibin'"),
  _MoodItem('ðŸ¥º', 'Feeling cute'),
  _MoodItem('ðŸ”¥', 'In the mood'),
  _MoodItem('ðŸ’Œ', 'Manifesting love'),
  _MoodItem('ðŸ˜Ž', 'Chill'),
  _MoodItem('ðŸŒ™', 'Lost in thoughts'),
  _MoodItem('â˜ï¸', 'Daydreaming'),
  _MoodItem('ðŸŽµ', 'Vibing with music'),
  _MoodItem('ðŸ›‹ï¸', 'Just chilling'),
  _MoodItem('ðŸ¤”', 'Confused'),
  _MoodItem('ðŸ˜„', "It's complicated"),
  _MoodItem('ðŸ¦‹', 'Mixed feelings'),
  _MoodItem('ðŸ’­', 'Missing someone'),
  _MoodItem('ðŸ“µ', 'On read'),
  _MoodItem('ðŸš€', 'Excited'),
  _MoodItem('ðŸŒ', 'Adventurous'),
  _MoodItem('ðŸŽ‰', 'Party mood'),
];

// â”€â”€â”€ Firestore â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

final _db = FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: 'default',
);

// â”€â”€â”€ Quick Post Box â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
  String? _planTitle;
  String? _planTime;
  String? _planLocation;
  XFile? _imageFile;
  String? _attachedVoicePath;
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

  // â”€â”€ Mood picker â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  // â”€â”€ Plan dialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _openPlanDialog() async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => _PlanDialog(
        onAttach: (title, time, loc) {
          setState(() {
            _planTitle = title;
            _planTime = time;
            _planLocation = loc;
          });
        },
      ),
    );
  }

  // â”€â”€ Take (camera) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _openTake() {
    // Close the sheet first, then navigate to the camera
    Navigator.of(context, rootNavigator: true).pop();
    Future.microtask(() => context.push('/take/create'));
  }

  // â”€â”€ Voice recorder â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _openVoiceRecorder() async {
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VoiceRecorderSheet(
        onRecorded: (audioPath) async {
          if (mounted) {
            setState(() {
              _attachedVoicePath = audioPath;
            });
          }
          _snack('🎤 Voice note attached!', isSuccess: true);
        },
      ),
    );
  }

  // â”€â”€ Image picker â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (picked != null) setState(() => _imageFile = picked);
  }

  // â”€â”€ Post â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _post() async {
    final text = _captionCtrl.text.trim();
    if (text.isEmpty && _imageFile == null && _selectedMoodLabel == null) {
      _snack('Say something first ðŸ’¬');
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

      String finalCaption = text.isEmpty ? '' : text;
      if (_planTitle != null) {
        final planStr = '\n\nðŸ—“ï¸ Plan: $_planTitle'
            '${_planTime!.isNotEmpty ? '\nâ° Time: $_planTime' : ''}'
            '${_planLocation!.isNotEmpty ? '\nðŸ“ Where: $_planLocation' : ''}';
        finalCaption += planStr;
      }

      String? voiceUrl;
      if (_attachedVoicePath != null) {
        final storageRef = FirebaseStorage.instance.ref('voice_notes/$postId.m4a');
        await storageRef.putFile(File(_attachedVoicePath!));
        voiceUrl = await storageRef.getDownloadURL();
      }

      final post = PostModel(
        id: postId,
        userId: currentUser.id,
        userName: currentUser.name,
        userAvatar: currentUser.avatarUrl,
        isUserVerified: currentUser.isVerified,
        imageUrl: imageUrl,
        caption: finalCaption.trim(),
        createdAt: DateTime.now(),
        mood: moodString,
        communityId: widget.communityId,
        communityName: widget.communityName,
        voiceUrl: voiceUrl,
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
          _planTitle = null;
          _planTime = null;
          _planLocation = null;
          _imageFile = null;
          _attachedVoicePath = null;
          _isSaving = false;
        });
        _snack('Posted! ðŸŽ‰', isSuccess: true);
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

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _isFocused
              ? AppTheme.primaryBlue.withOpacity(0.5)
              : (isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.06)),
          width: _isFocused ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: _isFocused
                ? AppTheme.primaryBlue.withOpacity(0.12)
                : Colors.black.withOpacity(isDark ? 0.25 : 0.06),
            blurRadius: _isFocused ? 20 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // â”€â”€ Handle and Close Button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               const SizedBox(width: 48), // Balance the close button
               // Drag handle
               Container(
                 margin: const EdgeInsets.only(top: 10),
                 width: 36,
                 height: 4,
                 decoration: BoxDecoration(
                   color: isDark ? Colors.white24 : Colors.black12,
                   borderRadius: BorderRadius.circular(2),
                 ),
               ),
               Padding(
                 padding: const EdgeInsets.only(top: 6, right: 6),
                 child: GestureDetector(
                   onTap: () => Navigator.of(context).pop(),
                   child: Container(
                     padding: const EdgeInsets.all(4),
                     decoration: BoxDecoration(
                       shape: BoxShape.circle,
                       border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                     ),
                     child: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 16),
                   ),
                 ),
               ),
            ],
          ),

          // â”€â”€ Text input row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
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

          // â”€â”€ Mood chip (when selected) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

          // â”€â”€ Plan chip (when selected) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_planTitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF4EAE8D).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF4EAE8D).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF4EAE8D)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _planTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4EAE8D),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() {
                        _planTitle = null;
                        _planTime = null;
                        _planLocation = null;
                      }),
                      child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4EAE8D)),
                    ),
                  ],
                ),
              ),
            ),

          // ── Voice chip (when selected) ───────────────────────────────────
          if (_attachedVoicePath != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFD66B7C).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD66B7C).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mic_rounded, size: 14, color: Color(0xFFD66B7C)),
                    const SizedBox(width: 6),
                    const Text(
                      'Voice Note',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD66B7C),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() {
                        _attachedVoicePath = null;
                      }),
                      child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFD66B7C)),
                    ),
                  ],
                ),
              ),
            ),

          // â”€â”€ Image preview â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

          // â”€â”€ Action bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _ToolBtn(
                  icon: Icons.image_outlined,
                  label: 'Upload',
                  color: const Color(0xFF4CA0DB),
                  onTap: _pickPhoto,
                ),
                const SizedBox(width: 8),
                _ToolBtn(
                  icon: Icons.mic_none,
                  label: 'Voice',
                  color: const Color(0xFFD66B7C),
                  onTap: kIsWeb ? () => _snack('Voice recording not supported on web') : _openVoiceRecorder,
                ),
                const SizedBox(width: 8),
                _ToolBtn(
                  icon: Icons.camera_alt_outlined,
                  label: 'Take',
                  color: const Color(0xFFE5B945),
                  onTap: _openTake,
                ),
                const SizedBox(width: 8),
                _ToolBtn(
                  icon: Icons.calendar_today_outlined,
                  label: 'Plan',
                  color: const Color(0xFF4EAE8D),
                  onTap: _openPlanDialog,
                ),
                const SizedBox(width: 8),
                _ToolBtn(
                  icon: Icons.sentiment_satisfied_alt_outlined,
                  label: 'Mood',
                  color: const Color(0xFFA17EC7),
                  onTap: _openMoodPicker,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Color(0xFFD1A041), size: 18),
                const SizedBox(width: 6),
                Text(
                  '+5 aura on first post today',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const Spacer(),
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

// â”€â”€â”€ Tool button (Photo / Mood) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€ Post button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€â”€ Mood chip â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€â”€ Mood picker sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€â”€ Plan dialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PlanDialog extends StatefulWidget {
  final Function(String title, String time, String location) onAttach;
  const _PlanDialog({required this.onAttach});
  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  final _titleCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  final _whereCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _timeCtrl.dispose();
    _whereCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1D2D) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10)),
          ]
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Make a plan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. Rooftop sunset hang',
                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 14),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _timeCtrl,
                    decoration: InputDecoration(
                      hintText: 'Fri 7:00 PM',
                      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 14),
                      filled: true,
                      fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: _whereCtrl,
                    decoration: InputDecoration(
                      hintText: 'Where',
                      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 14),
                      filled: true,
                      fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final t = _titleCtrl.text.trim();
                    if (t.isNotEmpty) {
                      widget.onAttach(t, _timeCtrl.text.trim(), _whereCtrl.text.trim());
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B5A96),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: const Text('Attach', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- Voice Recorder Sheet ---

class _VoiceRecorderSheet extends StatefulWidget {
  final Future<void> Function(String path) onRecorded;
  const _VoiceRecorderSheet({required this.onRecorded});

  @override
  State<_VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<_VoiceRecorderSheet>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _hasRecording = false;
  String? _filePath;
  int _seconds = 0;
  Timer? _timer;
  late AnimationController _pulseCtrl;
  VideoPlayerController? _previewAudioCtrl;
  bool _isPlayingPreview = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _recorder.dispose();
    _timer?.cancel();
    _pulseCtrl.dispose();
    _previewAudioCtrl?.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission denied'), backgroundColor: Colors.red));
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000), path: path);
    setState(() { _isRecording = true; _hasRecording = false; _seconds = 0; _filePath = path; });
    _pulseCtrl.repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _seconds++); });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    _pulseCtrl.stop(); _pulseCtrl.reset();
    setState(() { 
      _isRecording = false; 
      _hasRecording = true; 
      _filePath = path;
    });
  }

  Future<void> _togglePreviewPlay() async {
    if (_filePath == null) return;
    if (_isPlayingPreview) {
      await _previewAudioCtrl?.pause();
      setState(() => _isPlayingPreview = false);
    } else {
      if (_previewAudioCtrl == null) {
        _previewAudioCtrl = VideoPlayerController.file(File(_filePath!));
        await _previewAudioCtrl!.initialize();
        _previewAudioCtrl!.setLooping(false);
        _previewAudioCtrl!.addListener(() {
          if (mounted) {
            setState(() {
              _isPlayingPreview = _previewAudioCtrl!.value.isPlaying;
            });
            if (_previewAudioCtrl!.value.position >= _previewAudioCtrl!.value.duration) {
              setState(() {
                _isPlayingPreview = false;
              });
            }
          }
        });
      }
      await _previewAudioCtrl!.seekTo(Duration.zero);
      await _previewAudioCtrl!.play();
      setState(() => _isPlayingPreview = true);
    }
  }

  String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1A1D2D) : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(2))),
        Text('Voice Note', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
        const SizedBox(height: 32),
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, child) => Transform.scale(scale: _isRecording ? (1.0 + _pulseCtrl.value * 0.25) : 1.0, child: child),
          child: GestureDetector(
            onTap: _isRecording ? _stopRecording : _startRecording,
            child: Container(
              width: 88, height: 88,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _isRecording ? const Color(0xFFD66B7C) : const Color(0xFFD66B7C).withOpacity(0.15), border: Border.all(color: const Color(0xFFD66B7C), width: 2.5), boxShadow: _isRecording ? [BoxShadow(color: const Color(0xFFD66B7C).withOpacity(0.45), blurRadius: 24, spreadRadius: 4)] : []),
              child: Icon(_isRecording ? Icons.stop_rounded : Icons.mic_rounded, size: 40, color: _isRecording ? Colors.white : const Color(0xFFD66B7C)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(_isRecording ? 'REC  ${_fmt(_seconds)}' : _hasRecording ? 'Done  ${_fmt(_seconds)} recorded' : 'Tap to start recording', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _isRecording ? const Color(0xFFD66B7C) : (isDark ? Colors.white70 : Colors.black54))),
        const SizedBox(height: 32),
        if (_hasRecording) ...[
          GestureDetector(
            onTap: _togglePreviewPlay,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFD66B7C).withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD66B7C).withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isPlayingPreview ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: const Color(0xFFD66B7C),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Listen to Recording',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD66B7C),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () async {
                await _previewAudioCtrl?.dispose();
                _previewAudioCtrl = null;
                setState(() {
                  _hasRecording = false;
                  _seconds = 0;
                  _filePath = null;
                  _isPlayingPreview = false;
                });
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Re-record'),
              style: OutlinedButton.styleFrom(foregroundColor: isDark ? Colors.white70 : Colors.black54, side: BorderSide(color: isDark ? Colors.white24 : Colors.black12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 14)))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(onPressed: () async { Navigator.pop(context); if (_filePath != null) await widget.onRecorded(_filePath!); }, icon: const Icon(Icons.attach_file_rounded), label: const Text('Attach'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD66B7C), foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 14)))),
          ]),
        ] else SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(foregroundColor: isDark ? Colors.white70 : Colors.black54, side: BorderSide(color: isDark ? Colors.white24 : Colors.black12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('Cancel'))),
      ]),
    );
  }
}

