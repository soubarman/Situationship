import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/community_model.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../shared/widgets/background_orbs.dart';

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
  String? _selectedPresetUrl;
  bool _isOnlyAdminApproved = false;
  bool _isLoading = false;

  final List<Map<String, String>> _presetCovers = [
    {
      'label': 'Vibe Space',
      'url': 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?q=80&w=800&auto=format&fit=crop',
    },
    {
      'label': 'Night City',
      'url': 'https://images.unsplash.com/photo-1519501025264-65ba15a82390?q=80&w=800&auto=format&fit=crop',
    },
    {
      'label': 'Chill Cafe',
      'url': 'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?q=80&w=800&auto=format&fit=crop',
    },
    {
      'label': 'Music Souls',
      'url': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?q=80&w=800&auto=format&fit=crop',
    },
    {
      'label': 'Anime World',
      'url': 'https://images.unsplash.com/photo-1578632767115-351597cf2477?q=80&w=800&auto=format&fit=crop',
    },
  ];

  final List<String> _quickTags = [
    'LOCAL',
    'CAMPUS',
    'VIBE',
    'MUSIC',
    'ANIME',
    'CREATORS',
    'TECH',
    'NIGHT TALKS',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    HapticFeedback.selectionClick();
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1080,
      );
      if (picked != null) {
        setState(() {
          _imageFile = picked;
          _selectedPresetUrl = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _createCommunity() async {
    HapticFeedback.mediumImpact();
    final name = _nameController.text.trim();
    final tag = _tagController.text.trim().toUpperCase();

    if (name.isEmpty || tag.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please provide both a community name and category tag',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final firestore = firestoreProvider;
      final newDocRef = firestore.collection('communities').doc();
      final currentUser = ref.read(currentUserProvider);
      final communityId = newDocRef.id;

      // Upload Cover Photo if selected, else use preset or default
      String imageUrl = _selectedPresetUrl ??
          'https://images.unsplash.com/photo-1521737604893-d14cc237f11d?q=80&w=800&auto=format&fit=crop';

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
        name: name,
        description: _descriptionController.text.trim(),
        imageUrl: imageUrl,
        memberCount: 1, // Start with the creator
        memberAvatars: [currentUser.id],
        tag: tag,
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
          SnackBar(
            content: Text('Error creating community: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0D18) : const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          const BackgroundOrbs(),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    // Modern Header Bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => context.pop(),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                                border: Border.all(
                                  color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
                                ),
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Create Community',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Text(
                                  'Build your own circle of real people',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white38 : const Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 1, color: Colors.white10),

                    // Scrollable Form Content
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── 1. Cover Photo Area ─────────────────────────
                            _buildCoverPhotoSection(isDark),

                            const SizedBox(height: 24),

                            // ── 2. Community Name ───────────────────────────
                            _buildSectionHeader('Community Name', 'Give your circle a distinct identity', isDark),
                            const SizedBox(height: 8),
                            _buildModernInput(
                              controller: _nameController,
                              hintText: 'e.g. Midnight Thinkers, Jorhat Tech Circle',
                              prefixIcon: Icons.groups_rounded,
                              isDark: isDark,
                            ),

                            const SizedBox(height: 22),

                            // ── 3. Category Tag & Quick Pills ───────────────
                            _buildSectionHeader('Category Tag', 'Helps people discover your vibe', isDark),
                            const SizedBox(height: 8),
                            _buildModernInput(
                              controller: _tagController,
                              hintText: 'e.g. VIBE, CAMPUS, TECH',
                              prefixIcon: Icons.tag_rounded,
                              maxLength: 12,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            // Quick category chips
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: _quickTags.map((tag) {
                                  final isSelected = _tagController.text.toUpperCase() == tag;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: GestureDetector(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        setState(() => _tagController.text = tag);
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 180),
                                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFF8B5CF6)
                                              : (isDark ? const Color(0xFF191D2C) : const Color(0xFFE2E8F0)),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: isSelected
                                                ? const Color(0xFFA78BFA)
                                                : (isDark ? Colors.white10 : Colors.black12),
                                          ),
                                        ),
                                        child: Text(
                                          '#$tag',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: isSelected
                                                ? Colors.white
                                                : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),

                            const SizedBox(height: 22),

                            // ── 4. Description ──────────────────────────────
                            _buildSectionHeader('Description', 'What is this circle about?', isDark),
                            const SizedBox(height: 8),
                            _buildModernInput(
                              controller: _descriptionController,
                              hintText: 'Share topics, rituals, meetups, and what members can expect...',
                              maxLines: 3,
                              isDark: isDark,
                            ),

                            const SizedBox(height: 24),

                            // ── 5. Privacy Settings ─────────────────────────
                            _buildSectionHeader('Privacy & Access', 'Control who can view and join', isDark),
                            const SizedBox(height: 10),
                            _buildPrivacyCard(
                              title: 'Public Community',
                              subtitle: 'Anyone can discover, join instantly, and chat in the feed.',
                              icon: Icons.public_rounded,
                              iconColor: const Color(0xFF10B981),
                              isSelected: !_isOnlyAdminApproved,
                              onTap: () => setState(() => _isOnlyAdminApproved = false),
                              isDark: isDark,
                            ),
                            const SizedBox(height: 10),
                            _buildPrivacyCard(
                              title: 'Admin Approval Required',
                              subtitle: 'Members must request access before viewing or posting.',
                              icon: Icons.shield_rounded,
                              iconColor: const Color(0xFFF59E0B),
                              isSelected: _isOnlyAdminApproved,
                              onTap: () => setState(() => _isOnlyAdminApproved = true),
                              isDark: isDark,
                            ),

                            const SizedBox(height: 32),

                            // ── 6. Create Community Submit Button ───────────
                            GestureDetector(
                              onTap: _isLoading ? null : _createCommunity,
                              child: Container(
                                height: 54,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF4F75FF), Color(0xFF8B5CF6)],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF4F75FF).withOpacity(0.4),
                                      blurRadius: 16,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
                                            SizedBox(width: 8),
                                            Text(
                                              'Create Community',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
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
        ],
      ),
    );
  }

  // ─── Cover Photo Picker ───────────────────────────────────────────────────

  Widget _buildCoverPhotoSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: isDark ? const Color(0xFF141724) : Colors.white,
              border: Border.all(
                color: const Color(0xFF8B5CF6).withOpacity(isDark ? 0.35 : 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_imageFile != null)
                    kIsWeb
                        ? Image.network(_imageFile!.path, fit: BoxFit.cover)
                        : Image.file(File(_imageFile!.path), fit: BoxFit.cover)
                  else if (_selectedPresetUrl != null)
                    Image.network(_selectedPresetUrl!, fit: BoxFit.cover)
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF1E1B4B).withOpacity(isDark ? 0.8 : 0.05),
                            const Color(0xFF312E81).withOpacity(isDark ? 0.9 : 0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add_photo_alternate_rounded,
                              size: 24,
                              color: Color(0xFFA78BFA),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Upload Cover Photo',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap to choose from your gallery',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.white38 : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Overlay action badge if photo exists
                  if (_imageFile != null || _selectedPresetUrl != null)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24, width: 0.8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'Change',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
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

        const SizedBox(height: 12),

        // Quick Preset Covers
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Or choose a preset theme:',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white38 : const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _presetCovers.map((preset) {
              final isSelected = _selectedPresetUrl == preset['url'] && _imageFile == null;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedPresetUrl = preset['url'];
                      _imageFile = null;
                    });
                  },
                  child: Container(
                    width: 72,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF8B5CF6)
                            : (isDark ? Colors.white12 : Colors.black12),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(preset['url']!, fit: BoxFit.cover),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.7),
                                ],
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                preset['label']!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Center(
                              child: Icon(Icons.check_circle_rounded, color: Color(0xFF8B5CF6), size: 18),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── Modern Input Fields ──────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, String subtitle, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 11.5,
            color: isDark ? Colors.white38 : const Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildModernInput({
    required TextEditingController controller,
    required String hintText,
    required bool isDark,
    IconData? prefixIcon,
    int maxLines = 1,
    int? maxLength,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131724) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        style: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF0F172A),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: isDark ? Colors.white30 : Colors.black38,
            fontSize: 13,
            fontWeight: FontWeight.normal,
          ),
          prefixIcon: prefixIcon != null
              ? Icon(prefixIcon, size: 18, color: const Color(0xFF8B5CF6))
              : null,
          border: InputBorder.none,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  // ─── Privacy Toggle Cards ─────────────────────────────────────────────────

  Widget _buildPrivacyCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF171D33) : const Color(0xFFEEF2FF))
              : (isDark ? const Color(0xFF131724) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6366F1)
                : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06)),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(icon, color: iconColor, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF6366F1)
                      : (isDark ? Colors.white24 : Colors.black26),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
