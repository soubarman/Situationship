import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firebase_auth_provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/widgets/gradient_button.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _bioController = TextEditingController();
  final _locationController = TextEditingController();
  int _selectedAge = 21;
  bool _obscurePassword = true;
  bool _isLoading = false;
  int _step = 0;
  String? _errorMessage;
  XFile? _avatarFile;
  final ImagePicker _picker = ImagePicker();

  final List<String> _interests = [
    'Photography', 'Music', 'Art', 'Fashion', 'Travel',
    'Fitness', 'Gaming', 'Film', 'Books', 'Food',
    'Nature', 'Tech', 'Dance', 'Yoga', 'Coffee',
  ];
  final List<String> _selectedInterests = [];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool _validateStep() {
    if (_step == 0) {
      if (_nameController.text.trim().isEmpty) {
        setState(() => _errorMessage = 'Please enter your name');
        return false;
      }
      if (!_emailController.text.contains('@')) {
        setState(() => _errorMessage = 'Enter a valid email address');
        return false;
      }
      if (_passwordController.text.length < 6) {
        setState(() => _errorMessage = 'Password must be at least 6 characters');
        return false;
      }
    } else if (_step == 1) {
      if (_bioController.text.trim().isEmpty) {
        setState(() => _errorMessage = 'Tell us a bit about yourself ✨');
        return false;
      }
    } else if (_step == 2) {
      if (_selectedInterests.length < 3) {
        setState(() => _errorMessage = 'Pick at least 3 interests 🎯');
        return false;
      }
    } else if (_step == 3) {
      if (_avatarFile == null) {
        setState(() => _errorMessage = 'Please select a profile picture 📸');
        return false;
      }
    }
    setState(() => _errorMessage = null);
    return true;
  }

  void _nextStep() {
    if (!_validateStep()) return;
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _signup();
    }
  }

  void _signup() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      await ref.read(authControllerProvider.notifier).signUpWithEmail(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            age: _selectedAge,
            bio: _bioController.text.trim(),
            location: _locationController.text.trim().isNotEmpty
                ? _locationController.text.trim()
                : 'Earth 🌍',
            interests: List.from(_selectedInterests),
            avatarFile: _avatarFile,
          );
      if (mounted) {
        context.go('/feed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().contains(']') 
              ? e.toString().split(']').last.trim() 
              : 'Failed to create account.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.accentPurple.withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _buildTopBar(),
                  const SizedBox(height: 32),
                  _buildStepIndicator(),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: AppTheme.error, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, anim) => SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.3, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: _buildCurrentStep(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GradientButton(
                    text: _step == 3 ? 'Create Account 🎉' : 'Continue',
                    isLoading: _isLoading,
                    onPressed: _nextStep,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        IconButton(
          onPressed: () => _step == 0 ? context.pop() : setState(() { _step--; _errorMessage = null; }),
          icon: const Icon(Icons.arrow_back_ios_rounded),
          padding: EdgeInsets.zero,
        ),
        const Spacer(),
        TextButton(
          onPressed: () => context.go('/login'),
          child: Text(
            'Sign in',
            style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildStepIndicator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (index) {
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 4,
                margin: EdgeInsets.only(right: index < 3 ? 8 : 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: index <= _step ? AppTheme.primaryGradient : null,
                  color: index > _step ? AppTheme.textTertiary.withOpacity(0.2) : null,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        Text(
          _step == 0
              ? 'Create your account ✨'
              : _step == 1
                  ? 'About you 🌟'
                  : _step == 2 
                      ? 'Your interests 🎯'
                      : 'Final touch 📸',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _step == 0
              ? 'Step ${_step + 1} of 4 — Basic info'
              : _step == 1
                  ? 'Step ${_step + 1} of 4 — Tell us about yourself'
                  : _step == 2
                      ? 'Step ${_step + 1} of 4 — What are you into?'
                      : 'Step ${_step + 1} of 4 — Your profile picture',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return _buildStep0();
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      default:
        return _buildStep0();
    }
  }

  Widget _buildStep0() {
    return Column(
      key: const ValueKey(0),
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            hintText: 'Full name',
            prefixIcon: Icon(Icons.person_outline_rounded, color: AppTheme.primaryBlue, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'Email address',
            prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryBlue, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: 'Password (min. 6 chars)',
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.primaryBlue, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppTheme.textTertiary,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      key: const ValueKey(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Age', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Text(
                  '$_selectedAge',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
                ),
                const Spacer(),
                Column(
                  children: [
                    IconButton(
                      onPressed: () => setState(() { if (_selectedAge < 50) _selectedAge++; }),
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      onPressed: () => setState(() { if (_selectedAge > 18) _selectedAge--; }),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Bio', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 12),
          TextField(
            controller: _bioController,
            maxLines: 3,
            maxLength: 150,
            decoration: const InputDecoration(hintText: 'Share your vibe in a few words...'),
          ),
          const SizedBox(height: 16),
          const Text('Location', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(
              hintText: 'City, Country',
              prefixIcon: Icon(Icons.location_on_outlined, color: AppTheme.primaryBlue, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      key: const ValueKey(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick at least 3 interests',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _interests.map((interest) {
              final isSelected = _selectedInterests.contains(interest);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedInterests.remove(interest);
                    } else if (_selectedInterests.length < 6) {
                      _selectedInterests.add(interest);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isSelected ? AppTheme.primaryGradient : null,
                    color: isSelected ? null : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppTheme.primaryBlue.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    interest,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.textSecondary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text(
            '${_selectedInterests.length}/6 selected',
            style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return Column(
      key: const ValueKey(3),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () async {
            final XFile? image = await _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 70,
              maxWidth: 800,
            );
            if (image != null) {
              setState(() {
                _avatarFile = image;
                _errorMessage = null;
              });
            }
          },
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
              border: Border.all(
                color: _avatarFile != null ? AppTheme.primaryBlue : Colors.transparent,
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
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
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_rounded, size: 40, color: AppTheme.primaryBlue),
                        const SizedBox(height: 8),
                        Text(
                          'Upload Photo',
                          style: TextStyle(
                            color: AppTheme.primaryBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 48),
        Text(
          'Let others see your vibe! 💫',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'A clear photo helps you stand out in the community.',
          style: TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
