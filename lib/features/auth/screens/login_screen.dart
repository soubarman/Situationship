import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/firebase_auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOut,
    );

    _slideAnim = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: Curves.easeOutCubic,
      ),
    );

    _animCtrl.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill in both email and password ✨');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _errorMessage = 'Enter a valid email address');
      return;
    }
    if (password.length < 4) {
      setState(() => _errorMessage = 'Password is too short');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).signInWithEmail(email, password);
      if (mounted) {
        context.go('/feed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().contains(']')
              ? e.toString().split(']').last.trim()
              : 'Failed to sign in. Please verify your credentials.';
        });
      }
    }
  }

  void _forgotPassword() {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: const Color(0xFF161524).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5277).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.lock_reset_rounded,
                            color: Color(0xFFFF5277),
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Reset Password',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Enter your account email address and we\'ll send you a recovery link.',
                    style: GoogleFonts.outfit(
                      color: Colors.white70,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0E18).withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 14.5),
                      cursorColor: const Color(0xFFFF5277),
                      decoration: InputDecoration(
                        hintText: 'Enter your email',
                        hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
                        prefixIcon: const Icon(Icons.mail_outline_rounded, color: Color(0xFFFF5277), size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.outfit(
                              color: Colors.white60,
                              fontWeight: FontWeight.w600,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF3366), Color(0xFFFF5252)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF3366).withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () async {
                                final email = emailCtrl.text.trim();
                                if (email.isEmpty || !email.contains('@')) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Please enter a valid email address.', style: GoogleFonts.outfit()),
                                      backgroundColor: AppTheme.error,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.pop(ctx);
                                try {
                                  await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('✨ Reset link sent! Check your inbox.', style: GoogleFonts.outfit()),
                                        backgroundColor: const Color(0xFF22C55E),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Failed: ${e.toString().split(']').last.trim()}', style: GoogleFonts.outfit()),
                                        backgroundColor: AppTheme.error,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Center(
                                child: Text(
                                  'Send Link',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0B12),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── 1. Subtle Atmospheric Backdrop Image at Top ──────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.46,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.38,
                child: kIsWeb
                    ? Image.asset(
                        'assets/images/welcome_bg.jpg',
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, -0.45),
                        errorBuilder: (_, __, ___) => Image.network(
                          'welcome_bg.jpg',
                          fit: BoxFit.cover,
                          alignment: const Alignment(0, -0.45),
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        ),
                      )
                    : Image.asset(
                        'assets/images/welcome_bg.jpg',
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, -0.45),
                        errorBuilder: (_, __, ___) => const SizedBox(),
                      ),
              ),
            ),
          ),

          // ── 2. Atmospheric Dark Vignette Gradient ─────────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      const Color(0xFF0C0B12).withValues(alpha: 0.8),
                      const Color(0xFF0C0B12),
                    ],
                    stops: const [0.0, 0.42, 0.85],
                  ),
                ),
              ),
            ),
          ),

          // ── 3. Subtle Romantic Ambient Glows (Rose & Plum — No Lime Green!) ──
          Positioned(
            top: -60,
            right: -60,
            child: IgnorePointer(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFF3366).withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: size.height * 0.28,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFA855F7).withValues(alpha: 0.11),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── 4. Hand-Drawn Doodle Accents (Matching Welcome Screen) ────────
          // Top-Right Floating Doodle Heart
          Positioned(
            top: size.height * 0.08,
            right: 28,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: 0.18,
                child: CustomPaint(
                  size: const Size(28, 28),
                  painter: _DoodleHeartPainter(
                    color: const Color(0xFFFF5E8A).withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ),
          // Top-Left Floating Sparkle/Burst Lines
          Positioned(
            top: size.height * 0.14,
            left: 24,
            child: IgnorePointer(
              child: CustomPaint(
                size: const Size(26, 30),
                painter: _DoodleBurstPainter(
                  color: const Color(0xFFFF5E8A).withValues(alpha: 0.75),
                ),
              ),
            ),
          ),

          // ── 5. Main Foreground Scrollable Content ─────────────────────────
          SafeArea(
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnim.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideAnim.value),
                    child: child,
                  ),
                );
              },
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const SizedBox(height: 10),
                                // ── Top Bar with Frosted Back Button ────────
                                _buildTopBar(context),

                                const SizedBox(height: 18),

                                // ── Situationship™ Branding + Welcome Text ───
                                _buildHeader(context),

                                const SizedBox(height: 26),

                                // ── Glassmorphic Form Card ───────────────────
                                _buildFormCard(context),

                                const SizedBox(height: 26),

                                // ── Social Login Options ────────────────────
                                _buildSocialLogin(),

                                const Spacer(),

                                const SizedBox(height: 20),

                                // ── Sign Up Footer Link ─────────────────────
                                _buildSignupLink(context),

                                const SizedBox(height: 14),

                                // ── Romantic Bottom Flourish ────────────────
                                CustomPaint(
                                  size: const Size(140, 14),
                                  painter: _BottomFlourishPainter(
                                    color: const Color(0xFFFF5E8A).withValues(alpha: 0.35),
                                  ),
                                ),

                                SizedBox(height: bottomPadding > 0 ? bottomPadding + 6 : 18),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Top Bar with Sleek Frosted Back Button ─────────────────────────────────
  Widget _buildTopBar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Circular Frosted Back Button
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/welcome');
                  }
                },
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1A26).withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 1.0,
                    ),
                  ),
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Subtle Right Pill: "vibes only"
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF1B1A26).withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFF5277),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFFF5277),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'vibes only',
                    style: GoogleFonts.outfit(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Branding Header: "Situationship™" + "Welcome back" ─────────────────────
  Widget _buildHeader(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // "Situationship™" Wordmark matching Welcome Screen
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Situa',
              style: GoogleFonts.outfit(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1.0,
                height: 1.0,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
            Text(
              't',
              style: GoogleFonts.outfit(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFFF5277),
                letterSpacing: -1.0,
                height: 1.0,
                shadows: [
                  Shadow(
                    color: const Color(0xFFFF5277).withValues(alpha: 0.4),
                    blurRadius: 14,
                  ),
                ],
              ),
            ),
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: -8,
                  child: CustomPaint(
                    size: const Size(12, 10),
                    painter: _DoodleHeartPainter(
                      color: const Color(0xFFFF6584),
                      strokeWidth: 1.8,
                    ),
                  ),
                ),
                Text(
                  'i',
                  style: GoogleFonts.outfit(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFFF5E7E),
                    letterSpacing: -1.0,
                    height: 1.0,
                  ),
                ),
              ],
            ),
            ShaderMask(
              shaderCallback: (bounds) {
                return const LinearGradient(
                  colors: [
                    Color(0xFFFF6584),
                    Color(0xFFFF7E7E),
                    Color(0xFFFFA573),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ).createShader(bounds);
              },
              child: Text(
                'onship',
                style: GoogleFonts.outfit(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.0,
                  height: 1.0,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 1, left: 3),
              child: Text(
                '™',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Welcome back headline
        Text(
          'Welcome back ✨',
          style: GoogleFonts.outfit(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.6,
          ),
        ),

        const SizedBox(height: 4),

        // Romantic cursive tagline
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Sign in to continue your vibe',
              style: GoogleFonts.caveat(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFFF6584),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Frosted Glass Form Card ────────────────────────────────────────────────
  Widget _buildFormCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF161524).withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.11),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Email input field
              _buildInputField(
                controller: _emailController,
                hintText: 'Email address',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 14),

              // Password input field
              _buildInputField(
                controller: _passwordController,
                hintText: 'Password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _obscurePassword ? Colors.white38 : const Color(0xFFFF5277),
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),

              // Error Message Banner
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3366).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFFF3366).withValues(alpha: 0.35),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFFF5277),
                        size: 17,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.outfit(
                            color: const Color(0xFFFF6584),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Forgot password button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _forgotPassword,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    'Forgot password?',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFFFF6584),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Primary "Sign In" Button (Matches Welcome Screen CTA)
              _buildSignInButton(context),
            ],
          ),
        ),
      ),
    );
  }

  // ── Elegant Dark Translucent Input Container ──────────────────────────────
  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0E18).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Center(
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: const Color(0xFFFF5277),
          decoration: InputDecoration(
            isDense: true,
            hintText: hintText,
            hintStyle: GoogleFonts.outfit(
              color: Colors.white38,
              fontSize: 14,
            ),
            prefixIcon: Icon(
              icon,
              color: const Color(0xFFFF5277),
              size: 20,
            ),
            suffixIcon: suffixIcon,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }

  // ── Signature Primary Action Button: "Sign In →" ──────────────────────────
  Widget _buildSignInButton(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(27),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF3366),
            Color(0xFFFF5252),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF3366).withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _login,
          borderRadius: BorderRadius.circular(27),
          splashColor: Colors.white.withValues(alpha: 0.2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.4,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 24),
                      Text(
                        'Sign In',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ── Social Logins (Apple & Google Frosted Pills) ───────────────────────────
  Widget _buildSocialLogin() {
    return Column(
      children: [
        // "or continue with" Divider
        Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.12),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'or continue with',
                style: GoogleFonts.outfit(
                  color: Colors.white38,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Apple & Google Pills
        Row(
          children: [
            // Apple Button
            Expanded(
              child: _SocialGlassButton(
                iconWidget: const Icon(
                  Icons.apple,
                  color: Colors.white,
                  size: 22,
                ),
                label: 'Apple',
                onTap: () async {
                  try {
                    await ref.read(authControllerProvider.notifier).signInWithApple();
                    if (mounted) context.go('/feed');
                  } catch (e) {
                    if (mounted) {
                      setState(() => _errorMessage = 'Apple Sign-In: $e');
                    }
                  }
                },
              ),
            ),

            const SizedBox(width: 14),

            // Google Button
            Expanded(
              child: _SocialGlassButton(
                iconWidget: const _GoogleLogoWidget(size: 19),
                label: 'Google',
                onTap: () async {
                  try {
                    await ref.read(authControllerProvider.notifier).signInWithGoogle();
                    if (mounted) context.go('/feed');
                  } catch (e) {
                    if (mounted) {
                      setState(() => _errorMessage = 'Google Sign-In failed: $e');
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Bottom Sign Up Switcher ────────────────────────────────────────────────
  Widget _buildSignupLink(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account? ",
          style: GoogleFonts.outfit(
            color: Colors.white54,
            fontSize: 14,
          ),
        ),
        GestureDetector(
          onTap: () => context.go('/login/signup'),
          child: Text(
            'Sign up',
            style: GoogleFonts.outfit(
              color: const Color(0xFFFF5277),
              fontWeight: FontWeight.w800,
              fontSize: 14,
              decoration: TextDecoration.underline,
              decorationColor: const Color(0xFFFF5277).withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Frosted Glass Social Button ──────────────────────────────────────────────
class _SocialGlassButton extends StatelessWidget {
  final Widget iconWidget;
  final String label;
  final VoidCallback onTap;

  const _SocialGlassButton({
    required this.iconWidget,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            splashColor: Colors.white.withValues(alpha: 0.12),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF161524).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  iconWidget,
                  const SizedBox(width: 9),
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Authentic Crisp Multi-Color Google "G" Logo ─────────────────────────────
class _GoogleLogoWidget extends StatelessWidget {
  final double size;
  const _GoogleLogoWidget({this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleGPainter(),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2;
    final center = Offset(r, r);
    final strokeWidth = size.width * 0.22;
    final rect = Rect.fromCircle(center: center, radius: r - strokeWidth / 2);

    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Red: Top arc (-2.3 to -0.85 rad)
    canvas.drawArc(rect, -2.4, 1.6, false, redPaint);
    // Yellow: Bottom-left arc (-0.8 to 0.8 rad)
    canvas.drawArc(rect, 2.3, 1.6, false, yellowPaint);
    // Green: Bottom arc (0.8 to 2.3 rad)
    canvas.drawArc(rect, 0.7, 1.6, false, greenPaint);
    // Blue: Right arc (-0.8 to 0.7 rad) + horizontal bar
    canvas.drawArc(rect, -0.8, 1.5, false, bluePaint);

    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    final barRect = Rect.fromLTWH(
      r - 1,
      r - strokeWidth / 2,
      r + 1,
      strokeWidth,
    );
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Hand-Drawn Doodle Painters (Identical to Welcome Screen) ────────────────
class _DoodleHeartPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _DoodleHeartPainter({required this.color, this.strokeWidth = 2.4});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final path = Path();
    path.moveTo(w * 0.5, h * 0.88);
    path.cubicTo(w * 0.1, h * 0.58, w * 0.02, h * 0.22, w * 0.28, h * 0.08);
    path.cubicTo(w * 0.45, -0.01, w * 0.5, h * 0.2, w * 0.5, h * 0.25);
    path.cubicTo(w * 0.5, h * 0.2, w * 0.55, -0.01, w * 0.72, h * 0.08);
    path.cubicTo(w * 0.98, h * 0.22, w * 0.9, h * 0.58, w * 0.5, h * 0.88);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DoodleBurstPainter extends CustomPainter {
  final Color color;

  _DoodleBurstPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top ray
    canvas.drawLine(
      const Offset(20, 2),
      const Offset(9, 9),
      paint,
    );
    // Middle ray
    canvas.drawLine(
      const Offset(25, 14),
      const Offset(12, 16),
      paint,
    );
    // Bottom ray
    canvas.drawLine(
      const Offset(21, 26),
      const Offset(10, 23),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BottomFlourishPainter extends CustomPainter {
  final Color color;

  _BottomFlourishPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final cy = h * 0.55;

    // Left curved stroke
    final leftPath = Path();
    leftPath.moveTo(0, cy + 3);
    leftPath.cubicTo(w * 0.18, cy - 5, w * 0.32, cy + 5, w * 0.44, cy);
    canvas.drawPath(leftPath, paint);

    // Right curved stroke
    final rightPath = Path();
    rightPath.moveTo(w * 0.56, cy);
    rightPath.cubicTo(w * 0.68, cy + 5, w * 0.82, cy - 5, w, cy + 3);
    canvas.drawPath(rightPath, paint);

    // Center mini heart
    final heartPath = Path();
    final hx = w * 0.5;
    final hy = cy - 4.0;
    heartPath.moveTo(hx, hy + 6.5);
    heartPath.cubicTo(hx - 4.5, hy + 2.0, hx - 6.5, hy - 3.5, hx - 3.0, hy - 5.5);
    heartPath.cubicTo(hx - 0.5, hy - 6.5, hx, hy - 3.0, hx, hy - 1.5);
    heartPath.cubicTo(hx, hy - 3.0, hx + 0.5, hy - 6.5, hx + 3.0, hy - 5.5);
    heartPath.cubicTo(hx + 6.5, hy - 3.5, hx + 4.5, hy + 2.0, hx, hy + 6.5);

    canvas.drawPath(heartPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
