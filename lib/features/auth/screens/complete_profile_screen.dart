import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/firebase_auth_provider.dart';

// ─── Provider ────────────────────────────────────────────────────────────────

final _db = FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: 'default',
);

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
  XFile? _avatarFile;
  String? _avatarUrl;
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

  static const _steps = ['Photo', 'About You', 'Interests', 'Location'];

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _progressAnimation = Tween<double>(begin: 0, end: 1 / _steps.length)
        .animate(CurvedAnimation(parent: _progressController, curve: Curves.easeInOut));
    _progressController.forward();

    // Pre-fill name from Firebase Auth
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authStateChangesProvider).asData?.value;
      if (user != null && user.displayName != null) {
        _nameCtrl.text = user.displayName!;
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
    if (_currentStep == 0 && _avatarFile == null && _avatarUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('Please pick a profile photo 📸'),
      );
      return;
    }
    if (_currentStep == 1) {
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
        duration: const Duration(milliseconds: 400),
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
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
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
    setState(() => _isSaving = true);
    try {
      final user = ref.read(authStateChangesProvider).asData?.value;
      if (user == null) throw Exception('Not authenticated');

      // Upload avatar if a new file was chosen
      String? photoUrl = _avatarUrl;
      if (_avatarFile != null) {
        final storageRef = FirebaseStorage.instance.ref('avatars/${user.uid}.jpg');
        if (kIsWeb) {
          final bytes = await _avatarFile!.readAsBytes();
          await storageRef.putData(bytes);
        } else {
          await storageRef.putFile(File(_avatarFile!.path));
        }
        photoUrl = await storageRef.getDownloadURL();
      }

      // Build the profile map
      final data = <String, dynamic>{
        'id': user.uid,
        'name': _nameCtrl.text.trim(),
        'email': user.email ?? '',
        'bio': _bioCtrl.text.trim(),
        'age': int.parse(_ageCtrl.text.trim()),
        'avatarUrl': photoUrl,
        'location': _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        'interests': _selectedInterests.map((i) => i.substring(3)).toList(), // strip emoji prefix
        'isVerified': false,
        'isOnline': true,
        'photos': photoUrl != null ? [photoUrl] : [],
        'followers': [],
        'following': [],
        'likedBy': [],
        'matches': [],
        'postCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await _db.collection('users').doc(user.uid).set(data, SetOptions(merge: true));

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
      backgroundColor: isError ? AppTheme.error : AppTheme.primaryBlue,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFB8EDFF), Color(0xFFB8FFE8), Color(0xFFE8BBFF)],
                stops: [0.0, 0.5, 1.0],
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
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Setting up your vibe...', style: TextStyle(color: Colors.white, fontSize: 16)),
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
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          if (_currentStep > 0)
            GestureDetector(
              onTap: _prevStep,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              ),
            )
          else
            const SizedBox(width: 40),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Step ${_currentStep + 1} of ${_steps.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _steps[_currentStep],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(99),
        ),
        child: AnimatedBuilder(
          animation: _progressAnimation,
          builder: (context, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (_currentStep + 1) / _steps.length,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryBlue, AppTheme.accentPurple],
                ),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Step 1: Photo ───────────────────────────────────────────────────────

  Widget _buildPhotoStep(bool isDark, Size size) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Text(
            'Add your best photo ✨',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your photo is the first impression.\nMake it count! 🔥',
            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: _pickImage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _avatarFile != null
                    ? null
                    : const LinearGradient(
                        colors: [AppTheme.primaryBlue, AppTheme.accentPurple],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withOpacity(0.4),
                    blurRadius: 40,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: _avatarFile != null
                  ? ClipOval(
                      child: kIsWeb
                          ? Image.network(_avatarFile!.path, fit: BoxFit.cover)
                          : Image.file(File(_avatarFile!.path), fit: BoxFit.cover),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 48),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to choose',
                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                        ),
                      ],
                    ),
            ),
          ),
          if (_avatarFile != null) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Change photo'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryBlue,
                backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Text('💡', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Profiles with photos get 5× more connections',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
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
            const SizedBox(height: 16),
            const Text(
              'Tell us about you 🌟',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'This is what people see on your profile.',
              style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            _label('Your Name'),
            const SizedBox(height: 8),
            _glassField(
              controller: _nameCtrl,
              hint: 'e.g. Alex Chen',
              icon: Icons.person_rounded,
            ),
            const SizedBox(height: 20),
            _label('Your Age'),
            const SizedBox(height: 8),
            _glassField(
              controller: _ageCtrl,
              hint: 'e.g. 22',
              icon: Icons.cake_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 20),
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
          const SizedBox(height: 16),
          const Text(
            "What's your vibe? 🎯",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Pick at least 3 interests to find your match.',
            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _selectedInterests.length >= 3
                  ? AppTheme.primaryGreen.withOpacity(0.15)
                  : Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _selectedInterests.isEmpty
                  ? 'None selected'
                  : '${_selectedInterests.length} selected ${_selectedInterests.length >= 3 ? "✅" : ""}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _selectedInterests.length >= 3 ? AppTheme.primaryBlue : AppTheme.textSecondary,
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
                  setState(() {
                    if (selected) {
                      _selectedInterests.remove(interest);
                    } else {
                      _selectedInterests.add(interest);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.primaryBlue : Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                      color: selected ? AppTheme.primaryBlue : Colors.white,
                      width: 1.5,
                    ),
                    boxShadow: selected
                        ? [BoxShadow(color: AppTheme.primaryBlue.withOpacity(0.3), blurRadius: 12)]
                        : [],
                  ),
                  child: Text(
                    interest,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppTheme.textPrimary,
                    ),
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
          const SizedBox(height: 16),
          const Text(
            "Where are you? 📍",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Optional — helps find people near you.',
            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 32),
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
              color: Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
            ),
            child: Column(
              children: [
                const Text('🎉', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                const Text(
                  "You're all set!",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "Hit Launch to enter the vibe and start making connections 🔥",
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
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
        onTap: _nextStep,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryBlue, AppTheme.accentPurple],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryBlue.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isLast ? '🚀 Launch into Situationship' : 'Continue',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!isLast) ...[
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
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
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
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
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 14),
          prefixIcon: Icon(icon, color: AppTheme.primaryBlue, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
