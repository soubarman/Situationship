import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firebase_auth_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// ─── Provider ────────────────────────────────────────────────────────────────

final _db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');

// ─── Screen ──────────────────────────────────────────────────────────────────

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  bool _isSaving = false;
  XFile? _avatarFile;
  String? _currentAvatarUrl;
  
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _gender = 'other';
  bool _isPhonePublic = false;
  List<String> _selectedInterests = [];

  static const _allInterests = [
    '🎵 Music', '🎬 Movies', '📚 Books', '✈️ Travel', '🍕 Food',
    '🏋️ Fitness', '🎮 Gaming', '🐾 Pets', '🌿 Nature', '📸 Photography',
    '🎨 Art', '💃 Dancing', '☕ Coffee', '🧘 Yoga', '🏄 Surfing',
    '🍳 Cooking', '🎭 Theatre', '🎯 Sports', '🛍️ Fashion', '🌙 Astrology',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(currentUserProvider);
      setState(() {
        _nameCtrl.text = user.name;
        _bioCtrl.text = user.bio ?? '';
        _locationCtrl.text = user.location ?? '';
        _currentAvatarUrl = user.avatarUrl;
        _gender = user.gender;
        _phoneCtrl.text = user.phoneNumber ?? '';
        _isPhonePublic = user.isPhonePublic;
        
        _selectedInterests = user.interests.map((interestText) {
          final match = _allInterests.firstWhere(
            (i) => i.substring(3) == interestText,
            orElse: () => '✨ $interestText',
          );
          return match;
        }).toList();
      });
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _locationCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (picked != null) {
      setState(() => _avatarFile = picked);
    }
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(_snack('Name is required'));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final authUser = ref.read(authStateChangesProvider).asData?.value;
      if (authUser == null) throw Exception('Not authenticated');
      final userModel = ref.read(currentUserProvider);

      String? photoUrl = _currentAvatarUrl;
      if (_avatarFile != null) {
        final ref = FirebaseStorage.instance.ref('avatars/${authUser.uid}.jpg');
        
        if (kIsWeb) {
          final bytes = await _avatarFile!.readAsBytes();
          await ref.putData(
            bytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
        } else {
          await ref.putFile(
            File(_avatarFile!.path),
            SettableMetadata(contentType: 'image/jpeg'),
          );
        }
        
        photoUrl = await ref.getDownloadURL();
      }

      // Use the location text field as the city for Boost — simple and consistent
      final locationText = _locationCtrl.text.trim();
      final cityId = locationText.isEmpty ? null : locationText.toLowerCase().replaceAll(' ', '_');

      int newVersion = userModel.phoneVisibilityVersion;
      if (_isPhonePublic == false && userModel.isPhonePublic == true) {
        newVersion += 1; // Incrementing version to invalidate all previous unlocks
      }

      final updates = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'location': locationText.isEmpty ? null : locationText,
        'avatarUrl': photoUrl,
        'interests': _selectedInterests.map((i) => i.substring(3)).toList(),
        // Use location as city for Boost scope — users just type their city naturally
        'currentCityId': cityId,
        'gender': _gender,
        'phoneNumber': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'isPhonePublic': _isPhonePublic,
        'phoneVisibilityVersion': newVersion,
      };

      if (photoUrl != null) {
        updates['photos'] = FieldValue.arrayUnion([photoUrl]);
      }

      await _db.collection('users').doc(authUser.uid).set(updates, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(_snack('Profile updated! ✨'));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          _snack('Error saving profile: $e', isError: true),
        );
      }
    }
  }

  SnackBar _snack(String msg, {bool isError = false}) {
    return SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.error : AppTheme.primaryBlue,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark ? AppTheme.darkCard : Colors.white,
                        border: Border.all(
                          color: AppTheme.primaryBlue.withOpacity(0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryBlue.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: _avatarFile != null
                            ? (kIsWeb 
                                ? Image.network(_avatarFile!.path, fit: BoxFit.cover)
                                : Image.file(File(_avatarFile!.path), fit: BoxFit.cover))
                            : _currentAvatarUrl != null
                                ? Image.network(_currentAvatarUrl!, fit: BoxFit.cover)
                                : Icon(Icons.person, size: 60, color: AppTheme.textTertiary),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
                            width: 3,
                          ),
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            
            _label('Name'),
            const SizedBox(height: 8),
            _buildField(_nameCtrl, 'Your name', isDark),
            const SizedBox(height: 20),
            
            _label('Bio'),
            const SizedBox(height: 8),
            _buildField(_bioCtrl, 'A bit about you...', isDark, maxLines: 4),
            const SizedBox(height: 20),
            
            _label('Your City'),
            const SizedBox(height: 4),
            Text(
              'Used for Boost visibility — type any city you\'re in',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _buildField(_locationCtrl, 'e.g. Jorhat, Guwahati, Delhi...', isDark),
            const SizedBox(height: 20),
            
            _label('Gender'),
            const SizedBox(height: 8),
            _buildGenderSelector(isDark),
            const SizedBox(height: 20),

            _label('Phone Number'),
            const SizedBox(height: 8),
            _buildField(_phoneCtrl, '+1 234 567 8900', isDark),
            const SizedBox(height: 12),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppTheme.darkBorder : Colors.black12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Allow others to unlock number with coins', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          'If off, your number remains completely private.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isPhonePublic,
                    onChanged: (val) => setState(() => _isPhonePublic = val),
                    activeColor: AppTheme.primaryBlue,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _label('Interests'),
                Text(
                  '${_selectedInterests.length} selected',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 12,
              children: _allInterests.map((interest) {
                final isSelected = _selectedInterests.contains(interest);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedInterests.remove(interest);
                      } else {
                        _selectedInterests.add(interest);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? AppTheme.primaryBlue.withOpacity(isDark ? 0.2 : 0.1)
                          : isDark ? AppTheme.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryBlue : (isDark ? AppTheme.darkBorder : Colors.black12),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      interest,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 120),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String hint, bool isDark, {int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: isDark ? AppTheme.darkCard : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : Colors.black12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildGenderSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : Colors.black12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _gender.isNotEmpty ? _gender : 'other',
          isExpanded: true,
          dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
          items: const [
            DropdownMenuItem(value: 'male', child: Text('Male')),
            DropdownMenuItem(value: 'female', child: Text('Female')),
            DropdownMenuItem(value: 'other', child: Text('Other')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _gender = val);
          },
        ),
      ),
    );
  }
}
