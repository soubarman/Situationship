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

final _db = FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: 'default',
);

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
        location: _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
      );

      // Save to Firestore
      await _db.collection('posts').doc(postId).set(post.toMap());

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

            const SizedBox(height: 80),
          ],
        ),
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
}
