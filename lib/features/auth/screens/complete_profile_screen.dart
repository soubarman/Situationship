import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/providers/firebase_auth_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../shared/widgets/multi_photo_manager.dart';

// ─── Provider ────────────────────────────────────────────────────────────────

final _db = firestoreProvider;

// ─── Screen ──────────────────────────────────────────────────────────────────

class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  late AnimationController _progressController;
  late AnimationController _entryController;
  late Animation<double> _progressAnimation;

  int _currentStep = 0;
  bool _isSaving = false;

  // Form data
  String _gender = ''; // 'male' | 'female' | 'other'
  String _interestedIn = 'female';
  String _relationshipIntent = 'serious';
  List<PhotoItem> _photos = [];
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final List<String> _selectedInterests = [];
  static const _allInterests = [
    '🎵 Music', '🎬 Movies', '📚 Books', '✈️ Travel', '🍕 Food',
    '🏋️ Fitness', '🎮 Gaming', '🐾 Pets', '🌿 Nature', '📸 Photography',
    '🎨 Art', '💃 Dancing', '☕ Coffee', '🧘 Yoga', '🏄 Surfing',
    '🍳 Cooking', '🎭 Theatre', '🎯 Sports', '🛍️ Fashion', '🌙 Astrology',
  ];

  static const _steps = ['Who are you?', 'Photo', 'About You', 'Interests', 'Location'];

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _progressAnimation = Tween<double>(begin: 0, end: 1 / _steps.length)
        .animate(CurvedAnimation(parent: _progressController, curve: Curves.easeInOut));
    _progressController.forward();

    // Pre-fill name and photo from Firebase Auth
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authStateChangesProvider).asData?.value;
      if (user != null) {
        if (user.displayName != null && user.displayName!.isNotEmpty) {
          _nameCtrl.text = user.displayName!;
        }
        if (user.photoURL != null && user.photoURL!.isNotEmpty && _photos.isEmpty) {
          setState(() {
            _photos = [
              PhotoItem(
                id: 'auth_avatar_${DateTime.now().millisecondsSinceEpoch}',
                url: user.photoURL,
              ),
            ];
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _progressController.dispose();
    _entryController.dispose();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _ageCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  void _nextStep() {
    // Step 0: Gender must be selected
    if (_currentStep == 0 && _gender.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('Please select who you are 💫'),
      );
      return;
    }
    // Step 1: Photo
    if (_currentStep == 1 && _photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('Please add at least 1 photo 📸'),
      );
      return;
    }
    // Step 2: About You
    if (_currentStep == 2) {
      if (_nameCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(_snack('Name is required'));
        return;
      }
      if (_bioCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(_snack('Add a little bio 🌟'));
        return;
      }
      final age = int.tryParse(_ageCtrl.text.trim());
      if (age == null || age < 18 || age > 99) {
        ScaffoldMessenger.of(context).showSnackBar(_snack('Enter a valid age (18+)'));
        return;
      }
    }
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      _progressAnimation = Tween<double>(
        begin: _currentStep / _steps.length,
        end: (_currentStep + 1) / _steps.length,
      ).animate(CurvedAnimation(parent: _progressController, curve: Curves.easeInOut));
      _progressController
        ..reset()
        ..forward();
    } else {
      _saveProfile();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      final user = ref.read(authStateChangesProvider).asData?.value;
      if (user == null) throw Exception('Not authenticated');

      // Upload photos (max 4)
      final List<String> finalUrls = [];
      final storage = FirebaseStorage.instance;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < _photos.length && i < 4; i++) {
        final item = _photos[i];
        if (item.bytes != null || item.file != null) {
          final storageRef = storage.ref('avatars/${user.uid}_photo_${timestamp}_$i.jpg');
          final bytes = item.bytes ?? (item.file != null ? await item.file!.readAsBytes() : null);
          if (bytes != null) {
            await storageRef.putData(
              bytes,
              SettableMetadata(contentType: 'image/jpeg'),
            );
            final downloadUrl = await storageRef.getDownloadURL();
            finalUrls.add(downloadUrl);
          }
        } else if (item.url != null && item.url!.isNotEmpty) {
          finalUrls.add(item.url!);
        }
      }

      final String? photoUrl = finalUrls.isNotEmpty ? finalUrls.first : null;

      // Extract existing phone number from auth or empty string
      final String phoneNumber = user.phoneNumber ?? '';

      // Build the public profile map (PII excluded)
      final data = <String, dynamic>{
        'uid': user.uid,
        'name': _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : (user.displayName ?? 'Anonymous'),
        'gender': _gender,
        'interestedIn': _interestedIn,
        'relationshipIntent': _relationshipIntent,
        'bio': _bioCtrl.text.trim(),
        'age': int.tryParse(_ageCtrl.text.trim()) ?? 21,
        'avatarUrl': photoUrl,
        'photoUrls': finalUrls,
        'photos': finalUrls,
        'location': _locationCtrl.text.trim().isNotEmpty
            ? _locationCtrl.text.trim()
            : 'Nearby',
        'interests': _selectedInterests,
        'isVerified': false,
        'isPhonePublic': false,
        'unlockedUserPhones': [],
        'unlockedVisitors': [],
        'phoneVisibilityVersion': 1,
        'coins': _gender == 'female' ? 50 : 20,
        'totalEarnedCoins': 0,
        'claimedMilestones': [],
        'isSubscribed': false,
        'subscriptionExpiry': null,
        'phoneUnlocksUsed': 0,
        'phoneUnlockQuota': 0,
        'lastLoginDate': null,
        'dailyLoginStreak': 0,
        'conversationRewardsToday': 0,
      };

      // 1. Write public profile document (PII excluded)
      await _db.collection('users').doc(user.uid).set(data, SetOptions(merge: true));
      try {
        await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
            .collection('users')
            .doc(user.uid)
            .set(data, SetOptions(merge: true));
      } catch (_) {}

      // 2. Write private profile document (owner-only PII)
      final privateData = <String, dynamic>{
        'email': user.email ?? '',
        'phoneNumber': phoneNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await _db.collection('users').doc(user.uid).collection('private').doc('profile').set(privateData, SetOptions(merge: true));
      try {
        await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
            .collection('users')
            .doc(user.uid)
            .collection('private')
            .doc('profile')
            .set(privateData, SetOptions(merge: true));
      } catch (_) {}

      if (mounted) context.go('/feed');
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          _snack('Something went wrong: $e', isError: true),
        );
      }
    }
  }

  SnackBar _snack(String msg, {bool isError = false}) {
    return SnackBar(
      content: Text(msg),
      backgroundColor: isError ? DesignTokens.error : AppTheme.primaryBlue,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: DesignTokens.obsidianBase,
      body: Stack(
        children: [
          // Background ambient gradient
          Positioned(
            top: -100,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primaryBlue.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header
                _buildHeader(isDark),

                // Progress bar
                _buildProgressBar(),

                // Page view
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildGenderStep(),
                      _buildPhotoStep(isDark, size),
                      _buildAboutStep(isDark),
                      _buildInterestsStep(isDark),
                      _buildLocationStep(isDark),
                    ],
                  ),
                ),

                // Bottom navigation
                _buildBottomNav(isDark),
              ],
            ),
          ),

          // Saving overlay
          if (_isSaving)
            Container(
              color: Colors.black.withValues(alpha: 0.75),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primaryPink),
                    const SizedBox(height: 16),
                    Text(
                      'Setting up your vibe...',
                      style: DesignTokens.titleMedium(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          if (_currentStep > 0)
            GestureDetector(
              onTap: _prevStep,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: DesignTokens.obsidianCard,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white),
              ),
            )
          else
            const SizedBox(width: 38),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Step ${_currentStep + 1} of ${_steps.length}',
                  style: DesignTokens.microBadge(color: DesignTokens.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  _steps[_currentStep],
                  style: DesignTokens.headingMedium(color: DesignTokens.textPrimary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(width: 38),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
        ),
        child: AnimatedBuilder(
          animation: _progressAnimation,
          builder: (context, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (_currentStep + 1) / _steps.length,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryPink, AppTheme.primaryBlue],
                ),
                borderRadius: BorderRadius.circular(99),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryPink.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Step 0: Gender ─────────────────────────────────────────────────────

  Widget _buildGenderStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 18),
          Text(
            'Who are you? 💫',
            style: DesignTokens.displayHero(color: DesignTokens.textPrimary).copyWith(fontSize: 26),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This helps us tailor your match feed and experience.',
            style: DesignTokens.bodyMedium(color: DesignTokens.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _genderCard(
            value: 'male',
            label: 'Man',
            emoji: '🙋‍♂️',
            description: 'Buy coins, unlock features\n& connect with people',
            accentColor: const Color(0xFF2563EB),
          ),
          const SizedBox(height: 14),
          _genderCard(
            value: 'female',
            label: 'Woman',
            emoji: '🙋‍♀️',
            description: 'Earn coins through conversations\n& redeem for gift cards',
            accentColor: const Color(0xFFFF3366),
          ),
          const SizedBox(height: 14),
          _genderCard(
            value: 'other',
            label: 'Other',
            emoji: '✨',
            description: 'Express yourself freely\non Situationship',
            accentColor: const Color(0xFFA855F7),
          ),
          if (_gender.isNotEmpty) ...[
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Who would you like to date? 💕',
                style: DesignTokens.titleMedium(color: DesignTokens.textPrimary),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildPreferenceChip('Women 🌸', 'female'),
                const SizedBox(width: 8),
                _buildPreferenceChip('Men ⚡', 'male'),
                const SizedBox(width: 8),
                _buildPreferenceChip('Everyone ✨', 'all'),
              ],
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'What are you looking for? 🎯',
                style: DesignTokens.titleMedium(color: DesignTokens.textPrimary),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildIntentChip('Serious 💍', 'serious'),
                _buildIntentChip('Casual 🥂', 'casual'),
                _buildIntentChip('Open to explore 🌊', 'open'),
                _buildIntentChip('New friends ☕', 'friendship'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreferenceChip(String label, String value) {
    final isSelected = _interestedIn == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _interestedIn = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryBlue.withValues(alpha: 0.2)
                : DesignTokens.obsidianCard,
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            border: Border.all(
              color: isSelected ? AppTheme.primaryBlue : Colors.white.withValues(alpha: 0.10),
              width: 1.2,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: DesignTokens.labelBold(
              color: isSelected ? Colors.white : DesignTokens.textSecondary,
            ).copyWith(fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildIntentChip(String label, String value) {
    final isSelected = _relationshipIntent == value;
    return GestureDetector(
      onTap: () => setState(() => _relationshipIntent = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryPink.withValues(alpha: 0.2)
              : DesignTokens.obsidianCard,
          borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
          border: Border.all(
            color: isSelected ? AppTheme.primaryPink : Colors.white.withValues(alpha: 0.10),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: DesignTokens.labelBold(
            color: isSelected ? Colors.white : DesignTokens.textSecondary,
          ).copyWith(fontSize: 12),
        ),
      ),
    );
  }

  Widget _genderCard({
    required String value,
    required String label,
    required String emoji,
    required String description,
    required Color accentColor,
  }) {
    final selected = _gender == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _gender = value;
          if (value == 'male') {
            _interestedIn = 'female';
          } else if (value == 'female') {
            _interestedIn = 'male';
          } else {
            _interestedIn = 'all';
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: 0.15)
              : DesignTokens.obsidianCard,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(
            color: selected ? accentColor : Colors.white.withValues(alpha: 0.08),
            width: selected ? 1.6 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ]
              : DesignTokens.cardShadow(),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: DesignTokens.titleMedium(color: Colors.white).copyWith(fontSize: 17),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: DesignTokens.bodyMedium(color: DesignTokens.textSecondary).copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? accentColor : DesignTokens.textMuted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 1: Photo ───────────────────────────────────────────────────────

  Widget _buildPhotoStep(bool isDark, Size size) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'Add your best photos ✨',
            style: DesignTokens.displayHero(color: DesignTokens.textPrimary).copyWith(fontSize: 26),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Upload up to 4 photos. Drag or tap arrows to pick your #1 main picture!',
            style: DesignTokens.bodyMedium(color: DesignTokens.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          MultiPhotoManager(
            photos: _photos,
            onPhotosChanged: (updated) {
              setState(() => _photos = updated);
            },
            isDark: isDark,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DesignTokens.obsidianCard,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Text('💡', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'The 1st photo is your main avatar. Up to 4 photos will be shown in your profile!',
                    style: DesignTokens.bodyMedium(color: DesignTokens.textSecondary).copyWith(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 2: About ───────────────────────────────────────────────────────

  Widget _buildAboutStep(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text(
              'Tell us about you 🌟',
              style: DesignTokens.displayHero(color: DesignTokens.textPrimary).copyWith(fontSize: 26),
            ),
            const SizedBox(height: 6),
            Text(
              'This is what people see on your profile card.',
              style: DesignTokens.bodyMedium(color: DesignTokens.textSecondary),
            ),
            const SizedBox(height: 28),
            _label('Your Name'),
            const SizedBox(height: 8),
            _glassField(
              controller: _nameCtrl,
              hint: 'e.g. Alex Chen',
              icon: Icons.person_rounded,
            ),
            const SizedBox(height: 18),
            _label('Your Age'),
            const SizedBox(height: 8),
            _glassField(
              controller: _ageCtrl,
              hint: 'e.g. 22',
              icon: Icons.cake_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 18),
            _label('Bio / Vibe ✨'),
            const SizedBox(height: 8),
            _glassField(
              controller: _bioCtrl,
              hint: 'A short description of who you are...',
              icon: Icons.auto_awesome_rounded,
              maxLines: 4,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 3: Interests ───────────────────────────────────────────────────

  Widget _buildInterestsStep(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            "What's your vibe? 🎯",
            style: DesignTokens.displayHero(color: DesignTokens.textPrimary).copyWith(fontSize: 26),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick at least 3 interests to find your match.',
            style: DesignTokens.bodyMedium(color: DesignTokens.textSecondary),
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _selectedInterests.length >= 3
                  ? DesignTokens.success.withValues(alpha: 0.15)
                  : DesignTokens.obsidianCard,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              border: Border.all(
                color: _selectedInterests.length >= 3
                    ? DesignTokens.success.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Text(
              _selectedInterests.isEmpty
                  ? 'None selected'
                  : '${_selectedInterests.length} selected ${_selectedInterests.length >= 3 ? "✅" : ""}',
              style: DesignTokens.labelBold(
                color: _selectedInterests.length >= 3 ? DesignTokens.success : DesignTokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _allInterests.map((interest) {
              final selected = _selectedInterests.contains(interest);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (selected) {
                      _selectedInterests.remove(interest);
                    } else {
                      _selectedInterests.add(interest);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primaryPink.withValues(alpha: 0.22)
                        : DesignTokens.obsidianCard,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                    border: Border.all(
                      color: selected
                          ? AppTheme.primaryPink
                          : Colors.white.withValues(alpha: 0.10),
                      width: selected ? 1.4 : 1.0,
                    ),
                    boxShadow: selected
                        ? [BoxShadow(color: AppTheme.primaryPink.withValues(alpha: 0.25), blurRadius: 10)]
                        : [],
                  ),
                  child: Text(
                    interest,
                    style: DesignTokens.labelBold(
                      color: selected ? Colors.white : DesignTokens.textSecondary,
                    ).copyWith(fontSize: 13),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─── Step 4: Location ────────────────────────────────────────────────────

  Widget _buildLocationStep(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            "Where are you? 📍",
            style: DesignTokens.displayHero(color: DesignTokens.textPrimary).copyWith(fontSize: 26),
          ),
          const SizedBox(height: 6),
          Text(
            'Optional — helps find people near you.',
            style: DesignTokens.bodyMedium(color: DesignTokens.textSecondary),
          ),
          const SizedBox(height: 28),
          _label('City / Location'),
          const SizedBox(height: 8),
          _glassField(
            controller: _locationCtrl,
            hint: 'e.g. Mumbai, India',
            icon: Icons.location_on_rounded,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: DesignTokens.obsidianCard,
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: DesignTokens.cardShadow(),
            ),
            child: Column(
              children: [
                const Text('🎉', style: TextStyle(fontSize: 38)),
                const SizedBox(height: 12),
                Text(
                  "You're all set!",
                  style: DesignTokens.headingMedium(color: DesignTokens.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "Hit Launch to enter the vibe and start making connections 🔥",
                  style: DesignTokens.bodyMedium(color: DesignTokens.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bottom Nav ──────────────────────────────────────────────────────────

  Widget _buildBottomNav(bool isDark) {
    final isLast = _currentStep == _steps.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          _nextStep();
        },
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryPink.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isLast ? '🚀 Launch into Situationship' : 'Continue',
                style: DesignTokens.labelBold(color: Colors.white).copyWith(fontSize: 15),
              ),
              if (!isLast) ...[
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  Widget _label(String text) {
    return Text(
      text,
      style: DesignTokens.labelBold(color: DesignTokens.textPrimary),
    );
  }

  Widget _glassField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: DesignTokens.obsidianInput,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        style: DesignTokens.bodyLarge(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: DesignTokens.bodyMedium(color: DesignTokens.textMuted),
          prefixIcon: Icon(icon, color: AppTheme.primaryPink, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
