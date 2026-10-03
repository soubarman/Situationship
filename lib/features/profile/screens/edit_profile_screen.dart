import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firebase_auth_provider.dart';
import '../../../core/models/user_model.dart';
import '../../../shared/widgets/multi_photo_manager.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../core/providers/firestore_provider.dart';

// ─── Screen ──────────────────────────────────────────────────────────────────

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  bool _isSaving = false;
  List<PhotoItem> _photos = [];
  
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _gender = 'other';
  String _interestedIn = 'female';
  String _relationshipIntent = 'serious';
  bool _isPhonePublic = false;
  List<String> _selectedInterests = [];
  bool _initializedFromUser = false;

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
      if (user.id.isNotEmpty && !_initializedFromUser) {
        setState(() {
          _initializedFromUser = true;
          _populateFields(user);
        });
      }
    });
  }

  void _populateFields(UserModel user) {
    _nameCtrl.text = user.name;
    _bioCtrl.text = user.bio ?? '';
    _locationCtrl.text = user.location ?? '';
    final List<String> photosList = [];
    if (user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty) {
      photosList.add(user.avatarUrl!.trim());
    }
    for (final p in user.photos) {
      final trimmed = p.trim();
      if (trimmed.isNotEmpty && !photosList.contains(trimmed)) {
        photosList.add(trimmed);
      }
      if (photosList.length == 4) break;
    }
    _photos = photosList.map((url) => PhotoItem(url: url, id: 'url_$url')).toList();
    _gender = user.gender;
    final eff = user.effectiveInterestedIn;
    if (eff.contains('male') && eff.contains('female')) {
      _interestedIn = 'all';
    } else if (eff.isNotEmpty) {
      _interestedIn = eff.first;
    } else {
      _interestedIn = user.isMale ? 'female' : 'male';
    }
    _relationshipIntent = user.relationshipIntent ?? 'serious';
    _phoneCtrl.text = user.phoneNumber ?? '';
    _isPhonePublic = user.isPhonePublic;
    
    _selectedInterests = user.interests.map((interestText) {
      final match = _allInterests.firstWhere(
        (i) => i.substring(3) == interestText,
        orElse: () => '✨ $interestText',
      );
      return match;
    }).toList();
  }

  void _togglePhonePublic(bool val) {
    if (val && _phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('Please enter your phone number first so others can unlock it!', isError: true),
      );
    }
    setState(() => _isPhonePublic = val);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _locationCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(_snack('Name is required'));
      return;
    }

    if (_isPhonePublic && _phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('Please enter your phone number to enable coin unlock, or turn the switch off.', isError: true),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final authUser = ref.read(authStateChangesProvider).asData?.value;
      if (authUser == null) throw Exception('Not authenticated');
      final userModel = ref.read(currentUserProvider);

      // Upload newly chosen local photo files and preserve existing URLs in order
      final List<String> finalUrls = [];
      final storage = FirebaseStorage.instanceFor(
        app: Firebase.app(),
        bucket: 'situation-ship.firebasestorage.app',
      );

      for (int i = 0; i < _photos.length && i < 4; i++) {
        final item = _photos[i];
        if (item.bytes != null || item.file != null) {
          try {
            final fileName = 'avatars/${authUser.uid}_photo_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
            final storageRef = storage.ref(fileName);
            final bytes = item.bytes ?? (item.file != null ? await item.file!.readAsBytes() : null);
            if (bytes != null && bytes.isNotEmpty) {
              await storageRef.putData(
                bytes,
                SettableMetadata(contentType: 'image/jpeg'),
              );
              final downloadUrl = await storageRef.getDownloadURL();
              finalUrls.add(downloadUrl);
              debugPrint('✅ [EditProfile] Uploaded photo $i: $downloadUrl');
            }
          } catch (e) {
            debugPrint('⚠️ [EditProfile] Failed uploading photo $i: $e');
            // If upload fails, retain existing URL if available
            if (item.url != null && item.url!.isNotEmpty) {
              finalUrls.add(item.url!);
            }
          }
        } else if (item.url != null && item.url!.isNotEmpty) {
          finalUrls.add(item.url!);
        }
      }

      final String? primaryPhoto = finalUrls.isNotEmpty ? finalUrls.first : null;
      if (primaryPhoto != null) {
        try {
          await authUser.updatePhotoURL(primaryPhoto);
        } catch (_) {}
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
        'avatarUrl': primaryPhoto,
        'photos': finalUrls,
        'interests': _selectedInterests.map((i) => i.substring(3)).toList(),
        'currentCityId': cityId,
        'gender': _gender,
        'interestedIn': _interestedIn == 'all'
            ? ['male', 'female', 'other']
            : [_interestedIn],
        'relationshipIntent': _relationshipIntent,
        'phoneNumber': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'isPhonePublic': _isPhonePublic,
        'phoneVisibilityVersion': newVersion,
      };

      // 1. Primary write to centralized firestoreProvider ('default')
      await firestoreProvider.collection('users').doc(authUser.uid).set(updates, SetOptions(merge: true));

      // 2. Mirror write to '(default)' for backward-compatibility
      try {
        await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: '(default)')
            .collection('users')
            .doc(authUser.uid)
            .set(updates, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[EditProfile] Mirror write notice: $e');
      }

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
    final user = ref.watch(currentUserProvider);
    if (!_initializedFromUser && user.id.isNotEmpty) {
      _initializedFromUser = true;
      _populateFields(user);
    }
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
                : Text(
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
            MultiPhotoManager(
              photos: _photos,
              onPhotosChanged: (updated) => setState(() => _photos = updated),
              isDark: isDark,
              maxPhotos: 4,
            ),
            const SizedBox(height: 32),
            
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
            
            _label('My Gender'),
            const SizedBox(height: 8),
            _buildGenderSelector(isDark),
            const SizedBox(height: 20),

            _label('Interested In (Dating Preference)'),
            const SizedBox(height: 4),
            Text(
              'Strictly controls who you discover and who can discover you.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _buildInterestedInSelector(isDark),
            const SizedBox(height: 20),

            _label('Relationship Goals (Intent)'),
            const SizedBox(height: 4),
            Text(
              'Powers our personality and compatibility matching engine.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _buildRelationshipIntentSelector(isDark),
            const SizedBox(height: 20),

            _label('Theme Vibe'),
            const SizedBox(height: 4),
            Text(
              'Auto matches your gender (Girl = Pink 🌸, Boy = Blue ⚡), or pick your favorite vibe.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _buildThemeVibeSelector(isDark),
            const SizedBox(height: 20),

            _label('Phone Number'),
            const SizedBox(height: 8),
            _buildField(_phoneCtrl, '+1 234 567 8900', isDark),
            const SizedBox(height: 12),
            
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isPhonePublic
                      ? AppTheme.primaryBlue.withOpacity(0.5)
                      : (isDark ? AppTheme.darkBorder : Colors.black12),
                  width: _isPhonePublic ? 1.5 : 1.0,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _togglePhonePublic(!_isPhonePublic),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Flexible(
                                    child: Text(
                                      'Allow others to unlock number with coins',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _isPhonePublic
                                          ? Colors.green.withOpacity(0.15)
                                          : (isDark ? Colors.white10 : Colors.black12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _isPhonePublic ? 'ACTIVE' : 'OFF',
                                      style: TextStyle(
                                        color: _isPhonePublic ? Colors.green : AppTheme.textSecondary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isPhonePublic
                                    ? '🪙 Others can spend 50 coins to reveal and copy your phone number.'
                                    : '🔒 Off: Your number remains completely private and cannot be unlocked.',
                                style: TextStyle(
                                  color: _isPhonePublic
                                      ? (isDark ? Colors.white70 : Colors.black87)
                                      : AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isPhonePublic,
                          onChanged: _togglePhonePublic,
                          activeColor: AppTheme.primaryBlue,
                        ),
                      ],
                    ),
                  ),
                ),
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
          borderSide: BorderSide(color: AppTheme.primaryBlue, width: 2),
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

  Widget _buildInterestedInSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : Colors.black12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _interestedIn,
          isExpanded: true,
          dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
          items: const [
            DropdownMenuItem(value: 'female', child: Text('Women 🌸')),
            DropdownMenuItem(value: 'male', child: Text('Men ⚡')),
            DropdownMenuItem(value: 'all', child: Text('Everyone ✨')),
            DropdownMenuItem(value: 'other', child: Text('Non-Binary 💜')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _interestedIn = val);
          },
        ),
      ),
    );
  }

  Widget _buildRelationshipIntentSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : Colors.black12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _relationshipIntent,
          isExpanded: true,
          dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
          items: const [
            DropdownMenuItem(value: 'serious', child: Text('Serious / Long-term Connection 💍')),
            DropdownMenuItem(value: 'casual', child: Text('Casual Dating / Situationship 🥂')),
            DropdownMenuItem(value: 'open', child: Text('Open to explore / See where it goes 🌊')),
            DropdownMenuItem(value: 'friendship', child: Text('New friends & Activity partners ☕')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _relationshipIntent = val);
          },
        ),
      ),
    );
  }

  Widget _buildThemeVibeSelector(bool isDark) {
    final currentVibe = ref.watch(themeVibeProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : Colors.black12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ThemeVibe>(
          value: currentVibe,
          isExpanded: true,
          dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
          items: const [
            DropdownMenuItem(
              value: ThemeVibe.auto,
              child: Text('Auto (Matches Gender) ⚧'),
            ),
            DropdownMenuItem(
              value: ThemeVibe.male,
              child: Text('⚡ Boy Mode (Blue)'),
            ),
            DropdownMenuItem(
              value: ThemeVibe.female,
              child: Text('🌸 Girl Mode (Pink)'),
            ),
          ],
          onChanged: (val) {
            if (val != null) {
              ref.read(themeVibeProvider.notifier).setVibe(val);
            }
          },
        ),
      ),
    );
  }
}
