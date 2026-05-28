import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/community_model.dart';
import '../../../core/providers/firestore_provider.dart';

class CreateCommunityScreen extends ConsumerStatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  ConsumerState<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends ConsumerState<CreateCommunityScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagController = TextEditingController();
  XFile? _imageFile;
  bool _isOnlyAdminApproved = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1080,
      );
      if (picked != null) {
        setState(() {
          _imageFile = picked;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _createCommunity() async {
    if (_nameController.text.trim().isEmpty || _tagController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and tag are required')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final firestore = firestoreProvider;
      final newDocRef = firestore.collection('communities').doc();
      final currentUser = ref.read(currentUserProvider);
      final communityId = newDocRef.id;

      // Upload Cover Photo if selected, else fallback to Unsplash default
      String imageUrl = 'https://images.unsplash.com/photo-1521737604893-d14cc237f11d?q=80&w=800&auto=format&fit=crop';
      if (_imageFile != null) {
        final storageRef = FirebaseStorage.instance.ref('communities/$communityId.jpg');
        if (kIsWeb) {
          final bytes = await _imageFile!.readAsBytes();
          await storageRef.putData(bytes);
        } else {
          await storageRef.putFile(File(_imageFile!.path));
        }
        imageUrl = await storageRef.getDownloadURL();
      }

      final newCommunity = CommunityModel(
        id: communityId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        imageUrl: imageUrl,
        memberCount: 1, // Start with the creator
        memberAvatars: [currentUser.id],
        tag: _tagController.text.trim().toUpperCase(),
        createdBy: currentUser.id,
        isOnlyAdminApproved: _isOnlyAdminApproved,
        pendingApprovals: const [],
      );

      final batch = firestore.batch();
      
      // 1. Create the community
      batch.set(newDocRef, newCommunity.toMap());
      
      // 2. Add creator to the community
      final userRef = firestore.collection('users').doc(currentUser.id);
      batch.update(userRef, {
        'joinedCommunities': [...currentUser.joinedCommunities, communityId]
      });

      await batch.commit();

      if (mounted) {
        context.pop();
        context.push('/community/$communityId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating community: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: isDark ? Colors.white : Colors.black),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Create Community',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover Image Picker
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: double.infinity,
                  height: 160,
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : Colors.grey[200],
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppTheme.primaryBlue.withOpacity(0.3),
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: _imageFile != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: kIsWeb
                              ? Image.network(_imageFile!.path, fit: BoxFit.cover, width: double.infinity)
                              : Image.file(File(_imageFile!.path), fit: BoxFit.cover, width: double.infinity),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_rounded, size: 48, color: AppTheme.primaryBlue.withOpacity(0.6)),
                            const SizedBox(height: 8),
                            Text(
                              'Add Cover Photo',
                              style: TextStyle(
                                color: AppTheme.primaryBlue.withOpacity(0.8),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (_imageFile != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Change Cover Photo'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryBlue,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              
              _buildInputLabel('Community Name'),
              _buildTextField(
                controller: _nameController,
                hintText: 'E.g. Code & Coffee',
                isDark: isDark,
              ),
              
              const SizedBox(height: 24),
              _buildInputLabel('Category Tag'),
              _buildTextField(
                controller: _tagController,
                hintText: 'E.g. TECH, MUSIC, ART',
                isDark: isDark,
                maxLength: 10,
              ),
              
              const SizedBox(height: 24),
              _buildInputLabel('Description'),
              _buildTextField(
                controller: _descriptionController,
                hintText: 'What is this community about?',
                isDark: isDark,
                maxLines: 4,
              ),

              // Join Setting Custom Pill Cards
              const SizedBox(height: 28),
              _buildInputLabel('Privacy Settings'),
              const SizedBox(height: 10),
              
              GestureDetector(
                onTap: () => setState(() => _isOnlyAdminApproved = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: !_isOnlyAdminApproved
                        ? AppTheme.primaryBlue.withOpacity(isDark ? 0.08 : 0.04)
                        : (isDark ? AppTheme.darkSurface : Colors.white),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: !_isOnlyAdminApproved
                          ? AppTheme.primaryBlue
                          : (isDark ? Colors.white10 : Colors.black12),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2DD4BF).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.public_rounded, color: Color(0xFF2DD4BF), size: 22),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Public Community',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Anyone can join instantly and view the feed.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_isOnlyAdminApproved)
                        const Icon(Icons.check_circle_rounded, color: AppTheme.primaryBlue, size: 22),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              GestureDetector(
                onTap: () => setState(() => _isOnlyAdminApproved = true),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _isOnlyAdminApproved
                        ? AppTheme.primaryBlue.withOpacity(isDark ? 0.08 : 0.04)
                        : (isDark ? AppTheme.darkSurface : Colors.white),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isOnlyAdminApproved
                          ? AppTheme.primaryBlue
                          : (isDark ? Colors.white10 : Colors.black12),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_rounded, color: Colors.orange, size: 22),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Admin Approved',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Members require approval from you to view or post.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isOnlyAdminApproved)
                        const Icon(Icons.check_circle_rounded, color: AppTheme.primaryBlue, size: 22),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
              
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createCommunity,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                        )
                      : const Text(
                          'Create Community',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required bool isDark,
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
        filled: true,
        fillColor: isDark ? AppTheme.darkSurface : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppTheme.primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }
}
